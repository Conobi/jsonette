"""In-package round-trip verification helper.

Tape internals (`elements`, `string_buf`) are package-private, so an external
test cannot compare two parses directly. `tapes_equal` lives in-package and is
callable from tests by inference (callers never name `Document[o]`). Two parses
are tape-identical iff their `elements` and `string_buf` are byte-for-byte equal.
"""
from jsonette.document import Document


def tapes_equal[
    o1: Origin[mut=True], o2: Origin[mut=True]
](ref a: Document[o1], ref b: Document[o2]) -> Bool:
    """True if documents `a` and `b` have byte-identical tapes."""
    if len(a._tape[].elements) != len(b._tape[].elements):
        return False
    for i in range(len(a._tape[].elements)):
        if a._tape[].elements[i] != b._tape[].elements[i]:
            return False
    if len(a._tape[].string_buf) != len(b._tape[].string_buf):
        return False
    for i in range(len(a._tape[].string_buf)):
        if a._tape[].string_buf[i] != b._tape[].string_buf[i]:
            return False
    return True
