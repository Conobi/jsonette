"""On-Demand (lazy) parser — array navigation via `get_array()` + ArrayHandle.

These tests exercise array navigation through inference ONLY: a caller obtains
the root handle from `Parser.iter(...)`, descends into an array value with
`find_field(key).get_array()`, and walks its elements with `at_end()` /
`next_element()` — without ever naming any `[o]`-parametric type. Each element
is a `ValueHandle`, so leaves, nested objects, and nested arrays are reachable
the same way as anywhere else. Elements are skipped depth-aware, so the handle
stops at its own `]`.
"""

from std.testing import assert_equal, assert_true
from jsonette.parser import Parser


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def test_array_of_ints_in_order() raises:
    """An int array iterates exactly 1,2,3 in order, then is at_end."""
    var data = _make_bytes(String('{"xs":[1,2,3]}'))
    var parser = Parser()
    var root = parser.iter(data)
    var xs = root.find_field(String("xs")).get_array()

    var got = List[Int64]()
    while not xs.at_end():
        got.append(xs.next_element().get_int())
    assert_equal(len(got), 3)
    assert_equal(got[0], Int64(1))
    assert_equal(got[1], Int64(2))
    assert_equal(got[2], Int64(3))
    assert_true(xs.at_end(), "cursor must be at_end after the last element")


def test_array_mixed_leaf_types() raises:
    """A mixed array yields int, string, bool, null at indices 0..3."""
    var data = _make_bytes(String('{"xs":[1,"a",true,null]}'))
    var parser = Parser()
    var root = parser.iter(data)
    var xs = root.find_field(String("xs")).get_array()

    var e0 = xs.next_element()
    assert_equal(e0.get_int(), Int64(1))
    var e1 = xs.next_element()
    assert_equal(e1.get_string(), String("a"))
    var e2 = xs.next_element()
    assert_equal(e2.get_bool(), True)
    var e3 = xs.next_element()
    assert_true(e3.is_null(), "element 3 must be the null literal")
    assert_true(xs.at_end(), "cursor must be at_end after four elements")


def test_array_of_objects() raises:
    """Each element of an object-array exposes its own field via get_object.

    `{"xs":[{"k":1},{"k":2}]}` — element 0's k == 1, element 1's k == 2.
    """
    var data = _make_bytes(String('{"xs":[{"k":1},{"k":2}]}'))
    var parser = Parser()
    var root = parser.iter(data)
    var xs = root.find_field(String("xs")).get_array()

    var got = List[Int64]()
    while not xs.at_end():
        var elem = xs.next_element()
        got.append(elem.get_object().find_field(String("k")).get_int())
    assert_equal(len(got), 2)
    assert_equal(got[0], Int64(1))
    assert_equal(got[1], Int64(2))


def test_array_of_arrays() raises:
    """Nested arrays iterate independently: [[1,2],[3]] → 1,2 then 3.

    `{"xs":[[1,2],[3]]}` — the outer array yields two inner arrays; each is
    iterated via its own ArrayHandle (independent aliasing handles are OK).
    """
    var data = _make_bytes(String('{"xs":[[1,2],[3]]}'))
    var parser = Parser()
    var root = parser.iter(data)
    var xs = root.find_field(String("xs")).get_array()

    var flat = List[Int64]()
    while not xs.at_end():
        var inner = xs.next_element().get_array()
        while not inner.at_end():
            flat.append(inner.next_element().get_int())
    assert_equal(len(flat), 3)
    assert_equal(flat[0], Int64(1))
    assert_equal(flat[1], Int64(2))
    assert_equal(flat[2], Int64(3))


def test_array_empty() raises:
    """An empty array is at_end immediately and yields zero elements."""
    var data = _make_bytes(String('{"xs":[]}'))
    var parser = Parser()
    var root = parser.iter(data)
    var xs = root.find_field(String("xs")).get_array()
    assert_true(xs.at_end(), "empty array must be at_end immediately")

    var count = 0
    while not xs.at_end():
        _ = xs.next_element()
        count += 1
    assert_equal(count, 0)


def test_get_array_on_non_array_raises() raises:
    """Calling get_array on a non-array value raises (type guard).

    `{"a":1}` — find_field("a") points at an integer; get_array must raise
    rather than navigate garbage.
    """
    var data = _make_bytes(String('{"a":1}'))
    var parser = Parser()
    var root = parser.iter(data)
    var raised = False
    try:
        _ = root.find_field(String("a")).get_array()
    except:
        raised = True
    assert_true(raised, "get_array on a non-array value must raise")


def test_array_truncated_terminates_cleanly() raises:
    """A truncated array terminates cleanly under -D ASSERT=all (no OOB/crash).

    `{"xs":[1,2` — get_array() then iterating must not read positions out of
    range: it either yields the readable prefix and reaches at_end, or raises,
    but never crashes.
    """
    var data = _make_bytes(String('{"xs":[1,2'))
    var parser = Parser()
    var root = parser.iter(data)
    var xs = root.find_field(String("xs")).get_array()

    var count = 0
    var raised = False
    try:
        while not xs.at_end() and count < 100:
            _ = xs.next_element()
            count += 1
    except:
        raised = True
    # Either path is acceptable; the load-bearing property is no OOB/crash.
    assert_true(
        raised or count <= 2,
        "truncated array must terminate cleanly without OOB",
    )


def main() raises:
    test_array_of_ints_in_order()
    test_array_mixed_leaf_types()
    test_array_of_objects()
    test_array_of_arrays()
    test_array_empty()
    test_get_array_on_non_array_raises()
    test_array_truncated_terminates_cleanly()
    print("test_array: all passed")
