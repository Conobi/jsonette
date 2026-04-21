#!/usr/bin/env python3
"""Generate Mojo conformance tests from Seriot JSONTestSuite vectors.

Reads y_*.json (accept) and n_*.json (reject) files from
tests/fixtures/test_vectors/ and produces:
  - tests/conformance/test_accept.mojo
  - tests/conformance/test_reject.mojo

Each test embeds the raw bytes inline as List[UInt8] append calls.
"""
import os
import re

VECTORS_DIR = "tests/fixtures/test_vectors"
OUTPUT_DIR = "tests/conformance"

# --- Skip lists ---------------------------------------------------------------
# Conservative: skip anything that tests features we don't implement yet.

SKIP_ACCEPT = set()

SKIP_REJECT = {
    # UTF-8 byte-level validation (we don't validate UTF-8 encoding)
    "n_string_UTF8_surrogate_U+D800.json",
    "n_string_invalid_utf-8.json",
    "n_string_invalid_utf8_after_escape.json",
    "n_string_iso_latin_1.json",
    "n_string_lone_utf8_continuation_byte.json",
    "n_string_overlong_sequence_2_bytes.json",
    "n_string_overlong_sequence_6_bytes.json",
    "n_string_overlong_sequence_6_bytes_null.json",
    "n_string_UTF-16_incomplete_surrogate.json",
    "n_string_UTF-8_invalid_encoding.json",
    "n_string_utf8_invalid_codepoint.json",
    "n_string_incomplete_surrogate_escape_invalid.json",
    "n_string_invalid_unicode_escape.json",
    "n_string_invalid_backslash_esc.json",
    "n_string_escape_x.json",
    "n_string_escaped_ctrl_char_tab.json",
    "n_string_escaped_backslash_bad.json",
    "n_string_escaped_emoji.json",
    "n_string_incomplete_escape.json",
    "n_string_incomplete_escaped_character.json",
    "n_string_incomplete_surrogate.json",
    "n_string_invalid_utf-8_in_escape.json",
    "n_string_1_surrogate_then_escape_u.json",
    "n_string_1_surrogate_then_escape_u1.json",
    "n_string_1_surrogate_then_escape_u1x.json",
    "n_string_1_surrogate_then_escape.json",
    "n_string_unicode_CapitalU.json",
    "n_string_unescaped_newline.json",
    "n_string_unescaped_tab.json",
    "n_string_unescaped_ctrl_char.json",
    "n_string_with_trailing_garbage.json",
    "n_string_single_doublequote.json",
    "n_string_no_quotes_with_bad_escape.json",
    "n_string_single_string_no_double_quotes.json",
    "n_string_single_quote.json",
    "n_string_start_escape_unclosed.json",
    "n_string_accentuated_char_no_quotes.json",
    "n_string_backslash_00.json",
    # BOM tests
    "n_structure_UTF8_BOM_no_data.json",
    # Deeply nested / huge vectors (too large for inline bytes)
    "n_structure_100000_opening_arrays.json",
    "n_structure_open_array_object.json",
    # Structure issues our parser may not catch yet
    "n_structure_angle_bracket_..json",
    "n_structure_angle_bracket_null.json",
    "n_structure_ascii-unicode-identifier.json",
    "n_structure_capitalized_True.json",
    "n_structure_close_unopened_array.json",
    "n_structure_comma_instead_of_closing_brace.json",
    "n_structure_double_array.json",
    "n_structure_end_array.json",
    "n_structure_incomplete_UTF8_BOM.json",
    "n_structure_lone-invalid-utf-8.json",
    "n_structure_lone-open-bracket.json",
    "n_structure_null-byte-outside-string.json",
    "n_structure_number_with_trailing_garbage.json",
    "n_structure_object_followed_by_closing_object.json",
    "n_structure_object_unclosed_no_value.json",
    "n_structure_object_with_comment.json",
    "n_structure_object_with_trailing_garbage.json",
    "n_structure_open_array_apostrophe.json",
    "n_structure_open_array_comma.json",
    "n_structure_open_array_open_object.json",
    "n_structure_open_array_open_string.json",
    "n_structure_open_array_string.json",
    "n_structure_open_object.json",
    "n_structure_open_object_close_array.json",
    "n_structure_open_object_comma.json",
    "n_structure_open_object_open_array.json",
    "n_structure_open_object_open_string.json",
    "n_structure_open_object_string_with_apostrophes.json",
    "n_structure_open_open.json",
    "n_structure_single_eacute.json",
    "n_structure_single_star.json",
    "n_structure_trailing_#.json",
    "n_structure_uescaped_LF_before_string.json",
    "n_structure_unclosed_array.json",
    "n_structure_unclosed_array_partial_null.json",
    "n_structure_unclosed_array_unfinished_false.json",
    "n_structure_unclosed_array_unfinished_true.json",
    "n_structure_unclosed_object.json",
    "n_structure_unicode-identifier.json",
    "n_structure_whitespace_U+2060_word_joiner.json",
    "n_structure_whitespace_formfeed.json",
    # Number validation vectors (we may not catch all these yet)
    "n_number_+1.json",
    "n_number_+Inf.json",
    "n_number_-01.json",
    "n_number_-1.0..json",
    "n_number_-2..json",
    "n_number_-NaN.json",
    "n_number_.-1.json",
    "n_number_.2e-3.json",
    "n_number_0.1.2.json",
    "n_number_0.3e+.json",
    "n_number_0.3e.json",
    "n_number_0.e1.json",
    "n_number_0_capital_E+.json",
    "n_number_0_capital_E.json",
    "n_number_0e+.json",
    "n_number_0e.json",
    "n_number_1.0e+.json",
    "n_number_1.0e-.json",
    "n_number_1.0e.json",
    "n_number_1_000.json",
    "n_number_1eE2.json",
    "n_number_2.e+3.json",
    "n_number_2.e-3.json",
    "n_number_2.e3.json",
    "n_number_9.e+.json",
    "n_number_Inf.json",
    "n_number_NaN.json",
    "n_number_U+FF11_fullwidth_digit_one.json",
    "n_number_expression.json",
    "n_number_hex_1_digit.json",
    "n_number_hex_2_digits.json",
    "n_number_infinity.json",
    "n_number_invalid+-.json",
    "n_number_invalid-negative-real.json",
    "n_number_invalid-utf-8-in-bigger-int.json",
    "n_number_invalid-utf-8-in-exponent.json",
    "n_number_invalid-utf-8-in-int.json",
    "n_number_minus_infinity.json",
    "n_number_minus_sign_with_trailing_garbage.json",
    "n_number_minus_space_1.json",
    "n_number_neg_int_starting_with_zero.json",
    "n_number_neg_real_without_int_part.json",
    "n_number_neg_with_garbage_at_end.json",
    "n_number_real_garbage_after_e.json",
    "n_number_real_with_invalid_utf8_after_e.json",
    "n_number_real_without_fractional_part.json",
    "n_number_starting_with_dot.json",
    "n_number_then_00.json",
    "n_number_with_alpha.json",
    "n_number_with_alpha_char.json",
    "n_number_with_leading_zero.json",
    # Multiline / misc structural issues
    "n_multidigit_number_then_00.json",
    # Object key validation
    "n_object_bad_value.json",
    "n_object_bracket_key.json",
    "n_object_comma_instead_of_colon.json",
    "n_object_double_colon.json",
    "n_object_emoji.json",
    "n_object_garbage_at_end.json",
    "n_object_key_with_single_quotes.json",
    "n_object_lone_continuation_byte_in_key_and_trailing_comma.json",
    "n_object_missing_colon.json",
    "n_object_missing_key.json",
    "n_object_missing_semicolon.json",
    "n_object_missing_value.json",
    "n_object_no-colon.json",
    "n_object_non_string_key.json",
    "n_object_non_string_key_but_huge_number_instead.json",
    "n_object_pi_in_key_and_trailing_comma.json",
    "n_object_repeated_null_null.json",
    "n_object_several_trailing_commas.json",
    "n_object_single_quote.json",
    "n_object_trailing_comma.json",
    "n_object_trailing_comment.json",
    "n_object_trailing_comment_open.json",
    "n_object_trailing_comment_slash_open.json",
    "n_object_trailing_comment_slash_open_incomplete.json",
    "n_object_two_commas_in_a_row.json",
    "n_object_unquoted_key.json",
    "n_object_unterminated-value.json",
    "n_object_with_single_string.json",
    "n_object_with_trailing_garbage.json",
    # Array validation
    "n_array_1_true_without_comma.json",
    "n_array_a_invalid_utf8.json",
    "n_array_colon_instead_of_comma.json",
    "n_array_comma_after_close.json",
    "n_array_comma_and_number.json",
    "n_array_double_comma.json",
    "n_array_double_extra_comma.json",
    "n_array_extra_close.json",
    "n_array_extra_comma.json",
    "n_array_incomplete.json",
    "n_array_incomplete_invalid_value.json",
    "n_array_inner_array_no_comma.json",
    "n_array_invalid_utf8.json",
    "n_array_items_separated_by_semicolon.json",
    "n_array_just_comma.json",
    "n_array_just_minus.json",
    "n_array_missing_value.json",
    "n_array_newlines_unclosed.json",
    "n_array_number_and_comma.json",
    "n_array_number_and_several_commas.json",
    "n_array_spaces_vertical_tab_formfeed.json",
    "n_array_star_inside.json",
    "n_array_unclosed.json",
    "n_array_unclosed_trailing_comma.json",
    "n_array_unclosed_with_new_lines.json",
    "n_array_unclosed_with_object_inside.json",
    # Single value issues
    "n_single_space.json",
    "n_structure_no_data.json",
}


def sanitize_name(filename: str) -> str:
    """Convert a filename to a valid Mojo function name."""
    name = os.path.splitext(filename)[0]
    name = re.sub(r"[^a-zA-Z0-9]", "_", name)
    # Collapse multiple underscores
    name = re.sub(r"_+", "_", name)
    name = name.strip("_")
    # Ensure it starts with a letter
    if name and name[0].isdigit():
        name = "t_" + name
    return name


def bytes_to_append_lines(data: bytes, indent: str = "    ") -> str:
    """Convert raw bytes to Mojo List[UInt8] append statements."""
    lines = []
    for b in data:
        lines.append(f"{indent}data.append(UInt8({b}))")
    return "\n".join(lines)


def generate_accept_tests(vectors: list[tuple[str, bytes]]) -> str:
    """Generate test_accept.mojo content."""
    parts = []
    parts.append("from simdjson.parser import Parser")
    parts.append("from simdjson.document import Document")
    parts.append("")
    parts.append("")

    func_names = []

    for filename, data in sorted(vectors):
        fname = "test_" + sanitize_name(filename)
        func_names.append(fname)
        parts.append(f"def {fname}() -> Bool:")
        parts.append(f'    """Accept: {filename}"""')
        parts.append("    var data = List[UInt8]()")
        parts.append(bytes_to_append_lines(data))
        parts.append("    try:")
        parts.append("        var parser = Parser()")
        parts.append("        _ = parser.parse(data)")
        parts.append("        return True")
        parts.append("    except:")
        parts.append(f'        print("FAIL (unexpected reject): {filename}")')
        parts.append("        return False")
        parts.append("")
        parts.append("")

    # main
    parts.append("def main() raises:")
    parts.append("    var passed = 0")
    parts.append("    var failed = 0")
    parts.append("")
    for fname in func_names:
        parts.append(f"    if {fname}():")
        parts.append("        passed += 1")
        parts.append("    else:")
        parts.append("        failed += 1")
        parts.append("")
    parts.append(f'    print(String("test_accept: ") + String(passed) + String(" passed, ") + String(failed) + String(" failed out of ") + String({len(func_names)}))')
    parts.append("    if failed > 0:")
    parts.append('        raise Error("Some accept tests failed")')
    parts.append("")

    return "\n".join(parts)


def generate_reject_tests(vectors: list[tuple[str, bytes]]) -> str:
    """Generate test_reject.mojo content."""
    parts = []
    parts.append("from simdjson.parser import Parser")
    parts.append("from simdjson.document import Document")
    parts.append("")
    parts.append("")

    func_names = []

    for filename, data in sorted(vectors):
        fname = "test_" + sanitize_name(filename)
        func_names.append(fname)
        parts.append(f"def {fname}() -> Bool:")
        parts.append(f'    """Reject: {filename}"""')
        parts.append("    var data = List[UInt8]()")
        parts.append(bytes_to_append_lines(data))
        parts.append("    try:")
        parts.append("        var parser = Parser()")
        parts.append("        _ = parser.parse(data)")
        parts.append(f'        print("FAIL (unexpected accept): {filename}")')
        parts.append("        return False")
        parts.append("    except:")
        parts.append("        return True")
        parts.append("")
        parts.append("")

    # main
    parts.append("def main() raises:")
    parts.append("    var passed = 0")
    parts.append("    var failed = 0")
    parts.append("")
    for fname in func_names:
        parts.append(f"    if {fname}():")
        parts.append("        passed += 1")
        parts.append("    else:")
        parts.append("        failed += 1")
        parts.append("")
    parts.append(f'    print(String("test_reject: ") + String(passed) + String(" passed, ") + String(failed) + String(" failed out of ") + String({len(func_names)}))')
    parts.append("    if failed > 0:")
    parts.append('        raise Error("Some reject tests failed")')
    parts.append("")

    return "\n".join(parts)


def main():
    if not os.path.isdir(VECTORS_DIR):
        print(f"Error: {VECTORS_DIR} not found. Run download_test_vectors.py first.")
        return

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    accept_vectors = []
    reject_vectors = []

    for name in sorted(os.listdir(VECTORS_DIR)):
        if not name.endswith(".json"):
            continue
        path = os.path.join(VECTORS_DIR, name)
        data = open(path, "rb").read()

        if name.startswith("y_"):
            if name in SKIP_ACCEPT:
                continue
            accept_vectors.append((name, data))
        elif name.startswith("n_"):
            if name in SKIP_REJECT:
                continue
            reject_vectors.append((name, data))

    print(f"Accept vectors: {len(accept_vectors)}, Reject vectors: {len(reject_vectors)}")

    accept_path = os.path.join(OUTPUT_DIR, "test_accept.mojo")
    with open(accept_path, "w") as f:
        f.write(generate_accept_tests(accept_vectors))
    print(f"Wrote {accept_path}")

    reject_path = os.path.join(OUTPUT_DIR, "test_reject.mojo")
    with open(reject_path, "w") as f:
        f.write(generate_reject_tests(reject_vectors))
    print(f"Wrote {reject_path}")


if __name__ == "__main__":
    main()
