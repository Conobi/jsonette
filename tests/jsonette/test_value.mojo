"""Self-bound DOM navigation: owning Document + Value with no doc-threading."""
from std.testing import assert_equal, assert_true
from jsonette.document import parse


def _b(s: String) -> List[UInt8]:
    var d = List[UInt8]()
    for x in s.as_bytes():
        d.append(x)
    return d^


def test_scalar_root() raises:
    var doc = parse(_b(String("42")))
    assert_equal(doc.root().get_uint(), UInt64(42))


def test_nested_navigation() raises:
    var doc = parse(_b(String('{"data":{"items":[1,2,3]}}')))
    var items = doc.root().field("data").field("items")
    assert_equal(items.len(), 3)
    assert_equal(items.elem(0).get_uint(), UInt64(1))
    assert_equal(items.elem(2).get_uint(), UInt64(3))


def test_leaf_types() raises:
    var doc = parse(_b(String('{"s":"hi","i":-7,"u":9,"f":1.5,"b":true,"n":null}')))
    var r = doc.root()
    assert_equal(r.field("s").get_string(), String("hi"))
    assert_equal(r.field("i").get_int(), Int64(-7))
    assert_equal(r.field("u").get_uint(), UInt64(9))
    assert_true(r.field("f").get_float() > 1.49 and r.field("f").get_float() < 1.51, "f")
    assert_true(r.field("b").get_bool(), "b")
    assert_true(r.field("n").is_null(), "n")


def test_type_predicates() raises:
    var doc = parse(_b(String('{"o":{},"a":[],"s":"x"}')))
    var r = doc.root()
    assert_true(r.is_object(), "root obj")
    assert_true(r.field("o").is_object(), "o")
    assert_true(r.field("a").is_array(), "a")
    assert_true(r.field("s").is_string(), "s")


def test_getitem_sugar() raises:
    var doc = parse(_b(String('{"data":{"items":[10,20,30]}}')))
    assert_equal(doc.root()["data"]["items"][1].get_uint(), UInt64(20))


def test_iteration() raises:
    var doc = parse(_b(String('{"a":1,"b":2,"c":3}')))
    var keys = String("")
    var total = UInt64(0)
    for f in doc.root().fields():
        keys += f.key()
        total += f.value().get_uint()
    assert_equal(keys, String("abc"))
    assert_equal(total, UInt64(6))
    var arr = parse(_b(String("[4,5,6]")))
    var s = UInt64(0)
    for e in arr.root().elems():
        s += e.get_uint()
    assert_equal(s, UInt64(15))


def main() raises:
    test_scalar_root()
    test_nested_navigation()
    test_leaf_types()
    test_type_predicates()
    test_getitem_sugar()
    test_iteration()
    print("test_value: all passed")
