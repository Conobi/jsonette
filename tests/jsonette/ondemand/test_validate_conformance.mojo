"""Convergence gate: `Parser.validate` agrees with an INDEPENDENT oracle.

The strict `Parser.validate` is an RFC-8259 no-tape validator (returns iff valid,
else raises). The DOM `parse()` is broadly permissive and silently accepts many
malformed inputs (`,`, `:`, `{,}`, `[,1]`, `1.2.3`, trailing commas, ...), so it
is NOT a usable reject oracle. The AUTHORITATIVE oracle is Python's `json.loads`,
which shares none of jsonette's code.

The (vector, expected-verdict) table below is GENERATED — not hand-guessed — by
`tests/oracle/validate_oracle.py`, whose verdicts come from `json.loads`. To
regenerate it, run `python3 tests/oracle/validate_oracle.py` and paste its
"Mojo-pasteable block" into the two literal lists here. NaN/Infinity are
deliberately absent: `json.loads` accepts those Python extensions but RFC 8259
and jsonette reject them, which would be a non-bug disagreement.

Three gates:
- AUTHORITATIVE: for every vector, `validate()` accepts iff the oracle accepts.
- ACCEPT/REJECT split asserted from the generated table directly.
- SAFETY NET (one-directional): for every REJECT vector that the permissive DOM
  `parse()` itself rejects, `validate()` must ALSO reject it — guarding the
  validator from being more lenient than even the DOM. (The converse is not
  asserted, because `parse()` over-accepts.)

Note on byte spelling: Mojo's `\\xNN` String escape is a Unicode-CODEPOINT
escape, not a raw-byte escape, so multibyte vectors are spelled as direct UTF-8
source characters (`_b`) and any non-spellable sequence (a leading UTF-8 BOM)
is given as an explicit byte list (`_raw`).
"""

from std.testing import assert_true
from jsonette.parser import Parser


def _b(s: String) -> List[UInt8]:
    """Build a `List[UInt8]` from the UTF-8 bytes of a String literal vector."""
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def _raw(bytes: List[Int]) -> List[UInt8]:
    """Build a `List[UInt8]` from explicit byte values (for non-spellable wires)."""
    var buf = List[UInt8]()
    for b in bytes:
        buf.append(UInt8(b))
    return buf^


def _validate_accepts(data: List[UInt8]) raises -> Bool:
    """Return True iff `validate` returns normally on `data` (else it raised)."""
    var p = Parser()
    try:
        p.validate(data)
    except:
        return False
    return True


def _parse_rejects(data: List[UInt8]) raises -> Bool:
    """Return True iff the permissive DOM `parse` raises on `data`."""
    var rejected = False
    var p = Parser()
    try:
        _ = p.parse(data)
    except:
        rejected = True
    return rejected


# --- Generated verdict table (provenance: tests/oracle/validate_oracle.py) ----
# verdict is the json.loads result; this table mirrors it exactly.


def _accept_vectors() -> List[List[UInt8]]:
    """Vectors `json.loads` ACCEPTS (validate must accept each)."""
    return [
        # --- ACCEPT vectors (json.loads accepts) ---
        _b("42"),  # int
        _b("-0"),  # neg_zero
        _b("0"),  # zero
        _b("3.14"),  # float
        _b("-12.34"),  # neg_float
        _b("1e10"),  # exp_lower
        _b("1E10"),  # exp_upper
        _b("1.0e+1"),  # exp_plus
        _b("1.5e-3"),  # exp_minus
        _b("1e999"),  # exp_huge
        _b("123456789012345678901234567890"),  # bignum
        _b("\"x\""),  # str
        _b("\"hello world\""),  # str_words
        _b("\"a\\\"b\""),  # str_escaped_quote
        _b("\"{}\""),  # str_braces
        _b("\"[,:]\""),  # str_structural
        _b("\"é\""),  # str_utf8
        _b("true"),  # true
        _b("false"),  # false
        _b("null"),  # null
        _b("[]"),  # empty_arr
        _b("{}"),  # empty_obj
        _b("[1,2,3]"),  # arr_ints
        _b("[1,\"two\",3.0,true,null]"),  # arr_mixed
        _b("[\"a\",\"b\"]"),  # arr_strs
        _b("{\"a\":1}"),  # obj_one
        _b("{\"a\":1,\"b\":2}"),  # obj_two
        _b("{\"a\":1,\"a\":2}"),  # obj_dup_keys
        _b("[[]]"),  # arr_nested_empty
        _b("[[],[]]"),  # arr_two_empty
        _b("{\"a\":{}}"),  # obj_nested_empty
        _b("{\"a\":[1,2],\"b\":{\"c\":true}}"),  # obj_nested_mixed
        _b("[ 1 , 2 ]"),  # arr_ws
        _b("{\"a\" : 1}"),  # obj_colon_ws
        _b("{\"\":1}"),  # obj_empty_key
        _b("[true,false,null]"),  # arr_literals
    ]


def _reject_vectors() -> List[List[UInt8]]:
    """Vectors `json.loads` REJECTS (validate must reject each)."""
    return [
        # --- REJECT vectors (json.loads rejects) ---
        _b(""),  # empty
        _b("   "),  # ws_only
        _b("{"),  # open_obj
        _b("["),  # open_arr
        _b("[1"),  # trunc_arr
        _b("{\"a\""),  # trunc_obj_key
        _b("{\"a\":"),  # trunc_obj_colon
        _b("[}"),  # close_mismatch_arr
        _b("{]"),  # close_mismatch_obj
        _b("[1]x"),  # trailing_after_arr
        _b("{}{}"),  # two_objs
        _b("[1]]"),  # extra_close
        _b("12.3.4"),  # num_two_dots
        _b("1.2.3"),  # num_glue_dots
        _b("1e1e1"),  # num_two_exp
        _b("1..2"),  # num_double_dot
        _b("0x1"),  # num_hex
        _b("01"),  # num_leading_zero
        _b("1."),  # num_trailing_dot
        _b("1e"),  # num_bare_exp
        _b("-"),  # num_lone_minus
        _b("+1"),  # num_leading_plus
        _b(".5"),  # num_leading_dot
        _b("42x"),  # int_glue
        _b("truex"),  # true_glue
        _b("nullx"),  # null_glue
        _b("falsey"),  # false_glue
        _b("nullnull"),  # null_null
        _b("[1,2,]"),  # arr_trailing_comma
        _b("{\"a\":1,}"),  # obj_trailing_comma
        _b("{,}"),  # obj_comma_no_key
        _b("[,1]"),  # arr_leading_comma
        _b("[1,,2]"),  # arr_double_comma
        _b("[1 2]"),  # arr_missing_comma
        _b("{\"a\" 1}"),  # obj_missing_colon
        _b("{\"a\":}"),  # obj_missing_value
        _b("{1:2}"),  # obj_nonstring_key
        _b("[\"a\":1]"),  # arr_colon
        _b(","),  # bare_comma
        _b(":"),  # bare_colon
        _b("[\"asd]"),  # unclosed_str
        _b("{\"k\":\"\\x\"}"),  # bad_escape
        _raw([0xef, 0xbb, 0xbf, 0x34, 0x32]),  # bom_then_42
    ]


def _label(data: List[UInt8]) -> String:
    """Render a vector's ASCII-ish bytes for an assertion message."""
    var out = String("")
    for b in data:
        if b >= UInt8(0x20) and b < UInt8(0x7F):
            out += chr(Int(b))
        else:
            out += "<" + String(Int(b)) + ">"
    return out^


# --- GATE 1: AUTHORITATIVE — validate() accepts iff json.loads accepts --------


def test_accept_vectors_validate() raises:
    """Every json.loads-accepted vector must validate without raising."""
    var vectors = _accept_vectors()
    for v in vectors:
        assert_true(_validate_accepts(v), "validate must ACCEPT: " + _label(v))


def test_reject_vectors_validate() raises:
    """Every json.loads-rejected vector must be rejected (validate raises)."""
    var vectors = _reject_vectors()
    for v in vectors:
        assert_true(not _validate_accepts(v), "validate must REJECT: " + _label(v))


# --- GATE 3: one-directional parse() safety net (reject vectors only) ---------


def test_parse_rejects_imply_validate_rejects() raises:
    """If the permissive DOM rejects a vector, validate must reject it too.

    One-directional: only over the REJECT vectors, and only the implication
    `parse rejects => validate rejects`. The converse is intentionally NOT
    asserted because `parse()` over-accepts many malformed inputs.
    """
    var vectors = _reject_vectors()
    for v in vectors:
        if _parse_rejects(v):
            assert_true(
                not _validate_accepts(v),
                "parse rejected but validate accepted: " + _label(v),
            )


def main() raises:
    test_accept_vectors_validate()
    test_reject_vectors_validate()
    test_parse_rejects_imply_validate_rejects()
    print("test_validate_conformance: all passed")
