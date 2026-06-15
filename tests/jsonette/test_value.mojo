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


def test_get_int_accepts_nonnegative() raises:
    var doc = parse(String('{"a":42,"b":0,"c":-7}'))
    assert_equal(doc.root().field("a").get_int(), Int64(42))
    var doc2 = parse(String('{"a":42,"b":0,"c":-7}'))
    assert_equal(doc2.root().field("b").get_int(), Int64(0))
    var doc3 = parse(String('{"a":42,"b":0,"c":-7}'))
    assert_equal(doc3.root().field("c").get_int(), Int64(-7))

def test_get_int_max_int64() raises:
    var doc = parse(String('{"m":9223372036854775807}'))
    assert_equal(doc.root().field("m").get_int(), Int64(9223372036854775807))

def test_get_int_uint_above_max_raises() raises:
    var doc = parse(String('{"m":9223372036854775808}'))
    var raised = False
    try:
        _ = doc.root().field("m").get_int()
    except:
        raised = True
    assert_true(raised, "get_int on UINT64 above Int64.MAX must raise")

def test_get_int_on_noninteger_raises() raises:
    var doc = parse(String('{"f":1.5,"s":"x"}'))
    var rf = False
    try:
        _ = doc.root().field("f").get_int()
    except:
        rf = True
    assert_true(rf, "get_int on a float must raise")
    var doc2 = parse(String('{"f":1.5,"s":"x"}'))
    var rs = False
    try:
        _ = doc2.root().field("s").get_int()
    except:
        rs = True
    assert_true(rs, "get_int on a string must raise")

def test_get_float_widens_any_number() raises:
    var doc = parse(String('{"u":42,"i":-7,"f":1.5}'))
    assert_equal(doc.root().field("u").get_float(), Float64(42.0))
    var doc2 = parse(String('{"u":42,"i":-7,"f":1.5}'))
    assert_equal(doc2.root().field("i").get_float(), Float64(-7.0))
    var doc3 = parse(String('{"u":42,"i":-7,"f":1.5}'))
    var f = doc3.root().field("f").get_float()
    assert_true(f > 1.49 and f < 1.51, "float reads back")

def test_get_float_on_nonnumber_raises() raises:
    var doc = parse(String('{"s":"x"}'))
    var raised = False
    try:
        _ = doc.root().field("s").get_float()
    except:
        raised = True
    assert_true(raised, "get_float on a string must raise")


def test_try_field_present_absent_nonobject() raises:
    var doc = parse(String('{"a":1,"n":null}'))
    var a = doc.root().try_field("a")
    assert_true(Bool(a), "present key is Some")
    assert_equal(a.value().get_uint(), UInt64(1))
    var doc2 = parse(String('{"a":1,"n":null}'))
    assert_true(not doc2.root().try_field("zzz"), "absent key is None")
    var doc3 = parse(String('{"a":1,"n":null}'))
    var n = doc3.root().try_field("n")
    assert_true(Bool(n), "present null is Some")
    assert_true(n.value().is_null(), "present null value is_null")
    var doc4 = parse(String('[1,2]'))
    var raised = False
    try:
        _ = doc4.root().try_field("a")
    except:
        raised = True
    assert_true(raised, "try_field on a non-object must raise")

def test_try_elem_present_absent_nonarray() raises:
    var doc = parse(String('[10,20,30]'))
    assert_equal(doc.root().try_elem(1).value().get_uint(), UInt64(20))
    var doc2 = parse(String('[10,20,30]'))
    assert_true(not doc2.root().try_elem(9), "out-of-range is None")
    var doc3 = parse(String('{"a":1}'))
    var raised = False
    try:
        _ = doc3.root().try_elem(0)
    except:
        raised = True
    assert_true(raised, "try_elem on a non-array must raise")

def test_as_int_type_test() raises:
    var d = String('{"u":42,"i":-7,"f":1.5,"s":"x","b":true,"n":null}')
    var r1 = parse(d); assert_equal(r1.root().field("u").as_int().value(), Int64(42))
    var r2 = parse(d); assert_equal(r2.root().field("i").as_int().value(), Int64(-7))
    var r3 = parse(d); assert_true(not r3.root().field("f").as_int(), "float -> None")
    var r4 = parse(d); assert_true(not r4.root().field("s").as_int(), "string -> None")
    var r5 = parse(d); assert_true(not r5.root().field("b").as_int(), "bool -> None")
    var r6 = parse(d); assert_true(not r6.root().field("n").as_int(), "null -> None")

def test_as_int_out_of_range_raises() raises:
    var doc = parse(String('{"m":9223372036854775808}'))
    var raised = False
    try:
        _ = doc.root().field("m").as_int()
    except:
        raised = True
    assert_true(raised, "as_int on UINT64 above Int64.MAX must raise, not None")
    var d2 = parse(String('{"m":9223372036854775808}'))
    assert_equal(d2.root().field("m").as_uint().value(), UInt64(9223372036854775808))

def test_as_uint_float_string_bool() raises:
    var d = String('{"u":42,"i":-7,"f":1.5,"s":"x","b":true}')
    var r1 = parse(d); assert_equal(r1.root().field("u").as_uint().value(), UInt64(42))
    var r2 = parse(d); assert_true(not r2.root().field("i").as_uint(), "negative -> None")
    var r3 = parse(d); assert_true(not r3.root().field("f").as_uint(), "float -> None")

def test_as_float_widens_and_string_none() raises:
    var d = String('{"u":42,"f":1.5,"s":"x"}')
    var r1 = parse(d); assert_equal(r1.root().field("u").as_float().value(), Float64(42.0))
    var r2 = parse(d)
    var f = r2.root().field("f").as_float().value()
    assert_true(f > 1.49 and f < 1.51, "float as_float")
    var r3 = parse(d); assert_true(not r3.root().field("s").as_float(), "string -> None")

def test_as_string_and_as_bool() raises:
    var d = String('{"s":"hi","b":true,"u":42}')
    var r1 = parse(d); assert_equal(r1.root().field("s").as_string().value(), String("hi"))
    var r2 = parse(d); assert_true(r2.root().field("b").as_bool().value(), "bool as_bool")
    var r3 = parse(d); assert_true(not r3.root().field("u").as_string(), "non-string -> None")
    var r4 = parse(d); assert_true(not r4.root().field("s").as_bool(), "non-bool -> None")


def main() raises:
    test_scalar_root()
    test_nested_navigation()
    test_leaf_types()
    test_type_predicates()
    test_getitem_sugar()
    test_iteration()
    test_get_int_accepts_nonnegative()
    test_get_int_max_int64()
    test_get_int_uint_above_max_raises()
    test_get_int_on_noninteger_raises()
    test_get_float_widens_any_number()
    test_get_float_on_nonnumber_raises()
    test_try_field_present_absent_nonobject()
    test_try_elem_present_absent_nonarray()
    test_as_int_type_test()
    test_as_int_out_of_range_raises()
    test_as_uint_float_string_bool()
    test_as_float_widens_and_string_none()
    test_as_string_and_as_bool()
    print("test_value: all passed")
