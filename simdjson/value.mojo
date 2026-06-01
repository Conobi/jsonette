from std.memory import bitcast
from simdjson.tape import TAG_ROOT, TAG_OBJECT_OPEN, TAG_OBJECT_CLOSE, TAG_ARRAY_OPEN, TAG_ARRAY_CLOSE, TAG_STRING, TAG_INT64, TAG_UINT64, TAG_FLOAT64, TAG_TRUE, TAG_FALSE, TAG_NULL
from simdjson.document import Document


struct Value:
    """Lightweight tape index view into a Document."""
    var _idx: Int

    def __init__(out self, idx: Int):
        self._idx = idx

    # --- Internal helpers ---
    @always_inline("nodebug")
    def _tag[o: Origin[mut=True]](self, ref doc: Document[o]) -> UInt8:
        # Safety: idx comes from tape structure written by builder
        return UInt8(doc._tape[].elements.unsafe_get(self._idx) >> 56)

    @always_inline("nodebug")
    def _payload[o: Origin[mut=True]](self, ref doc: Document[o]) -> UInt64:
        # Safety: idx comes from tape structure written by builder
        return doc._tape[].elements.unsafe_get(self._idx) & 0x00FFFFFFFFFFFFFF

    # --- Type checks ---
    def is_object[o: Origin[mut=True]](self, ref doc: Document[o]) -> Bool:
        return self._tag(doc) == TAG_OBJECT_OPEN

    def is_array[o: Origin[mut=True]](self, ref doc: Document[o]) -> Bool:
        return self._tag(doc) == TAG_ARRAY_OPEN

    def is_string[o: Origin[mut=True]](self, ref doc: Document[o]) -> Bool:
        return self._tag(doc) == TAG_STRING

    def is_int[o: Origin[mut=True]](self, ref doc: Document[o]) -> Bool:
        return self._tag(doc) == TAG_INT64

    def is_uint[o: Origin[mut=True]](self, ref doc: Document[o]) -> Bool:
        return self._tag(doc) == TAG_UINT64

    def is_float[o: Origin[mut=True]](self, ref doc: Document[o]) -> Bool:
        return self._tag(doc) == TAG_FLOAT64

    def is_bool[o: Origin[mut=True]](self, ref doc: Document[o]) -> Bool:
        var t = self._tag(doc)
        return t == TAG_TRUE or t == TAG_FALSE

    def is_null[o: Origin[mut=True]](self, ref doc: Document[o]) -> Bool:
        return self._tag(doc) == TAG_NULL

    # --- Scalar getters ---
    def get_bool[o: Origin[mut=True]](self, ref doc: Document[o]) raises -> Bool:
        var t = self._tag(doc)
        if t == TAG_TRUE:
            return True
        if t == TAG_FALSE:
            return False
        raise "TAPE_ERROR: expected bool"

    def get_uint[o: Origin[mut=True]](self, ref doc: Document[o]) raises -> UInt64:
        if self._tag(doc) != TAG_UINT64:
            raise "TAPE_ERROR: expected uint64"
        # Safety: idx comes from tape structure written by builder
        return doc._tape[].elements.unsafe_get(self._idx + 1)

    def get_int[o: Origin[mut=True]](self, ref doc: Document[o]) raises -> Int64:
        if self._tag(doc) != TAG_INT64:
            raise "TAPE_ERROR: expected int64"
        # Safety: idx comes from tape structure written by builder
        return Int64(bitcast[DType.int64](SIMD[DType.uint64, 1](doc._tape[].elements.unsafe_get(self._idx + 1))))

    def get_float[o: Origin[mut=True]](self, ref doc: Document[o]) raises -> Float64:
        if self._tag(doc) != TAG_FLOAT64:
            raise "TAPE_ERROR: expected float64"
        # Safety: idx comes from tape structure written by builder
        return Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](doc._tape[].elements.unsafe_get(self._idx + 1))))

    def get_string_length[o: Origin[mut=True]](self, ref doc: Document[o]) raises -> Int:
        if self._tag(doc) != TAG_STRING:
            raise "TAPE_ERROR: expected string"
        var offset = Int(self._payload(doc))
        return Int(
            UInt32(doc._tape[].string_buf.unsafe_get(offset))
            | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 1)) << 8)
            | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 2)) << 16)
            | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 3)) << 24)
        )

    def get_string[o: Origin[mut=True]](self, ref doc: Document[o]) raises -> String:
        """Get string as an owned Mojo String. Raises if not a string."""
        if self._tag(doc) != TAG_STRING:
            raise "TAPE_ERROR: expected string"
        var offset = Int(self._payload(doc))
        var str_len = Int(
            UInt32(doc._tape[].string_buf.unsafe_get(offset))
            | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 1)) << 8)
            | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 2)) << 16)
            | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 3)) << 24)
        )
        var buf = List[UInt8](capacity=str_len)
        for i in range(str_len):
            buf.append(doc._tape[].string_buf.unsafe_get(offset + 4 + i))
        return String(from_utf8=buf^)

    def string_eq[o: Origin[mut=True]](self, ref doc: Document[o], expected: String) raises -> Bool:
        if self._tag(doc) != TAG_STRING:
            raise "TAPE_ERROR: expected string"
        var offset = Int(self._payload(doc))
        var str_len = Int(
            UInt32(doc._tape[].string_buf.unsafe_get(offset))
            | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 1)) << 8)
            | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 2)) << 16)
            | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 3)) << 24)
        )
        var expected_bytes = expected.as_bytes()
        if str_len != len(expected_bytes):
            return False
        for i in range(str_len):
            if doc._tape[].string_buf.unsafe_get(offset + 4 + i) != expected_bytes[i]:
                return False
        return True

    # --- Container access ---
    def get[o: Origin[mut=True]](self, ref doc: Document[o], key: String) raises -> Value:
        """Object key lookup. O(n) linear scan."""
        if self._tag(doc) != TAG_OBJECT_OPEN:
            raise "TAPE_ERROR: expected object for key lookup"
        var i = self._idx + 1
        var close_plus_one = Int(self._payload(doc) & 0xFFFFFFFF)
        while i < close_plus_one - 1:
            # Safety: idx comes from tape structure written by builder
            var key_tag = UInt8(doc._tape[].elements.unsafe_get(i) >> 56)
            if key_tag != TAG_STRING:
                raise "TAPE_ERROR: expected string key in object"
            # Safety: idx comes from tape structure written by builder
            var offset = Int(doc._tape[].elements.unsafe_get(i) & 0x00FFFFFFFFFFFFFF)
            var key_len = Int(
                UInt32(doc._tape[].string_buf.unsafe_get(offset))
                | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 1)) << 8)
                | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 2)) << 16)
                | (UInt32(doc._tape[].string_buf.unsafe_get(offset + 3)) << 24)
            )
            var expected_bytes = key.as_bytes()
            var is_match = key_len == len(expected_bytes)
            if is_match:
                for j in range(key_len):
                    if doc._tape[].string_buf.unsafe_get(offset + 4 + j) != expected_bytes[j]:
                        is_match = False
                        break
            var val_idx = i + 1
            if is_match:
                return Value(val_idx)
            i = skip_value(doc, val_idx)
        raise "KEY_NOT_FOUND: '" + key + "'"

    def at[o: Origin[mut=True]](self, ref doc: Document[o], idx: Int) raises -> Value:
        """Array element access by index. O(n) skip."""
        if self._tag(doc) != TAG_ARRAY_OPEN:
            raise "TAPE_ERROR: expected array for index access"
        var i = self._idx + 1
        var close_plus_one = Int(self._payload(doc) & 0xFFFFFFFF)
        var current = 0
        while i < close_plus_one - 1:
            if current == idx:
                return Value(i)
            i = skip_value(doc, i)
            current += 1
        raise "INDEX_ERROR: index " + String(idx) + " out of range"

    def count[o: Origin[mut=True]](self, ref doc: Document[o]) raises -> Int:
        """Return element count from container open entry."""
        var t = self._tag(doc)
        if t != TAG_OBJECT_OPEN and t != TAG_ARRAY_OPEN:
            raise "TAPE_ERROR: expected container for count"
        return Int((self._payload(doc) >> 32) & 0xFFFFFF)


def skip_value[o: Origin[mut=True]](ref doc: Document[o], idx: Int) -> Int:
    """Return the tape index past the element at idx."""
    # Safety: idx comes from tape structure written by builder
    var entry = doc._tape[].elements.unsafe_get(idx)
    var tag = UInt8(entry >> 56)
    if tag == TAG_TRUE or tag == TAG_FALSE or tag == TAG_NULL or tag == TAG_STRING:
        return idx + 1
    if tag == TAG_INT64 or tag == TAG_UINT64 or tag == TAG_FLOAT64:
        return idx + 2
    if tag == TAG_OBJECT_OPEN or tag == TAG_ARRAY_OPEN:
        return Int(entry & 0xFFFFFFFF)
    return idx + 1
