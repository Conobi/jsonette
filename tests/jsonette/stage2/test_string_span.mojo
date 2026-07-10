"""Exact-span string fast path: boundary and delegation seams via `parse()`.

The tape builder feeds `parse_string_span` the closing-quote position from the
structural index. Cover the 32-byte chunk seams (content lengths around 32 and
64), the masked tail (control-byte false positives from bytes after the close
quote), and delegation (escapes, control bytes, unterminated strings).
"""

from std.testing import assert_equal, assert_true

from jsonette.document import parse


def _doc(content: String) -> List[UInt8]:
    """Build `{"k":"<content>"}` as bytes."""
    var s = String('{"k":"') + content + String('"}')
    var o = List[UInt8]()
    for b in s.as_bytes():
        o.append(b)
    return o^


def test_boundary_lengths() raises:
    """Escape-free contents straddling the 32-byte chunk seams round-trip."""
    for n in [0, 1, 31, 32, 33, 63, 64, 65, 127, 128]:
        var content = String("x") * n
        var doc = parse(_doc(content))
        assert_equal(doc["k"].get_string(), content, "length " + String(n))


def test_tail_mask_ignores_bytes_past_close() raises:
    """A newline right after the closing quote must not trip the ctrl check."""
    var raw = List[UInt8]()
    for b in String('{"k": "ab",\n "j": 1}').as_bytes():
        raw.append(b)
    var doc = parse(raw)
    assert_equal(doc["k"].get_string(), "ab")


def test_escapes_delegate() raises:
    """Escapes anywhere in the span (incl. at a 32-byte seam) still unescape."""
    var doc = parse(_doc(String("a") * 31 + String("\\n") + String("b") * 31))
    assert_equal(doc["k"].get_string(), String("a") * 31 + "\n" + String("b") * 31)
    var doc2 = parse(_doc(String('a\\"b')))
    assert_equal(doc2["k"].get_string(), 'a"b')


def test_ctrl_and_unterminated_reject() raises:
    """Raw control byte and unterminated string still raise."""
    var ctrl = List[UInt8]()
    for b in String('{"k":"a').as_bytes():
        ctrl.append(b)
    ctrl.append(UInt8(0x01))
    for b in String('b"}').as_bytes():
        ctrl.append(b)
    var raised = False
    try:
        _ = parse(ctrl)
    except:
        raised = True
    assert_true(raised, "control byte must raise")

    var unterminated = List[UInt8]()
    for b in String('{"k":"abc').as_bytes():
        unterminated.append(b)
    var raised2 = False
    try:
        _ = parse(unterminated)
    except:
        raised2 = True
    assert_true(raised2, "unterminated string must raise")


def main() raises:
    test_boundary_lengths()
    test_tail_mask_ignores_bytes_past_close()
    test_escapes_delegate()
    test_ctrl_and_unterminated_reject()
    print("All string-span tests passed!")
