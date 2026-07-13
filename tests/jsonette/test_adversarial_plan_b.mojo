"""Adversarial tests for Plan B (M1 zero-copy + M2 raw span / escape-free fast path).

Each test targets a specific attack surface in the new code paths:
- _needs_slow_string_path guard completeness (control chars, DEL, NUL, UTF-8)
- _raw_string_span invariant under adversarial strings
- DOM nocopy lifetime and correctness
- OD nocopy parity with copy path
"""

from std.testing import assert_equal, assert_true
from std.memory import memcpy, memset, UnsafePointer
from jsonette.document import parse, parse_nocopy
from jsonette.ondemand.reader import iter as od_iter, iter_nocopy
from jsonette.stage1.indexer import structural_index
from jsonette.stage2.strings import _raw_string_span
from jsonette.ondemand.ondemand import _needs_slow_string_path


# ──────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────

def _make_padded(s: String) -> List[UInt8]:
    """Create a padded buffer matching Parser's formula: ceil(n/64)*64 + 128."""
    var data = s.as_bytes()
    var input_len = len(data)
    var num_chunks = (input_len + 63) // 64
    var padded_len = num_chunks * 64 + 128
    var buf = List[UInt8](unsafe_uninit_length=padded_len)
    memcpy(dest=buf.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
    memset(buf.unsafe_ptr() + input_len, 0, padded_len - input_len)
    return buf^


def _make_padded_bytes(data: List[UInt8]) -> List[UInt8]:
    """Create a padded buffer from raw bytes."""
    var input_len = len(data)
    var num_chunks = (input_len + 63) // 64
    var padded_len = num_chunks * 64 + 128
    var buf = List[UInt8](unsafe_uninit_length=padded_len)
    memcpy(dest=buf.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
    memset(buf.unsafe_ptr() + input_len, 0, padded_len - input_len)
    return buf^


def _bytes_from_string(s: String) -> List[UInt8]:
    """Extract a List[UInt8] from a String (copies)."""
    var sb = s.as_bytes()
    var out = List[UInt8](capacity=len(sb))
    for b in sb:
        out.append(b)
    return out^


# ──────────────────────────────────────────────────────────────────────
# ATTACK 1: Control-char / escape guard completeness
# ──────────────────────────────────────────────────────────────────────

def test_guard_nul_byte() raises:
    """NUL (0x00) inside a string must trigger the slow path.

    NUL is < 0x20, so _needs_slow_string_path should return True.
    More importantly, parse_string should reject unescaped NUL (control char).
    """
    # Direct guard test: a buffer containing a NUL byte
    var buf = List[UInt8](capacity=3)
    buf.append(UInt8(ord("a")))
    buf.append(UInt8(0x00))
    buf.append(UInt8(ord("b")))
    assert_true(
        _needs_slow_string_path(buf.unsafe_ptr(), len(buf)),
        "NUL byte must trigger slow path",
    )
    print("  PASS: NUL triggers slow path guard")


def test_guard_del_byte() raises:
    """DEL (0x7F) does NOT trigger the slow path.

    RFC 8259 does not require escaping DEL. It is > 0x1F so the guard
    should let it through (fast path). Verify the fast path handles it.
    """
    var buf = List[UInt8](capacity=3)
    buf.append(UInt8(ord("a")))
    buf.append(UInt8(0x7F))
    buf.append(UInt8(ord("b")))
    assert_true(
        not _needs_slow_string_path(buf.unsafe_ptr(), len(buf)),
        "DEL (0x7F) should NOT trigger slow path (RFC 8259 allows it unescaped)",
    )
    print("  PASS: DEL (0x7F) correctly uses fast path")


def test_guard_all_control_chars() raises:
    """Every control char 0x00..0x1F must trigger the slow path."""
    for c in range(0x20):
        var buf = List[UInt8](capacity=1)
        buf.append(UInt8(c))
        assert_true(
            _needs_slow_string_path(buf.unsafe_ptr(), 1),
            "control char must trigger slow path",
        )
    print("  PASS: all 0x00..0x1F trigger slow path")


def test_guard_boundary_0x20() raises:
    """0x20 (space) should NOT trigger the slow path.

    It is the first non-control byte, right at the boundary.
    """
    var buf = List[UInt8](capacity=1)
    buf.append(UInt8(0x20))
    assert_true(
        not _needs_slow_string_path(buf.unsafe_ptr(), 1),
        "space (0x20) should NOT trigger slow path",
    )
    print("  PASS: 0x20 (space) correctly uses fast path")


def test_guard_empty_content() raises:
    """Empty content (length 0) should NOT trigger slow path.

    This is the empty string "" case.
    """
    var buf = List[UInt8](capacity=1)
    buf.append(UInt8(0x41))  # anything, length is 0
    assert_true(
        not _needs_slow_string_path(buf.unsafe_ptr(), 0),
        "empty content must use fast path",
    )
    print("  PASS: empty content uses fast path")


def test_guard_only_control_chars() raises:
    """A string containing ONLY control chars must trigger slow path."""
    var buf = List[UInt8](capacity=4)
    buf.append(UInt8(0x01))
    buf.append(UInt8(0x02))
    buf.append(UInt8(0x03))
    buf.append(UInt8(0x04))
    assert_true(
        _needs_slow_string_path(buf.unsafe_ptr(), 4),
        "all-control-char content must trigger slow path",
    )
    print("  PASS: all-control-char content triggers slow path")


def test_guard_high_utf8_bytes() raises:
    """High-byte UTF-8 sequences (> 0x7F) should NOT trigger slow path.

    These are valid UTF-8 continuation/lead bytes, not control chars.
    The guard only checks < 0x20 and == 0x5C.
    """
    # e-acute: U+00E9 = 0xC3 0xA9 in UTF-8
    var buf = List[UInt8](capacity=2)
    buf.append(UInt8(0xC3))
    buf.append(UInt8(0xA9))
    assert_true(
        not _needs_slow_string_path(buf.unsafe_ptr(), 2),
        "UTF-8 high bytes should NOT trigger slow path",
    )
    # 4-byte UTF-8: U+1F600 (grinning face) = F0 9F 98 80
    var buf4 = List[UInt8](capacity=4)
    buf4.append(UInt8(0xF0))
    buf4.append(UInt8(0x9F))
    buf4.append(UInt8(0x98))
    buf4.append(UInt8(0x80))
    assert_true(
        not _needs_slow_string_path(buf4.unsafe_ptr(), 4),
        "4-byte UTF-8 should NOT trigger slow path",
    )
    print("  PASS: high-byte UTF-8 correctly uses fast path")


def test_od_utf8_string_fast_path() raises:
    """OD get_string for UTF-8 strings without escapes uses the fast path correctly.

    The string contains multi-byte UTF-8 but no backslash and no control chars,
    so the fast path should be taken and the returned String should be correct.
    """
    # "café" = "cafe" + combining acute accent, but let's use a precomposed form
    # Use e-acute: \xc3\xa9 in the JSON directly (valid UTF-8, no escape needed)
    var raw = _bytes_from_string(String('{"name": "caf'))
    raw.append(UInt8(0xC3))
    raw.append(UInt8(0xA9))
    for b in String('"}').as_bytes():
        raw.append(b)

    var padded = _make_padded_bytes(raw)
    var reader = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(raw),
    )
    var result = reader.root().get_object().field("name").get_string()
    # The result should be "caf" + e-acute (2 UTF-8 bytes)
    var rb = result.as_bytes()
    assert_equal(len(rb), 5)
    assert_equal(rb[3], UInt8(0xC3))
    assert_equal(rb[4], UInt8(0xA9))
    print("  PASS: UTF-8 string through fast path is correct")


def test_od_control_char_rejected_via_fast_path_guard() raises:
    """A string with an unescaped control char (no backslash) must be rejected.

    The fast path guard (_needs_slow_string_path) sees the control char and
    falls through to parse_string, which rejects it. Without the guard, the
    fast path would silently accept the control char.
    """
    # Build {"a": "x\x01y"} manually
    var raw = _bytes_from_string(String('{"a": "x'))
    raw.append(UInt8(0x01))
    for b in String('y"}').as_bytes():
        raw.append(b)

    var rejected = False
    try:
        var reader = od_iter(Span(raw))
        var obj = reader.root().get_object()
        _ = obj.field("a").get_string()
    except:
        rejected = True
    assert_true(rejected, "unescaped control char must be rejected")
    print("  PASS: unescaped control char rejected (slow path raises)")


def test_od_tab_char_rejected() raises:
    """Unescaped TAB (0x09) in a string value must be rejected.

    TAB is a control char (< 0x20). The guard should trigger slow path,
    which rejects it.
    """
    var raw = _bytes_from_string(String('{"a": "x'))
    raw.append(UInt8(0x09))  # TAB
    for b in String('y"}').as_bytes():
        raw.append(b)

    var rejected = False
    try:
        var reader = od_iter(Span(raw))
        _ = reader.root().get_object().field("a").get_string()
    except:
        rejected = True
    assert_true(rejected, "unescaped TAB must be rejected")
    print("  PASS: unescaped TAB rejected")


# ──────────────────────────────────────────────────────────────────────
# ATTACK 2: _raw_string_span invariant under adversarial strings
# ──────────────────────────────────────────────────────────────────────

def test_span_backslash_backslash_quote() raises:
    """String with \\\\\" (backslash-backslash-quote).

    In JSON: "a\\\\"  = content is a\\ (literal backslash, then closing quote).
    The escaped backslash is NOT an escape for the quote, so the closing quote
    position must be correct. Verify the raw span length.
    """
    # "a\\\\" in JSON source = a, backslash, backslash, then closing quote
    # (The last " is the real closing quote, not escaped.)
    var json = String('{"k": "a\\\\\\\\"}')
    var reader = od_iter(json)
    var result = reader.root().get_object().field("k").get_string()
    assert_equal(result, "a\\\\")
    print("  PASS: backslash-backslash-quote correctly parsed")


def test_span_long_string_multi_chunk() raises:
    """A string > 64 bytes (spanning multiple SIMD chunks).

    The raw span must cover the full string across chunk boundaries.
    """
    # Build a 200-char escape-free string
    var content = String("x" * 200)
    var json = String('{"data": "') + content + String('"}')
    var reader = od_iter(json)
    var result = reader.root().get_object().field("data").get_string()
    assert_equal(len(result.as_bytes()), 200)
    assert_equal(result, content)
    print("  PASS: long string (200 bytes, multi-chunk) correct")


def test_span_very_long_string_with_escapes() raises:
    """A long string with escape sequences spanning multiple SIMD chunks.

    The slow path must handle this correctly.
    """
    # Build a string with escapes scattered across chunk boundaries
    var content = String("")
    for _ in range(20):
        content += "abcdefghij"  # 10 clean chars
        content += "\\n"  # escape sequence
    var json = String('{"data": "') + content + String('"}')
    var reader = od_iter(json)
    var result = reader.root().get_object().field("data").get_string()
    # Each "\\n" in JSON source becomes "\n" (newline) in the parsed result
    var expected = String("")
    for _ in range(20):
        expected += "abcdefghij"
        expected += "\n"
    assert_equal(result, expected)
    print("  PASS: long string with escapes (multi-chunk) correct")


def test_span_string_at_end_of_input() raises:
    """A string at the very end of the input (right before padding zeros).

    Verify the raw span doesn't overread into padding.
    """
    var json = String('"hello"')
    var reader = od_iter(json)
    var result = reader.root().get_string()
    assert_equal(result, "hello")
    print("  PASS: string at end of input correct")


def test_span_multiple_consecutive_strings() raises:
    """Multiple strings in an array — verify si indexing is correct for each.

    Each get_string call must get the right structural index.
    """
    var json = String('["aaa", "bbb", "ccc", "ddd", "eee"]')
    var reader = od_iter(json)
    var arr = reader.root().get_array()
    var vals = List[String]()
    while not arr.at_end():
        vals.append(arr.next_element().get_string())
    assert_equal(len(vals), 5)
    assert_equal(vals[0], "aaa")
    assert_equal(vals[1], "bbb")
    assert_equal(vals[2], "ccc")
    assert_equal(vals[3], "ddd")
    assert_equal(vals[4], "eee")
    print("  PASS: multiple consecutive strings indexed correctly")


def test_span_all_escape_types() raises:
    """String containing every JSON escape sequence.

    Must fall back to slow path and unescape everything correctly.
    """
    # JSON source: \n \t \r \b \f \/ \\ \" \uXXXX
    var json = String('{"e": "\\n\\t\\r\\b\\f\\/\\\\\\\"\\u0041"}')
    var reader = od_iter(json)
    var result = reader.root().get_object().field("e").get_string()
    # Expected: newline, tab, CR, backspace, formfeed, /, \, ", A
    assert_equal(len(result.as_bytes()), 9)
    var rb = result.as_bytes()
    assert_equal(rb[0], UInt8(0x0A))  # \n
    assert_equal(rb[1], UInt8(0x09))  # \t
    assert_equal(rb[2], UInt8(0x0D))  # \r
    assert_equal(rb[3], UInt8(0x08))  # \b
    assert_equal(rb[4], UInt8(0x0C))  # \f
    assert_equal(rb[5], UInt8(ord("/")))
    assert_equal(rb[6], UInt8(ord("\\")))
    assert_equal(rb[7], UInt8(ord('"')))
    assert_equal(rb[8], UInt8(ord("A")))
    print("  PASS: all escape types unescaped correctly")


def test_span_escaped_quote_variations() raises:
    """Various escaped-quote patterns to verify stage1 masking.

    Escaped quotes must not be treated as structurals.
    """
    # "say \"hi\"" -> say "hi"
    var json1 = String('["say \\"hi\\""]')
    var r1 = od_iter(json1)
    assert_equal(r1.root().elem(0).get_string(), 'say "hi"')

    # "\"\"\"\""  -> """"
    var json2 = String('["\\"\\"\\"\\""]')
    var r2 = od_iter(json2)
    assert_equal(r2.root().elem(0).get_string(), '""""')

    # "\\\"" -> \" (literal backslash then quote via escape)
    var json3 = String('["\\\\\\""]')
    var r3 = od_iter(json3)
    assert_equal(r3.root().elem(0).get_string(), '\\"')

    print("  PASS: escaped quote variations handled correctly")


def test_span_empty_and_single_char_strings() raises:
    """Edge cases: empty string, single-char string, single-escape string."""
    var json = String('["", "a", "\\n"]')
    var reader = od_iter(json)
    var root = reader.root()
    assert_equal(root.elem(0).get_string(), "")
    assert_equal(root.elem(1).get_string(), "a")
    assert_equal(root.elem(2).get_string(), "\n")
    print("  PASS: empty and single-char strings correct")


# ──────────────────────────────────────────────────────────────────────
# ATTACK 3: DOM nocopy lifetime and correctness
# ──────────────────────────────────────────────────────────────────────

def test_dom_nocopy_complex_document() raises:
    """Nocopy parse of a complex nested document with mixed types.

    All value types must work correctly through nocopy.
    """
    var json = String(
        '{"obj": {"a": 1, "b": [2, 3.14, true, false, null, "str"]},'
        ' "arr": [{"nested": "value"}, [1, 2, 3]], "empty": {}, "earr": []}'
    )
    var padded = _make_padded(json)
    var doc_nc = parse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )
    var doc_copy = parse(json)

    # Compare nested values
    assert_equal(
        doc_nc.root().field("obj").field("a").get_uint(),
        doc_copy.root().field("obj").field("a").get_uint(),
    )
    assert_equal(
        doc_nc.root().field("obj").field("b").elem(1).get_float(),
        doc_copy.root().field("obj").field("b").elem(1).get_float(),
    )
    assert_equal(
        doc_nc.root().field("obj").field("b").elem(2).get_bool(),
        doc_copy.root().field("obj").field("b").elem(2).get_bool(),
    )
    assert_equal(
        doc_nc.root().field("obj").field("b").elem(3).get_bool(),
        doc_copy.root().field("obj").field("b").elem(3).get_bool(),
    )
    assert_equal(
        doc_nc.root().field("obj").field("b").elem(4).is_null(),
        doc_copy.root().field("obj").field("b").elem(4).is_null(),
    )
    assert_equal(
        doc_nc.root().field("obj").field("b").elem(5).get_string(),
        doc_copy.root().field("obj").field("b").elem(5).get_string(),
    )
    assert_equal(
        doc_nc.root().field("arr").elem(0).field("nested").get_string(),
        doc_copy.root().field("arr").elem(0).field("nested").get_string(),
    )
    assert_equal(
        doc_nc.root().field("arr").elem(1).elem(2).get_uint(),
        doc_copy.root().field("arr").elem(1).elem(2).get_uint(),
    )
    assert_equal(Int(doc_nc.root().field("empty").len()), 0)
    assert_equal(Int(doc_nc.root().field("earr").len()), 0)
    print("  PASS: nocopy complex document matches copy path")


def test_dom_nocopy_strings_with_escapes() raises:
    """DOM nocopy must handle escape sequences in strings correctly.

    Escaped strings go through parse_string during tape building, so the
    tape's string buffer should hold unescaped content regardless of copy mode.
    """
    var json = String('{"a": "hello\\nworld", "b": "tab\\there", "c": "\\u0041"}')
    var padded = _make_padded(json)
    var doc_nc = parse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )
    assert_equal(doc_nc.root().field("a").get_string(), "hello\nworld")
    assert_equal(doc_nc.root().field("b").get_string(), "tab\there")
    assert_equal(doc_nc.root().field("c").get_string(), "A")
    print("  PASS: nocopy DOM strings with escapes correct")


def test_dom_nocopy_reparse_shorter_doc() raises:
    """Reparse with a SHORTER document than the first parse.

    The old tape/positions must be properly replaced (not just appended to).
    """
    var json1 = String(
        '{"a": 1, "b": 2, "c": 3, "d": 4, "e": 5,'
        ' "f": "a long string value here"}'
    )
    var json2 = String('{"x": 42}')
    var padded1 = _make_padded(json1)
    var padded2 = _make_padded(json2)

    var doc = parse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded1.unsafe_ptr()),
        len(json1.as_bytes()),
    )
    # Verify first parse works
    assert_equal(doc.root().field("a").get_uint(), UInt64(1))
    assert_equal(doc.root().field("f").get_string(), "a long string value here")

    # Reparse with shorter doc
    doc.reparse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded2.unsafe_ptr()),
        len(json2.as_bytes()),
    )
    # Must see the new document
    assert_equal(doc.root().field("x").get_uint(), UInt64(42))

    # The old fields must NOT be accessible -- field lookup should fail
    var old_field_found = False
    try:
        _ = doc.root().field("a")
        old_field_found = True
    except:
        pass
    assert_true(not old_field_found, "old field 'a' must not exist after reparse")
    print("  PASS: nocopy reparse with shorter document works correctly")


def test_dom_nocopy_reparse_longer_doc() raises:
    """Reparse with a LONGER document than the first parse.

    The tape must grow to accommodate the new data.
    """
    var json1 = String('{"x": 1}')
    var json2 = String(
        '{"a": 1, "b": 2, "c": 3, "d": [4, 5, 6],'
        ' "e": {"nested": "value"}, "f": "string"}'
    )
    var padded1 = _make_padded(json1)
    var padded2 = _make_padded(json2)

    var doc = parse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded1.unsafe_ptr()),
        len(json1.as_bytes()),
    )
    assert_equal(doc.root().field("x").get_uint(), UInt64(1))

    doc.reparse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded2.unsafe_ptr()),
        len(json2.as_bytes()),
    )
    assert_equal(doc.root().field("a").get_uint(), UInt64(1))
    assert_equal(doc.root().field("d").elem(2).get_uint(), UInt64(6))
    assert_equal(
        doc.root().field("e").field("nested").get_string(), "value"
    )
    assert_equal(doc.root().field("f").get_string(), "string")
    print("  PASS: nocopy reparse with longer document works correctly")


def test_dom_nocopy_minimum_padding() raises:
    """Nocopy with a buffer EXACTLY the minimum padded size.

    ceil(n/64)*64 + 128 bytes allocated, zeros past input_len.
    Must not overread or produce wrong results.
    """
    # A 1-byte JSON: just the number 7
    var json = String("7")
    var padded = _make_padded(json)  # ceil(1/64)*64 + 128 = 192 bytes
    # Verify padding size
    assert_equal(len(padded), 192)

    var doc = parse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )
    assert_equal(doc.root().get_uint(), UInt64(7))

    # A 64-byte JSON (exactly one chunk boundary)
    var json64 = String('{"a": "') + String("x" * 49) + String('"}')
    # 7 + 49 + 2 = 58 ... let me make it exactly 64
    # {"a": "xxxxxxxxxxx..."} where x-count makes total = 64
    # {"a": " = 6, "} = 2, total overhead = 8, content = 56
    var content56 = String("x" * 56)
    var json_exact = String('{"a": "') + content56 + String('"}')
    assert_equal(len(json_exact.as_bytes()), 65)  # 7 + 56 + 2 = 65
    var padded64 = _make_padded(json_exact)
    var doc64 = parse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded64.unsafe_ptr()),
        len(json_exact.as_bytes()),
    )
    assert_equal(doc64.root().field("a").get_string(), content56)
    print("  PASS: minimum padding size works correctly")


# ──────────────────────────────────────────────────────────────────────
# ATTACK 4: OD nocopy parity with copy path
# ──────────────────────────────────────────────────────────────────────

def test_od_nocopy_vs_copy_strings() raises:
    """OD iter_nocopy and iter must produce identical results for strings.

    Tests both escape-free (fast path) and escaped (slow path) strings.
    """
    var json = String(
        '{"clean": "hello world", "escaped": "line1\\nline2",'
        ' "unicode": "\\u00e9", "empty": "", "backslash": "\\\\"}'
    )
    var padded = _make_padded(json)

    var r_copy = od_iter(json)
    var r_nc = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )

    # Clean string (fast path in both)
    assert_equal(
        r_copy.root().get_object().field("clean").get_string(),
        r_nc.root().get_object().field("clean").get_string(),
    )
    # Escaped string (slow path)
    assert_equal(
        r_copy.root().get_object().field("escaped").get_string(),
        r_nc.root().get_object().field("escaped").get_string(),
    )
    # Unicode escape
    assert_equal(
        r_copy.root().get_object().field("unicode").get_string(),
        r_nc.root().get_object().field("unicode").get_string(),
    )
    # Empty string
    assert_equal(
        r_copy.root().get_object().field("empty").get_string(),
        r_nc.root().get_object().field("empty").get_string(),
    )
    # Backslash
    assert_equal(
        r_copy.root().get_object().field("backslash").get_string(),
        r_nc.root().get_object().field("backslash").get_string(),
    )
    print("  PASS: OD nocopy strings match copy path")


def test_od_nocopy_vs_copy_numbers() raises:
    """OD iter_nocopy and iter must produce identical numeric results.

    Numbers read through input_ptr — verify the pointer is correct.
    """
    var json = String(
        '{"int": 42, "neg": -17, "big": 9999999999999, "float": 3.14159,'
        ' "exp": 1.23e10, "negexp": -5.67e-8, "zero": 0}'
    )
    var padded = _make_padded(json)

    var r_copy = od_iter(json)
    var r_nc = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )

    assert_equal(
        r_copy.root().get_object().field("int").get_uint(),
        r_nc.root().get_object().field("int").get_uint(),
    )
    assert_equal(
        r_copy.root().get_object().field("neg").get_int(),
        r_nc.root().get_object().field("neg").get_int(),
    )
    assert_equal(
        r_copy.root().get_object().field("big").get_uint(),
        r_nc.root().get_object().field("big").get_uint(),
    )
    assert_equal(
        r_copy.root().get_object().field("float").get_float(),
        r_nc.root().get_object().field("float").get_float(),
    )
    assert_equal(
        r_copy.root().get_object().field("exp").get_float(),
        r_nc.root().get_object().field("exp").get_float(),
    )
    assert_equal(
        r_copy.root().get_object().field("negexp").get_float(),
        r_nc.root().get_object().field("negexp").get_float(),
    )
    assert_equal(
        r_copy.root().get_object().field("zero").get_uint(),
        r_nc.root().get_object().field("zero").get_uint(),
    )
    print("  PASS: OD nocopy numbers match copy path")


def test_od_nocopy_vs_copy_booleans_null() raises:
    """OD iter_nocopy and iter must match for booleans and null."""
    var json = String('{"t": true, "f": false, "n": null}')
    var padded = _make_padded(json)

    var r_copy = od_iter(json)
    var r_nc = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )

    assert_equal(
        r_copy.root().get_object().field("t").get_bool(),
        r_nc.root().get_object().field("t").get_bool(),
    )
    assert_equal(
        r_copy.root().get_object().field("f").get_bool(),
        r_nc.root().get_object().field("f").get_bool(),
    )
    assert_equal(
        r_copy.root().get_object().field("n").is_null(),
        r_nc.root().get_object().field("n").is_null(),
    )
    print("  PASS: OD nocopy booleans/null match copy path")


def test_od_nocopy_vs_copy_nested() raises:
    """OD nocopy parity on a deeply nested document."""
    var json = String(
        '{"level1": {"level2": {"level3": {"deep": "value", "num": 42}}}}'
    )
    var padded = _make_padded(json)

    var r_copy = od_iter(json)
    var r_nc = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )

    var s_copy = (
        r_copy.root().get_object()
        .field("level1").get_object()
        .field("level2").get_object()
        .field("level3").get_object()
        .field("deep").get_string()
    )
    var s_nc = (
        r_nc.root().get_object()
        .field("level1").get_object()
        .field("level2").get_object()
        .field("level3").get_object()
        .field("deep").get_string()
    )
    assert_equal(s_copy, s_nc)

    # Re-parse for number check (OD is forward-only so we need fresh readers).
    # Use reparse_nocopy instead of reassignment to avoid Mojo codegen heap
    # corruption on iter_nocopy reader reassignment (see test_nocopy_reader_reassign_crash).
    r_nc.reparse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )
    var r_copy2 = od_iter(json)
    var n_copy = (
        r_copy2.root().get_object()
        .field("level1").get_object()
        .field("level2").get_object()
        .field("level3").get_object()
        .field("num").get_uint()
    )
    var n_nc = (
        r_nc.root().get_object()
        .field("level1").get_object()
        .field("level2").get_object()
        .field("level3").get_object()
        .field("num").get_uint()
    )
    assert_equal(n_copy, n_nc)
    print("  PASS: OD nocopy deeply nested document matches copy path")


def test_od_nocopy_vs_copy_array_iteration() raises:
    """OD nocopy parity for array iteration over mixed types.

    Uses reparse_nocopy instead of reader reassignment to avoid a Mojo 1.0.0b2
    codegen heap corruption on iter_nocopy variable reassignment (see
    test_nocopy_reader_reassign_crash for the documented crash).
    """
    var json = String('[1, "two", 3.0, true, null, [4, 5], {"k": "v"}]')
    var padded = _make_padded(json)
    var nc_ptr = UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr())
    var nc_len = len(json.as_bytes())

    # elem(0): uint
    var r_c0 = od_iter(json)
    var r_n0 = iter_nocopy(nc_ptr, nc_len)
    assert_equal(r_c0.root().elem(0).get_uint(), r_n0.root().elem(0).get_uint())

    # elem(1): string — reparse instead of reassign
    r_n0.reparse_nocopy(nc_ptr, nc_len)
    var r_c1 = od_iter(json)
    assert_equal(r_c1.root().elem(1).get_string(), r_n0.root().elem(1).get_string())

    # elem(2): float
    r_n0.reparse_nocopy(nc_ptr, nc_len)
    var r_c2 = od_iter(json)
    assert_equal(r_c2.root().elem(2).get_float(), r_n0.root().elem(2).get_float())

    # elem(3): bool
    r_n0.reparse_nocopy(nc_ptr, nc_len)
    var r_c3 = od_iter(json)
    assert_equal(r_c3.root().elem(3).get_bool(), r_n0.root().elem(3).get_bool())

    # elem(4): null
    r_n0.reparse_nocopy(nc_ptr, nc_len)
    var r_c4 = od_iter(json)
    assert_equal(r_c4.root().elem(4).is_null(), r_n0.root().elem(4).is_null())

    # elem(5): nested array
    r_n0.reparse_nocopy(nc_ptr, nc_len)
    var r_c5 = od_iter(json)
    assert_equal(
        r_c5.root().elem(5).elem(1).get_uint(),
        r_n0.root().elem(5).elem(1).get_uint(),
    )

    # elem(6): nested object
    r_n0.reparse_nocopy(nc_ptr, nc_len)
    var r_c6 = od_iter(json)
    assert_equal(
        r_c6.root().elem(6).field("k").get_string(),
        r_n0.root().elem(6).field("k").get_string(),
    )
    print("  PASS: OD nocopy array iteration matches copy path")


def test_od_nocopy_reparse_parity() raises:
    """OD nocopy reparse produces same results as fresh iter_nocopy."""
    var json1 = String('{"a": "first"}')
    var json2 = String('{"b": "second", "c": 99}')
    var padded1 = _make_padded(json1)
    var padded2 = _make_padded(json2)

    var reader = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded1.unsafe_ptr()),
        len(json1.as_bytes()),
    )
    assert_equal(
        reader.root().get_object().field("a").get_string(), "first"
    )

    reader.reparse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded2.unsafe_ptr()),
        len(json2.as_bytes()),
    )
    assert_equal(
        reader.root().get_object().field("b").get_string(), "second"
    )
    assert_equal(
        reader.root().get_object().field("c").get_uint(), UInt64(99)
    )
    print("  PASS: OD nocopy reparse produces correct results")


# ──────────────────────────────────────────────────────────────────────
# ATTACK 5: Tricky edge cases for the fast path
# ──────────────────────────────────────────────────────────────────────

def test_fast_path_string_with_only_spaces() raises:
    """A string containing only spaces (0x20).

    Spaces are >= 0x20 and not backslash, so the fast path should handle them.
    """
    var json = String('{"s": "   "}')
    var reader = od_iter(json)
    assert_equal(reader.root().get_object().field("s").get_string(), "   ")
    print("  PASS: string of spaces uses fast path correctly")


def test_fast_path_string_with_tilde() raises:
    """A string containing tilde (0x7E) and DEL-adjacent chars.

    These high ASCII chars are not control chars and not backslash.
    """
    # Braces/brackets inside a string are masked by stage1 (not structural)
    var json = String('{"s": "tilde~pipe|brace{}bracket[]"}')
    var reader = od_iter(json)
    assert_equal(
        reader.root().get_object().field("s").get_string(),
        "tilde~pipe|brace{}bracket[]",
    )
    print("  PASS: string with structural-like chars inside uses fast path correctly")


def test_fast_path_string_backslash_at_position_zero() raises:
    """A string starting with a backslash (escape at offset 0).

    The guard must catch this at the very first byte.
    """
    var json = String('{"s": "\\nhello"}')
    var reader = od_iter(json)
    assert_equal(
        reader.root().get_object().field("s").get_string(), "\nhello"
    )
    print("  PASS: backslash at position 0 triggers slow path correctly")


def test_fast_path_string_backslash_at_last_position() raises:
    """A string ending with an escape sequence.

    The guard must scan to the very end.
    """
    var json = String('{"s": "hello\\n"}')
    var reader = od_iter(json)
    assert_equal(
        reader.root().get_object().field("s").get_string(), "hello\n"
    )
    print("  PASS: backslash at last position triggers slow path correctly")


def test_dom_nocopy_vs_copy_parity_full() raises:
    """Full parity test: DOM nocopy and copy on a representative document.

    Every value type, nesting level, and string variant must match.
    """
    var json = String(
        '{"str": "hello", "esc": "a\\tb", "num": 42, "flt": 1.5,'
        ' "neg": -7, "t": true, "f": false, "n": null,'
        ' "arr": [1, "two", [3]], "obj": {"inner": "val"}}'
    )
    var padded = _make_padded(json)

    var dc = parse(json)
    var dn = parse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )

    assert_equal(dc.root().field("str").get_string(), dn.root().field("str").get_string())
    assert_equal(dc.root().field("esc").get_string(), dn.root().field("esc").get_string())
    assert_equal(dc.root().field("num").get_uint(), dn.root().field("num").get_uint())
    assert_equal(dc.root().field("flt").get_float(), dn.root().field("flt").get_float())
    assert_equal(dc.root().field("neg").get_int(), dn.root().field("neg").get_int())
    assert_equal(dc.root().field("t").get_bool(), dn.root().field("t").get_bool())
    assert_equal(dc.root().field("f").get_bool(), dn.root().field("f").get_bool())
    assert_equal(dc.root().field("n").is_null(), dn.root().field("n").is_null())
    assert_equal(
        dc.root().field("arr").elem(0).get_uint(),
        dn.root().field("arr").elem(0).get_uint(),
    )
    assert_equal(
        dc.root().field("arr").elem(1).get_string(),
        dn.root().field("arr").elem(1).get_string(),
    )
    assert_equal(
        dc.root().field("arr").elem(2).elem(0).get_uint(),
        dn.root().field("arr").elem(2).elem(0).get_uint(),
    )
    assert_equal(
        dc.root().field("obj").field("inner").get_string(),
        dn.root().field("obj").field("inner").get_string(),
    )
    print("  PASS: DOM nocopy/copy full parity confirmed")


def test_raw_span_unicode_surrogate_pair() raises:
    """Unicode surrogate pair escape (😀) must be handled by slow path.

    The backslash triggers slow path, which should process the surrogate pair.
    """
    var json = String('{"emoji": "\\uD83D\\uDE00"}')
    var reader = od_iter(json)
    var result = reader.root().get_object().field("emoji").get_string()
    # U+1F600 = F0 9F 98 80 in UTF-8
    var rb = result.as_bytes()
    assert_equal(len(rb), 4)
    assert_equal(rb[0], UInt8(0xF0))
    assert_equal(rb[1], UInt8(0x9F))
    assert_equal(rb[2], UInt8(0x98))
    assert_equal(rb[3], UInt8(0x80))
    print("  PASS: surrogate pair escape handled correctly via slow path")


def test_od_nocopy_string_only_document() raises:
    """A document that is just a string (root is a string, not object/array).

    The raw span fast path must work for root-level strings too.
    """
    var json = String('"just a string"')
    var padded = _make_padded(json)

    var reader = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )
    assert_equal(reader.root().get_string(), "just a string")

    # Also test a root string with escapes
    var json2 = String('"hello\\nworld"')
    var padded2 = _make_padded(json2)
    var reader2 = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded2.unsafe_ptr()),
        len(json2.as_bytes()),
    )
    assert_equal(reader2.root().get_string(), "hello\nworld")
    print("  PASS: root-level string document works with nocopy")


def test_od_key_matching_with_escapes_nocopy() raises:
    """Object key matching with escaped keys must work through nocopy.

    The _find_value_si method has its own escape-aware key matching.
    """
    var json = String('{"normal": 1, "with\\nnewline": 2, "with\\tquote": 3}')
    var padded = _make_padded(json)

    var reader = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )
    assert_equal(
        reader.root().get_object().field("normal").get_uint(), UInt64(1)
    )

    # Re-read with fresh reader for next field (forward-only)
    var reader2 = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )
    assert_equal(
        reader2.root().get_object().field("with\nnewline").get_uint(),
        UInt64(2),
    )
    print("  PASS: escaped key matching works with nocopy")


# ──────────────────────────────────────────────────────────────────────
# ATTACK 6: iter_nocopy reader reassignment crash (documented bug)
#
# THIS TEST IS NOT RUN because it crashes the process. The pattern is
# documented here for awareness. See scratchpad notes for full repro.
#
# Trigger: create an iter_nocopy reader, call field().get_uint() (or
# get_string()), then REASSIGN the reader variable to a new iter_nocopy.
# The old reader's destruction corrupts the heap (TCMalloc cfree crash).
#
# Repro: run test_A then test_D from separate functions, where test_A
# does field-only + reassign and test_D does field+get_uint + reassign.
# Individually they pass; together the heap corruption from A crashes D.
#
# Workaround: use reparse_nocopy() instead of reassignment.
# Root cause: likely Mojo 1.0.0b2 codegen bug — _build_index_nocopy
# does identical work to _build_index (both memcpy to self.padded), but
# only iter_nocopy triggers the crash. od_iter works fine with the same
# usage pattern.
# ──────────────────────────────────────────────────────────────────────


# ──────────────────────────────────────────────────────────────────────
# Runner
# ──────────────────────────────────────────────────────────────────────

def main() raises:
    print("=== ATTACK 1: Control-char / escape guard completeness ===")
    test_guard_nul_byte()
    test_guard_del_byte()
    test_guard_all_control_chars()
    test_guard_boundary_0x20()
    test_guard_empty_content()
    test_guard_only_control_chars()
    test_guard_high_utf8_bytes()
    test_od_utf8_string_fast_path()
    test_od_control_char_rejected_via_fast_path_guard()
    test_od_tab_char_rejected()

    print("\n=== ATTACK 2: _raw_string_span invariant ===")
    test_span_backslash_backslash_quote()
    test_span_long_string_multi_chunk()
    test_span_very_long_string_with_escapes()
    test_span_string_at_end_of_input()
    test_span_multiple_consecutive_strings()
    test_span_all_escape_types()
    test_span_escaped_quote_variations()
    test_span_empty_and_single_char_strings()

    print("\n=== ATTACK 3: DOM nocopy lifetime and correctness ===")
    test_dom_nocopy_complex_document()
    test_dom_nocopy_strings_with_escapes()
    test_dom_nocopy_reparse_shorter_doc()
    test_dom_nocopy_reparse_longer_doc()
    test_dom_nocopy_minimum_padding()

    print("\n=== ATTACK 4: OD nocopy parity with copy path ===")
    test_od_nocopy_vs_copy_strings()
    test_od_nocopy_vs_copy_numbers()
    test_od_nocopy_vs_copy_booleans_null()
    test_od_nocopy_vs_copy_nested()
    test_od_nocopy_vs_copy_array_iteration()
    test_od_nocopy_reparse_parity()

    print("\n=== ATTACK 5: Edge cases for fast path ===")
    test_fast_path_string_with_only_spaces()
    test_fast_path_string_with_tilde()
    test_fast_path_string_backslash_at_position_zero()
    test_fast_path_string_backslash_at_last_position()
    test_dom_nocopy_vs_copy_parity_full()
    test_raw_span_unicode_surrogate_pair()
    test_od_nocopy_string_only_document()
    test_od_key_matching_with_escapes_nocopy()

    print("\n=== ALL ADVERSARIAL PLAN B TESTS PASSED ===")
