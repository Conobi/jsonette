"""Tape-free JSON decoder: Stage 1 structural index straight into user structs.

Skips Stage 2 (tape construction) entirely. Instead of the DOM path
  JSON -> tape -> Value -> struct
this module walks the Stage 1 structural positions directly:
  JSON -> structural index -> hash-dispatch field walk -> struct fields

Key mechanisms:
  - Compile-time reflection over T's fields, each hashed at compile time.
  - Runtime key bytes hashed as StringSlice; compared against comptime hashes.
  - Byte-level collision guard after hash match (comptime-unrolled comparison).
  - Leaf values parsed in-place from input bytes (_parse_number, parse_string,
    _validate_true/false/null).
  - _skip_value from the On-Demand layer to skip unrecognised or nested values.
"""
from std.reflection import reflect
from std.builtin.rebind import trait_downcast, rebind_var
from std.memory import bitcast

from jsonette.parser import Parser
from jsonette.stage2.strings import parse_string, _raw_string_span, span_is_clean
from jsonette.stage2.numbers import _parse_number, _scalar_token_ok
from jsonette.stage2.builder import _validate_true, _validate_false
from jsonette.tape import TAG_INT64, TAG_UINT64, TAG_FLOAT64
from jsonette.ondemand.ondemand import _skip_value


comptime _Base = Movable & ImplicitlyDestructible
comptime _Struct = Defaultable & Movable & ImplicitlyDestructible

comptime _QUOTE = UInt8(0x22)     # '"'
comptime _BACKSLASH = UInt8(0x5C) # '\'
comptime _COLON = UInt8(0x3A)     # ':'
comptime _LBRACE = UInt8(0x7B)    # '{'
comptime _RBRACE = UInt8(0x7D)    # '}'
comptime _COMMA = UInt8(0x2C)     # ','
comptime _LOWER_T = UInt8(0x74)   # 't'
comptime _LOWER_F = UInt8(0x66)   # 'f'


def _decode_string(
    ip: UnsafePointer[UInt8, _],
    positions: List[UInt32],
    si: Int,
    input_len: Int,
    mut scratch: List[UInt8],
) raises -> String:
    """Parse a JSON string value at structural index `si` and return it as a String.

    First checks if the string content is escape-free (no backslash, no control
    bytes). If so, constructs a String directly from the raw input span (fast path).
    Otherwise, falls back to the full parse_string with SIMD unescape.

    Args:
        ip: Pointer to padded input buffer.
        positions: Structural character positions from Stage 1.
        si: Structural index of the opening quote.
        input_len: Length of the input buffer.
        scratch: Reusable scratch buffer for parse_string.

    Returns:
        The parsed string value.
    """
    var content = _raw_string_span(positions, si, ip)
    var content_ptr = content[0]
    var content_len = content[1]

    # Fast path: no escapes needed — construct String from raw input span
    if span_is_clean(content_ptr, content_len):
        return String(StringSlice(unsafe_from_utf8=Span[UInt8](
            ptr=content_ptr, length=content_len
        )))

    # Slow path: parse_string with escape handling
    var pos = Int(positions.unsafe_get(si))
    var needed = input_len + 64
    if len(scratch) < needed:
        scratch = List[UInt8](unsafe_uninit_length=needed)
    _ = parse_string(ip, pos, input_len, scratch.unsafe_ptr(), 0)

    # parse_string writes [u32 len LE][content bytes][NUL] at buf_start=0
    var sp = scratch.unsafe_ptr()
    var str_len = Int(
        UInt32(sp[0])
        | (UInt32(sp[1]) << 8)
        | (UInt32(sp[2]) << 16)
        | (UInt32(sp[3]) << 24)
    )
    return String(StringSlice(unsafe_from_utf8=Span[UInt8](
        ptr=sp + 4, length=str_len
    )))


def _decode_leaf[T: _Base](
    ip: UnsafePointer[UInt8, _],
    positions: List[UInt32],
    si: Int,
    input_len: Int,
    mut scratch: List[UInt8],
    out result: T,
) raises:
    """Decode a JSON leaf value at structural index `si` into type T.

    Dispatches at compile time based on the type name:
      - String: parse JSON string from structural positions
      - Bool: validate true/false literal
      - Float64/Float32: parse number, extract float bits
      - Int/Int64/Int32/Int16/Int8: parse number, extract signed integer
      - UInt64/UInt32/UInt16/UInt8: parse number, extract unsigned integer

    Args:
        ip: Pointer to padded input buffer.
        positions: Structural character positions from Stage 1.
        si: Structural index of the value.
        input_len: Length of the input buffer.
        scratch: Reusable scratch buffer for string parsing.

    Returns:
        The decoded value of type T.
    """
    var pos = Int(positions.unsafe_get(si))
    var b = ip[pos]

    comptime tn = reflect[T].name()

    comptime if tn == "String":
        if b != _QUOTE:
            raise "DECODE: expected string at position " + String(pos)
        result = rebind_var[T](_decode_string(ip, positions, si, input_len, scratch))

    elif tn == "Bool":
        if b == _LOWER_T:
            _validate_true(ip, pos, input_len)
            if not _scalar_token_ok(ip, pos, 4, input_len):
                raise "DECODE: trailing characters after 'true' at position " + String(pos)
            result = rebind_var[T](True)
        elif b == _LOWER_F:
            _validate_false(ip, pos, input_len)
            if not _scalar_token_ok(ip, pos, 5, input_len):
                raise "DECODE: trailing characters after 'false' at position " + String(pos)
            result = rebind_var[T](False)
        else:
            raise "DECODE: expected bool at position " + String(pos)

    elif tn == "SIMD[DType.float64, 1]":
        var nr = _parse_number(ip + pos, input_len - pos)
        if not _scalar_token_ok(ip, pos, nr.bytes_consumed, input_len):
            raise "DECODE: invalid number at position " + String(pos)
        if nr.tag == TAG_FLOAT64:
            result = rebind_var[T](bitcast[DType.float64](nr.value))
        elif nr.tag == TAG_INT64:
            result = rebind_var[T](Float64(bitcast[DType.int64](nr.value)))
        else:
            result = rebind_var[T](Float64(nr.value))

    elif tn == "SIMD[DType.float32, 1]":
        var nr = _parse_number(ip + pos, input_len - pos)
        if not _scalar_token_ok(ip, pos, nr.bytes_consumed, input_len):
            raise "DECODE: invalid number at position " + String(pos)
        var d: Float64
        if nr.tag == TAG_FLOAT64:
            d = bitcast[DType.float64](nr.value)
        elif nr.tag == TAG_INT64:
            d = Float64(bitcast[DType.int64](nr.value))
        else:
            d = Float64(nr.value)
        comptime F32_MAX = Float64(3.4028234663852886e38)
        if d > F32_MAX or d < -F32_MAX:
            raise "DECODE: float overflow for Float32 at position " + String(pos)
        result = rebind_var[T](Float32(d))

    elif tn == "Int":
        var nr = _parse_number(ip + pos, input_len - pos)
        if not _scalar_token_ok(ip, pos, nr.bytes_consumed, input_len):
            raise "DECODE: invalid number at position " + String(pos)
        if nr.tag == TAG_INT64:
            result = rebind_var[T](Int(bitcast[DType.int64](nr.value)))
        elif nr.tag == TAG_UINT64:
            if nr.value > UInt64(Int64.MAX):
                raise "DECODE: integer out of Int range at position " + String(pos)
            result = rebind_var[T](Int(nr.value))
        else:
            raise "DECODE: expected integer at position " + String(pos)

    elif tn == "SIMD[DType.int64, 1]":
        var nr = _parse_number(ip + pos, input_len - pos)
        if not _scalar_token_ok(ip, pos, nr.bytes_consumed, input_len):
            raise "DECODE: invalid number at position " + String(pos)
        if nr.tag == TAG_INT64:
            result = rebind_var[T](bitcast[DType.int64](nr.value))
        elif nr.tag == TAG_UINT64:
            if nr.value > UInt64(Int64.MAX):
                raise "DECODE: integer overflow at position " + String(pos)
            result = rebind_var[T](Int64(nr.value))
        else:
            raise "DECODE: expected integer at position " + String(pos)

    elif tn == "SIMD[DType.int32, 1]":
        var nr = _parse_number(ip + pos, input_len - pos)
        if not _scalar_token_ok(ip, pos, nr.bytes_consumed, input_len):
            raise "DECODE: invalid number at position " + String(pos)
        if nr.tag != TAG_INT64 and nr.tag != TAG_UINT64:
            raise "DECODE: expected integer for Int32 at position " + String(pos)
        if nr.tag == TAG_UINT64 and nr.value > UInt64(Int32.MAX):
            raise "DECODE: integer overflow at position " + String(pos)
        var v = bitcast[DType.int64](nr.value)
        if v < Int64(Int32.MIN) or v > Int64(Int32.MAX):
            raise "DECODE: integer overflow at position " + String(pos)
        result = rebind_var[T](Int32(v))

    elif tn == "SIMD[DType.int16, 1]":
        var nr = _parse_number(ip + pos, input_len - pos)
        if not _scalar_token_ok(ip, pos, nr.bytes_consumed, input_len):
            raise "DECODE: invalid number at position " + String(pos)
        if nr.tag != TAG_INT64 and nr.tag != TAG_UINT64:
            raise "DECODE: expected integer for Int16 at position " + String(pos)
        if nr.tag == TAG_UINT64 and nr.value > 32767:
            raise "DECODE: integer overflow at position " + String(pos)
        var v = bitcast[DType.int64](nr.value)
        if v < -32768 or v > 32767:
            raise "DECODE: integer overflow at position " + String(pos)
        result = rebind_var[T](Int16(v))

    elif tn == "SIMD[DType.int8, 1]":
        var nr = _parse_number(ip + pos, input_len - pos)
        if not _scalar_token_ok(ip, pos, nr.bytes_consumed, input_len):
            raise "DECODE: invalid number at position " + String(pos)
        if nr.tag != TAG_INT64 and nr.tag != TAG_UINT64:
            raise "DECODE: expected integer for Int8 at position " + String(pos)
        if nr.tag == TAG_UINT64 and nr.value > 127:
            raise "DECODE: integer overflow at position " + String(pos)
        var v = bitcast[DType.int64](nr.value)
        if v < -128 or v > 127:
            raise "DECODE: integer overflow at position " + String(pos)
        result = rebind_var[T](Int8(v))

    elif tn == "SIMD[DType.uint64, 1]":
        var nr = _parse_number(ip + pos, input_len - pos)
        if not _scalar_token_ok(ip, pos, nr.bytes_consumed, input_len):
            raise "DECODE: invalid number at position " + String(pos)
        if nr.tag == TAG_UINT64:
            result = rebind_var[T](nr.value)
        elif nr.tag == TAG_INT64:
            var sv = bitcast[DType.int64](nr.value)
            if sv < 0:
                raise "DECODE: unsigned underflow at position " + String(pos)
            result = rebind_var[T](UInt64(sv))
        else:
            raise "DECODE: expected unsigned integer at position " + String(pos)

    elif tn == "SIMD[DType.uint32, 1]":
        var nr = _parse_number(ip + pos, input_len - pos)
        if not _scalar_token_ok(ip, pos, nr.bytes_consumed, input_len):
            raise "DECODE: invalid number at position " + String(pos)
        if nr.tag != TAG_INT64 and nr.tag != TAG_UINT64:
            raise "DECODE: expected integer for UInt32 at position " + String(pos)
        if nr.tag == TAG_INT64 and bitcast[DType.int64](nr.value) < 0:
            raise "DECODE: negative integer for UInt32 at position " + String(pos)
        var uval = nr.value if nr.tag == TAG_UINT64 else UInt64(bitcast[DType.int64](nr.value))
        if uval > UInt64(UInt32.MAX):
            raise "DECODE: unsigned overflow at position " + String(pos)
        result = rebind_var[T](UInt32(uval))

    elif tn == "SIMD[DType.uint16, 1]":
        var nr = _parse_number(ip + pos, input_len - pos)
        if not _scalar_token_ok(ip, pos, nr.bytes_consumed, input_len):
            raise "DECODE: invalid number at position " + String(pos)
        if nr.tag != TAG_INT64 and nr.tag != TAG_UINT64:
            raise "DECODE: expected integer for UInt16 at position " + String(pos)
        if nr.tag == TAG_INT64 and bitcast[DType.int64](nr.value) < 0:
            raise "DECODE: negative integer for UInt16 at position " + String(pos)
        var uval = nr.value if nr.tag == TAG_UINT64 else UInt64(bitcast[DType.int64](nr.value))
        if uval > 65535:
            raise "DECODE: unsigned overflow at position " + String(pos)
        result = rebind_var[T](UInt16(uval))

    elif tn == "SIMD[DType.uint8, 1]":
        var nr = _parse_number(ip + pos, input_len - pos)
        if not _scalar_token_ok(ip, pos, nr.bytes_consumed, input_len):
            raise "DECODE: invalid number at position " + String(pos)
        if nr.tag != TAG_INT64 and nr.tag != TAG_UINT64:
            raise "DECODE: expected integer for UInt8 at position " + String(pos)
        if nr.tag == TAG_INT64 and bitcast[DType.int64](nr.value) < 0:
            raise "DECODE: negative integer for UInt8 at position " + String(pos)
        var uval = nr.value if nr.tag == TAG_UINT64 else UInt64(bitcast[DType.int64](nr.value))
        if uval > 255:
            raise "DECODE: unsigned overflow at position " + String(pos)
        result = rebind_var[T](UInt8(uval))

    else:
        comptime assert False, "decode_direct: unsupported leaf type '" + tn + "'"


def _decode_object[T: _Struct](
    positions: List[UInt32],
    ip: UnsafePointer[UInt8, _],
    input_len: Int,
    root_pos: Int,
    mut scratch: List[UInt8],
    out s: T,
) raises:
    """Walk a JSON object's structural positions and fill struct T by hash dispatch.

    For each key in the JSON object:
      1. Hash the raw key bytes as StringSlice.
      2. Compare against compile-time hashes of T's field names.
      3. On match, byte-verify the key content (collision guard).
      4. Parse the value directly into the matched field.
      5. On no match or mismatch, skip the value via _skip_value.

    After the walk, check that all required fields were found. Absent fields
    raise MISSING_FIELD.

    Args:
        positions: Structural character positions from Stage 1.
        ip: Pointer to padded input buffer.
        input_len: Length of the input buffer.
        root_pos: Byte position of the opening '{'.
        scratch: Reusable scratch buffer for string parsing.

    Returns:
        A freshly constructed T with all fields populated from the JSON.
    """
    if ip[root_pos] != _LBRACE:
        raise "DECODE: expected '{' at position " + String(root_pos)

    s = type_of(s)()
    comptime r = reflect[T]
    comptime fc = r.field_count()
    comptime names = r.field_names()

    # Track which fields have been found
    var found = List[Bool]()
    for _ in range(fc):
        found.append(False)

    var n = len(positions)

    # Find the structural index of the opening brace
    # We need to find which si corresponds to root_pos
    var si = 0
    while si < n and Int(positions[si]) != root_pos:
        si += 1
    if si >= n:
        raise "DECODE: opening '{' not found in structural positions"

    si += 1  # move past '{'

    # Walk key-value pairs
    var closed = False
    while si < n:
        var cur_byte = ip[Int(positions[si])]

        # End of object
        if cur_byte == _RBRACE:
            closed = True
            break

        # Skip comma between members
        if cur_byte == _COMMA:
            si += 1
            if si >= n:
                raise "DECODE: truncated object after comma"
            cur_byte = ip[Int(positions[si])]

        # Expect a key (opening quote)
        if cur_byte != _QUOTE:
            raise "DECODE: expected string key at position " + String(Int(positions[si]))

        # Guard: _raw_string_span needs positions[si+1] (closing quote)
        if si + 1 >= n:
            raise "DECODE: truncated key (no closing quote) at position " + String(Int(positions[si]))

        # Extract key span: positions[si] is opening quote, positions[si+1] is closing quote
        var key_content = _raw_string_span(positions, si, ip)
        var key_ptr = key_content[0]
        var key_len = key_content[1]

        # Check for escaped keys (scan for backslash)
        var has_escape = False
        for k in range(key_len):
            if key_ptr[k] == _BACKSLASH:
                has_escape = True
                break

        # Hash the key — escaped keys must be unescaped first
        var key_hash: UInt64
        var decoded_key = String("")
        if has_escape:
            var kpos = Int(positions[si])
            var needed = input_len + 64
            if len(scratch) < needed:
                scratch = List[UInt8](unsafe_uninit_length=needed)
            _ = parse_string(ip, kpos, input_len, scratch.unsafe_ptr(), 0)
            var sp = scratch.unsafe_ptr()
            var ln = Int(
                UInt32(sp[0])
                | (UInt32(sp[1]) << 8)
                | (UInt32(sp[2]) << 16)
                | (UInt32(sp[3]) << 24)
            )
            decoded_key = String(StringSlice(unsafe_from_utf8=Span[UInt8](ptr=sp + 4, length=ln)))
            key_hash = hash(decoded_key)
        else:
            var key_span = Span[UInt8](ptr=key_ptr, length=key_len)
            key_hash = hash(StringSlice(unsafe_from_utf8=key_span))

        # Move past key (opening quote + closing quote)
        si += 2

        # Expect colon — the colon is the next structural
        if si >= n or ip[Int(positions[si])] != _COLON:
            raise "DECODE: expected ':' after key at position " + String(Int(positions[si - 1]))
        si += 1  # move past colon

        # si now points to the value
        if si >= n:
            raise "DECODE: truncated object — no value after colon"

        # Hash-dispatch: compare against comptime field hashes
        var matched = False
        comptime for i in range(fc):
            comptime key = String(names[i])
            comptime field_hash = hash(key)
            if not matched and key_hash == field_hash:
                # Collision guard: verify key content matches field name
                var key_match: Bool
                if has_escape:
                    key_match = decoded_key == key
                else:
                    comptime expected_len = key.byte_length()
                    if key_len == expected_len:
                        key_match = True
                        comptime key_bytes = key.as_bytes()
                        comptime for j in range(expected_len):
                            comptime expected_byte = key_bytes[j]
                            if key_ptr[j] != expected_byte:
                                key_match = False
                    else:
                        key_match = False
                if key_match:
                        # Match! Parse value into field
                        ref field = trait_downcast[_Base](r.field_ref[i](s))
                        field = _decode_leaf[type_of(field)](
                            ip, positions, si, input_len, scratch
                        )
                        found[i] = True
                        matched = True

        # Skip value (advance si past it regardless of match)
        si = _skip_value(ip, positions, n, si)

    if not closed:
        raise "DECODE: unclosed object (no matching '}')"

    # Check all required fields were found
    comptime for i in range(fc):
        comptime key = String(names[i])
        if not found[i]:
            raise "MISSING_FIELD: '" + key + "'"


def decode_direct[T: _Struct](data: String, out s: T) raises:
    """Decode JSON data directly into struct T, skipping tape construction.

    Runs Stage 1 (structural indexing) only, then walks the structural
    positions with compile-time hash dispatch to parse leaf values directly
    into the struct's fields. No tape is built, no DOM Value is created.

    This is the tape-free alternative to decode[T], trading generality
    (flat structs with leaf fields only) for speed (fewer allocations,
    fewer indirections, no tape materialisation).

    Args:
        data: JSON string to decode.

    Returns:
        A freshly constructed T with all fields populated from the JSON.
    """
    var parser = Parser()
    var b = data.as_bytes()
    parser._build_index(b)

    var scratch = List[UInt8]()

    # The first structural position is the root value
    if len(parser.positions) == 0:
        raise "DECODE: empty document"

    var root_byte_pos = Int(parser.positions[0])

    s = _decode_object[T](
        parser.positions,
        parser.get_input_ptr(),
        len(b),
        root_byte_pos,
        scratch,
    )
