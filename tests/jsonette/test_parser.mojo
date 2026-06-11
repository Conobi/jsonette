from std.testing import assert_equal
from jsonette.tape import Tape
from jsonette.document import Document
from jsonette.parser import Parser
from jsonette.value import Value


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def test_document_root() raises:
    """Document.root() returns Value at tape index 1."""
    var tape = Tape()
    tape.elements.append((UInt64(0x72) << 56) | UInt64(2))  # root open -> 2
    tape.elements.append(UInt64(0x74) << 56)  # true
    tape.elements.append(UInt64(0x72) << 56)  # root close
    var doc = Document(tape)  # borrowing view over the local tape
    var root = doc.root()
    assert_equal(root._idx, 1)


def test_parser_parse_true() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String("true")))
    var root = doc.root()
    assert_equal(root.get_bool(doc), True)


def test_parser_parse_false() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String("false")))
    assert_equal(doc.root().get_bool(doc), False)


def test_parser_parse_null() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String("null")))
    assert_equal(doc.root().is_null(doc), True)


def test_parser_parse_number() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String("42")))
    assert_equal(doc.root().get_uint(doc), UInt64(42))


def test_parser_parse_object() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String('{"key": 42}')))
    var root = doc.root()
    var val = root.get(doc, String("key"))
    assert_equal(val.get_uint(doc), UInt64(42))


def test_parser_parse_array() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String("[1, 2, 3]")))
    var root = doc.root()
    assert_equal(root.count(doc), 3)
    assert_equal(root.at(doc, 1).get_uint(doc), UInt64(2))


def test_parser_mixed_object() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String('{"name": "test", "count": 42, "active": true}')))
    var root = doc.root()
    assert_equal(root.get(doc, String("name")).string_eq(doc, String("test")), True)
    assert_equal(root.get(doc, String("count")).get_uint(doc), UInt64(42))
    assert_equal(root.get(doc, String("active")).get_bool(doc), True)


def test_parser_nested() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String('{"data": {"items": [1, 2, 3]}}')))
    var root = doc.root()
    var items = root.get(doc, String("data")).get(doc, String("items"))
    assert_equal(items.count(doc), 3)
    assert_equal(items.at(doc, 0).get_uint(doc), UInt64(1))
    assert_equal(items.at(doc, 2).get_uint(doc), UInt64(3))


def test_parser_array_of_objects() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String('[{"id": 1}, {"id": 2}]')))
    var root = doc.root()
    assert_equal(root.count(doc), 2)
    assert_equal(root.at(doc, 0).get(doc, String("id")).get_uint(doc), UInt64(1))
    assert_equal(root.at(doc, 1).get(doc, String("id")).get_uint(doc), UInt64(2))


def test_parser_negative() raises:
    var parser = Parser()
    var doc = parser.parse(_make_bytes(String('{"val": -42}')))
    assert_equal(doc.root().get(doc, String("val")).get_int(doc), Int64(-42))


def test_parser_reused_across_parses() raises:
    """One Parser instance parses twice; both yield correct values."""
    var p = Parser()
    var doc1 = p.parse(_make_bytes(String('{"a": 1}')))
    assert_equal(doc1.root().get(doc1, String("a")).get_uint(doc1), UInt64(1))
    var doc2 = p.parse(_make_bytes(String("[1, 2, 3]")))
    assert_equal(doc2.root().count(doc2), 3)
    assert_equal(doc2.root().at(doc2, 0).get_uint(doc2), UInt64(1))
    assert_equal(doc2.root().at(doc2, 2).get_uint(doc2), UInt64(3))


def main() raises:
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
    print("test_parser: all passed")
