"""Non-finite float contract: parse saturates out-of-range magnitudes to ±inf,
the encoder refuses to emit a non-finite float by raising.

This locks the agreed policy end to end. RFC 8259 does not bound the magnitude of
a JSON number, so `1e999` is well-formed: jsonette (like simdjson and Python's
`json.loads`) accepts it and SATURATES to ±Infinity during number parsing. JSON,
however, has no Infinity/NaN literal, so the encoder cannot round-trip such a
value — `to_string` RAISES by design rather than silently emitting `null` or an
invalid token. Underflow (`1e-999`) must resolve to a FINITE `0.0`, never inf and
never a raise. `parse()` and `Parser.validate()` must agree on acceptance.
"""
from std.testing import assert_true, assert_equal
from std.math import isfinite, isinf
from jsonette.document import parse
from jsonette.parser import Parser
from jsonette.serialize.tape_writer import to_string


def _bytes(s: String) -> List[UInt8]:
    """Convert the ASCII/UTF-8 bytes of `s` into a List[UInt8] parser input."""
    var b = List[UInt8]()
    for x in s.as_bytes():
        b.append(x)
    return b^


def _big_int_digits(zeros: Int) -> List[UInt8]:
    """Build the bytes for `1` followed by `zeros` `0`s (a bare huge integer)."""
    var b = List[UInt8]()
    b.append(UInt8(0x31))  # '1'
    for _ in range(zeros):
        b.append(UInt8(0x30))  # '0'
    return b^


def _emit_raises(data: List[UInt8]) raises -> Bool:
    """True iff parsing `data` then serialising it via to_string raises."""
    var doc = parse(data)
    try:
        _ = to_string(doc)
        return False
    except:
        return True


def _validate_rejects(data: List[UInt8]) raises -> Bool:
    """True iff Parser.validate rejects `data`."""
    var p = Parser()
    try:
        p.validate(data)
        return False
    except:
        return True


def test_parse_saturates_overflow_to_inf() raises:
    """`1e999` and `-1e999` saturate to ±inf; a 400-digit integer overflows to +inf."""
    var pos_doc = parse(_bytes(String("1e999")))
    var pos = pos_doc.root().get_float()
    assert_true(isinf(pos), "1e999 must be infinite")
    assert_true(pos > 0.0, "1e999 must be +inf")

    var neg_doc = parse(_bytes(String("-1e999")))
    var neg = neg_doc.root().get_float()
    assert_true(isinf(neg), "-1e999 must be infinite")
    assert_true(neg < 0.0, "-1e999 must be -inf")

    # A bare integer with 400 digits ("1" + 400 zeros) is out of Float64 range.
    var huge_doc = parse(_big_int_digits(400))
    var huge = huge_doc.root().get_float()
    assert_true(isinf(huge), "1 followed by 400 zeros must be infinite")
    assert_true(huge > 0.0, "huge integer must be +inf")


def test_parse_underflow_is_finite_zero() raises:
    """`1e-999` underflows to a FINITE 0.0 — it must not saturate to inf or raise."""
    var z_doc = parse(_bytes(String("1e-999")))
    var z = z_doc.root().get_float()
    assert_true(isfinite(z), "1e-999 must be finite")
    assert_equal(z, Float64(0.0))


def test_validate_agrees_with_parse_on_overflow() raises:
    """`validate()` accepts `1e999`, consistent with `parse()` accepting it."""
    assert_true(not _validate_rejects(_bytes(String("1e999"))),
                "validate() must accept 1e999")
    assert_true(not _validate_rejects(_bytes(String("-1e999"))),
                "validate() must accept -1e999")


def test_encode_refuses_nonfinite_by_raising() raises:
    """`to_string` raises for a parsed +inf and -inf document (no silent null)."""
    assert_true(_emit_raises(_bytes(String("1e999"))),
                "to_string on +inf must raise")
    assert_true(_emit_raises(_bytes(String("-1e999"))),
                "to_string on -inf must raise")


def test_encode_finite_document_does_not_raise() raises:
    """Control: a finite document round-trips through to_string without raising.

    Proves _emit_raises is not trivially always-true."""
    assert_true(not _emit_raises(_bytes(String("[1.5,2]"))),
                "finite document must serialise without raising")


def main() raises:
    test_parse_saturates_overflow_to_inf()
    test_parse_underflow_is_finite_zero()
    test_validate_agrees_with_parse_on_overflow()
    test_encode_refuses_nonfinite_by_raising()
    test_encode_finite_document_does_not_raise()
    print("test_nonfinite_roundtrip: all passed")
