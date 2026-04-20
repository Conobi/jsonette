from std.testing import assert_equal
from simdjson.stage1.string_mask import EscapeScanner, StringScanner


def test_escape_no_backslashes() raises:
    """No backslashes -> escaped = 0."""
    var scanner = EscapeScanner()
    var escaped = scanner.next(UInt64(0))
    assert_equal(escaped, UInt64(0))


def test_escape_single_backslash() raises:
    """Single backslash at pos 3 -> pos 4 is escaped."""
    var scanner = EscapeScanner()
    var backslash: UInt64 = UInt64(1) << 3
    var escaped = scanner.next(backslash)
    assert_equal(escaped, UInt64(1) << 4)


def test_escape_double_backslash() raises:
    """Double backslash (pos 3,4) -> even-length run, nothing after is escaped."""
    var scanner = EscapeScanner()
    var backslash: UInt64 = (UInt64(1) << 3) | (UInt64(1) << 4)
    var escaped = scanner.next(backslash)
    # Even-length run: first \ escapes second \, byte after (pos 5) is NOT escaped.
    assert_equal(escaped, UInt64(0))


def test_escape_triple_backslash() raises:
    """Triple backslash (pos 3,4,5) -> odd-length run, pos 6 is escaped."""
    var scanner = EscapeScanner()
    var backslash: UInt64 = (UInt64(1) << 3) | (UInt64(1) << 4) | (UInt64(1) << 5)
    var escaped = scanner.next(backslash)
    assert_equal(escaped, UInt64(1) << 6)


def test_escape_carry_across_blocks() raises:
    """Backslash at pos 63 -> next_is_escaped flag set for next block."""
    var scanner = EscapeScanner()
    var backslash: UInt64 = UInt64(1) << 63
    _ = scanner.next(backslash)
    # The escaped byte overflows into the next block (pos 64 = next block pos 0).
    assert_equal(scanner.next_is_escaped, UInt64(1))


def test_string_basic_quotes() raises:
    """Quotes at pos 0 and 6, no escapes -> in_string bits 0-5 set."""
    var scanner = StringScanner()
    var quote: UInt64 = (UInt64(1) << 0) | (UInt64(1) << 6)
    var in_string = scanner.next(quote, UInt64(0))
    # prefix_xor(bit0 | bit6): bits 0-5 set, bit 6 onward clear
    var expected: UInt64 = (UInt64(1) << 6) - 1  # bits 0-5
    assert_equal(in_string, expected)


def test_string_escaped_quote() raises:
    """Escaped quote doesn't toggle string state."""
    var scanner = StringScanner()
    # Real quotes at 0 and 5, escaped "quote" at 3
    var quote: UInt64 = (UInt64(1) << 0) | (UInt64(1) << 3) | (UInt64(1) << 5)
    var escaped: UInt64 = UInt64(1) << 3  # pos 3 is escaped
    var in_string = scanner.next(quote, escaped)
    # real_quotes = bit0 | bit5. prefix_xor -> bits 0-4 set
    var expected: UInt64 = (UInt64(1) << 5) - 1  # bits 0-4
    assert_equal(in_string, expected)


def test_string_carry_across_blocks() raises:
    """String opens in block 1 (no close) -> block 2 entirely in-string."""
    var scanner = StringScanner()
    # Block 1: quote at pos 5, no closing quote
    var quote1: UInt64 = UInt64(1) << 5
    var in_string1 = scanner.next(quote1, UInt64(0))
    # prefix_xor(bit5) = bits 5-63 set
    var expected1: UInt64 = ~((UInt64(1) << 5) - 1)  # bits 5-63
    assert_equal(in_string1, expected1)
    # prev_in_string should now be ~0 (bit 63 was set)
    assert_equal(scanner.prev_in_string, ~UInt64(0))
    # Block 2: no quotes -> entirely in-string
    var in_string2 = scanner.next(UInt64(0), UInt64(0))
    assert_equal(in_string2, ~UInt64(0))


def main() raises:
    test_escape_no_backslashes()
    test_escape_single_backslash()
    test_escape_double_backslash()
    test_escape_triple_backslash()
    test_escape_carry_across_blocks()
    test_string_basic_quotes()
    test_string_escaped_quote()
    test_string_carry_across_blocks()
    print("test_string_mask: all passed")
