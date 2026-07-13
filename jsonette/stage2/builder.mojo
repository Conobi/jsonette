"""Stage 2 tape builder: walks structural positions and produces a complete tape.

Combines containers (objects/arrays), literals (true/false/null), strings, and
numbers into a flat tape format with root envelope.
"""

from jsonette.tape import Tape, make_tape_entry, TAG_ROOT, TAG_OBJECT_OPEN, TAG_OBJECT_CLOSE, TAG_ARRAY_OPEN, TAG_ARRAY_CLOSE, TAG_STRING, TAG_TRUE, TAG_FALSE, TAG_NULL
from jsonette.error import ParseError, ErrorCode
from jsonette._alloc_count import record_alloc
from jsonette.stage2.numbers import _parse_number, _scalar_token_ok
from jsonette.stage2.strings import parse_string
from std.sys.intrinsics import unlikely

comptime MAX_DEPTH: Int = 1024

# Grammar states for the single-pass strict walk. The builder is now both the
# validator and the tape constructor (touch-once): each token is dispatched on
# (state, byte), so malformed structure is rejected where it occurs instead of a
# separate validation pass re-reading every leaf. States mirror the strict
# recursive-descent grammar in ondemand/validate.mojo, flattened onto the
# existing iterative container stack so deep nesting cannot overflow the native
# stack.
comptime ST_DOC_BEGIN: Int = 0      # expect the single root value
comptime ST_OBJ_BEGIN: Int = 1      # after '{': expect a string key or '}'
comptime ST_OBJ_KEY: Int = 2        # after ',': expect a string key
comptime ST_OBJ_COLON: Int = 3      # after a key: expect ':'
comptime ST_OBJ_VALUE: Int = 4      # after ':': expect a value
comptime ST_OBJ_CONTINUE: Int = 5   # after a member value: expect ',' or '}'
comptime ST_ARR_BEGIN: Int = 6      # after '[': expect a value or ']'
comptime ST_ARR_VALUE: Int = 7      # after ',': expect a value
comptime ST_ARR_CONTINUE: Int = 8   # after an element: expect ',' or ']'
comptime ST_DOC_END: Int = 9        # root value complete: nothing may follow


def build_tape(
    input_ptr: UnsafePointer[UInt8, _], input_len: Int, mut structural_positions: List[UInt32],
    mut container_stack: List[UInt32],
    mut tape: Tape,
) raises ParseError:
    """Stage 2 entry point: fill a caller-owned tape from structural positions and input bytes.

    The tape is supplied by the caller (the Parser owns it across parses). Its
    backing Lists are grown only when the current input needs more room than a
    prior parse left allocated; a warm tape with sufficient capacity contributes
    0 allocations. The function shrinks the Lists to the exact used length at the
    end, so capacity (not length) drives the grow decision.

    Args:
        input_ptr: Pointer to padded input buffer (must have >= 128 zero bytes after
            input_len for safe SIMD overread in parse_string and _parse_number).
        input_len: Real (unpadded) length of the JSON input.
        structural_positions: Structural character positions from Stage 1.
        container_stack: Pre-allocated stack for container open positions (capacity >= MAX_DEPTH).
            Used as an interleaved [open_idx, count] stack — see the loop body — so it
            also carries per-container element counts; no separate count stack is needed.
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
    # Size string_buf for the true worst case. Each parsed string is stored as
    # [4-byte LE length][content][1-byte NUL], so the cumulative used bytes are
    # sbuf_pos = Sum(content) + 5*n_strings. Sum(content) <= input_len because
    # unescaping never expands (\n is 2 input bytes -> 1, \uXXXX is 6 -> <=4).
    # For the per-string overhead, Stage 1 emits BOTH the opening and the closing
    # quote of every string as structural positions (real_quotes in the indexer)
    # and nothing else emits a paired quote, so the document holds at most
    # num_structurals // 2 strings — a closed-form upper bound on n_strings taken
    # straight from the structural index, no extra pass. The trailing +64
    # preserves the SIMD copy slack parse_string's unconditional 32-byte memcpy
    # overrun relies on. need_str is therefore >= sbuf_pos for ANY input, so the
    # buffer never overruns and the terminal resize only truncates.
    var n_strings_max = num_structurals // 2
    var need_str = input_len + 5 * n_strings_max + 64
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
    # Root open placeholder at tape[0]
    tape_ptr[tape_pos] = make_tape_entry(TAG_ROOT, UInt64(0))
    tape_pos += 1

    # Interleaved container stack: stk[depth*2] = open_idx, stk[depth*2+1] = count
    # One pointer carries both the open index and the element count, saving a register.
    container_stack.resize(MAX_DEPTH * 2, UInt32(0))
    var stk = container_stack.unsafe_ptr()
    var depth = 0

    # Sentinel: append UINT32_MAX so the loop needs no bounds check on si
    structural_positions.append(UInt32(0xFFFFFFFF))
    var si_ptr = structural_positions.unsafe_ptr()
    var si = 0

    var state = ST_DOC_BEGIN

    while True:
        var pos = Int(si_ptr[si])
        if pos == Int(UInt32(0xFFFFFFFF)):
            break  # sentinel reached
        var byte = input_ptr[pos]

        if (
            state == ST_DOC_BEGIN
            or state == ST_OBJ_VALUE
            or state == ST_ARR_BEGIN
            or state == ST_ARR_VALUE
        ):
            # A value is expected (ST_ARR_BEGIN additionally permits a closing ']').
            # After a scalar, the next state is fixed by the surrounding container.
            var after_scalar = ST_ARR_CONTINUE
            if state == ST_DOC_BEGIN:
                after_scalar = ST_DOC_END
            elif state == ST_OBJ_VALUE:
                after_scalar = ST_OBJ_CONTINUE

            if byte == TAG_STRING:  # '"'
                var buf_offset = UInt64(sbuf_pos)
                var result = parse_string(input_ptr, pos, input_len, tape.string_buf.unsafe_ptr() + sbuf_pos, 0)
                var consumed = result[0]
                sbuf_pos += result[1]
                tape_ptr[tape_pos] = make_tape_entry(TAG_STRING, buf_offset)
                tape_pos += 1
                si += 1
                var string_end = pos + consumed - 1
                while Int(si_ptr[si]) <= string_end:
                    si += 1
                state = after_scalar
            elif byte == UInt8(0x2D) or (byte >= UInt8(0x30) and byte <= UInt8(0x39)):  # number
                var result = _parse_number(input_ptr + pos, input_len - pos)
                if not _scalar_token_ok(input_ptr, pos, result.bytes_consumed, input_len):
                    raise ParseError(code=ErrorCode.NUMBER_ERROR.value, position=pos)
                tape_ptr[tape_pos] = make_tape_entry(result.tag, UInt64(0))
                tape_ptr[tape_pos + 1] = result.value
                tape_pos += 2
                si += 1
                state = after_scalar
            elif byte == TAG_TRUE:  # 't' (true)
                _validate_true(input_ptr, pos, input_len)
                if not _scalar_token_ok(input_ptr, pos, 4, input_len):
                    raise ParseError(code=ErrorCode.INVALID_LITERAL.value, position=pos)
                tape_ptr[tape_pos] = make_tape_entry(TAG_TRUE, UInt64(0))
                tape_pos += 1
                si += 1
                state = after_scalar
            elif byte == TAG_FALSE:  # 'f' (false)
                _validate_false(input_ptr, pos, input_len)
                if not _scalar_token_ok(input_ptr, pos, 5, input_len):
                    raise ParseError(code=ErrorCode.INVALID_LITERAL.value, position=pos)
                tape_ptr[tape_pos] = make_tape_entry(TAG_FALSE, UInt64(0))
                tape_pos += 1
                si += 1
                state = after_scalar
            elif byte == TAG_NULL:  # 'n' (null)
                _validate_null(input_ptr, pos, input_len)
                if not _scalar_token_ok(input_ptr, pos, 4, input_len):
                    raise ParseError(code=ErrorCode.INVALID_LITERAL.value, position=pos)
                tape_ptr[tape_pos] = make_tape_entry(TAG_NULL, UInt64(0))
                tape_pos += 1
                si += 1
                state = after_scalar
            elif byte == TAG_OBJECT_OPEN:  # '{'
                if depth >= MAX_DEPTH:
                    raise ParseError(code=ErrorCode.DEPTH_EXCEEDED.value, position=pos)
                stk[depth * 2] = UInt32(tape_pos)
                stk[depth * 2 + 1] = UInt32(0)
                tape_ptr[tape_pos] = make_tape_entry(TAG_OBJECT_OPEN, UInt64(0))
                tape_pos += 1
                depth += 1
                si += 1
                state = ST_OBJ_BEGIN
            elif byte == TAG_ARRAY_OPEN:  # '['
                if depth >= MAX_DEPTH:
                    raise ParseError(code=ErrorCode.DEPTH_EXCEEDED.value, position=pos)
                stk[depth * 2] = UInt32(tape_pos)
                stk[depth * 2 + 1] = UInt32(0)
                tape_ptr[tape_pos] = make_tape_entry(TAG_ARRAY_OPEN, UInt64(0))
                tape_pos += 1
                depth += 1
                si += 1
                state = ST_ARR_BEGIN
            elif state == ST_ARR_BEGIN and unlikely(byte == TAG_ARRAY_CLOSE):  # empty array ']'
                _close_container(tape_ptr, tape_pos, stk, depth, TAG_ARRAY_CLOSE)
                tape_pos += 1
                depth -= 1
                si += 1
                state = _parent_state(tape_ptr, stk, depth)
            else:
                raise ParseError(code=ErrorCode.UNEXPECTED_VALUE.value, position=pos)
        elif state == ST_OBJ_BEGIN or state == ST_OBJ_KEY:
            # An object member key (a string) is expected; ST_OBJ_BEGIN also
            # permits a closing '}' (empty object).
            if byte == TAG_STRING:  # '"' key
                var buf_offset = UInt64(sbuf_pos)
                var result = parse_string(input_ptr, pos, input_len, tape.string_buf.unsafe_ptr() + sbuf_pos, 0)
                var consumed = result[0]
                sbuf_pos += result[1]
                tape_ptr[tape_pos] = make_tape_entry(TAG_STRING, buf_offset)
                tape_pos += 1
                si += 1
                var string_end = pos + consumed - 1
                while Int(si_ptr[si]) <= string_end:
                    si += 1
                state = ST_OBJ_COLON
            elif state == ST_OBJ_BEGIN and unlikely(byte == TAG_OBJECT_CLOSE):  # empty object '}'
                _close_container(tape_ptr, tape_pos, stk, depth, TAG_OBJECT_CLOSE)
                tape_pos += 1
                depth -= 1
                si += 1
                state = _parent_state(tape_ptr, stk, depth)
            else:
                # non-string key, or a trailing comma before '}'
                raise ParseError(code=ErrorCode.UNEXPECTED_VALUE.value, position=pos)
        elif state == ST_OBJ_COLON:
            if byte == UInt8(0x3A):  # ':'
                si += 1
                state = ST_OBJ_VALUE
            else:
                raise ParseError(code=ErrorCode.TAPE_ERROR.value, position=pos)  # missing colon
        elif state == ST_OBJ_CONTINUE:
            if byte == UInt8(0x2C):  # ','
                stk[depth * 2 - 1] += 1
                si += 1
                state = ST_OBJ_KEY
            elif unlikely(byte == TAG_OBJECT_CLOSE):  # '}'
                _close_container(tape_ptr, tape_pos, stk, depth, TAG_OBJECT_CLOSE)
                tape_pos += 1
                depth -= 1
                si += 1
                state = _parent_state(tape_ptr, stk, depth)
            else:
                raise ParseError(code=ErrorCode.TAPE_ERROR.value, position=pos)  # missing comma
        elif state == ST_ARR_CONTINUE:
            if byte == UInt8(0x2C):  # ','
                stk[depth * 2 - 1] += 1
                si += 1
                state = ST_ARR_VALUE
            elif unlikely(byte == TAG_ARRAY_CLOSE):  # ']'
                _close_container(tape_ptr, tape_pos, stk, depth, TAG_ARRAY_CLOSE)
                tape_pos += 1
                depth -= 1
                si += 1
                state = _parent_state(tape_ptr, stk, depth)
            else:
                raise ParseError(code=ErrorCode.TAPE_ERROR.value, position=pos)  # missing comma
        else:  # ST_DOC_END — the single root value is complete; nothing may follow
            raise ParseError(code=ErrorCode.TRAILING_CONTENT.value, position=pos)

    # Reaching the sentinel in any state other than ST_DOC_END means a container
    # was left open (or a key/colon/value was still expected) at end of input.
    if state != ST_DOC_END:
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
def _parent_state[o: Origin[mut=True]](
    tape_ptr: UnsafePointer[UInt64, origin=o], stk: UnsafePointer[UInt32, _], depth: Int
) -> Int:
    """Next state after popping a container (depth already decremented): the parent
    container's continue-state, or document-end at the root."""
    if depth == 0:
        return ST_DOC_END
    var parent_tag = UInt8(tape_ptr[Int(stk[(depth - 1) * 2])] >> 56)
    if parent_tag == TAG_OBJECT_OPEN:
        return ST_OBJ_CONTINUE
    return ST_ARR_CONTINUE


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
