"""Pythonic surface: Value dunders + Document facade (Q1)."""
from std.testing import assert_equal, assert_true
from jsonette.document import parse


def test_eq_vs_string() raises:
    var doc = parse(String('{"type":"user","name":"Ada","n":5}'))
    var r = doc.root()
    assert_true(r.field("type") == "user", "string equals literal")
    assert_true(r.field("type") != "admin", "string not-equals literal")
    # total: non-string receiver compares False, never raises
    assert_true(not (r.field("n") == "5"), "number is not equal to a string")
    assert_true(r.field("n") != "5", "number != string is True")


def test_contains() raises:
    var doc = parse(String('{"a":1,"b":null,"nested":{"x":9}}'))
    var r = doc.root()
    assert_true("a" in r, "present key")
    assert_true("b" in r, "present key with null value")
    assert_true(not ("z" in r), "absent key")
    # total: non-object receiver → False, never raises
    assert_true(not ("a" in r.field("a")), "contains on a number is False")


def main() raises:
    test_eq_vs_string()
    test_contains()
    print("test_pythonic_surface: all passed")
