from jsonette.stage1.simd_ops import SimdInput, shuffle_bytes
from std.memory import pack_bits


# Low-nibble table: which bits are set for each low nibble value (0-15)
# 0xA -> bit 0 (: = 0x3A)
# 0xB -> bit 1 ({ = 0x7B, [ = 0x5B)
# 0xC -> bit 2 (, = 0x2C)
# 0xD -> bit 3 (} = 0x7D, ] = 0x5D)
comptime _LOW_NIBBLE_TABLE = SIMD[DType.uint8, 16](
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 4, 8, 0, 0,
)

# High-nibble table: which bits are allowed for each high nibble value (0-15)
# High 2 (, = 0x2C) -> bit 2
# High 3 (: = 0x3A) -> bit 0
# High 5 ([ = 0x5B, ] = 0x5D) -> bits 1, 3 = 0x0A
# High 7 ({ = 0x7B, } = 0x7D) -> bits 1, 3 = 0x0A
comptime _HIGH_NIBBLE_TABLE = SIMD[DType.uint8, 16](
    0, 0, 4, 1, 0, 0x0A, 0, 0x0A, 0, 0, 0, 0, 0, 0, 0, 0,
)


@fieldwise_init
struct CharacterBlock(Movable, Copyable):
    """Result of classifying a 64-byte chunk into whitespace and operator bitmasks."""

    var whitespace: UInt64
    var op: UInt64


@always_inline("nodebug")
def _op_mask(chunk: SIMD[DType.uint8, 32]) -> UInt32:
    """Return the 32-bit operator bitmask for one 32-byte chunk.

    Intersects the low-nibble and high-nibble shuffle tables: a byte is a
    structural operator ({, }, [, ], :, ,) only when its low nibble's candidate
    bitset and its high nibble's permitted bitset share a bit. Packs the
    nonzero-byte lanes into a bitmask. The byte shuffle is a full-width VPSHUFB
    on AVX2 and a portable NEON `tbl` elsewhere (see `shuffle_bytes`).
    """
    var lo = chunk & SIMD[DType.uint8, 32](0x0F)
    var hi = chunk >> 4
    var op = shuffle_bytes(_LOW_NIBBLE_TABLE, lo) & shuffle_bytes(
        _HIGH_NIBBLE_TABLE, hi
    )
    return pack_bits[DType.uint32](op.ne(SIMD[DType.uint8, 32](0)))


@always_inline("nodebug")
def classify(input: SimdInput) -> CharacterBlock:
    """Classify 64 bytes into whitespace and structural operator bitmasks.

    Operators ({, }, [, ], :, ,) use the simdjson low/high-nibble shuffle-table
    intersection (full-width VPSHUFB on AVX2, portable NEON TBL elsewhere);
    whitespace (space, tab, LF, CR) uses eq() compares.
    """
    var op_lo = _op_mask(input.chunks[0]).cast[DType.uint64]()
    var op_hi = _op_mask(input.chunks[1]).cast[DType.uint64]()
    var op_combined = op_lo | (op_hi << 32)

    # --- Whitespace via eq() ---
    var ws_space = input.eq(UInt8(0x20))
    var ws_tab = input.eq(UInt8(0x09))
    var ws_lf = input.eq(UInt8(0x0A))
    var ws_cr = input.eq(UInt8(0x0D))
    var ws_combined = ws_space | ws_tab | ws_lf | ws_cr

    return CharacterBlock(whitespace=ws_combined, op=op_combined)
