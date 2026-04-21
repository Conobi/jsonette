from std.bit import count_trailing_zeros

from simdjson.stage1.simd_ops import SimdInput
from simdjson.stage1.classifier import classify, CharacterBlock
from simdjson.stage1.string_mask import EscapeScanner, StringScanner


struct BitIndexer:
    """Converts a 64-bit bitmask into a list of absolute byte positions."""

    var positions: List[UInt32]

    def __init__(out self):
        self.positions = List[UInt32]()

    def write(mut self, base_idx: UInt32, bits: UInt64):
        """Append positions of each set bit (relative to base_idx)."""
        var b = bits
        while b != 0:
            self.positions.append(base_idx + UInt32(count_trailing_zeros(b)))
            b = b & (b - 1)


def structural_index(padded_buf: List[UInt8], input_len: Int) -> List[UInt32]:
    """Stage 1 main entry point: produce a list of structural character positions.

    Processes input in 64-byte chunks using SIMD classification, escape/string
    scanning, and pseudo-structural (scalar start) detection.

    Args:
        padded_buf: Input buffer already padded to at least
                    ceil(input_len/64)*64 + 64 zero bytes.
        input_len: Real (unpadded) length of the JSON input.
    """
    if input_len == 0:
        return List[UInt32]()

    var num_chunks = (input_len + 63) // 64

    var escape_scanner = EscapeScanner()
    var string_scanner = StringScanner()
    var indexer = BitIndexer()

    var prev_structurals: UInt64 = 0
    var prev_scalar_carry: UInt64 = 0
    var prev_base: UInt32 = 0

    var ptr = padded_buf.unsafe_ptr()

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
            indexer.write(prev_base, prev_structurals)

        # Save for next iteration
        prev_structurals = structurals
        prev_scalar_carry = (scalar >> 63) & 1
        prev_base = base_idx

    # Flush last chunk
    indexer.write(prev_base, prev_structurals)

    # Filter positions beyond input length
    var result = List[UInt32]()
    for i in range(len(indexer.positions)):
        if Int(indexer.positions[i]) < input_len:
            result.append(indexer.positions[i])

    return result^
