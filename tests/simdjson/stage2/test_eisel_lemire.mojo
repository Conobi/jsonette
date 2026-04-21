from std.testing import assert_equal
from simdjson.stage2.eisel_lemire import Uint128, umul128
from simdjson.stage2.pow5_table import get_pow5, SMALLEST_POWER_OF_FIVE, LARGEST_POWER_OF_FIVE


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


def main() raises:
    test_umul128_small()
    test_umul128_max_times_2()
    test_umul128_max_times_max()
    test_umul128_power_of_two()
    test_pow5_table_bounds()
    test_pow5_known_values()
    print("test_eisel_lemire: all passed")
