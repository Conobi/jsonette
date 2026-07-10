"""UTF-8 well-formedness: parse() and validate() reject non-UTF-8 input.

RFC 8259 requires JSON text to be valid UTF-8. jsonette validates the input
inside the Stage 1 chunk loop (`structural_index[validate_utf8=True]`), fused
with structural indexing. The interesting vectors put raw byte-invalid UTF-8 INSIDE an
otherwise structurally-valid JSON string — the case structural parsing alone
misses, since string content bytes are not encoding-checked by Stage 2. Both the
DOM `parse()` and the strict `validate()` must reject them (and agree), and valid
multibyte content must be accepted.
"""
from std.testing import assert_true
from jsonette.document import parse
from jsonette.parser import Parser


def _raw(bytes: List[Int]) -> List[UInt8]:
    var o = List[UInt8]()
    for x in bytes:
        o.append(UInt8(x))
    return o^


def _quoted(inner: List[Int]) -> List[UInt8]:
    """Wrap raw inner bytes in a JSON string: '"' inner '"'."""
    var o = List[UInt8]()
    o.append(UInt8(0x22))
    for x in inner:
        o.append(UInt8(x))
    o.append(UInt8(0x22))
    return o^


def _parse_rejects(data: List[UInt8]) raises -> Bool:
    try:
        _ = parse(data)
        return False
    except:
        return True


def _validate_rejects(data: List[UInt8]) raises -> Bool:
    var p = Parser()
    try:
        p.validate(data)
        return False
    except:
        return True


def _both_reject(name: String, data: List[UInt8]) raises:
    assert_true(_parse_rejects(data), name + ": parse() must reject")
    assert_true(_validate_rejects(data), name + ": validate() must reject")


def _both_accept(name: String, data: List[UInt8]) raises:
    assert_true(not _parse_rejects(data), name + ": parse() must accept")
    assert_true(not _validate_rejects(data), name + ": validate() must accept")


def main() raises:
    # Valid multibyte inside strings -> accepted by both paths.
    _both_accept("ascii", _quoted([0x61, 0x62]))                 # "ab"
    _both_accept("2-byte e-acute C3 A9", _quoted([0xC3, 0xA9]))
    _both_accept("3-byte CJK E6 97 A5", _quoted([0xE6, 0x97, 0xA5]))
    _both_accept("4-byte emoji F0 9F 98 80", _quoted([0xF0, 0x9F, 0x98, 0x80]))

    # Invalid UTF-8 inside an otherwise-valid JSON string -> rejected by both.
    _both_reject("illegal byte FF", _quoted([0xFF]))
    _both_reject("lone continuation 80", _quoted([0x80]))
    _both_reject("overlong C0 80", _quoted([0xC0, 0x80]))
    _both_reject("overlong E0 80 80", _quoted([0xE0, 0x80, 0x80]))
    _both_reject("surrogate ED A0 80", _quoted([0xED, 0xA0, 0x80]))
    _both_reject("too-large F5 80 80 80", _quoted([0xF5, 0x80, 0x80, 0x80]))
    _both_reject("truncated 2-byte C2", _quoted([0xC2]))
    _both_reject("truncated 3-byte E6 97", _quoted([0xE6, 0x97]))

    # Bare invalid byte at the top level (not inside a string) -> rejected too.
    _both_reject("bare FF", _raw([0xFF]))

    print("test_utf8: all passed")
