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


def main() raises:
    test_escaping()
    test_escaped_buf()
    test_numbers()
    test_finite_guard()
    test_pretty_colon_and_indent()
    test_raw_bulk()
    test_int_boundaries()
    test_uint_boundaries()
    print("test_writer: all passed")
