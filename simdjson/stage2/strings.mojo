"""JSON string parser with escape and unicode handling.

Parses JSON strings (opening quote to closing quote), handling all escape
sequences including \\uXXXX unicode escapes and surrogate pairs.

String buffer layout: [UInt32 length (LE)][UTF-8 bytes][0x00 null terminator]
"""


def parse_string(
    input_ptr: UnsafePointer[UInt8, _],
    pos: Int,
    input_len: Int,
    mut string_buf: List[UInt8],
) raises -> Int:
    """Parse a JSON string starting at input_ptr[pos] (opening quote).

    Writes to string_buf: [UInt32 length (LE)][UTF-8 bytes][0x00].
    Returns: number of input bytes consumed (from opening to closing quote inclusive).
    """
    var buf_start = len(string_buf)

    # Reserve 4 bytes for length prefix
    string_buf.append(UInt8(0))
    string_buf.append(UInt8(0))
    string_buf.append(UInt8(0))
    string_buf.append(UInt8(0))

    var i = pos + 1  # skip opening quote

    while i < input_len:
        var b = input_ptr[i]
        if b == UInt8(0x5C):  # backslash
            if i + 1 >= input_len:
                raise "UNCLOSED_STRING: escape at end of input"
            var escaped = input_ptr[i + 1]
            if escaped == UInt8(0x22):  # \"
                string_buf.append(UInt8(0x22))
                i += 2
            elif escaped == UInt8(0x5C):  # \\
                string_buf.append(UInt8(0x5C))
                i += 2
            elif escaped == UInt8(0x2F):  # \/
                string_buf.append(UInt8(0x2F))
                i += 2
            elif escaped == UInt8(0x62):  # \b
                string_buf.append(UInt8(0x08))
                i += 2
            elif escaped == UInt8(0x66):  # \f
                string_buf.append(UInt8(0x0C))
                i += 2
            elif escaped == UInt8(0x6E):  # \n
                string_buf.append(UInt8(0x0A))
                i += 2
            elif escaped == UInt8(0x72):  # \r
                string_buf.append(UInt8(0x0D))
                i += 2
            elif escaped == UInt8(0x74):  # \t
                string_buf.append(UInt8(0x09))
                i += 2
            elif escaped == UInt8(0x75):  # \uXXXX
                i = _parse_unicode_escape(input_ptr, i, input_len, string_buf)
            else:
                raise "STRING_ERROR: invalid escape sequence at position " + String(i)
        elif b == UInt8(0x22):  # closing quote
            string_buf.append(UInt8(0))  # null terminator
            var str_len = UInt32(len(string_buf) - buf_start - 4 - 1)
            string_buf[buf_start] = UInt8(str_len & 0xFF)
            string_buf[buf_start + 1] = UInt8((str_len >> 8) & 0xFF)
            string_buf[buf_start + 2] = UInt8((str_len >> 16) & 0xFF)
            string_buf[buf_start + 3] = UInt8((str_len >> 24) & 0xFF)
            return i - pos + 1
        else:
            if b <= UInt8(0x1F):
                raise "STRING_ERROR: unescaped control character at position " + String(i)
            string_buf.append(b)
            i += 1

    raise "UNCLOSED_STRING: no closing quote found"


def _parse_hex4(
    ptr: UnsafePointer[UInt8, _], start: Int, input_len: Int
) raises -> UInt32:
    """Parse 4 hex digits starting at ptr[start] into a UInt32."""
    if start + 4 > input_len:
        raise "STRING_ERROR: incomplete hex escape"
    var value: UInt32 = 0
    for i in range(4):
        var b = ptr[start + i]
        var digit: UInt32
        if b >= UInt8(0x30) and b <= UInt8(0x39):
            digit = UInt32(b) - 0x30
        elif b >= UInt8(0x61) and b <= UInt8(0x66):
            digit = UInt32(b) - 0x61 + 10
        elif b >= UInt8(0x41) and b <= UInt8(0x46):
            digit = UInt32(b) - 0x41 + 10
        else:
            raise "STRING_ERROR: invalid hex digit at position " + String(
                start + i
            )
        value = (value << 4) | digit
    return value


def _encode_utf8(code_point: UInt32, mut buf: List[UInt8]):
    """Encode a Unicode code point as UTF-8 bytes into buf."""
    if code_point <= 0x7F:
        buf.append(UInt8(code_point))
    elif code_point <= 0x7FF:
        buf.append(UInt8(0xC0 | (code_point >> 6)))
        buf.append(UInt8(0x80 | (code_point & 0x3F)))
    elif code_point <= 0xFFFF:
        buf.append(UInt8(0xE0 | (code_point >> 12)))
        buf.append(UInt8(0x80 | ((code_point >> 6) & 0x3F)))
        buf.append(UInt8(0x80 | (code_point & 0x3F)))
    else:
        buf.append(UInt8(0xF0 | (code_point >> 18)))
        buf.append(UInt8(0x80 | ((code_point >> 12) & 0x3F)))
        buf.append(UInt8(0x80 | ((code_point >> 6) & 0x3F)))
        buf.append(UInt8(0x80 | (code_point & 0x3F)))


def _parse_unicode_escape(
    ptr: UnsafePointer[UInt8, _],
    backslash_pos: Int,
    input_len: Int,
    mut string_buf: List[UInt8],
) raises -> Int:
    """Parse \\uXXXX (and surrogate pairs \\uXXXX\\uXXXX) starting at backslash_pos.

    Returns the new position after the escape sequence.
    """
    var hex_start = backslash_pos + 2
    var code_point = _parse_hex4(ptr, hex_start, input_len)
    var new_pos = backslash_pos + 6

    if code_point >= 0xD800 and code_point <= 0xDBFF:
        # High surrogate — must be followed by \uXXXX low surrogate
        if (
            new_pos + 1 >= input_len
            or ptr[new_pos] != UInt8(0x5C)
            or ptr[new_pos + 1] != UInt8(0x75)
        ):
            raise "STRING_ERROR: orphan high surrogate at position " + String(
                backslash_pos
            )
        var low = _parse_hex4(ptr, new_pos + 2, input_len)
        if low < 0xDC00 or low > 0xDFFF:
            raise "STRING_ERROR: invalid low surrogate at position " + String(
                new_pos
            )
        code_point = 0x10000 + (code_point - 0xD800) * 0x400 + (low - 0xDC00)
        new_pos += 6
    elif code_point >= 0xDC00 and code_point <= 0xDFFF:
        raise "STRING_ERROR: orphan low surrogate at position " + String(
            backslash_pos
        )

    _encode_utf8(code_point, string_buf)
    return new_pos
