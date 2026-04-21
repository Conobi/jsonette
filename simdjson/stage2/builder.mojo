"""Stage 2 tape builder: walks structural positions and produces a complete tape.

Combines containers (objects/arrays), literals (true/false/null), strings, and
numbers into a flat tape format with root envelope.
"""

from simdjson.tape import Tape, make_tape_entry, TAG_ROOT, TAG_OBJECT_OPEN, TAG_OBJECT_CLOSE, TAG_ARRAY_OPEN, TAG_ARRAY_CLOSE, TAG_STRING, TAG_INT64, TAG_UINT64, TAG_FLOAT64, TAG_TRUE, TAG_FALSE, TAG_NULL
from simdjson.error import ParseError, ErrorCode
from simdjson.stage2.numbers import parse_number
from simdjson.stage2.strings import parse_string

comptime MAX_DEPTH: Int = 1024


def build_tape(
    input_buf: List[UInt8], input_len: Int, structural_positions: List[UInt32]
) raises ParseError -> Tape:
    """Stage 2 entry point: build a tape from structural positions and input bytes.

    Args:
        input_buf: Padded input buffer (must have >= 128 zero bytes after input_len
            for safe SIMD overread in parse_string and parse_number).
        input_len: Real (unpadded) length of the JSON input.
        structural_positions: Structural character positions from Stage 1.
    """
    var num_structurals = len(structural_positions)
    if num_structurals == 0:
        raise ParseError(code=ErrorCode.EMPTY_DOCUMENT.value, position=0)

    # R4: Pre-allocate tape (unsafe_uninit_length — no zeroing, raw pointer writes fill before read)
    var tape = Tape(element_capacity=input_len * 2 + 2, string_capacity=input_len + 64)
    var tape_ptr = tape.elements.unsafe_ptr()
    var tape_pos = 0
    var input_ptr = input_buf.unsafe_ptr()

    # Root open placeholder at tape[0]
    tape_ptr[tape_pos] = make_tape_entry(TAG_ROOT, UInt64(0))
    tape_pos += 1

    var container_stack = InlineArray[UInt32, MAX_DEPTH](uninitialized=True)
    var count_stack = InlineArray[UInt32, MAX_DEPTH](uninitialized=True)
    var depth = 0
    var root_done = False

    var si = 0
    while si < num_structurals:
        # Safety: si < num_structurals guaranteed by while loop guard
        var pos = Int(structural_positions.unsafe_get(si))
        var byte = input_ptr[pos]

        if root_done and depth == 0:
            raise ParseError(code=ErrorCode.TRAILING_CONTENT.value, position=pos)

        if byte == TAG_STRING:  # '"'
            var buf_offset = UInt64(len(tape.string_buf))
            var consumed = parse_string(input_ptr, pos, input_len, tape.string_buf)
            tape_ptr[tape_pos] = make_tape_entry(TAG_STRING, buf_offset)
            tape_pos += 1
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
            var result = parse_number(input_ptr + pos, input_len - pos)
            tape_ptr[tape_pos] = make_tape_entry(result.tag, UInt64(0))
            tape_pos += 1
            tape_ptr[tape_pos] = result.value
            tape_pos += 1
            if depth == 0:
                root_done = True
            si += 1
        elif byte == TAG_OBJECT_OPEN:  # '{'
            if depth >= MAX_DEPTH:
                raise ParseError(code=ErrorCode.DEPTH_EXCEEDED.value, position=pos)
            container_stack[depth] = UInt32(tape_pos)
            count_stack[depth] = UInt32(0)
            tape_ptr[tape_pos] = make_tape_entry(TAG_OBJECT_OPEN, UInt64(0))
            tape_pos += 1
            depth += 1
            si += 1
        elif byte == TAG_ARRAY_OPEN:  # '['
            if depth >= MAX_DEPTH:
                raise ParseError(code=ErrorCode.DEPTH_EXCEEDED.value, position=pos)
            container_stack[depth] = UInt32(tape_pos)
            count_stack[depth] = UInt32(0)
            tape_ptr[tape_pos] = make_tape_entry(TAG_ARRAY_OPEN, UInt64(0))
            tape_pos += 1
            depth += 1
            si += 1
        elif byte == TAG_OBJECT_CLOSE:  # '}'
            if depth == 0 or UInt8(tape_ptr[Int(container_stack[depth - 1])] >> 56) != TAG_OBJECT_OPEN:
                raise ParseError(code=ErrorCode.TAPE_ERROR.value, position=pos)
            tape_pos = _close_container(tape_ptr, tape_pos, container_stack, count_stack, depth, TAG_OBJECT_CLOSE)
            depth -= 1
            if depth == 0:
                root_done = True
            si += 1
        elif byte == TAG_ARRAY_CLOSE:  # ']'
            if depth == 0 or UInt8(tape_ptr[Int(container_stack[depth - 1])] >> 56) != TAG_ARRAY_OPEN:
                raise ParseError(code=ErrorCode.TAPE_ERROR.value, position=pos)
            tape_pos = _close_container(tape_ptr, tape_pos, container_stack, count_stack, depth, TAG_ARRAY_CLOSE)
            depth -= 1
            if depth == 0:
                root_done = True
            si += 1
        elif byte == TAG_TRUE:  # 't' (true)
            _validate_true(input_ptr, pos, input_len)
            tape_ptr[tape_pos] = make_tape_entry(TAG_TRUE, UInt64(0))
            tape_pos += 1
            if depth == 0:
                root_done = True
            si += 1
        elif byte == TAG_FALSE:  # 'f' (false)
            _validate_false(input_ptr, pos, input_len)
            tape_ptr[tape_pos] = make_tape_entry(TAG_FALSE, UInt64(0))
            tape_pos += 1
            if depth == 0:
                root_done = True
            si += 1
        elif byte == TAG_NULL:  # 'n' (null)
            _validate_null(input_ptr, pos, input_len)
            tape_ptr[tape_pos] = make_tape_entry(TAG_NULL, UInt64(0))
            tape_pos += 1
            if depth == 0:
                root_done = True
            si += 1
        else:
            raise ParseError(code=ErrorCode.UNEXPECTED_VALUE.value, position=pos)

    if depth != 0:
        raise ParseError(code=ErrorCode.UNCLOSED_CONTAINER.value, position=0)

    var root_close_idx = tape_pos
    tape_ptr[tape_pos] = make_tape_entry(TAG_ROOT, UInt64(0))
    tape_pos += 1
    tape_ptr[0] = make_tape_entry(TAG_ROOT, UInt64(root_close_idx))

    # Shrink tape to actual size
    tape.elements.resize(tape_pos, UInt64(0))

    return tape^


@always_inline("nodebug")
def _close_container[o: Origin[mut=True]](
    tape_ptr: UnsafePointer[UInt64, origin=o],
    mut tape_pos: Int,
    container_stack: InlineArray[UInt32, MAX_DEPTH],
    count_stack: InlineArray[UInt32, MAX_DEPTH],
    depth: Int,
    close_tag: UInt8,
) -> Int:
    # depth is current depth BEFORE decrement; container was opened at depth-1
    var open_idx = Int(container_stack[depth - 1])
    var comma_count = count_stack[depth - 1]
    var close_idx = tape_pos
    var open_tag = UInt8(tape_ptr[open_idx] >> 56)

    var is_empty = (close_idx == open_idx + 1)
    var count = UInt64(comma_count)
    if not is_empty:
        count += 1
    if count > 0xFFFFFF:
        count = 0xFFFFFF

    tape_ptr[tape_pos] = make_tape_entry(close_tag, UInt64(open_idx))
    tape_pos += 1
    tape_ptr[open_idx] = make_tape_entry(
        open_tag, (count << 32) | UInt64(close_idx + 1)
    )
    return tape_pos


@always_inline("nodebug")
def _validate_true(
    ptr: UnsafePointer[UInt8, _], pos: Int, input_len: Int
) raises ParseError:
    if pos + 4 > input_len:
        raise ParseError(code=ErrorCode.INVALID_LITERAL.value, position=pos)
    if ptr[pos] != UInt8(0x74) or ptr[pos + 1] != UInt8(0x72) or ptr[pos + 2] != UInt8(0x75) or ptr[pos + 3] != UInt8(0x65):
        raise ParseError(code=ErrorCode.INVALID_LITERAL.value, position=pos)


@always_inline("nodebug")
def _validate_false(
    ptr: UnsafePointer[UInt8, _], pos: Int, input_len: Int
) raises ParseError:
    if pos + 5 > input_len:
        raise ParseError(code=ErrorCode.INVALID_LITERAL.value, position=pos)
    if ptr[pos] != UInt8(0x66) or ptr[pos + 1] != UInt8(0x61) or ptr[pos + 2] != UInt8(0x6C) or ptr[pos + 3] != UInt8(0x73) or ptr[pos + 4] != UInt8(0x65):
        raise ParseError(code=ErrorCode.INVALID_LITERAL.value, position=pos)


@always_inline("nodebug")
def _validate_null(
    ptr: UnsafePointer[UInt8, _], pos: Int, input_len: Int
) raises ParseError:
    if pos + 4 > input_len:
        raise ParseError(code=ErrorCode.INVALID_LITERAL.value, position=pos)
    if ptr[pos] != UInt8(0x6E) or ptr[pos + 1] != UInt8(0x75) or ptr[pos + 2] != UInt8(0x6C) or ptr[pos + 3] != UInt8(0x6C):
        raise ParseError(code=ErrorCode.INVALID_LITERAL.value, position=pos)
