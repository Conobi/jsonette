"""On-Demand (lazy) parser — forward object iteration + escape-aware keys.

These tests exercise the M1 iteration surface through inference ONLY: a caller
obtains the root object navigator from `iter(...).root().get_object()`, then walks
the root object's TOP-LEVEL fields in document order via `at_end()` /
`next_field()`, reading each `Field`'s unescaped `key()` and its `value()` leaf —
without ever naming any `[o]`-parametric type. They also lock in key-escape-aware
matching: a key with a JSON escape must compare correctly against an
already-unescaped Mojo search key, both in `field` and in `Field.key()`.
"""

from std.testing import assert_equal, assert_true
from jsonette.ondemand.reader import iter


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def test_iter_yields_fields_in_order() raises:
    """Forward iteration yields exactly the top-level fields a,b,c in order."""
    var data = _make_bytes(String('{"a":1,"b":"x","c":true}'))
    var rdr = iter(data)
    var root = rdr.root().get_object()

    assert_true(not root.at_end(), "fresh non-empty object must not be at_end")
    var f0 = root.next_field()
    assert_equal(f0.key(), String("a"))
    assert_equal(f0.value().get_int(), Int64(1))

    var f1 = root.next_field()
    assert_equal(f1.key(), String("b"))
    assert_equal(f1.value().get_string(), String("x"))

    var f2 = root.next_field()
    assert_equal(f2.key(), String("c"))
    assert_equal(f2.value().get_bool(), True)

    assert_true(root.at_end(), "cursor must be at_end after the last field")


def test_iter_skips_nested_values() raises:
    """Iteration is TOP-LEVEL only: nested object/array values are skipped whole.

    `{"a":{"n":1},"b":2,"c":[1,2]}` yields keys a,b,c — never the nested "n" —
    and b's value is 2.
    """
    var data = _make_bytes(String('{"a":{"n":1},"b":2,"c":[1,2]}'))
    var rdr = iter(data)
    var root = rdr.root().get_object()

    var f0 = root.next_field()
    assert_equal(f0.key(), String("a"))

    var f1 = root.next_field()
    assert_equal(f1.key(), String("b"))
    assert_equal(f1.value().get_int(), Int64(2))

    var f2 = root.next_field()
    assert_equal(f2.key(), String("c"))

    assert_true(root.at_end(), "cursor must be at_end after the last top-level field")


def test_iter_empty_object_at_end_immediately() raises:
    """An empty object is at_end immediately and yields zero fields."""
    var data = _make_bytes(String("{}"))
    var rdr = iter(data)
    var root = rdr.root().get_object()
    assert_true(root.at_end(), "empty object must be at_end immediately")


def test_field_escaped_key_matches() raises:
    """A key containing a JSON escape (`a\\nb`) is matched by field.

    Source key is `"a\\nb"` (a, newline, b after unescaping). The search key is
    the already-unescaped 3-char Mojo String a<newline>b; it must match.
    """
    var data = _make_bytes(String('{"a\\nb":1}'))
    var rdr = iter(data)
    var search = String("a") + chr(10) + String("b")  # a, newline, b
    assert_equal(rdr.root().field(search).get_int(), Int64(1))


def test_field_plain_key_still_matches() raises:
    """The byte-compare fast path still matches a plain (escape-free) key."""
    var data = _make_bytes(String('{"plain":7,"a\\nb":1}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("plain")).get_int(), Int64(7))


def test_field_key_unescaped() raises:
    """Field.key() returns the UNESCAPED key for an escaped-key field."""
    var data = _make_bytes(String('{"a\\nb":1}'))
    var rdr = iter(data)
    var root = rdr.root().get_object()
    var f = root.next_field()
    var expected = String("a") + chr(10) + String("b")  # a, newline, b
    assert_equal(f.key(), expected)


def main() raises:
    test_iter_yields_fields_in_order()
    test_iter_skips_nested_values()
    test_iter_empty_object_at_end_immediately()
    test_field_escaped_key_matches()
    test_field_plain_key_still_matches()
    test_field_key_unescaped()
    print("test_iteration: all passed")
