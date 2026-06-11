from std.testing import assert_equal
from jsonette.serialize.reflect_writer import dumps, JsonSerializable
from jsonette.serialize.writer import JsonWriter


@fieldwise_init
struct Inner(Copyable, Movable):
    var a: Int
    var b: Bool


@fieldwise_init
struct Outer(Copyable, Movable):
    var name: String
    var inner: Inner
    var score: Float64


def test_primitives_and_nested() raises:
    assert_equal(dumps(Outer("hi", Inner(7, True), 2.5)),
                 String('{"name":"hi","inner":{"a":7,"b":true},"score":2.5}'))


def test_pretty() raises:
    var got = dumps(Inner(1, False), indent=String("  "))
    assert_equal(got, String('{') + chr(10) + '  "a": 1,' + chr(10) + '  "b": false' + chr(10) + '}')


@fieldwise_init
struct Money(JsonSerializable, Copyable, Movable):
    var cents: Int
    def write_json(self, mut w: JsonWriter) raises:
        w.raw(String(self.cents) + ".00")


@fieldwise_init
struct Bag(Copyable, Movable):
    var tags: List[String]
    var maybe: Optional[Int]
    var price: Money


def test_containers_and_override() raises:
    assert_equal(dumps(Bag(["x", "y"], Optional[Int](7), Money(150))),
                 String('{"tags":["x","y"],"maybe":7,"price":150.00}'))
    assert_equal(dumps(Bag(List[String](), None, Money(0))),
                 String('{"tags":[],"maybe":null,"price":0.00}'))


def test_dict() raises:
    var d = Dict[String, Int]()
    d["k"] = 1
    assert_equal(dumps(d), String('{"k":1}'))


@fieldwise_init
struct HasFloat(Copyable, Movable):
    var f: Float64


def test_non_finite_raises() raises:
    """Non-finite float fields (Inf, NaN) must raise — JSON (RFC 8259) has no
    representation for infinity or not-a-number."""
    from std.testing import assert_true
    var inf = Float64(1.0) / Float64(0.0)
    var raised = False
    try:
        _ = dumps(HasFloat(inf))
    except:
        raised = True
    assert_true(raised)


def test_cpython_parity() raises:
    """Output matches json.dumps(ensure_ascii=False, separators=(",",":"))
    for nested structs with escaped characters and custom serializers."""
    assert_equal(dumps(Outer("a\"b", Inner(0, False), 1.0)),
                 String('{"name":"a\\"b","inner":{"a":0,"b":false},"score":1.0}'))
    assert_equal(dumps(Money(150)), String("150.00"))


def test_dict_multikey() raises:
    """Dict serialises in insertion order (Mojo Dict is insertion-ordered)."""
    var d = Dict[String, Int]()
    d["b"] = 1
    d["a"] = 2
    assert_equal(dumps(d), String('{"b":1,"a":2}'))


@fieldwise_init
struct Nums(Copyable, Movable):
    var i8: Int8
    var i16: Int16
    var i32: Int32
    var u8: UInt8
    var u16: UInt16
    var u32: UInt32
    var u64: UInt64
    var f32: Float32


def test_sized_numerics() raises:
    """All sized integer and float types (Int8/16/32, UInt8/16/32/64, Float32)
    must be dispatched correctly by the reflection writer without truncation,
    sign errors, or missing branches."""
    var n = Nums(Int8(-128), Int16(-32768), Int32(-2000000000),
                 UInt8(255), UInt16(65535), UInt32(4000000000),
                 UInt64(18446744073709551615), Float32(1.5))
    assert_equal(dumps(n),
                 String('{"i8":-128,"i16":-32768,"i32":-2000000000,"u8":255,"u16":65535,"u32":4000000000,"u64":18446744073709551615,"f32":1.5}'))


def main() raises:
    test_primitives_and_nested()
    test_pretty()
    test_containers_and_override()
    test_dict()
    test_non_finite_raises()
    test_cpython_parity()
    test_dict_multikey()
    test_sized_numerics()
    print("test_reflect: all passed")
