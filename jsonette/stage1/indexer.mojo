"""Stage 1 indexer: the chunk loop that emits structural character positions.

`structural_index` is the Stage 1 entry point. It walks the padded input 64 bytes
at a time, and for each chunk combines the classifier's operator/whitespace masks
with the string-mask scanners to compute that chunk's structural bits: structural
operators outside strings, every real (non-escaped) quote, and pseudo-structural
scalar starts (the first byte of a number or `true`/`false`/`null`). Set bits are
scattered into the caller's reusable `positions` buffer by a branchless,
8-at-a-time `emit` (simdjson AVX2-kernel style) that trades a small over-write
tail for removing the per-structural mispredicted branch.

Output is deferred by one chunk so cross-chunk carries settle, and the spurious
tail produced by the final chunk's zero-padding is trimmed at the end. On exit,
`len(positions)` equals the true structural count so Stage 2 reads it directly.
The buffer is reused across calls and grows only on capacity, so a warm run
allocates nothing.

With `validate_utf8=True`, a `Utf8Checker` rides the same chunk loop, enforcing
RFC 8259's UTF-8 requirement without a second pass. The zero padding is valid
ASCII, so checking the padded chunks equals checking the exact input.
"""

from std.bit import count_trailing_zeros, pop_count

from jsonette.stage1.simd_ops import SimdInput
from jsonette.stage1.classifier import classify
from jsonette.stage1.string_mask import EscapeScanner, StringScanner
from jsonette.stage1.utf8 import Utf8Checker
from jsonette.error import format_parse_error, ErrorCode
from jsonette._alloc_count import record_alloc


def structural_index[
    validate_utf8: Bool = False
](padded_buf: List[UInt8], input_len: Int, mut positions: List[UInt32]) raises:
    """Stage 1 main entry point: fill `positions` with structural character offsets.

    Processes input in 64-byte chunks using SIMD classification, escape/string
    scanning, and pseudo-structural (scalar start) detection, writing each
    structural offset into the caller-provided `positions` buffer.

    The buffer is reused across calls: it is only (re)allocated when its
    capacity cannot hold the worst case of one structural per input byte. The
    decision is CAPACITY-based, not length-based, because this function leaves
    `positions` resized DOWN to the (small) structural count, so a warm buffer
    has a tiny length but a large capacity. On exit, `len(positions)` equals the
    number of structurals so Stage 2 can read it directly.

    Parameters:
        validate_utf8: When True, validate UTF-8 in the same chunk loop and
                       raise a formatted INVALID_UTF8 error on violation.

    Args:
        padded_buf: Input buffer already padded to at least
                    ceil(input_len/64)*64 + 64 zero bytes.
        input_len: Real (unpadded) length of the JSON input.
        positions: Caller-owned, reusable output buffer. Filled with structural
                   offsets and resized to the structural count.
    """
    if input_len == 0:
        positions.resize(0, UInt32(0))
        return

    # Capacity-based reuse: worst case is one structural per byte. The branchless
    # 8-at-a-time emit can over-write up to 7 entries past the true count, so the
    # buffer carries EMIT_SLACK extra slots; those over-writes are never read.
    comptime EMIT_SLACK = 8
    if positions.capacity < input_len + EMIT_SLACK:
        record_alloc()  # genuine grow: the sole heap alloc on this path
        positions.reserve(input_len + EMIT_SLACK)
    # Length must cover the raw-pointer write phase (writer indexes [write_pos]).
    positions.resize(unsafe_uninit_length=input_len + EMIT_SLACK)

    var num_chunks = (input_len + 63) // 64

    var escape_scanner = EscapeScanner()
    var string_scanner = StringScanner()
    var utf8_checker = Utf8Checker()

    var prev_structurals: UInt64 = 0
    var prev_scalar_carry: UInt64 = 0
    var prev_base: UInt32 = 0

    var ptr = padded_buf.unsafe_ptr()
    var out_ptr = positions.unsafe_ptr()
    var write_pos = 0

    @parameter
    @always_inline("nodebug")
    def emit(base_idx: UInt32, bits: UInt64):
        """Write offsets of each set bit (relative to base_idx) into positions.

        Branchless 8-at-a-time scatter (simdjson AVX2-kernel style): each
        iteration writes 8 indices unconditionally and advances a local cursor by
        8, but write_pos advances only by the true popcount. The spurious tail
        (<8 entries, where count_trailing_zeros(0)==64) is overwritten by the
        next emit or lands in the buffer's EMIT_SLACK and is never read. This
        removes the per-set-bit branch (one mispredict per structural char) that
        the stage-1 profile showed was ~2/3 of stage-1 cost on object input.
        """
        if bits == 0:
            return
        var cnt = Int(pop_count(bits))
        var b = bits
        var w = write_pos
        var done = 0
        while done < cnt:
            out_ptr[w + 0] = base_idx + UInt32(count_trailing_zeros(b))
            b = b & (b - 1)
            out_ptr[w + 1] = base_idx + UInt32(count_trailing_zeros(b))
            b = b & (b - 1)
            out_ptr[w + 2] = base_idx + UInt32(count_trailing_zeros(b))
            b = b & (b - 1)
            out_ptr[w + 3] = base_idx + UInt32(count_trailing_zeros(b))
            b = b & (b - 1)
            out_ptr[w + 4] = base_idx + UInt32(count_trailing_zeros(b))
            b = b & (b - 1)
            out_ptr[w + 5] = base_idx + UInt32(count_trailing_zeros(b))
            b = b & (b - 1)
            out_ptr[w + 6] = base_idx + UInt32(count_trailing_zeros(b))
            b = b & (b - 1)
            out_ptr[w + 7] = base_idx + UInt32(count_trailing_zeros(b))
            b = b & (b - 1)
            w += 8
            done += 8
        write_pos += cnt

    for chunk_idx in range(num_chunks):
        var base_idx = UInt32(chunk_idx * 64)
        var input = SimdInput.load(ptr + Int(base_idx))

        comptime if validate_utf8:
            utf8_checker.check_next_input(input)

        # Classify whitespace and operators
        var block = classify(input)

        # Escape and string scanning
        var backslash = input.eq(UInt8(0x5C))
        var all_quotes = input.eq(UInt8(0x22))
        var escaped = escape_scanner.next(backslash)
        var in_string = string_scanner.next(all_quotes, escaped)

        # Real quotes (non-escaped)
        var real_quotes = all_quotes & ~escaped

        # Structural operators outside strings, plus all real quotes
        var structural_ops = (block.op & ~in_string) | real_quotes

        # Pseudo-structural: scalar starts (first byte of numbers, true, false, null)
        # A scalar is anything not whitespace, not an operator, not a quote, and not in a string
        var scalar = ~(block.whitespace | block.op | real_quotes | in_string)
        # A scalar start is a scalar byte NOT preceded by another scalar
        var scalar_start = scalar & ~((scalar << 1) | prev_scalar_carry)

        # Combined structurals for this chunk
        var structurals = structural_ops | scalar_start

        # Deferred output: write PREVIOUS chunk's structurals
        if chunk_idx > 0:
            emit(prev_base, prev_structurals)

        # Save for next iteration
        prev_structurals = structurals
        prev_scalar_carry = (scalar >> 63) & 1
        prev_base = base_idx

    # Flush last chunk
    emit(prev_base, prev_structurals)

    # Positions are emitted in strictly ascending order (chunks in order, bits
    # low->high within each chunk), so any position >= input_len — the spurious
    # structurals from the final chunk's zero-padding — forms a contiguous tail.
    # Trim that tail instead of filtering all n positions (was an O(n) pass with
    # a branch per structural that filtered only ~1 entry).
    while write_pos > 0 and Int(out_ptr[write_pos - 1]) >= input_len:
        write_pos -= 1
    # Shrink to actual structural count so Stage 2 sees the right len().
    positions.resize(write_pos, UInt32(0))

    comptime if validate_utf8:
        # After the buffer bookkeeping, so `positions` stays consistent on raise.
        utf8_checker.check_eof()
        if utf8_checker.has_error():
            raise format_parse_error(ErrorCode.INVALID_UTF8.value, 0)
