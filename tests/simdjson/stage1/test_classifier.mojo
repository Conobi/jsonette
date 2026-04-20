from std.testing import assert_true, assert_equal

from simdjson.stage1.simd_ops import SimdInput
from simdjson.stage1.classifier import classify, CharacterBlock


def pad_to_64(s: String) -> List[UInt8]:
    """Pad a string to 64 bytes with zeros."""
    var buf = List[UInt8](capacity=64)
    var bytes = s.as_bytes()
    for i in range(len(bytes)):
        buf.append(bytes[i])
    while len(buf) < 64:
        buf.append(UInt8(0))
    return buf^


def bit_set(mask: UInt64, pos: Int) -> Bool:
    """Check if bit at pos is set in mask."""
    return ((mask >> UInt64(pos)) & 1) != 0


def test_object_simple() raises:
    """Test {"a": 1} - operators and whitespace."""
    var buf = pad_to_64('{"a": 1}')
    var input = SimdInput.load(buf.unsafe_ptr())
    var result = classify(input)

    # {"a": 1}
    # pos: 0123456 7
    # { at position 0
    assert_true(bit_set(result.op, 0), '{ at pos 0')
    # : at position 4
    assert_true(bit_set(result.op, 4), ': at pos 4')
    # } at position 7
    assert_true(bit_set(result.op, 7), '} at pos 7')

    # space at position 5
    assert_true(bit_set(result.whitespace, 5), 'space at pos 5')

    # " characters should NOT be operators
    assert_true(not bit_set(result.op, 1), 'no op at pos 1')
    assert_true(not bit_set(result.op, 3), 'no op at pos 3')


def test_array_with_commas() raises:
    """Test [1, 2, 3] - brackets and commas."""
    var buf = pad_to_64("[1, 2, 3]")
    var input = SimdInput.load(buf.unsafe_ptr())
    var result = classify(input)

    # [ at position 0
    assert_true(bit_set(result.op, 0), '[ at pos 0')
    # ] at position 8
    assert_true(bit_set(result.op, 8), '] at pos 8')
    # , at position 2
    assert_true(bit_set(result.op, 2), ', at pos 2')
    # , at position 5
    assert_true(bit_set(result.op, 5), ', at pos 5')

    # spaces at positions 3 and 6
    assert_true(bit_set(result.whitespace, 3), 'space at pos 3')
    assert_true(bit_set(result.whitespace, 6), 'space at pos 6')


def test_zero_padding_no_false_positives() raises:
    """NUL bytes (0x00) should not be classified as whitespace or operators."""
    var buf = List[UInt8](capacity=64)
    for _ in range(64):
        buf.append(UInt8(0))
    var input = SimdInput.load(buf.unsafe_ptr())
    var result = classify(input)

    assert_equal(result.op, UInt64(0))
    assert_equal(result.whitespace, UInt64(0))


def main() raises:
    test_object_simple()
    test_array_with_commas()
    test_zero_padding_no_false_positives()
    print("test_classifier: all passed")
