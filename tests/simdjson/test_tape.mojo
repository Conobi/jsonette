from std.testing import assert_equal
from simdjson.tape import Tape, make_tape_entry, tape_tag, tape_payload


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


def main() raises:
    test_make_tape_entry()
    test_tape_append_and_read()
    test_tape_back_patch()
    test_string_buf_write_read()
    print("test_tape: all passed")
