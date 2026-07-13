from std.testing import assert_equal
from std.memory import memcpy, memset
from jsonette.stage1.indexer import structural_index
from jsonette.stage2.strings import _raw_string_span
from jsonette.ondemand.reader import iter as od_iter


def _pad_and_index(
    s: String, mut buf: List[UInt8], mut positions: List[UInt32]
) raises:
    """Pad input and run Stage 1 to fill buf and positions."""
    var data = s.as_bytes()
    var input_len = len(data)
    var num_chunks = (input_len + 63) // 64
    var padded_len = num_chunks * 64 + 128
    buf = List[UInt8](unsafe_uninit_length=padded_len)
    memcpy(dest=buf.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
    memset(buf.unsafe_ptr() + input_len, 0, padded_len - input_len)
    positions = List[UInt32]()
    structural_index(buf.unsafe_ptr(), input_len, positions)


def test_simple_string() raises:
    """Raw span of a simple string returns correct pointer and length."""
    var buf = List[UInt8]()
    var pos = List[UInt32]()
    _pad_and_index(String('"hello"'), buf, pos)
    var span = _raw_string_span(pos, 0, buf.unsafe_ptr())
    assert_equal(span[1], 5)
    assert_equal(span[0][0], UInt8(ord("h")))
    assert_equal(span[0][1], UInt8(ord("e")))
    assert_equal(span[0][2], UInt8(ord("l")))
    assert_equal(span[0][3], UInt8(ord("l")))
    assert_equal(span[0][4], UInt8(ord("o")))


def test_empty_string() raises:
    """Raw span of an empty string returns length 0."""
    var buf = List[UInt8]()
    var pos = List[UInt32]()
    _pad_and_index(String('""'), buf, pos)
    var span = _raw_string_span(pos, 0, buf.unsafe_ptr())
    assert_equal(span[1], 0)


def test_string_with_escape() raises:
    """Raw span includes the raw bytes including the backslash (no unescaping)."""
    var buf = List[UInt8]()
    var pos = List[UInt32]()
    _pad_and_index(String('"he\\nlo"'), buf, pos)
    var span = _raw_string_span(pos, 0, buf.unsafe_ptr())
    # Content is he\nlo = 6 raw bytes (backslash + n, not a newline)
    assert_equal(span[1], 6)


def test_escaped_quote() raises:
    """Escaped quotes are NOT structurals — closing quote is correct."""
    var buf = List[UInt8]()
    var pos = List[UInt32]()
    _pad_and_index(String('"say \\"hi\\""'), buf, pos)
    var span = _raw_string_span(pos, 0, buf.unsafe_ptr())
    # Content: say \"hi\" = 10 raw bytes
    assert_equal(span[1], 10)


def test_object_key_value() raises:
    """In an object, the key's raw span gives the key content."""
    var buf = List[UInt8]()
    var pos = List[UInt32]()
    _pad_and_index(String('{"key":"val"}'), buf, pos)
    # For {"key":"val"}, structurals are: { " " : " " }
    # positions[0] = { (offset 0)
    # positions[1] = " (key open, offset 1)
    # positions[2] = " (key close, offset 5)
    # positions[3] = : (offset 6)
    # positions[4] = " (val open, offset 7)
    # positions[5] = " (val close, offset 11)
    # positions[6] = } (offset 12)

    # Key span: si=1, content starts at offset 2, length = 5-1-1 = 3
    var key_span = _raw_string_span(pos, 1, buf.unsafe_ptr())
    assert_equal(key_span[1], 3)  # "key" = 3 bytes
    assert_equal(key_span[0][0], UInt8(ord("k")))
    assert_equal(key_span[0][1], UInt8(ord("e")))
    assert_equal(key_span[0][2], UInt8(ord("y")))

    # Value span: si=4, content starts at offset 8, length = 11-7-1 = 3
    var val_span = _raw_string_span(pos, 4, buf.unsafe_ptr())
    assert_equal(val_span[1], 3)  # "val" = 3 bytes
    assert_equal(val_span[0][0], UInt8(ord("v")))
    assert_equal(val_span[0][1], UInt8(ord("a")))
    assert_equal(val_span[0][2], UInt8(ord("l")))


def test_od_get_string_clean() raises:
    """OD get_string for escape-free strings returns correct value."""
    var json = String('{"name": "Ada Lovelace", "city": "London"}')
    var reader = od_iter(json)
    var obj = reader.root().get_object()
    assert_equal(obj.field("name").get_string(), "Ada Lovelace")


def test_od_get_string_escaped() raises:
    """OD get_string for strings with escapes falls back correctly."""
    var json = String('{"msg": "hello\\nworld"}')
    var reader = od_iter(json)
    var obj = reader.root().get_object()
    assert_equal(obj.field("msg").get_string(), "hello\nworld")


def test_od_get_string_empty() raises:
    """OD get_string for empty strings works."""
    var json = String('{"e": ""}')
    var reader = od_iter(json)
    assert_equal(reader.root().get_object().field("e").get_string(), "")


def test_od_get_string_unicode_escape() raises:
    """OD get_string for unicode escapes falls back correctly."""
    var json = String('{"u": "\\u0041"}')
    var reader = od_iter(json)
    assert_equal(reader.root().get_object().field("u").get_string(), "A")


def main() raises:
    test_simple_string()
    test_empty_string()
    test_string_with_escape()
    test_escaped_quote()
    test_object_key_value()
    test_od_get_string_clean()
    test_od_get_string_escaped()
    test_od_get_string_empty()
    test_od_get_string_unicode_escape()
    print("All raw string span tests passed!")
