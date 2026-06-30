"""Stage 1 SIMD primitives: the ISA-portable building blocks for the indexer.

This module isolates the few hardware-width SIMD operations the rest of Stage 1
builds on, each with a fast x86 path and a portable fallback that is verified
bit-identical:

  * `SimdInput` wraps the 64-byte logical chunk (two 32-byte registers),
    abstracting the hardware SIMD width, and exposes `load`, `eq`, and `lteq`
    that produce 64-bit per-byte masks.
  * `shuffle_bytes` is a full-width 16-entry byte table lookup (AVX2 VPSHUFB, or
    two portable lane shuffles), used by the classifier's nibble tables.
  * `prefix_xor` is the inclusive XOR-scan of a 64-bit mask (AVX2 PCLMUL by
    all-ones, or a Hillis-Steele doubling scan), used to propagate in-string
    state across a quote mask.

Keeping these here means the indexer/classifier/string-mask code reads as
straight-line bit logic with no `comptime if` ISA branching inline.
"""

from std.sys.intrinsics import llvm_intrinsic
from std.sys.info import CompilationTarget
from std.memory import pack_bits


@always_inline("nodebug")
def shuffle_bytes(
    table: SIMD[DType.uint8, 16], indices: SIMD[DType.uint8, 32]
) -> SIMD[DType.uint8, 32]:
    """Full-width byte table lookup: r[i] = table[indices[i]] over 32 bytes.

    `table` is the 16-byte lookup table; `indices` are 32 per-byte selectors that
    must be in 0..15 (the classifier feeds nibbles, so this always holds).

    On AVX2 this is a single `ymm` VPSHUFB. VPSHUFB indexes within each 128-bit
    lane independently, so the 16-byte table is replicated into both lanes; the
    replication folds away at compile time since the table is constant. On every
    other target it falls back to two portable 16-byte `SIMD._dynamic_shuffle`
    lookups (NEON `tbl`), one per lane, then joins them. Both paths are
    bit-identical here because the indices never set the high bit that would make
    VPSHUFB (but not `_dynamic_shuffle`) zero the output.
    """
    comptime if CompilationTarget.has_avx2():
        return llvm_intrinsic[
            "llvm.x86.avx2.pshuf.b", SIMD[DType.uint8, 32]
        ](table.join(table), indices)

    return table._dynamic_shuffle(indices.slice[16, offset=0]()).join(
        table._dynamic_shuffle(indices.slice[16, offset=16]())
    )


@always_inline("nodebug")
def prefix_xor(bitmask: UInt64) -> UInt64:
    """Compute the prefix XOR (inclusive XOR-scan) of a 64-bit mask.

    Returns out where out[i] = bitmask[0] ^ bitmask[1] ^ ... ^ bitmask[i]; each
    1-bit flips the polarity of all subsequent bits, which propagates in-string
    state across a 64-bit quote mask.

    On x86 (AVX2) this is a single PCLMULQDQ, since multiplying by all-ones in
    GF(2) is exactly a prefix XOR. On every other target it falls back to the
    portable Hillis-Steele doubling scan (six shift-XOR steps), which is
    verified bit-identical to the CLMUL result.
    """
    comptime if CompilationTarget.has_avx2():
        # CLMUL: multiplying by all-ones in GF(2) = prefix XOR.
        var input = SIMD[DType.uint64, 2](bitmask, 0)
        var multiplier = SIMD[DType.uint64, 2](0xFFFFFFFFFFFFFFFF, 0)
        var result = llvm_intrinsic[
            "llvm.x86.pclmulqdq",
            SIMD[DType.uint64, 2],
            has_side_effect=False,
        ](input, multiplier, Int8(0))
        return result[0]

    # Portable fallback (non-AVX2 targets, e.g. ARM): doubling XOR-scan.
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
        var lo = pack_bits[DType.uint32](self.chunks[0].eq(splat)).cast[
            DType.uint64
        ]()
        var hi = pack_bits[DType.uint32](self.chunks[1].eq(splat)).cast[
            DType.uint64
        ]()
        return lo | (hi << 32)

    @always_inline("nodebug")
    def lteq(self, target: UInt8) -> UInt64:
        """Return 64-bit mask: bit i set if byte i <= target (unsigned)."""
        var splat = SIMD[DType.uint8, 32](target)
        var lo = pack_bits[DType.uint32](self.chunks[0].le(splat)).cast[
            DType.uint64
        ]()
        var hi = pack_bits[DType.uint32](self.chunks[1].le(splat)).cast[
            DType.uint64
        ]()
        return lo | (hi << 32)
