"""On-Demand `validate()` — strict no-tape RFC-8259 walk over the structural index.

A whole-document validator that the lazy On-Demand reader deliberately is NOT.
Stage 1 (`structural_index`) runs and produces a flat `List[UInt32]` of structural
positions; this module walks that index with a strict recursive-descent grammar,
materialising NO tape. It returns normally iff the byte stream is valid RFC 8259
and raises a `ParseError` otherwise.

The walk is over the structural-position INDEX, not characters:

- token kind = `ip[Int(positions[si])]` (the first byte at that structural).
- a number/literal occupies ONE structural (its scalar start); advance `si += 1`.
- a string `"` occupies TWO structurals (open at `si`, close at `si+1`); advance
  `si += 2`. A string is NEVER advanced by 1.
- `{` `}` `[` `]` `,` `:` each occupy one structural.
- a key and a string value are both `"` tokens; the grammar STATE distinguishes
  them — `_validate_object` validates a key then expects `:` then a value.

Leaf validation reuses the shared stage-2 primitives unchanged: `parse_string`
(escapes/surrogates/control chars/closing quote), `_parse_number` plus the
On-Demand terminator guard `_number_token_ok` (rejects glued junk like `12.3.4`),
and `_validate_true/false/null`. The nesting-depth bound matches the tape
builder's `MAX_DEPTH` exactly, so the validator and the DOM reject deeply-nested
input at the same depth; that bound also makes the recursion stack-safe (it
raises before the cap is exceeded).
"""

from jsonette.error import ParseError, ErrorCode
from jsonette.stage2.strings import parse_string
from jsonette.stage2.numbers import _parse_number
from jsonette.stage2.builder import (
    MAX_DEPTH,
    _validate_true,
    _validate_false,
    _validate_null,
)
from jsonette.ondemand.ondemand import _number_token_ok


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


def _validate_document(
    ip: UnsafePointer[UInt8, _],
    positions: List[UInt32],
    n: Int,
    input_len: Int,
    mut scratch: List[UInt8],
) raises ParseError:
    """Validate the whole document: exactly one top-level value, nothing after it.

    `n` is `len(positions)`. An empty OR whitespace-only document produces zero
    structurals (`n == 0`) and is rejected as EMPTY_DOCUMENT. Otherwise a single
    value is validated from `si = 0`; if that value does not consume every
    structural, the remainder is TRAILING_CONTENT (e.g. `[1]x`, `{}{}`).
    """
    if n == 0:
        raise ParseError(code=ErrorCode.EMPTY_DOCUMENT.value, position=0)
    var next = _validate_value(ip, positions, n, input_len, scratch, 0, 0)
    if next != n:
        raise ParseError(
            code=ErrorCode.TRAILING_CONTENT.value,
            position=Int(positions[next]),
        )


def _validate_value(
    ip: UnsafePointer[UInt8, _],
    positions: List[UInt32],
    n: Int,
    input_len: Int,
    mut scratch: List[UInt8],
    si: Int,
    depth: Int,
) raises ParseError -> Int:
    """Validate one JSON value starting at structural index `si`; return next_si.

    Dispatches on the value's first byte:
    - `{` / `[` descend into `_validate_object` / `_validate_array`.
    - `"` validates the string via `parse_string` and advances by 2 structurals.
    - `-`/digit validates the number via `_parse_number` plus the terminator
      guard (rejecting glued junk), advancing by 1.
    - `t`/`f`/`n` validate the literal, advancing by 1.
    - anything else (a stray `,`/`:`/`}`/`]`, a BOM `0xEF`, `@`, a control byte)
      is UNEXPECTED_VALUE — there is no value at this position.
    """
    var pos = Int(positions[si])
    var b = ip[pos]
    if b == _LBRACE:
        return _validate_object(ip, positions, n, input_len, scratch, si, depth)
    if b == _LBRACK:
        return _validate_array(ip, positions, n, input_len, scratch, si, depth)
    if b == _QUOTE:
        # Validates escapes/surrogates/control chars/closing quote; result unused.
        _ = parse_string(ip, pos, input_len, scratch.unsafe_ptr(), 0)
        return si + 2
    if b == _MINUS or (b >= _DIGIT0 and b <= _DIGIT9):
        var r = _parse_number(ip + pos, input_len - pos)
        if not _number_token_ok(ip, pos, r.bytes_consumed, input_len):
            raise ParseError(code=ErrorCode.NUMBER_ERROR.value, position=pos)
        return si + 1
    if b == _LOWER_T:
        _validate_true(ip, pos, input_len)
        return si + 1
    if b == _LOWER_F:
        _validate_false(ip, pos, input_len)
        return si + 1
    if b == _LOWER_N:
        _validate_null(ip, pos, input_len)
        return si + 1
    raise ParseError(code=ErrorCode.UNEXPECTED_VALUE.value, position=pos)


def _validate_object(
    ip: UnsafePointer[UInt8, _],
    positions: List[UInt32],
    n: Int,
    input_len: Int,
    mut scratch: List[UInt8],
    si: Int,
    depth: Int,
) raises ParseError -> Int:
    """Validate an object whose `{` is at structural `si`; return the index past `}`.

    The depth check matches the tape builder exactly (`depth >= MAX_DEPTH` raises
    DEPTH_EXCEEDED before recursing). An empty object `{}` returns immediately.
    Otherwise the `key : value (, key : value)* }` grammar is enforced:
    - a non-string in key position (incl. `}` right after a `,` = trailing comma)
      is UNEXPECTED_VALUE.
    - a missing `:` after a key is TAPE_ERROR (e.g. `{"a" 1}`, `{"a",1}`).
    - a separator that is neither `}` nor `,` after a value is TAPE_ERROR
      (missing comma, e.g. `{"a":1 "b":2}`).
    A run off the end before the closing `}` is UNCLOSED_CONTAINER.
    """
    if depth >= MAX_DEPTH:
        raise ParseError(
            code=ErrorCode.DEPTH_EXCEEDED.value, position=Int(positions[si])
        )
    var cur = si + 1
    if cur >= n:
        raise ParseError(
            code=ErrorCode.UNCLOSED_CONTAINER.value, position=Int(positions[si])
        )
    if ip[Int(positions[cur])] == _RBRACE:
        return cur + 1  # empty object {}
    while True:
        if cur >= n:
            raise ParseError(
                code=ErrorCode.UNCLOSED_CONTAINER.value,
                position=Int(positions[si]),
            )
        var key_pos = Int(positions[cur])
        if ip[key_pos] != _QUOTE:
            # Non-string key, OR a `}` right after a `,` (trailing comma).
            raise ParseError(
                code=ErrorCode.UNEXPECTED_VALUE.value, position=key_pos
            )
        _ = parse_string(ip, key_pos, input_len, scratch.unsafe_ptr(), 0)
        cur += 2  # a string occupies two structurals
        if cur >= n:
            raise ParseError(
                code=ErrorCode.UNCLOSED_CONTAINER.value,
                position=Int(positions[si]),
            )
        if ip[Int(positions[cur])] != _COLON:
            # Missing colon, e.g. `{"a" 1}` or `{"a",1}`.
            raise ParseError(
                code=ErrorCode.TAPE_ERROR.value, position=Int(positions[cur])
            )
        cur += 1
        if cur >= n:
            raise ParseError(
                code=ErrorCode.UNCLOSED_CONTAINER.value,
                position=Int(positions[si]),
            )
        cur = _validate_value(ip, positions, n, input_len, scratch, cur, depth + 1)
        if cur >= n:
            raise ParseError(
                code=ErrorCode.UNCLOSED_CONTAINER.value,
                position=Int(positions[si]),
            )
        var c = ip[Int(positions[cur])]
        if c == _RBRACE:
            return cur + 1
        elif c == _COMMA:
            cur += 1
            continue
        else:
            # Missing comma between members, e.g. `{"a":1 "b":2}`.
            raise ParseError(
                code=ErrorCode.TAPE_ERROR.value, position=Int(positions[cur])
            )


def _validate_array(
    ip: UnsafePointer[UInt8, _],
    positions: List[UInt32],
    n: Int,
    input_len: Int,
    mut scratch: List[UInt8],
    si: Int,
    depth: Int,
) raises ParseError -> Int:
    """Validate an array whose `[` is at structural `si`; return the index past `]`.

    The depth check matches the tape builder exactly (`depth >= MAX_DEPTH` raises
    DEPTH_EXCEEDED before recursing). An empty array `[]` returns immediately.
    Otherwise the `value (, value)* ]` grammar is enforced: a stray `]`/`,` in
    value position is UNEXPECTED_VALUE (caught by `_validate_value`), which
    rejects leading/double/trailing commas (`[,1]`, `[1,,2]`, `[1,2,]`). A
    separator that is neither `]` nor `,` after a value is TAPE_ERROR (missing
    comma `[1 2]`, or colon-in-array `["a":1]`). A run off the end before `]` is
    UNCLOSED_CONTAINER.
    """
    if depth >= MAX_DEPTH:
        raise ParseError(
            code=ErrorCode.DEPTH_EXCEEDED.value, position=Int(positions[si])
        )
    var cur = si + 1
    if cur >= n:
        raise ParseError(
            code=ErrorCode.UNCLOSED_CONTAINER.value, position=Int(positions[si])
        )
    if ip[Int(positions[cur])] == _RBRACK:
        return cur + 1  # empty array []
    while True:
        if cur >= n:
            raise ParseError(
                code=ErrorCode.UNCLOSED_CONTAINER.value,
                position=Int(positions[si]),
            )
        # A stray `]`/`,` in value position -> UNEXPECTED_VALUE (leading/double/
        # trailing commas all land here).
        cur = _validate_value(ip, positions, n, input_len, scratch, cur, depth + 1)
        if cur >= n:
            raise ParseError(
                code=ErrorCode.UNCLOSED_CONTAINER.value,
                position=Int(positions[si]),
            )
        var c = ip[Int(positions[cur])]
        if c == _RBRACK:
            return cur + 1
        elif c == _COMMA:
            cur += 1
            continue
        else:
            # Missing comma `[1 2]`, or colon-in-array `["a":1]`.
            raise ParseError(
                code=ErrorCode.TAPE_ERROR.value, position=Int(positions[cur])
            )
