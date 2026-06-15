"""On-Demand (lazy) parser — M0: flat top-level object, lazy leaf reads.

These tests exercise the M0 surface through inference ONLY: a caller obtains the
root handle from `iter(...).root()`, navigates with `field(key)`, and reads
a leaf with `get_string()` / `get_int()` — without ever naming any `[o]`-
parametric type. That constraint is the contract: the public entry returns a
type used by inference, like `iter(...)` itself.
"""

from std.testing import assert_equal, assert_true
from jsonette.ondemand.reader import iter


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def test_field_get_string() raises:
    """A string value found by key is returned unescaped."""
    var data = _make_bytes(String('{"name":"hello","age":42,"city":"paris"}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("name")).get_string(), String("hello"))


def test_field_get_string_last_field() raises:
    """The last field of a flat object is reachable by key."""
    var data = _make_bytes(String('{"name":"hello","age":42,"city":"paris"}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("city")).get_string(), String("paris"))


def test_field_get_int() raises:
    """An integer value found by key is parsed to Int64."""
    var data = _make_bytes(String('{"name":"hello","age":42,"city":"paris"}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("age")).get_int(), Int64(42))


def test_field_missing_raises() raises:
    """An absent key raises from field."""
    var data = _make_bytes(String('{"name":"hello","age":42,"city":"paris"}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("missing"))
    except:
        raised = True
    assert_true(raised, "field on a missing key must raise")


def test_iter_reused_across_parses() raises:
    """A Reader reused via reparse reuses warm buffers and still reads."""
    var first = _make_bytes(String('{"name":"hello","age":42,"city":"paris"}'))
    var rdr = iter(first)
    assert_equal(rdr.root().field(String("name")).get_string(), String("hello"))

    var second = _make_bytes(String('{"greeting":"bonjour","count":7}'))
    rdr.reparse(second)
    assert_equal(
        rdr.root().field(String("greeting")).get_string(), String("bonjour")
    )
    assert_equal(rdr.root().field(String("count")).get_int(), Int64(7))


def test_field_skips_nested_object() raises:
    """A nested object value must NOT leak its inner keys to the top level.

    `{"outer":{"target":111},"target":222}` — field("target") must match the
    TOP-LEVEL "target" (222), never the nested one (111).
    """
    var data = _make_bytes(
        String('{"outer":{"target":111},"target":222}')
    )
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("target")).get_int(), Int64(222))


def test_field_sibling_after_nested_object() raises:
    """A sibling key after a nested object must remain reachable (no desync)."""
    var data = _make_bytes(String('{"a":{"x":1,"y":2},"b":7}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("b")).get_int(), Int64(7))


def test_field_sibling_after_array() raises:
    """A sibling key after an array value must remain reachable (array skipped)."""
    var data = _make_bytes(String('{"a":[1,2,3],"b":"z"}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("b")).get_string(), String("z"))


def test_field_empty_object_raises() raises:
    """An empty object yields no fields, so field raises."""
    var data = _make_bytes(String("{}"))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("x"))
    except:
        raised = True
    assert_true(raised, "field on empty object must raise")


def test_field_truncated_no_value_raises() raises:
    """A key with no value (truncated `{\"a\":`) raises, never reads OOB.

    Run under -D ASSERT=all: bounds checks must not be tripped — field must
    detect the missing value and raise cleanly.
    """
    var data = _make_bytes(String('{"a":'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("a"))
    except:
        raised = True
    assert_true(raised, "field on a value-less key must raise, not crash")


def test_get_string_on_int_raises() raises:
    """Reading an integer value via get_string raises (type guard)."""
    var data = _make_bytes(String('{"a":1}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("a")).get_string()
    except:
        raised = True
    assert_true(raised, "get_string on a non-string must raise")


def test_get_int_on_string_raises() raises:
    """Reading a string value via get_int raises (type guard)."""
    var data = _make_bytes(String('{"a":"x"}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("a")).get_int()
    except:
        raised = True
    assert_true(raised, "get_int on a string must raise")


def test_get_int_on_float_raises() raises:
    """Reading a float value via get_int raises (type guard)."""
    var data = _make_bytes(String('{"a":1.5}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("a")).get_int()
    except:
        raised = True
    assert_true(raised, "get_int on a float must raise")


def test_container_as_leaf_raises() raises:
    """Reading a container value as a leaf is a clean error, not garbage.

    `{"a":{"b":1}}` — field("a") points at an object; both get_int and
    get_string must raise (navigation into containers is deferred past M0).
    """
    var data = _make_bytes(String('{"a":{"b":1}}'))
    var rdr = iter(data)

    var int_raised = False
    try:
        _ = rdr.root().field(String("a")).get_int()
    except:
        int_raised = True
    assert_true(int_raised, "get_int on an object value must raise")

    var str_raised = False
    try:
        _ = rdr.root().field(String("a")).get_string()
    except:
        str_raised = True
    assert_true(str_raised, "get_string on an object value must raise")


def test_field_non_object_root_raises() raises:
    """A non-object root must fail safe (raise), never read OOB.

    `field` assumes an object root; a string/number/array root (`"x"`, `42`,
    `[1,2]`) must raise from field rather than crash or read past the positions
    list. Run under -D ASSERT=all: the key-close index (si+1) must stay in bounds.
    """
    for ref s in [String('"x"'), String("42"), String("[1,2]")]:
        var data = _make_bytes(s)
        var rdr = iter(data)
        var raised = False
        try:
            _ = rdr.root().field(String("x"))
        except:
            raised = True
        assert_true(raised, "field on a non-object root must raise: " + s)


def test_field_unterminated_key_raises() raises:
    """An unterminated final key (`{\"a`) raises, never reads OOB at si+1.

    Run under -D ASSERT=all: the missing closing-quote structural must be detected
    by the bounds guard, not by indexing past the positions list.
    """
    var data = _make_bytes(String('{"a'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("a"))
    except:
        raised = True
    assert_true(raised, "field on an unterminated key must raise, not crash")


def test_get_int_uint64_overflow_raises() raises:
    """A positive integer above Int64.MAX (tagged uint64) raises, not wraps.

    `{"id":18446744073709551615}` (uint64 max) must raise from get_int rather
    than silently returning -1; `9223372036854775807` (Int64.MAX) is fine.
    """
    var data = _make_bytes(String('{"id":18446744073709551615}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("id")).get_int()
    except:
        raised = True
    assert_true(raised, "get_int on a uint64 above Int64.MAX must raise")

    var data2 = _make_bytes(String('{"m":9223372036854775807}'))
    var rdr2 = iter(data2)
    assert_equal(
        rdr2.root().field(String("m")).get_int(), Int64(9223372036854775807)
    )


def main() raises:
    test_field_get_string()
    test_field_get_string_last_field()
    test_field_get_int()
    test_field_missing_raises()
    test_iter_reused_across_parses()
    test_field_skips_nested_object()
    test_field_sibling_after_nested_object()
    test_field_sibling_after_array()
    test_field_empty_object_raises()
    test_field_truncated_no_value_raises()
    test_get_string_on_int_raises()
    test_get_int_on_string_raises()
    test_get_int_on_float_raises()
    test_container_as_leaf_raises()
    test_field_non_object_root_raises()
    test_field_unterminated_key_raises()
    test_get_int_uint64_overflow_raises()
    print("test_flat_object: all passed")
