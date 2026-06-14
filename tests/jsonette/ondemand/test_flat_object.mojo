"""On-Demand (lazy) parser — M0: flat top-level object, lazy leaf reads.

These tests exercise the M0 surface through inference ONLY: a caller obtains the
root handle from `Parser.iter(...)`, navigates with `find_field(key)`, and reads
a leaf with `get_string()` / `get_int()` — without ever naming any `[o]`-
parametric type. That constraint is the contract: the public entry returns a
type used by inference, like `Parser.document()`.
"""

from std.testing import assert_equal, assert_true
from jsonette.parser import Parser


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def test_find_field_get_string() raises:
    """A string value found by key is returned unescaped."""
    var data = _make_bytes(String('{"name":"hello","age":42,"city":"paris"}'))
    var parser = Parser()
    var root = parser.iter(data)
    assert_equal(root.find_field(String("name")).get_string(), String("hello"))


def test_find_field_get_string_last_field() raises:
    """The last field of a flat object is reachable by key."""
    var data = _make_bytes(String('{"name":"hello","age":42,"city":"paris"}'))
    var parser = Parser()
    var root = parser.iter(data)
    assert_equal(root.find_field(String("city")).get_string(), String("paris"))


def test_find_field_get_int() raises:
    """An integer value found by key is parsed to Int64."""
    var data = _make_bytes(String('{"name":"hello","age":42,"city":"paris"}'))
    var parser = Parser()
    var root = parser.iter(data)
    assert_equal(root.find_field(String("age")).get_int(), Int64(42))


def test_find_field_missing_raises() raises:
    """An absent key raises from find_field."""
    var data = _make_bytes(String('{"name":"hello","age":42,"city":"paris"}'))
    var parser = Parser()
    var root = parser.iter(data)
    var raised = False
    try:
        _ = root.find_field(String("missing"))
    except:
        raised = True
    assert_true(raised, "find_field on a missing key must raise")


def test_iter_reused_across_parses() raises:
    """A second iter() on the same parser reuses warm buffers and still reads."""
    var parser = Parser()
    var first = _make_bytes(String('{"name":"hello","age":42,"city":"paris"}'))
    var root1 = parser.iter(first)
    assert_equal(root1.find_field(String("name")).get_string(), String("hello"))

    var second = _make_bytes(String('{"greeting":"bonjour","count":7}'))
    var root2 = parser.iter(second)
    assert_equal(
        root2.find_field(String("greeting")).get_string(), String("bonjour")
    )
    assert_equal(root2.find_field(String("count")).get_int(), Int64(7))


def main() raises:
    test_find_field_get_string()
    test_find_field_get_string_last_field()
    test_find_field_get_int()
    test_find_field_missing_raises()
    test_iter_reused_across_parses()
    print("test_flat_object: all passed")
