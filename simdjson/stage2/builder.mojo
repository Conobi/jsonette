"""Stage 2 tape builder: walks structural positions and produces a complete tape.

Combines containers (objects/arrays), literals (true/false/null), strings, and
numbers into a flat tape format with root envelope.
"""

from simdjson.tape import Tape, make_tape_entry, TAG_ROOT, TAG_OBJECT_OPEN, TAG_OBJECT_CLOSE, TAG_ARRAY_OPEN, TAG_ARRAY_CLOSE, TAG_STRING, TAG_INT64, TAG_UINT64, TAG_FLOAT64, TAG_TRUE, TAG_FALSE, TAG_NULL
from simdjson.error import ParseError, ErrorCode
from simdjson._alloc_count import record_alloc
from simdjson.stage2.numbers import _parse_number
from simdjson.stage2.strings import parse_string

comptime MAX_DEPTH: Int = 1024


def build_tape(
    input_buf: List[UInt8], input_len: Int, mut structural_positions: List[UInt32],
    mut container_stack: List[UInt32], mut count_stack: List[UInt32],
    mut tape: Tape,
) raises ParseError:
    """Stage 2 entry point: fill a caller-owned tape from structural positions and input bytes.

    The tape is supplied by the caller (the Parser owns it across parses). Its
    backing Lists are grown only when the current input needs more room than a
    prior parse left allocated; a warm tape with sufficient capacity contributes
    0 allocations. The function shrinks the Lists to the exact used length at the
    end, so capacity (not length) drives the grow decision.

    Args:
        input_buf: Padded input buffer (must have >= 128 zero bytes after input_len
            for safe SIMD overread in parse_string and _parse_number).
        input_len: Real (unpadded) length of the JSON input.
        structural_positions: Structural character positions from Stage 1.
        container_stack: Pre-allocated stack for container open positions (capacity >= MAX_DEPTH).
        count_stack: Pre-allocated stack for element counts (capacity >= MAX_DEPTH).
        tape: Caller-owned tape to fill (reused across parses for zero warm allocs).
    """
    var num_structurals = len(structural_positions)
    if num_structurals == 0:
        raise ParseError(code=ErrorCode.EMPTY_DOCUMENT.value, position=0)

    # Append sentinel to structural_positions — eliminates si < num_structurals check in loop
    structural_positions.append(UInt32(0xFFFFFFFF))

    # Capacity-grow the caller tape (unsafe_uninit_length — no zeroing, raw pointer
    # writes fill before read). record_alloc() fires only on the grow branches, so a
    # warm tape with enough capacity contributes 0 allocations.
    var need_elem = input_len * 2 + 2
    var need_str = input_len + 64
    if tape.elements.capacity < need_elem:
        record_alloc()
        tape.elements.reserve(need_elem)
    tape.elements.resize(unsafe_uninit_length=need_elem)
    if tape.string_buf.capacity < need_str:
        record_alloc()
        tape.string_buf.reserve(need_str)
    tape.string_buf.resize(unsafe_uninit_length=need_str)
    var tape_ptr = tape.elements.unsafe_ptr()
    var tape_pos = 0
    var sbuf_pos = 0  # tracks used bytes in string_buf
    var input_ptr = input_buf.unsafe_ptr()

    # Root open placeholder at tape[0]
    tape_ptr[tape_pos] = make_tape_entry(TAG_ROOT, UInt64(0))
    tape_pos += 1

    # Interleaved container stack: stk[depth*2] = open_idx, stk[depth*2+1] = count
    # Merges container_stack and count_stack into one pointer, saving one register.
    container_stack.resize(MAX_DEPTH * 2, UInt32(0))
    var stk = container_stack.unsafe_ptr()
    var depth = 0

    # Sentinel: append UINT32_MAX so the loop needs no bounds check on si
    structural_positions.append(UInt32(0xFFFFFFFF))
    var si_ptr = structural_positions.unsafe_ptr()
    var si = 0

    while True:
        var pos = Int(si_ptr[si])
        if pos == Int(UInt32(0xFFFFFFFF)):
            break  # sentinel reached
        var byte = input_ptr[pos]

        if byte == TAG_STRING:  # '"'
            var buf_offset = UInt64(sbuf_pos)
            var result = parse_string(input_ptr, pos, input_len, tape.string_buf.unsafe_ptr() + sbuf_pos, 0)
            var consumed = result[0]
            sbuf_pos += result[1]
            tape_ptr[tape_pos] = make_tape_entry(TAG_STRING, buf_offset)
            tape_pos += 1
            si += 1
            # Skip structural positions within the consumed string (closing quote)
            var string_end = pos + consumed - 1
            while Int(si_ptr[si]) <= string_end:
                si += 1
            if depth == 0:
                break
        elif byte == UInt8(0x2C):  # ','
            if depth > 0:
                stk[depth * 2 - 1] += 1
            si += 1
        elif byte == UInt8(0x3A):  # ':'
            si += 1
        elif byte == UInt8(0x2D) or (byte >= UInt8(0x30) and byte <= UInt8(0x39)):
            var result = _parse_number(input_ptr + pos, input_len - pos)
            tape_ptr[tape_pos] = make_tape_entry(result.tag, UInt64(0))
            tape_ptr[tape_pos + 1] = result.value
            tape_pos += 2
            si += 1
            if depth == 0:
                break
        elif byte == TAG_OBJECT_OPEN:  # '{'
            if depth >= MAX_DEPTH:
                raise ParseError(code=ErrorCode.DEPTH_EXCEEDED.value, position=pos)
            stk[depth * 2] = UInt32(tape_pos)
            stk[depth * 2 + 1] = UInt32(0)
            tape_ptr[tape_pos] = make_tape_entry(TAG_OBJECT_OPEN, UInt64(0))
            tape_pos += 1
            depth += 1
            si += 1
        elif byte == TAG_ARRAY_OPEN:  # '['
            if depth >= MAX_DEPTH:
                raise ParseError(code=ErrorCode.DEPTH_EXCEEDED.value, position=pos)
            stk[depth * 2] = UInt32(tape_pos)
            stk[depth * 2 + 1] = UInt32(0)
            tape_ptr[tape_pos] = make_tape_entry(TAG_ARRAY_OPEN, UInt64(0))
            tape_pos += 1
            depth += 1
            si += 1
        elif byte == TAG_OBJECT_CLOSE:  # '}'
            if depth == 0 or UInt8(tape_ptr[Int(stk[depth * 2 - 2])] >> 56) != TAG_OBJECT_OPEN:
                raise ParseError(code=ErrorCode.TAPE_ERROR.value, position=pos)
            _close_container(tape_ptr, tape_pos, stk, depth, TAG_OBJECT_CLOSE)
            tape_pos += 1
            depth -= 1
            si += 1
            if depth == 0:
                break
        elif byte == TAG_ARRAY_CLOSE:  # ']'
            if depth == 0 or UInt8(tape_ptr[Int(stk[depth * 2 - 2])] >> 56) != TAG_ARRAY_OPEN:
                raise ParseError(code=ErrorCode.TAPE_ERROR.value, position=pos)
            _close_container(tape_ptr, tape_pos, stk, depth, TAG_ARRAY_CLOSE)
            tape_pos += 1
            depth -= 1
            si += 1
            if depth == 0:
                break
        elif byte == TAG_TRUE:  # 't' (true)
            _validate_true(input_ptr, pos, input_len)
            tape_ptr[tape_pos] = make_tape_entry(TAG_TRUE, UInt64(0))
            tape_pos += 1
            si += 1
            if depth == 0:
                break
        elif byte == TAG_FALSE:  # 'f' (false)
            _validate_false(input_ptr, pos, input_len)
            tape_ptr[tape_pos] = make_tape_entry(TAG_FALSE, UInt64(0))
            tape_pos += 1
            si += 1
            if depth == 0:
                break
        elif byte == TAG_NULL:  # 'n' (null)
            _validate_null(input_ptr, pos, input_len)
            tape_ptr[tape_pos] = make_tape_entry(TAG_NULL, UInt64(0))
            tape_pos += 1
            si += 1
            if depth == 0:
                break
        else:
            raise ParseError(code=ErrorCode.UNEXPECTED_VALUE.value, position=pos)

    # Check for trailing content (sentinel still present — if si didn't hit it, there's trailing)
    if Int(si_ptr[si]) != Int(UInt32(0xFFFFFFFF)):
        raise ParseError(code=ErrorCode.TRAILING_CONTENT.value, position=Int(si_ptr[si]))

    if depth != 0:
        raise ParseError(code=ErrorCode.UNCLOSED_CONTAINER.value, position=0)

    var root_close_idx = tape_pos
    tape_ptr[tape_pos] = make_tape_entry(TAG_ROOT, UInt64(0))
    tape_pos += 1
    tape_ptr[0] = make_tape_entry(TAG_ROOT, UInt64(root_close_idx))

    # Shrink tape and string_buf to actual used size (no zeroing on shrink)
    tape.elements.resize(tape_pos, UInt64(0))
    tape.string_buf.resize(sbuf_pos, UInt8(0))


@always_inline("nodebug")
def _close_container[o: Origin[mut=True]](
    tape_ptr: UnsafePointer[UInt64, origin=o],
    tape_pos: Int,
    stk: UnsafePointer[UInt32, _],
    depth: Int,
    close_tag: UInt8,
):
    # depth is current depth BEFORE decrement; container was opened at depth-1
    var open_idx = Int(stk[(depth - 1) * 2])
    var comma_count = stk[(depth - 1) * 2 + 1]
    var close_idx = tape_pos
    var open_tag = UInt8(tape_ptr[open_idx] >> 56)

    var is_empty = (close_idx == open_idx + 1)
    var count = UInt64(comma_count)
    if not is_empty:
        count += 1
    if count > 0xFFFFFF:
        count = 0xFFFFFF

    tape_ptr[tape_pos] = make_tape_entry(close_tag, UInt64(open_idx))
    tape_ptr[open_idx] = make_tape_entry(
        open_tag, (count << 32) | UInt64(close_idx + 1)
    )


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
