"""Leaf parity: the SAME single in-order navigation reads identically through the
DOM and the On-Demand reader (the spec's parity contract — in-order only)."""

from std.testing import assert_equal, assert_true
from jsonette.document import parse
from jsonette.ondemand.reader import iter


def test_get_int_parity() raises:
    var doc = parse(String('{"age":42}'))
    var rdr = iter(String('{"age":42}'))
    assert_equal(doc.root().field("age").get_int(), Int64(42))
    assert_equal(rdr.root().field("age").get_int(), Int64(42))

def test_get_float_parity() raises:
    var doc = parse(String('{"x":42}'))
    var rdr = iter(String('{"x":42}'))
    assert_equal(doc.root().field("x").get_float(), Float64(42.0))
    assert_equal(rdr.root().field("x").get_float(), Float64(42.0))

def test_as_int_parity_and_none() raises:
    var doc = parse(String('{"u":42,"f":1.5}'))
    var rdr = iter(String('{"u":42,"f":1.5}'))
    assert_equal(doc.root().field("u").as_int().value(), Int64(42))
    assert_equal(rdr.root().field("u").as_int().value(), Int64(42))
    var doc2 = parse(String('{"u":42,"f":1.5}'))
    var rdr2 = iter(String('{"u":42,"f":1.5}'))
    assert_true(not doc2.root().field("f").as_int(), "DOM float -> None")
    assert_true(not rdr2.root().field("f").as_int(), "OD float -> None")

def test_try_field_parity() raises:
    var doc = parse(String('{"a":1}'))
    var rdr = iter(String('{"a":1}'))
    assert_true(Bool(doc.root().try_field("a")), "DOM present")
    assert_true(Bool(rdr.root().try_field("a")), "OD present")
    var doc2 = parse(String('{"a":1}'))
    var rdr2 = iter(String('{"a":1}'))
    assert_true(not doc2.root().try_field("zzz"), "DOM absent None")
    assert_true(not rdr2.root().try_field("zzz"), "OD absent None")


def main() raises:
    test_get_int_parity()
    test_get_float_parity()
    test_as_int_parity_and_none()
    test_try_field_parity()
    print("test_leaf_parity: all passed")
