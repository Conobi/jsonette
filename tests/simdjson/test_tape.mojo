from std.testing import assert_equal
from simdjson.tape import Tape, make_tape_entry, tape_tag, tape_payload
from simdjson.tape import TAG_ROOT, TAG_OBJECT_OPEN, TAG_OBJECT_CLOSE, TAG_ARRAY_OPEN, TAG_ARRAY_CLOSE, TAG_STRING, TAG_INT64, TAG_UINT64, TAG_FLOAT64, TAG_TRUE, TAG_FALSE, TAG_NULL


def test_make_tape_entry() raises:
    """Encode and decode a tape entry."""
    var entry = make_tape_entry(UInt8(0x72), UInt64(42))  # 'r', payload 42
    assert_equal(tape_tag(entry), UInt8(0x72))
    assert_equal(tape_payload(entry), UInt64(42))


def test_tape_append_and_read() raises:
    """Append entries and read them back."""
    var tape = Tape()
    tape.append(UInt8(0x72), UInt64(0))  # root open
    tape.append(UInt8(0x74), UInt64(0))  # true
    tape.append(UInt8(0x72), UInt64(0))  # root close
    assert_equal(len(tape.elements), 3)
    assert_equal(tape.tag_at(0), UInt8(0x72))
    assert_equal(tape.tag_at(1), UInt8(0x74))


def test_tape_back_patch() raises:
    """Back-patch a container open entry."""
    var tape = Tape()
    tape.append(UInt8(0x5B), UInt64(0))  # '[' placeholder
    tape.append(UInt8(0x74), UInt64(0))  # true
    # Back-patch open: count=1, close_idx+1=3
    var patched = make_tape_entry(UInt8(0x5B), (UInt64(1) << 32) | UInt64(3))
    tape.elements[0] = patched
    assert_equal(tape_payload(tape.elements[0]) & 0xFFFFFFFF, UInt64(3))
    assert_equal((tape_payload(tape.elements[0]) >> 32) & 0xFFFFFF, UInt64(1))


def test_string_buf_write_read() raises:
    """Write a string to string_buf and verify layout."""
    var tape = Tape()
    var offset = len(tape.string_buf)
    # Write length prefix (3 bytes, little-endian)
    tape.string_buf.append(UInt8(3))
    tape.string_buf.append(UInt8(0))
    tape.string_buf.append(UInt8(0))
    tape.string_buf.append(UInt8(0))
    # Write bytes "abc"
    tape.string_buf.append(UInt8(0x61))  # a
    tape.string_buf.append(UInt8(0x62))  # b
    tape.string_buf.append(UInt8(0x63))  # c
    # Null terminator
    tape.string_buf.append(UInt8(0))

    # Read back length
    var str_len = UInt32(tape.string_buf[offset])
    assert_equal(str_len, UInt32(3))
    # Read back bytes
    assert_equal(tape.string_buf[offset + 4], UInt8(0x61))
    assert_equal(tape.string_buf[offset + 5], UInt8(0x62))
    assert_equal(tape.string_buf[offset + 6], UInt8(0x63))
    assert_equal(tape.string_buf[offset + 7], UInt8(0))


def test_tag_constants() raises:
    assert_equal(TAG_ROOT, UInt8(0x72))
    assert_equal(TAG_OBJECT_OPEN, UInt8(0x7B))
    assert_equal(TAG_OBJECT_CLOSE, UInt8(0x7D))
    assert_equal(TAG_ARRAY_OPEN, UInt8(0x5B))
    assert_equal(TAG_ARRAY_CLOSE, UInt8(0x5D))
    assert_equal(TAG_STRING, UInt8(0x22))
    assert_equal(TAG_INT64, UInt8(0x6C))
    assert_equal(TAG_UINT64, UInt8(0x75))
    assert_equal(TAG_FLOAT64, UInt8(0x64))
    assert_equal(TAG_TRUE, UInt8(0x74))
    assert_equal(TAG_FALSE, UInt8(0x66))
    assert_equal(TAG_NULL, UInt8(0x6E))


def main() raises:
    test_make_tape_entry()
    test_tape_append_and_read()
    test_tape_back_patch()
    test_string_buf_write_read()
    test_tag_constants()
    print("test_tape: all passed")
