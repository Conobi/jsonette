"""Eisel-Lemire float parsing: Uint128, umul128, and compute_float_64."""

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


def _leading_zeros(x: UInt64) -> Int:
    """Count leading zeros of a 64-bit integer."""
    if x == 0:
        return 64
    var n = 0
    var val = x
    if val & 0xFFFFFFFF00000000 == 0:
        n += 32
        val <<= 32
    if val & 0xFFFF000000000000 == 0:
        n += 16
        val <<= 16
    if val & 0xFF00000000000000 == 0:
        n += 8
        val <<= 8
    if val & 0xF000000000000000 == 0:
        n += 4
        val <<= 4
    if val & 0xC000000000000000 == 0:
        n += 2
        val <<= 2
    if val & 0x8000000000000000 == 0:
        n += 1
    return n


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
    var lz = _leading_zeros(mantissa)
    var w = mantissa << UInt64(lz)

    # Get 128-bit power of 5.
    var pow5 = get_pow5(exponent)

    # First multiply.
    var product = umul128(w, pow5.hi)

    # Ambiguity check: low 9 bits all ones means we need more precision.
    if (product.lo & 0x1FF) == 0x1FF:
        var second = umul128(w, pow5.lo)
        var lo_sum = product.lo + second.hi
        # Detect carry.
        if lo_sum < product.lo:
            product.hi += 1
        product.lo = lo_sum
        if (product.lo & 0x1FF) == 0x1FF and product.hi == UInt64.MAX:
            return FloatResult(value=UInt64(0), valid=False)

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
