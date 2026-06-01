from std.testing import assert_true, assert_equal

from simdjson.stage1.indexer import BitIndexer, structural_index


def _pad(data: List[UInt8]) -> List[UInt8]:
    """Pad buffer for Stage 1: input + 128 zero bytes."""
    var n = len(data)
    var num_chunks = (n + 63) // 64
    var padded_len = num_chunks * 64 + 128
    var buf = List[UInt8](capacity=padded_len)
    for i in range(n):
        buf.append(data[i])
    while len(buf) < padded_len:
        buf.append(UInt8(0))
    return buf^


def _index(padded: List[UInt8], input_len: Int) -> List[UInt32]:
    """Run Stage 1 into a fresh buffer and return the structural positions."""
    var positions = List[UInt32]()
    structural_index(padded, input_len, positions)
    return positions^


# ===== BitIndexer tests =====


def test_bit_indexer_empty() raises:
    """Empty bitmask produces no positions."""
    var bi = BitIndexer(64)
    bi.write(UInt32(0), UInt64(0))
    assert_equal(bi.write_pos, 0)


def test_bit_indexer_single_bit() raises:
    """Single bit at position 5."""
    var bi = BitIndexer(64)
    bi.write(UInt32(0), UInt64(1) << 5)
    assert_equal(bi.write_pos, 1)
    assert_equal(bi.positions.unsafe_ptr()[0], UInt32(5))


def test_bit_indexer_multiple_bits_with_base() raises:
    """Multiple bits (0, 3, 7, 63) with base_idx=100."""
    var bi = BitIndexer(64)
    var bits = (UInt64(1) << 0) | (UInt64(1) << 3) | (UInt64(1) << 7) | (UInt64(1) << 63)
    bi.write(UInt32(100), bits)
    assert_equal(bi.write_pos, 4)
    assert_equal(bi.positions.unsafe_ptr()[0], UInt32(100))
    assert_equal(bi.positions.unsafe_ptr()[1], UInt32(103))
    assert_equal(bi.positions.unsafe_ptr()[2], UInt32(107))
    assert_equal(bi.positions.unsafe_ptr()[3], UInt32(163))


def test_bit_indexer_all_bits_set() raises:
    """All 64 bits set produces positions 0..63."""
    var bi = BitIndexer(64)
    bi.write(UInt32(0), ~UInt64(0))
    assert_equal(bi.write_pos, 64)
    for i in range(64):
        assert_equal(bi.positions.unsafe_ptr()[i], UInt32(i))


# ===== structural_index integration tests =====


def has_position(positions: List[UInt32], pos: UInt32) -> Bool:
    """Check if a position exists in the list."""
    for i in range(len(positions)):
        if positions[i] == pos:
            return True
    return False


def test_structural_index_empty_object() raises:
    """{} -> exactly 2 positions: 0, 1."""
    var data = List[UInt8]()
    var s = String("{}")
    var bytes = s.as_bytes()
    for i in range(len(bytes)):
        data.append(bytes[i])
    var positions = _index(_pad(data), len(data))
    assert_equal(len(positions), 2)
    assert_equal(positions[0], UInt32(0))
    assert_equal(positions[1], UInt32(1))


def test_structural_index_simple_object() raises:
    """{"a":1} -> structural positions include {, ", a-quote, :, scalar start for 1, }."""
    var data = List[UInt8]()
    var s = String('{"a":1}')
    var bytes = s.as_bytes()
    for i in range(len(bytes)):
        data.append(bytes[i])
    var positions = _index(_pad(data), len(data))

    # Must contain: { at 0, " at 1, " at 3, : at 4, 1-start at 5, } at 6
    assert_true(has_position(positions, UInt32(0)), "missing {")
    assert_true(has_position(positions, UInt32(1)), "missing opening quote for key")
    assert_true(has_position(positions, UInt32(3)), "missing closing quote for key")
    assert_true(has_position(positions, UInt32(4)), "missing :")
    assert_true(has_position(positions, UInt32(5)), "missing scalar start for 1")
    assert_true(has_position(positions, UInt32(6)), "missing }")


def test_structural_index_nested() raises:
    """{"a": [1, 2], "b": {"c": true}} -> verify key structural positions."""
    var data = List[UInt8]()
    var s = String('{"a": [1, 2], "b": {"c": true}}')
    var bytes = s.as_bytes()
    for i in range(len(bytes)):
        data.append(bytes[i])
    var positions = _index(_pad(data), len(data))

    # { at 0
    assert_true(has_position(positions, UInt32(0)), "missing opening {")
    # [ at 6
    assert_true(has_position(positions, UInt32(6)), "missing [")
    # ] at 12
    assert_true(has_position(positions, UInt32(12)), "missing ]")
    # inner { at 20
    assert_true(has_position(positions, UInt32(20)), "missing inner {")
    # last } at 30
    assert_true(has_position(positions, UInt32(30)), "missing closing }")


def test_structural_index_escaped_quotes() raises:
    """Escaped quotes should NOT be in structural positions."""
    var data = List[UInt8]()
    # {"key": "val\"ue"}
    var s = String('{"key": "val\\"ue"}')
    var bytes = s.as_bytes()
    for i in range(len(bytes)):
        data.append(bytes[i])
    var positions = _index(_pad(data), len(data))

    # The escaped quote (preceded by \) should not appear as a structural position.
    # In the string: {"key": "val\"ue"}
    # Positions:      0123456789...
    # { at 0 should be present
    assert_true(has_position(positions, UInt32(0)), "missing {")
    # The last } should be present
    var last_pos = UInt32(len(s.as_bytes()) - 1)
    assert_true(has_position(positions, last_pos), "missing closing }")


def test_structural_index_long_string() raises:
    """Long string crossing chunk boundary - string content excluded from structurals."""
    var data = List[UInt8]()
    # Build: {"k": "<80+ chars>"}
    var s = String('{"k": "') + String("x") * 80 + String('"}')
    var bytes = s.as_bytes()
    for i in range(len(bytes)):
        data.append(bytes[i])
    var positions = _index(_pad(data), len(data))

    # { at 0
    assert_true(has_position(positions, UInt32(0)), "missing {")
    # The string content should NOT produce structural positions
    # The 'x' bytes inside the string (positions 7..86) should not appear
    var found_inner = False
    for i in range(len(positions)):
        if positions[i] > UInt32(7) and positions[i] < UInt32(87):
            found_inner = True
            break
    assert_true(not found_inner, "string content should not produce structural positions")


def main() raises:
    test_bit_indexer_empty()
    test_bit_indexer_single_bit()
    test_bit_indexer_multiple_bits_with_base()
    test_bit_indexer_all_bits_set()
    test_structural_index_empty_object()
    test_structural_index_simple_object()
    test_structural_index_nested()
    test_structural_index_escaped_quotes()
    test_structural_index_long_string()
    print("All indexer tests passed!")
