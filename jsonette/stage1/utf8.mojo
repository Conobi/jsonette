"""Stage 1 fused UTF-8 validation: the simdjson "lookup4" range checker.

`Utf8Checker` validates UTF-8 well-formedness over the same 64-byte `SimdInput`
chunks the indexer already loads, so RFC 8259's UTF-8 requirement costs no extra
pass over the input. The algorithm is a faithful port of simdjson's lookup4
(Keiser & Lemire, "Validating UTF-8 In Less Than One Instruction Per Byte"):

  * Three 16-entry nibble tables classify every byte PAIR (`prev1`, `input`)
    into an error bitset covering too-short/too-long sequences, overlongs,
    surrogates, and out-of-range code points (`_check_special_cases`).
  * A separate range check verifies that 3rd/4th continuation bytes appear
    exactly where a 3-byte or 4-byte lead demands them
    (`_check_multibyte_lengths`).
  * Errors accumulate branchlessly into a 32-byte vector; callers test it once
    at end of input (`has_error`).

Chunks that are pure ASCII (the common case in real-world JSON) skip all of the
above via a single movemask test. That test is the one branch this adds to the
64-byte loop; it is taken with near-perfect prediction on mostly-ASCII input,
which is why simdjson's kernels carry the same branch.

Cross-chunk state (the last 32 bytes of the previous chunk, and whether it ended
mid-sequence) is threaded through the struct, mirroring the escape/string
scanners. `check_eof` folds the final "ended mid-sequence" carry into the error;
with the indexer's zero-padded tail a truncated sequence inside the last chunk
is caught by the pair checks directly (NUL is not a continuation byte), so the
eof carry only matters when the input ends exactly at a chunk boundary.
"""

from std.memory import pack_bits

from jsonette.stage1.simd_ops import SimdInput, shuffle_bytes


# Error bits assigned by the nibble tables below (simdjson lookup4 encoding).
# A byte pair is invalid iff the three table lookups share a bit. TWO_CONTS
# (0x80) is special: it marks a continuation byte following a continuation
# byte, which is only VALID when a 3/4-byte lead two or three bytes back
# demands it; `_check_multibyte_lengths` XORs that expectation against it.
comptime _TOO_SHORT: UInt8 = 1 << 0   # lead byte not followed by a continuation
comptime _TOO_LONG: UInt8 = 1 << 1    # continuation after ASCII / complete sequence
comptime _OVERLONG_3: UInt8 = 1 << 2  # E0 followed by 80..9F (overlong 3-byte)
comptime _TOO_LARGE: UInt8 = 1 << 3   # F4 90.. and above (beyond U+10FFFF)
comptime _SURROGATE: UInt8 = 1 << 4   # ED A0..BF (UTF-16 surrogate half)
comptime _OVERLONG_2: UInt8 = 1 << 5  # C0/C1 lead (overlong 2-byte)
comptime _TOO_LARGE_1000: UInt8 = 1 << 6  # F5..FF lead with 80.. continuation
comptime _OVERLONG_4: UInt8 = 1 << 6  # F0 followed by 80..8F (overlong 4-byte)
comptime _TWO_CONTS: UInt8 = 1 << 7   # continuation following a continuation
comptime _CARRY: UInt8 = _TOO_SHORT | _TOO_LONG | _TWO_CONTS

# Indexed by the HIGH nibble of the previous byte (`prev1`): which error
# classes this byte-1 value can participate in.
comptime _BYTE_1_HIGH_TABLE = SIMD[DType.uint8, 16](
    # 0_______: ASCII in byte 1. Only error: a continuation follows it.
    _TOO_LONG, _TOO_LONG, _TOO_LONG, _TOO_LONG,
    _TOO_LONG, _TOO_LONG, _TOO_LONG, _TOO_LONG,
    # 10______: byte 1 is itself a continuation.
    _TWO_CONTS, _TWO_CONTS, _TWO_CONTS, _TWO_CONTS,
    # 1100____ / 1101____: 2-byte lead (C0/C1 overlong caught via low nibble).
    _TOO_SHORT | _OVERLONG_2,
    _TOO_SHORT,
    # 1110____: 3-byte lead (E0 overlong, ED surrogate via low nibble).
    _TOO_SHORT | _OVERLONG_3 | _SURROGATE,
    # 1111____: 4-byte lead (F0 overlong, F4+ too large via low nibble).
    _TOO_SHORT | _TOO_LARGE | _TOO_LARGE_1000 | _OVERLONG_4,
)

# Indexed by the LOW nibble of the previous byte (`prev1`): which of byte 1's
# candidate error classes its low nibble permits. _CARRY classes do not depend
# on the low nibble, so every entry includes them.
comptime _BYTE_1_LOW_TABLE = SIMD[DType.uint8, 16](
    # ____0000: C0 (overlong 2), E0 (overlong 3), F0 (overlong 4).
    _CARRY | _OVERLONG_3 | _OVERLONG_2 | _OVERLONG_4,
    # ____0001: C1 (overlong 2).
    _CARRY | _OVERLONG_2,
    # ____001_
    _CARRY,
    _CARRY,
    # ____0100: F4 (too large above U+10FFFF).
    _CARRY | _TOO_LARGE,
    # ____0101 and up: F5..FF leads are always too large.
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    # ____1101: ED (surrogate range).
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000 | _SURROGATE,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
)

# Indexed by the HIGH nibble of the CURRENT byte (byte 2 of the pair): which
# error classes the current byte confirms.
comptime _BYTE_2_HIGH_TABLE = SIMD[DType.uint8, 16](
    # 0_______: ASCII in byte 2 confirms a lead was cut short.
    _TOO_SHORT, _TOO_SHORT, _TOO_SHORT, _TOO_SHORT,
    _TOO_SHORT, _TOO_SHORT, _TOO_SHORT, _TOO_SHORT,
    # 1000____: continuation 80..8F.
    _TOO_LONG | _OVERLONG_2 | _TWO_CONTS | _OVERLONG_3 | _TOO_LARGE_1000 | _OVERLONG_4,
    # 1001____: continuation 90..9F.
    _TOO_LONG | _OVERLONG_2 | _TWO_CONTS | _OVERLONG_3 | _TOO_LARGE,
    # 101_____: continuation A0..BF.
    _TOO_LONG | _OVERLONG_2 | _TWO_CONTS | _SURROGATE | _TOO_LARGE,
    _TOO_LONG | _OVERLONG_2 | _TWO_CONTS | _SURROGATE | _TOO_LARGE,
    # 11______: another lead byte confirms a lead was cut short.
    _TOO_SHORT, _TOO_SHORT, _TOO_SHORT, _TOO_SHORT,
)


def _build_incomplete_max() -> SIMD[DType.uint8, 32]:
    """Build the per-lane maxima for `_is_incomplete`.

    A chunk ends mid-sequence iff its last byte is any lead (>= 0xC0), its
    second-to-last is a 3/4-byte lead (>= 0xE0), or its third-to-last is a
    4-byte lead (>= 0xF0). All other lanes get 0xFF so they can never exceed
    the maximum.
    """
    var v = SIMD[DType.uint8, 32](0xFF)
    v[29] = 0xEF  # third-to-last: incomplete iff >= 0xF0
    v[30] = 0xDF  # second-to-last: incomplete iff >= 0xE0
    v[31] = 0xBF  # last: incomplete iff >= 0xC0
    return v


comptime _INCOMPLETE_MAX: SIMD[DType.uint8, 32] = _build_incomplete_max()


@always_inline("nodebug")
def _prev[n: Int](
    current: SIMD[DType.uint8, 32], prev: SIMD[DType.uint8, 32]
) -> SIMD[DType.uint8, 32]:
    """Return `current` shifted back by `n` bytes, pulling in `prev`'s tail.

    result[i] holds the byte `n` positions before current[i] in stream order
    (so result[0..n-1] come from the end of `prev`). One shuffle over the
    joined 64-byte vector; the simdjson `prev<N>` primitive.
    """
    return prev.join(current).slice[32, offset = 32 - n]()


@always_inline("nodebug")
def _check_special_cases(
    input: SIMD[DType.uint8, 32], prev1: SIMD[DType.uint8, 32]
) -> SIMD[DType.uint8, 32]:
    """Classify every (prev1, input) byte pair into an error bitset.

    Three nibble-table lookups (byte 1 high/low nibble, byte 2 high nibble)
    are ANDed together: a pair is invalid iff some error class survives all
    three. The 0x80 bit (TWO_CONTS) is not an error by itself; the caller
    XORs it against the "must be a 3rd/4th continuation" expectation.
    """
    var byte_1_high = shuffle_bytes(_BYTE_1_HIGH_TABLE, prev1 >> 4)
    var byte_1_low = shuffle_bytes(
        _BYTE_1_LOW_TABLE, prev1 & SIMD[DType.uint8, 32](0x0F)
    )
    var byte_2_high = shuffle_bytes(_BYTE_2_HIGH_TABLE, input >> 4)
    return byte_1_high & byte_1_low & byte_2_high


@always_inline("nodebug")
def _check_multibyte_lengths(
    input: SIMD[DType.uint8, 32],
    prev_input: SIMD[DType.uint8, 32],
    sc: SIMD[DType.uint8, 32],
) -> SIMD[DType.uint8, 32]:
    """Fold the 3rd/4th-continuation-byte requirement into the pair errors.

    A byte two positions after a 3/4-byte lead, or three positions after a
    4-byte lead, MUST be a continuation-of-continuation (the 0x80 TWO_CONTS
    bit in `sc`). XOR flags both violations: a required continuation that is
    missing, and a continuation-of-continuation nothing asked for.
    """
    var prev2 = _prev[2](input, prev_input)
    var prev3 = _prev[3](input, prev_input)
    # 3-byte leads are >= 0xE0, 4-byte leads are >= 0xF0.
    var must23 = prev2.ge(SIMD[DType.uint8, 32](0xE0)) | prev3.ge(
        SIMD[DType.uint8, 32](0xF0)
    )
    var must23_80 = must23.select(
        SIMD[DType.uint8, 32](0x80), SIMD[DType.uint8, 32](0)
    )
    return must23_80 ^ sc


@always_inline("nodebug")
def _is_incomplete(input: SIMD[DType.uint8, 32]) -> SIMD[DType.uint8, 32]:
    """Return nonzero lanes iff the vector ends mid-UTF-8-sequence.

    Only the last three lanes can fire (see `_build_incomplete_max`). The
    result is carried into the next chunk; if that chunk is pure ASCII (or
    the input ends), the carry itself becomes the error.
    """
    return input.gt(_INCOMPLETE_MAX).select(
        SIMD[DType.uint8, 32](0x80), SIMD[DType.uint8, 32](0)
    )


struct Utf8Checker(Movable):
    """Accumulating UTF-8 validator over the Stage 1 chunk stream.

    Feed every 64-byte chunk in order via `check_next_input`, call `check_eof`
    after the last one, then test `has_error`. Errors accumulate in a vector,
    so the hot loop never branches on validity; pure-ASCII chunks short-circuit
    past the table checks on a single movemask test.
    """

    var error: SIMD[DType.uint8, 32]
    var prev_input_block: SIMD[DType.uint8, 32]
    var prev_incomplete: SIMD[DType.uint8, 32]

    def __init__(out self):
        self.error = SIMD[DType.uint8, 32](0)
        self.prev_input_block = SIMD[DType.uint8, 32](0)
        self.prev_incomplete = SIMD[DType.uint8, 32](0)

    @always_inline("nodebug")
    def _check_utf8_block(
        mut self,
        input: SIMD[DType.uint8, 32],
        prev_input: SIMD[DType.uint8, 32],
    ):
        """Accumulate pair and continuation-position errors for one 32-byte block."""
        var prev1 = _prev[1](input, prev_input)
        var sc = _check_special_cases(input, prev1)
        self.error |= _check_multibyte_lengths(input, prev_input, sc)

    @always_inline("nodebug")
    def check_next_input(mut self, input: SimdInput):
        """Validate one 64-byte chunk, threading state from the previous one.

        Pure-ASCII chunks (no byte >= 0x80) skip the table checks entirely; the
        only thing a preceding chunk can owe them is an unfinished multibyte
        sequence, which `prev_incomplete` folds into the error. Non-ASCII
        chunks run the full pair checks on both 32-byte halves.

        When the previous chunk was ASCII, `prev_input_block` is stale (it
        still holds the last non-ASCII chunk). That is safe, simdjson relies
        on the same invariant: a stale tail can only mask a sequence that
        crossed INTO the ASCII chunk, and `prev_incomplete` already flagged
        that; any fresh error inside this chunk is detected regardless.
        """
        var non_ascii = pack_bits[DType.uint32](
            (input.chunks[0] | input.chunks[1]).ge(SIMD[DType.uint8, 32](0x80))
        )
        if non_ascii == 0:
            self.error |= self.prev_incomplete
            return
        self._check_utf8_block(input.chunks[0], self.prev_input_block)
        self._check_utf8_block(input.chunks[1], input.chunks[0])
        self.prev_incomplete = _is_incomplete(input.chunks[1])
        self.prev_input_block = input.chunks[1]

    @always_inline("nodebug")
    def check_eof(mut self):
        """Flag an input that ends in the middle of a multibyte sequence.

        Only reachable when the final chunk is fully occupied by real input
        (input length a multiple of 64); otherwise the indexer's NUL padding
        terminates the sequence inside the chunk and the pair checks catch it.
        """
        self.error |= self.prev_incomplete

    @always_inline("nodebug")
    def has_error(self) -> Bool:
        """Return True iff any chunk seen so far violated UTF-8 well-formedness."""
        return self.error.reduce_or() != 0
