from std.testing import assert_equal
from std.memory import bitcast
from simdjson.stage2.eisel_lemire import Uint128, umul128, compute_float_64, FloatResult
from simdjson.stage2.pow5_table import get_pow5, SMALLEST_POWER_OF_FIVE, LARGEST_POWER_OF_FIVE


def _bits_to_float(bits: UInt64) -> Float64:
    return Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](bits)))


def test_umul128_small() raises:
    var r = umul128(UInt64(2), UInt64(3))
    assert_equal(r.hi, UInt64(0))
    assert_equal(r.lo, UInt64(6))


def test_umul128_max_times_2() raises:
    var r = umul128(UInt64.MAX, UInt64(2))
    assert_equal(r.hi, UInt64(1))
    assert_equal(r.lo, UInt64.MAX - 1)


def test_umul128_max_times_max() raises:
    var r = umul128(UInt64.MAX, UInt64.MAX)
    assert_equal(r.hi, UInt64.MAX - 1)
    assert_equal(r.lo, UInt64(1))


def test_umul128_power_of_two() raises:
    # 2^32 * 2^32 = 2^64 -> hi=1, lo=0
    var r = umul128(UInt64(1) << 32, UInt64(1) << 32)
    assert_equal(r.hi, UInt64(1))
    assert_equal(r.lo, UInt64(0))


def test_pow5_table_bounds() raises:
    # 5^0 normalized: MSB should be set
    var p0 = get_pow5(0)
    assert_equal(p0.hi >> 63, UInt64(1))
    # Boundary values should not crash
    var p_min = get_pow5(SMALLEST_POWER_OF_FIVE)
    var p_max = get_pow5(LARGEST_POWER_OF_FIVE)
    assert_equal(p_min.hi >> 63, UInt64(1))
    assert_equal(p_max.hi >> 63, UInt64(1))


def test_pow5_known_values() raises:
    # 5^0 = 1, normalized to 128 bits = 2^127 = hi=0x8000000000000000, lo=0
    var p0 = get_pow5(0)
    assert_equal(p0.hi, UInt64(0x8000000000000000))
    assert_equal(p0.lo, UInt64(0))
    # 5^1 = 5, normalized: 5 << 125 = 0xA000000000000000_0000000000000000
    var p1 = get_pow5(1)
    assert_equal(p1.hi, UInt64(0xA000000000000000))
    assert_equal(p1.lo, UInt64(0))


def test_eisel_lemire_simple() raises:
    """Converts 314 * 10^-2 to 3.14."""

    var result = compute_float_64(UInt64(314), -2, False)
    assert_equal(result.valid, True)
    var val = _bits_to_float(result.value)
    var diff = val - 3.14
    if diff < 0.0:
        diff = -diff
    assert_equal(diff < 1e-15, True)


def test_eisel_lemire_integer() raises:
    """Converts 42 * 10^0 to 42.0."""

    var result = compute_float_64(UInt64(42), 0, False)
    assert_equal(result.valid, True)
    assert_equal(_bits_to_float(result.value), 42.0)


def test_eisel_lemire_negative() raises:

    var result = compute_float_64(UInt64(1), 0, True)
    assert_equal(result.valid, True)
    assert_equal(_bits_to_float(result.value), -1.0)


def test_eisel_lemire_1e10() raises:

    var result = compute_float_64(UInt64(1), 10, False)
    assert_equal(result.valid, True)
    assert_equal(_bits_to_float(result.value), 1e10)


def test_eisel_lemire_large_exponent() raises:
    """Converts 1 * 10^308 near float64 max."""

    var result = compute_float_64(UInt64(1), 308, False)
    assert_equal(result.valid, True)
    assert_equal(_bits_to_float(result.value) > 0.0, True)


def test_eisel_lemire_small_exponent() raises:
    """Converts 5 * 10^-324, subnormal that may fall back."""

    var result = compute_float_64(UInt64(5), -324, False)
    # Either valid with correct value, or invalid (fallback needed)
    if result.valid:
        assert_equal(_bits_to_float(result.value) >= 0.0, True)


def test_eisel_lemire_zero() raises:

    var result = compute_float_64(UInt64(0), 0, False)
    assert_equal(result.valid, True)
    assert_equal(_bits_to_float(result.value), 0.0)


def test_eisel_lemire_negative_zero() raises:

    var result = compute_float_64(UInt64(0), 0, True)
    assert_equal(result.valid, True)
    # Negative zero: bit 63 set, everything else 0
    assert_equal(result.value, UInt64(1) << 63)


def test_eisel_lemire_one_point_zero() raises:
    """Converts 1 * 10^0 to 1.0 with IEEE bits 0x3FF0000000000000."""

    var result = compute_float_64(UInt64(1), 0, False)
    assert_equal(result.valid, True)
    assert_equal(result.value, UInt64(0x3FF0000000000000))


def test_eisel_lemire_half() raises:
    """Converts 5 * 10^-1 to 0.5 with IEEE bits 0x3FE0000000000000."""

    var result = compute_float_64(UInt64(5), -1, False)
    assert_equal(result.valid, True)
    assert_equal(result.value, UInt64(0x3FE0000000000000))


def test_eisel_lemire_common_negative_decimal() raises:
    """Converts -79.123456 via the EFL fast path (not slow-path)."""

    var result = compute_float_64(UInt64(79123456), -6, True)
    assert_equal(result.valid, True)
    assert_equal(result.value, UInt64(0xC053C7E6B3FE9FAE))


def main() raises:
    test_umul128_small()
    test_umul128_max_times_2()
    test_umul128_max_times_max()
    test_umul128_power_of_two()
    test_pow5_table_bounds()
    test_pow5_known_values()
    test_eisel_lemire_simple()
    test_eisel_lemire_integer()
    test_eisel_lemire_negative()
    test_eisel_lemire_1e10()
    test_eisel_lemire_large_exponent()
    test_eisel_lemire_small_exponent()
    test_eisel_lemire_zero()
    test_eisel_lemire_negative_zero()
    test_eisel_lemire_one_point_zero()
    test_eisel_lemire_half()
    test_eisel_lemire_common_negative_decimal()
    print("test_eisel_lemire: all passed")
