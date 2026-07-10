"""Fused UTF-8 validation: simdjson's "lookup4" checker (Keiser & Lemire).

`Utf8Checker` validates the same 64-byte `SimdInput` chunks the indexer already
loads, so RFC 8259's UTF-8 requirement costs no extra pass. Three nibble-table
lookups classify each byte pair into an error bitset (truncation, overlong,
surrogate, out-of-range); a range check pins 3rd/4th continuation bytes; errors
accumulate and are tested once at end of input. Pure-ASCII chunks skip it all
on two sign-bit movemasks, the one (highly predictable) branch this adds to the
64-byte loop.
"""

from std.memory import pack_bits

from jsonette.stage1.simd_ops import SimdInput, shuffle_bytes


# Error bits (simdjson lookup4 encoding). A pair is invalid iff the three table
# lookups share a bit. TWO_CONTS (0x80) is not an error by itself: it marks a
# continuation-after-continuation, XORed later against the "must be a 3rd/4th
# continuation" expectation.
comptime _TOO_SHORT: UInt8 = 1 << 0   # lead not followed by a continuation
comptime _TOO_LONG: UInt8 = 1 << 1    # continuation after ASCII / complete seq
comptime _OVERLONG_3: UInt8 = 1 << 2  # E0 80..9F
comptime _TOO_LARGE: UInt8 = 1 << 3   # beyond U+10FFFF
comptime _SURROGATE: UInt8 = 1 << 4   # ED A0..BF
comptime _OVERLONG_2: UInt8 = 1 << 5  # C0/C1 lead
comptime _TOO_LARGE_1000: UInt8 = 1 << 6  # F5..FF lead
comptime _OVERLONG_4: UInt8 = 1 << 6  # F0 80..8F
comptime _TWO_CONTS: UInt8 = 1 << 7   # continuation after continuation
comptime _CARRY: UInt8 = _TOO_SHORT | _TOO_LONG | _TWO_CONTS

# Indexed by prev1's high nibble: 0_ ASCII, 10 continuation, 110x 2-byte lead,
# 1110 3-byte lead, 1111 4-byte lead.
comptime _BYTE_1_HIGH_TABLE = SIMD[DType.uint8, 16](
    _TOO_LONG, _TOO_LONG, _TOO_LONG, _TOO_LONG,
    _TOO_LONG, _TOO_LONG, _TOO_LONG, _TOO_LONG,
    _TWO_CONTS, _TWO_CONTS, _TWO_CONTS, _TWO_CONTS,
    _TOO_SHORT | _OVERLONG_2,
    _TOO_SHORT,
    _TOO_SHORT | _OVERLONG_3 | _SURROGATE,
    _TOO_SHORT | _TOO_LARGE | _TOO_LARGE_1000 | _OVERLONG_4,
)

# Indexed by prev1's low nibble; _CARRY classes hold regardless of it.
# Nibble 0 covers C0/E0/F0 overlongs, 4 covers F4, D covers ED surrogates.
comptime _BYTE_1_LOW_TABLE = SIMD[DType.uint8, 16](
    _CARRY | _OVERLONG_3 | _OVERLONG_2 | _OVERLONG_4,
    _CARRY | _OVERLONG_2,
    _CARRY,
    _CARRY,
    _CARRY | _TOO_LARGE,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000 | _SURROGATE,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
    _CARRY | _TOO_LARGE | _TOO_LARGE_1000,
)

# Indexed by the current byte's high nibble: ASCII/lead confirms TOO_SHORT,
# continuations 80..8F / 90..9F / A0..BF confirm the range-dependent classes.
comptime _BYTE_2_HIGH_TABLE = SIMD[DType.uint8, 16](
    _TOO_SHORT, _TOO_SHORT, _TOO_SHORT, _TOO_SHORT,
    _TOO_SHORT, _TOO_SHORT, _TOO_SHORT, _TOO_SHORT,
    _TOO_LONG | _OVERLONG_2 | _TWO_CONTS | _OVERLONG_3 | _TOO_LARGE_1000 | _OVERLONG_4,
    _TOO_LONG | _OVERLONG_2 | _TWO_CONTS | _OVERLONG_3 | _TOO_LARGE,
    _TOO_LONG | _OVERLONG_2 | _TWO_CONTS | _SURROGATE | _TOO_LARGE,
    _TOO_LONG | _OVERLONG_2 | _TWO_CONTS | _SURROGATE | _TOO_LARGE,
    _TOO_SHORT, _TOO_SHORT, _TOO_SHORT, _TOO_SHORT,
)


def _build_incomplete_max() -> SIMD[DType.uint8, 32]:
    """Per-lane maxima for `_is_incomplete`: a chunk ends mid-sequence iff its
    last byte is >= 0xC0, second-to-last >= 0xE0, or third-to-last >= 0xF0."""
    var v = SIMD[DType.uint8, 32](0xFF)
    v[29] = 0xEF
    v[30] = 0xDF
    v[31] = 0xBF
    return v


comptime _INCOMPLETE_MAX: SIMD[DType.uint8, 32] = _build_incomplete_max()


@always_inline("nodebug")
def _prev[n: Int](
    current: SIMD[DType.uint8, 32], prev: SIMD[DType.uint8, 32]
) -> SIMD[DType.uint8, 32]:
    """`current` shifted back by `n` bytes in stream order, pulling in `prev`'s
    tail (simdjson's `prev<N>`); one shuffle over the joined 64-byte vector."""
    return prev.join(current).slice[32, offset = 32 - n]()


@always_inline("nodebug")
def _check_special_cases(
    input: SIMD[DType.uint8, 32], prev1: SIMD[DType.uint8, 32]
) -> SIMD[DType.uint8, 32]:
    """Classify every (prev1, input) byte pair: AND of the three nibble-table
    lookups, nonzero iff some error class survives all three."""
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
    """XOR the "must be a 3rd/4th continuation" expectation (prev2 >= 0xE0 or
    prev3 >= 0xF0) against `sc`'s TWO_CONTS bit, flagging both a missing
    required continuation and one nothing asked for."""
    var prev2 = _prev[2](input, prev_input)
    var prev3 = _prev[3](input, prev_input)
    var must23 = prev2.ge(SIMD[DType.uint8, 32](0xE0)) | prev3.ge(
        SIMD[DType.uint8, 32](0xF0)
    )
    var must23_80 = must23.select(
        SIMD[DType.uint8, 32](0x80), SIMD[DType.uint8, 32](0)
    )
    return must23_80 ^ sc


@always_inline("nodebug")
def _is_incomplete(input: SIMD[DType.uint8, 32]) -> Bool:
    """True iff the vector ends mid-sequence (only the last 3 lanes can fire).

    Carried as a scalar, unlike simdjson's vector: equivalent for the final
    any-bits verdict, and one less vector register live in the chunk loop.
    """
    return pack_bits[DType.uint32](input.gt(_INCOMPLETE_MAX)) != 0


struct Utf8Checker(Movable):
    """Accumulating UTF-8 validator over the Stage 1 chunk stream.

    Feed chunks in order via `check_next_input`, call `check_eof` after the
    last one, then test `has_error`. The hot loop never branches on validity.
    """

    var error: SIMD[DType.uint8, 32]
    var prev_input_block: SIMD[DType.uint8, 32]
    var prev_incomplete: Bool
    var incomplete_error: Bool

    def __init__(out self):
        self.error = SIMD[DType.uint8, 32](0)
        self.prev_input_block = SIMD[DType.uint8, 32](0)
        self.prev_incomplete = False
        self.incomplete_error = False

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

        The ASCII fast path touches no vector state; the only thing a prior
        chunk can owe an ASCII chunk is an unfinished sequence, folded in via
        the scalar carry. After an ASCII chunk `prev_input_block` goes stale;
        that is safe (simdjson relies on the same invariant) because a
        sequence crossing INTO the ASCII chunk was already flagged by the
        carry, and fresh errors in later chunks are detected regardless.
        """
        var non_ascii = pack_bits[DType.uint32](
            input.chunks[0].cast[DType.int8]().lt(SIMD[DType.int8, 32](0))
        ) | pack_bits[DType.uint32](
            input.chunks[1].cast[DType.int8]().lt(SIMD[DType.int8, 32](0))
        )
        if non_ascii == 0:
            self.incomplete_error |= self.prev_incomplete
            return
        self._check_utf8_block(input.chunks[0], self.prev_input_block)
        self._check_utf8_block(input.chunks[1], input.chunks[0])
        self.prev_incomplete = _is_incomplete(input.chunks[1])
        self.prev_input_block = input.chunks[1]

    @always_inline("nodebug")
    def check_eof(mut self):
        """Flag an input ending mid-sequence. Only matters when the input ends
        exactly at a chunk boundary; otherwise the indexer's NUL padding (not a
        valid continuation) already made the pair checks catch it in-chunk."""
        self.incomplete_error |= self.prev_incomplete

    @always_inline("nodebug")
    def has_error(self) -> Bool:
        """True iff any chunk seen so far violated UTF-8 well-formedness."""
        return self.incomplete_error or self.error.reduce_or() != 0
