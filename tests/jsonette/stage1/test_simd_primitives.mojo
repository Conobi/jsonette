from std.testing import assert_equal
from jsonette.stage1.simd_ops import shuffle_bytes, prefix_xor, SimdInput


def test_shuffle_bytes_identity() raises:
    # table[i] = i, so r[i] = table[indices[i]] = indices[i], in both lanes.
    var table = SIMD[DType.uint8, 16](0)
    for i in range(16):
        table[i] = UInt8(i)
    var indices = SIMD[DType.uint8, 32](0)
    indices[0] = 5
    indices[1] = 10
    indices[7] = 3
    indices[15] = 12
    indices[16] = 7  # second 128-bit lane reuses the same 16-byte table
    indices[31] = 9
    var result = shuffle_bytes(table, indices)
    assert_equal(result[0], UInt8(5))
    assert_equal(result[1], UInt8(10))
    assert_equal(result[7], UInt8(3))
    assert_equal(result[15], UInt8(12))
    assert_equal(result[16], UInt8(7))
    assert_equal(result[31], UInt8(9))


def test_shuffle_bytes_table() raises:
    # Classifier-style constant lookup table: each index returns its entry.
    var table = SIMD[DType.uint8, 16](
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 4, 8, 0, 0,
    )
    var indices = SIMD[DType.uint8, 32](0)
    indices[0] = 10  # -> 1
    indices[1] = 11  # -> 2
    indices[2] = 12  # -> 4
    indices[3] = 13  # -> 8
    indices[4] = 9  # -> 0
    indices[20] = 13  # second lane -> 8
    var result = shuffle_bytes(table, indices)
    assert_equal(result[0], UInt8(1))
    assert_equal(result[1], UInt8(2))
    assert_equal(result[2], UInt8(4))
    assert_equal(result[3], UInt8(8))
    assert_equal(result[4], UInt8(0))
    assert_equal(result[20], UInt8(8))


def test_prefix_xor() raises:
    # Quotes at positions 2 and 5: bits 2,3,4 should be "in string"
    var q: UInt64 = (1 << 2) | (1 << 5)
    var result = prefix_xor(q)
    assert_equal(result, UInt64(28))

    # Single bit at position 0: all subsequent bits flipped
    var q2: UInt64 = 1
    var r2 = prefix_xor(q2)
    assert_equal(r2, ~UInt64(0))


def test_simdinput_eq() raises:
    var buf = List[UInt8](capacity=64)
    for _ in range(64):
        buf.append(UInt8(ord('x')))
    buf[1] = UInt8(ord('"'))
    buf[40] = UInt8(ord('"'))
    var input = SimdInput.load(buf.unsafe_ptr())
    var mask = input.eq(UInt8(ord('"')))
    assert_equal(mask, (UInt64(1) << 1) | (UInt64(1) << 40))


def test_simdinput_lteq() raises:
    var buf = List[UInt8](capacity=64)
    for _ in range(64):
        buf.append(UInt8(0x20))
    buf[0] = UInt8(0x09)
    buf[5] = UInt8(0x01)
    var input = SimdInput.load(buf.unsafe_ptr())
    var mask = input.lteq(UInt8(0x1F))
    assert_equal(mask & 1, UInt64(1))
    assert_equal((mask >> 5) & 1, UInt64(1))
    assert_equal((mask >> 1) & 1, UInt64(0))


def main() raises:
    test_shuffle_bytes_identity()
    test_shuffle_bytes_table()
    test_prefix_xor()
    test_simdinput_eq()
    test_simdinput_lteq()
    print("test_simd_primitives: all passed")
