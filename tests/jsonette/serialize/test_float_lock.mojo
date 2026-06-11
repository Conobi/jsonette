"""Float bit-exactness lock for the JSON encoder.

Pins that `parse(s) → to_string → parse` yields a bit-identical `Float64` for
a set of hard cases. If the stdlib `String(Float64)` formatter ever stops being
shortest-round-trip, this test fails loudly (the escape-hatch trigger).
"""
from std.testing import assert_equal
from std.memory import bitcast
from jsonette.parser import Parser
from jsonette.serialize.tape_writer import to_string


def _bytes(s: String) -> List[UInt8]:
    """Convert a String to a List[UInt8] byte buffer."""
    var b = List[UInt8]()
    for x in s.as_bytes():
        b.append(x)
    return b^


def _bits(s: String) raises -> UInt64:
    """Parse `s` as a JSON float and return its raw IEEE-754 bit pattern."""
    var p = Parser()
    var doc = p.parse(_bytes(s))
    var f = doc.root().get_float(doc)
    return bitcast[DType.uint64](SIMD[DType.float64, 1](f))


def _assert_float_roundtrips(s: String) raises:
    """Assert that parse(s) → to_string → parse yields a bit-identical Float64.

    A mismatch means the stdlib formatter is not shortest-round-trip for this
    value. Do NOT relax this assertion — escalate to the architect to evaluate
    a native Ryu/Grisu3 formatter instead.
    """
    var p = Parser()
    var doc = p.parse(_bytes(s))
    var emitted = to_string(doc)
    assert_equal(_bits(s), _bits(emitted))


def test_float_lock() raises:
    """Lock float round-trip bit-exactness across 8 hard cases.

    Cases cover: negative zero, decimal fraction, pi, large mantissa, denorm
    boundary (5e-324 = min positive subnormal), near-overflow (1e308), the
    minimum normal (2.2250738585072014e-308), and max finite (1.7976931348623157e308).
    """
    _assert_float_roundtrips(String("-0.0"))
    _assert_float_roundtrips(String("0.1"))
    _assert_float_roundtrips(String("3.141592653589793"))
    _assert_float_roundtrips(String("123456789.12345679"))
    _assert_float_roundtrips(String("5e-324"))
    _assert_float_roundtrips(String("1e308"))
    _assert_float_roundtrips(String("2.2250738585072014e-308"))
    _assert_float_roundtrips(String("1.7976931348623157e308"))


def main() raises:
    test_float_lock()
    print("test_float_lock: all passed")
