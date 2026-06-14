"""On-Demand (lazy) JSON reader — M0: flat top-level object.

A second, additive parsing layer beside the DOM. Stage 1 runs (the structural
index is built) but NO tape is materialised; a leaf is parsed only when its value
is actually read. This file holds the M0 surface:

- `ObjectHandle[o]` — a forward navigator over the flat root object's structural
  positions, obtained from `Parser.iter(...)`.
- `ValueHandle[o]` — a lazily-parsed leaf, obtained from `ObjectHandle.find_field`.

Both handles borrow the owning `Parser` through an origin-tracked
`Pointer[Parser, Self.o]` (the verified pattern; a bare `UnsafePointer` field
miscompiles on 1.0.0b1). They reuse stage 1's `structural_index` and the leaf
parsers `parse_string` / `_parse_number` as-is. The handles are valid only while
their `Parser` is alive and is neither reparsed nor moved — the same lifetime
contract as `Document[o]`. Callers never name these `[o]`-parametric types: the
public entry `Parser.iter(...)` returns the root handle by inference.

M0 scope: a flat top-level object whose root is `{...}` (positions[0] is `'{'`),
string and integer leaves only. Arrays, nesting, other leaf types, key-escape
handling, and validation modes are later milestones.
"""

from std.memory import bitcast

from jsonette.parser import Parser
from jsonette.stage2.strings import parse_string
from jsonette.stage2.numbers import _parse_number
from jsonette.tape import TAG_INT64, TAG_UINT64


comptime _QUOTE = UInt8(0x22)  # '"'
comptime _COLON = UInt8(0x3A)  # ':'
comptime _LBRACE = UInt8(0x7B)  # '{'
comptime _RBRACE = UInt8(0x7D)  # '}'
comptime _LBRACK = UInt8(0x5B)  # '['
comptime _RBRACK = UInt8(0x5D)  # ']'
comptime _COMMA = UInt8(0x2C)  # ','


struct ValueHandle[o: Origin[mut=True]](Movable):
    """A lazily-parsed JSON value, located by its structural index.

    Borrows the owning `Parser` through an origin-tracked pointer. The leaf is
    parsed only on access (`get_string` / `get_int`); nothing is parsed at
    construction. Valid only while the `Parser` is alive and is neither reparsed
    nor moved.
    """

    var _parser: Pointer[Parser, Self.o]
    var _si: Int        # structural index of this value in the parser's positions
    var _input_len: Int  # real (unpadded) input length; the Parser does not keep it

    def __init__(out self, ref [Self.o] parser: Parser, si: Int, input_len: Int):
        """Borrow `parser`; record the value's structural index and input length."""
        self._parser = Pointer(to=parser)
        self._si = si
        self._input_len = input_len

    def __init__(out self, *, deinit take: Self):
        """Move constructor: transfer the borrowed-parser pointer and fields."""
        self._parser = take._parser
        self._si = take._si
        self._input_len = take._input_len

    @no_inline
    def get_string(self) raises -> String:
        """Unescape this value as a JSON string and return it as an owned String.

        Parses lazily into the parser's reusable scratch buffer via the shared
        `parse_string`, then reads the 4-byte little-endian length prefix and the
        UTF-8 bytes it wrote. Raises if the value is not a JSON string (mirroring
        `get_int`'s tag guard), so a non-string never returns silently empty.
        """
        ref p = self._parser[]
        var pos = Int(p.positions[self._si])
        if p.padded.unsafe_ptr()[pos] != _QUOTE:
            raise Error("get_string: value is not a string")
        var needed = self._input_len + 64  # parse_string requires input_len + 64
        if len(p._od_scratch) < needed:
            p._od_scratch = List[UInt8](unsafe_uninit_length=needed)
        _ = parse_string(
            p.padded.unsafe_ptr(), pos, self._input_len, p._od_scratch.unsafe_ptr(), 0
        )
        var sp = p._od_scratch.unsafe_ptr()
        var ln = Int(
            UInt32(sp[0])
            | (UInt32(sp[1]) << 8)
            | (UInt32(sp[2]) << 16)
            | (UInt32(sp[3]) << 24)
        )
        return String(StringSlice(ptr=sp + 4, length=ln))

    @no_inline
    def get_int(self) raises -> Int64:
        """Parse this value as a JSON integer and return it as Int64.

        Parses lazily via the shared `_parse_number` and raises if the value is
        not an integer (e.g. a float), so a non-integer never returns silently
        wrong bits. The raw 64-bit payload is reinterpreted as a signed Int64.
        """
        ref p = self._parser[]
        var pos = Int(p.positions[self._si])
        var r = _parse_number(p.padded.unsafe_ptr() + pos, self._input_len - pos)
        if r.tag != TAG_INT64 and r.tag != TAG_UINT64:
            raise Error("get_int: value is not an integer")
        return bitcast[DType.int64](r.value)


struct ObjectHandle[o: Origin[mut=True]](Movable):
    """Forward navigator over a flat top-level JSON object.

    Borrows the owning `Parser` through an origin-tracked pointer. `find_field`
    scans the object's structural positions left to right and returns a
    `ValueHandle` at the matched key's value, unified with this handle's origin
    so the whole borrow chain shares one lifetime root. Valid only while the
    `Parser` is alive and is neither reparsed nor moved.
    """

    var _parser: Pointer[Parser, Self.o]
    var _input_len: Int

    def __init__(out self, ref [Self.o] parser: Parser, input_len: Int):
        """Borrow `parser` as a cursor over the root object (positions[0] is '{')."""
        self._parser = Pointer(to=parser)
        self._input_len = input_len

    def __init__(out self, *, deinit take: Self):
        """Move constructor: transfer the borrowed-parser pointer and length."""
        self._parser = take._parser
        self._input_len = take._input_len

    @no_inline
    def _skip_value(self, value_si: Int) -> Int:
        """Return the structural index just past the value starting at `value_si`.

        Depth-aware so the cursor never descends into a nested value's interior:

        - Object/array (`'{'`/`'['`): scan forward counting nesting depth (+1 on
          `'{'`/`'['`, -1 on `'}'`/`']'`); return the index AFTER the matching
          close. If the scan runs off the end (truncated input), return `n`.
        - String (`'"'`): two structurals (open + close), so `value_si + 2`.
        - Number/literal: a single structural, so `value_si + 1`.

        Modelled on the depth-aware skip used by the multi-hop on-demand PoC.
        """
        ref p = self._parser[]
        var ip = p.padded.unsafe_ptr()
        var n = len(p.positions)
        if value_si >= n:
            return n  # truncated: key had no value
        var vb = ip[Int(p.positions[value_si])]
        if vb == _LBRACE or vb == _LBRACK:
            var depth = 0
            var si = value_si
            while si < n:
                var ch = ip[Int(p.positions[si])]
                if ch == _LBRACE or ch == _LBRACK:
                    depth += 1
                elif ch == _RBRACE or ch == _RBRACK:
                    depth -= 1
                    if depth == 0:
                        return si + 1
                si += 1
            return n  # truncated: matching close never found
        elif vb == _QUOTE:
            return value_si + 2
        else:
            return value_si + 1

    @no_inline
    def find_field(self, key: String) raises -> ValueHandle[Self.o]:
        """Find the value for `key` in the flat root object; raise if absent.

        Walks the root object's KEY→VALUE pairs left to right, DEPTH-AWARE: each
        top-level key is a string at `si` (close quote at `si+1`, `':'` at `si+2`,
        value at `si+3`); after a non-matching pair the cursor jumps past the whole
        value via `_skip_value`, so nested objects/arrays are skipped wholesale and
        their interior keys never masquerade as top-level keys. On a key match,
        returns a `ValueHandle` at the value's structural index (`si+3`), raising
        if that value is missing (truncated input) rather than indexing past the
        positions list. M0 keys are matched byte-for-byte (no escape handling).
        """
        ref p = self._parser[]
        var ip = p.padded.unsafe_ptr()
        var n = len(p.positions)
        var si = 1  # skip the root '{' at positions[0]
        while si < n:
            var b = ip[Int(p.positions[si])]
            if b == _RBRACE:
                break  # end of root object
            # A complete top-level key needs at least its closing-quote structural
            # at si+1. If it is missing — a non-object root (e.g. `"x"`, `42`,
            # `[1,2]`) or an unterminated key (`{"a`) — no further complete key
            # exists, so the field is absent: break instead of reading positions
            # out of bounds (the OOB an earlier pass left at this index).
            if si + 1 >= n:
                break
            # `si` is a top-level KEY (a string): value structural is at si+3.
            var value_si = si + 3
            var pos = Int(p.positions[si])
            var kclose = Int(p.positions[si + 1])
            var klen = kclose - pos - 1
            var matched = klen == key.byte_length()
            if matched:
                var kb = key.as_bytes()
                for k in range(klen):
                    if ip[pos + 1 + k] != kb[k]:
                        matched = False
                        break
            if matched:
                if value_si >= n:
                    raise Error("field has no value: " + key)
                return ValueHandle[Self.o](p, value_si, self._input_len)
            si = self._skip_value(value_si)  # depth-aware advance past the value
            if si < n and ip[Int(p.positions[si])] == _COMMA:
                si += 1
        raise Error("field not found: " + key)
