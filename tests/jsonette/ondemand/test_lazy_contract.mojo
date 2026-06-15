"""On-Demand (lazy) parser — documented lazy contract + accessed-reject conformance.

These tests PIN the On-Demand reader's deliberately best-effort, path-local
contract as executable assertions. Lazy navigation is NOT a validator: certain
malformed inputs are intentionally tolerated when they are never read or merely
skipped, while a malformed leaf that IS read RAISES rather than returning a
silently wrong value. (Whole-document validity is the job of a later `validate()`
pass, not of lazy navigation.)

Groups:
- A: a malformed leaf that IS accessed raises (number trailing junk, bad string
  escape, unclosed string, invalid literal).
- B: an UNREAD bad sibling leaf does not raise — laziness is preserved.
- C: a SKIPPED malformed sibling (skipped depth-aware) is invisible to lazy
  navigation, so a following good field stays reachable.
- D: key<->value adjacency is unchecked — `value_si = key_si + 3` is positional,
  not grammar-checked, so a comma standing in for a colon is tolerated.
- E: a `Value` landing on a structural close byte is SAFE (no OOB, no
  silent wrong value) — predicates are False and a numeric read raises cleanly.
- F: the accept subset still parses through On-Demand (cross-check M0-M2), plus
  the M3.1 space-before-close terminator case.

Like the other on-demand tests they go through inference ONLY: a caller obtains
the root handle from `iter(...).root()` and navigates without ever naming any
`[o]`-parametric type.
"""

from std.testing import assert_equal, assert_true, assert_false
from jsonette.ondemand.reader import iter


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


# --- A. Accessed malformed leaf RAISES (each kind) ---------------------------


def test_accessed_number_trailing_junk_raises() raises:
    """An accessed number with glued trailing junk (12.3.4) makes get_float raise."""
    var data = _make_bytes(String('{"b":12.3.4}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("b")).get_float()
    except:
        raised = True
    assert_true(raised, "get_float on 12.3.4 must raise (trailing junk)")


def test_accessed_bad_string_escape_raises() raises:
    """An accessed string with a bad escape (backslash-x) makes get_string raise.

    The Mojo literal `\\x` produces the two input bytes `\\` then `x`, i.e. a
    single backslash followed by `x`, which is not a valid JSON escape.
    """
    var data = _make_bytes(String('{"s":"\\x"}'))
    # Confirm the on-the-wire bytes are a single backslash then x (0x5C, 0x78).
    assert_equal(data[6], UInt8(0x5C))
    assert_equal(data[7], UInt8(0x78))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("s")).get_string()
    except:
        raised = True
    assert_true(raised, "get_string on a bad escape must raise (STRING_ERROR)")


def test_accessed_unclosed_string_raises() raises:
    """An accessed unclosed string value makes get_string raise (UNCLOSED_STRING)."""
    var data = _make_bytes(String('{"s":"abc}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("s")).get_string()
    except:
        raised = True
    assert_true(raised, "get_string on an unclosed string must raise")


def test_accessed_invalid_literal_raises() raises:
    """An accessed truncated literal (tru) makes get_bool raise (INVALID_LITERAL)."""
    var data = _make_bytes(String('{"t":tru}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("t")).get_bool()
    except:
        raised = True
    assert_true(raised, "get_bool on tru must raise (INVALID_LITERAL)")


# --- B. Laziness preserved — an UNREAD bad leaf does NOT raise ----------------


def test_unread_bad_leaf_does_not_raise() raises:
    """Reading only the good field never touches a malformed sibling leaf.

    `{"good":1,"bad":12.3.4}` — get_int("good") returns 1 and the function
    returns normally; the malformed "bad" value is never parsed.
    """
    var data = _make_bytes(String('{"good":1,"bad":12.3.4}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("good")).get_int(), Int64(1))


# --- C. Laziness preserved — a SKIPPED malformed sibling does NOT raise -------


def test_skipped_double_comma_array_invisible() raises:
    """A double-comma in a skipped array is invisible to lazy navigation.

    `{"a":[1,2,,],"b":7}` — field("b") skips the malformed array under "a"
    depth-aware and reaches "b" == 7 without ever inspecting the array's commas.
    """
    var data = _make_bytes(String('{"a":[1,2,,],"b":7}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("b")).get_int(), Int64(7))


def test_skipped_missing_colon_object_invisible() raises:
    """A missing colon in a skipped nested object is invisible to lazy navigation.

    `{"a":{"x" 1},"b":7}` — field("b") skips the nested object under "a"
    depth-aware (its missing colon is never examined) and reaches "b" == 7.
    """
    var data = _make_bytes(String('{"a":{"x" 1},"b":7}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("b")).get_int(), Int64(7))


# --- D. Laziness preserved — key<->value adjacency is unchecked ---------------


def test_comma_for_colon_adjacency_unchecked() raises:
    """A comma standing in for the key/value colon is tolerated positionally.

    `{"a",1}` — lazy navigation computes the value index as key_si + 3 without
    grammar-checking the separator, so the byte at that slot (`1`) is returned.
    """
    var data = _make_bytes(String('{"a",1}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("a")).get_int(), Int64(1))


# --- E. A value-handle on a structural close is SAFE -------------------------


def test_value_on_structural_close_is_safe() raises:
    """A value slot that lands on `}` yields safe predicates and a clean raise.

    `{"a":}` — the value index points at the closing `}` byte. is_object and
    is_array are both False (it is neither `{` nor `[`) and get_int RAISES
    cleanly (the `}` byte is not a number) with no OOB read under -D ASSERT=all.
    """
    var data = _make_bytes(String('{"a":}'))
    var rdr = iter(data)
    var v = rdr.root().field(String("a"))
    assert_false(v.is_object())
    assert_false(v.is_array())
    var raised = False
    try:
        _ = v.get_int()
    except:
        raised = True
    assert_true(raised, "get_int on a `}` value slot must raise cleanly")


# --- F. Accept subset through On-Demand (cross-check M0-M2 still hold) --------


def test_accept_subset_full_object() raises:
    """A representative valid object reads every leaf type through On-Demand."""
    var data = _make_bytes(
        String(
            '{"name":"jsonette","count":42,"ratio":1.5,"ok":true,"empty":null,'
            + '"tags":["a","b"],"nested":{"k":7}}'
        )
    )
    var rdr = iter(data)

    assert_equal(
        rdr.root().field(String("name")).get_string(), String("jsonette")
    )
    assert_equal(rdr.root().field(String("count")).get_int(), Int64(42))
    var ratio = rdr.root().field(String("ratio")).get_float()
    assert_true(
        (ratio - Float64(1.5)) < Float64(1e-9)
        and (Float64(1.5) - ratio) < Float64(1e-9),
        "ratio must be within 1e-9 of 1.5",
    )
    assert_equal(rdr.root().field(String("ok")).get_bool(), True)
    assert_true(rdr.root().field(String("empty")).is_null())

    var tags = rdr.root().field(String("tags")).get_array()
    assert_equal(tags.next_element().get_string(), String("a"))
    assert_equal(tags.next_element().get_string(), String("b"))

    assert_equal(
        rdr.root().field(String("nested")).get_object().field(String("k")).get_int(),
        Int64(7),
    )

    # Forward iteration of the root still works: count the top-level fields.
    var iter_root = rdr.root().get_object()
    var count = 0
    while not iter_root.at_end():
        var f = iter_root.next_field()
        _ = f.key()
        count += 1
    assert_true(count >= 7, "root forward iteration must yield >= 7 fields")


def test_accept_space_before_close_terminator() raises:
    """A space between the digits and the close brace terminates the number.

    `{"n":1 }` — the space ends the integer token, so get_int == 1 (the M3.1
    review's minor suggestion, pinned here).
    """
    var data = _make_bytes(String('{"n":1 }'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("n")).get_int(), Int64(1))


def main() raises:
    test_accessed_number_trailing_junk_raises()
    test_accessed_bad_string_escape_raises()
    test_accessed_unclosed_string_raises()
    test_accessed_invalid_literal_raises()
    test_unread_bad_leaf_does_not_raise()
    test_skipped_double_comma_array_invisible()
    test_skipped_missing_colon_object_invisible()
    test_comma_for_colon_adjacency_unchecked()
    test_value_on_structural_close_is_safe()
    test_accept_subset_full_object()
    test_accept_space_before_close_terminator()
    print("test_lazy_contract: all passed")
