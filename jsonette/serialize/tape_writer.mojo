"""Serialize a parsed `Document` back to JSON text (round-trip).

Walks the depth-first tape from the root (index 1), reusing the tag layout and
container payload encoding established in `value.mojo` (low 32 payload bits =
index past the close marker; numbers/strings as in the Value getters). Emits
through the shared `JsonWriter`. Lives in-package so it may name `Document[o]`;
external callers invoke `to_string`/`to_json` by inference, never naming the type.
"""
from std.memory import bitcast
from jsonette.document import Document
from jsonette.tape import (
    TAG_OBJECT_OPEN, TAG_ARRAY_OPEN, TAG_STRING, TAG_INT64, TAG_UINT64,
    TAG_FLOAT64, TAG_TRUE, TAG_FALSE, TAG_NULL,
)
from jsonette.serialize.writer import JsonWriter


def _write_string_at[o: Origin[mut=True]](ref [o] doc: Document, idx: Int, mut w: JsonWriter):
    """Emit the STRING entry at `idx` (payload = offset into string_buf)."""
    var entry = doc._parser._tape.elements[idx]
    var offset = Int(entry & 0x00FFFFFFFFFFFFFF)
    var slen = Int(
        UInt32(doc._parser._tape.string_buf[offset])
        | (UInt32(doc._parser._tape.string_buf[offset + 1]) << 8)
        | (UInt32(doc._parser._tape.string_buf[offset + 2]) << 16)
        | (UInt32(doc._parser._tape.string_buf[offset + 3]) << 24)
    )
    w.write_escaped_buf(doc._parser._tape.string_buf, offset + 4, slen)


def _write_value[o: Origin[mut=True]](ref [o] doc: Document, idx: Int, mut w: JsonWriter) raises -> Int:
    """Emit the value at tape index `idx`; return the index just past it.

    Pretty-print is driven by the writer's indent state: `newline_indent()` and
    `colon()` are minimal in compact mode, so one walk serves both modes. Empty
    containers emit `{}`/`[]` with no interior newline.
    """
    var entry = doc._parser._tape.elements[idx]
    var tag = UInt8(entry >> 56)
    if tag == TAG_OBJECT_OPEN:
        var close_p1 = Int(entry & 0xFFFFFFFF)
        var i = idx + 1
        if i >= close_p1 - 1:
            w.raw("{}")
            return close_p1
        w.raw("{")
        w.depth += 1
        var first = True
        while i < close_p1 - 1:
            if not first:
                w.raw(",")
            first = False
            w.newline_indent()
            _write_string_at(doc, i, w)   # key (STRING) at i
            w.colon()
            i = _write_value(doc, i + 1, w)  # value at i+1
        w.depth -= 1
        w.newline_indent()
        w.raw("}")
        return close_p1
    elif tag == TAG_ARRAY_OPEN:
        var close_p1 = Int(entry & 0xFFFFFFFF)
        var i = idx + 1
        if i >= close_p1 - 1:
            w.raw("[]")
            return close_p1
        w.raw("[")
        w.depth += 1
        var first = True
        while i < close_p1 - 1:
            if not first:
                w.raw(",")
            first = False
            w.newline_indent()
            i = _write_value(doc, i, w)
        w.depth -= 1
        w.newline_indent()
        w.raw("]")
        return close_p1
    elif tag == TAG_STRING:
        _write_string_at(doc, idx, w)
        return idx + 1
    elif tag == TAG_INT64:
        w.write_int(Int64(bitcast[DType.int64](SIMD[DType.uint64, 1](doc._parser._tape.elements[idx + 1]))))
        return idx + 2
    elif tag == TAG_UINT64:
        w.write_uint(doc._parser._tape.elements[idx + 1])
        return idx + 2
    elif tag == TAG_FLOAT64:
        w.write_float(Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](doc._parser._tape.elements[idx + 1]))))
        return idx + 2
    elif tag == TAG_TRUE:
        w.write_bool(True)
        return idx + 1
    elif tag == TAG_FALSE:
        w.write_bool(False)
        return idx + 1
    elif tag == TAG_NULL:
        w.write_null()
        return idx + 1
    else:
        raise "TAPE_ERROR: unknown tag in serializer"


def to_string[o: Origin[mut=True]](ref [o] doc: Document) raises -> String:
    """Serialize `doc` to compact JSON text."""
    var w = JsonWriter()
    _ = _write_value(doc, 1, w)
    return w^.finish()


def to_json[o: Origin[mut=True], pretty: Bool = False](ref [o] doc: Document) raises -> String:
    """Serialize `doc` to JSON text; `pretty=True` indents with two spaces."""
    comptime if pretty:
        var w = JsonWriter(String("  "))
        _ = _write_value(doc, 1, w)
        return w^.finish()
    else:
        var w = JsonWriter()
        _ = _write_value(doc, 1, w)
        return w^.finish()
