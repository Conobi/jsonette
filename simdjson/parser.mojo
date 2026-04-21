from simdjson.tape import Tape
from simdjson.document import Document
from simdjson.stage1.indexer import structural_index
from simdjson.stage2.builder import build_tape


struct Parser:
    """JSON parser. Orchestrates Stage 1 + Stage 2."""

    def __init__(out self):
        pass

    def parse(mut self, data: List[UInt8]) raises -> Document:
        """Parse JSON bytes into a Document."""
        var positions = structural_index(data)
        var tape = build_tape(data, positions)
        var doc = Document(tape^)
        return doc^
