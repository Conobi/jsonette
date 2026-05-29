from std.testing import assert_equal, assert_true
from std.memory import bitcast
from simdjson.stage2.numbers import _parse_number, NumberResult


def _nul_padded(s: String) -> List[UInt8]:
    """Build a buffer holding s's bytes + >=8 NUL padding (satisfies the
    _parse_number over-read precondition)."""
    var buf = List[UInt8](unsafe_uninit_length=0)
    for b in s.as_bytes():
        buf.append(b)
    for _ in range(16):
        buf.append(UInt8(0))
    return buf^


def test_parse_positive_int() raises:
    """Parse '123' as unsigned integer."""

    var s = String("123")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64(123))
    assert_equal(result.bytes_consumed, 3)


def test_parse_zero() raises:
    """Parse '0' as unsigned integer."""

    var s = String("0")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64(0))
    assert_equal(result.bytes_consumed, 1)


def test_parse_negative_int() raises:
    """Parse '-42' as signed integer."""

    var s = String("-42")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x6C))  # 'l'
    var val = bitcast[DType.int64](SIMD[DType.uint64, 1](result.value))
    assert_equal(Int64(val), Int64(-42))
    assert_equal(result.bytes_consumed, 3)


def test_parse_int_with_terminator() raises:
    """Parse '42,' — stops at comma."""

    var s = String("42,")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64(42))
    assert_equal(result.bytes_consumed, 2)


def test_parse_large_uint() raises:
    """Parse large unsigned integer near UInt64 max."""

    var s = String("18446744073709551615")  # UInt64.MAX
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64.MAX)


def test_parse_int64_min() raises:
    """Parse '-9223372036854775808' (INT64_MIN)."""

    var s = String("-9223372036854775808")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x6C))  # 'l'
    # INT64_MIN in two's complement = 0x8000000000000000
    assert_equal(result.value, UInt64(1) << 63)
    var val = bitcast[DType.int64](SIMD[DType.uint64, 1](result.value))
    assert_equal(Int64(val), Int64.MIN)


def test_parse_float_3_14() raises:
    """Parse '3.14' — should use Eisel-Lemire for exact result."""

    var s = String("3.14")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x64))
    var val = Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](result.value)))
    assert_equal(val, 3.14)


def test_parse_1e10() raises:
    """Parse '1e10' — scientific notation."""

    var s = String("1e10")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x64))
    var val = Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](result.value)))
    assert_equal(val, 1e10)


def test_parse_negative_float() raises:
    """Parse '-0.5' — negative float."""

    var s = String("-0.5")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x64))
    var val = Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](result.value)))
    assert_equal(val, -0.5)


def test_parse_1e308() raises:
    """Parse '1e308' — large exponent near Float64 max."""

    var s = String("1e308")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x64))
    var val = Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](result.value)))
    assert_true(val > 0.0)


def test_parse_8_digit_int() raises:
    """Parse '12345678' — exactly 8 digits, one SWAR batch."""

    var s = String("12345678")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64(12345678))
    assert_equal(result.bytes_consumed, 8)


def test_parse_16_digit_int() raises:
    """Parse '1234567890123456' — 16 digits, two SWAR batches."""

    var s = String("1234567890123456")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64(1234567890123456))
    assert_equal(result.bytes_consumed, 16)


def test_parse_19_digit_int() raises:
    """Parse '9999999999999999999' — 19 digits, max for UInt64 without overflow."""

    var s = String("9999999999999999999")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64(9999999999999999999))
    assert_equal(result.bytes_consumed, 19)


def test_parse_9_digit_int() raises:
    """Parse '123456789' — 8 SWAR + 1 scalar digit."""

    var s = String("123456789")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x75))  # 'u'
    assert_equal(result.value, UInt64(123456789))
    assert_equal(result.bytes_consumed, 9)


def test_parse_float_many_decimals() raises:
    """Parse '3.14159265358979' — float with 14 decimal digits."""

    var s = String("3.14159265358979")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x64))  # 'd'
    var val = Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](result.value)))
    assert_equal(val, 3.14159265358979)
    assert_equal(result.bytes_consumed, 16)


def test_parse_negative_8_digit() raises:
    """Parse '-12345678' — negative 8-digit number."""

    var s = String("-12345678")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, UInt8(0x6C))  # 'l'
    var val = bitcast[DType.int64](SIMD[DType.uint64, 1](result.value))
    assert_equal(Int64(val), Int64(-12345678))
    assert_equal(result.bytes_consumed, 9)


def test_parse_5e_minus_324() raises:
    """Parse '5e-324' — near Float64 minimum subnormal."""

    var s = String("5e-324")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
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
    test_parse_8_digit_int()
    test_parse_16_digit_int()
    test_parse_19_digit_int()
    test_parse_9_digit_int()
    test_parse_float_many_decimals()
    test_parse_negative_8_digit()
    print("test_numbers: all passed")
