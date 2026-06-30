"""On-Demand `validate()` — strict no-tape RFC-8259 walk over the structural index.

A whole-document validator that the lazy On-Demand reader deliberately is NOT.
Stage 1 (`structural_index`) runs and produces a flat `List[UInt32]` of structural
positions; this module walks that index with a strict grammar state machine,
materialising NO tape. It returns normally iff the byte stream is valid RFC 8259
and raises a `ParseError` otherwise.

The walk is over the structural-position INDEX, not characters:

- token kind = `ip[Int(positions[si])]` (the first byte at that structural).
- a number/literal occupies ONE structural (its scalar start); advance `si += 1`.
- a string `"` occupies TWO structurals (open at `si`, close at `si+1`); advance
  `si += 2`. A string is NEVER advanced by 1.
- `{` `}` `[` `]` `,` `:` each occupy one structural.
- a key and a string value are both `"` tokens; the grammar STATE distinguishes
  them — an object validates a key then expects `:` then a value.

Leaf validation reuses the shared stage-2 primitives unchanged: `parse_string`
(escapes/surrogates/control chars/closing quote), `_parse_number` plus the
On-Demand terminator guard `_scalar_token_ok` (rejects glued junk like `12.3.4`
after a number AND `truex`/`nullx` after a literal), and `_validate_true/false/
null`.

The grammar is driven by an EXPLICIT heap-allocated container stack rather than
native recursion, mirroring the iterative tape builder in `stage2/builder.mojo`
(same `ST_*` state set, same depth bound). One native stack frame walks any
nesting depth, so a deeply-nested document cannot overflow the native stack — a
2 KB document of 1024 `[` plus 1024 `]` is validated in constant native-stack
space. The nesting-depth bound matches the tape builder's `MAX_DEPTH` exactly,
so the validator and the DOM reject deeply-nested input at the same depth (accept
at MAX_DEPTH, reject at MAX_DEPTH+1 with `DEPTH_EXCEEDED`).
"""

from jsonette.error import ParseError, ErrorCode
from jsonette.stage2.strings import parse_string
from jsonette.stage2.numbers import _parse_number, _scalar_token_ok
from jsonette.stage2.builder import (
    MAX_DEPTH,
    _validate_true,
    _validate_false,
    _validate_null,
)


comptime _QUOTE = UInt8(0x22)  # '"'
comptime _COLON = UInt8(0x3A)  # ':'
comptime _LBRACE = UInt8(0x7B)  # '{'
comptime _RBRACE = UInt8(0x7D)  # '}'
comptime _LBRACK = UInt8(0x5B)  # '['
comptime _RBRACK = UInt8(0x5D)  # ']'
comptime _COMMA = UInt8(0x2C)  # ','
comptime _MINUS = UInt8(0x2D)  # '-'
comptime _DIGIT0 = UInt8(0x30)  # '0'
comptime _DIGIT9 = UInt8(0x39)  # '9'
comptime _LOWER_T = UInt8(0x74)  # 't'
comptime _LOWER_F = UInt8(0x66)  # 'f'
comptime _LOWER_N = UInt8(0x6E)  # 'n'


# Grammar states for the single-pass strict walk. These mirror the tape
# builder's `ST_*` states one-for-one so the two paths reach the same verdict by
# construction (locked by tests/conformance/test_parse_validate_differential).
comptime _ST_DOC_BEGIN: Int = 0      # expect the single root value
comptime _ST_OBJ_BEGIN: Int = 1     # after '{': expect a string key or '}'
comptime _ST_OBJ_KEY: Int = 2       # after ',': expect a string key
comptime _ST_OBJ_COLON: Int = 3     # after a key: expect ':'
comptime _ST_OBJ_VALUE: Int = 4     # after ':': expect a value
comptime _ST_OBJ_CONTINUE: Int = 5  # after a member value: expect ',' or '}'
comptime _ST_ARR_BEGIN: Int = 6     # after '[': expect a value or ']'
comptime _ST_ARR_VALUE: Int = 7     # after ',': expect a value
comptime _ST_ARR_CONTINUE: Int = 8  # after an element: expect ',' or ']'
comptime _ST_DOC_END: Int = 9       # root value complete: nothing may follow

# Container-stack frame markers. The explicit stack records, per open container,
# whether the parent is an object (so the close arm restores the right CONTINUE
# state). It replaces the native call stack the recursive walk used.
comptime _FRAME_OBJ: Int = 0  # this open container is an object
comptime _FRAME_ARR: Int = 1  # this open container is an array


def _validate_document(
    ip: UnsafePointer[UInt8, _],
    positions: List[UInt32],
    n: Int,
    input_len: Int,
    mut scratch: List[UInt8],
) raises ParseError:
    """Validate the whole document: exactly one top-level value, nothing after it.

    `n` is `len(positions)`. An empty OR whitespace-only document produces zero
    structurals (`n == 0`) and is rejected as EMPTY_DOCUMENT. Otherwise the
    structural index is walked once by an explicit grammar state machine: a
    heap-allocated `frames` stack (capacity MAX_DEPTH) records the enclosing
    container per nesting level, so any nesting depth is validated in constant
    native-stack space (no recursion). The walk raises on the first grammar
    violation; reaching the end in any state but `_ST_DOC_END` (a container left
    open, or a key/colon/value still expected) raises UNCLOSED_CONTAINER, and a
    token after the root value raises TRAILING_CONTENT — matching the prior
    recursive validator's accept/reject decisions and the tape builder exactly.
    """
    if n == 0:
        raise ParseError(code=ErrorCode.EMPTY_DOCUMENT.value, position=0)

    # Explicit container stack: frames[d] is _FRAME_OBJ / _FRAME_ARR for the
    # container opened at depth d. Bounded by MAX_DEPTH, so it allocates O(depth)
    # heap (never the native stack). depth==0 means we are at the root.
    var frames = List[Int](capacity=MAX_DEPTH)
    var depth = 0

    var state = _ST_DOC_BEGIN
    var si = 0

    while si < n:
        var pos = Int(positions[si])
        var b = ip[pos]

        if (
            state == _ST_DOC_BEGIN
            or state == _ST_OBJ_VALUE
            or state == _ST_ARR_BEGIN
            or state == _ST_ARR_VALUE
        ):
            # A value is expected (_ST_ARR_BEGIN additionally permits a closing
            # ']'). After a scalar, the next state is fixed by the enclosing
            # container (document end at the root).
            var after_scalar = _ST_ARR_CONTINUE
            if state == _ST_DOC_BEGIN:
                after_scalar = _ST_DOC_END
            elif state == _ST_OBJ_VALUE:
                after_scalar = _ST_OBJ_CONTINUE

            if b == _QUOTE:
                # Validates escapes/surrogates/control chars/closing quote.
                _ = parse_string(ip, pos, input_len, scratch.unsafe_ptr(), 0)
                si += 2  # a string occupies two structurals
                state = after_scalar
            elif b == _MINUS or (b >= _DIGIT0 and b <= _DIGIT9):
                var r = _parse_number(ip + pos, input_len - pos)
                if not _scalar_token_ok(ip, pos, r.bytes_consumed, input_len):
                    raise ParseError(
                        code=ErrorCode.NUMBER_ERROR.value, position=pos
                    )
                si += 1
                state = after_scalar
            elif b == _LOWER_T:
                _validate_true(ip, pos, input_len)
                if not _scalar_token_ok(ip, pos, 4, input_len):
                    raise ParseError(
                        code=ErrorCode.INVALID_LITERAL.value, position=pos
                    )
                si += 1
                state = after_scalar
            elif b == _LOWER_F:
                _validate_false(ip, pos, input_len)
                if not _scalar_token_ok(ip, pos, 5, input_len):
                    raise ParseError(
                        code=ErrorCode.INVALID_LITERAL.value, position=pos
                    )
                si += 1
                state = after_scalar
            elif b == _LOWER_N:
                _validate_null(ip, pos, input_len)
                if not _scalar_token_ok(ip, pos, 4, input_len):
                    raise ParseError(
                        code=ErrorCode.INVALID_LITERAL.value, position=pos
                    )
                si += 1
                state = after_scalar
            elif b == _LBRACE:
                if depth >= MAX_DEPTH:
                    raise ParseError(
                        code=ErrorCode.DEPTH_EXCEEDED.value, position=pos
                    )
                frames.append(_FRAME_OBJ)
                depth += 1
                si += 1
                state = _ST_OBJ_BEGIN
            elif b == _LBRACK:
                if depth >= MAX_DEPTH:
                    raise ParseError(
                        code=ErrorCode.DEPTH_EXCEEDED.value, position=pos
                    )
                frames.append(_FRAME_ARR)
                depth += 1
                si += 1
                state = _ST_ARR_BEGIN
            elif state == _ST_ARR_BEGIN and b == _RBRACK:
                # empty array []
                _ = frames.pop()
                depth -= 1
                si += 1
                state = _parent_state(frames, depth)
            else:
                # stray ',' / ':' / '}' / ']', BOM, control byte, etc.
                raise ParseError(
                    code=ErrorCode.UNEXPECTED_VALUE.value, position=pos
                )
        elif state == _ST_OBJ_BEGIN or state == _ST_OBJ_KEY:
            # An object member key (a string) is expected; _ST_OBJ_BEGIN also
            # permits a closing '}' (empty object).
            if b == _QUOTE:
                _ = parse_string(ip, pos, input_len, scratch.unsafe_ptr(), 0)
                si += 2  # a string occupies two structurals
                state = _ST_OBJ_COLON
            elif state == _ST_OBJ_BEGIN and b == _RBRACE:
                # empty object {}
                _ = frames.pop()
                depth -= 1
                si += 1
                state = _parent_state(frames, depth)
            else:
                # non-string key, or a trailing comma before '}'
                raise ParseError(
                    code=ErrorCode.UNEXPECTED_VALUE.value, position=pos
                )
        elif state == _ST_OBJ_COLON:
            if b == _COLON:
                si += 1
                state = _ST_OBJ_VALUE
            else:
                # missing colon, e.g. {"a" 1} or {"a",1}
                raise ParseError(code=ErrorCode.TAPE_ERROR.value, position=pos)
        elif state == _ST_OBJ_CONTINUE:
            if b == _COMMA:
                si += 1
                state = _ST_OBJ_KEY
            elif b == _RBRACE:
                _ = frames.pop()
                depth -= 1
                si += 1
                state = _parent_state(frames, depth)
            else:
                # missing comma between members, e.g. {"a":1 "b":2}
                raise ParseError(code=ErrorCode.TAPE_ERROR.value, position=pos)
        elif state == _ST_ARR_CONTINUE:
            if b == _COMMA:
                si += 1
                state = _ST_ARR_VALUE
            elif b == _RBRACK:
                _ = frames.pop()
                depth -= 1
                si += 1
                state = _parent_state(frames, depth)
            else:
                # missing comma between elements, e.g. [1 2], or colon-in-array
                raise ParseError(code=ErrorCode.TAPE_ERROR.value, position=pos)
        else:  # _ST_DOC_END — the single root value is complete; nothing follows
            raise ParseError(
                code=ErrorCode.TRAILING_CONTENT.value, position=pos
            )

    # Reaching the end of the structural index in any state but _ST_DOC_END means
    # a container was left open (or a key/colon/value was still expected).
    if state != _ST_DOC_END:
        raise ParseError(code=ErrorCode.UNCLOSED_CONTAINER.value, position=0)


@always_inline("nodebug")
def _parent_state(frames: List[Int], depth: Int) -> Int:
    """Next state after popping a container (depth already decremented): the parent
    container's continue-state, or document-end at the root.

    `depth` is the post-pop depth; `frames[depth-1]` is the now-current enclosing
    container (object -> _ST_OBJ_CONTINUE, array -> _ST_ARR_CONTINUE). At depth 0
    the root value is complete, so _ST_DOC_END.
    """
    if depth == 0:
        return _ST_DOC_END
    if frames[depth - 1] == _FRAME_OBJ:
        return _ST_OBJ_CONTINUE
    return _ST_ARR_CONTINUE
