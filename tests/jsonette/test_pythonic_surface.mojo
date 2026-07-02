"""Pythonic operator surface over the DOM: dunders, iteration sugar, get()."""
from std.testing import assert_equal, assert_true
from jsonette.document import parse
from jsonette.serialize.tape_writer import to_string, to_json


def test_eq_vs_string() raises:
    var doc = parse(String('{"type":"user","name":"Ada","n":5}'))
    var r = doc.root()
    assert_true(r.field("type") == "user", "string equals literal")
    assert_true(r.field("type") != "admin", "string not-equals literal")
    # total: non-string receiver compares False, never raises
    assert_true(not (r.field("n") == "5"), "number is not equal to a string")
    assert_true(r.field("n") != "5", "number != string is True")


def test_contains() raises:
    var doc = parse(String('{"a":1,"b":null,"nested":{"x":9}}'))
    var r = doc.root()
    assert_true("a" in r, "present key")
    assert_true("b" in r, "present key with null value")
    assert_true(not ("z" in r), "absent key")
    # total: non-object receiver → False, never raises
    assert_true(not ("a" in r.field("a")), "contains on a number is False")


def test_len() raises:
    var doc = parse(String('{"arr":[10,20,30],"obj":{"a":1,"b":2},"s":"hi","n":7}'))
    var r = doc.root()
    assert_equal(len(r.field("arr")), 3)
    assert_equal(len(r.field("obj")), 2)
    assert_equal(len(r), 4)  # root object has 4 members
    # total: len() of a non-container is 0, never raises
    assert_equal(len(r.field("s")), 0)
    assert_equal(len(r.field("n")), 0)


def test_iter_array() raises:
    var doc = parse(String('{"xs":[4,5,6]}'))
    var total = UInt64(0)
    for x in doc.root().field("xs"):
        total += x.get_uint()
    assert_equal(total, UInt64(15))
    # total: iterating a non-array yields nothing, never raises
    var count = 0
    for _x in doc.root().field("xs").elem(0):  # elem(0) is a number
        count += 1
    assert_equal(count, 0)


def test_reiteration() raises:
    var doc = parse(String("[1,2,3]"))
    var r = doc.root()
    var a = UInt64(0)
    for x in r: a += x.get_uint()
    var b = UInt64(0)
    for x in r: b += x.get_uint()  # second pass must read identically
    assert_equal(a, b)
    assert_equal(r.elem(0).get_uint(), UInt64(1))  # random access still works after iterating


def test_get_optional() raises:
    var doc = parse(String('{"a":null,"arr":[7,8]}'))
    var r = doc.root()
    # present key (even null) -> Some ; absent -> None
    assert_true(r.get("a").__bool__(), "present-null key is Some")
    assert_true(r.get("a").value().is_null(), "value is JSON null")
    assert_true(not r.get("missing").__bool__(), "absent key is None")
    # array index get
    assert_equal(r.field("arr").get(1).value().get_uint(), UInt64(8))
    assert_true(not r.field("arr").get(9).__bool__(), "out-of-range is None")


def test_items_keys() raises:
    var doc = parse(String('{"a":1,"b":2,"c":3}'))
    var r = doc.root()
    var ks = String("")
    for k in r.keys():
        ks += k
    assert_equal(ks, String("abc"))
    var kk = String("")
    var vv = UInt64(0)
    for k, v in r.items():
        kk += k
        vv += v.get_uint()
    assert_equal(kk, String("abc"))
    assert_equal(vv, UInt64(6))
    # raises on a non-object receiver
    var raised = False
    try:
        _ = r.field("a").keys()
    except:
        raised = True
    assert_true(raised, "keys() on a number must raise")


def test_document_facade_nav() raises:
    var doc = parse(String('{"user":{"name":"Ada"},"tags":["x","y"],"k":3}'))
    # no .root() hop:
    assert_equal(doc["user"]["name"].get_string(), String("Ada"))
    assert_equal(doc["tags"][1].get_string(), String("y"))
    assert_equal(doc.field("k").get_uint(), UInt64(3))
    assert_true("user" in doc, "contains on document")
    assert_true(not ("zzz" in doc), "absent on document")
    assert_equal(doc.len(), 3)
    assert_true(doc.get("user").__bool__(), "get present")
    assert_true(not doc.get("zzz").__bool__(), "get absent")
    var total = UInt64(0)
    for x in doc["tags"].elems():
        _ = x
        total += 1
    assert_equal(total, UInt64(2))
    var kk = String("")
    for k, v in doc["user"].items():
        kk += k
        _ = v
    assert_equal(kk, String("name"))


def test_document_facade_leaves() raises:
    var s = parse(String('"hello"'))
    assert_true(s.is_string(), "scalar-root is_string")
    assert_equal(s.get_string(), String("hello"))
    var n = parse(String("-7"))
    assert_true(n.is_number(), "is_number")
    assert_equal(n.get_int(), Int64(-7))
    assert_equal(n.as_int().value(), Int64(-7))
    var b = parse(String("true"))
    assert_true(b.is_bool() and b.get_bool(), "bool root")
    var nul = parse(String("null"))
    assert_true(nul.is_null(), "null root")
    var f = parse(String("1.5"))
    assert_true(f.get_float() > 1.49 and f.get_float() < 1.51, "float root")
    assert_true(f.as_string().__bool__() == False, "as_string on number is None")


def test_value_serialization_subtree() raises:
    """String(value) and to_string(value) serialize only the sub-tree, not the doc."""
    var doc = parse(String('{"user":{"name":"Ada","age":36},"tags":["x","y"]}'))
    # String(value) routes through the Writable conformance (write_to).
    assert_equal(String(doc.root().field("user")), String('{"name":"Ada","age":36}'))
    # Free to_string(value) overload on an array sub-tree (not the whole document).
    assert_equal(to_string(doc.root().field("tags")), String('["x","y"]'))


def test_to_json_pretty_subtree() raises:
    """Pretty-printing a value sub-tree indents it with two spaces."""
    var doc = parse(String('{"user":{"name":"Ada","age":36}}'))
    var pretty = to_json[pretty=True](doc.root().field("user"))
    assert_equal(pretty, String('{\n  "name": "Ada",\n  "age": 36\n}'))


def test_value_scalar_serialization() raises:
    """String(value) on scalar/null leaves yields their bare JSON tokens."""
    var doc = parse(String('{"s":"hello","n":42,"z":null}'))
    var r = doc.root()
    assert_equal(String(r.field("s")), String('"hello"'))
    assert_equal(String(r.field("n")), String("42"))
    assert_equal(String(r.field("z")), String("null"))


def test_value_nonfinite_serialization() raises:
    """Strict to_string(value) raises on a non-finite node; String(value) is
    infallible and substitutes null only for the offending node."""
    var doc = parse(String('{"x":1e999}'))
    var raised = False
    try:
        _ = to_string(doc.root())
    except:
        raised = True
    assert_true(raised, "strict to_string(value) must raise on a non-finite node")
    # Infallible write_to path: only the non-finite node becomes null, rest intact.
    assert_equal(String(doc.root()), String('{"x":null}'))


def main() raises:
    test_eq_vs_string()
    test_contains()
    test_len()
    test_iter_array()
    test_reiteration()
    test_get_optional()
    test_items_keys()
    test_document_facade_nav()
    test_document_facade_leaves()
    test_value_serialization_subtree()
    test_to_json_pretty_subtree()
    test_value_scalar_serialization()
    test_value_nonfinite_serialization()
    print("test_pythonic_surface: all passed")
