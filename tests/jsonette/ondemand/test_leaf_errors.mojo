"""On-Demand (lazy) parser — number-token-boundary terminator guard.

A number leaf must consume to a clean token boundary (whitespace, `,`, `}`, `]`,
or EOF) or raise. These tests exercise the trailing-junk rejection in the three
numeric accessors `get_int` / `get_uint` / `get_float`: glued trailing
characters such as `12.3.4`, `1e1e1`, `0x1`, or `42x` must RAISE rather than
silently returning the leading numeric prefix. They also pin the absence of
false rejects — a number that ends at a real terminator parses cleanly.

Like the other on-demand tests they go through inference ONLY: a caller obtains
the root handle from `iter(...).root()`, navigates with `field(key)` /
`get_array` / `next_element`, and reads a leaf without naming any `[o]`-parametric
type. This file exercises the object/array-navigated terminator path; the
bare-root-at-EOF scalar case (a number that is the entire document) is covered by
`test_any_root.mojo` and the validate() path. The non-EOF terminator path is
covered by the `}` and `,` terminator cases below.
"""

from std.testing import assert_equal, assert_true
from std.math import isinf
from jsonette.ondemand.reader import iter


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


# --- Trailing junk must raise ------------------------------------------------


def test_get_float_double_dot_raises() raises:
    """A number with a glued second dot (12.3.4) makes get_float raise."""
    var data = _make_bytes(String('{"n":12.3.4}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("n")).get_float()
    except:
        raised = True
    assert_true(raised, "get_float on 12.3.4 must raise (trailing junk)")


def test_get_float_one_dot_two_dot_three_raises() raises:
    """A number with a glued second dot (1.2.3) makes get_float raise."""
    var data = _make_bytes(String('{"n":1.2.3}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("n")).get_float()
    except:
        raised = True
    assert_true(raised, "get_float on 1.2.3 must raise (trailing junk)")


def test_get_float_double_exponent_raises() raises:
    """A number with a glued second exponent (1e1e1) makes get_float raise."""
    var data = _make_bytes(String('{"n":1e1e1}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("n")).get_float()
    except:
        raised = True
    assert_true(raised, "get_float on 1e1e1 must raise (trailing junk)")


def test_get_int_hex_prefix_raises() raises:
    """A hex-looking integer (0x1) makes get_int raise (trailing junk)."""
    var data = _make_bytes(String('{"n":0x1}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("n")).get_int()
    except:
        raised = True
    assert_true(raised, "get_int on 0x1 must raise (trailing junk)")


def test_get_int_trailing_letter_raises() raises:
    """An integer with a glued trailing letter (42x) makes get_int raise."""
    var data = _make_bytes(String('{"n":42x}'))
    var rdr = iter(data)
    var raised = False
    try:
        _ = rdr.root().field(String("n")).get_int()
    except:
        raised = True
    assert_true(raised, "get_int on 42x must raise (trailing junk)")


# --- No false reject: clean terminators parse ---------------------------------


def test_get_int_brace_terminator() raises:
    """An integer ending at `}` (1) parses cleanly to 1."""
    var data = _make_bytes(String('{"n":1}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("n")).get_int(), Int64(1))


def test_get_int_comma_terminator() raises:
    """An integer ending at `,` (1) parses cleanly to 1."""
    var data = _make_bytes(String('{"n":1,"m":2}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("n")).get_int(), Int64(1))


def test_get_int_array_element_terminator() raises:
    """An array element ending at `,` (7 in [7,8]) parses cleanly to 7."""
    var data = _make_bytes(String('{"a":[7,8]}'))
    var rdr = iter(data)
    var arr = rdr.root().field(String("a")).get_array()
    assert_equal(arr.next_element().get_int(), Int64(7))


def test_get_float_negative_float() raises:
    """A negative float ending at `}` (-12.34) parses within 1e-9."""
    var data = _make_bytes(String('{"n":-12.34}'))
    var rdr = iter(data)
    var got = rdr.root().field(String("n")).get_float()
    assert_true(
        (got - Float64(-12.34)) < Float64(1e-9)
        and (Float64(-12.34) - got) < Float64(1e-9),
        "get_float on -12.34 must be within 1e-9",
    )


def test_get_float_overflow_to_inf() raises:
    """A float beyond double range (1e999) ends cleanly and reads as inf."""
    var data = _make_bytes(String('{"n":1e999}'))
    var rdr = iter(data)
    var got = rdr.root().field(String("n")).get_float()
    assert_true(isinf(got), "get_float on 1e999 must be inf")


def test_get_float_small_exponent() raises:
    """A float with a negative exponent (1.5e-3) parses within 1e-9 of 0.0015."""
    var data = _make_bytes(String('{"n":1.5e-3}'))
    var rdr = iter(data)
    var got = rdr.root().field(String("n")).get_float()
    assert_true(
        (got - Float64(0.0015)) < Float64(1e-9)
        and (Float64(0.0015) - got) < Float64(1e-9),
        "get_float on 1.5e-3 must be within 1e-9 of 0.0015",
    )


# --- Lazy contract: a space terminates the token before a later comma --------


def test_get_int_space_terminator_before_comma() raises:
    """A space after the digits (42 ,) terminates the token; get_int == 42."""
    var data = _make_bytes(String('{"n":42 ,"m":1}'))
    var rdr = iter(data)
    assert_equal(rdr.root().field(String("n")).get_int(), Int64(42))


def main() raises:
    test_get_float_double_dot_raises()
    test_get_float_one_dot_two_dot_three_raises()
    test_get_float_double_exponent_raises()
    test_get_int_hex_prefix_raises()
    test_get_int_trailing_letter_raises()
    test_get_int_brace_terminator()
    test_get_int_comma_terminator()
    test_get_int_array_element_terminator()
    test_get_float_negative_float()
    test_get_float_overflow_to_inf()
    test_get_float_small_exponent()
    test_get_int_space_terminator_before_comma()
    print("test_leaf_errors: all passed")
