"""On-Demand (lazy) parser — remaining leaf accessors and type predicates.

These tests exercise the additional `Value` surface beyond M0's
`get_string`/`get_int`: the unsigned, double, bool, and null accessors plus the
no-parse byte predicates. Like the M0 tests they go through inference ONLY — a
caller obtains the root handle from `iter(...).root()`, navigates with
`field(key)`, and reads or inspects a leaf without ever naming any
`[o]`-parametric type.
"""

from std.testing import assert_equal, assert_true, assert_false
from jsonette.ondemand.reader import iter


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def test_get_uint_uint64_max() raises:
    """A uint64-max value is returned exactly by get_uint."""
    var data = _make_bytes(String('{"a":18446744073709551615}'))
    var rdr = iter(data)
    assert_equal(
        rdr.root().field(String("a")).get_uint(), UInt64(18446744073709551615)
    )


def test_get_uint_negative_raises() raises:
    """A negative integer cannot be unsigned, so get_uint raises."""
    var data = _make_bytes(String('{"a":-1}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("a")).get_uint()
    except:
        raised = True
    assert_true(raised, "get_uint on a negative integer must raise")


def test_get_uint_small_positive() raises:
    """A small non-negative integer is returned by get_uint."""
    var data = _make_bytes(String('{"a":1}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("a")).get_uint(), UInt64(1))


def test_get_uint_on_float_raises() raises:
    """A float value cannot be unsigned, so get_uint raises."""
    var data = _make_bytes(String('{"a":1.5}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("a")).get_uint()
    except:
        raised = True
    assert_true(raised, "get_uint on a float must raise")


def test_get_float_float() raises:
    """A float value is returned by get_float."""
    var data = _make_bytes(String('{"a":1.5}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("a")).get_float(), Float64(1.5))


def test_get_float_int() raises:
    """An integer value widens to Float64 via get_float."""
    var data = _make_bytes(String('{"a":42}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("a")).get_float(), Float64(42.0))


def test_get_float_uint64() raises:
    """A uint64-tagged integer widens to Float64 via get_float."""
    var data = _make_bytes(String('{"a":18446744073709551615}'))
    var rdr = iter(data)
    assert_equal(
        rdr.root().field(String("a")).get_float(),
        Float64(18446744073709551615.0),
    )


def test_get_float_on_string_raises() raises:
    """A string value is not a number, so get_float raises."""
    var data = _make_bytes(String('{"a":"x"}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("a")).get_float()
    except:
        raised = True
    assert_true(raised, "get_float on a string must raise")


def test_get_bool_true() raises:
    """A true literal is returned as True by get_bool."""
    var data = _make_bytes(String('{"a":true}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("a")).get_bool(), True)


def test_get_bool_false() raises:
    """A false literal is returned as False by get_bool."""
    var data = _make_bytes(String('{"a":false}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("a")).get_bool(), False)


def test_get_bool_on_int_raises() raises:
    """A non-bool value makes get_bool raise."""
    var data = _make_bytes(String('{"a":1}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("a")).get_bool()
    except:
        raised = True
    assert_true(raised, "get_bool on a non-bool must raise")


def test_is_null_true() raises:
    """A null literal makes is_null return True."""
    var data = _make_bytes(String('{"a":null}'))
    var rdr = iter(data)
    assert_true(rdr.root().field(String("a")).is_null())


def test_is_null_false() raises:
    """A non-null value makes is_null return False, not raise."""
    var data = _make_bytes(String('{"a":1}'))
    var rdr = iter(data)
    assert_false(rdr.root().field(String("a")).is_null())


def test_is_string_predicate() raises:
    """The byte predicate is_string is True for a string and False otherwise."""
    var data = _make_bytes(String('{"a":"x","b":1}'))
    var rdr = iter(data)
    assert_true(rdr.root().field(String("a")).is_string())
    assert_false(rdr.root().field(String("b")).is_string())


def test_is_number_predicate() raises:
    """The byte predicate is_number is True for a number and False otherwise."""
    var data = _make_bytes(String('{"a":1,"b":"x"}'))
    var rdr = iter(data)
    assert_true(rdr.root().field(String("a")).is_number())
    assert_false(rdr.root().field(String("b")).is_number())


def test_is_number_predicate_negative() raises:
    """The byte predicate is_number is True for a negative number."""
    var data = _make_bytes(String('{"a":-3}'))
    var rdr = iter(data)
    assert_true(rdr.root().field(String("a")).is_number())


def test_is_bool_predicate() raises:
    """The byte predicate is_bool is True for true/false and False otherwise."""
    var data = _make_bytes(String('{"a":true,"b":false,"c":1}'))
    var rdr = iter(data)
    assert_true(rdr.root().field(String("a")).is_bool())
    assert_true(rdr.root().field(String("b")).is_bool())
    assert_false(rdr.root().field(String("c")).is_bool())


def test_is_object_predicate() raises:
    """The byte predicate is_object is True for an object and False otherwise."""
    var data = _make_bytes(String('{"a":{},"b":1}'))
    var rdr = iter(data)
    assert_true(rdr.root().field(String("a")).is_object())
    assert_false(rdr.root().field(String("b")).is_object())


def test_is_array_predicate() raises:
    """The byte predicate is_array is True for an array and False otherwise."""
    var data = _make_bytes(String('{"a":[],"b":1}'))
    var rdr = iter(data)
    assert_true(rdr.root().field(String("a")).is_array())
    assert_false(rdr.root().field(String("b")).is_array())


def main() raises:
    test_get_uint_uint64_max()
    test_get_uint_negative_raises()
    test_get_uint_small_positive()
    test_get_uint_on_float_raises()
    test_get_float_float()
    test_get_float_int()
    test_get_float_uint64()
    test_get_float_on_string_raises()
    test_get_bool_true()
    test_get_bool_false()
    test_get_bool_on_int_raises()
    test_is_null_true()
    test_is_null_false()
    test_is_string_predicate()
    test_is_number_predicate()
    test_is_number_predicate_negative()
    test_is_bool_predicate()
    test_is_object_predicate()
    test_is_array_predicate()
    print("test_leaf_types: all passed")
