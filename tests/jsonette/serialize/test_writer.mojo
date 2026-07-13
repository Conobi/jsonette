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


def main() raises:
    test_escaping()
    test_escaped_buf()
    test_numbers()
    test_finite_guard()
    test_pretty_colon_and_indent()
    test_raw_bulk()
    print("test_writer: all passed")
