from std.testing import assert_equal
from simdjson.stage2.strings import parse_string


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def test_simple_string() raises:
    """Parse '"hello"' — no escapes."""
    var input = _make_bytes(String('"hello"'))
    var string_buf = List[UInt8]()
    var consumed = parse_string(input.unsafe_ptr(), 0, len(input), string_buf)
    assert_equal(consumed, 7)
    assert_equal(string_buf[0], UInt8(5))  # length low byte
    assert_equal(string_buf[1], UInt8(0))
    assert_equal(string_buf[2], UInt8(0))
    assert_equal(string_buf[3], UInt8(0))
    assert_equal(string_buf[4], UInt8(0x68))  # 'h'
    assert_equal(string_buf[5], UInt8(0x65))  # 'e'
    assert_equal(string_buf[9], UInt8(0))     # null terminator


def test_empty_string() raises:
    """Parse '""' — empty string."""
    var input = _make_bytes(String('""'))
    var string_buf = List[UInt8]()
    var consumed = parse_string(input.unsafe_ptr(), 0, len(input), string_buf)
    assert_equal(consumed, 2)
    assert_equal(string_buf[0], UInt8(0))
    assert_equal(string_buf[4], UInt8(0))  # null terminator


def test_escaped_quote() raises:
    """Parse string with escaped quote."""
    # Input bytes: " a \ " b "
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x61))  # a
    input.append(UInt8(0x5C))  # backslash
    input.append(UInt8(0x22))  # " (escaped)
    input.append(UInt8(0x62))  # b
    input.append(UInt8(0x22))  # " (closing)
    var string_buf = List[UInt8]()
    var consumed = parse_string(input.unsafe_ptr(), 0, len(input), string_buf)
    assert_equal(consumed, 6)
    assert_equal(string_buf[0], UInt8(3))  # length
    assert_equal(string_buf[4], UInt8(0x61))  # a
    assert_equal(string_buf[5], UInt8(0x22))  # "
    assert_equal(string_buf[6], UInt8(0x62))  # b


def test_escape_sequences() raises:
    """Parse all basic escape sequences: \\n \\t \\r."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x5C)); input.append(UInt8(0x6E))  # \n
    input.append(UInt8(0x5C)); input.append(UInt8(0x74))  # \t
    input.append(UInt8(0x5C)); input.append(UInt8(0x72))  # \r
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8]()
    var consumed = parse_string(input.unsafe_ptr(), 0, len(input), string_buf)
    assert_equal(consumed, 8)
    assert_equal(string_buf[0], UInt8(3))     # length = 3
    assert_equal(string_buf[4], UInt8(0x0A))  # \n
    assert_equal(string_buf[5], UInt8(0x09))  # \t
    assert_equal(string_buf[6], UInt8(0x0D))  # \r


def test_escaped_backslash() raises:
    """Parse string with escaped backslashes."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x5C)); input.append(UInt8(0x5C))  # \\
    input.append(UInt8(0x5C)); input.append(UInt8(0x5C))  # \\
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8]()
    var consumed = parse_string(input.unsafe_ptr(), 0, len(input), string_buf)
    assert_equal(consumed, 6)
    assert_equal(string_buf[0], UInt8(2))     # length = 2
    assert_equal(string_buf[4], UInt8(0x5C))  # backslash
    assert_equal(string_buf[5], UInt8(0x5C))  # backslash


def test_string_at_offset() raises:
    """Parse string starting at non-zero offset."""
    var input = _make_bytes(String('  "hi"'))
    var string_buf = List[UInt8]()
    var consumed = parse_string(input.unsafe_ptr(), 2, len(input), string_buf)
    assert_equal(consumed, 4)
    assert_equal(string_buf[0], UInt8(2))     # length = 2
    assert_equal(string_buf[4], UInt8(0x68))  # 'h'
    assert_equal(string_buf[5], UInt8(0x69))  # 'i'


def test_unicode_escape_ascii() raises:
    """Parse '\\u0041' (A = U+0041)."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x5C)); input.append(UInt8(0x75))  # \u
    input.append(UInt8(0x30)); input.append(UInt8(0x30))  # 00
    input.append(UInt8(0x34)); input.append(UInt8(0x31))  # 41
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8]()
    var consumed = parse_string(input.unsafe_ptr(), 0, len(input), string_buf)
    assert_equal(consumed, 8)
    assert_equal(string_buf[0], UInt8(1))     # length = 1
    assert_equal(string_buf[4], UInt8(0x41))  # 'A'


def test_unicode_escape_2byte() raises:
    """Parse '\\u00E9' (e-acute = U+00E9, 2-byte UTF-8: C3 A9)."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x5C)); input.append(UInt8(0x75))  # \u
    input.append(UInt8(0x30)); input.append(UInt8(0x30))  # 00
    input.append(UInt8(0x45)); input.append(UInt8(0x39))  # E9
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8]()
    _ = parse_string(input.unsafe_ptr(), 0, len(input), string_buf)
    assert_equal(string_buf[0], UInt8(2))     # 2-byte UTF-8
    assert_equal(string_buf[4], UInt8(0xC3))
    assert_equal(string_buf[5], UInt8(0xA9))


def test_unicode_escape_3byte() raises:
    """Parse '\\u4E16' (CJK char = U+4E16, 3-byte UTF-8: E4 B8 96)."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x5C)); input.append(UInt8(0x75))  # \u
    input.append(UInt8(0x34)); input.append(UInt8(0x45))  # 4E
    input.append(UInt8(0x31)); input.append(UInt8(0x36))  # 16
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8]()
    _ = parse_string(input.unsafe_ptr(), 0, len(input), string_buf)
    assert_equal(string_buf[0], UInt8(3))     # 3-byte UTF-8
    assert_equal(string_buf[4], UInt8(0xE4))
    assert_equal(string_buf[5], UInt8(0xB8))
    assert_equal(string_buf[6], UInt8(0x96))


def test_surrogate_pair() raises:
    """Parse surrogate pair for U+1F44D (thumbs up, 4-byte UTF-8: F0 9F 91 8D)."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    # \uD83D
    input.append(UInt8(0x5C)); input.append(UInt8(0x75))
    input.append(UInt8(0x44)); input.append(UInt8(0x38))
    input.append(UInt8(0x33)); input.append(UInt8(0x44))
    # \uDC4D
    input.append(UInt8(0x5C)); input.append(UInt8(0x75))
    input.append(UInt8(0x44)); input.append(UInt8(0x43))
    input.append(UInt8(0x34)); input.append(UInt8(0x44))
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8]()
    _ = parse_string(input.unsafe_ptr(), 0, len(input), string_buf)
    assert_equal(string_buf[0], UInt8(4))     # 4-byte UTF-8
    assert_equal(string_buf[4], UInt8(0xF0))
    assert_equal(string_buf[5], UInt8(0x9F))
    assert_equal(string_buf[6], UInt8(0x91))
    assert_equal(string_buf[7], UInt8(0x8D))


def test_control_char_rejected() raises:
    """Unescaped control character (0x0A newline) should raise."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x61))  # a
    input.append(UInt8(0x0A))  # raw newline (invalid)
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8]()
    var raised = False
    try:
        _ = parse_string(input.unsafe_ptr(), 0, len(input), string_buf)
    except:
        raised = True
    assert_equal(raised, True)

def test_control_char_null_rejected() raises:
    """Unescaped null byte should raise."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x00))  # null
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8]()
    var raised = False
    try:
        _ = parse_string(input.unsafe_ptr(), 0, len(input), string_buf)
    except:
        raised = True
    assert_equal(raised, True)


def main() raises:
    test_simple_string()
    test_empty_string()
    test_escaped_quote()
    test_escape_sequences()
    test_escaped_backslash()
    test_string_at_offset()
    test_unicode_escape_ascii()
    test_unicode_escape_2byte()
    test_unicode_escape_3byte()
    test_surrogate_pair()
    test_control_char_rejected()
    test_control_char_null_rejected()
    print("test_strings: all passed")
