#!/usr/bin/env python3
"""Independent reject/accept oracle for jsonette's strict `Parser.validate`.

Run it:

    python3 tests/oracle/validate_oracle.py

For each vector below it computes a verdict the AUTHORITATIVE way — by calling
the Python standard library's `json.loads` (which shares NONE of jsonette's
code): a vector that `json.loads` parses is "accept"; a vector that raises
`ValueError` (its `json.JSONDecodeError` subclass) is "reject". It prints both a
human summary and a Mojo-pasteable block.

The Mojo conformance test
(`tests/jsonette/ondemand/test_validate_conformance.mojo`) embeds the table this
script emits, so the expected verdicts come from the oracle and are never hand
guessed. Regenerate the embedded table by re-running this script and pasting its
"Mojo-pasteable block".

Oracle caveats (why certain inputs are deliberately absent):
- `json.loads` ACCEPTS the Python extensions `NaN`, `Infinity`, `-Infinity` as
  bare tokens, but RFC 8259 and jsonette REJECT them. Including them would make
  the oracle and `validate` disagree for a NON-bug reason, so they are excluded.
- `json.loads("1e999")` accepts (yielding `inf`); jsonette also accepts a
  syntactically-valid out-of-range exponent, so `1e999` is a fair ACCEPT vector.
- `json.loads` accepts surrounding ASCII whitespace; vectors here avoid leading/
  trailing whitespace except the explicit internal-whitespace ACCEPT cases.
- `json.loads` LENIENTLY accepts lone/unpaired UTF-16 surrogate escapes (e.g.
  `"\uD800"`, `"\uDFFF"`), but RFC 8259 and jsonette correctly REJECT them. Like
  NaN/Infinity, this is a deliberate Python-vs-RFC divergence — do NOT add lone
  surrogates as ACCEPT vectors (they would spuriously "disagree" with `validate`).
"""

import json

# Each entry is (label, value). `label` is a short ASCII tag used only for the
# Mojo comment; `value` is the exact text whose bytes are validated. Non-ASCII
# and on-the-wire-escape cases are constructed explicitly so the bytes are
# unambiguous (see notes inline).

ACCEPT = [
    ("int", "42"),
    ("neg_zero", "-0"),
    ("zero", "0"),
    ("float", "3.14"),
    ("neg_float", "-12.34"),
    ("exp_lower", "1e10"),
    ("exp_upper", "1E10"),
    ("exp_plus", "1.0e+1"),
    ("exp_minus", "1.5e-3"),
    ("exp_huge", "1e999"),
    ("bignum", "123456789012345678901234567890"),
    ("str", '"x"'),
    ("str_words", '"hello world"'),
    ("str_escaped_quote", '"a\\"b"'),  # JSON: "a\"b" -> bytes contain \ "
    ("str_braces", '"{}"'),
    ("str_structural", '"[,:]"'),  # structural-looking bytes INSIDE a string
    ("str_utf8", '"é"'),  # multibyte UTF-8 ('é')
    ("true", "true"),
    ("false", "false"),
    ("null", "null"),
    ("empty_arr", "[]"),
    ("empty_obj", "{}"),
    ("arr_ints", "[1,2,3]"),
    ("arr_mixed", '[1,"two",3.0,true,null]'),
    ("arr_strs", '["a","b"]'),
    ("obj_one", '{"a":1}'),
    ("obj_two", '{"a":1,"b":2}'),
    ("obj_dup_keys", '{"a":1,"a":2}'),  # duplicate keys: RFC allows
    ("arr_nested_empty", "[[]]"),
    ("arr_two_empty", "[[],[]]"),
    ("obj_nested_empty", '{"a":{}}'),
    ("obj_nested_mixed", '{"a":[1,2],"b":{"c":true}}'),
    ("arr_ws", "[ 1 , 2 ]"),  # internal whitespace
    ("obj_colon_ws", '{"a" : 1}'),  # spaces around colon
    ("obj_empty_key", '{"":1}'),  # empty key
    ("arr_literals", "[true,false,null]"),
]

REJECT = [
    ("empty", ""),
    ("ws_only", "   "),
    ("open_obj", "{"),
    ("open_arr", "["),
    ("trunc_arr", "[1"),
    ("trunc_obj_key", '{"a"'),
    ("trunc_obj_colon", '{"a":'),
    ("close_mismatch_arr", "[}"),
    ("close_mismatch_obj", "{]"),
    ("trailing_after_arr", "[1]x"),
    ("two_objs", "{}{}"),
    ("extra_close", "[1]]"),
    ("num_two_dots", "12.3.4"),
    ("num_glue_dots", "1.2.3"),
    ("num_two_exp", "1e1e1"),
    ("num_double_dot", "1..2"),
    ("num_hex", "0x1"),
    ("num_leading_zero", "01"),
    ("num_trailing_dot", "1."),
    ("num_bare_exp", "1e"),
    ("num_lone_minus", "-"),
    ("num_leading_plus", "+1"),
    ("num_leading_dot", ".5"),
    ("int_glue", "42x"),
    ("true_glue", "truex"),
    ("null_glue", "nullx"),
    ("false_glue", "falsey"),
    ("null_null", "nullnull"),
    ("arr_trailing_comma", "[1,2,]"),
    ("obj_trailing_comma", '{"a":1,}'),
    ("obj_comma_no_key", "{,}"),
    ("arr_leading_comma", "[,1]"),
    ("arr_double_comma", "[1,,2]"),
    ("arr_missing_comma", "[1 2]"),
    ("obj_missing_colon", '{"a" 1}'),
    ("obj_missing_value", '{"a":}'),
    ("obj_nonstring_key", "{1:2}"),
    ("arr_colon", '["a":1]'),
    ("bare_comma", ","),
    ("bare_colon", ":"),
    ("unclosed_str", '["asd]'),  # unclosed string inside array
    ("bad_escape", '{"k":"\\x"}'),  # single backslash + x on the wire
    ("bom_then_42", "﻿42"),  # leading UTF-8 BOM (0xEF 0xBB 0xBF) then 42
]


def verdict(value: str) -> str:
    """Return 'accept' if `json.loads` parses `value`, else 'reject'.

    `json.JSONDecodeError` subclasses `ValueError`, so catching `ValueError`
    covers every malformed-input failure mode `json.loads` reports.
    """
    try:
        json.loads(value)
        return "accept"
    except ValueError:
        return "reject"


def _mojo_expr(value: str) -> str:
    """Render `value` as a Mojo expression that yields its exact wire bytes.

    Mojo's `\\xNN` escape is a UNICODE-CODEPOINT escape (U+00NN, then UTF-8
    encoded), NOT a raw-byte escape — verified on the 1.0.0b1 toolchain — so it
    cannot spell an arbitrary raw byte. This emitter therefore:
      * keeps printable ASCII as-is (escaping `\\` and `"`),
      * keeps valid multibyte UTF-8 as the literal source character (Mojo source
        is UTF-8, so e.g. 'é' round-trips to bytes 0xC3 0xA9),
      * falls back to an explicit `_raw([...])` byte list for any sequence not
        safely spellable as a String literal (e.g. a leading UTF-8 BOM).
    Both `_b("...")` and `_raw([...])` yield a `List[UInt8]` in the Mojo test, so
    the embedded table is a uniform `List[List[UInt8]]` and a faithful,
    regenerable image of the oracle's vectors.
    """
    raw = value.encode("utf-8")
    if _is_string_safe(raw):
        out = ['_b("']
        for ch in value:
            if ch == "\\":
                out.append("\\\\")
            elif ch == '"':
                out.append('\\"')
            else:
                out.append(ch)
        out.append('")')
        return "".join(out)
    body = ", ".join("0x%02x" % b for b in raw)
    return "_raw([%s])" % body


def _is_string_safe(raw: bytes) -> bool:
    """True if `raw` can be spelled directly as a Mojo UTF-8 String literal.

    A BOM or a control byte cannot (Mojo's `\\xNN` is a codepoint escape, not a
    raw byte), so such vectors are emitted as explicit byte lists instead.
    """
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return all(ch != "﻿" and ord(ch) >= 0x20 for ch in text)


def main() -> int:
    """Print the human summary and the Mojo-pasteable verdict block.

    Also enforces the contract this oracle exists for: every ACCEPT-group vector
    must `json.loads`-accept and every REJECT-group vector must `json.loads`-
    reject. If the standard library disagrees with the intended grouping, the
    script exits non-zero so the disagreement cannot be silently shipped.
    """
    mismatches = []

    print("=== Oracle verdicts (json.loads) ===")
    for group, expected, vectors in (
        ("ACCEPT", "accept", ACCEPT),
        ("REJECT", "reject", REJECT),
    ):
        print("--- %s group (intended: %s) ---" % (group, expected))
        for label, value in vectors:
            got = verdict(value)
            mark = "ok " if got == expected else "!! "
            print("  %s%-22s -> %s" % (mark, label, got))
            if got != expected:
                mismatches.append((group, label, value, expected, got))

    print()
    print("=== Mojo-pasteable block ===")
    print("# generated by tests/oracle/validate_oracle.py — do not hand-edit")
    print("# verdict is the json.loads result; the Mojo table mirrors it exactly")
    print("    # --- ACCEPT vectors (json.loads accepts) ---")
    for label, value in ACCEPT:
        print('    %s,  # %s' % (_mojo_expr(value), label))
    print("    # --- REJECT vectors (json.loads rejects) ---")
    for label, value in REJECT:
        print('    %s,  # %s' % (_mojo_expr(value), label))

    print()
    n = len(ACCEPT) + len(REJECT)
    print("Summary: %d vectors (%d accept, %d reject), %d oracle mismatches"
          % (n, len(ACCEPT), len(REJECT), len(mismatches)))
    if mismatches:
        print("ORACLE MISMATCH — these vectors do not match their intended group:")
        for group, label, value, expected, got in mismatches:
            print("  [%s] %s expected=%s json.loads=%s value=%r"
                  % (group, label, expected, got, value))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
