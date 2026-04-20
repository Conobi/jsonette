from std.sys.intrinsics import llvm_intrinsic
from std.bit import count_trailing_zeros


def movemask_epi8(v: SIMD[DType.uint8, 32]) -> Int32:
    """Extract high bit of each byte into a 32-bit integer mask (AVX2 PMOVMSKB)."""
    return llvm_intrinsic["llvm.x86.avx2.pmovmskb", Int32](v)


def shuffle_epi8(
    table: SIMD[DType.uint8, 32], indices: SIMD[DType.uint8, 32]
) -> SIMD[DType.uint8, 32]:
    """SIMD byte shuffle (AVX2 VPSHUFB). Each lane (128-bit) is independent.
    If high bit of index byte is set, output byte is 0.
    Only the low 4 bits of each index select from the 16-byte lane table."""
    return llvm_intrinsic["llvm.x86.avx2.pshuf.b", SIMD[DType.uint8, 32]](
        table, indices
    )


def prefix_xor(bitmask: UInt64) -> UInt64:
    """Compute prefix XOR: out[i] = bitmask[0] ^ bitmask[1] ^ ... ^ bitmask[i].
    Each 1-bit flips the polarity of all subsequent bits.
    Software fallback for CLMUL (6 XOR + 6 shift)."""
    var x = bitmask
    x ^= x << 1
    x ^= x << 2
    x ^= x << 4
    x ^= x << 8
    x ^= x << 16
    x ^= x << 32
    return x


@fieldwise_init
struct SimdInput(Movable, Copyable):
    """64 bytes loaded into 2 AVX2 registers. Abstracts the hardware SIMD width."""

    var chunks: InlineArray[SIMD[DType.uint8, 32], 2]

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

    def eq(self, target: UInt8) -> UInt64:
        """Return 64-bit mask: bit i set if byte i == target."""
        var splat = SIMD[DType.uint8, 32](target)
        var m0 = self.chunks[0].eq(splat).select(
            SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
        )
        var m1 = self.chunks[1].eq(splat).select(
            SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
        )
        var lo = UInt64(movemask_epi8(m0).cast[DType.uint64]())
        var hi = UInt64(movemask_epi8(m1).cast[DType.uint64]())
        return lo | (hi << 32)

    def lteq(self, target: UInt8) -> UInt64:
        """Return 64-bit mask: bit i set if byte i <= target (unsigned)."""
        var splat = SIMD[DType.uint8, 32](target)
        var m0 = self.chunks[0].le(splat).select(
            SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
        )
        var m1 = self.chunks[1].le(splat).select(
            SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
        )
        var lo = UInt64(movemask_epi8(m0).cast[DType.uint64]())
        var hi = UInt64(movemask_epi8(m1).cast[DType.uint64]())
        return lo | (hi << 32)
