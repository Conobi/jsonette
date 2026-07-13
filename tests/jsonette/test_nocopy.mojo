from std.testing import assert_equal
from std.memory import memcpy, memset, UnsafePointer
from jsonette.document import parse, parse_nocopy
from jsonette.ondemand.reader import iter as od_iter, iter_nocopy


def _make_padded(s: String) -> List[UInt8]:
    """Create a padded buffer matching Parser's formula: ceil(n/64)*64 + 128."""
    var data = s.as_bytes()
    var input_len = len(data)
    var num_chunks = (input_len + 63) // 64
    var padded_len = num_chunks * 64 + 128
    var buf = List[UInt8](unsafe_uninit_length=padded_len)
    memcpy(dest=buf.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
    memset(buf.unsafe_ptr() + input_len, 0, padded_len - input_len)
    return buf^


def test_nocopy_parse_object() raises:
    """Nocopy parse produces identical results to copy parse."""
    var json = String('{"name": "Ada", "age": 30}')
    var padded = _make_padded(json)

    var doc_copy = parse(json)
    var doc_nc = parse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )

    assert_equal(doc_copy.root().field("name").get_string(), "Ada")
    assert_equal(doc_nc.root().field("name").get_string(), "Ada")
    assert_equal(
        doc_copy.root().field("age").get_uint(),
        doc_nc.root().field("age").get_uint(),
    )
    _ = padded^


def test_nocopy_reparse() raises:
    """Nocopy reparse reuses buffers and produces correct results."""
    var json1 = String('{"x": 1}')
    var json2 = String('{"x": 2}')
    var padded1 = _make_padded(json1)
    var padded2 = _make_padded(json2)

    var doc = parse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded1.unsafe_ptr()),
        len(json1.as_bytes()),
    )
    assert_equal(doc.root().field("x").get_uint(), UInt64(1))

    doc.reparse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded2.unsafe_ptr()),
        len(json2.as_bytes()),
    )
    assert_equal(doc.root().field("x").get_uint(), UInt64(2))
    _ = padded1^
    _ = padded2^


def test_nocopy_iter() raises:
    """Nocopy On-Demand iter produces correct results."""
    var json = String('{"key": "value"}')
    var padded = _make_padded(json)

    var reader = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )
    var root = reader.root()
    var obj = root.get_object()
    var f = obj.field("key")
    assert_equal(f.get_string(), "value")
    _ = padded^


def test_nocopy_matches_copy() raises:
    """Nocopy and copy parse produce identical results for complex input."""
    var json = String('{"arr": [1, 2.5, true, null, "hello\\nworld"]}')
    var padded = _make_padded(json)

    var doc_copy = parse(json)
    var doc_nc = parse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded.unsafe_ptr()),
        len(json.as_bytes()),
    )

    var c_arr = doc_copy.root().field("arr")
    var n_arr = doc_nc.root().field("arr")
    assert_equal(c_arr.len(), n_arr.len())
    assert_equal(c_arr.elem(0).get_uint(), n_arr.elem(0).get_uint())
    assert_equal(c_arr.elem(1).get_float(), n_arr.elem(1).get_float())
    assert_equal(c_arr.elem(2).get_bool(), n_arr.elem(2).get_bool())
    assert_equal(c_arr.elem(3).is_null(), n_arr.elem(3).is_null())
    assert_equal(c_arr.elem(4).get_string(), n_arr.elem(4).get_string())
    _ = padded^


def test_nocopy_iter_reparse() raises:
    """Nocopy On-Demand reparse works correctly."""
    var json1 = String('{"a": 10}')
    var json2 = String('{"a": 20}')
    var padded1 = _make_padded(json1)
    var padded2 = _make_padded(json2)

    var reader = iter_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded1.unsafe_ptr()),
        len(json1.as_bytes()),
    )
    assert_equal(reader.root().get_object().field("a").get_uint(), UInt64(10))

    reader.reparse_nocopy(
        UnsafePointer[UInt8, MutAnyOrigin](padded2.unsafe_ptr()),
        len(json2.as_bytes()),
    )
    assert_equal(reader.root().get_object().field("a").get_uint(), UInt64(20))
    _ = padded1^
    _ = padded2^


def main() raises:
    test_nocopy_parse_object()
    test_nocopy_reparse()
    test_nocopy_iter()
    test_nocopy_matches_copy()
    test_nocopy_iter_reparse()
    print("All nocopy tests passed!")
