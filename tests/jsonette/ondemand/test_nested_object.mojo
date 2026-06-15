"""On-Demand (lazy) parser — nested object descent via `get_object()`.

These tests exercise nested-object navigation through inference ONLY: a caller
obtains the root handle from `iter(...).root()`, descends into a nested object
with `field(key).get_object()`, and reads its fields — without ever naming
any `[o]`-parametric type. `Object` is generalized to navigate an object
starting at an arbitrary structural position, so a nested handle iterates only
its OWN fields and stops at its own `}`.
"""

from std.testing import assert_equal, assert_true
from jsonette.ondemand.reader import iter


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def test_get_object_field_string() raises:
    """A nested object's string field is reachable via get_object + field."""
    var data = _make_bytes(
        String('{"u":{"name":"bob","id":7},"n":9}')
    )
    var rdr = iter(data)
    assert_equal(
        rdr.root().field(String("u")).get_object().field(String("name")).get_string(),
        String("bob"),
    )


def test_get_object_field_int() raises:
    """A nested object's integer field is reachable via get_object + field."""
    var data = _make_bytes(
        String('{"u":{"name":"bob","id":7},"n":9}')
    )
    var rdr = iter(data)
    assert_equal(
        rdr.root().field(String("u")).get_object().field(String("id")).get_int(),
        Int64(7),
    )


def test_top_level_field_after_nested_object() raises:
    """A top-level field after a nested object stays reachable from the rdr.root()."""
    var data = _make_bytes(
        String('{"u":{"name":"bob","id":7},"n":9}')
    )
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("n")).get_int(), Int64(9))


def test_get_object_iteration_only_own_fields() raises:
    """Iterating a nested object yields only its own fields, in order.

    `{"u":{"name":"bob","id":7},"n":9}` — the nested object under "u" must
    iterate exactly ["name", "id"] and stop at its own `}` (never reaching the
    top-level "n").
    """
    var data = _make_bytes(
        String('{"u":{"name":"bob","id":7},"n":9}')
    )
    var rdr = iter(data)
    var inner = rdr.root().field(String("u")).get_object()

    var keys = List[String]()
    while not inner.at_end():
        var f = inner.next_field()
        keys.append(f.key())
    assert_equal(len(keys), 2)
    assert_equal(keys[0], String("name"))
    assert_equal(keys[1], String("id"))


def test_get_object_empty_nested_object() raises:
    """An empty nested object iterates zero fields and field raises.

    `{"a":{},"b":1}` — get_object() on "a" yields a handle over `{}` whose
    `_start_si` is the `}`: it iterates no fields and field raises. The
    sibling "b" stays reachable from the rdr.root().
    """
    var data = _make_bytes(String('{"a":{},"b":1}'))
    var rdr = iter(data)

    var inner = rdr.root().field(String("a")).get_object()
    var raised = False
    try:
        _ = inner.field(String("x"))
    except:
        raised = True
    assert_true(raised, "field on an empty nested object must raise")

    var inner2 = rdr.root().field(String("a")).get_object()
    var count = 0
    while not inner2.at_end():
        var f = inner2.next_field()
        _ = f.key()
        count += 1
    assert_equal(count, 0)

    assert_equal(rdr.root().field(String("b")).get_int(), Int64(1))


def test_get_object_three_deep() raises:
    """A 3-deep nested object is reachable via get_object twice + field.

    `{"a":{"b":{"c":42}}}` — descend a -> b, then read c == 42.
    """
    var data = _make_bytes(String('{"a":{"b":{"c":42}}}'))
    var rdr = iter(data)
    assert_equal(
        rdr.root().field(String("a")).get_object().field(String("b")).get_object().field(String("c")).get_int(),
        Int64(42),
    )


def test_get_object_on_non_object_raises() raises:
    """A non-object value read via get_object raises (type guard).

    `{"a":1}` — field("a") points at an integer; get_object must raise
    rather than navigate garbage.
    """
    var data = _make_bytes(String('{"a":1}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("a")).get_object()
    except:
        raised = True
    assert_true(raised, "get_object on a non-object value must raise")


def main() raises:
    test_get_object_field_string()
    test_get_object_field_int()
    test_top_level_field_after_nested_object()
    test_get_object_iteration_only_own_fields()
    test_get_object_empty_nested_object()
    test_get_object_three_deep()
    test_get_object_on_non_object_raises()
    print("test_nested_object: all passed")
