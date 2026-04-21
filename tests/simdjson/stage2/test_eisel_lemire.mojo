from std.testing import assert_equal
from simdjson.stage2.eisel_lemire import Uint128, umul128


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


def main() raises:
    test_umul128_small()
    test_umul128_max_times_2()
    test_umul128_max_times_max()
    test_umul128_power_of_two()
    print("test_eisel_lemire: all passed")
