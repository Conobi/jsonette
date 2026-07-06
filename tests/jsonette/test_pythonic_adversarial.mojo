"""Adversarial edge-case coverage for the pythonic DOM + owned-builder surface.

Hunts the corners of the total operators (`__eq__`/`__ne__`, `__contains__`,
`__len__`, `__iter__`), object-iteration sugar (`keys`/`items`), the
null-vs-absent `get`, the infallible-and-strict serialization split, and the
owned `JsonValue` builder / `loads` round-trip. Complements the happy-path
`test_pythonic_surface`: everything here targets empty containers, wrong-type
receivers, prefix collisions, embedded NUL / control / multibyte bytes,
duplicate keys, non-finite nodes, the encoder depth cap, and scalar-overwrite
auto-vivification.
"""
from std.testing import assert_equal, assert_raises, assert_true
from jsonette.document import parse
from jsonette.serialize.tape_writer import to_string, to_json
from jsonette.serialize.json_value import JsonValue, loads
from jsonette.serialize.reflect_writer import dumps


def test_eq_string_fidelity() raises:
    """`__eq__`/`__ne__` vs String: total, byte-exact, never raises."""
    var doc = parse(
        String('{"empty":"","ada":"Ada","o":{},"a":[],"n":5,"f":1.5,"b":true,"z":null}')
    )
    var r = doc.root()

    # Empty string value vs empty comparand (both empty) is equal.
    assert_true(r.field("empty") == "", "empty value equals empty string")
    assert_true(not (r.field("empty") != ""), "__ne__ mirror on empty")
    # Empty value vs a non-empty comparand differs.
    assert_true(r.field("empty") != "x", "empty value != non-empty")
    # Non-empty value vs empty comparand differs.
    assert_true(r.field("ada") != "", "non-empty value != empty")

    # Prefix collisions: neither a shorter nor a longer comparand matches.
    assert_true(r.field("ada") == "Ada", "exact match")
    assert_true(not (r.field("ada") == "Ad"), "shorter prefix is not equal")
    assert_true(not (r.field("ada") == "Adax"), "longer superstring is not equal")
    assert_true(r.field("ada") != "Ad", "__ne__ shorter")
    assert_true(r.field("ada") != "Adax", "__ne__ longer")

    # Non-string receivers all compare False (total, never raises); __ne__ True.
    assert_true(not (r.field("o") == "x"), "object == string is False")
    assert_true(r.field("o") != "x", "object != string is True")
    assert_true(not (r.field("a") == "x"), "array == string is False")
    assert_true(r.field("a") != "x", "array != string is True")
    assert_true(not (r.field("n") == "5"), "number == string is False")
    assert_true(r.field("n") != "5", "number != string is True")
    assert_true(not (r.field("f") == "1.5"), "float == string is False")
    assert_true(not (r.field("b") == "true"), "bool == string is False")
    assert_true(not (r.field("z") == "null"), "null == string is False")
    assert_true(r.field("z") != "null", "null != string is True")


def test_eq_control_multibyte_nul() raises:
    """`__eq__` byte-compares embedded NUL, multibyte UTF-8, and control bytes."""
    # Embedded NUL: value is x<NUL>y (3 bytes); equals its own get_string,
    # differs from the NUL-stripped "xy".
    var nd = parse(String('{"s":"x\\u0000y"}'))
    var nv = nd.root().field("s")
    assert_equal(nv.get_string().byte_length(), 3)
    assert_true(nv == nv.get_string(), "value equals its own extracted bytes (with NUL)")
    assert_true(nv != "xy", "NUL-bearing value differs from NUL-free comparand")

    # Multibyte UTF-8: cafe + U+00E9. Equal to the 2-byte-encoded comparand;
    # differs from the ASCII 'cafe' and from a bare prefix.
    var md = parse(String('{"s":"caf\\u00e9"}'))
    var mv = md.root().field("s")
    assert_true(mv == (String("caf") + chr(233)), "multibyte content matches")
    assert_true(mv != "cafe", "multibyte differs from ASCII look-alike")
    assert_true(mv != "caf", "multibyte differs from its ASCII prefix")


def test_totality_contains() raises:
    """`in` is total: correct on objects (incl. prefix collisions), False on
    non-objects and empties, never raises."""
    var doc = parse(String('{"ab":1,"nested":{"x":9},"arr":[1,2]}'))
    var r = doc.root()
    assert_true("ab" in r, "present key")
    assert_true(not ("a" in r), "prefix of a key is not the key")
    assert_true(not ("abc" in r), "superstring of a key is not the key")
    # Non-object receivers -> False (never raise).
    assert_true(not ("x" in r.field("arr")), "contains on an array is False")
    assert_true(not ("x" in r.field("ab")), "contains on a number is False")
    # Empty object -> any key absent.
    var ed = parse(String("{}"))
    assert_true(not ("k" in ed.root()), "contains on empty object is False")


def test_totality_len() raises:
    """`len()` is total: element count on containers, 0 on non-containers and
    empties."""
    var doc = parse(String('{"o":{"a":1,"b":2},"e":{},"arr":[9,9,9],"ea":[],"s":"hi","n":7}'))
    var r = doc.root()
    assert_equal(len(r.field("o")), 2)
    assert_equal(len(r.field("e")), 0)   # empty object
    assert_equal(len(r.field("arr")), 3)
    assert_equal(len(r.field("ea")), 0)  # empty array
    assert_equal(len(r.field("s")), 0)   # scalar -> 0, no raise
    assert_equal(len(r.field("n")), 0)
    assert_equal(len(r), 6)              # root member count


def test_totality_iter() raises:
    """`for x in value` is total: array elements, nothing on objects/scalars/
    empties; re-iteration is identical; random access survives iteration."""
    var doc = parse(String('{"xs":[4,5,6],"obj":{"a":1},"ea":[],"n":9}'))
    var r = doc.root()

    # Iterating an object value yields nothing (objects are not __iter__-able).
    var oc = 0
    for _x in r.field("obj"):
        oc += 1
    assert_equal(oc, 0)
    # Iterating a scalar yields nothing.
    var sc = 0
    for _x in r.field("n"):
        sc += 1
    assert_equal(sc, 0)
    # Iterating an empty array yields nothing.
    var ec = 0
    for _x in r.field("ea"):
        ec += 1
    assert_equal(ec, 0)

    # Re-iterate the same array twice: identical sums.
    var xs = r.field("xs")
    var a = UInt64(0)
    for x in xs:
        a += x.get_uint()
    var b = UInt64(0)
    for x in xs:
        b += x.get_uint()
    assert_equal(a, UInt64(15))
    assert_equal(a, b)
    # Random access still valid after iterating.
    assert_equal(xs.elem(0).get_uint(), UInt64(4))
    assert_equal(xs.elem(2).get_uint(), UInt64(6))


def test_keys_items_edges() raises:
    """`keys`/`items`: empty object, unicode/escaped keys, duplicate keys, nested
    values skipped correctly, re-readable values, raise on non-object."""
    # Empty object.
    var ed = parse(String("{}"))
    assert_equal(len(ed.root().keys()), 0)
    assert_equal(len(ed.root().items()), 0)

    # Unicode + escaped keys survive unescaping.
    var ud = parse(String('{"caf\\u00e9":1,"a\\nb":2}'))
    var uk = ud.root().keys()
    assert_equal(len(uk), 2)
    assert_true(uk[0] == (String("caf") + chr(233)), "unicode key content")
    assert_true(uk[1] == (String("a") + chr(10) + String("b")), "escaped-newline key content")

    # keys() must SKIP a nested container value, not descend into it.
    var sd = parse(String('{"a":{"b":1},"c":2}'))
    var sk = sd.root().keys()
    assert_equal(len(sk), 2)
    assert_true(sk[0] == "a", "first key")
    assert_true(sk[1] == "c", "key after a nested object (inner 'b' skipped)")

    # items() values are re-readable, including a nested object.
    var kk = String("")
    var seen_nested = False
    for k, v in sd.root().items():
        kk += k
        if k == "a":
            seen_nested = v.is_object() and v.field("b").get_uint() == UInt64(1)
    assert_equal(kk, String("ac"))
    assert_true(seen_nested, "nested object value re-readable through items()")

    # Duplicate keys: DOM keeps BOTH entries; field() returns the first.
    var dd = parse(String('{"a":1,"a":2}'))
    var dr = dd.root()
    assert_equal(dr.field("a").get_uint(), UInt64(1))  # first wins
    assert_equal(dr.len(), 2)                           # both counted
    assert_true("a" in dr, "duplicate key present")
    var dk = dr.keys()
    assert_equal(len(dk), 2)
    assert_true(dk[0] == "a" and dk[1] == "a", "both duplicate keys returned")

    # keys()/items() raise on a non-object receiver, with the specific
    # object-type guard message (not merely *some* exception, which would still
    # pass if the guard were removed and a different fault raised downstream).
    var ad = parse(String("[1,2]"))
    with assert_raises(contains="expected object for keys"):
        _ = ad.root().keys()
    with assert_raises(contains="expected object for items"):
        _ = ad.root().items()


def test_get_null_vs_absent() raises:
    """`get`: present-null is Some (is_null), absent is None, OOR index is None,
    wrong-container receiver raises."""
    var doc = parse(String('{"a":null,"arr":[7,8]}'))
    var r = doc.root()
    # Present key with a null value is Some, and the value is JSON null.
    assert_true(r.get("a").__bool__(), "present-null key is Some")
    assert_true(r.get("a").value().is_null(), "value is JSON null")
    # Absent key is None.
    assert_true(not r.get("b").__bool__(), "absent key is None")
    # In-range index Some, out-of-range index None.
    var arr = r.field("arr")
    assert_equal(arr.get(0).value().get_uint(), UInt64(7))
    assert_true(not arr.get(5).__bool__(), "out-of-range index is None")
    assert_true(not arr.get(2).__bool__(), "one-past-end index is None")

    # get(key) on a non-object raises the object-type guard (via has_field);
    # get(idx) on a non-array raises the array-index guard. Match each specific
    # message so a regression that faults on a different path is not accepted.
    with assert_raises(contains="expected object"):
        _ = arr.get("k")  # array.get(key) -> non-object receiver
    with assert_raises(contains="expected array for index access"):
        _ = r.get(0)  # object.get(idx) -> non-array receiver


def test_writable_escaping() raises:
    """`String(value)`/`to_string(value)` escape exactly and handle empties."""
    # Each JSON escape round-trips to its canonical short form.
    assert_equal(_ser_field(String('{"s":"\\t"}')), String('"\\t"'))
    assert_equal(_ser_field(String('{"s":"\\n"}')), String('"\\n"'))
    assert_equal(_ser_field(String('{"s":"\\r"}')), String('"\\r"'))
    assert_equal(_ser_field(String('{"s":"\\b"}')), String('"\\b"'))
    assert_equal(_ser_field(String('{"s":"\\f"}')), String('"\\f"'))
    assert_equal(_ser_field(String('{"s":"\\""}')), String('"\\""'))
    assert_equal(_ser_field(String('{"s":"\\\\"}')), String('"\\\\"'))
    # Non-short control bytes use \u00XX (lowercase hex).
    assert_equal(_ser_field(String('{"s":"\\u0001"}')), String('"\\u0001"'))
    assert_equal(_ser_field(String('{"s":"\\u001f"}')), String('"\\u001f"'))
    # Embedded NUL escapes back to the six-character \u0000 form.
    assert_equal(_ser_field(String('{"s":"x\\u0000y"}')), String('"x\\u0000y"'))
    # Empty string serializes to "".
    assert_equal(_ser_field(String('{"s":""}')), String('""'))

    # Empty containers.
    var eo = parse(String("{}"))
    assert_equal(String(eo.root()), String("{}"))
    var ea = parse(String("[]"))
    assert_equal(String(ea.root()), String("[]"))


def test_pretty_subtree() raises:
    """Pretty sub-tree serialization indents relative to the sub-tree root."""
    var doc = parse(String('{"outer":{"a":{"b":1}},"other":9}'))
    var pretty = to_json[pretty=True](doc.root().field("outer"))
    assert_equal(pretty, String('{\n  "a": {\n    "b": 1\n  }\n}'))


def test_writable_nonfinite() raises:
    """Non-finite nodes: strict `to_string` raises; infallible `String` degrades
    only the offending node to null (nested and array cases)."""
    # Nested object: {"a":{"b":1e999}}.
    var nd = parse(String('{"a":{"b":1e999}}'))
    var nr = nd.root()
    with assert_raises(contains="non-finite float"):
        _ = to_string(nr)
    assert_equal(String(nr), String('{"a":{"b":null}}'))
    # Strict pretty overload also raises with the same non-finite diagnostic.
    with assert_raises(contains="non-finite float"):
        _ = to_json[pretty=True](nr)

    # Array: [1e999] -> String -> [null]; strict raises.
    var ad = parse(String("[1e999]"))
    var ar = ad.root()
    assert_equal(String(ar), String("[null]"))
    with assert_raises(contains="non-finite float"):
        _ = to_string(ar)


def test_jsonvalue_autovivify_overwrite() raises:
    """Auto-vivifying `__getitem__` over an existing SCALAR retags it to an object
    (silently discarding the scalar), with no crash."""
    var d = JsonValue.object()
    d["a"] = JsonValue(1)          # "a" is now a scalar int
    d["a"]["b"] = JsonValue(2)     # index into the scalar -> retagged to object
    # The scalar 1 is overwritten; the result is a nested object.
    assert_equal(dumps(d), String('{"a":{"b":2}}'))


def test_jsonvalue_setitem_overwrite_order() raises:
    """Re-assigning an existing key overwrites in place, preserving order."""
    var d = JsonValue.object()
    d["a"] = JsonValue(1)
    d["b"] = JsonValue(2)
    d["a"] = JsonValue(3)  # overwrite first key
    assert_equal(dumps(d), String('{"a":3,"b":2}'))


def test_jsonvalue_empty_and_nonfinite() raises:
    """Empty builder containers dump to `{}`/`[]`; a non-finite scalar raises."""
    assert_equal(dumps(JsonValue.object()), String("{}"))
    assert_equal(dumps(JsonValue.array()), String("[]"))
    # dumps of a non-finite scalar raises (1e999 -> +inf).
    with assert_raises(contains="non-finite float"):
        _ = dumps(JsonValue(1e999))


def test_jsonvalue_depth_boundary() raises:
    """The encoder depth cap is exact: a tree at the cap dumps; one level deeper
    raises (rather than overflowing the native stack)."""
    # 1024 wrappers: innermost scalar sits exactly at the cap -> no raise.
    var ok = JsonValue(1)
    for _i in range(1024):
        var w = JsonValue.object()
        w["x"] = ok^
        ok = w^
    # A tree exactly at the depth cap must dump without raising: a stray
    # exception here propagates out of this `raises` test and fails it.
    _ = dumps(ok)

    # 1025 wrappers: one level past the cap -> raises the depth-cap guard, no crash.
    var deep = JsonValue(1)
    for _i in range(1025):
        var w = JsonValue.object()
        w["x"] = deep^
        deep = w^
    with assert_raises(contains="max nesting depth exceeded"):
        _ = dumps(deep)


def test_loads_from_value_fidelity() raises:
    """`loads`/`dumps` round-trips preserve escapes, unicode, numeric kinds, and
    empty nesting; `loads` of a non-finite succeeds but `dumps` then raises."""
    # Escaped-string canonical round-trip (short escapes stay short).
    assert_equal(dumps(loads(String('"a\\nb"'))), String('"a\\nb"'))
    assert_equal(dumps(loads(String('"\\t\\""'))), String('"\\t\\""'))
    # \uXXXX canonicalizes to raw UTF-8 (2-byte encoded, not the escape).
    assert_equal(dumps(loads(String('"\\u00e9"'))), String('"') + chr(233) + String('"'))

    # Numeric kinds: uint above Int64.MAX stays unsigned; negative stays signed;
    # 0 stays 0, and -0.0 PRESERVES its sign. Python and simdjson both keep
    # "-0.0"; assert the literal round-trip so a sign-dropping regression (which
    # a self-referential idempotency check structurally cannot catch) fails here.
    assert_equal(
        dumps(loads(String("18446744073709551615"))),
        String("18446744073709551615"),
    )
    assert_equal(dumps(loads(String("-9"))), String("-9"))
    assert_equal(dumps(loads(String("0"))), String("0"))
    assert_equal(dumps(loads(String("-0.0"))), String("-0.0"))

    # Empty nested containers round-trip.
    assert_equal(dumps(loads(String('{"a":[],"b":{}}'))), String('{"a":[],"b":{}}'))

    # Canonical compact document round-trips byte-for-byte.
    var canon = String('{"a":1,"b":[2,3],"c":"x","d":true,"e":null}')
    assert_equal(dumps(loads(canon)), canon)

    # loads(dumps(jv)) is idempotent for a hand-built tree.
    var jv = JsonValue.object()
    jv["n"] = JsonValue(UInt64(18446744073709551615))
    jv["s"] = JsonValue(String("hi"))
    var d1 = dumps(jv)
    assert_equal(dumps(loads(d1)), d1)

    # Duplicate keys through loads: last value wins (Python-faithful).
    assert_equal(dumps(loads(String('{"a":1,"a":2}'))), String('{"a":2}'))

    # loads of 1e999 SUCCEEDS (materializes +inf), but dumps then RAISES.
    var inf = loads(String("1e999"))
    with assert_raises(contains="non-finite float"):
        _ = dumps(inf)


def test_reparse_reroot_serializes_fresh() raises:
    """After a reparse, a freshly re-rooted Value serializes the NEW document
    (the stale-Value trap is exercised separately by the negative gate)."""
    var doc = parse(String('{"a":1}'))
    assert_equal(String(doc.root()), String('{"a":1}'))
    doc.reparse(String('{"b":[7,8]}'))
    # Re-root after the reparse: current generation, serializes the new tape.
    assert_equal(String(doc.root()), String('{"b":[7,8]}'))
    assert_equal(String(doc.root().field("b")), String("[7,8]"))


def _ser_field(src: String) raises -> String:
    """Serialize the `"s"` field of a one-key object via the Writable path."""
    var d = parse(src)
    return String(d.root().field("s"))


def main() raises:
    """Run every adversarial edge-case test in declaration order."""
    test_eq_string_fidelity()
    test_eq_control_multibyte_nul()
    test_totality_contains()
    test_totality_len()
    test_totality_iter()
    test_keys_items_edges()
    test_get_null_vs_absent()
    test_writable_escaping()
    test_pretty_subtree()
    test_writable_nonfinite()
    test_jsonvalue_autovivify_overwrite()
    test_jsonvalue_setitem_overwrite_order()
    test_jsonvalue_empty_and_nonfinite()
    test_jsonvalue_depth_boundary()
    test_loads_from_value_fidelity()
    test_reparse_reroot_serializes_fresh()
    print("test_pythonic_adversarial: all passed")
