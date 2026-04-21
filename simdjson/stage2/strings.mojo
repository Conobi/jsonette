"""JSON string parser with SIMD-accelerated scanning.

Parses JSON strings (opening quote to closing quote), handling all escape
sequences including \\uXXXX unicode escapes and surrogate pairs. Uses 32-byte
SIMD scanning to find quotes, backslashes, and control characters in bulk.

String buffer layout: [UInt32 length (LE)][UTF-8 bytes][0x00 null terminator]
"""

from simdjson.stage1.simd_ops import movemask_epi8
from simdjson.error import ParseError, ErrorCode
from std.bit import count_trailing_zeros
from std.memory import memcpy


def _bulk_copy(
    mut string_buf: List[UInt8],
    write_pos: Int,
    src_ptr: UnsafePointer[UInt8, _],
    count: Int,
):
    """Copy count bytes from src_ptr into string_buf at write_pos."""
    string_buf.resize(write_pos + count, 0)
    memcpy(dest=string_buf.unsafe_ptr() + write_pos, src=src_ptr, count=count)


def _handle_escape(
    input_ptr: UnsafePointer[UInt8, _],
    i: Int,
    input_len: Int,
    mut string_buf: List[UInt8],
    write_pos: Int,
) raises ParseError -> Tuple[Int, Int]:
    """Handle a backslash escape sequence. Returns (new_i, new_write_pos)."""
    if i + 1 >= input_len:
        raise ParseError(code=ErrorCode.UNCLOSED_STRING.value, position=i, message="UNCLOSED_STRING: escape at end of input")
    var escaped = input_ptr[i + 1]
    if escaped == UInt8(0x22):  # \"
        string_buf.resize(write_pos + 1, 0)
        string_buf[write_pos] = UInt8(0x22)
        return (i + 2, write_pos + 1)
    elif escaped == UInt8(0x5C):  # \\
        string_buf.resize(write_pos + 1, 0)
        string_buf[write_pos] = UInt8(0x5C)
        return (i + 2, write_pos + 1)
    elif escaped == UInt8(0x2F):  # \/
        string_buf.resize(write_pos + 1, 0)
        string_buf[write_pos] = UInt8(0x2F)
        return (i + 2, write_pos + 1)
    elif escaped == UInt8(0x62):  # \b
        string_buf.resize(write_pos + 1, 0)
        string_buf[write_pos] = UInt8(0x08)
        return (i + 2, write_pos + 1)
    elif escaped == UInt8(0x66):  # \f
        string_buf.resize(write_pos + 1, 0)
        string_buf[write_pos] = UInt8(0x0C)
        return (i + 2, write_pos + 1)
    elif escaped == UInt8(0x6E):  # \n
        string_buf.resize(write_pos + 1, 0)
        string_buf[write_pos] = UInt8(0x0A)
        return (i + 2, write_pos + 1)
    elif escaped == UInt8(0x72):  # \r
        string_buf.resize(write_pos + 1, 0)
        string_buf[write_pos] = UInt8(0x0D)
        return (i + 2, write_pos + 1)
    elif escaped == UInt8(0x74):  # \t
        string_buf.resize(write_pos + 1, 0)
        string_buf[write_pos] = UInt8(0x09)
        return (i + 2, write_pos + 1)
    elif escaped == UInt8(0x75):  # \uXXXX
        var new_i = _parse_unicode_escape(input_ptr, i, input_len, string_buf)
        # _parse_unicode_escape appends bytes directly; figure out new write_pos
        var new_write_pos = len(string_buf)
        return (new_i, new_write_pos)
    else:
        raise ParseError(code=ErrorCode.STRING_ERROR.value, position=i, message="STRING_ERROR: invalid escape sequence at position " + String(i))


def parse_string(
    input_ptr: UnsafePointer[UInt8, _],
    pos: Int,
    input_len: Int,
    mut string_buf: List[UInt8],
) raises ParseError -> Int:
    """Parse a JSON string starting at input_ptr[pos] (opening quote).

    Writes to string_buf: [UInt32 length (LE)][UTF-8 bytes][0x00].
    Returns: number of input bytes consumed (from opening to closing quote inclusive).

    Uses 32-byte SIMD scanning to find quotes, backslashes, and control
    characters in bulk. The input buffer must have at least 32 bytes of
    padding beyond input_len for safe SIMD loads.
    """
    var buf_start = len(string_buf)

    # Reserve 4 bytes for length prefix
    string_buf.resize(buf_start + 4, 0)
    var write_pos = buf_start + 4

    var i = pos + 1  # skip opening quote

    comptime QUOTE = UInt8(0x22)
    comptime BACKSLASH = UInt8(0x5C)
    comptime CONTROL_MAX = UInt8(0x1F)

    var quote_splat = SIMD[DType.uint8, 32](QUOTE)
    var bs_splat = SIMD[DType.uint8, 32](BACKSLASH)
    var ctrl_splat = SIMD[DType.uint8, 32](CONTROL_MAX)

    while i < input_len:
        # --- SIMD scan: load 32 bytes and classify ---
        var chunk = (input_ptr + i).load[width=32]()

        var quote_cmp = chunk.eq(quote_splat).select(
            SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
        )
        var bs_cmp = chunk.eq(bs_splat).select(
            SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
        )
        var ctrl_cmp = chunk.le(ctrl_splat).select(
            SIMD[DType.uint8, 32](0xFF), SIMD[DType.uint8, 32](0)
        )

        var quote_mask = UInt32(movemask_epi8(quote_cmp).cast[DType.uint32]()) & 0xFFFFFFFF
        var bs_mask = UInt32(movemask_epi8(bs_cmp).cast[DType.uint32]()) & 0xFFFFFFFF
        var ctrl_mask = UInt32(movemask_epi8(ctrl_cmp).cast[DType.uint32]()) & 0xFFFFFFFF

        var special_mask = quote_mask | bs_mask

        if special_mask == 0 and ctrl_mask == 0:
            # No special characters in this 32-byte chunk — bulk copy
            _bulk_copy(string_buf, write_pos, input_ptr + i, 32)
            write_pos += 32
            i += 32
            continue

        # Find the first special character position
        var first_special = Int(count_trailing_zeros(special_mask)) if special_mask != 0 else 32
        var first_ctrl = Int(count_trailing_zeros(ctrl_mask)) if ctrl_mask != 0 else 32

        # Check for control char before any quote/backslash
        if first_ctrl < first_special:
            raise ParseError(code=ErrorCode.STRING_ERROR.value, position=i + first_ctrl, message="STRING_ERROR: unescaped control character at position " + String(
                i + first_ctrl
            ))

        # Bulk copy bytes before the first special character
        if first_special > 0:
            _bulk_copy(string_buf, write_pos, input_ptr + i, first_special)
            write_pos += first_special
            i += first_special

        # Now handle the special character
        var b = input_ptr[i]
        if b == QUOTE:
            # Closing quote found — finalize string
            string_buf.resize(write_pos + 1, 0)
            string_buf[write_pos] = UInt8(0)  # null terminator
            var str_len = UInt32(write_pos - buf_start - 4)
            string_buf[buf_start] = UInt8(str_len & 0xFF)
            string_buf[buf_start + 1] = UInt8((str_len >> 8) & 0xFF)
            string_buf[buf_start + 2] = UInt8((str_len >> 16) & 0xFF)
            string_buf[buf_start + 3] = UInt8((str_len >> 24) & 0xFF)
            return i - pos + 1
        elif b == BACKSLASH:
            # Handle escape sequence
            var result = _handle_escape(
                input_ptr, i, input_len, string_buf, write_pos
            )
            i = result[0]
            write_pos = result[1]
        else:
            # Should not reach here
            raise ParseError(code=ErrorCode.STRING_ERROR.value, position=i, message="STRING_ERROR: unexpected byte at position " + String(i))

    raise ParseError(code=ErrorCode.UNCLOSED_STRING.value, position=pos, message="UNCLOSED_STRING: no closing quote found")


def _parse_hex4(
    ptr: UnsafePointer[UInt8, _], start: Int, input_len: Int
) raises ParseError -> UInt32:
    """Parse 4 hex digits starting at ptr[start] into a UInt32."""
    if start + 4 > input_len:
        raise ParseError(code=ErrorCode.STRING_ERROR.value, position=start, message="STRING_ERROR: incomplete hex escape")
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
            raise ParseError(code=ErrorCode.STRING_ERROR.value, position=start + i, message="STRING_ERROR: invalid hex digit at position " + String(
                start + i
            ))
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
) raises ParseError -> Int:
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
            raise ParseError(code=ErrorCode.STRING_ERROR.value, position=backslash_pos, message="STRING_ERROR: orphan high surrogate at position " + String(
                backslash_pos
            ))
        var low = _parse_hex4(ptr, new_pos + 2, input_len)
        if low < 0xDC00 or low > 0xDFFF:
            raise ParseError(code=ErrorCode.STRING_ERROR.value, position=new_pos, message="STRING_ERROR: invalid low surrogate at position " + String(
                new_pos
            ))
        code_point = 0x10000 + (code_point - 0xD800) * 0x400 + (low - 0xDC00)
        new_pos += 6
    elif code_point >= 0xDC00 and code_point <= 0xDFFF:
        raise ParseError(code=ErrorCode.STRING_ERROR.value, position=backslash_pos, message="STRING_ERROR: orphan low surrogate at position " + String(
            backslash_pos
        ))

    _encode_utf8(code_point, string_buf)
    return new_pos
