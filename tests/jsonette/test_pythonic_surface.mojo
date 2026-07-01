"""Pythonic operator surface over the DOM: dunders, iteration sugar, get()."""
from std.testing import assert_equal, assert_true
from jsonette.document import parse


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


def main() raises:
    test_eq_vs_string()
    test_contains()
    test_len()
    test_iter_array()
    test_reiteration()
    test_get_optional()
    test_items_keys()
    test_document_facade_nav()
    print("test_pythonic_surface: all passed")
