"""Tests for the owned, origin-free `JsonValue` output builder.

`JsonValue` is a hand-built JSON tree that serializes through the existing
encoder (`dumps`) with no dedicated serialization entry point: it conforms to
`JsonSerializable`, so `dumps`/`emit` route it to `write_json`. These tests
cover construction (implicit and explicit), the array/object builders, the
auto-vivifying getter, pretty output parity with the encoder, the numeric
signed/unsigned/float distinction, and the recursion depth guard.
"""
from std.testing import assert_equal, assert_true
from jsonette import JsonValue, dumps, loads, parse


def test_nested_compact() raises:
    """An object with a nested array and object dumps to compact JSON in
    insertion order."""
    var v = JsonValue.object()
    v["name"] = JsonValue("jsonette")
    var arr = JsonValue.array()
    arr.append(JsonValue(1))
    arr.append(JsonValue(2))
    v["nums"] = arr^
    var inner = JsonValue.object()
    inner["x"] = JsonValue(True)
    v["meta"] = inner^
    assert_equal(
        dumps(v),
        String('{"name":"jsonette","nums":[1,2],"meta":{"x":true}}'),
    )


def test_pretty() raises:
    """Pretty output matches the encoder's indentation style (two-space units,
    trailing comma on the line, `": "` after keys)."""
    var v = JsonValue.object()
    v["a"] = JsonValue(1)
    var inner = JsonValue.object()
    inner["b"] = JsonValue(False)
    v["c"] = inner^
    var nl = chr(10)
    var expected = (
        String("{") + nl
        + '  "a": 1,' + nl
        + '  "c": {' + nl
        + '    "b": false' + nl
        + "  }" + nl
        + "}"
    )
    assert_equal(dumps(v, indent=String("  ")), expected)


def test_scalars_explicit() raises:
    """Each explicit scalar constructor dumps to the right JSON token."""
    assert_equal(dumps(JsonValue(42)), String("42"))
    assert_equal(dumps(JsonValue("hi")), String('"hi"'))
    assert_equal(dumps(JsonValue(True)), String("true"))
    assert_equal(dumps(JsonValue(False)), String("false"))
    assert_equal(dumps(JsonValue(None)), String("null"))
    assert_equal(dumps(JsonValue(1.5)), String("1.5"))
    assert_equal(dumps(JsonValue()), String("null"))


def test_numeric_distinction() raises:
    """Signed, unsigned, and float numerics are preserved distinctly."""
    # UInt64 max would be -1 if reinterpreted as signed; stays unsigned.
    assert_equal(
        dumps(JsonValue(UInt64(18446744073709551615))),
        String("18446744073709551615"),
    )
    assert_equal(dumps(JsonValue(Int64(-9))), String("-9"))
    # A whole-valued float keeps its decimal point (float token, not int).
    assert_equal(dumps(JsonValue(2.0)), String("2.0"))
    # A bare integer literal is signed.
    assert_equal(dumps(JsonValue(-5)), String("-5"))


def test_scalars_implicit() raises:
    """Implicit literal coercion works for int/string/bool/float targets."""
    var a: JsonValue = 42
    assert_equal(dumps(a), String("42"))
    var s: JsonValue = "hi"
    assert_equal(dumps(s), String('"hi"'))
    var b: JsonValue = True
    assert_equal(dumps(b), String("true"))
    var f: JsonValue = 1.5
    assert_equal(dumps(f), String("1.5"))


def test_autovivify() raises:
    """Indexing an absent key inserts an empty object, enabling `d[a][b] = x`."""
    var d = JsonValue.object()
    d["a"]["b"] = JsonValue(1)
    assert_equal(dumps(d), String('{"a":{"b":1}}'))


def test_setitem_overwrite() raises:
    """Re-assigning a key overwrites in place and preserves insertion order."""
    var d = JsonValue.object()
    d["a"] = JsonValue(1)
    d["b"] = JsonValue(2)
    d["a"] = JsonValue(3)
    assert_equal(dumps(d), String('{"a":3,"b":2}'))


def test_empty_containers() raises:
    """An empty array and object dump to `[]` and `{}`."""
    assert_equal(dumps(JsonValue.array()), String("[]"))
    assert_equal(dumps(JsonValue.object()), String("{}"))


def test_depth_limit_raises() raises:
    """Nesting beyond the depth cap raises instead of overflowing the stack."""
    var deep = JsonValue(1)
    for _ in range(1200):
        var wrapper = JsonValue.object()
        wrapper["x"] = deep^
        deep = wrapper^
    var raised = False
    try:
        _ = dumps(deep)
    except:
        raised = True
    assert_true(raised)


def test_loads_any_root() raises:
    """`loads` materializes any JSON root — scalar, array, or object — into an
    owned tree that re-serializes to the same compact token(s)."""
    assert_equal(dumps(loads(String("42"))), String("42"))
    assert_equal(dumps(loads(String('"hi"'))), String('"hi"'))
    assert_equal(dumps(loads(String("true"))), String("true"))
    assert_equal(dumps(loads(String("null"))), String("null"))
    assert_equal(dumps(loads(String("1.5"))), String("1.5"))
    assert_equal(dumps(loads(String("[1,2,3]"))), String("[1,2,3]"))
    assert_equal(dumps(loads(String('{"a":1}'))), String('{"a":1}'))


def test_loads_roundtrip_nested() raises:
    """A nested compact document (nested array + nested object, already in
    insertion order) round-trips byte-for-byte through `loads` then `dumps`."""
    var s = String(
        '{"name":"jsonette","nums":[1,2,3],"meta":{"x":true,"y":null}}'
    )
    assert_equal(dumps(loads(s)), s)


def test_loads_numeric_preserved() raises:
    """`loads` preserves the signed/unsigned/float distinction: a magnitude above
    Int64.MAX stays unsigned, a negative stays signed, a whole-valued float stays
    a float."""
    assert_equal(
        dumps(loads(String("18446744073709551615"))),
        String("18446744073709551615"),
    )
    assert_equal(dumps(loads(String("-9"))), String("-9"))
    # A whole-valued float keeps its decimal point (stays a float, not an int).
    assert_equal(dumps(loads(String("2.0"))), String("2.0"))


def test_from_value_bridge() raises:
    """`JsonValue.from_value` deep-copies a borrowing DOM sub-tree into an owned
    tree that serializes to that sub-tree's JSON."""
    var doc = parse(String('{"k":[1,2,{"z":true}]}'))
    var jv = JsonValue.from_value(doc.root().field("k"))
    assert_equal(dumps(jv), String('[1,2,{"z":true}]'))


def test_loads_nonfinite_edge() raises:
    """`loads` of `1e999` SUCCEEDS (materializes +inf, mirroring the DOM's
    parse-accepts contract), but `dumps` of it RAISES (non-finite has no JSON
    form, mirroring the encoder's refuse contract)."""
    var jv = loads(String('{"x":1e999}'))  # parse accepts -> +inf materialized
    var raised = False
    try:
        _ = dumps(jv)
    except:
        raised = True
    assert_true(raised)


def main() raises:
    test_nested_compact()
    test_pretty()
    test_scalars_explicit()
    test_numeric_distinction()
    test_scalars_implicit()
    test_autovivify()
    test_setitem_overwrite()
    test_empty_containers()
    test_depth_limit_raises()
    test_loads_any_root()
    test_loads_roundtrip_nested()
    test_loads_numeric_preserved()
    test_from_value_bridge()
    test_loads_nonfinite_edge()
    print("test_json_value: all passed")
