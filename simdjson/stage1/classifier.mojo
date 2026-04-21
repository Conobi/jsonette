from simdjson.stage1.simd_ops import SimdInput, movemask_epi8, shuffle_epi8


@fieldwise_init
struct CharacterBlock(Movable, Copyable):
    """Result of classifying a 64-byte chunk into whitespace and operator bitmasks."""

    var whitespace: UInt64
    var op: UInt64


def classify(input: SimdInput) -> CharacterBlock:
    """Classify 64 bytes into whitespace and structural operator bitmasks.

    Uses VPSHUFB shuffle-table approach for operators ({, }, [, ], :, ,)
    and eq() calls for whitespace (space, tab, LF, CR).
    """
    # --- Operators via shuffle tables ---
    # Low-nibble table: which bits are set for each low nibble value (0-15)
    # 0xA -> bit 0 (: = 0x3A)
    # 0xB -> bit 1 ({ = 0x7B, [ = 0x5B)
    # 0xC -> bit 2 (, = 0x2C)
    # 0xD -> bit 3 (} = 0x7D, ] = 0x5D)
    var low_table = SIMD[DType.uint8, 32](
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 4, 8, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 4, 8, 0, 0,
    )

    # High-nibble table: which bits are allowed for each high nibble value (0-15)
    # High 2 (, = 0x2C) -> bit 2
    # High 3 (: = 0x3A) -> bit 0
    # High 5 ([ = 0x5B, ] = 0x5D) -> bits 1, 3 = 0x0A
    # High 7 ({ = 0x7B, } = 0x7D) -> bits 1, 3 = 0x0A
    var high_table = SIMD[DType.uint8, 32](
        0, 0, 4, 1, 0, 0x0A, 0, 0x0A, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 4, 1, 0, 0x0A, 0, 0x0A, 0, 0, 0, 0, 0, 0, 0, 0,
    )

    var low_nibble_mask = SIMD[DType.uint8, 32](0x0F)

    # Process chunk 0
    var lo0 = input.chunks[0] & low_nibble_mask
    var hi0 = input.chunks[0] >> 4
    var low_res0 = shuffle_epi8(low_table, lo0)
    var high_res0 = shuffle_epi8(high_table, hi0)
    var op0 = low_res0 & high_res0
    # Convert nonzero -> 0xFF for movemask
    var op_mask0 = op0.ne(SIMD[DType.uint8, 32](0)).select(
        SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
    )

    # Process chunk 1
    var lo1 = input.chunks[1] & low_nibble_mask
    var hi1 = input.chunks[1] >> 4
    var low_res1 = shuffle_epi8(low_table, lo1)
    var high_res1 = shuffle_epi8(high_table, hi1)
    var op1 = low_res1 & high_res1
    var op_mask1 = op1.ne(SIMD[DType.uint8, 32](0)).select(
        SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
    )

    var op_lo = UInt64(movemask_epi8(op_mask0).cast[DType.uint64]()) & 0xFFFFFFFF
    var op_hi = UInt64(movemask_epi8(op_mask1).cast[DType.uint64]()) & 0xFFFFFFFF
    var op_combined = op_lo | (op_hi << 32)

    # --- Whitespace via eq() ---
    var ws_space = input.eq(UInt8(0x20))
    var ws_tab = input.eq(UInt8(0x09))
    var ws_lf = input.eq(UInt8(0x0A))
    var ws_cr = input.eq(UInt8(0x0D))
    var ws_combined = ws_space | ws_tab | ws_lf | ws_cr

    return CharacterBlock(whitespace=ws_combined, op=op_combined)
