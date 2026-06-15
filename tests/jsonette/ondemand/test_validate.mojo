"""On-Demand `validate()` — strict no-tape RFC-8259 walk over the structural index.

`Parser.validate(data)` runs Stage 1 (structural indexing) and a strict
recursive-descent grammar walk over the resulting structural positions, building
NO tape. It returns normally iff the document is valid RFC 8259 and raises a
ParseError otherwise. This is the whole-document validator the lazy On-Demand
reader deliberately is NOT (see test_lazy_contract).

Groups:
- ACCEPT: representative valid documents (each leaf type, nesting, duplicate
  keys, large, scientific, and signed numbers, mixed arrays/objects) return cleanly.
- REJECT: malformed documents (empty/whitespace, truncated containers, trailing
  content, glued/invalid numbers, leading/double/trailing commas, missing colon/
  comma, non-string keys, bare structural bytes, unclosed string, bad escape)
  each RAISE.
- DEPTH: the validator's nesting-depth rejection boundary is derived EMPIRICALLY
  from the DOM `parse()` so it matches the builder by construction (accepts at
  K-1, raises at the same K where parse() first rejects).

Tests go through the public surface only: build `List[UInt8]` from a String,
`var p = Parser()`, then `p.validate(data)`.
"""

from std.testing import assert_true
from jsonette.parser import Parser
from jsonette.document import parse


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def _accepts(s: String) raises -> Bool:
    """Return True iff `validate` returns normally on the bytes of `s`."""
    var data = _make_bytes(s)
    var p = Parser()
    try:
        p.validate(data)
    except:
        return False
    return True


def _parse_accepts(s: String) raises -> Bool:
    """Return True iff the DOM `parse` returns normally on the bytes of `s`."""
    var data = _make_bytes(s)
    try:
        _ = parse(data)
    except:
        return False
    return True


# --- ACCEPT: valid documents return cleanly ----------------------------------


def test_accept_cases() raises:
    """Each representative valid document validates without raising."""
    var cases = [
        String("42"),
        String("-0"),
        String('"x"'),
        String('"é"'),
        String("true"),
        String("false"),
        String("null"),
        String("[]"),
        String("{}"),
        String("[[]]"),
        String('{"a":{}}'),
        String('{"a":1,"a":2}'),  # duplicate keys are valid JSON
        String("1e999"),
        String("1.5e-3"),
        String("-12.34"),
        String('{"a":[1,2,3],"b":{"c":true}}'),
        String('[1,"two",3.0,true,null,{"k":[]}]'),
    ]
    for c in cases:
        assert_true(_accepts(c), "must ACCEPT: " + c)


# --- REJECT: malformed documents raise ---------------------------------------


def test_reject_cases() raises:
    """Each malformed document is rejected (validate raises)."""
    var cases = [
        String(""),  # empty
        String("   "),  # whitespace only
        String("{"),  # unclosed object
        String("[1"),  # unclosed array
        String("[}"),  # mismatched close in value position
        String("[1]x"),  # trailing content
        String("{}{}"),  # trailing content
        String("12.3.4"),  # glued number
        String("1.2.3"),  # glued number
        String("1e1e1"),  # glued number
        String("0x1"),  # hex not JSON
        String("01"),  # leading zero
        String("1."),  # trailing dot
        String("1e"),  # truncated exponent
        String("-"),  # lone minus
        String("+1"),  # leading plus
        String(".5"),  # leading dot
        String("[1,2,]"),  # trailing comma in array
        String('{"a":1,}'),  # trailing comma in object
        String("{,}"),  # comma where key expected
        String("[,1]"),  # leading comma in array
        String("[1,,2]"),  # double comma in array
        String("[1 2]"),  # missing comma in array
        String('{"a" 1}'),  # missing colon
        String('{"a":}'),  # missing value
        String("{1:2}"),  # non-string key
        String('["a":1]'),  # colon in array
        String(","),  # bare comma
        String(":"),  # bare colon
        String('["asd]'),  # unclosed string
        String('{"k":"\\x"}'),  # bad escape (single backslash + x on the wire)
    ]
    for c in cases:
        assert_true(not _accepts(c), "must REJECT: " + c)


def test_reject_literal_glue() raises:
    """A literal glued to trailing junk is rejected (no token-boundary slack).

    Stage 1 folds a non-structural suffix glued to a `true`/`false`/`null`
    literal into the same scalar, so the glued bytes are never seen as a
    separate structural. Each of these is rejected by Python `json.loads`, so
    `validate` must reject them too — at top level and nested inside arrays and
    objects.
    """
    var cases = [
        String("truex"),
        String("trueX"),
        String("true1"),
        String("truefalse"),
        String("nullnull"),
        String("nulla"),
        String("falsey"),
        String("falsehood"),
        String("[truex]"),
        String('{"a":truex}'),
        String('{"a":truex,"b":2}'),
        String("[true,false,nullx]"),
    ]
    for c in cases:
        assert_true(not _accepts(c), "must REJECT: " + c)


def test_accept_literals_at_boundary() raises:
    """A literal followed by a clean terminator (`,`/`}`/`]`/EOF) still accepts.

    The token-boundary guard must not over-reject valid literals: bare literals
    and literals followed by a comma or a closing bracket/brace are valid JSON
    and must still validate.
    """
    var cases = [
        String("true"),
        String("false"),
        String("null"),
        String("[true,false,null]"),
        String('{"a":true}'),
        String('{"ok":true,"x":1}'),
        String('{"a":true,"b":false,"c":null}'),
    ]
    for c in cases:
        assert_true(_accepts(c), "must ACCEPT: " + c)


def test_bad_escape_on_the_wire() raises:
    """The bad-escape reject case is a single backslash + x on the wire."""
    var data = _make_bytes(String('{"k":"\\x"}'))
    # bytes:  { " k " : " \ x " }
    # index:  0 1 2 3 4 5 6 7 8 9
    assert_true(data[6] == UInt8(0x5C), "byte 6 must be a single backslash")
    assert_true(data[7] == UInt8(0x78), "byte 7 must be x")


# --- DEPTH: empirically match the DOM builder's rejection boundary -----------


def _nested(k: Int) -> String:
    """Return a string of `k` nested arrays: `[`*k + `]`*k."""
    var s = String("")
    for _ in range(k):
        s += "["
    for _ in range(k):
        s += "]"
    return s^


def test_depth_boundary_matches_parse() raises:
    """Validate's depth rejection matches parse: accept at K-1, reject at K.

    K is the first nesting depth at which the DOM `parse()` rejects (probed in a
    modest range). The validator must mirror the builder by construction: it
    accepts the K-1 nesting and rejects the K nesting at the SAME K.
    """
    var k = 0
    # Probe upward for the first depth parse() rejects. MAX_DEPTH is 1024 in the
    # builder, so the boundary is at 1025; cap the probe well above that.
    for cand in range(1, 1100):
        if not _parse_accepts(_nested(cand)):
            k = cand
            break
    assert_true(k > 1, "parse() must reject at some depth K > 1 within probe range")

    # Just below the boundary: parse() accepts and so must validate().
    assert_true(_parse_accepts(_nested(k - 1)), "parse must ACCEPT at K-1")
    assert_true(_accepts(_nested(k - 1)), "validate must ACCEPT at K-1")

    # At the boundary: parse() rejects and so must validate().
    assert_true(not _parse_accepts(_nested(k)), "parse must REJECT at K")
    assert_true(not _accepts(_nested(k)), "validate must REJECT at K")


def main() raises:
    test_accept_cases()
    test_reject_cases()
    test_reject_literal_glue()
    test_accept_literals_at_boundary()
    test_bad_escape_on_the_wire()
    test_depth_boundary_matches_parse()
    print("test_validate: all passed")
