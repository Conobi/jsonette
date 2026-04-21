from std.testing import assert_equal, assert_true
from std.memory import bitcast
from simdjson.stage2.numbers import parse_number, NumberResult


def test_parse_positive_int() raises:
    """Parse '123' as unsigned integer."""
    var s = String("123")
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    var result = parse_number(buf.unsafe_ptr(), len(buf))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64(123))
    assert_equal(result.bytes_consumed, 3)


def test_parse_zero() raises:
    """Parse '0' as unsigned integer."""
    var s = String("0")
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    var result = parse_number(buf.unsafe_ptr(), len(buf))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64(0))
    assert_equal(result.bytes_consumed, 1)


def test_parse_negative_int() raises:
    """Parse '-42' as signed integer."""
    var s = String("-42")
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    var result = parse_number(buf.unsafe_ptr(), len(buf))
    assert_equal(result.tag, UInt8(0x6C))  # 'l'
    var val = bitcast[DType.int64](SIMD[DType.uint64, 1](result.value))
    assert_equal(Int64(val), Int64(-42))
    assert_equal(result.bytes_consumed, 3)


def test_parse_int_with_terminator() raises:
    """Parse '42,' — stops at comma."""
    var s = String("42,")
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    var result = parse_number(buf.unsafe_ptr(), len(buf))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64(42))
    assert_equal(result.bytes_consumed, 2)


def test_parse_large_uint() raises:
    """Parse large unsigned integer near UInt64 max."""
    var s = String("18446744073709551615")  # UInt64.MAX
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    var result = parse_number(buf.unsafe_ptr(), len(buf))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64.MAX)


def test_parse_int64_min() raises:
    """Parse '-9223372036854775808' (INT64_MIN)."""
    var s = String("-9223372036854775808")
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    var result = parse_number(buf.unsafe_ptr(), len(buf))
    assert_equal(result.tag, UInt8(0x6C))  # 'l'
    # INT64_MIN in two's complement = 0x8000000000000000
    assert_equal(result.value, UInt64(1) << 63)
    var val = bitcast[DType.int64](SIMD[DType.uint64, 1](result.value))
    assert_equal(Int64(val), Int64.MIN)


def test_parse_float_3_14() raises:
    """Parse '3.14' — should use Eisel-Lemire for exact result."""
    var s = String("3.14")
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    var result = parse_number(buf.unsafe_ptr(), len(buf))
    assert_equal(result.tag, UInt8(0x64))
    var val = Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](result.value)))
    assert_equal(val, 3.14)


def test_parse_1e10() raises:
    """Parse '1e10' — scientific notation."""
    var s = String("1e10")
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    var result = parse_number(buf.unsafe_ptr(), len(buf))
    assert_equal(result.tag, UInt8(0x64))
    var val = Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](result.value)))
    assert_equal(val, 1e10)


def test_parse_negative_float() raises:
    """Parse '-0.5' — negative float."""
    var s = String("-0.5")
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    var result = parse_number(buf.unsafe_ptr(), len(buf))
    assert_equal(result.tag, UInt8(0x64))
    var val = Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](result.value)))
    assert_equal(val, -0.5)


def test_parse_1e308() raises:
    """Parse '1e308' — large exponent near Float64 max."""
    var s = String("1e308")
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    var result = parse_number(buf.unsafe_ptr(), len(buf))
    assert_equal(result.tag, UInt8(0x64))
    var val = Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](result.value)))
    assert_true(val > 0.0)


def test_parse_5e_minus_324() raises:
    """Parse '5e-324' — near Float64 minimum subnormal."""
    var s = String("5e-324")
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    var result = parse_number(buf.unsafe_ptr(), len(buf))
    assert_equal(result.tag, UInt8(0x64))
    # Should not crash — may use fallback


def main() raises:
    test_parse_positive_int()
    test_parse_zero()
    test_parse_negative_int()
    test_parse_int_with_terminator()
    test_parse_large_uint()
    test_parse_int64_min()
    test_parse_float_3_14()
    test_parse_1e10()
    test_parse_negative_float()
    test_parse_1e308()
    test_parse_5e_minus_324()
    print("test_numbers: all passed")
