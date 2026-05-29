"""Eisel-Lemire float parsing: Uint128, umul128, and compute_float_64."""

from std.bit import count_leading_zeros
from simdjson.stage2.pow5_table import get_pow5, SMALLEST_POWER_OF_FIVE, LARGEST_POWER_OF_FIVE


@fieldwise_init
struct Uint128(Movable, Copyable):
    """128-bit unsigned integer as two 64-bit halves."""

    var hi: UInt64
    var lo: UInt64


@fieldwise_init
struct FloatResult(Movable, Copyable):
    """Result of Eisel-Lemire. valid=False means fallback needed."""

    var value: UInt64  # IEEE 754 bits
    var valid: Bool


@always_inline("nodebug")
def umul128(a: UInt64, b: UInt64) -> Uint128:
    """64x64 -> 128 unsigned multiply using native UInt128."""
    var product = UInt128(a) * UInt128(b)
    return Uint128(hi=UInt64(product >> 64), lo=UInt64(product & 0xFFFFFFFFFFFFFFFF))


def compute_float_64(mantissa: UInt64, exponent: Int, negative: Bool) -> FloatResult:
    """Convert mantissa * 10^exponent to IEEE 754 double via Eisel-Lemire."""
    # Zero mantissa.
    if mantissa == 0:
        var bits = UInt64(1) << 63 if negative else UInt64(0)
        return FloatResult(value=bits, valid=True)

    # Range check.
    if exponent < SMALLEST_POWER_OF_FIVE or exponent > LARGEST_POWER_OF_FIVE:
        return FloatResult(value=UInt64(0), valid=False)

    # Normalize: shift mantissa so bit 63 is set.
    var lz = Int(count_leading_zeros(SIMD[DType.uint64, 1](mantissa))[0])
    var w = mantissa << UInt64(lz)

    # Get 128-bit power of 5.
    var pow5 = get_pow5(exponent)

    # First multiply.
    var product = umul128(w, pow5.hi)

    # Precision guard (fast_float compute_product_approximation): when the top
    # 9 bits of the high word are all ones, the single 64x64 product may be too
    # imprecise to round correctly, so fold in the second 128-bit power-of-five
    # word. The mask is on the HIGH word (0xFFFF...FFFF >> 55 == 0x1FF).
    if (product.hi & 0x1FF) == 0x1FF:
        var second = umul128(w, pow5.lo)
        product.lo += second.hi
        # Carry out of the low word into the high word.
        if second.hi > product.lo:
            product.hi += 1

    # Extract mantissa from upper 64 bits.
    var upper = product.hi
    var upperbit = Int(upper >> 63)

    # Shift to get 54-bit value (will round to 53).
    var ieee_m = upper >> UInt64(upperbit + 9)
    lz += Int(1 ^ upperbit)

    # Compute IEEE exponent.
    # floor(log2(10^e)) approximated by simdjson formula.
    var ieee_e = Int(((152170 + 65536) * exponent) >> 16) + 1024 + 63 - Int(lz)

    # Overflow -> infinity.
    if ieee_e >= 2047:
        return FloatResult(value=UInt64(0), valid=False)

    # Subnormal -> fallback.
    if ieee_e <= 0:
        return FloatResult(value=UInt64(0), valid=False)

    # Round-to-nearest-ties-to-even correction (fast_float compute_float):
    # usually we round up, but a value falling exactly halfway between two
    # representable floats must round to even. This can only happen for small
    # |exponent| where 5^q fits in a single 64-bit word. Detect the exact-tie
    # case and clear the low bit so the +1 below does not round it up.
    var shift = UInt64(upperbit + 9)
    if (
        product.lo <= 1
        and exponent >= -4
        and exponent <= 23
        and (ieee_m & 3) == 1
        and (ieee_m << shift) == upper
    ):
        ieee_m &= ~UInt64(1)

    # Round to even.
    ieee_m += ieee_m & 1
    ieee_m >>= 1

    # Mantissa overflow from rounding.
    if ieee_m >= (UInt64(1) << 53):
        ieee_m = UInt64(1) << 52
        ieee_e += 1
        if ieee_e >= 2047:
            return FloatResult(value=UInt64(0), valid=False)

    # Remove implicit 1 bit.
    ieee_m &= ~(UInt64(1) << 52)

    # Assemble IEEE 754 bits.
    var bits = ieee_m | (UInt64(ieee_e) << 52)
    if negative:
        bits |= UInt64(1) << 63

    return FloatResult(value=bits, valid=True)
