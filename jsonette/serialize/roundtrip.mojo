"""In-package round-trip verification helper.

Tape internals are package-private, so an external test cannot compare two
parses directly. `tapes_equal` lives in-package and is callable from tests by
inference (callers never name `Document[o]`). Two parses are equal iff their
tapes match element-for-element, with `TAG_STRING` entries compared by CONTENT:
a raw-span payload holds an offset into that document's own input buffer, so
two equivalent documents parsed from different texts (e.g. original vs
re-serialized) carry different offsets for identical strings.
"""
from jsonette.document import Document
from jsonette.tape import (
    TAG_STRING, TAG_INT64, TAG_UINT64, TAG_FLOAT64,
    is_raw_string, raw_string_offset, raw_string_length,
)


def _str_len_of[o: Origin[mut=True]](ref [o] d: Document, payload: UInt64) -> Int:
    """Content length of a TAG_STRING payload in document `d` (either variant)."""
    if is_raw_string(payload):
        return raw_string_length(payload)
    var off = Int(payload)
    return Int(
        UInt32(d._parser._tape.string_buf[off])
        | (UInt32(d._parser._tape.string_buf[off + 1]) << 8)
        | (UInt32(d._parser._tape.string_buf[off + 2]) << 16)
        | (UInt32(d._parser._tape.string_buf[off + 3]) << 24)
    )


def _str_byte_of[o: Origin[mut=True]](ref [o] d: Document, payload: UInt64, i: Int) -> UInt8:
    """`i`-th content byte of a TAG_STRING payload in document `d`."""
    if is_raw_string(payload):
        return d._parser.get_input_ptr()[raw_string_offset(payload) + i]
    return d._parser._tape.string_buf[Int(payload) + 4 + i]


def tapes_equal[
    o1: Origin[mut=True], o2: Origin[mut=True]
](ref [o1] a: Document, ref [o2] b: Document) -> Bool:
    """True if `a` and `b` have structurally identical tapes (strings by content)."""
    var n = len(a._parser._tape.elements)
    if n != len(b._parser._tape.elements):
        return False
    var i = 0
    while i < n:
        var wa = a._parser._tape.elements[i]
        var wb = b._parser._tape.elements[i]
        var tag = UInt8(wa >> 56)
        if UInt8(wb >> 56) != tag:
            return False
        if tag == TAG_STRING:
            var pa = wa & 0x00FFFFFFFFFFFFFF
            var pb = wb & 0x00FFFFFFFFFFFFFF
            var sl = _str_len_of(a, pa)
            if sl != _str_len_of(b, pb):
                return False
            for j in range(sl):
                if _str_byte_of(a, pa, j) != _str_byte_of(b, pb, j):
                    return False
            i += 1
        elif tag == TAG_INT64 or tag == TAG_UINT64 or tag == TAG_FLOAT64:
            # Tag word, then the raw 64-bit value word (not a tagged entry).
            if wa != wb or a._parser._tape.elements[i + 1] != b._parser._tape.elements[i + 1]:
                return False
            i += 2
        else:
            if wa != wb:
                return False
            i += 1
    return True
