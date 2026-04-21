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
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    var result = parse_string(input.unsafe_ptr(), 0, len(input), string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 7)
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(5))  # length low byte
    assert_equal(string_buf.unsafe_ptr()[1], UInt8(0))
    assert_equal(string_buf.unsafe_ptr()[2], UInt8(0))
    assert_equal(string_buf.unsafe_ptr()[3], UInt8(0))
    assert_equal(string_buf.unsafe_ptr()[4], UInt8(0x68))  # 'h'
    assert_equal(string_buf.unsafe_ptr()[5], UInt8(0x65))  # 'e'
    assert_equal(string_buf.unsafe_ptr()[9], UInt8(0))     # null terminator


def test_empty_string() raises:
    """Parse '""' — empty string."""
    var input = _make_bytes(String('""'))
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    var result = parse_string(input.unsafe_ptr(), 0, len(input), string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 2)
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(0))
    assert_equal(string_buf.unsafe_ptr()[4], UInt8(0))  # null terminator


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
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    var result = parse_string(input.unsafe_ptr(), 0, len(input), string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 6)
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(3))  # length
    assert_equal(string_buf.unsafe_ptr()[4], UInt8(0x61))  # a
    assert_equal(string_buf.unsafe_ptr()[5], UInt8(0x22))  # "
    assert_equal(string_buf.unsafe_ptr()[6], UInt8(0x62))  # b


def test_escape_sequences() raises:
    """Parse all basic escape sequences: \\n \\t \\r."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x5C)); input.append(UInt8(0x6E))  # \n
    input.append(UInt8(0x5C)); input.append(UInt8(0x74))  # \t
    input.append(UInt8(0x5C)); input.append(UInt8(0x72))  # \r
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    var result = parse_string(input.unsafe_ptr(), 0, len(input), string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 8)
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(3))     # length = 3
    assert_equal(string_buf.unsafe_ptr()[4], UInt8(0x0A))  # \n
    assert_equal(string_buf.unsafe_ptr()[5], UInt8(0x09))  # \t
    assert_equal(string_buf.unsafe_ptr()[6], UInt8(0x0D))  # \r


def test_escaped_backslash() raises:
    """Parse string with escaped backslashes."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x5C)); input.append(UInt8(0x5C))  # \\
    input.append(UInt8(0x5C)); input.append(UInt8(0x5C))  # \\
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    var result = parse_string(input.unsafe_ptr(), 0, len(input), string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 6)
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(2))     # length = 2
    assert_equal(string_buf.unsafe_ptr()[4], UInt8(0x5C))  # backslash
    assert_equal(string_buf.unsafe_ptr()[5], UInt8(0x5C))  # backslash


def test_string_at_offset() raises:
    """Parse string starting at non-zero offset."""
    var input = _make_bytes(String('  "hi"'))
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    var result = parse_string(input.unsafe_ptr(), 2, len(input), string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 4)
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(2))     # length = 2
    assert_equal(string_buf.unsafe_ptr()[4], UInt8(0x68))  # 'h'
    assert_equal(string_buf.unsafe_ptr()[5], UInt8(0x69))  # 'i'


def test_unicode_escape_ascii() raises:
    """Parse '\\u0041' (A = U+0041)."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x5C)); input.append(UInt8(0x75))  # \u
    input.append(UInt8(0x30)); input.append(UInt8(0x30))  # 00
    input.append(UInt8(0x34)); input.append(UInt8(0x31))  # 41
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    var result = parse_string(input.unsafe_ptr(), 0, len(input), string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 8)
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(1))     # length = 1
    assert_equal(string_buf.unsafe_ptr()[4], UInt8(0x41))  # 'A'


def test_unicode_escape_2byte() raises:
    """Parse '\\u00E9' (e-acute = U+00E9, 2-byte UTF-8: C3 A9)."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x5C)); input.append(UInt8(0x75))  # \u
    input.append(UInt8(0x30)); input.append(UInt8(0x30))  # 00
    input.append(UInt8(0x45)); input.append(UInt8(0x39))  # E9
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    _ = parse_string(input.unsafe_ptr(), 0, len(input), string_buf.unsafe_ptr(), 0)
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(2))     # 2-byte UTF-8
    assert_equal(string_buf.unsafe_ptr()[4], UInt8(0xC3))
    assert_equal(string_buf.unsafe_ptr()[5], UInt8(0xA9))


def test_unicode_escape_3byte() raises:
    """Parse '\\u4E16' (CJK char = U+4E16, 3-byte UTF-8: E4 B8 96)."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x5C)); input.append(UInt8(0x75))  # \u
    input.append(UInt8(0x34)); input.append(UInt8(0x45))  # 4E
    input.append(UInt8(0x31)); input.append(UInt8(0x36))  # 16
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    _ = parse_string(input.unsafe_ptr(), 0, len(input), string_buf.unsafe_ptr(), 0)
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(3))     # 3-byte UTF-8
    assert_equal(string_buf.unsafe_ptr()[4], UInt8(0xE4))
    assert_equal(string_buf.unsafe_ptr()[5], UInt8(0xB8))
    assert_equal(string_buf.unsafe_ptr()[6], UInt8(0x96))


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
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    _ = parse_string(input.unsafe_ptr(), 0, len(input), string_buf.unsafe_ptr(), 0)
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(4))     # 4-byte UTF-8
    assert_equal(string_buf.unsafe_ptr()[4], UInt8(0xF0))
    assert_equal(string_buf.unsafe_ptr()[5], UInt8(0x9F))
    assert_equal(string_buf.unsafe_ptr()[6], UInt8(0x91))
    assert_equal(string_buf.unsafe_ptr()[7], UInt8(0x8D))


def test_control_char_rejected() raises:
    """Unescaped control character (0x0A newline) should raise."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x61))  # a
    input.append(UInt8(0x0A))  # raw newline (invalid)
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    var raised = False
    try:
        _ = parse_string(input.unsafe_ptr(), 0, len(input), string_buf.unsafe_ptr(), 0)
    except:
        raised = True
    assert_equal(raised, True)

def test_long_string_no_escapes() raises:
    """42-char string with no escapes — exercises bulk copy path."""
    # Build: " + 42 x 'A' + " + 128 zero-byte padding
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # opening "
    for _ in range(42):
        input.append(UInt8(0x41))  # 'A'
    input.append(UInt8(0x22))  # closing "
    var real_len = len(input)
    for _ in range(128):
        input.append(UInt8(0))  # SIMD safety padding
    var string_buf = List[UInt8](unsafe_uninit_length=real_len + 128)
    var result = parse_string(input.unsafe_ptr(), 0, real_len, string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 44)  # 1 open + 42 chars + 1 close
    # Length prefix should be 42 (LE UInt32)
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(42))
    assert_equal(string_buf.unsafe_ptr()[1], UInt8(0))
    assert_equal(string_buf.unsafe_ptr()[2], UInt8(0))
    assert_equal(string_buf.unsafe_ptr()[3], UInt8(0))
    # All content bytes should be 'A'
    for i in range(42):
        assert_equal(string_buf.unsafe_ptr()[4 + i], UInt8(0x41))
    # Null terminator
    assert_equal(string_buf.unsafe_ptr()[4 + 42], UInt8(0))


def test_escape_at_position_31() raises:
    """Backslash at byte 31 (SIMD boundary - 1), straddles 32-byte lane."""
    # Content: 30 x 'x' + \n + 'y' = 30 + 2 escape bytes + 1 = 33 content bytes
    # Input:   " + 30 x 'x' + '\' + 'n' + 'y' + "
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # opening " at pos 0
    for _ in range(30):
        input.append(UInt8(0x78))  # 'x'
    # Backslash at input position 31
    input.append(UInt8(0x5C))  # backslash
    input.append(UInt8(0x6E))  # 'n'
    input.append(UInt8(0x79))  # 'y'
    input.append(UInt8(0x22))  # closing "
    var real_len = len(input)
    for _ in range(128):
        input.append(UInt8(0))
    var string_buf = List[UInt8](unsafe_uninit_length=real_len + 128)
    var result = parse_string(input.unsafe_ptr(), 0, real_len, string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 35)  # 1 + 30 + 2 + 1 + 1
    # Output: 30 x 'x' + 0x0A + 'y' = 32 bytes
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(32))
    assert_equal(string_buf.unsafe_ptr()[4 + 30], UInt8(0x0A))  # decoded \n
    assert_equal(string_buf.unsafe_ptr()[4 + 31], UInt8(0x79))  # 'y'


def test_escape_at_position_32() raises:
    """Backslash at byte 32 (exact SIMD boundary)."""
    # Content: 31 x 'x' + \t + 'y'
    # Input:   " + 31 x 'x' + '\' + 't' + 'y' + "
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # opening " at pos 0
    for _ in range(31):
        input.append(UInt8(0x78))  # 'x'
    # Backslash at input position 32
    input.append(UInt8(0x5C))  # backslash
    input.append(UInt8(0x74))  # 't'
    input.append(UInt8(0x79))  # 'y'
    input.append(UInt8(0x22))  # closing "
    var real_len = len(input)
    for _ in range(128):
        input.append(UInt8(0))
    var string_buf = List[UInt8](unsafe_uninit_length=real_len + 128)
    var result = parse_string(input.unsafe_ptr(), 0, real_len, string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 36)  # 1 + 31 + 2 + 1 + 1
    # Output: 31 x 'x' + 0x09 + 'y' = 33 bytes
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(33))
    assert_equal(string_buf.unsafe_ptr()[4 + 31], UInt8(0x09))  # decoded \t
    assert_equal(string_buf.unsafe_ptr()[4 + 32], UInt8(0x79))  # 'y'


def test_string_exactly_32_bytes() raises:
    """String content exactly 32 bytes — one full SIMD lane."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # opening "
    for i in range(32):
        input.append(UInt8(0x61 + (i % 26)))  # 'a'..'z' cycling
    input.append(UInt8(0x22))  # closing "
    var real_len = len(input)
    for _ in range(128):
        input.append(UInt8(0))
    var string_buf = List[UInt8](unsafe_uninit_length=real_len + 128)
    var result = parse_string(input.unsafe_ptr(), 0, real_len, string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 34)  # 1 + 32 + 1
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(32))  # length
    # Spot-check first and last content bytes
    assert_equal(string_buf.unsafe_ptr()[4], UInt8(0x61))       # 'a'
    assert_equal(string_buf.unsafe_ptr()[4 + 31], UInt8(0x61 + (31 % 26)))  # 'f'
    assert_equal(string_buf.unsafe_ptr()[4 + 32], UInt8(0))     # null terminator


def test_string_64_bytes_with_middle_escape() raises:
    """64-byte string content with escape in the middle (position ~32)."""
    # 31 x 'a' + \n + 30 x 'b' = 31 + 2 + 30 = 63 input content bytes
    # Output: 31 + 1 + 30 = 62 decoded bytes
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # opening "
    for _ in range(31):
        input.append(UInt8(0x61))  # 'a'
    input.append(UInt8(0x5C))  # backslash at content position 31
    input.append(UInt8(0x6E))  # 'n'
    for _ in range(30):
        input.append(UInt8(0x62))  # 'b'
    input.append(UInt8(0x22))  # closing "
    var real_len = len(input)
    for _ in range(128):
        input.append(UInt8(0))
    var string_buf = List[UInt8](unsafe_uninit_length=real_len + 128)
    var result = parse_string(input.unsafe_ptr(), 0, real_len, string_buf.unsafe_ptr(), 0)
    var consumed = result[0]
    assert_equal(consumed, 65)  # 1 + 63 + 1
    assert_equal(string_buf.unsafe_ptr()[0], UInt8(62))  # decoded length
    # Check boundary region
    assert_equal(string_buf.unsafe_ptr()[4 + 30], UInt8(0x61))  # last 'a'
    assert_equal(string_buf.unsafe_ptr()[4 + 31], UInt8(0x0A))  # decoded \n
    assert_equal(string_buf.unsafe_ptr()[4 + 32], UInt8(0x62))  # first 'b'
    assert_equal(string_buf.unsafe_ptr()[4 + 61], UInt8(0x62))  # last 'b'
    assert_equal(string_buf.unsafe_ptr()[4 + 62], UInt8(0))     # null terminator


def test_control_char_null_rejected() raises:
    """Unescaped null byte should raise."""
    var input = List[UInt8]()
    input.append(UInt8(0x22))  # "
    input.append(UInt8(0x00))  # null
    input.append(UInt8(0x22))  # "
    var string_buf = List[UInt8](unsafe_uninit_length=1024)
    var raised = False
    try:
        _ = parse_string(input.unsafe_ptr(), 0, len(input), string_buf.unsafe_ptr(), 0)
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
    test_long_string_no_escapes()
    test_escape_at_position_31()
    test_escape_at_position_32()
    test_string_exactly_32_bytes()
    test_string_64_bytes_with_middle_escape()
    test_control_char_rejected()
    test_control_char_null_rejected()
    print("test_strings: all passed")
