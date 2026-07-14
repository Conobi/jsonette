"""Tape-free decode: flat struct with leaf fields, hash dispatch, required-field enforcement."""
from std.testing import assert_equal, assert_true
from std.memory import bitcast
from jsonette.serialize.direct_decode import decode_direct
from jsonette.serialize.reflect_loader import decode as decode_dom, JsonDeserializable


struct Flat(Copyable, Movable, Defaultable):
    var name: String
    var count: Int64
    var ratio: Float64
    var flag: Bool
    def __init__(out self):
        self.name = String(""); self.count = 0; self.ratio = 0.0; self.flag = False


def test_flat_leaves() raises:
    var f = decode_direct[Flat](String('{"name":"jsonette","count":42,"ratio":1.5,"flag":true}'))
    assert_equal(f.name, String("jsonette"))
    assert_equal(f.count, Int64(42))
    assert_true(f.ratio > 1.49 and f.ratio < 1.51, "ratio")
    assert_true(f.flag, "flag")


def test_missing_required_raises() raises:
    var raised = False
    try:
        _ = decode_direct[Flat](String('{"name":"x","count":1,"ratio":1.0}'))
    except:
        raised = True
    assert_true(raised, "absent required field must raise")


def test_unknown_keys_skipped() raises:
    var f = decode_direct[Flat](String('{"name":"x","count":1,"ratio":1.0,"flag":false,"EXTRA":[1,2,3]}'))
    assert_equal(f.name, String("x"))
    assert_equal(f.count, Int64(1))


def test_type_mismatch_raises() raises:
    var raised = False
    try:
        _ = decode_direct[Flat](String('{"name":"x","count":"oops","ratio":1.0,"flag":true}'))
    except:
        raised = True
    assert_true(raised, "string into Int64 must raise")


struct NarrowDirect(Copyable, Movable, Defaultable):
    var i8: Int8
    var u8: UInt8
    def __init__(out self):
        self.i8 = 0; self.u8 = 0


def test_narrow_int_in_range() raises:
    var n = decode_direct[NarrowDirect](String('{"i8":-128,"u8":255}'))
    assert_equal(n.i8, Int8(-128))
    assert_equal(n.u8, UInt8(255))


def test_narrow_int_overflow_raises() raises:
    var r1 = False
    try:
        _ = decode_direct[NarrowDirect](String('{"i8":300,"u8":1}'))
    except:
        r1 = True
    assert_true(r1, "300 into Int8 must raise")


def test_empty_object_raises() raises:
    var raised = False
    try:
        _ = decode_direct[Flat](String('{}'))
    except:
        raised = True
    assert_true(raised, "empty object must raise MISSING_FIELD for all required fields")


def test_root_not_object_raises() raises:
    var raised = False
    try:
        _ = decode_direct[Flat](String('[1,2,3]'))
    except:
        raised = True
    assert_true(raised, "array root must raise")


def test_escaped_string_value() raises:
    var f = decode_direct[Flat](String('{"name":"hello\\nworld","count":0,"ratio":0.0,"flag":false}'))
    assert_equal(f.name, String("hello\nworld"))


struct OracleFlat(Copyable, Movable, Defaultable, JsonDeserializable):
    """Flat struct conforming to both Defaultable (for decode_direct) and
    JsonDeserializable (for DOM decode), used by the differential oracle."""
    var name: String
    var count: Int64
    var ratio: Float64
    var flag: Bool
    def __init__(out self):
        self.name = String(""); self.count = 0; self.ratio = 0.0; self.flag = False


def test_differential_oracle() raises:
    """Assert tape-free decode produces identical output to DOM decode on valid inputs."""
    var inputs = List[String]()
    inputs.append(String('{"name":"a","count":0,"ratio":0.0,"flag":false}'))
    inputs.append(String('{"flag":true,"ratio":3.14,"count":-99,"name":"reversed order"}'))
    inputs.append(String('{"name":"with spaces","count":1000000,"ratio":-0.001,"flag":true}'))
    inputs.append(String('{"name":"","count":0,"ratio":0.0,"flag":false}'))
    inputs.append(String('{"name":"esc\\nape","count":42,"ratio":1e10,"flag":false}'))
    inputs.append(String('{"name":"x","count":9223372036854775807,"ratio":1.7976931348623157e+308,"flag":true,"EXTRA":"ignored"}'))

    for idx in range(len(inputs)):
        var json = inputs[idx]
        var dom = decode_dom[OracleFlat](json)
        var direct = decode_direct[OracleFlat](json)
        assert_equal(dom.name, direct.name)
        assert_equal(dom.count, direct.count)
        assert_true(dom.ratio == direct.ratio, "ratio mismatch on input " + String(idx))
        assert_true(dom.flag == direct.flag, "flag mismatch on input " + String(idx))


def main() raises:
    test_flat_leaves()
    test_missing_required_raises()
    test_unknown_keys_skipped()
    test_type_mismatch_raises()
    test_narrow_int_in_range()
    test_narrow_int_overflow_raises()
    test_empty_object_raises()
    test_root_not_object_raises()
    test_escaped_string_value()
    test_differential_oracle()
    print("test_direct_decode: all passed")
