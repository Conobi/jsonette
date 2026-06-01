from std.bit import count_trailing_zeros

from simdjson.stage1.simd_ops import SimdInput
from simdjson.stage1.classifier import classify, CharacterBlock
from simdjson.stage1.string_mask import EscapeScanner, StringScanner
from simdjson._alloc_count import record_alloc


struct BitIndexer:
    """Converts a 64-bit bitmask into positions via direct pointer writes."""

    var positions: List[UInt32]
    var write_pos: Int

    def __init__(out self, capacity: Int = 0):
        if capacity > 0:
            self.positions = List[UInt32](unsafe_uninit_length=capacity)
        else:
            self.positions = List[UInt32]()
        self.write_pos = 0

    @always_inline("nodebug")
    def write(mut self, base_idx: UInt32, bits: UInt64):
        """Write positions of each set bit (relative to base_idx)."""
        var ptr = self.positions.unsafe_ptr()
        var b = bits
        while b != 0:
            ptr[self.write_pos] = base_idx + UInt32(count_trailing_zeros(b))
            self.write_pos += 1
            b = b & (b - 1)


def structural_index(
    padded_buf: List[UInt8], input_len: Int, mut positions: List[UInt32]
):
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

    # Capacity-based reuse: worst case is one structural per byte, so the writer
    # can index up to input_len - 1. Only grow (and count) when too small.
    if positions.capacity < input_len:
        record_alloc()  # genuine grow: the sole heap alloc on this path
        positions.reserve(input_len)
    # Length must cover the raw-pointer write phase (writer indexes [write_pos]).
    positions.resize(unsafe_uninit_length=input_len)

    var num_chunks = (input_len + 63) // 64

    var escape_scanner = EscapeScanner()
    var string_scanner = StringScanner()

    var prev_structurals: UInt64 = 0
    var prev_scalar_carry: UInt64 = 0
    var prev_base: UInt32 = 0

    var ptr = padded_buf.unsafe_ptr()
    var out_ptr = positions.unsafe_ptr()
    var write_pos = 0

    @parameter
    @always_inline("nodebug")
    def emit(base_idx: UInt32, bits: UInt64):
        """Write offsets of each set bit (relative to base_idx) into positions."""
        var b = bits
        while b != 0:
            out_ptr[write_pos] = base_idx + UInt32(count_trailing_zeros(b))
            write_pos += 1
            b = b & (b - 1)

    for chunk_idx in range(num_chunks):
        var base_idx = UInt32(chunk_idx * 64)
        var input = SimdInput.load(ptr + Int(base_idx))

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

    # In-place filter: compact valid positions (< input_len) to front
    var write = 0
    for i in range(write_pos):
        if Int(out_ptr[i]) < input_len:
            out_ptr[write] = out_ptr[i]
            write += 1
    # Shrink to actual structural count so Stage 2 sees the right len().
    positions.resize(write, UInt32(0))
