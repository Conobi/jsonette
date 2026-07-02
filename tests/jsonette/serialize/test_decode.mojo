"""Typed loader decode[T]: leaf fields, strict missing-key policy, memory safety."""
from std.testing import assert_equal, assert_true
from std.collections import Optional, Dict
from jsonette.serialize.reflect_loader import decode, JsonDeserializable


struct Flat(Copyable, Movable, Defaultable, JsonDeserializable):
    var name: String
    var count: Int64
    var ratio: Float64
    var flag: Bool
    def __init__(out self):
        self.name = String(""); self.count = 0; self.ratio = 0.0; self.flag = False


def test_flat_leaves() raises:
    var f = decode[Flat](String('{"name":"jsonette","count":42,"ratio":1.5,"flag":true}'))
    assert_equal(f.name, String("jsonette"))
    assert_equal(f.count, Int64(42))
    assert_true(f.ratio > 1.49 and f.ratio < 1.51, "ratio")
    assert_true(f.flag, "flag")


def test_missing_required_leaf_raises() raises:
    var raised = False
    try:
        _ = decode[Flat](String('{"name":"x","count":1,"ratio":1.0}'))
    except:
        raised = True
    assert_true(raised, "absent required leaf must raise MISSING_FIELD")


def test_type_mismatch_raises() raises:
    var raised = False
    try:
        _ = decode[Flat](String('{"name":"x","count":"oops","ratio":1.0,"flag":true}'))
    except:
        raised = True
    assert_true(raised, "string into Int64 field must raise")


def test_int_out_of_range_raises() raises:
    var raised = False
    try:
        _ = decode[Flat](String('{"name":"x","count":9223372036854775808,"ratio":1.0,"flag":true}'))
    except:
        raised = True
    assert_true(raised, "UInt64 above Int64.MAX into Int64 field must raise")


def test_unknown_keys_ignored() raises:
    var f = decode[Flat](String('{"name":"x","count":1,"ratio":1.0,"flag":false,"EXTRA":[1,2,3]}'))
    assert_equal(f.name, String("x"))
    assert_equal(f.count, Int64(1))


def test_midwalk_raise_is_memory_safe() raises:
    var raised = False
    try:
        _ = decode[Flat](String('{"name":"assigned-then-raise"}'))
    except:
        raised = True
    assert_true(raised, "mid-walk raise must be caught cleanly")


struct Narrow(Copyable, Movable, Defaultable, JsonDeserializable):
    var i8: Int8
    var u8: UInt8
    def __init__(out self):
        self.i8 = 0; self.u8 = 0


def test_narrow_int_in_range() raises:
    var n = decode[Narrow](String('{"i8":-128,"u8":255}'))
    assert_equal(n.i8, Int8(-128))
    assert_equal(n.u8, UInt8(255))


def test_narrow_int_overflow_raises() raises:
    """A value outside a narrow field's range must RAISE, never silently wrap."""
    var r1 = False
    try:
        _ = decode[Narrow](String('{"i8":300,"u8":1}'))  # 300 would wrap to 44
    except:
        r1 = True
    assert_true(r1, "300 into Int8 must raise, not wrap to 44")
    var r2 = False
    try:
        _ = decode[Narrow](String('{"i8":0,"u8":300}'))  # 300 would wrap to 44
    except:
        r2 = True
    assert_true(r2, "300 into UInt8 must raise, not wrap")
    var r3 = False
    try:
        _ = decode[Narrow](String('{"i8":0,"u8":-1}'))  # negative into UInt8
    except:
        r3 = True
    assert_true(r3, "-1 into UInt8 must raise")


struct Inner(Copyable, Movable, Defaultable, JsonDeserializable):
    var x: Int64
    var label: String
    def __init__(out self):
        self.x = 0; self.label = String("")


struct HasNested(Copyable, Movable, Defaultable, JsonDeserializable):
    var id: Int64
    var inner: Inner
    def __init__(out self):
        self.id = 0; self.inner = Inner()


def test_nested_struct() raises:
    var h = decode[HasNested](String('{"id":5,"inner":{"x":7,"label":"hi"}}'))
    assert_equal(h.id, Int64(5))
    assert_equal(h.inner.x, Int64(7))
    assert_equal(h.inner.label, String("hi"))


def test_nested_missing_inner_leaf_raises() raises:
    var raised = False
    try:
        _ = decode[HasNested](String('{"id":5,"inner":{"x":7}}'))  # inner.label missing
    except:
        raised = True
    assert_true(raised, "missing leaf inside a nested struct must raise")


def test_absent_nested_struct_raises() raises:
    var raised = False
    try:
        _ = decode[HasNested](String('{"id":5}'))  # whole inner object missing
    except:
        raised = True
    assert_true(raised, "absent required nested struct must raise MISSING_FIELD")


struct WithContainers(Copyable, Movable, Defaultable, JsonDeserializable):
    var tags: List[String]
    var scores: List[Inner]
    var opt_present: Optional[Int64]
    var opt_absent: Optional[Int64]
    var nullable: Optional[String]
    var meta: Dict[String, Int64]
    def __init__(out self):
        self.tags = List[String](); self.scores = List[Inner]()
        self.opt_present = None; self.opt_absent = None; self.nullable = None
        self.meta = Dict[String, Int64]()


def test_containers() raises:
    var w = decode[WithContainers](String(
        '{"tags":["a","b","c"],'
        '"scores":[{"x":1,"label":"one"},{"x":2,"label":"two"}],'
        '"opt_present":99,"nullable":null,"meta":{"k1":10,"k2":20}}'
    ))
    assert_equal(len(w.tags), 3)
    assert_equal(w.tags[0], String("a")); assert_equal(w.tags[2], String("c"))
    assert_equal(len(w.scores), 2)
    assert_equal(w.scores[0].x, Int64(1)); assert_equal(w.scores[1].label, String("two"))
    assert_true(Bool(w.opt_present) and w.opt_present.value() == Int64(99), "opt_present")
    assert_true(not w.opt_absent, "opt_absent -> None (absent key)")
    assert_true(not w.nullable, "nullable -> None (explicit JSON null)")
    assert_equal(w.meta["k1"], Int64(10)); assert_equal(w.meta["k2"], Int64(20))


def test_empty_containers() raises:
    var w = decode[WithContainers](String('{"tags":[],"scores":[],"opt_present":1,"meta":{}}'))
    assert_equal(len(w.tags), 0)
    assert_equal(len(w.scores), 0)
    assert_equal(len(w.meta), 0)


def test_absent_list_raises() raises:
    var raised = False
    try:
        _ = decode[WithContainers](String('{"scores":[],"opt_present":1,"meta":{}}'))  # tags missing
    except:
        raised = True
    assert_true(raised, "absent required List must raise (wrap in Optional to tolerate)")


struct HasF32(Copyable, Movable, Defaultable, JsonDeserializable):
    var f: Float32
    def __init__(out self):
        self.f = 0.0


def test_float32_in_range() raises:
    var h = decode[HasF32](String('{"f":1.5}'))
    assert_true(h.f > 1.49 and h.f < 1.51, "float32 in range")


def test_float32_overflow_raises() raises:
    """A finite JSON double that overflows Float32 must RAISE, not become +inf."""
    var raised = False
    try:
        _ = decode[HasF32](String('{"f":1e40}'))  # > Float32.MAX -> would be +inf
    except:
        raised = True
    assert_true(raised, "1e40 into Float32 must raise, not silently become inf")


def main() raises:
    test_flat_leaves()
    test_missing_required_leaf_raises()
    test_type_mismatch_raises()
    test_int_out_of_range_raises()
    test_unknown_keys_ignored()
    test_midwalk_raise_is_memory_safe()
    test_narrow_int_in_range()
    test_narrow_int_overflow_raises()
    test_nested_struct()
    test_nested_missing_inner_leaf_raises()
    test_absent_nested_struct_raises()
    test_containers()
    test_empty_containers()
    test_absent_list_raises()
    test_float32_in_range()
    test_float32_overflow_raises()
    print("test_decode: all passed")
