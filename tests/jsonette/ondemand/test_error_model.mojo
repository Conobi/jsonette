"""On-Demand error-model opt-ins: has_field, try_field, try_elem (P3)."""

from std.testing import assert_equal, assert_true
from jsonette.ondemand.reader import iter


def test_has_field() raises:
    var rdr = iter(String('{"a":1,"b":2}'))
    assert_true(rdr.root().has_field("a"), "present key")
    var r2 = iter(String('{"a":1,"b":2}'))
    assert_true(not r2.root().has_field("zzz"), "absent key")

def test_has_field_nonobject_raises() raises:
    var rdr = iter(String('[1,2]'))
    var raised = False
    try:
        _ = rdr.root().has_field("a")
    except:
        raised = True
    assert_true(raised, "has_field on a non-object must raise")

def test_try_field_present_absent_null() raises:
    var rdr = iter(String('{"a":1,"n":null}'))
    var a = rdr.root().try_field("a")
    assert_true(Bool(a), "present is Some")
    assert_equal(a.value().get_int(), Int64(1))
    var r2 = iter(String('{"a":1,"n":null}'))
    assert_true(not r2.root().try_field("zzz"), "absent is None")
    var r3 = iter(String('{"a":1,"n":null}'))
    var n = r3.root().try_field("n")
    assert_true(Bool(n), "present null is Some")
    assert_true(n.value().is_null(), "present null value is_null")

def test_try_field_nonobject_raises() raises:
    var rdr = iter(String('"x"'))
    var raised = False
    try:
        _ = rdr.root().try_field("a")
    except:
        raised = True
    assert_true(raised, "try_field on a non-object must raise")

def test_try_elem_present_absent_nonarray() raises:
    var rdr = iter(String('[10,20,30]'))
    assert_equal(rdr.root().try_elem(1).value().get_int(), Int64(20))
    var r2 = iter(String('[10,20,30]'))
    assert_true(not r2.root().try_elem(9), "out of range is None")
    var r3 = iter(String('{"a":1}'))
    var raised = False
    try:
        _ = r3.root().try_elem(0)
    except:
        raised = True
    assert_true(raised, "try_elem on a non-array must raise")


def test_as_int_wrong_kind_none() raises:
    var d = String('{"u":42,"i":-7,"f":1.5,"s":"x","b":true,"n":null}')
    var r1 = iter(d); assert_equal(r1.root().field("u").as_int().value(), Int64(42))
    var r2 = iter(d); assert_equal(r2.root().field("i").as_int().value(), Int64(-7))
    var r3 = iter(d); assert_true(not r3.root().field("f").as_int(), "float -> None")
    var r4 = iter(d); assert_true(not r4.root().field("s").as_int(), "string -> None")
    var r5 = iter(d); assert_true(not r5.root().field("b").as_int(), "bool -> None")
    var r6 = iter(d); assert_true(not r6.root().field("n").as_int(), "null -> None")

def test_as_int_malformed_and_oor_raise() raises:
    for ref bad in [String("1.5x"), String("12.3.4"), String("01"), String("1."), String("1e")]:
        var rdr = iter(String('{"v":') + bad + String("}"))
        var raised = False
        try:
            _ = rdr.root().field("v").as_int()
        except:
            raised = True
        assert_true(raised, "as_int must raise on malformed: " + bad)
    var rf = iter(String('{"v":1.5}'))
    assert_true(not rf.root().field("v").as_int(), "clean 1.5 -> None")
    var ro = iter(String('{"v":9223372036854775808}'))
    var raised2 = False
    try:
        _ = ro.root().field("v").as_int()
    except:
        raised2 = True
    assert_true(raised2, "as_int out of range must raise")

def test_as_uint_as_float() raises:
    var r1 = iter(String('{"v":42}')); assert_equal(r1.root().field("v").as_uint().value(), UInt64(42))
    var r2 = iter(String('{"v":-7}')); assert_true(not r2.root().field("v").as_uint(), "negative -> None")
    var r3 = iter(String('{"v":1.5}')); assert_true(not r3.root().field("v").as_uint(), "float -> None")
    var r4 = iter(String('{"v":42}'))
    assert_equal(r4.root().field("v").as_float().value(), Float64(42.0))
    var r5 = iter(String('{"v":1.5x}'))
    var raised = False
    try:
        _ = r5.root().field("v").as_float()
    except:
        raised = True
    assert_true(raised, "as_float must raise on trailing junk")

def test_as_string_as_bool() raises:
    var r1 = iter(String('{"v":"hi"}')); assert_equal(r1.root().field("v").as_string().value(), String("hi"))
    var r2 = iter(String('{"v":42}')); assert_true(not r2.root().field("v").as_string(), "non-string -> None")
    var r3 = iter(String('{"v":true}')); assert_true(r3.root().field("v").as_bool().value(), "bool")
    var r4 = iter(String('{"v":42}')); assert_true(not r4.root().field("v").as_bool(), "non-bool -> None")
    var r5 = iter(String('{"v":"\\x"}'))
    var raised = False
    try:
        _ = r5.root().field("v").as_string()
    except:
        raised = True
    assert_true(raised, "as_string must raise on a bad escape")


def test_literal_trailing_junk_raises() raises:
    """Glued-junk literals (`truex`/`falsey`/`nullx`) must RAISE, not be masked.

    `_validate_true/false/null` check only the fixed keyword bytes; without a
    terminator guard the lazy accessors would accept the leading literal and drop
    the junk silently. get_bool, is_null, AND the as_bool opt-in must all raise.
    """
    var rt = iter(String('{"v":truex}'))
    var raised_t = False
    try:
        _ = rt.root().field("v").get_bool()
    except:
        raised_t = True
    assert_true(raised_t, "get_bool on truex must raise")

    var rf = iter(String('{"v":falsey}'))
    var raised_f = False
    try:
        _ = rf.root().field("v").get_bool()
    except:
        raised_f = True
    assert_true(raised_f, "get_bool on falsey must raise")

    var rn = iter(String('{"v":nullx}'))
    var raised_n = False
    try:
        _ = rn.root().field("v").is_null()
    except:
        raised_n = True
    assert_true(raised_n, "is_null on nullx must raise")

    var rb = iter(String('{"v":truex}'))
    var raised_b = False
    try:
        _ = rb.root().field("v").as_bool()
    except:
        raised_b = True
    assert_true(raised_b, "as_bool on truex must raise, not mask as Some")

    # clean literals are unaffected
    var rc = iter(String('{"t":true,"f":false,"n":null}'))
    assert_true(rc.root().field("t").get_bool(), "clean true")
    var rc2 = iter(String('{"t":true,"f":false,"n":null}'))
    assert_true(not rc2.root().field("f").get_bool(), "clean false")
    var rc3 = iter(String('{"t":true,"f":false,"n":null}'))
    assert_true(rc3.root().field("n").is_null(), "clean null")


def main() raises:
    test_has_field()
    test_has_field_nonobject_raises()
    test_try_field_present_absent_null()
    test_try_field_nonobject_raises()
    test_try_elem_present_absent_nonarray()
    test_as_int_wrong_kind_none()
    test_as_int_malformed_and_oor_raise()
    test_as_uint_as_float()
    test_as_string_as_bool()
    test_literal_trailing_junk_raises()
    print("test_error_model: all passed")
