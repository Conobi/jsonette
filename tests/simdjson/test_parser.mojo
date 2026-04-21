from std.testing import assert_equal
from simdjson.tape import Tape
from simdjson.document import Document


def test_document_root() raises:
    """Document.root() returns Value at tape index 1."""
    var tape = Tape()
    tape.elements.append((UInt64(0x72) << 56) | UInt64(2))  # root open -> 2
    tape.elements.append(UInt64(0x74) << 56)  # true
    tape.elements.append(UInt64(0x72) << 56)  # root close
    var doc = Document(tape^)
    var root = doc.root()
    assert_equal(root._idx, 1)


def main() raises:
    test_document_root()
    print("test_parser: all passed")
