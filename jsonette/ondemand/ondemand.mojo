"""On-Demand (lazy) JSON reader — navigable handles over the structural index.

A second, additive parsing layer beside the DOM. Stage 1 runs (the structural
index is built) but NO tape is materialised; a leaf is parsed and validated only
when its value is actually read. This file holds the navigation surface:

- `Object[o]` — forward navigator over an object's structural positions
  (root object via `Reader.root().get_object()`, nested via `Value.get_object`):
  `field(key)` (depth-aware, escape-aware) and forward iteration
  (`at_end`/`next_field` yielding `Field`).
- `Array[o]` — forward navigator over an array (`Value.get_array`):
  `at_end`/`next_element` yielding `Value`.
- `Value[o]` — a lazily-parsed value: leaf accessors (`get_string`,
  `get_int`/`get_uint`/`get_float`, `get_bool`, `is_null`) and byte-level type
  predicates (`is_string`/`is_number`/`is_bool`/`is_object`/`is_array`), plus
  `get_object`/`get_array` to descend.
- `Field[o]` — a `(key, value)` pair from object iteration.

Validation is **lazy / path-local**: a leaf is fully validated on access (a
malformed accessed leaf raises — incl. a number's `_scalar_token_ok` trailing-junk
guard), but structure off the navigated path is NOT checked, and a skipped
malformed sibling is tolerated. For a strict whole-document yes/no, use
`Parser.validate` (the no-tape full walk in `validate.mojo`).

All handles borrow the owning `Reader` through an origin-tracked
`Pointer[Reader, Self.o]` (the verified pattern; a bare `UnsafePointer` field
miscompiles on 1.0.0b1), reaching the underlying `Parser` as `self._reader[]._parser`.
They reuse stage 1's `structural_index` and the leaf parsers `parse_string` /
`_parse_number` as-is. A handle is valid only while its `Reader` is alive and is
neither reparsed nor moved (the same lifetime contract as `Document[o]`; a
generation token trapped under `-D ASSERT=all` catches use-across-reparse) and,
being forward-only, only until its issuing cursor advances again. Callers never
name these `[o]`-parametric types: the public entries (`Reader.root`, the
accessors) return handles by inference.
"""

from std.collections import Optional
from std.memory import bitcast

from jsonette.parser import Parser
from jsonette.ondemand.reader import Reader
from jsonette.stage2.strings import parse_string
from jsonette.stage2.numbers import _parse_number, _scalar_token_ok
from jsonette.stage2.builder import _validate_true, _validate_false, _validate_null
from jsonette.tape import TAG_INT64, TAG_UINT64, TAG_FLOAT64


comptime _QUOTE = UInt8(0x22)  # '"'
comptime _BACKSLASH = UInt8(0x5C)  # '\'
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


# `_scalar_token_ok` moved to jsonette.stage2.numbers (core Stage 2) and is
# imported above, so this On-Demand module no longer owns the shared guard and
# the DOM parse path can reach it without depending on On-Demand.


struct Value[o: Origin[mut=True]](Movable):
    """A lazily-parsed JSON value, located by its structural index.

    Borrows the owning `Reader` through an origin-tracked pointer (reaching the
    underlying `Parser` as `self._reader[]._parser`). The leaf is parsed only on
    access (`get_string` / `get_int`); nothing is parsed at construction. Valid
    only while the `Reader` is alive and is neither reparsed nor moved.
    """

    var _reader: Pointer[Reader, Self.o]
    var _si: Int        # structural index of this value in the parser's positions
    var _gen: Int       # the Reader's generation at construction (use-after-reparse trap)

    def __init__(out self, ref [Self.o] reader: Reader, si: Int, gen: Int):
        """Borrow `reader`; record the value's structural index and generation."""
        self._reader = Pointer(to=reader)
        self._si = si
        self._gen = gen

    def __init__(out self, *, deinit take: Self):
        """Move constructor: transfer the borrowed-reader pointer and fields."""
        self._reader = take._reader
        self._si = take._si
        self._gen = take._gen

    @always_inline("nodebug")
    def _check(self):
        debug_assert(
            self._gen == self._reader[]._gen, "stale on-demand handle used after reparse"
        )

    @no_inline
    def get_string(self) raises -> String:
        """Unescape this value as a JSON string and return it as an owned String.

        Parses lazily into the parser's reusable scratch buffer via the shared
        `parse_string`, then reads the 4-byte little-endian length prefix and the
        UTF-8 bytes it wrote. Raises if the value is not a JSON string (mirroring
        `get_int`'s tag guard), so a non-string never returns silently empty.
        """
        self._check()
        ref p = self._reader[]._parser
        var input_len = self._reader[]._input_len
        var pos = Int(p.positions[self._si])
        if p.padded.unsafe_ptr()[pos] != _QUOTE:
            raise Error("get_string: value is not a string")
        var needed = input_len + 64  # parse_string requires input_len + 64
        if len(p._od_scratch) < needed:
            p._od_scratch = List[UInt8](unsafe_uninit_length=needed)
        _ = parse_string(
            p.padded.unsafe_ptr(), pos, input_len, p._od_scratch.unsafe_ptr(), 0
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
        Also raises on trailing junk glued to the number (e.g. `0x1`, `42x`):
        the token must end at a clean boundary (whitespace, `,`, `}`, `]`, EOF)
        or the leading numeric prefix would be returned silently.
        """
        self._check()
        ref p = self._reader[]._parser
        var input_len = self._reader[]._input_len
        var pos = Int(p.positions[self._si])
        var r = _parse_number(p.padded.unsafe_ptr() + pos, input_len - pos)
        if r.tag != TAG_INT64 and r.tag != TAG_UINT64:
            raise Error("get_int: value is not an integer")
        # A positive integer above Int64.MAX is tagged UINT64; bitcasting it would
        # silently return a negative Int64. Raise instead (matches the DOM), so a
        # valid-but-out-of-range integer never returns silently wrong bits.
        if r.tag == TAG_UINT64 and r.value > UInt64(0x7FFF_FFFF_FFFF_FFFF):
            raise Error("get_int: integer out of Int64 range")
        if not _scalar_token_ok(
            p.padded.unsafe_ptr(), pos, r.bytes_consumed, input_len
        ):
            raise Error("get_int: trailing characters after number")
        return bitcast[DType.int64](r.value)

    @no_inline
    def get_uint(self) raises -> UInt64:
        """Parse this value as a non-negative JSON integer and return it as UInt64.

        Parses lazily via the shared `_parse_number` and raises if the value is
        not an integer (e.g. a float or string). A negative integer (tagged
        INT64 with a negative payload) cannot be represented as unsigned, so it
        raises rather than wrapping. A UINT64-tagged value is returned directly;
        a non-negative INT64 is reinterpreted from its signed bits. Also raises on
        trailing junk glued to the number (e.g. `0x1`, `42x`): the token must end
        at a clean boundary (whitespace, `,`, `}`, `]`, EOF) or the leading
        numeric prefix would be returned silently.
        """
        self._check()
        ref p = self._reader[]._parser
        var input_len = self._reader[]._input_len
        var pos = Int(p.positions[self._si])
        var r = _parse_number(p.padded.unsafe_ptr() + pos, input_len - pos)
        if r.tag != TAG_UINT64 and r.tag != TAG_INT64:
            raise Error("get_uint: value is not an integer")
        if not _scalar_token_ok(
            p.padded.unsafe_ptr(), pos, r.bytes_consumed, input_len
        ):
            raise Error("get_uint: trailing characters after number")
        if r.tag == TAG_UINT64:
            return r.value
        var signed = bitcast[DType.int64](r.value)
        if signed < 0:
            raise Error("get_uint: integer is negative")
        return UInt64(signed)

    @no_inline
    def get_float(self) raises -> Float64:
        """Parse this value as any JSON number and return it as Float64.

        Parses lazily via the shared `_parse_number` and raises if the value is
        not a number. A FLOAT64-tagged value is reinterpreted from its raw bits;
        an INT64 or UINT64 integer is widened to Float64 (with the usual
        round-to-nearest loss for magnitudes above 2^53). Also raises on trailing
        junk glued to the number (e.g. `12.3.4`, `1e1e1`): the token must end at a
        clean boundary (whitespace, `,`, `}`, `]`, EOF) or the leading numeric
        prefix would be returned silently.
        """
        self._check()
        ref p = self._reader[]._parser
        var input_len = self._reader[]._input_len
        var pos = Int(p.positions[self._si])
        var r = _parse_number(p.padded.unsafe_ptr() + pos, input_len - pos)
        if r.tag != TAG_FLOAT64 and r.tag != TAG_INT64 and r.tag != TAG_UINT64:
            raise Error("get_float: value is not a number")
        if not _scalar_token_ok(
            p.padded.unsafe_ptr(), pos, r.bytes_consumed, input_len
        ):
            raise Error("get_float: trailing characters after number")
        if r.tag == TAG_FLOAT64:
            return bitcast[DType.float64](r.value)
        if r.tag == TAG_INT64:
            return Float64(bitcast[DType.int64](r.value))
        return Float64(r.value)

    @no_inline
    def get_bool(self) raises -> Bool:
        """Read this value as a JSON boolean and return it as Bool.

        Inspects the value's first byte (through the parser pointer, like
        `get_string`): `t` validates the `true` literal and returns True, `f`
        validates `false` and returns False. Any other first byte raises, so a
        non-bool never returns a silently wrong result. Also raises on trailing
        junk glued to the literal (e.g. `truex`, `falsey`): `_validate_true/false`
        only check the fixed keyword bytes, so the token must additionally end at a
        clean boundary (whitespace, `,`, `}`, `]`, EOF) — mirroring the number
        path's `_scalar_token_ok` guard and the whole-document validator.
        """
        self._check()
        ref p = self._reader[]._parser
        var input_len = self._reader[]._input_len
        var pos = Int(p.positions[self._si])
        var b = p.padded.unsafe_ptr()[pos]
        if b == _LOWER_T:
            _validate_true(p.padded.unsafe_ptr(), pos, input_len)
            if not _scalar_token_ok(p.padded.unsafe_ptr(), pos, 4, input_len):
                raise Error("get_bool: trailing characters after literal")
            return True
        if b == _LOWER_F:
            _validate_false(p.padded.unsafe_ptr(), pos, input_len)
            if not _scalar_token_ok(p.padded.unsafe_ptr(), pos, 5, input_len):
                raise Error("get_bool: trailing characters after literal")
            return False
        raise Error("get_bool: value is not a bool")

    @no_inline
    def is_null(self) raises -> Bool:
        """Return True iff this value is the JSON `null` literal.

        Inspects the value's first byte: a first byte other than `n` yields False
        (a predicate — a non-null value does not raise). A first byte of `n` is
        validated as the full `null` literal: it yields True, or RAISES if it is a
        malformed `n...` token (e.g. `nul`, or trailing junk like `nullx`), rather
        than silently accepting it — the token must also end at a clean boundary
        (the `_scalar_token_ok` guard), since `_validate_null` only checks the four
        keyword bytes.
        """
        self._check()
        ref p = self._reader[]._parser
        var input_len = self._reader[]._input_len
        var pos = Int(p.positions[self._si])
        if p.padded.unsafe_ptr()[pos] != _LOWER_N:
            return False
        _validate_null(p.padded.unsafe_ptr(), pos, input_len)
        if not _scalar_token_ok(p.padded.unsafe_ptr(), pos, 4, input_len):
            raise Error("is_null: trailing characters after literal")
        return True

    @always_inline("nodebug")
    def _first_byte(self) -> UInt8:
        """Return the value's first input byte (the type-discriminating char)."""
        ref p = self._reader[]._parser
        return p.padded.unsafe_ptr()[Int(p.positions[self._si])]

    @always_inline("nodebug")
    def is_string(self) -> Bool:
        """Return True iff the value's first byte opens a JSON string (`"`)."""
        self._check()
        return self._first_byte() == _QUOTE

    @always_inline("nodebug")
    def is_number(self) -> Bool:
        """Return True iff the value's first byte starts a JSON number.

        A number begins with `-` or a digit `0`-`9`; this is a byte test only,
        so it neither parses nor validates the number that follows.
        """
        self._check()
        var b = self._first_byte()
        return b == _MINUS or (b >= _DIGIT0 and b <= _DIGIT9)

    @always_inline("nodebug")
    def is_bool(self) -> Bool:
        """Return True iff the value's first byte starts `true` or `false`."""
        self._check()
        var b = self._first_byte()
        return b == _LOWER_T or b == _LOWER_F

    @always_inline("nodebug")
    def is_object(self) -> Bool:
        """Return True iff the value's first byte opens a JSON object (`{`)."""
        self._check()
        return self._first_byte() == _LBRACE

    @always_inline("nodebug")
    def is_array(self) -> Bool:
        """Return True iff the value's first byte opens a JSON array (`[`)."""
        self._check()
        return self._first_byte() == _LBRACK

    @no_inline
    def get_object(self) raises -> Object[Self.o]:
        """Descend into this value as a JSON object; raise if it is not one.

        If the value's first byte is `'{'`, returns an `Object` borrowing
        the SAME parser (sharing this value's origin `o`), positioned at the
        nested object's first key — `_start_si = self._si + 1`. For an empty
        object `{}` that index is its `'}'`, so the handle iterates zero fields
        and `field` raises. Because `field`/`next_field` skip nested
        values depth-aware, the returned handle stops at this object's OWN `'}'`.
        Raises if the value is not an object, so a non-object never yields a
        handle that would navigate unrelated structure.
        """
        self._check()
        if self._first_byte() != _LBRACE:
            raise Error("get_object: value is not an object")
        return Object[Self.o](
            self._reader[], self._si + 1, self._gen
        )

    @no_inline
    def get_array(self) raises -> Array[Self.o]:
        """Descend into this value as a JSON array; raise if it is not one.

        If the value's first byte is `'['`, returns an `Array` borrowing
        the SAME parser (sharing this value's origin `o`), positioned at the
        array's first element — `start_si = self._si + 1`. For an empty array
        `[]` that index is its `']'`, so the handle is immediately `at_end` and
        iterates zero elements. Raises if the value is not an array, so a
        non-array never yields a handle that would navigate unrelated structure.
        """
        self._check()
        if self._first_byte() != _LBRACK:
            raise Error("get_array: value is not an array")
        return Array[Self.o](
            self._reader[], self._si + 1, self._gen
        )

    @no_inline
    def as_int(self) raises -> Optional[Int64]:
        """Some(Int64) for an in-range integer; None for a non-number or a clean
        float (wrong kind); raises on a parse-step-malformed number (Gate 0),
        trailing junk (Gate 1), or a UINT64 above Int64.MAX. Does NOT delegate to
        get_int (which checks the tag before _scalar_token_ok)."""
        self._check()
        if not self.is_number():
            return None
        ref p = self._reader[]._parser
        var input_len = self._reader[]._input_len
        var pos = Int(p.positions[self._si])
        var r = _parse_number(p.padded.unsafe_ptr() + pos, input_len - pos)
        if not _scalar_token_ok(p.padded.unsafe_ptr(), pos, r.bytes_consumed, input_len):
            raise Error("as_int: trailing characters after number")
        if r.tag == TAG_FLOAT64:
            return None
        if r.tag == TAG_UINT64 and r.value > UInt64(0x7FFF_FFFF_FFFF_FFFF):
            raise Error("as_int: integer out of Int64 range")
        return Optional(bitcast[DType.int64](r.value))

    @no_inline
    def as_uint(self) raises -> Optional[UInt64]:
        """Some(UInt64) for a non-negative integer; None for a non-number, a clean
        float, or a negative integer (wrong kind); raises on parse-step-malformed
        (Gate 0) or trailing junk (Gate 1)."""
        self._check()
        if not self.is_number():
            return None
        ref p = self._reader[]._parser
        var input_len = self._reader[]._input_len
        var pos = Int(p.positions[self._si])
        var r = _parse_number(p.padded.unsafe_ptr() + pos, input_len - pos)
        if not _scalar_token_ok(p.padded.unsafe_ptr(), pos, r.bytes_consumed, input_len):
            raise Error("as_uint: trailing characters after number")
        if r.tag == TAG_FLOAT64:
            return None
        if r.tag == TAG_INT64:
            var signed = bitcast[DType.int64](r.value)
            if signed < 0:
                return None
            return Optional(UInt64(signed))
        return Optional(r.value)

    @no_inline
    def as_float(self) raises -> Optional[Float64]:
        """Some(Float64) for any number; None for a non-number; raises on
        parse-step-malformed (Gate 0) or trailing junk (Gate 1)."""
        self._check()
        if not self.is_number():
            return None
        ref p = self._reader[]._parser
        var input_len = self._reader[]._input_len
        var pos = Int(p.positions[self._si])
        var r = _parse_number(p.padded.unsafe_ptr() + pos, input_len - pos)
        if not _scalar_token_ok(p.padded.unsafe_ptr(), pos, r.bytes_consumed, input_len):
            raise Error("as_float: trailing characters after number")
        if r.tag == TAG_FLOAT64:
            return Optional(bitcast[DType.float64](r.value))
        if r.tag == TAG_INT64:
            return Optional(Float64(bitcast[DType.int64](r.value)))
        return Optional(Float64(r.value))

    def as_string(self) raises -> Optional[String]:
        """Some(String) if a string; None otherwise. A malformed string (bad escape
        / invalid UTF-8) raises via get_string — never masked as None."""
        self._check()
        if not self.is_string():
            return None
        return Optional(self.get_string())

    def as_bool(self) raises -> Optional[Bool]:
        """Some(Bool) if a bool; None otherwise. A malformed literal raises via
        get_bool — never masked as None."""
        self._check()
        if not self.is_bool():
            return None
        return Optional(self.get_bool())

    def field(self, key: String) raises -> Value[Self.o]:
        """Object field by key (forward scan). Convenience for get_object().field(key).

        Delegates to `get_object().field(key)`, so a non-object value raises
        cleanly via `get_object` and the matched value shares this value's
        origin (the chained `Value[Self.o]` types unify on `Self.o`). Like the
        DOM `Value.field`, the lookup is a left-to-right depth-aware key scan.
        """
        return self.get_object().field(key)

    def elem(self, idx: Int) raises -> Value[Self.o]:
        """Array element by index (forward skip; O(idx) — On-Demand arrays are forward-only).

        Delegates to `get_array()` (which raises on a non-array), then advances
        the cursor past `idx` elements before yielding the `idx`-th. The forward
        skip is O(idx) because On-Demand arrays are single-pass — there is no
        random access into the structural index. Checks `at_end()` before each
        advance and before the final yield, so an out-of-range `idx` raises
        INDEX_ERROR instead of landing the cursor on the array's `']'` and
        returning a junk `Value`.
        """
        var arr = self.get_array()
        var i = 0
        while i < idx:
            if arr.at_end():
                raise "INDEX_ERROR: array index out of range"
            _ = arr.next_element()
            i += 1
        if arr.at_end():
            raise "INDEX_ERROR: array index out of range"
        return arr.next_element()

    def has_field(self, key: String) raises -> Bool:
        """True iff this object value has `key`. Delegates to get_object() (raises
        on a non-object — DOM parity; safe because get_object raises only on a type
        mismatch and has no not-found string-signal to match)."""
        return self.get_object().has_field(key)

    def try_field(self, key: String) raises -> Optional[Value[Self.o]]:
        """Some(value) if present, None if absent; raises if not an object."""
        return self.get_object().try_field(key)

    def try_elem(self, idx: Int) raises -> Optional[Value[Self.o]]:
        """Some(element) if `idx` is in range, None if out of range; raises if not
        an array. Reimplements the forward scan (like elem) and returns None at the
        at-end boundary — no try/except, no INDEX_ERROR string match. A malformed
        element surfaces later at the get_* call, not here."""
        var arr = self.get_array()
        var i = 0
        while i < idx:
            if arr.at_end():
                return None
            _ = arr.next_element()
            i += 1
        if arr.at_end():
            return None
        return Optional(arr.next_element())

    def __getitem__(self, key: String) raises -> Value[Self.o]:
        """Object field by key — `value["k"]` is sugar for `value.field("k")`."""
        return self.field(key)

    def __getitem__(self, idx: Int) raises -> Value[Self.o]:
        """Array element by index — `value[i]` is sugar for `value.elem(i)`."""
        return self.elem(idx)


@no_inline
def _skip_value(
    ip: UnsafePointer[UInt8, _],
    positions: List[UInt32],
    n: Int,
    value_si: Int,
) -> Int:
    """Return the structural index just past the value starting at `value_si`.

    The single depth-aware skip shared by `Object` and `Array`, so
    both advance past a value (and never descend into its interior) identically.
    `n` is `len(positions)` and `ip` is the padded-input pointer.

    - Object/array (`'{'`/`'['`): scan forward counting nesting depth (+1 on
      `'{'`/`'['`, -1 on `'}'`/`']'`); return the index AFTER the matching close.
      If the scan runs off the end (truncated input), return `n`.
    - String (`'"'`): two structurals (open + close), so `value_si + 2`.
    - Number/literal: a single structural, so `value_si + 1`.

    Bounds-safe: a `value_si >= n` (truncated: no value) returns `n` without
    reading positions out of range.
    """
    if value_si >= n:
        return n  # truncated: no value at this index
    var vb = ip[Int(positions[value_si])]
    if vb == _LBRACE or vb == _LBRACK:
        var depth = 0
        var si = value_si
        while si < n:
            var ch = ip[Int(positions[si])]
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


@always_inline("nodebug")
def _unescaped_key_into(
    ip: UnsafePointer[UInt8, _],
    key_pos: Int,
    input_len: Int,
    mut scratch: List[UInt8],
) raises -> String:
    """Unescape the key string opening at `ip[key_pos]` and return it as a String.

    Reuses `parse_string` (which writes `[u32 len LE][bytes]` into `scratch`,
    growing it to `input_len + 64` first), then reads the length prefix and the
    UTF-8 bytes back. Shared by `field`'s escaped-key compare and
    `Field.key()` so both unescape identically.
    """
    var needed = input_len + 64  # parse_string requires input_len + 64
    if len(scratch) < needed:
        scratch = List[UInt8](unsafe_uninit_length=needed)
    _ = parse_string(ip, key_pos, input_len, scratch.unsafe_ptr(), 0)
    var sp = scratch.unsafe_ptr()
    var ln = Int(
        UInt32(sp[0])
        | (UInt32(sp[1]) << 8)
        | (UInt32(sp[2]) << 16)
        | (UInt32(sp[3]) << 24)
    )
    return String(StringSlice(ptr=sp + 4, length=ln))


struct Field[o: Origin[mut=True]](Movable):
    """A single top-level object field (key + value) yielded by forward iteration.

    Borrows the owning `Reader` directly through an origin-tracked pointer (a
    1-hop chain, like `Value`), recording the structural indices of the
    key's open quote and of its value. `key()` returns the UNESCAPED key;
    `value()` hands back a `Value` at the value.

    Lifetime: a `Field` (and the `Value` it yields) is live only until the
    issuing `Object` cursor advances again (the next `next_field`) — the
    cursor is forward-only and the unescape scratch is shared. Read the field's
    key/value before calling `next_field` again. Like all on-demand handles it is
    also valid only while the `Reader` is alive and is neither reparsed nor moved.
    """

    var _reader: Pointer[Reader, Self.o]
    var _key_si: Int     # structural index of the key's open quote
    var _value_si: Int   # structural index of the value (key_si + 3)
    var _gen: Int        # the Reader's generation at construction

    def __init__(
        out self,
        ref [Self.o] reader: Reader,
        key_si: Int,
        value_si: Int,
        gen: Int,
    ):
        """Borrow `reader`; record the key/value structural indices and generation."""
        self._reader = Pointer(to=reader)
        self._key_si = key_si
        self._value_si = value_si
        self._gen = gen

    def __init__(out self, *, deinit take: Self):
        """Move constructor: transfer the borrowed-reader pointer and fields."""
        self._reader = take._reader
        self._key_si = take._key_si
        self._value_si = take._value_si
        self._gen = take._gen

    @always_inline("nodebug")
    def _check(self):
        debug_assert(
            self._gen == self._reader[]._gen, "stale on-demand handle used after reparse"
        )

    @no_inline
    def key(self) raises -> String:
        """Return this field's UNESCAPED key as an owned String.

        Unescapes the key string via the shared `parse_string` (handling JSON
        escapes correctly), into the parser's reusable on-demand scratch buffer.
        Note the scratch is shared with `value().get_string()`: call `key()`
        before reading a sibling string value if both are needed.
        """
        self._check()
        ref p = self._reader[]._parser
        var key_pos = Int(p.positions[self._key_si])
        return _unescaped_key_into(
            p.padded.unsafe_ptr(), key_pos, self._reader[]._input_len, p._od_scratch
        )

    @always_inline("nodebug")
    def value(self) -> Value[Self.o]:
        """Return a `Value` at this field's value, sharing this origin."""
        self._check()
        return Value[Self.o](self._reader[], self._value_si, self._gen)


struct Object[o: Origin[mut=True]](Movable):
    """Forward navigator over a flat top-level JSON object.

    Borrows the owning `Reader` through an origin-tracked pointer (reaching the
    underlying `Parser` as `self._reader[]._parser`). Two ways to read fields:

    - `field(key)` re-scans the object's structural positions left to right
      from the start (independent of the cursor) and returns a `Value` at
      the matched key's value, unified with this handle's origin so the whole
      borrow chain shares one lifetime root.
    - Forward iteration via `at_end()` / `next_field()`, which walk the
      TOP-LEVEL fields in document order using a mutable cursor `_si`. Each
      `next_field` advances the cursor PAST the value (depth-aware, skipping
      nested containers) and yields a `Field`. Forward-only: a yielded `Field`
      is live until the cursor advances again.

    `field` is cursor-independent, so the two styles do not interfere.
    Valid only while the `Reader` is alive and is neither reparsed nor moved.
    """

    var _reader: Pointer[Reader, Self.o]
    var _start_si: Int  # this object's first key (or its '}' if empty)
    var _si: Int  # forward-iteration cursor: a key in this object, or its '}'
    var _gen: Int  # the Reader's generation at construction

    def __init__(out self, ref [Self.o] reader: Reader, start_si: Int, gen: Int):
        """Borrow `reader` as a cursor over the object whose first key is `start_si`.

        `start_si` is the structural index of this object's first key — for the
        ROOT object that is 1 (positions[0] is the root `'{'`); for a nested
        object it is the index just past its opening `'{'`. For an EMPTY object
        `start_si` is the object's own `'}'`, so iteration yields zero fields and
        `field` finds nothing. The forward-iteration cursor `_si` starts at
        `start_si`.
        """
        self._reader = Pointer(to=reader)
        self._start_si = start_si
        self._si = start_si
        self._gen = gen

    def __init__(out self, *, deinit take: Self):
        """Move constructor: transfer the borrowed-reader pointer, cursor, generation."""
        self._reader = take._reader
        self._start_si = take._start_si
        self._si = take._si
        self._gen = take._gen

    @always_inline("nodebug")
    def _check(self):
        debug_assert(
            self._gen == self._reader[]._gen, "stale on-demand handle used after reparse"
        )

    @no_inline
    def _skip_value(self, value_si: Int) -> Int:
        """Return the structural index just past the value starting at `value_si`.

        Thin wrapper over the shared module-level `_skip_value`, which is
        depth-aware so the cursor never descends into a nested value's interior.
        Behaviour is identical to the prior in-struct implementation.
        """
        ref p = self._reader[]._parser
        return _skip_value(
            p.padded.unsafe_ptr(), p.positions, len(p.positions), value_si
        )

    @no_inline
    def at_end(self) -> Bool:
        """Return True when the forward cursor is past the last top-level field.

        True when the cursor `_si` has reached the root `'}'`, run off the end of
        the positions list (truncated input), or landed on a position that is not
        the open quote of a complete key (no closing-quote structural at `_si+1`).
        In all those cases `next_field` would have nothing well-formed to yield.
        """
        self._check()
        ref p = self._reader[]._parser
        var n = len(p.positions)
        if self._si >= n:
            return True
        var b = p.padded.unsafe_ptr()[Int(p.positions[self._si])]
        if b == _RBRACE:
            return True
        # A complete top-level key needs its closing-quote structural at _si+1;
        # if that is missing the object is exhausted/truncated — treat as end so
        # callers never read positions out of bounds.
        if self._si + 1 >= n:
            return True
        return False

    @no_inline
    def next_field(mut self) raises -> Field[Self.o]:
        """Advance the forward cursor past one top-level field and yield it.

        Precondition: `at_end()` is False (the cursor is at a complete top-level
        key). Captures `(key_si, value_si = key_si + 3)`, advances the cursor PAST
        the whole value via the depth-aware `_skip_value` (so nested containers
        are skipped wholesale, never descended), then past a following comma, and
        returns a `Field` borrowing the parser. Raises if the key has no value
        (truncated input) rather than yielding a `Field` whose value index is out
        of bounds. Forward-only: the yielded `Field` is live until the next call.
        """
        self._check()
        ref p = self._reader[]._parser
        var ip = p.padded.unsafe_ptr()
        var n = len(p.positions)
        var key_si = self._si
        var value_si = key_si + 3
        if value_si >= n:
            raise Error("next_field: top-level key has no value")
        # Advance the cursor past the value (depth-aware) and an optional comma.
        var nxt = self._skip_value(value_si)
        if nxt < n and ip[Int(p.positions[nxt])] == _COMMA:
            nxt += 1
        self._si = nxt
        return Field[Self.o](self._reader[], key_si, value_si, self._gen)

    @no_inline
    def _find_value_si(self, key: String) raises -> Int:
        """Forward depth-aware, escape-aware scan for `key` from `_start_si`; return
        its value's structural index, or -1 if absent. Shared by field/has_field/
        try_field. Propagates a malformed candidate-key raise (bad escape via
        parse_string) — never masks it as 'absent'. Raises if a matched key has no
        value (truncated input).

        Walks this object's KEY→VALUE pairs left to right from `_start_si`,
        DEPTH-AWARE: each key is a string at `si` (close quote at `si+1`, `':'`
        at `si+2`, value at `si+3`); after a non-matching pair the cursor jumps
        past the whole value via `_skip_value`, so nested objects/arrays are
        skipped wholesale and their interior keys never masquerade as this
        object's keys (which also makes the scan stop at THIS object's own `'}'`,
        a nested `'}'` always sitting inside a skipped value). On a key match,
        returns the value's structural index (`si+3`), raising if that value is
        missing (truncated input) rather than indexing past the positions list.
        Keys are matched ESCAPE-AWARE: a candidate key with no backslash is
        byte-compared on the fast path; a candidate with an escape is unescaped
        (via `parse_string`) and compared to the search key (which is a normal,
        already-unescaped Mojo String).
        """
        self._check()
        ref p = self._reader[]._parser
        var input_len = self._reader[]._input_len
        var ip = p.padded.unsafe_ptr()
        var n = len(p.positions)
        var si = self._start_si  # this object's first key (root: 1, past '{')
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
            # Fast path: a candidate key with no backslash can be byte-compared
            # directly against the (already-unescaped) search key. A candidate
            # with an escape must be unescaped before comparison — its raw byte
            # span is longer than its decoded form.
            var has_escape = False
            for k in range(klen):
                if ip[pos + 1 + k] == _BACKSLASH:
                    has_escape = True
                    break
            var matched: Bool
            if has_escape:
                var decoded = _unescaped_key_into(
                    ip, pos, input_len, p._od_scratch
                )
                matched = decoded == key
            else:
                matched = klen == key.byte_length()
                if matched:
                    var kb = key.as_bytes()
                    for k in range(klen):
                        if ip[pos + 1 + k] != kb[k]:
                            matched = False
                            break
            if matched:
                if value_si >= n:
                    raise Error("field has no value: " + key)
                return value_si
            si = self._skip_value(value_si)  # depth-aware advance past the value
            if si < n and ip[Int(p.positions[si])] == _COMMA:
                si += 1
        return -1

    @no_inline
    def field(self, key: String) raises -> Value[Self.o]:
        """Find the value for `key` in this object; raise if absent. Scan logic in
        `_find_value_si` (escape-aware, depth-aware, left to right from start)."""
        var vsi = self._find_value_si(key)
        if vsi < 0:
            raise Error("field not found: " + key)
        return Value[Self.o](self._reader[], vsi, self._gen)

    @no_inline
    def has_field(self, key: String) raises -> Bool:
        """True iff `key` is present (forward re-scan, cursor-independent). False
        ONLY on a clean absence; a malformed candidate key propagates its raise."""
        return self._find_value_si(key) >= 0

    @no_inline
    def try_field(self, key: String) raises -> Optional[Value[Self.o]]:
        """Some(value) if present, None if absent (clean). Reimplements via
        _find_value_si — no try/except, no message-string match; a malformed
        candidate key propagates."""
        var vsi = self._find_value_si(key)
        if vsi < 0:
            return None
        return Optional(Value[Self.o](self._reader[], vsi, self._gen))


struct Array[o: Origin[mut=True]](Movable):
    """Forward navigator over a JSON array's elements.

    Borrows the owning `Reader` through an origin-tracked pointer (mirroring
    `Object`; reaching the underlying `Parser` as `self._reader[]._parser`). A
    mutable cursor `_si` walks the array's ELEMENT structural positions in
    document order; it starts at the array's first element — or at the array's
    `']'` if the array is empty. Each `next_element` advances the cursor PAST one
    element (depth-aware via the shared `_skip_value`, so nested objects/arrays
    are skipped wholesale, never descended) and a following comma, then yields a
    `Value` at the captured element index.

    Lifetime: a yielded `Value` borrows the same reader and shares this
    handle's origin `o`; independent aliasing handles are OK (Mojo origins are
    lifetime, not exclusivity), so a nested element can be navigated through its
    own `get_object()` / `get_array()` while this handle is alive. Valid only
    while the `Reader` is alive and is neither reparsed nor moved.
    """

    var _reader: Pointer[Reader, Self.o]
    var _si: Int  # cursor: this array's current element, or its ']' when at end
    var _gen: Int  # the Reader's generation at construction

    def __init__(out self, ref [Self.o] reader: Reader, start_si: Int, gen: Int):
        """Borrow `reader` as a cursor over the array whose first element is `start_si`.

        `start_si` is the structural index of this array's first element — for an
        array opened at value index `v`, that is `v + 1` (one past its `'['`).
        For an EMPTY array `start_si` is the array's own `']'`, so `at_end` is
        immediately True and iteration yields zero elements.
        """
        self._reader = Pointer(to=reader)
        self._si = start_si
        self._gen = gen

    def __init__(out self, *, deinit take: Self):
        """Move constructor: transfer the borrowed-reader pointer, cursor, generation."""
        self._reader = take._reader
        self._si = take._si
        self._gen = take._gen

    @always_inline("nodebug")
    def _check(self):
        debug_assert(
            self._gen == self._reader[]._gen, "stale on-demand handle used after reparse"
        )

    @no_inline
    def at_end(self) -> Bool:
        """Return True when the cursor is past the last element of this array.

        True when the cursor `_si` has reached the array's `']'` or run off the
        end of the positions list (truncated input). In both cases
        `next_element` would have nothing well-formed to yield, so callers never
        read positions out of bounds.
        """
        self._check()
        ref p = self._reader[]._parser
        var n = len(p.positions)
        if self._si >= n:
            return True
        return p.padded.unsafe_ptr()[Int(p.positions[self._si])] == _RBRACK

    @no_inline
    def next_element(mut self) raises -> Value[Self.o]:
        """Advance the cursor past one element and yield it.

        Precondition: `at_end()` is False (the cursor is at a real element).
        Captures the current element's structural index, advances the cursor PAST
        the whole element via the shared depth-aware `_skip_value` (so nested
        containers are skipped wholesale, never descended), then past a following
        comma, and returns a `Value` at the captured index. Bounds-safe: a
        cursor already off the end of the positions list raises rather than
        reading out of range on truncated input. Forward-only.
        """
        self._check()
        ref p = self._reader[]._parser
        var ip = p.padded.unsafe_ptr()
        var n = len(p.positions)
        var elem_si = self._si
        if elem_si >= n:
            raise Error("next_element: cursor past end of array")
        # Advance the cursor past this element (depth-aware) and an optional comma.
        var nxt = _skip_value(ip, p.positions, n, elem_si)
        if nxt < n and ip[Int(p.positions[nxt])] == _COMMA:
            nxt += 1
        self._si = nxt
        return Value[Self.o](self._reader[], elem_si, self._gen)
