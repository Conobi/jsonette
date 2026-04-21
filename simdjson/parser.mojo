from std.memory import memcpy, memset

from simdjson.tape import Tape
from simdjson.document import Document
from simdjson.error import format_parse_error
from simdjson.stage1.indexer import structural_index
from simdjson.stage2.builder import build_tape


struct Parser:
    """JSON parser. Orchestrates Stage 1 + Stage 2."""

    var container_stack: List[UInt32]  # interleaved: [open_idx, count, open_idx, count, ...]
    var count_stack: List[UInt32]     # unused after interleaving, kept for API compat

    def __init__(out self):
        self.container_stack = List[UInt32](capacity=2048)  # MAX_DEPTH * 2
        self.count_stack = List[UInt32](capacity=1024)

    def __init__(out self, *, deinit take: Self):
        self.container_stack = take.container_stack^
        self.count_stack = take.count_stack^

    def parse(mut self, data: List[UInt8]) raises -> Document:
        """Parse JSON bytes into a Document."""
        var input_len = len(data)

        # Create padded buffer: input + 128 zero bytes (enough for SIMD overread)
        var num_chunks = (input_len + 63) // 64
        var padded_len = num_chunks * 64 + 128
        var padded = List[UInt8](unsafe_uninit_length=padded_len)
        memcpy(dest=padded.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
        memset(padded.unsafe_ptr() + input_len, 0, padded_len - input_len)

        var positions = structural_index(padded, input_len)
        self.container_stack.resize(0, UInt32(0))
        self.count_stack.resize(0, UInt32(0))
        try:
            var tape = build_tape(padded, input_len, positions, self.container_stack, self.count_stack)
            var doc = Document(tape^)
            return doc^
        except e:
            raise format_parse_error(e.code, e.position)
