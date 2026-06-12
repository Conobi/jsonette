from std.testing import assert_equal, assert_true
from std.memory import bitcast
from jsonette.tape import Tape, TAG_ROOT, TAG_TRUE, TAG_FALSE, TAG_NULL, TAG_UINT64, TAG_INT64, TAG_FLOAT64, TAG_STRING, TAG_OBJECT_OPEN, TAG_ARRAY_OPEN
from jsonette.document import Document
from jsonette.value import Value, skip_value
from jsonette.parser import Parser


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def _parse[o: Origin[mut=True]](ref [o] parser: Parser, s: String) raises -> Document[origin_of(parser._tape)]:
    """Parse `s` through the caller-owned parser, returning a view over its tape."""
    return parser.parse(_make_bytes(s))


# --- Type check + scalar getter tests ---

def test_bool_true() raises:
    var parser = Parser()
    var doc = _parse(parser, String("true"))
    var root = doc.root()
    assert_equal(root.is_bool(doc), True)
    assert_equal(root.get_bool(doc), True)

def test_bool_false() raises:
    var parser = Parser()
    var doc = _parse(parser, String("false"))
    var root = doc.root()
    assert_equal(root.get_bool(doc), False)

def test_null() raises:
    var parser = Parser()
    var doc = _parse(parser, String("null"))
    var root = doc.root()
    assert_equal(root.is_null(doc), True)

def test_uint() raises:
    var parser = Parser()
    var doc = _parse(parser, String("42"))
    var root = doc.root()
    assert_equal(root.is_uint(doc), True)
    assert_equal(root.get_uint(doc), UInt64(42))

def test_int() raises:
    var parser = Parser()
    var doc = _parse(parser, String("-7"))
    var root = doc.root()
    assert_equal(root.is_int(doc), True)
    assert_equal(root.get_int(doc), Int64(-7))

def test_float() raises:
    var parser = Parser()
    var doc = _parse(parser, String("3.14"))
    var root = doc.root()
    assert_equal(root.is_float(doc), True)
    var val = root.get_float(doc)
    var diff = val - 3.14
    if diff < 0.0: diff = -diff
    assert_true(diff < 0.001)

def test_string_eq() raises:
    var parser = Parser()
    var doc = _parse(parser, String('"hello"'))
    var root = doc.root()
    assert_equal(root.is_string(doc), True)
    assert_equal(root.string_eq(doc, String("hello")), True)
    assert_equal(root.string_eq(doc, String("world")), False)
    assert_equal(root.get_string_length(doc), 5)

# --- Container access tests ---

def test_object_get() raises:
    var parser = Parser()
    var doc = _parse(parser, String('{"a": 42, "b": true}'))
    var root = doc.root()
    assert_equal(root.is_object(doc), True)
    var a_val = root.get(doc, String("a"))
    assert_equal(a_val.get_uint(doc), UInt64(42))
    var b_val = root.get(doc, String("b"))
    assert_equal(b_val.get_bool(doc), True)

def test_array_at() raises:
    var parser = Parser()
    var doc = _parse(parser, String("[10, 20, 30]"))
    var root = doc.root()
    assert_equal(root.is_array(doc), True)
    assert_equal(root.at(doc, 0).get_uint(doc), UInt64(10))
    assert_equal(root.at(doc, 2).get_uint(doc), UInt64(30))

def test_array_count() raises:
    var parser = Parser()
    var doc = _parse(parser, String("[1, 2, 3]"))
    var root = doc.root()
    assert_equal(root.count(doc), 3)

def test_empty_array_count() raises:
    var parser = Parser()
    var doc = _parse(parser, String("[]"))
    var root = doc.root()
    assert_equal(root.count(doc), 0)

def test_empty_object_count() raises:
    var parser = Parser()
    var doc = _parse(parser, String("{}"))
    var root = doc.root()
    assert_equal(root.count(doc), 0)

def test_nested_get() raises:
    var parser = Parser()
    var doc = _parse(parser, String('{"data": {"x": 1}}'))
    var root = doc.root()
    var data = root.get(doc, String("data"))
    var x = data.get(doc, String("x"))
    assert_equal(x.get_uint(doc), UInt64(1))

def test_nested_array_in_object() raises:
    var parser = Parser()
    var doc = _parse(parser, String('{"items": [10, 20]}'))
    var root = doc.root()
    var items = root.get(doc, String("items"))
    assert_equal(items.count(doc), 2)
    assert_equal(items.at(doc, 1).get_uint(doc), UInt64(20))

def test_array_of_objects() raises:
    var parser = Parser()
    var doc = _parse(parser, String('[{"id": 1}, {"id": 2}]'))
    var root = doc.root()
    assert_equal(root.count(doc), 2)
    assert_equal(root.at(doc, 0).get(doc, String("id")).get_uint(doc), UInt64(1))
    assert_equal(root.at(doc, 1).get(doc, String("id")).get_uint(doc), UInt64(2))

def test_mixed_object() raises:
    var parser = Parser()
    var doc = _parse(parser, String('{"name": "test", "count": 42, "active": true}'))
    var root = doc.root()
    assert_equal(root.get(doc, String("name")).string_eq(doc, String("test")), True)
    assert_equal(root.get(doc, String("count")).get_uint(doc), UInt64(42))
    assert_equal(root.get(doc, String("active")).get_bool(doc), True)

def test_negative_in_object() raises:
    var parser = Parser()
    var doc = _parse(parser, String('{"val": -42}'))
    var root = doc.root()
    assert_equal(root.get(doc, String("val")).get_int(doc), Int64(-42))

def test_deeply_nested() raises:
    var parser = Parser()
    var doc = _parse(parser, String('{"data": {"items": [1, 2, 3]}}'))
    var root = doc.root()
    var items = root.get(doc, String("data")).get(doc, String("items"))
    assert_equal(items.count(doc), 3)
    assert_equal(items.at(doc, 0).get_uint(doc), UInt64(1))
    assert_equal(items.at(doc, 2).get_uint(doc), UInt64(3))

# --- get_string tests ---

def test_get_string() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String('"hello"')))
    var root = doc.root()
    var s = root.get_string(doc)
    assert_equal(s, String("hello"))

def test_get_string_from_object() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String('{"name": "world"}')))
    var root = doc.root()
    var name = root.get(doc, String("name")).get_string(doc)
    assert_equal(name, String("world"))

def test_get_string_empty() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String('""')))
    var root = doc.root()
    var s = root.get_string(doc)
    assert_equal(s, String(""))


def main() raises:
    test_bool_true()
    test_bool_false()
    test_null()
    test_uint()
    test_int()
    test_float()
    test_string_eq()
    test_object_get()
    test_array_at()
    test_array_count()
    test_empty_array_count()
    test_empty_object_count()
    test_nested_get()
    test_nested_array_in_object()
    test_array_of_objects()
    test_mixed_object()
    test_negative_in_object()
    test_deeply_nested()
    test_get_string()
    test_get_string_from_object()
    test_get_string_empty()
    print("test_value: all passed")
