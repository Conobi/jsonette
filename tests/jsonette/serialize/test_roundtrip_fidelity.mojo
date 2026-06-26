"""Foundational round-trip fidelity tests, stressed as a function of STRING COUNT.

The existing serialize/parser suite tests breadth of value-types, escape forms,
structure depth, and number edge cases, but never drives the one axis that
crosses the stage-2 string-tape allocation boundary: the *number* of strings in
a document. The stage-2 builder sizes its string tape as `input_len + 64`, yet
each parsed string is stored as `[4-byte LE length][content][1-byte NUL]`, a
fixed +5 bytes of per-string overhead. For a document with MANY SHORT strings
the cumulative tape use `sum(content) + 5*N` overruns `input_len + 64` once the
+5*N overhead exceeds the document's non-string structural slack — the tail
strings then truncate into NULs and keys collapse to "".

These tests assert round-trip fidelity as a function of N. They are written to
be GREEN against a correctly-sized string tape and to expose any sizing that is
a function of `input_len` alone. Each test targets a distinct facet of the same
fidelity property; none is a golden fixture.

Encoded JSON is canonical compact (member order preserved, no spaces), so for a
canonically-built input `to_string(parse(input)) == input` is an exact
full-fidelity identity oracle: it asserts every key and every value re-emits
byte-for-byte.
"""

from std.testing import assert_equal, assert_true
from jsonette.document import parse
from jsonette.serialize.tape_writer import to_string


def _bytes(s: String) -> List[UInt8]:
    var b = List[UInt8]()
    for x in s.as_bytes():
        b.append(x)
    return b^


def _emit(s: String) raises -> String:
    """parse(s) -> encode; the round-trip under test."""
    var doc = parse(_bytes(s))
    return to_string(doc)


def _first_diff(a: String, b: String) -> Int:
    """Byte index of the first difference (or the shorter length if a prefix)."""
    var ab = a.as_bytes()
    var bb = b.as_bytes()
    var n = len(ab) if len(ab) < len(bb) else len(bb)
    for i in range(n):
        if ab[i] != bb[i]:
            return i
    if len(ab) != len(bb):
        return n
    return -1


def _assert_identity(src: String, label: String) raises:
    """Round-trip `src` and raise a concise, located message on any mismatch.

    Avoids dumping whole documents: reports the label, the byte lengths, and the
    first differing byte position so a corruption at the document TAIL is named
    precisely.
    """
    var out = _emit(src)
    if out != src:
        var d = _first_diff(src, out)
        raise Error(
            "round-trip fidelity broken [" + label + "]: src_len="
            + String(src.byte_length()) + " emitted_len="
            + String(out.byte_length()) + " first_diff_byte=" + String(d)
            + " (tail-string corruption: +5B/string overhead overran input_len+64)"
        )


# --- shape generators (canonical compact JSON) --------------------------------

def _arr_objs(n: Int) -> String:
    """`[{"k":"v"},...]` — N single-member objects (2 short strings each)."""
    var s = String("[")
    for i in range(n):
        if i > 0:
            s += ","
        s += '{"k":"v"}'
    s += "]"
    return s^


def _arr_objs_unique(n: Int) -> String:
    """`[{"k":"V0"},{"k":"V1"},...]` — unique values to detect mis-association."""
    var s = String("[")
    for i in range(n):
        if i > 0:
            s += ","
        s += '{"k":"V' + String(i) + '"}'
    s += "]"
    return s^


def _flat_obj(n: Int) -> String:
    """`{"k0":"v0",...}` — one flat object, N members, 2N short strings."""
    var s = String("{")
    for i in range(n):
        if i > 0:
            s += ","
        s += '"k' + String(i) + '":"v' + String(i) + '"'
    s += "}"
    return s^


def _empty_vals(n: Int) -> String:
    """`{"a0":"","a1":"",...}` — nonempty keys, empty values (key-collapse probe)."""
    var s = String("{")
    for i in range(n):
        if i > 0:
            s += ","
        s += '"a' + String(i) + '":""'
    s += "}"
    return s^


def _raw_unicode(n: Int) -> String:
    """`[{"k":"é"},...]` — raw 2-byte UTF-8 (U+00E9) content, repeated.

    Raw multibyte (not `\\u00e9`): an escaped form is 6 input bytes for 2 content
    bytes, so its input slack grows faster than the +5 tape overhead and would
    NOT cross the boundary. Raw multibyte content is the short-input/wide-tape
    case that does.
    """
    var s = String("[")
    for i in range(n):
        if i > 0:
            s += ","
        s += '{"k":"' + chr(0xE9) + '"}'
    s += "]"
    return s^


def _mixed(n: Int) -> String:
    """Mostly `{"k":"v"}`, every 10th carries a 40-char value.

    The sparse long values inflate `input_len` (and thus `input_len + 64`); the
    test pins that a few long strings do NOT mask a count-driven overrun.
    """
    var s = String("[")
    for i in range(n):
        if i > 0:
            s += ","
        if i % 10 == 0:
            var long = String("")
            for _ in range(40):
                long += "L"
            s += '{"k":"' + long + '"}'
        else:
            s += '{"k":"v"}'
    s += "]"
    return s^


# --- facet 1: round-trip fidelity scaled by string count ----------------------

def test_roundtrip_fidelity_scaled_by_string_count() raises:
    """The foundational test: identity must hold for ANY string count.

    Sweeps N over {1, 16, 64, 128, 512} arrays of single-member objects and
    asserts the re-emitted JSON is byte-identical to the input. A tape sized on
    `input_len` alone holds for small N and corrupts the tail once 5*N exceeds
    the structural slack (here near N=34).
    """
    var ns = List[Int]()
    ns.append(1); ns.append(16); ns.append(64); ns.append(128); ns.append(512)
    for j in range(len(ns)):
        var n = ns[j]
        _assert_identity(_arr_objs(n), "arr_objs N=" + String(n))


# --- facet 2: corruption-signature invariant (fixture-independent) ------------

def test_no_nul_injection_and_no_empty_collapse() raises:
    """Invariant: a generated many-short-string doc reads back losslessly.

    For an array of N objects with KNOWN unique nonempty values, every value
    extracted through the DOM must (a) equal what was generated (constructive
    oracle), (b) contain no NUL byte (none was in the source), and (c) never be
    empty (every source value was nonempty). This asserts the invariant, not a
    golden fixture. N=64 corrupts the tail without tripping the heap crash that
    larger N induces, yielding a stable assertion.
    """
    comptime N = 64
    var doc = parse(_bytes(_arr_objs_unique(N)))
    var root = doc.root()
    for i in range(N):
        var expected = String("V") + String(i)
        # A collapsed tail key makes this raise KEY_NOT_FOUND — itself a RED
        # signal; it propagates to the caller with the missing-key message.
        var got = root.elem(i).field("k").get_string()
        # (b) no spurious NUL injected into a value that had none.
        for bb in got.as_bytes():
            if bb == UInt8(0):
                raise Error(
                    "NUL injected: object N=" + String(i) + " value expected '"
                    + expected + "' came back with an embedded NUL byte "
                    + "(content truncated into the zero-filled tape region)"
                )
        # (c) no empty collapse; value must be exact.
        if got != expected:
            raise Error(
                "value corrupted: object N=" + String(i) + " expected '"
                + expected + "' got byte_length=" + String(got.byte_length())
            )


# --- facet 3: allocation-boundary pin -----------------------------------------

def test_allocation_boundary_pin() raises:
    """Pin the exact N where `input_len + 64` first fails to hold all strings.

    For `[{"k":"v"},...]`: each object emits 2 strings of 1 content byte =
    2*(4+1+1) = 12 tape bytes; input_len = 10*N + 1, so need_str = input_len+64
    = 10*N + 65. The tape needs 12*N, which first exceeds need_str at N=33
    (396 > 395) — a 1-byte overrun that only zeroes an already-NUL terminator,
    so N=33 still round-trips. The first VISIBLE corruption is N=34
    (sbuf 408 > need_str 405 by 3 bytes), clipping the last value's content.

    This test pins both edges so a fix's margin is verifiable: N=33 must stay
    clean (control) and N=34 must round-trip (RED until the tape is sized for
    the +5B/string overhead).
    """
    _assert_identity(_arr_objs(33), "boundary control N=33 (last clean)")
    _assert_identity(_arr_objs(34), "boundary first-overrun N=34 (5*N=408 > input_len+64=405)")


# --- facet 4: shape diversity -------------------------------------------------

def test_shape_flat_object_many_short_keys() raises:
    """(a) One FLAT object with many short keys+values. Densest string packing
    (2 strings/member), so it overruns at the lowest member count (near N=17)."""
    _assert_identity(_flat_obj(24), "flat_obj N=24")


def test_shape_many_empty_string_values() raises:
    """(b) Many empty-string values. The values are already empty, so the
    corruption shows as KEYS collapsing — identity catches the lost key bytes."""
    _assert_identity(_empty_vals(64), "empty_vals N=64")


def test_shape_short_unicode_multibyte_repeated() raises:
    """(c) Short raw-multibyte (U+00E9) values repeated near/over the boundary.
    Exercises the multibyte content copy path under string-count pressure."""
    _assert_identity(_raw_unicode(64), "raw_unicode N=64")


def test_shape_mixed_short_and_long() raises:
    """(d) Mostly short strings with sparse long values. A few long strings
    raise input_len but must NOT mask the count-driven tail overrun."""
    _assert_identity(_mixed(64), "mixed N=64")


# --- facet 5: memory-safety under many-short-string pressure ------------------

def test_memory_safety_large_many_short_strings() raises:
    """A large many-short-string parse must not silently corrupt memory.

    The over-budget writes go through a raw `string_buf` pointer past the
    reserved capacity, so they are out-of-bounds heap writes — not caught by
    bounds checks even under `-D ASSERT=all`. At N=128 the round-trip identity
    fails; at larger N (or during per-element DOM extraction) the corrupted heap
    crashes the process. This test asserts the identity failure (the stable,
    capturable signal); the crash at larger N is the harder memory-safety RED.
    """
    _assert_identity(_arr_objs(128), "memory_safety arr_objs N=128")


# --- aggregator ---------------------------------------------------------------

def _run(name: String, mut failures: List[String]) -> Bool:
    """Run a named test, returning True on pass; on failure record a one-line
    RED message and return False. Lets one run report every facet's signal."""
    try:
        if name == "fidelity_scaled":
            test_roundtrip_fidelity_scaled_by_string_count()
        elif name == "no_nul_no_empty":
            test_no_nul_injection_and_no_empty_collapse()
        elif name == "boundary_pin":
            test_allocation_boundary_pin()
        elif name == "flat_keys":
            test_shape_flat_object_many_short_keys()
        elif name == "empty_vals":
            test_shape_many_empty_string_values()
        elif name == "unicode":
            test_shape_short_unicode_multibyte_repeated()
        elif name == "mixed":
            test_shape_mixed_short_and_long()
        elif name == "mem_safety":
            test_memory_safety_large_many_short_strings()
        return True
    except e:
        failures.append(name + ": " + String(e))
        return False


def main() raises:
    var order = List[String]()
    order.append("fidelity_scaled")
    order.append("no_nul_no_empty")
    order.append("boundary_pin")
    order.append("flat_keys")
    order.append("empty_vals")
    order.append("unicode")
    order.append("mixed")
    order.append("mem_safety")

    var failures = List[String]()
    for j in range(len(order)):
        var name = order[j]
        if _run(name, failures):
            print("ok   " + name)
        else:
            print("RED  " + failures[len(failures) - 1])

    if len(failures) != 0:
        raise Error("test_roundtrip_fidelity: " + String(len(failures)) + " RED")
    print("test_roundtrip_fidelity: all passed")
