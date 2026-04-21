"""Stage 2 tape builder: walks structural positions and produces a complete tape.

Combines containers (objects/arrays), literals (true/false/null), strings, and
numbers into a flat tape format with root envelope.
"""

from simdjson.tape import Tape, make_tape_entry
from simdjson.stage2.numbers import parse_number
from simdjson.stage2.strings import parse_string

comptime MAX_DEPTH: Int = 1024


def build_tape(
    input_buf: List[UInt8], structural_positions: List[UInt32]
) raises -> Tape:
    """Stage 2 entry point: build a tape from structural positions and input bytes."""
    var num_structurals = len(structural_positions)
    if num_structurals == 0:
        raise "EMPTY_DOCUMENT: no structural characters found"

    var tape = Tape()
    var input_ptr = input_buf.unsafe_ptr()
    var input_len = len(input_buf)

    # Root open placeholder at tape[0]
    tape.append(UInt8(0x72), UInt64(0))

    var container_stack = List[UInt32]()
    var count_stack = List[UInt32]()
    var depth = 0
    var root_done = False

    var si = 0
    while si < num_structurals:
        var pos = Int(structural_positions[si])
        var byte = input_ptr[pos]

        if root_done and depth == 0:
            raise "TRAILING_CONTENT: unexpected content at position " + String(pos)

        if byte == UInt8(0x7B):  # '{'
            if depth >= MAX_DEPTH:
                raise "DEPTH_EXCEEDED: nesting depth exceeds " + String(MAX_DEPTH)
            container_stack.append(UInt32(len(tape.elements)))
            count_stack.append(UInt32(0))
            tape.append(UInt8(0x7B), UInt64(0))
            depth += 1
            si += 1
        elif byte == UInt8(0x7D):  # '}'
            if depth == 0 or tape.tag_at(Int(container_stack[len(container_stack) - 1])) != UInt8(0x7B):
                raise "TAPE_ERROR: unexpected '}' at position " + String(pos)
            _close_container(tape, container_stack, count_stack, UInt8(0x7D))
            depth -= 1
            if depth == 0:
                root_done = True
            si += 1
        elif byte == UInt8(0x5B):  # '['
            if depth >= MAX_DEPTH:
                raise "DEPTH_EXCEEDED: nesting depth exceeds " + String(MAX_DEPTH)
            container_stack.append(UInt32(len(tape.elements)))
            count_stack.append(UInt32(0))
            tape.append(UInt8(0x5B), UInt64(0))
            depth += 1
            si += 1
        elif byte == UInt8(0x5D):  # ']'
            if depth == 0 or tape.tag_at(Int(container_stack[len(container_stack) - 1])) != UInt8(0x5B):
                raise "TAPE_ERROR: unexpected ']' at position " + String(pos)
            _close_container(tape, container_stack, count_stack, UInt8(0x5D))
            depth -= 1
            if depth == 0:
                root_done = True
            si += 1
        elif byte == UInt8(0x22):  # '"'
            var buf_offset = UInt64(len(tape.string_buf))
            var consumed = parse_string(input_ptr, pos, input_len, tape.string_buf)
            tape.append(UInt8(0x22), buf_offset)
            if depth == 0:
                root_done = True
            si += 1
            # Skip structural positions within the consumed string (closing quote)
            var string_end = pos + consumed - 1
            while si < num_structurals and Int(structural_positions[si]) <= string_end:
                si += 1
        elif byte == UInt8(0x74):  # 't' (true)
            _validate_literal(input_ptr, pos, input_len, String("true"))
            tape.append(UInt8(0x74), UInt64(0))
            if depth == 0:
                root_done = True
            si += 1
        elif byte == UInt8(0x66):  # 'f' (false)
            _validate_literal(input_ptr, pos, input_len, String("false"))
            tape.append(UInt8(0x66), UInt64(0))
            if depth == 0:
                root_done = True
            si += 1
        elif byte == UInt8(0x6E):  # 'n' (null)
            _validate_literal(input_ptr, pos, input_len, String("null"))
            tape.append(UInt8(0x6E), UInt64(0))
            if depth == 0:
                root_done = True
            si += 1
        elif byte == UInt8(0x2D) or (byte >= UInt8(0x30) and byte <= UInt8(0x39)):
            var result = parse_number(input_ptr + pos, input_len - pos)
            tape.append(result.tag, UInt64(0))
            tape.append_raw(result.value)
            if depth == 0:
                root_done = True
            si += 1
        elif byte == UInt8(0x3A):  # ':'
            si += 1
        elif byte == UInt8(0x2C):  # ','
            if depth > 0:
                count_stack[len(count_stack) - 1] += 1
            si += 1
        else:
            raise "UNEXPECTED_VALUE: unexpected byte " + String(Int(byte)) + " at position " + String(pos)

    if depth != 0:
        raise "UNCLOSED_CONTAINER: " + String(depth) + " unclosed container(s)"

    var root_close_idx = len(tape.elements)
    tape.append(UInt8(0x72), UInt64(0))
    tape.elements[0] = make_tape_entry(UInt8(0x72), UInt64(root_close_idx))

    return tape^


def _close_container(
    mut tape: Tape,
    mut container_stack: List[UInt32],
    mut count_stack: List[UInt32],
    close_tag: UInt8,
):
    var open_idx = Int(container_stack.pop())
    var comma_count = count_stack.pop()
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


def _validate_literal(
    ptr: UnsafePointer[UInt8, _], pos: Int, input_len: Int, expected: String
) raises:
    var expected_bytes = expected.as_bytes()
    if pos + len(expected_bytes) > input_len:
        raise "INVALID_LITERAL: unexpected end of input at position " + String(pos)
    for i in range(len(expected_bytes)):
        if ptr[pos + i] != expected_bytes[i]:
            raise "INVALID_LITERAL: expected '" + expected + "' at position " + String(pos)
