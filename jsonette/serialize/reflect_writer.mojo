"""Serialize arbitrary user structs via compile-time reflection.

Dispatch is conformance-driven (no overloads): `emit[T]` routes types that
conform to `JsonSerializable` (user overrides, plus `List`/`Dict`/`Optional`
via retroactive `__extension` conformance) to `write_json`, and everything
else to `_default_emit` — a reflection field-walk that discriminates leaf types
by `reflect[T]().name()` and bridges via `rebind`. The trait's default
`write_json` body calls `_default_emit`, so a plain struct conforms with zero
methods.

Verified on the active toolchain: `conforms_to` + type refinement + the name/
rebind table all compile and emit correct JSON.
"""
from std.reflection import reflect
from jsonette.serialize.writer import JsonWriter


trait JsonSerializable:
    """A type that can write itself as JSON. Default body uses reflection."""
    def write_json(self, mut w: JsonWriter) raises:
        _default_emit(self, w)


def _default_emit[T: AnyType, //](value: T, mut w: JsonWriter) raises:
    """Reflection field-walk for structs; name/rebind dispatch for leaf types.

    Note: the word-sized `UInt` type is unsupported as a field type. Mojo
    reflection's `name()` calls `get_type_name` internally, which errors on its
    non-concrete dtype (`scalar<uindex>`), crashing before any branch can be
    reached. Use `UInt64` or `Int` instead. Supported sized unsigned types are
    `UInt8`, `UInt16`, `UInt32`, and `UInt64`.
    """
    comptime tn = reflect[T]().name()
    comptime if tn == "Int":
        w.write_int(Int64(rebind[Int](value)))
    elif tn == "Bool":
        w.write_bool(rebind[Bool](value))
    elif tn == "String":
        w.write_escaped_str(rebind[String](value))
    elif tn == "SIMD[DType.float64, 1]":
        w.write_float(rebind[Float64](value))
    elif tn == "SIMD[DType.float32, 1]":
        w.write_float(Float64(rebind[Float32](value)))
    elif tn == "SIMD[DType.int64, 1]":
        w.write_int(rebind[Int64](value))
    elif tn == "SIMD[DType.int32, 1]":
        w.write_int(Int64(rebind[Int32](value)))
    elif tn == "SIMD[DType.int16, 1]":
        w.write_int(Int64(rebind[Int16](value)))
    elif tn == "SIMD[DType.int8, 1]":
        w.write_int(Int64(rebind[Int8](value)))
    elif tn == "SIMD[DType.uint64, 1]":
        w.write_uint(rebind[UInt64](value))
    elif tn == "SIMD[DType.uint32, 1]":
        w.write_uint(UInt64(rebind[UInt32](value)))
    elif tn == "SIMD[DType.uint16, 1]":
        w.write_uint(UInt64(rebind[UInt16](value)))
    elif tn == "SIMD[DType.uint8, 1]":
        w.write_uint(UInt64(rebind[UInt8](value)))
    elif reflect[T]().is_struct():
        comptime r = reflect[T]()
        comptime names = r.field_names()
        w.raw("{")
        w.depth += 1
        comptime for i in range(r.field_count()):
            comptime if i > 0:
                w.raw(",")
            w.newline_indent()
            w.write_escaped_str(String(names[i]))
            w.colon()
            emit(r.field_ref[i](value), w)
        w.depth -= 1
        if r.field_count() > 0:
            w.newline_indent()
        w.raw("}")
    else:
        raise "JSON_ENCODE_ERROR: unsupported type '" + String(tn) + "'"


def emit[T: AnyType, //](value: T, mut w: JsonWriter) raises:
    """Emit any value: conforming types via `write_json`, else reflection."""
    comptime if conforms_to(T, JsonSerializable):
        value.write_json(w)
    else:
        _default_emit(value, w)


def dumps[T: AnyType, //](value: T, indent: String = String("")) raises -> String:
    """Serialize a user value to JSON. Non-empty `indent` enables pretty mode."""
    var w = JsonWriter(indent)
    emit(value, w)
    return w^.finish()


__extension List(JsonSerializable):
    def write_json(self, mut w: JsonWriter) raises:
        """Emit a JSON array; element type recovered from `Self.T`, not reflection."""
        if len(self) == 0:
            w.raw("[]")
            return
        w.raw("[")
        w.depth += 1
        for i in range(len(self)):
            if i > 0:
                w.raw(",")
            w.newline_indent()
            emit(self[i], w)
        w.depth -= 1
        w.newline_indent()
        w.raw("]")


__extension Optional(JsonSerializable):
    def write_json(self, mut w: JsonWriter) raises:
        """Emit the contained value, or `null` when empty."""
        if self:
            emit(self.value(), w)
        else:
            w.write_null()


__extension Dict(JsonSerializable):
    def write_json(self, mut w: JsonWriter) raises:
        """Emit a JSON object. Keys must be `String` (compile-time enforced)."""
        comptime assert reflect[Self.K]().name() == "String", "JSON object keys must be String"
        if len(self) == 0:
            w.raw("{}")
            return
        w.raw("{")
        w.depth += 1
        var i = 0
        for item in self.items():
            if i > 0:
                w.raw(",")
            w.newline_indent()
            w.write_escaped_str(rebind[String](item.key))
            w.colon()
            emit(item.value, w)
            i += 1
        w.depth -= 1
        w.newline_indent()
        w.raw("}")
