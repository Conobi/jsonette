"""Value: the user-facing, zero-copy DOM accessor over a Document's tape.

`Value` is a lightweight view — a pointer to the owning `Document`, a tape index,
and the generation it was created at — so it allocates nothing and copies
cheaply. Type predicates (`is_object`, `is_string`, ...) read the tag at the
current tape index; typed getters (`get_int`, `get_string`, ...) read and decode
the value, raising on a type mismatch; `as_*` variants return `Optional` instead
of raising. Navigation (`field`/`elem` and their `[]` sugar, plus the
`fields()`/`elems()` iterators) walks the tape via `_skip_value`.

Every access first runs `_check`, which traps use of a `Value` whose generation
no longer matches the Document's — i.e. use after a `reparse` — under
`-D ASSERT=all`. The `o` origin parameter binds the view's lifetime to the
Document so the borrow checker forbids it from outliving the source.

This module also defines the supporting `_Entry`, `_FieldIter`, and `_ElemIter`
iteration helpers and the `_skip_value` tape-skip primitive.
"""

from std.collections import Optional
from std.memory import bitcast
from jsonette.tape import TAG_OBJECT_OPEN, TAG_ARRAY_OPEN, TAG_STRING, TAG_INT64, TAG_UINT64, TAG_FLOAT64, TAG_TRUE, TAG_FALSE, TAG_NULL
from jsonette.document import Document


struct Value[o: Origin[mut=True]](Copyable, Movable):
    """A self-bound zero-copy view into a Document's tape (no doc-threading)."""

    var _doc: Pointer[Document, Self.o]
    var _idx: Int
    var _gen: Int

    def __init__(out self, ref [Self.o] doc: Document, idx: Int, gen: Int):
        self._doc = Pointer(to=doc)
        self._idx = idx
        self._gen = gen

    def __init__(out self, *, deinit move: Self):
        self._doc = move._doc
        self._idx = move._idx
        self._gen = move._gen

    @always_inline("nodebug")
    def _check(self):
        debug_assert(self._gen == self._doc[]._gen, "stale Value used after reparse")

    @always_inline("nodebug")
    def _elem(self, i: Int) -> UInt64:
        return self._doc[]._parser._tape.elements.unsafe_get(i)

    @always_inline("nodebug")
    def _sbuf(self, i: Int) -> UInt8:
        return self._doc[]._parser._tape.string_buf.unsafe_get(i)

    @always_inline("nodebug")
    def _tag(self) -> UInt8:
        self._check()
        return UInt8(self._elem(self._idx) >> 56)

    @always_inline("nodebug")
    def _payload(self) -> UInt64:
        return self._elem(self._idx) & 0x00FFFFFFFFFFFFFF

    @always_inline("nodebug")
    def _strlen_at(self, offset: Int) -> Int:
        return Int(
            UInt32(self._sbuf(offset))
            | (UInt32(self._sbuf(offset + 1)) << 8)
            | (UInt32(self._sbuf(offset + 2)) << 16)
            | (UInt32(self._sbuf(offset + 3)) << 24)
        )

    def is_object(self) -> Bool:
        """True iff this value is a JSON object."""
        return self._tag() == TAG_OBJECT_OPEN
    def is_array(self) -> Bool:
        """True iff this value is a JSON array."""
        return self._tag() == TAG_ARRAY_OPEN
    def is_string(self) -> Bool:
        """True iff this value is a JSON string."""
        return self._tag() == TAG_STRING
    def is_int(self) -> Bool:
        """True iff this value is a signed-integer tape entry (negative integers).

        Non-negative integers carry `TAG_UINT64`, so test `is_uint` (or `is_number`)
        for those; `is_int` alone is not "is it an integer".
        """
        return self._tag() == TAG_INT64
    def is_uint(self) -> Bool:
        """True iff this value is an unsigned-integer tape entry (non-negative integers, incl. 0)."""
        return self._tag() == TAG_UINT64
    def is_float(self) -> Bool:
        """True iff this value is a floating-point tape entry."""
        return self._tag() == TAG_FLOAT64
    def is_number(self) -> Bool:
        """True iff this value is any JSON number (signed int, unsigned int, or float)."""
        var t = self._tag()
        return t == TAG_INT64 or t == TAG_UINT64 or t == TAG_FLOAT64
    def is_bool(self) -> Bool:
        """True iff this value is a JSON boolean (true or false)."""
        var t = self._tag()
        return t == TAG_TRUE or t == TAG_FALSE
    def is_null(self) -> Bool:
        """True iff this value is JSON null."""
        return self._tag() == TAG_NULL

    def get_bool(self) raises -> Bool:
        """Read this value as a Bool. Raises if it is not a JSON boolean."""
        var t = self._tag()
        if t == TAG_TRUE: return True
        if t == TAG_FALSE: return False
        raise "TAPE_ERROR: expected bool"

    def get_uint(self) raises -> UInt64:
        """Read this value as a UInt64. Raises unless it is an unsigned-integer entry.

        Only accepts `TAG_UINT64` (non-negative integers); a negative integer
        (`TAG_INT64`) raises. Use `get_int` to read across both integer tags.
        """
        if self._tag() != TAG_UINT64: raise "TAPE_ERROR: expected uint64"
        return self._elem(self._idx + 1)

    def get_int(self) raises -> Int64:
        """Read any in-range integer as Int64.

        Accepts both `TAG_INT64` (negatives) and `TAG_UINT64` (non-negatives,
        including 0). Raises if the value is not an integer, or if a `TAG_UINT64`
        magnitude exceeds `Int64.MAX` (cannot be represented as Int64).
        """
        var t = self._tag()
        if t == TAG_INT64:
            return Int64(bitcast[DType.int64](SIMD[DType.uint64, 1](self._elem(self._idx + 1))))
        if t == TAG_UINT64:
            var u = self._elem(self._idx + 1)
            if u > UInt64(0x7FFF_FFFF_FFFF_FFFF):
                raise "TAPE_ERROR: integer out of Int64 range"
            return Int64(bitcast[DType.int64](SIMD[DType.uint64, 1](u)))
        raise "TAPE_ERROR: expected integer"

    def get_float(self) raises -> Float64:
        """Read any JSON number as Float64.

        Widens across all numeric tags: `TAG_FLOAT64` is returned as-is, while
        `TAG_INT64` and `TAG_UINT64` are converted to Float64. Raises if the
        value is not a number.
        """
        var t = self._tag()
        if t == TAG_FLOAT64:
            return Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](self._elem(self._idx + 1))))
        if t == TAG_INT64:
            return Float64(Int64(bitcast[DType.int64](SIMD[DType.uint64, 1](self._elem(self._idx + 1)))))
        if t == TAG_UINT64:
            return Float64(self._elem(self._idx + 1))
        raise "TAPE_ERROR: expected number"

    def get_string_length(self) raises -> Int:
        """Return the byte length of this string's (already-unescaped) content.

        Reads the 4-byte length prefix from the string buffer without copying the
        bytes out. Raises if this value is not a string.
        """
        if self._tag() != TAG_STRING: raise "TAPE_ERROR: expected string"
        return self._strlen_at(Int(self._payload()))

    def get_string(self) raises -> String:
        """Copy this string's content out as an owned `String`.

        The bytes are the already-unescaped UTF-8 content held in the document's
        string buffer; this allocates a fresh `String` (the only copy on the read
        path). Raises if this value is not a string. For a non-allocating compare,
        use `string_eq`.
        """
        if self._tag() != TAG_STRING: raise "TAPE_ERROR: expected string"
        var offset = Int(self._payload())
        var str_len = self._strlen_at(offset)
        var buf = List[UInt8](capacity=str_len)
        for i in range(str_len):
            buf.append(self._sbuf(offset + 4 + i))
        return String(from_utf8=buf^)

    def string_eq(self, expected: String) raises -> Bool:
        """Compare this string's content to `expected` without allocating.

        Checks length then bytes directly against the document's string buffer, so
        no `String` is materialised (unlike `get_string`). Raises if this value is
        not a string.
        """
        if self._tag() != TAG_STRING: raise "TAPE_ERROR: expected string"
        var offset = Int(self._payload())
        var str_len = self._strlen_at(offset)
        var eb = expected.as_bytes()
        if str_len != len(eb): return False
        for i in range(str_len):
            if self._sbuf(offset + 4 + i) != eb[i]: return False
        return True

    def field(self, key: String) raises -> Value[Self.o]:
        """Object key lookup (O(n) scan). Raises if absent or not an object."""
        if self._tag() != TAG_OBJECT_OPEN: raise "TAPE_ERROR: expected object for key lookup"
        var i = self._idx + 1
        var close_plus_one = Int(self._payload() & 0xFFFFFFFF)
        while i < close_plus_one - 1:
            var key_tag = UInt8(self._elem(i) >> 56)
            if key_tag != TAG_STRING: raise "TAPE_ERROR: expected string key in object"
            var offset = Int(self._elem(i) & 0x00FFFFFFFFFFFFFF)
            var key_len = self._strlen_at(offset)
            var eb = key.as_bytes()
            var is_match = key_len == len(eb)
            if is_match:
                for j in range(key_len):
                    if self._sbuf(offset + 4 + j) != eb[j]:
                        is_match = False
                        break
            var val_idx = i + 1
            if is_match:
                return Value[Self.o](self._doc[], val_idx, self._gen)
            i = _skip_value(self._doc[], val_idx)
        raise "KEY_NOT_FOUND: '" + key + "'"

    def has_field(self, key: String) raises -> Bool:
        """True iff `key` exists (no raise on absence)."""
        if self._tag() != TAG_OBJECT_OPEN: raise "TAPE_ERROR: expected object"
        var i = self._idx + 1
        var close_plus_one = Int(self._payload() & 0xFFFFFFFF)
        while i < close_plus_one - 1:
            var key_tag = UInt8(self._elem(i) >> 56)
            if key_tag != TAG_STRING: raise "TAPE_ERROR: expected string key in object"
            var offset = Int(self._elem(i) & 0x00FFFFFFFFFFFFFF)
            var key_len = self._strlen_at(offset)
            var eb = key.as_bytes()
            var is_match = key_len == len(eb)
            if is_match:
                for j in range(key_len):
                    if self._sbuf(offset + 4 + j) != eb[j]:
                        is_match = False
                        break
            if is_match: return True
            i = _skip_value(self._doc[], i + 1)
        return False

    def elem(self, idx: Int) raises -> Value[Self.o]:
        """Array element by index (O(n) skip). Raises if out of range or not an array."""
        if self._tag() != TAG_ARRAY_OPEN: raise "TAPE_ERROR: expected array for index access"
        var i = self._idx + 1
        var close_plus_one = Int(self._payload() & 0xFFFFFFFF)
        var current = 0
        while i < close_plus_one - 1:
            if current == idx:
                return Value[Self.o](self._doc[], i, self._gen)
            i = _skip_value(self._doc[], i)
            current += 1
        raise "INDEX_ERROR: index " + String(idx) + " out of range"

    def len(self) raises -> Int:
        """Element count of this container (object members or array elements)."""
        var t = self._tag()
        if t != TAG_OBJECT_OPEN and t != TAG_ARRAY_OPEN: raise "TAPE_ERROR: expected container for len"
        return Int((self._payload() >> 32) & 0xFFFFFF)

    def __getitem__(self, key: String) raises -> Value[Self.o]:
        """Sugar for object key lookup: `value["key"]`."""
        return self.field(key)

    def __getitem__(self, idx: Int) raises -> Value[Self.o]:
        """Sugar for array element access: `value[idx]`."""
        return self.elem(idx)

    def fields(self) raises -> _FieldIter[Self.o]:
        """Iterate object (key, value) entries in document order."""
        if self._tag() != TAG_OBJECT_OPEN: raise "TAPE_ERROR: expected object to iterate fields"
        var close_plus_one = Int(self._payload() & 0xFFFFFFFF)
        return _FieldIter[Self.o](self._doc, self._idx + 1, close_plus_one, self._gen)

    def elems(self) raises -> _ElemIter[Self.o]:
        """Iterate array elements in document order."""
        if self._tag() != TAG_ARRAY_OPEN: raise "TAPE_ERROR: expected array to iterate elements"
        var close_plus_one = Int(self._payload() & 0xFFFFFFFF)
        return _ElemIter[Self.o](self._doc, self._idx + 1, close_plus_one, self._gen)

    def try_field(self, key: String) raises -> Optional[Value[Self.o]]:
        """Some(value) if `key` is present (even a JSON null), None if absent;
        raises if the receiver is not an object (via has_field)."""
        if self.has_field(key):
            return Optional(self.field(key))
        return None

    def try_elem(self, idx: Int) raises -> Optional[Value[Self.o]]:
        """Some(element) if `idx` is in range, None if out of range; raises if the
        receiver is not an array."""
        if self._tag() != TAG_ARRAY_OPEN: raise "TAPE_ERROR: expected array for index access"
        var i = self._idx + 1
        var close_plus_one = Int(self._payload() & 0xFFFFFFFF)
        var current = 0
        while i < close_plus_one - 1:
            if current == idx:
                return Optional(Value[Self.o](self._doc[], i, self._gen))
            i = _skip_value(self._doc[], i)
            current += 1
        return None

    def as_int(self) raises -> Optional[Int64]:
        """Some(Int64) if this is an integer; None for any non-integer kind; raises
        only on a UINT64 above Int64.MAX. The is_int()-or-is_uint() guard spans BOTH
        integer tags to match the widened get_int acceptance set."""
        if self.is_int() or self.is_uint():
            return Optional(self.get_int())
        return None

    def as_uint(self) raises -> Optional[UInt64]:
        """Some(UInt64) if non-negative integer; None otherwise (negative -> None)."""
        if self.is_uint():
            return Optional(self.get_uint())
        return None

    def as_float(self) raises -> Optional[Float64]:
        """Some(Float64) if any number (get_float widens); None otherwise."""
        if self.is_number():
            return Optional(self.get_float())
        return None

    def as_string(self) raises -> Optional[String]:
        """Some(String) if a string; None otherwise."""
        if self.is_string():
            return Optional(self.get_string())
        return None

    def as_bool(self) raises -> Optional[Bool]:
        """Some(Bool) if a bool; None otherwise."""
        if self.is_bool():
            return Optional(self.get_bool())
        return None


struct _Entry[o: Origin[mut=True]](Copyable, Movable):
    """A single object entry: tape indices for a key and its value."""

    var _doc: Pointer[Document, Self.o]
    var _key_idx: Int
    var _val_idx: Int
    var _gen: Int

    def __init__(out self, doc: Pointer[Document, Self.o], key_idx: Int, val_idx: Int, gen: Int):
        self._doc = doc
        self._key_idx = key_idx
        self._val_idx = val_idx
        self._gen = gen

    def __init__(out self, *, deinit move: Self):
        self._doc = move._doc
        self._key_idx = move._key_idx
        self._val_idx = move._val_idx
        self._gen = move._gen

    def key(self) raises -> String:
        return Value[Self.o](self._doc[], self._key_idx, self._gen).get_string()

    def value(self) -> Value[Self.o]:
        return Value[Self.o](self._doc[], self._val_idx, self._gen)


struct _FieldIter[o: Origin[mut=True]](Copyable, Movable):
    """Forward iterator over an object's (key, value) entries."""

    var _doc: Pointer[Document, Self.o]
    var _i: Int
    var _end: Int
    var _gen: Int

    def __init__(out self, doc: Pointer[Document, Self.o], i: Int, end: Int, gen: Int):
        self._doc = doc
        self._i = i
        self._end = end
        self._gen = gen

    def __init__(out self, *, deinit move: Self):
        self._doc = move._doc
        self._i = move._i
        self._end = move._end
        self._gen = move._gen

    @always_inline("nodebug")
    def _check(self):
        debug_assert(self._gen == self._doc[]._gen, "stale iterator used after reparse")

    def __iter__(self) -> Self:
        return self.copy()

    def __has_next__(self) -> Bool:
        self._check()
        return self._i < self._end - 1

    def __next__(mut self) -> _Entry[Self.o]:
        self._check()
        var key_idx = self._i
        var val_idx = self._i + 1
        self._i = _skip_value(self._doc[], val_idx)
        return _Entry[Self.o](self._doc, key_idx, val_idx, self._gen)


struct _ElemIter[o: Origin[mut=True]](Copyable, Movable):
    """Forward iterator over an array's elements."""

    var _doc: Pointer[Document, Self.o]
    var _i: Int
    var _end: Int
    var _gen: Int

    def __init__(out self, doc: Pointer[Document, Self.o], i: Int, end: Int, gen: Int):
        self._doc = doc
        self._i = i
        self._end = end
        self._gen = gen

    def __init__(out self, *, deinit move: Self):
        self._doc = move._doc
        self._i = move._i
        self._end = move._end
        self._gen = move._gen

    @always_inline("nodebug")
    def _check(self):
        debug_assert(self._gen == self._doc[]._gen, "stale iterator used after reparse")

    def __iter__(self) -> Self:
        return self.copy()

    def __has_next__(self) -> Bool:
        self._check()
        return self._i < self._end - 1

    def __next__(mut self) -> Value[Self.o]:
        self._check()
        var idx = self._i
        self._i = _skip_value(self._doc[], idx)
        return Value[Self.o](self._doc[], idx, self._gen)


def _skip_value[o2: Origin[mut=True]](ref [o2] doc: Document, idx: Int) -> Int:
    """Tape index past the element at idx (preserves the prior skip_value)."""
    var entry = doc._parser._tape.elements.unsafe_get(idx)
    var tag = UInt8(entry >> 56)
    if tag == TAG_TRUE or tag == TAG_FALSE or tag == TAG_NULL or tag == TAG_STRING:
        return idx + 1
    if tag == TAG_INT64 or tag == TAG_UINT64 or tag == TAG_FLOAT64:
        return idx + 2
    if tag == TAG_OBJECT_OPEN or tag == TAG_ARRAY_OPEN:
        return Int(entry & 0xFFFFFFFF)
    return idx + 1
