"""JSON string parser with SIMD-accelerated scanning.

Parses JSON strings (opening quote to closing quote), handling all escape
sequences including \\uXXXX unicode escapes and surrogate pairs. Uses 32-byte
SIMD scanning with unconditional stores (copy first, check after) and a
256-byte escape lookup table for branchless dispatch.

String buffer layout: [UInt32 length (LE)][UTF-8 bytes][0x00 null terminator]
"""

from std.memory import pack_bits
from jsonette.error import ParseError, ErrorCode
from std.bit import count_trailing_zeros
from std.memory import memcpy


# --- Escape lookup table (comptime) ---


def _build_escape_table() -> InlineArray[UInt8, 256]:
    """Build a 256-byte LUT mapping escaped byte -> replacement byte.
    0x00 = invalid escape, 0xFE = \\u sentinel for unicode escapes."""
    var t = InlineArray[UInt8, 256](fill=UInt8(0))
    t[0x22] = UInt8(0x22)  # \" -> "
    t[0x5C] = UInt8(0x5C)  # \\ -> backslash
    t[0x2F] = UInt8(0x2F)  # \/ -> /
    t[0x62] = UInt8(0x08)  # \b -> BS
    t[0x66] = UInt8(0x0C)  # \f -> FF
    t[0x6E] = UInt8(0x0A)  # \n -> LF
    t[0x72] = UInt8(0x0D)  # \r -> CR
    t[0x74] = UInt8(0x09)  # \t -> TAB
    t[0x75] = UInt8(0xFE)  # \u -> unicode sentinel
    return t^


comptime _ESCAPE_LUT: InlineArray[UInt8, 256] = _build_escape_table()


# --- Raw-pointer UTF-8 encoder ---


@always_inline("nodebug")
def _encode_utf8_ptr(
    code_point: UInt32,
    write_ptr: UnsafePointer[mut=True, UInt8, _],
    write_pos: Int,
) -> Int:
    """Encode a Unicode code point as UTF-8 via raw pointer. Returns new write_pos."""
    if code_point <= 0x7F:
        write_ptr[write_pos] = UInt8(code_point)
        return write_pos + 1
    elif code_point <= 0x7FF:
        write_ptr[write_pos] = UInt8(0xC0 | (code_point >> 6))
        write_ptr[write_pos + 1] = UInt8(0x80 | (code_point & 0x3F))
        return write_pos + 2
    elif code_point <= 0xFFFF:
        write_ptr[write_pos] = UInt8(0xE0 | (code_point >> 12))
        write_ptr[write_pos + 1] = UInt8(0x80 | ((code_point >> 6) & 0x3F))
        write_ptr[write_pos + 2] = UInt8(0x80 | (code_point & 0x3F))
        return write_pos + 3
    else:
        write_ptr[write_pos] = UInt8(0xF0 | (code_point >> 18))
        write_ptr[write_pos + 1] = UInt8(0x80 | ((code_point >> 12) & 0x3F))
        write_ptr[write_pos + 2] = UInt8(0x80 | ((code_point >> 6) & 0x3F))
        write_ptr[write_pos + 3] = UInt8(0x80 | (code_point & 0x3F))
        return write_pos + 4


# --- Raw-pointer unicode escape parser ---


def _parse_unicode_escape_ptr(
    ptr: UnsafePointer[UInt8, _],
    backslash_pos: Int,
    input_len: Int,
    write_ptr: UnsafePointer[mut=True, UInt8, _],
    write_pos: Int,
) raises ParseError -> Tuple[Int, Int]:
    """Parse \\uXXXX (and surrogate pairs) starting at backslash_pos.

    Returns (new_input_pos, new_write_pos).
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
            raise ParseError(
                code=ErrorCode.STRING_ERROR.value, position=backslash_pos
            )
        var low = _parse_hex4(ptr, new_pos + 2, input_len)
        if low < 0xDC00 or low > 0xDFFF:
            raise ParseError(code=ErrorCode.STRING_ERROR.value, position=new_pos)
        code_point = 0x10000 + (code_point - 0xD800) * 0x400 + (low - 0xDC00)
        new_pos += 6
    elif code_point >= 0xDC00 and code_point <= 0xDFFF:
        raise ParseError(
            code=ErrorCode.STRING_ERROR.value, position=backslash_pos
        )

    var new_write_pos = _encode_utf8_ptr(code_point, write_ptr, write_pos)
    return (new_pos, new_write_pos)


# --- Main string parser ---


def parse_string(
    input_ptr: UnsafePointer[UInt8, _],
    pos: Int,
    input_len: Int,
    string_buf_ptr: UnsafePointer[mut=True, UInt8, _],
    buf_start: Int,
) raises ParseError -> Tuple[Int, Int]:
    """Parse a JSON string starting at input_ptr[pos] (opening quote).

    Writes to string_buf_ptr at offset buf_start: [UInt32 length (LE)][UTF-8 bytes][0x00].
    Returns: (bytes_consumed, new_buf_end) where new_buf_end is the next free position.

    string_buf must have capacity >= input_len + 64 (guaranteed by Tape pre-allocation).
    Uses unconditional 32-byte SIMD stores (copy first, check after) with a
    256-byte escape LUT for branchless dispatch.
    """
    var write_ptr = string_buf_ptr
    var write_pos = buf_start + 4  # skip 4-byte length prefix

    var i = pos + 1  # skip opening quote

    comptime QUOTE = UInt8(0x22)
    comptime BACKSLASH = UInt8(0x5C)

    var quote_splat = SIMD[DType.uint8, 32](QUOTE)
    var bs_splat = SIMD[DType.uint8, 32](BACKSLASH)

    while i < input_len:
        # --- SIMD scan: load 32 bytes ---
        var chunk = (input_ptr + i).load[width=32]()

        # Unconditional 32-byte store (copy first, check after)
        memcpy(dest=write_ptr + write_pos, src=input_ptr + i, count=32)

        # Only 2 comparisons: quote and backslash
        var quote_mask = pack_bits[DType.uint32](chunk.eq(quote_splat))
        var bs_mask = pack_bits[DType.uint32](chunk.eq(bs_splat))
        var special_mask = quote_mask | bs_mask

        if special_mask == 0:
            # No quotes or backslashes — all 32 bytes already copied.
            # Deferred ctrl check: scan this INPUT chunk for control chars.
            var ctrl_mask = pack_bits[DType.uint32](
                chunk.le(SIMD[DType.uint8, 32](UInt8(0x1F)))
            )
            if ctrl_mask != 0:
                raise ParseError(
                    code=ErrorCode.STRING_ERROR.value,
                    position=i + Int(count_trailing_zeros(ctrl_mask)),
                )
            write_pos += 32
            i += 32
            continue

        # Find first special character
        var first_special = Int(count_trailing_zeros(special_mask))

        # Check for control chars in the prefix bytes before the special char
        if first_special > 0:
            var ctrl_mask = pack_bits[DType.uint32](
                chunk.le(SIMD[DType.uint8, 32](UInt8(0x1F)))
            )
            # Mask to only consider positions before first_special
            var prefix_mask = (UInt32(1) << UInt32(first_special)) - 1
            var prefix_ctrl = ctrl_mask & prefix_mask
            if prefix_ctrl != 0:
                raise ParseError(
                    code=ErrorCode.STRING_ERROR.value,
                    position=i + Int(count_trailing_zeros(prefix_ctrl)),
                )

        # Advance write_pos to include only bytes before the special char
        # (the unconditional store already wrote them; we just adjust the cursor)
        write_pos += first_special
        i += first_special

        # Handle the special character
        var b = input_ptr[i]
        if b == QUOTE:
            # Closing quote found — finalize string
            write_ptr[write_pos] = UInt8(0)  # null terminator
            var str_len = UInt32(write_pos - buf_start - 4)
            write_ptr[buf_start] = UInt8(str_len & 0xFF)
            write_ptr[buf_start + 1] = UInt8((str_len >> 8) & 0xFF)
            write_ptr[buf_start + 2] = UInt8((str_len >> 16) & 0xFF)
            write_ptr[buf_start + 3] = UInt8((str_len >> 24) & 0xFF)
            return (i - pos + 1, write_pos + 1)

        elif b == BACKSLASH:
            # Escape dispatch via LUT
            if i + 1 >= input_len:
                raise ParseError(
                    code=ErrorCode.UNCLOSED_STRING.value, position=i
                )
            var escaped = input_ptr[i + 1]
            var replacement = _ESCAPE_LUT[Int(escaped)]

            if replacement == UInt8(0xFE):
                # Unicode escape: \uXXXX (possibly surrogate pair)
                var result = _parse_unicode_escape_ptr(
                    input_ptr, i, input_len, write_ptr, write_pos
                )
                i = result[0]
                write_pos = result[1]
            elif replacement != UInt8(0):
                # Simple escape: single replacement byte
                write_ptr[write_pos] = replacement
                write_pos += 1
                i += 2
            else:
                # Invalid escape character
                raise ParseError(
                    code=ErrorCode.STRING_ERROR.value, position=i
                )
        else:
            # Should not reach here
            raise ParseError(code=ErrorCode.STRING_ERROR.value, position=i)

    raise ParseError(code=ErrorCode.UNCLOSED_STRING.value, position=pos)


# --- Hex digit parser ---


def _parse_hex4(
    ptr: UnsafePointer[UInt8, _], start: Int, input_len: Int
) raises ParseError -> UInt32:
    """Parse 4 hex digits starting at ptr[start] into a UInt32."""
    if start + 4 > input_len:
        raise ParseError(code=ErrorCode.STRING_ERROR.value, position=start)
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
            raise ParseError(code=ErrorCode.STRING_ERROR.value, position=start + i)
        value = (value << 4) | digit
    return value
