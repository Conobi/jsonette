from std.testing import assert_equal, assert_true
from std.memory import bitcast
from simdjson.stage2.numbers import _parse_number, NumberResult
from simdjson.tape import TAG_UINT64, TAG_INT64, TAG_FLOAT64
from simdjson.error import ParseError


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
    # Smallest positive subnormal double: IEEE-754 bits 0x0...01.
    assert_equal(result.value, UInt64(0x0000000000000001))


# --- Task 9: maximal-prefix contract (trailing junk is the validator's job) ---


def test_maximal_prefix_double_dot_value() raises:
    """'1.2.3' consumes only '1.2'; trailing '.3' is left to the validator."""

    var s = String("1.2.3")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.bytes_consumed, 3)


def test_maximal_prefix_dot_dot() raises:
    """'1..2' consumes only '1'; the second '.' has no fractional digit."""

    var s = String("1..2")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.bytes_consumed, 1)


def test_maximal_prefix_double_exponent() raises:
    """'1e1e1' consumes only '1e1'; trailing 'e1' is left to the validator."""

    var s = String("1e1e1")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.bytes_consumed, 3)


def test_maximal_prefix_trailing_alpha() raises:
    """'123abc' consumes only '123'."""

    var s = String("123abc")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.bytes_consumed, 3)


# --- Task 9: integer / sign edge cases ---


def test_negative_zero_integer() raises:
    """'-0' is uint64 0 (two's-complement -0 == 0; no information lost)."""

    var s = String("-0")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, TAG_UINT64)
    assert_equal(result.value, UInt64(0))


def test_negative_zero_float() raises:
    """'-0.0' is float64 -0.0 (sign bit set): oracle 0x8000000000000000."""

    var s = String("-0.0")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, TAG_FLOAT64)
    assert_equal(result.value, UInt64(0x8000000000000000))


def test_two_pow_64_routes_to_float() raises:
    """'18446744073709551616' (2^64) overflows uint64 -> correctly-rounded float64."""

    var s = String("18446744073709551616")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, TAG_FLOAT64)
    assert_equal(result.value, UInt64(0x43F0000000000000))


def test_uint64_max_stays_integer() raises:
    """'18446744073709551615' (2^64-1) is uint64 UInt64.MAX, not float."""

    var s = String("18446744073709551615")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, TAG_UINT64)
    assert_equal(result.value, UInt64.MAX)


# --- Task 9: malformed numbers must raise NUMBER_ERROR ---


def test_leading_plus_raises() raises:
    """'+1' is not in the RFC 8259 number grammar."""

    var s = String("+1")
    var buf = _nul_padded(s)
    var raised = False
    try:
        _ = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    except e:
        raised = True
    assert_true(raised, "'+1' must raise NUMBER_ERROR")


def test_trailing_dot_raises() raises:
    """'1.' has a dot but no fractional digit before the terminator."""

    var s = String("1.")
    var buf = _nul_padded(s)
    var raised = False
    try:
        _ = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    except e:
        raised = True
    assert_true(raised, "'1.' must raise NUMBER_ERROR")


def test_bare_exponent_raises() raises:
    """'1e' has no exponent digit."""

    var s = String("1e")
    var buf = _nul_padded(s)
    var raised = False
    try:
        _ = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    except e:
        raised = True
    assert_true(raised, "'1e' must raise NUMBER_ERROR")


def test_exponent_sign_only_raises() raises:
    """'1e+' has an exponent sign but no exponent digit."""

    var s = String("1e+")
    var buf = _nul_padded(s)
    var raised = False
    try:
        _ = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    except e:
        raised = True
    assert_true(raised, "'1e+' must raise NUMBER_ERROR")


# --- Task 9: valid exponent signs / leading-zero fraction must NOT raise ---


def test_exponent_plus_sign() raises:
    """'1e+5' is a valid float: oracle 0x40F86A0000000000."""

    var s = String("1e+5")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, TAG_FLOAT64)
    assert_equal(result.value, UInt64(0x40F86A0000000000))


def test_exponent_minus_sign() raises:
    """'1e-5' is a valid float: oracle 0x3EE4F8B588E368F1."""

    var s = String("1e-5")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, TAG_FLOAT64)
    assert_equal(result.value, UInt64(0x3EE4F8B588E368F1))


def test_leading_zero_fraction() raises:
    """'0.5' is a valid float (leading-zero rule allows it): oracle 0x3FE0000000000000."""

    var s = String("0.5")
    var buf = _nul_padded(s)
    var result = _parse_number(buf.unsafe_ptr(), len(s.as_bytes()))
    assert_equal(result.tag, TAG_FLOAT64)
    assert_equal(result.value, UInt64(0x3FE0000000000000))


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
    test_maximal_prefix_double_dot_value()
    test_maximal_prefix_dot_dot()
    test_maximal_prefix_double_exponent()
    test_maximal_prefix_trailing_alpha()
    test_negative_zero_integer()
    test_negative_zero_float()
    test_two_pow_64_routes_to_float()
    test_uint64_max_stays_integer()
    test_leading_plus_raises()
    test_trailing_dot_raises()
    test_bare_exponent_raises()
    test_exponent_sign_only_raises()
    test_exponent_plus_sign()
    test_exponent_minus_sign()
    test_leading_zero_fraction()
    print("test_numbers: all passed")
