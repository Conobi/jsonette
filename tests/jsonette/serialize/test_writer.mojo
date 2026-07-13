from std.testing import assert_equal, assert_true
from jsonette.serialize.writer import JsonWriter


def test_escaping() raises:
    var w = JsonWriter()
    w.write_escaped_str(String('a"b\\c') + chr(10) + chr(9) + chr(1) + chr(127))
    assert_equal(w^.finish(), String('"a\\"b\\\\c\\n\\t\\u0001') + chr(127) + '"')

def test_escaped_buf() raises:
    var src = String("x") + chr(13) + "y"
    var lb = List[UInt8]()
    for b in src.as_bytes():
        lb.append(b)
    var w = JsonWriter()
    w.write_escaped_buf(lb, 0, len(lb))
    assert_equal(w^.finish(), String('"x\\ry"'))

def test_numbers() raises:
    var w = JsonWriter()
    w.write_int(-42); w.raw(","); w.write_uint(18446744073709551615); w.raw(",")
    w.write_float(3.5); w.raw(","); w.write_bool(True); w.raw(","); w.write_null()
    assert_equal(w^.finish(), String("-42,18446744073709551615,3.5,true,null"))

def test_finite_guard() raises:
    var w = JsonWriter()
    var inf = Float64(1.0) / Float64(0.0)
    var raised = False
    try:
        w.write_float(inf)
    except e:
        raised = True
    assert_true(raised)

def test_pretty_colon_and_indent() raises:
    var w = JsonWriter(String("  "))
    assert_true(w.is_pretty())
    w.raw("{"); w.depth += 1; w.newline_indent(); w.write_escaped_str(String("k")); w.colon(); w.write_int(1)
    w.depth -= 1; w.newline_indent(); w.raw("}")
    assert_equal(w^.finish(), String('{') + chr(10) + '  "k": 1' + chr(10) + '}')


def test_raw_bulk() raises:
    var w = JsonWriter()
    w.raw(String(""))
    w.raw(String("a"))
    w.raw(String("hello world this is a longer string for memcpy"))
    assert_equal(
        w^.finish(),
        String("ahello world this is a longer string for memcpy"),
    )


def test_int_boundaries() raises:
    # Zero
    var w0 = JsonWriter()
    w0.write_int(Int64(0))
    assert_equal(w0^.finish(), String("0"))

    # Single digits
    var w1 = JsonWriter()
    w1.write_int(Int64(7))
    assert_equal(w1^.finish(), String("7"))

    var w2 = JsonWriter()
    w2.write_int(Int64(-3))
    assert_equal(w2^.finish(), String("-3"))

    # Int64.MAX
    var w3 = JsonWriter()
    w3.write_int(Int64(9223372036854775807))
    assert_equal(w3^.finish(), String("9223372036854775807"))

    # Int64.MIN — magnitude overflows Int64
    var w4 = JsonWriter()
    w4.write_int(Int64(-9223372036854775808))
    assert_equal(w4^.finish(), String("-9223372036854775808"))

    # Powers of 10
    var w5 = JsonWriter()
    w5.write_int(Int64(1000))
    assert_equal(w5^.finish(), String("1000"))

    var w6 = JsonWriter()
    w6.write_int(Int64(-100))
    assert_equal(w6^.finish(), String("-100"))


def test_uint_boundaries() raises:
    var w0 = JsonWriter()
    w0.write_uint(UInt64(0))
    assert_equal(w0^.finish(), String("0"))

    # UInt64.MAX — 20 digits
    var w1 = JsonWriter()
    w1.write_uint(UInt64(18446744073709551615))
    assert_equal(w1^.finish(), String("18446744073709551615"))

    var w2 = JsonWriter()
    w2.write_uint(UInt64(1))
    assert_equal(w2^.finish(), String("1"))

    var w3 = JsonWriter()
    w3.write_uint(UInt64(10))
    assert_equal(w3^.finish(), String("10"))


def _scalar_escape(data: List[UInt8]) raises -> String:
    """Reference scalar escaper — same logic as the old _esc_one loop."""
    var w = List[UInt8]()
    w.append(0x22)
    for i in range(len(data)):
        var c = data[i]
        if c == 0x22:
            w.append(0x5C); w.append(0x22)
        elif c == 0x5C:
            w.append(0x5C); w.append(0x5C)
        elif c >= 0x20:
            w.append(c)
        elif c == 0x08:
            w.append(0x5C); w.append(0x62)
        elif c == 0x0C:
            w.append(0x5C); w.append(0x66)
        elif c == 0x0A:
            w.append(0x5C); w.append(0x6E)
        elif c == 0x09:
            w.append(0x5C); w.append(0x74)
        elif c == 0x0D:
            w.append(0x5C); w.append(0x72)
        else:
            var hex = String("0123456789abcdef")
            w.append(0x5C); w.append(0x75)
            w.append(0x30); w.append(0x30)
            w.append(hex.as_bytes()[Int(c >> 4)])
            w.append(hex.as_bytes()[Int(c & 0xF)])
    w.append(0x22)
    return String(from_utf8=w^)


def _check_escape_differential(data: List[UInt8]) raises:
    """Assert SIMD escaper matches scalar reference for `data`."""
    var expected = _scalar_escape(data)
    var w = JsonWriter()
    w.write_escaped_buf(data, 0, len(data))
    var got = w^.finish()
    assert_equal(got, expected)


def test_simd_escape_boundaries() raises:
    # Empty
    _check_escape_differential(List[UInt8]())

    # Lengths around the 32-byte SIMD boundary, all clean
    for length in [1, 15, 31, 32, 33, 63, 64, 65, 128]:
        var data = List[UInt8]()
        for i in range(length):
            data.append(UInt8(0x41 + (i % 26)))  # A-Z cycling
        _check_escape_differential(data)


def test_simd_escape_dirty() raises:
    # All quotes
    var all_q = List[UInt8]()
    for _ in range(64):
        all_q.append(0x22)
    _check_escape_differential(all_q)

    # All backslashes
    var all_bs = List[UInt8]()
    for _ in range(64):
        all_bs.append(0x5C)
    _check_escape_differential(all_bs)

    # Control bytes: NUL, tab, newline, CR, BS, FF, and generic 0x01
    var ctrl = List[UInt8]()
    ctrl.append(0x00); ctrl.append(0x09); ctrl.append(0x0A)
    ctrl.append(0x0D); ctrl.append(0x08); ctrl.append(0x0C)
    ctrl.append(0x01); ctrl.append(0x1F)
    _check_escape_differential(ctrl)

    # DEL (0x7F) — must pass through verbatim
    var del_byte = List[UInt8]()
    del_byte.append(0x7F)
    _check_escape_differential(del_byte)

    # UTF-8 multi-byte: U+00E9 = 0xC3 0xA9 (pass-through)
    var utf8 = List[UInt8]()
    utf8.append(0xC3); utf8.append(0xA9)
    _check_escape_differential(utf8)


def test_simd_escape_mixed() raises:
    # 32 clean bytes, then a quote, then 32 more clean bytes
    var mixed = List[UInt8]()
    for _ in range(32):
        mixed.append(0x61)  # 'a'
    mixed.append(0x22)  # '"'
    for _ in range(32):
        mixed.append(0x62)  # 'b'
    _check_escape_differential(mixed)

    # Dirty byte at offset 0, rest clean (31 bytes)
    var first_dirty = List[UInt8]()
    first_dirty.append(0x0A)
    for _ in range(31):
        first_dirty.append(0x63)
    _check_escape_differential(first_dirty)

    # Dirty byte at offset 31 in a 32-byte chunk
    var last_dirty = List[UInt8]()
    for _ in range(31):
        last_dirty.append(0x64)
    last_dirty.append(0x5C)
    _check_escape_differential(last_dirty)

    # UTF-8 spanning chunk boundary: 31 clean + 2-byte UTF-8 (crosses byte 32)
    var span_utf8 = List[UInt8]()
    for _ in range(31):
        span_utf8.append(0x65)
    span_utf8.append(0xC3); span_utf8.append(0xA9)
    _check_escape_differential(span_utf8)


def main() raises:
    test_escaping()
    test_escaped_buf()
    test_numbers()
    test_finite_guard()
    test_pretty_colon_and_indent()
    test_raw_bulk()
    test_int_boundaries()
    test_uint_boundaries()
    test_simd_escape_boundaries()
    test_simd_escape_dirty()
    test_simd_escape_mixed()
    print("test_writer: all passed")
