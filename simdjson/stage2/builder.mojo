"""Stage 2 tape builder: walks structural positions and produces a complete tape.

Combines containers (objects/arrays), literals (true/false/null), strings, and
numbers into a flat tape format with root envelope.
"""

from simdjson.tape import Tape, make_tape_entry, TAG_ROOT, TAG_OBJECT_OPEN, TAG_OBJECT_CLOSE, TAG_ARRAY_OPEN, TAG_ARRAY_CLOSE, TAG_STRING, TAG_INT64, TAG_UINT64, TAG_FLOAT64, TAG_TRUE, TAG_FALSE, TAG_NULL
from simdjson.stage2.numbers import parse_number
from simdjson.stage2.pow5_table import Pow5Cache
from simdjson.stage2.strings import parse_string

comptime MAX_DEPTH: Int = 1024


def build_tape(
    input_buf: List[UInt8], input_len: Int, structural_positions: List[UInt32]
) raises -> Tape:
    """Stage 2 entry point: build a tape from structural positions and input bytes.

    Args:
        input_buf: Padded input buffer (may be longer than the real input).
        input_len: Real (unpadded) length of the JSON input.
        structural_positions: Structural character positions from Stage 1.
    """
    var num_structurals = len(structural_positions)
    if num_structurals == 0:
        raise "EMPTY_DOCUMENT: no structural characters found"

    # R4: Pre-allocate tape and string_buf to avoid reallocation during parsing
    var tape = Tape(element_capacity=input_len * 2 + 2, string_capacity=input_len + 64)
    var pow5_cache = Pow5Cache()
    var input_ptr = input_buf.unsafe_ptr()

    # Root open placeholder at tape[0]
    tape.append(TAG_ROOT, UInt64(0))

    var container_stack = InlineArray[UInt32, MAX_DEPTH](fill=UInt32(0))
    var count_stack = InlineArray[UInt32, MAX_DEPTH](fill=UInt32(0))
    var depth = 0
    var root_done = False

    var si = 0
    while si < num_structurals:
        # Safety: si < num_structurals guaranteed by while loop guard
        var pos = Int(structural_positions.unsafe_get(si))
        var byte = input_ptr[pos]

        if root_done and depth == 0:
            raise "TRAILING_CONTENT: unexpected content at position " + String(pos)

        if byte == TAG_STRING:  # '"'
            var buf_offset = UInt64(len(tape.string_buf))
            var consumed = parse_string(input_ptr, pos, input_len, tape.string_buf)
            tape.append(TAG_STRING, buf_offset)
            if depth == 0:
                root_done = True
            si += 1
            # Skip structural positions within the consumed string (closing quote)
            var string_end = pos + consumed - 1
            # Safety: si < num_structurals guaranteed by while loop guard
            while si < num_structurals and Int(structural_positions.unsafe_get(si)) <= string_end:
                si += 1
        elif byte == UInt8(0x2C):  # ','
            if depth > 0:
                count_stack[depth - 1] += 1
            si += 1
        elif byte == UInt8(0x3A):  # ':'
            si += 1
        elif byte == UInt8(0x2D) or (byte >= UInt8(0x30) and byte <= UInt8(0x39)):
            var result = parse_number(input_ptr + pos, input_len - pos, pow5_cache)
            tape.append(result.tag, UInt64(0))
            tape.append_raw(result.value)
            if depth == 0:
                root_done = True
            si += 1
        elif byte == TAG_OBJECT_OPEN:  # '{'
            if depth >= MAX_DEPTH:
                raise "DEPTH_EXCEEDED: nesting depth exceeds " + String(MAX_DEPTH)
            container_stack[depth] = UInt32(len(tape.elements))
            count_stack[depth] = UInt32(0)
            tape.append(TAG_OBJECT_OPEN, UInt64(0))
            depth += 1
            si += 1
        elif byte == TAG_ARRAY_OPEN:  # '['
            if depth >= MAX_DEPTH:
                raise "DEPTH_EXCEEDED: nesting depth exceeds " + String(MAX_DEPTH)
            container_stack[depth] = UInt32(len(tape.elements))
            count_stack[depth] = UInt32(0)
            tape.append(TAG_ARRAY_OPEN, UInt64(0))
            depth += 1
            si += 1
        elif byte == TAG_OBJECT_CLOSE:  # '}'
            if depth == 0 or tape.tag_at(Int(container_stack[depth - 1])) != TAG_OBJECT_OPEN:
                raise "TAPE_ERROR: unexpected '}' at position " + String(pos)
            _close_container(tape, container_stack, count_stack, depth, TAG_OBJECT_CLOSE)
            depth -= 1
            if depth == 0:
                root_done = True
            si += 1
        elif byte == TAG_ARRAY_CLOSE:  # ']'
            if depth == 0 or tape.tag_at(Int(container_stack[depth - 1])) != TAG_ARRAY_OPEN:
                raise "TAPE_ERROR: unexpected ']' at position " + String(pos)
            _close_container(tape, container_stack, count_stack, depth, TAG_ARRAY_CLOSE)
            depth -= 1
            if depth == 0:
                root_done = True
            si += 1
        elif byte == TAG_TRUE:  # 't' (true)
            _validate_true(input_ptr, pos, input_len)
            tape.append(TAG_TRUE, UInt64(0))
            if depth == 0:
                root_done = True
            si += 1
        elif byte == TAG_FALSE:  # 'f' (false)
            _validate_false(input_ptr, pos, input_len)
            tape.append(TAG_FALSE, UInt64(0))
            if depth == 0:
                root_done = True
            si += 1
        elif byte == TAG_NULL:  # 'n' (null)
            _validate_null(input_ptr, pos, input_len)
            tape.append(TAG_NULL, UInt64(0))
            if depth == 0:
                root_done = True
            si += 1
        else:
            raise "UNEXPECTED_VALUE: unexpected byte " + String(Int(byte)) + " at position " + String(pos)

    if depth != 0:
        raise "UNCLOSED_CONTAINER: " + String(depth) + " unclosed container(s)"

    var root_close_idx = len(tape.elements)
    tape.append(TAG_ROOT, UInt64(0))
    tape.elements[0] = make_tape_entry(TAG_ROOT, UInt64(root_close_idx))

    return tape^


@always_inline("nodebug")
def _close_container(
    mut tape: Tape,
    container_stack: InlineArray[UInt32, MAX_DEPTH],
    count_stack: InlineArray[UInt32, MAX_DEPTH],
    depth: Int,
    close_tag: UInt8,
):
    # depth is current depth BEFORE decrement; container was opened at depth-1
    var open_idx = Int(container_stack[depth - 1])
    var comma_count = count_stack[depth - 1]
    var close_idx = len(tape.elements)
    var open_tag = tape.tag_at(open_idx)

    var is_empty = (close_idx == open_idx + 1)
    var count = UInt64(comma_count)
    if not is_empty:
        count += 1
    if count > 0xFFFFFF:
        count = 0xFFFFFF

    tape.append(close_tag, UInt64(open_idx))
    tape.elements[open_idx] = make_tape_entry(
        open_tag, (count << 32) | UInt64(close_idx + 1)
    )


@always_inline("nodebug")
def _validate_true(
    ptr: UnsafePointer[UInt8, _], pos: Int, input_len: Int
) raises:
    if pos + 4 > input_len:
        raise "INVALID_LITERAL: unexpected end of input at position " + String(pos)
    if ptr[pos] != UInt8(0x74) or ptr[pos + 1] != UInt8(0x72) or ptr[pos + 2] != UInt8(0x75) or ptr[pos + 3] != UInt8(0x65):
        raise "INVALID_LITERAL: expected 'true' at position " + String(pos)


@always_inline("nodebug")
def _validate_false(
    ptr: UnsafePointer[UInt8, _], pos: Int, input_len: Int
) raises:
    if pos + 5 > input_len:
        raise "INVALID_LITERAL: unexpected end of input at position " + String(pos)
    if ptr[pos] != UInt8(0x66) or ptr[pos + 1] != UInt8(0x61) or ptr[pos + 2] != UInt8(0x6C) or ptr[pos + 3] != UInt8(0x73) or ptr[pos + 4] != UInt8(0x65):
        raise "INVALID_LITERAL: expected 'false' at position " + String(pos)


@always_inline("nodebug")
def _validate_null(
    ptr: UnsafePointer[UInt8, _], pos: Int, input_len: Int
) raises:
    if pos + 4 > input_len:
        raise "INVALID_LITERAL: unexpected end of input at position " + String(pos)
    if ptr[pos] != UInt8(0x6E) or ptr[pos + 1] != UInt8(0x75) or ptr[pos + 2] != UInt8(0x6C) or ptr[pos + 3] != UInt8(0x6C):
        raise "INVALID_LITERAL: expected 'null' at position " + String(pos)
