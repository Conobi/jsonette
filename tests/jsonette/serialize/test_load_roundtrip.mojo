"""Round-trip `load[T](dumps(x))` (field-wise), edge cases, and the Optional-prefix
self-test (guards the missing-key policy against a future stdlib rename)."""
from std.testing import assert_equal, assert_true
from std.reflection import reflect
from std.collections import Optional, Dict
from jsonette.serialize.reflect_loader import load, JsonDeserializable
from jsonette.serialize import dumps, JsonSerializable


struct RInner(Copyable, Movable, Defaultable, JsonSerializable, JsonDeserializable):
    var x: Int64
    var label: String
    def __init__(out self):
        self.x = 0; self.label = String("")


struct RAll(Copyable, Movable, Defaultable, JsonSerializable, JsonDeserializable):
    var name: String
    var count: Int64
    var ratio: Float64
    var flag: Bool
    var inner: RInner
    var tags: List[String]
    var opt: Optional[Int64]
    var meta: Dict[String, Int64]
    def __init__(out self):
        self.name = String(""); self.count = 0; self.ratio = 0.0; self.flag = False
        self.inner = RInner(); self.tags = List[String](); self.opt = None
        self.meta = Dict[String, Int64]()


def test_optional_prefix_selftest() raises:
    assert_true(
        reflect[Optional[Int64]].name().startswith("std.collections.optional.Optional["),
        "Optional reflected-name prefix changed — load[T]'s missing-key policy must be updated",
    )


def test_roundtrip_fieldwise() raises:
    var x = RAll()
    x.name = String("jsonette"); x.count = 42; x.ratio = 0.1 + 0.2; x.flag = True
    x.inner.x = 7; x.inner.label = String("hi")
    x.tags.append(String("a")); x.tags.append(String("b"))
    x.opt = Optional[Int64](99)
    x.meta[String("k")] = Int64(5)

    var js = dumps(x)
    var y = load[RAll](js)

    assert_equal(y.name, x.name)
    assert_equal(y.count, x.count)
    assert_equal(y.ratio, x.ratio)  # Float64 bit-exact round-trip
    assert_equal(y.flag, x.flag)
    assert_equal(y.inner.x, x.inner.x)
    assert_equal(y.inner.label, x.inner.label)
    assert_equal(len(y.tags), 2)
    assert_equal(y.tags[0], String("a")); assert_equal(y.tags[1], String("b"))
    assert_true(Bool(y.opt) and y.opt.value() == Int64(99), "opt round-trip")
    assert_equal(y.meta[String("k")], Int64(5))


def test_unicode_escaped_key() raises:
    # An escaped key in JSON matches by its unescaped form ("label" == "label").
    var w = load[RInner](String('{"x":1,"lab\\u0065l":"ok"}'))
    assert_equal(w.label, String("ok"))


def test_duplicate_keys_first_wins() raises:
    var f = load[RInner](String('{"x":1,"label":"first","label":"second"}'))
    assert_equal(f.label, String("first"))


def main() raises:
    test_optional_prefix_selftest()
    test_roundtrip_fieldwise()
    test_unicode_escaped_key()
    test_duplicate_keys_first_wins()
    print("test_load_roundtrip: all passed")
