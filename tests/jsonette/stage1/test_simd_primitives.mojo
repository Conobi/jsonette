from std.testing import assert_equal
from jsonette.stage1.simd_ops import movemask_epi8, shuffle_epi8, prefix_xor, SimdInput


def test_movemask() raises:
    var v = SIMD[DType.uint8, 32](0)
    v[0] = 0xFF
    v[1] = 0xFF
    v[7] = 0xFF
    v[31] = 0xFF
    var mask = movemask_epi8(v)
    var expected = Int32((1 << 0) | (1 << 1) | (1 << 7) | (1 << 31))
    assert_equal(mask, expected)


def test_shuffle_identity() raises:
    var table = SIMD[DType.uint8, 32](0)
    for i in range(16):
        table[i] = UInt8(i)
        table[i + 16] = UInt8(i)
    var indices = SIMD[DType.uint8, 32](0)
    indices[0] = 5
    indices[1] = 10
    indices[16] = 3
    var result = shuffle_epi8(table, indices)
    assert_equal(result[0], UInt8(5))
    assert_equal(result[1], UInt8(10))
    assert_equal(result[16], UInt8(3))


def test_shuffle_high_bit_zeroes() raises:
    var table = SIMD[DType.uint8, 32](0xFF)
    var indices = SIMD[DType.uint8, 32](0x80)
    var result = shuffle_epi8(table, indices)
    assert_equal(result[0], UInt8(0))
    assert_equal(result[15], UInt8(0))


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
    test_movemask()
    test_shuffle_identity()
    test_shuffle_high_bit_zeroes()
    test_prefix_xor()
    test_simdinput_eq()
    test_simdinput_lteq()
    print("test_simd_primitives: all passed")
