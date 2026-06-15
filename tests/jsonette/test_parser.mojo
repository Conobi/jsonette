from std.testing import assert_equal
from jsonette.document import parse


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def test_document_root() raises:
    """Document.root() returns Value at tape index 1."""
    var doc = parse(_make_bytes(String("true")))
    var root = doc.root()
    assert_equal(root._idx, 1)


def test_parser_parse_true() raises:
    var doc = parse(_make_bytes(String("true")))
    var root = doc.root()
    assert_equal(root.get_bool(), True)


def test_parser_parse_false() raises:
    var doc = parse(_make_bytes(String("false")))
    assert_equal(doc.root().get_bool(), False)


def test_parser_parse_null() raises:
    var doc = parse(_make_bytes(String("null")))
    assert_equal(doc.root().is_null(), True)


def test_parser_parse_number() raises:
    var doc = parse(_make_bytes(String("42")))
    assert_equal(doc.root().get_uint(), UInt64(42))


def test_parser_parse_object() raises:
    var doc = parse(_make_bytes(String('{"key": 42}')))
    var root = doc.root()
    var val = root.field(String("key"))
    assert_equal(val.get_uint(), UInt64(42))


def test_parser_parse_array() raises:
    var doc = parse(_make_bytes(String("[1, 2, 3]")))
    var root = doc.root()
    assert_equal(root.len(), 3)
    assert_equal(root.elem(1).get_uint(), UInt64(2))


def test_parser_mixed_object() raises:
    var doc = parse(_make_bytes(String('{"name": "test", "count": 42, "active": true}')))
    var root = doc.root()
    assert_equal(root.field(String("name")).string_eq(String("test")), True)
    assert_equal(root.field(String("count")).get_uint(), UInt64(42))
    assert_equal(root.field(String("active")).get_bool(), True)


def test_parser_nested() raises:
    var doc = parse(_make_bytes(String('{"data": {"items": [1, 2, 3]}}')))
    var root = doc.root()
    var items = root.field(String("data")).field(String("items"))
    assert_equal(items.len(), 3)
    assert_equal(items.elem(0).get_uint(), UInt64(1))
    assert_equal(items.elem(2).get_uint(), UInt64(3))


def test_parser_array_of_objects() raises:
    var doc = parse(_make_bytes(String('[{"id": 1}, {"id": 2}]')))
    var root = doc.root()
    assert_equal(root.len(), 2)
    assert_equal(root.elem(0).field(String("id")).get_uint(), UInt64(1))
    assert_equal(root.elem(1).field(String("id")).get_uint(), UInt64(2))


def test_parser_negative() raises:
    var doc = parse(_make_bytes(String('{"val": -42}')))
    assert_equal(doc.root().field(String("val")).get_int(), Int64(-42))


def test_parser_reused_across_parses() raises:
    """One Document reparses into reused buffers; both parses yield correct values."""
    var doc = parse(_make_bytes(String('{"a": 1}')))
    assert_equal(doc.root().field(String("a")).get_uint(), UInt64(1))
    doc.reparse(_make_bytes(String("[1, 2, 3]")))
    assert_equal(doc.root().len(), 3)
    assert_equal(doc.root().elem(0).get_uint(), UInt64(1))
    assert_equal(doc.root().elem(2).get_uint(), UInt64(3))


def test_root_repeat_view() raises:
    """Root view is repeatable: root() is callable multiple times with no reparse."""
    var doc = parse(_make_bytes(String("42")))
    assert_equal(doc.root().get_uint(), UInt64(42))
    assert_equal(doc.root().get_uint(), UInt64(42))


def test_reparse_reflects_latest() raises:
    """Reparse rebuilds into the same buffers, so root() sees the new data."""
    var doc = parse(_make_bytes(String('{"a": 1}')))
    doc.reparse(_make_bytes(String("[1, 2, 3]")))
    assert_equal(doc.root().len(), 3)
    assert_equal(doc.root().elem(2).get_uint(), UInt64(3))


def test_parse_string_input() raises:
    """Parse from a String is a convenience entry: no manual byte buffer."""
    var doc = parse(String('{"k":5}'))
    assert_equal(doc.root().field("k").get_uint(), UInt64(5))


def test_reparse_string_input() raises:
    """Reparse from a String rebuilds, reusing buffers."""
    var doc = parse(String('{"k":1}'))
    assert_equal(doc.root().field("k").get_uint(), UInt64(1))
    doc.reparse(String('{"k":2}'))
    assert_equal(doc.root().field("k").get_uint(), UInt64(2))


def main() raises:
    test_root_repeat_view()
    test_reparse_reflects_latest()
    test_document_root()
    test_parser_parse_true()
    test_parser_parse_false()
    test_parser_parse_null()
    test_parser_parse_number()
    test_parser_parse_object()
    test_parser_parse_array()
    test_parser_mixed_object()
    test_parser_nested()
    test_parser_array_of_objects()
    test_parser_negative()
    test_parser_reused_across_parses()
    test_parse_string_input()
    test_reparse_string_input()
    print("test_parser: all passed")
