"""Owned, origin-free JSON value tree for building dynamic JSON output.

`JsonValue` is a self-owning, recursive builder: unlike `Value` (a borrowing
view into a parsed `Document`'s tape), it holds its own data and carries no
origin, so it can be constructed, mutated, moved, and returned freely. It is the
output-side counterpart to the parser's DOM — build a tree with the scalar
constructors, the `array()`/`object()` factories, `append`, and `__setitem__`,
then serialize it with the existing `dumps`.

Representation is a tag-discriminated fat struct: every value carries all
possible payload fields and a `tag` selecting the live one. Memory is not the
concern for a transient output builder, and the flat layout keeps construction
and serialization branch-simple. Three distinct numeric tags preserve the
signed / unsigned / float distinction of the parsed DOM.

Because `JsonValue` conforms to `JsonSerializable`, `dumps(v)` /
`dumps(v, indent="  ")` serialize it through `write_json` with no dedicated
serialization entry point.

`JsonValue` is `Copyable` (via `List` indirection over `Self`) but is treated as
move-only in its own builders: they take `var` parameters and transfer with `^`.
"""
from jsonette.serialize.writer import JsonWriter
from jsonette.serialize.reflect_writer import JsonSerializable
from jsonette.value import Value
from jsonette.document import parse

# Recursion depth cap for serialization, matching the parser's tape builder. A
# hand-built tree is not bounded by the parser, so `write_json` guards its native
# recursion to avoid unbounded stack growth on adversarial input (OWASP).
comptime _MAX_DEPTH: Int = 1024

# Tag values selecting the live payload field.
comptime _TAG_NULL: Int = 0
comptime _TAG_BOOL: Int = 1
comptime _TAG_INT: Int = 2
comptime _TAG_UINT: Int = 3
comptime _TAG_FLOAT: Int = 4
comptime _TAG_STRING: Int = 5
comptime _TAG_ARRAY: Int = 6
comptime _TAG_OBJECT: Int = 7


struct JsonValue(JsonSerializable, Copyable, Movable):
    """An owned, origin-free JSON value: null, bool, number, string, array, or
    object. Build it up, then serialize with `dumps`."""

    var tag: Int
    """Selects the live payload field (see the `_TAG_*` constants)."""
    var b: Bool
    """Boolean payload (live when `tag == _TAG_BOOL`)."""
    var i: Int64
    """Signed integer payload (live when `tag == _TAG_INT`)."""
    var u: UInt64
    """Unsigned integer payload (live when `tag == _TAG_UINT`)."""
    var f: Float64
    """Float payload (live when `tag == _TAG_FLOAT`)."""
    var s: String
    """String payload (live when `tag == _TAG_STRING`)."""
    var arr: List[JsonValue]
    """Array elements (live when `tag == _TAG_ARRAY`)."""
    var keys: List[String]
    """Object keys, insertion-ordered and unique (live when `tag == _TAG_OBJECT`)."""
    var vals: List[JsonValue]
    """Object values, parallel to `keys` (live when `tag == _TAG_OBJECT`)."""

    def __init__(out self):
        """Create a JSON `null`."""
        self.tag = _TAG_NULL
        self.b = False
        self.i = 0
        self.u = 0
        self.f = 0.0
        self.s = String("")
        self.arr = List[JsonValue]()
        self.keys = List[String]()
        self.vals = List[JsonValue]()

    @implicit
    def __init__(out self, none: NoneType):
        """Create a JSON `null` from `None`.

        Note: on the current toolchain a bare `var v: JsonValue = None` does not
        implicitly coerce; use the explicit form `JsonValue(None)`.
        """
        self = Self()

    @implicit
    def __init__(out self, v: Bool):
        """Create a JSON boolean."""
        self = Self()
        self.tag = _TAG_BOOL
        self.b = v

    @implicit
    def __init__(out self, v: Int):
        """Create a signed-integer JSON number from a word-sized `Int`."""
        self = Self()
        self.tag = _TAG_INT
        self.i = Int64(v)

    @implicit
    def __init__(out self, v: Int64):
        """Create a signed-integer JSON number."""
        self = Self()
        self.tag = _TAG_INT
        self.i = v

    @implicit
    def __init__(out self, v: UInt64):
        """Create an unsigned-integer JSON number (preserves values > Int64.MAX)."""
        self = Self()
        self.tag = _TAG_UINT
        self.u = v

    @implicit
    def __init__(out self, v: Float64):
        """Create a floating-point JSON number."""
        self = Self()
        self.tag = _TAG_FLOAT
        self.f = v

    @implicit
    def __init__(out self, v: String):
        """Create a JSON string."""
        self = Self()
        self.tag = _TAG_STRING
        self.s = v

    @staticmethod
    def array() -> JsonValue:
        """Create an empty JSON array; populate it with `append`."""
        var v = JsonValue()
        v.tag = _TAG_ARRAY
        return v^

    @staticmethod
    def object() -> JsonValue:
        """Create an empty JSON object; populate it with `__setitem__`/`__getitem__`."""
        var v = JsonValue()
        v.tag = _TAG_OBJECT
        return v^

    @staticmethod
    def from_value[o: Origin[mut=True]](v: Value[o]) raises -> JsonValue:
        """Deep-copy a borrowing DOM `Value` into an owned, origin-free `JsonValue`.

        Recursively materializes each parsed node using only `Value`'s public
        accessors (never the tape internals), preserving the signed / unsigned /
        float numeric distinction (three separate integer/float branches).
        Recursion is naturally bounded by the parser's MAX_DEPTH — the tape cannot
        nest deeper than what `parse` accepted — so no extra depth guard is needed
        here.
        """
        if v.is_object():
            var obj = JsonValue.object()
            for k, val in v.items():
                obj[k] = JsonValue.from_value(val)
            return obj^
        if v.is_array():
            var arr = JsonValue.array()
            for e in v:  # Value.__iter__ yields array elements
                arr.append(JsonValue.from_value(e))
            return arr^
        if v.is_string():
            return JsonValue(v.get_string())
        if v.is_int():
            return JsonValue(v.get_int())  # signed
        if v.is_uint():
            return JsonValue(v.get_uint())  # unsigned (preserves > Int64.MAX)
        if v.is_float():
            return JsonValue(v.get_float())
        if v.is_bool():
            return JsonValue(v.get_bool())
        return JsonValue()  # null

    def append(mut self, var v: JsonValue):
        """Append `v` as the next array element (making `self` an array)."""
        self.tag = _TAG_ARRAY
        self.arr.append(v^)

    def __setitem__(mut self, var key: String, var v: JsonValue):
        """Insert or overwrite `key` -> `v` (making `self` an object).

        Keys are unique and insertion-ordered: overwriting an existing key
        replaces its value in place without changing its position.
        """
        self.tag = _TAG_OBJECT
        for idx in range(len(self.keys)):
            if self.keys[idx] == key:
                self.vals[idx] = v^
                return
        self.keys.append(key^)
        self.vals.append(v^)

    def __getitem__(mut self, var key: String) -> ref [self.vals] JsonValue:
        """Return a mutable reference to the value at `key` (making `self` an
        object), auto-vivifying an empty object at `key` if absent.

        This enables chained assignment such as `doc["a"]["b"] = x`.
        """
        self.tag = _TAG_OBJECT
        for idx in range(len(self.keys)):
            if self.keys[idx] == key:
                return self.vals[idx]
        self.keys.append(key^)
        self.vals.append(Self.object())
        return self.vals[len(self.vals) - 1]

    def write_json(self, mut w: JsonWriter) raises:
        """Emit `self` as JSON into `w` (conforms `JsonSerializable`).

        Serialization is a depth-bounded recursion; see `_write_json`.
        """
        self._write_json(w, 0)

    def _write_json(self, mut w: JsonWriter, depth: Int) raises:
        """Recursively emit `self` at nesting `depth`.

        Raises `JSON_ENCODE_ERROR: max nesting depth exceeded` beyond
        `_MAX_DEPTH` so a hand-built tree cannot overflow the native stack.
        Container layout (comma-before-newline, empty as `{}`/`[]`, `": "` after
        keys in pretty mode) matches the rest of the encoder.
        """
        if depth > _MAX_DEPTH:
            raise "JSON_ENCODE_ERROR: max nesting depth exceeded"
        if self.tag == _TAG_NULL:
            w.write_null()
        elif self.tag == _TAG_BOOL:
            w.write_bool(self.b)
        elif self.tag == _TAG_INT:
            w.write_int(self.i)
        elif self.tag == _TAG_UINT:
            w.write_uint(self.u)
        elif self.tag == _TAG_FLOAT:
            w.write_float(self.f)
        elif self.tag == _TAG_STRING:
            w.write_escaped_str(self.s)
        elif self.tag == _TAG_ARRAY:
            if len(self.arr) == 0:
                w.raw("[]")
                return
            w.raw("[")
            w.depth += 1
            for idx in range(len(self.arr)):
                if idx > 0:
                    w.raw(",")
                w.newline_indent()
                self.arr[idx]._write_json(w, depth + 1)
            w.depth -= 1
            w.newline_indent()
            w.raw("]")
        elif self.tag == _TAG_OBJECT:
            if len(self.keys) == 0:
                w.raw("{}")
                return
            w.raw("{")
            w.depth += 1
            for idx in range(len(self.keys)):
                if idx > 0:
                    w.raw(",")
                w.newline_indent()
                w.write_escaped_str(self.keys[idx])
                w.colon()
                self.vals[idx]._write_json(w, depth + 1)
            w.depth -= 1
            w.newline_indent()
            w.raw("}")
        else:
            raise "JSON_ENCODE_ERROR: unknown JsonValue tag"


def loads(data: String) raises -> JsonValue:
    """Parse JSON text into an OWNED `JsonValue` tree (Python-faithful: the result
    owns its data and carries no origin, so it can be stored/returned freely).
    This is the allocating, own-everything path; for zero-copy navigation use
    `parse` -> `Document`, and for a typed struct use `decode[T]`."""
    var doc = parse(data)
    return JsonValue.from_value(doc.root())


def loads(data: Span[UInt8, _]) raises -> JsonValue:
    """Byte-span overload of `loads`."""
    var doc = parse(data)
    return JsonValue.from_value(doc.root())
