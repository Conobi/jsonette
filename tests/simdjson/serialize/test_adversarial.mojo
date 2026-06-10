from std.testing import assert_equal
from simdjson.parser import Parser
from simdjson.serialize.tape_writer import to_string


def _bytes(s: String) -> List[UInt8]:
    var b = List[UInt8]()
    for x in s.as_bytes():
        b.append(x)
    return b^


def _emit(s: String) raises -> String:
    var p = Parser()
    var doc = p.parse(_bytes(s))
    return to_string(doc)


def test_scalar_roots() raises:
    assert_equal(_emit(String("42")), String("42"))
    assert_equal(_emit(String('"x"')), String('"x"'))
    assert_equal(_emit(String("true")), String("true"))
    assert_equal(_emit(String("false")), String("false"))
    assert_equal(_emit(String("null")), String("null"))


def test_escapes() raises:
    # control chars + quote + backslash re-escaped canonically
    assert_equal(_emit(String('"a\\nb\\t\\"q\\\\z"')), String('"a\\nb\\t\\"q\\\\z"'))
    assert_equal(_emit(String('"\\u0001"')), String('"\\u0001"'))
    # carriage return must re-emit as the short escape \r, not a raw byte
    assert_equal(_emit(String('"\\r"')), String('"\\r"'))


def test_unicode_passthrough() raises:
    # non-ASCII UTF-8 (e-acute, U+00E9 = 0xC3 0xA9) passes through verbatim
    assert_equal(_emit(String('"caf') + chr(0xC3) + chr(0xA9) + '"'),
                 String('"caf') + chr(0xC3) + chr(0xA9) + '"')


def test_int_bounds() raises:
    assert_equal(_emit(String("-9223372036854775808")), String("-9223372036854775808"))
    assert_equal(_emit(String("18446744073709551615")), String("18446744073709551615"))


def test_deep_nesting() raises:
    assert_equal(_emit(String("[[[[[1]]]]]")), String("[[[[[1]]]]]"))
    assert_equal(_emit(String('{"a":{"b":{"c":{}}}}')), String('{"a":{"b":{"c":{}}}}'))


def main() raises:
    test_scalar_roots()
    test_escapes()
    test_unicode_passthrough()
    test_int_bounds()
    test_deep_nesting()
    print("test_adversarial: all passed")
