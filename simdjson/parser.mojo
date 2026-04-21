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
        var input_len = len(data)

        # Create padded buffer: input + 128 zero bytes (enough for SIMD overread)
        var num_chunks = (input_len + 63) // 64
        var padded_len = num_chunks * 64 + 128
        var padded = List[UInt8](capacity=padded_len)
        for i in range(input_len):
            padded.append(data[i])
        while len(padded) < padded_len:
            padded.append(UInt8(0))

        var positions = structural_index(padded, input_len)
        var tape = build_tape(padded, input_len, positions)
        var doc = Document(tape^)
        return doc^
