from std.testing import assert_equal
from simdjson.serialize.reflect_writer import dumps, JsonSerializable
from simdjson.serialize.writer import JsonWriter


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


def main() raises:
    test_primitives_and_nested()
    test_pretty()
    test_containers_and_override()
    test_dict()
    print("test_reflect: all passed")
