from std.testing import assert_equal
from std.memory import bitcast
from simdjson.tape import tape_tag, tape_payload
from simdjson.stage1.indexer import structural_index
from simdjson.stage2.builder import build_tape


def _make_bytes(s: String) -> List[UInt8]:
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def _pad(data: List[UInt8]) -> List[UInt8]:
    """Pad buffer: input + 128 zero bytes."""
    var n = len(data)
    var num_chunks = (n + 63) // 64
    var padded_len = num_chunks * 64 + 128
    var buf = List[UInt8](capacity=padded_len)
    for i in range(n):
        buf.append(data[i])
    while len(buf) < padded_len:
        buf.append(UInt8(0))
    return buf^


def test_literal_true() raises:
    """Parse 'true' — simplest valid JSON."""
    var input = _make_bytes(String("true"))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    # tape[0] = root open 'r', tape[1] = 't', tape[2] = root close 'r'
    assert_equal(len(tape.elements), 3)
    assert_equal(tape.tag_at(0), UInt8(0x72))  # 'r'
    assert_equal(tape.tag_at(1), UInt8(0x74))  # 't'
    assert_equal(tape.tag_at(2), UInt8(0x72))  # 'r'
    assert_equal(tape.payload_at(0), UInt64(2))
    assert_equal(tape.payload_at(2), UInt64(0))


def test_literal_false() raises:
    var input = _make_bytes(String("false"))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    assert_equal(tape.tag_at(1), UInt8(0x66))  # 'f'


def test_literal_null() raises:
    var input = _make_bytes(String("null"))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    assert_equal(tape.tag_at(1), UInt8(0x6E))  # 'n'


def test_empty_array() raises:
    var input = _make_bytes(String("[]"))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    # tape: r, [, ], r
    assert_equal(len(tape.elements), 4)
    assert_equal(tape.tag_at(1), UInt8(0x5B))  # '['
    assert_equal(tape.tag_at(2), UInt8(0x5D))  # ']'
    # '[' payload: count=0, close+1=3
    assert_equal(tape.payload_at(1) & 0xFFFFFFFF, UInt64(3))
    assert_equal((tape.payload_at(1) >> 32) & 0xFFFFFF, UInt64(0))
    # ']' payload: points back to '['
    assert_equal(tape.payload_at(2), UInt64(1))


def test_empty_object() raises:
    var input = _make_bytes(String("{}"))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    assert_equal(len(tape.elements), 4)
    assert_equal(tape.tag_at(1), UInt8(0x7B))  # '{'
    assert_equal(tape.tag_at(2), UInt8(0x7D))  # '}'
    assert_equal(tape.payload_at(2), UInt64(1))


def test_nested_containers() raises:
    var input = _make_bytes(String("[[]]"))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    # tape: r, [outer, [inner, ]inner, ]outer, r
    assert_equal(len(tape.elements), 6)
    assert_equal(tape.tag_at(1), UInt8(0x5B))  # outer [
    assert_equal(tape.tag_at(2), UInt8(0x5B))  # inner [
    assert_equal(tape.tag_at(3), UInt8(0x5D))  # inner ]
    assert_equal(tape.tag_at(4), UInt8(0x5D))  # outer ]
    assert_equal(tape.payload_at(3), UInt64(2))
    assert_equal(tape.payload_at(4), UInt64(1))
    # Outer [ count=1, close+1=5
    assert_equal(tape.payload_at(1) & 0xFFFFFFFF, UInt64(5))
    assert_equal((tape.payload_at(1) >> 32) & 0xFFFFFF, UInt64(1))


def test_array_with_literals() raises:
    var input = _make_bytes(String("[true, false, null]"))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    # tape: r, [, true, false, null, ], r
    assert_equal(len(tape.elements), 7)
    assert_equal(tape.tag_at(2), UInt8(0x74))  # 't'
    assert_equal(tape.tag_at(3), UInt8(0x66))  # 'f'
    assert_equal(tape.tag_at(4), UInt8(0x6E))  # 'n'
    assert_equal((tape.payload_at(1) >> 32) & 0xFFFFFF, UInt64(3))


def test_number_in_array() raises:
    var input = _make_bytes(String("[42, -7]"))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    # tape: r, [, u(42), 42, l(-7), -7, ], r
    assert_equal(len(tape.elements), 8)
    assert_equal(tape.tag_at(2), UInt8(0x75))  # 'u'
    assert_equal(tape.elements[3], UInt64(42))
    assert_equal(tape.tag_at(4), UInt8(0x6C))  # 'l'
    var neg7 = Int64(bitcast[DType.int64](SIMD[DType.uint64, 1](tape.elements[5])))
    assert_equal(neg7, Int64(-7))


def test_string_value() raises:
    var input = _make_bytes(String('["hello"]'))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    assert_equal(tape.tag_at(2), UInt8(0x22))  # '"'
    var offset = Int(tape.payload_at(2))
    assert_equal(tape.string_buf[offset], UInt8(5))  # length
    assert_equal(tape.string_buf[offset + 4], UInt8(0x68))  # 'h'
    assert_equal(tape.string_buf[offset + 8], UInt8(0x6F))  # 'o'


def test_object_with_values() raises:
    var input = _make_bytes(String('{"a": 1, "b": true}'))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    assert_equal(tape.tag_at(1), UInt8(0x7B))  # '{'
    assert_equal(tape.tag_at(2), UInt8(0x22))  # '"' key "a"
    assert_equal(tape.tag_at(3), UInt8(0x75))  # 'u' value 1
    assert_equal(tape.elements[4], UInt64(1))
    assert_equal(tape.tag_at(5), UInt8(0x22))  # '"' key "b"
    assert_equal(tape.tag_at(6), UInt8(0x74))  # 't' true
    assert_equal(tape.tag_at(7), UInt8(0x7D))  # '}'
    assert_equal((tape.payload_at(1) >> 32) & 0xFFFFFF, UInt64(2))


def test_float_in_object() raises:
    var input = _make_bytes(String('{"pi": 3.14}'))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    assert_equal(tape.tag_at(3), UInt8(0x64))  # 'd'
    var float_bits = tape.elements[4]
    var val = Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](float_bits)))
    var diff = val - 3.14
    if diff < 0.0:
        diff = -diff
    assert_equal(diff < 0.001, True)


def test_nested_object_array() raises:
    var input = _make_bytes(String('{"arr": [1, 2]}'))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    assert_equal(tape.tag_at(0), UInt8(0x72))  # root
    assert_equal(tape.tag_at(1), UInt8(0x7B))  # '{'
    assert_equal((tape.payload_at(1) >> 32) & 0xFFFFFF, UInt64(1))


def test_scalar_root_number() raises:
    var input = _make_bytes(String("42"))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    # tape: r, u(42), 42, r
    assert_equal(len(tape.elements), 4)
    assert_equal(tape.tag_at(1), UInt8(0x75))
    assert_equal(tape.elements[2], UInt64(42))


def test_scalar_root_string() raises:
    var input = _make_bytes(String('"hello"'))
    var input_len = len(input)
    var padded = _pad(input)
    var positions = structural_index(padded, input_len)
    var tape = build_tape(padded, input_len, positions)
    assert_equal(tape.tag_at(1), UInt8(0x22))


def main() raises:
    test_literal_true()
    test_literal_false()
    test_literal_null()
    test_empty_array()
    test_empty_object()
    test_nested_containers()
    test_array_with_literals()
    test_number_in_array()
    test_string_value()
    test_object_with_values()
    test_float_in_object()
    test_nested_object_array()
    test_scalar_root_number()
    test_scalar_root_string()
    print("test_builder: all passed")
