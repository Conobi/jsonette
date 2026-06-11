from std.sys.intrinsics import llvm_intrinsic


@always_inline("nodebug")
def movemask_epi8(v: SIMD[DType.uint8, 32]) -> Int32:
    """Extract high bit of each byte into a 32-bit integer mask (AVX2 PMOVMSKB)."""
    return llvm_intrinsic["llvm.x86.avx2.pmovmskb", Int32](v)


@always_inline("nodebug")
def shuffle_epi8(
    table: SIMD[DType.uint8, 32], indices: SIMD[DType.uint8, 32]
) -> SIMD[DType.uint8, 32]:
    """SIMD byte shuffle (AVX2 VPSHUFB). Each lane (128-bit) is independent.
    If high bit of index byte is set, output byte is 0.
    Only the low 4 bits of each index select from the 16-byte lane table."""
    return llvm_intrinsic["llvm.x86.avx2.pshuf.b", SIMD[DType.uint8, 32]](
        table, indices
    )


@always_inline("nodebug")
def prefix_xor(bitmask: UInt64) -> UInt64:
    """Compute prefix XOR via carry-less multiply (PCLMULQDQ).
    Each 1-bit flips the polarity of all subsequent bits.
    Equivalent to: out[i] = bitmask[0] ^ bitmask[1] ^ ... ^ bitmask[i].
    """
    # CLMUL: multiplying by all-ones in GF(2) = prefix XOR
    # Software fallback (non-x86):
    #   x ^= x << 1; x ^= x << 2; x ^= x << 4;
    #   x ^= x << 8; x ^= x << 16; x ^= x << 32; return x
    var input = SIMD[DType.uint64, 2](bitmask, 0)
    var multiplier = SIMD[DType.uint64, 2](0xFFFFFFFFFFFFFFFF, 0)
    var result = llvm_intrinsic[
        "llvm.x86.pclmulqdq",
        SIMD[DType.uint64, 2],
        has_side_effect=False,
    ](input, multiplier, Int8(0))
    return result[0]


@fieldwise_init
struct SimdInput(Movable, Copyable):
    """64 bytes loaded into 2 AVX2 registers. Abstracts the hardware SIMD width."""

    var chunks: InlineArray[SIMD[DType.uint8, 32], 2]

    @always_inline("nodebug")
    @staticmethod
    def load(ptr: UnsafePointer[UInt8, _]) -> SimdInput:
        """Load 64 bytes from ptr (unaligned)."""
        var result = SimdInput(
            chunks=InlineArray[SIMD[DType.uint8, 32], 2](
                fill=SIMD[DType.uint8, 32](0)
            )
        )
        result.chunks[0] = ptr.load[width=32]()
        result.chunks[1] = (ptr + 32).load[width=32]()
        return result^

    @always_inline("nodebug")
    def eq(self, target: UInt8) -> UInt64:
        """Return 64-bit mask: bit i set if byte i == target."""
        var splat = SIMD[DType.uint8, 32](target)
        var m0 = self.chunks[0].eq(splat).select(
            SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
        )
        var m1 = self.chunks[1].eq(splat).select(
            SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
        )
        var lo = UInt64(movemask_epi8(m0).cast[DType.uint64]()) & 0xFFFFFFFF
        var hi = UInt64(movemask_epi8(m1).cast[DType.uint64]()) & 0xFFFFFFFF
        return lo | (hi << 32)

    @always_inline("nodebug")
    def lteq(self, target: UInt8) -> UInt64:
        """Return 64-bit mask: bit i set if byte i <= target (unsigned)."""
        var splat = SIMD[DType.uint8, 32](target)
        var m0 = self.chunks[0].le(splat).select(
            SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
        )
        var m1 = self.chunks[1].le(splat).select(
            SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
        )
        var lo = UInt64(movemask_epi8(m0).cast[DType.uint64]()) & 0xFFFFFFFF
        var hi = UInt64(movemask_epi8(m1).cast[DType.uint64]()) & 0xFFFFFFFF
        return lo | (hi << 32)
