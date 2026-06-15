"""On-Demand any-root: Reader.root() works for every JSON root type."""
from std.testing import assert_equal, assert_true
from jsonette.ondemand.reader import iter


def test_scalar_roots() raises:
    var n = iter(String("42")); assert_equal(n.root().get_uint(), UInt64(42))
    var neg = iter(String("-7")); assert_equal(neg.root().get_int(), Int64(-7))
    var f = iter(String("1.5")); assert_true(f.root().get_float() > 1.49, "float root")
    var s = iter(String('"hi"')); assert_equal(s.root().get_string(), String("hi"))
    var t = iter(String("true")); assert_true(t.root().get_bool(), "true root")
    var nul = iter(String("null")); assert_true(nul.root().is_null(), "null root")


def test_array_root() raises:
    var rdr = iter(String("[10,20,30]"))
    var arr = rdr.root().get_array()
    assert_equal(arr.next_element().get_uint(), UInt64(10))


def test_object_root() raises:
    var rdr = iter(String('{"k":5}'))
    assert_equal(rdr.root().field("k").get_uint(), UInt64(5))


def test_scalar_root_not_container() raises:
    var rdr = iter(String("42"))
    var raised = False
    try:
        _ = rdr.root().get_object()
    except:
        raised = True
    assert_true(raised, "get_object on a scalar root must raise")


def test_shared_verbs() raises:
    var rdr = iter(String('{"data":{"items":[1,2,3]},"name":"x"}'))
    assert_equal(rdr.root().field("data").field("items").elem(2).get_uint(), UInt64(3))
    assert_equal(rdr.root()["name"].get_string(), String("x"))
    assert_equal(rdr.root()["data"]["items"][0].get_uint(), UInt64(1))


def test_empty_root_raises() raises:
    for ref s in [String(""), String("   "), String("\t\n ")]:
        var raised = False
        try:
            var rdr = iter(s)
            _ = rdr.root()
        except:
            raised = True
        assert_true(raised, "empty/whitespace root must raise, not crash: [" + s + "]")


def test_elem_out_of_range_raises() raises:
    var empty = iter(String("[]"))
    var r1 = False
    try:
        _ = empty.root().elem(0)
    except:
        r1 = True
    assert_true(r1, "elem(0) on [] must raise")
    var three = iter(String("[1,2,3]"))
    var r2 = False
    try:
        _ = three.root().elem(3)
    except:
        r2 = True
    assert_true(r2, "elem(3) on a 3-element array must raise")


def main() raises:
    test_scalar_roots()
    test_array_root()
    test_object_root()
    test_scalar_root_not_container()
    test_shared_verbs()
    test_empty_root_raises()
    test_elem_out_of_range_raises()
    print("test_any_root: all passed")
