"""Deserialize JSON straight into a user struct via compile-time reflection.

The decode-side mirror of `reflect_writer.dumps[T]`. Reads through the DOM and
builds each value by OUT-RETURN. Safety: `load[T]` requires `T: Defaultable`,
default-constructs T (every field valid), then reflectively ASSIGNS each field —
no uninitialised memory exists, so a mid-decode raise unwinds over a valid struct.
"""
from std.reflection import reflect
from std.builtin.rebind import trait_downcast, rebind_var, downcast
from std.collections import Optional, Dict
from jsonette.document import parse
from jsonette.value import Value


comptime _Base = Movable & ImplicitlyDestructible
comptime _Struct = Defaultable & Movable & ImplicitlyDestructible


def _checked_int(v: Int64, lo: Int64, hi: Int64, tn: String) raises -> Int64:
    """Range-check a JSON integer before narrowing to a signed field, so an
    out-of-range value RAISES rather than silently wrapping (e.g. 300 -> Int8)."""
    if v < lo or v > hi:
        raise "NARROW_OVERFLOW: " + String(v) + " out of range for field type " + tn
    return v


def _checked_uint(v: UInt64, hi: UInt64, tn: String) raises -> UInt64:
    """Range-check a JSON integer before narrowing to an unsigned field; an
    out-of-range value RAISES rather than wrapping. (A negative source value is
    already rejected upstream by `get_uint`.)"""
    if v > hi:
        raise "NARROW_OVERFLOW: " + String(v) + " out of range for field type " + tn
    return v


def _checked_f32(d: Float64, tn: String) raises -> Float32:
    """Range-check a JSON double before narrowing to Float32, so a finite source
    that overflows Float32 RAISES rather than silently becoming +/-inf (the float
    analog of the narrow-integer guard). Magnitudes within range narrow with the
    usual Float32 precision loss, which is acceptable; only overflow is masked."""
    comptime F32_MAX = Float64(3.4028234663852886e38)
    if d > F32_MAX or d < -F32_MAX:
        raise "NARROW_OVERFLOW: " + String(d) + " out of range for field type " + tn
    return Float32(d)


trait JsonDeserializable(Movable):
    """Builds itself from a DOM `Value` (static out-return). The default body routes
    to the reflective struct field-walk, so a plain struct conforms with zero methods."""
    @staticmethod
    def from_json[o: Origin[mut=True]](val: Value[o], out s: Self) raises:
        s = _default_decode[downcast[Self, _Struct]](val)


def _decode[T: _Base, o: Origin[mut=True]](val: Value[o], out s: T) raises:
    comptime if conforms_to(T, JsonDeserializable):
        s = downcast[T, JsonDeserializable].from_json(val)
    else:
        comptime tn = reflect[T].name()
        comptime if tn == "String":
            s = rebind_var[T](val.get_string())
        elif tn == "Bool":
            s = rebind_var[T](val.get_bool())
        elif tn == "SIMD[DType.float64, 1]":
            s = rebind_var[T](val.get_float())
        elif tn == "SIMD[DType.float32, 1]":
            s = rebind_var[T](_checked_f32(val.get_float(), tn))
        elif tn == "Int":
            s = rebind_var[T](Int(val.get_int()))
        elif tn == "SIMD[DType.int64, 1]":
            s = rebind_var[T](val.get_int())
        elif tn == "SIMD[DType.int32, 1]":
            s = rebind_var[T](Int32(_checked_int(val.get_int(), -2147483648, 2147483647, tn)))
        elif tn == "SIMD[DType.int16, 1]":
            s = rebind_var[T](Int16(_checked_int(val.get_int(), -32768, 32767, tn)))
        elif tn == "SIMD[DType.int8, 1]":
            s = rebind_var[T](Int8(_checked_int(val.get_int(), -128, 127, tn)))
        elif tn == "SIMD[DType.uint64, 1]":
            s = rebind_var[T](val.get_uint())
        elif tn == "SIMD[DType.uint32, 1]":
            s = rebind_var[T](UInt32(_checked_uint(val.get_uint(), 4294967295, tn)))
        elif tn == "SIMD[DType.uint16, 1]":
            s = rebind_var[T](UInt16(_checked_uint(val.get_uint(), 65535, tn)))
        elif tn == "SIMD[DType.uint8, 1]":
            s = rebind_var[T](UInt8(_checked_uint(val.get_uint(), 255, tn)))
        elif reflect[T].is_struct():
            s = _default_decode[downcast[T, _Struct]](val)
        else:
            comptime assert False, "load[T]: unsupported field type '" + tn + "'"


def _default_decode[T: _Struct, o: Origin[mut=True]](val: Value[o], out s: T) raises:
    """Default-construct T, then assign each field. Absent key -> raise MISSING_FIELD
    EXCEPT an Optional field (kept as default None). Optional detected by name prefix."""
    comptime assert conforms_to(T, Defaultable), "load[T]: T must be Defaultable (add a no-arg __init__)"
    s = type_of(s)()
    comptime r = reflect[T]
    comptime names = r.field_names()
    comptime for i in range(r.field_count()):
        comptime key = String(names[i])
        ref field = trait_downcast[_Base](r.field_ref[i](s))
        var maybe = val.try_field(key)
        if maybe:
            field = _decode[type_of(field)](maybe.value())
        else:
            comptime is_opt = reflect[type_of(field)].name().startswith(
                "std.collections.optional.Optional["
            )
            comptime if not is_opt:
                raise "MISSING_FIELD: '" + key + "'"


def load[T: Defaultable & Movable & ImplicitlyDestructible & JsonDeserializable](
    data: String, out s: T
) raises:
    """Parse JSON `data` and reflectively build a fresh `T`."""
    var doc = parse(data)
    s = T.from_json(doc.root())


def load[T: Defaultable & Movable & ImplicitlyDestructible & JsonDeserializable](
    data: Span[UInt8, _], out s: T
) raises:
    var doc = parse(data)
    s = T.from_json(doc.root())


__extension List(JsonDeserializable):
    @staticmethod
    def from_json[o: Origin[mut=True]](val: Value[o], out s: Self) raises:
        """Build a JSON array into List[T]; element type recovered from Self.T."""
        # Build into a list whose element type is STATICALLY `_Base` (Movable &
        # ImplicitlyDestructible), so a mid-decode raise unwinds over a list the
        # compiler can implicitly destroy. `List[Self.T]` alone is only
        # *conditionally* destructible (b2), so building straight into `s` leaves
        # a partially-filled list "abandoned" on the throw path. Rebind into `s`
        # once fully built (same element layout, zero-copy move).
        comptime ET = downcast[Self.T, _Base]
        var built = List[ET]()
        for elem in val.elems():
            built.append(_decode[ET](elem))
        s = rebind_var[Self](built^)


__extension Optional(JsonDeserializable):
    @staticmethod
    def from_json[o: Origin[mut=True]](val: Value[o], out s: Self) raises:
        """Explicit JSON null -> None; else decode the inner value as Self.T. Absent
        keys never reach here (the struct field-walk keeps the default None)."""
        if val.is_null():
            s = Self()
        else:
            s = Self(_decode[downcast[Self.T, _Base]](val))


__extension Dict(JsonDeserializable):
    @staticmethod
    def from_json[o: Origin[mut=True]](val: Value[o], out s: Self) raises:
        """Build a JSON object into Dict[String, V]; V recovered from Self.V. Keys
        must be String (compile-time enforced)."""
        comptime assert reflect[Self.K].name() == "String", "JSON object keys must be String"
        s = Self()
        for entry in val.fields():
            s[rebind_var[Self.K](entry.key())] = _decode[downcast[Self.V, _Base]](entry.value())
