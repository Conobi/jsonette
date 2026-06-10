from std.testing import assert_equal
from simdjson.serialize.reflect_writer import dumps, JsonSerializable


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


def main() raises:
    test_primitives_and_nested()
    test_pretty()
    print("test_reflect: core passed")
