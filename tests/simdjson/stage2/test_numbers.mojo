from std.testing import assert_equal
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


def main() raises:
    test_parse_positive_int()
    test_parse_zero()
    test_parse_negative_int()
    test_parse_int_with_terminator()
    test_parse_large_uint()
    print("test_numbers: all passed")
