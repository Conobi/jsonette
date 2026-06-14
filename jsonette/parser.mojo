from std.memory import memcpy, memset

from jsonette.tape import Tape
from jsonette.document import Document
from jsonette.error import format_parse_error
from jsonette._alloc_count import record_alloc
from jsonette.stage1.indexer import structural_index
from jsonette.stage2.builder import build_tape
from jsonette.ondemand.ondemand import ObjectHandle
from jsonette.ondemand.validate import _validate_document


struct Parser(Movable):
    """JSON parser. Orchestrates Stage 1 + Stage 2.

    Movable: the parser owns its reusable buffers and tape; moving it transfers
    that ownership (the existing `deinit take` constructor is the move). Any
    `Document` borrowing the old location is invalidated by the move, enforced by
    the Document's origin parameter."""

    var container_stack: List[UInt32]  # interleaved: [open_idx, count, open_idx, count, ...]
    var count_stack: List[UInt32]     # unused after interleaving, kept for API compat
    var padded: List[UInt8]           # reusable zero-padded input buffer (grows only)
    var positions: List[UInt32]       # reusable Stage 1 structural-offset buffer (grows only)
    var _tape: Tape                   # parser-owned tape, reused across parses (grows only)
    var _od_scratch: List[UInt8]      # reusable On-Demand string-unescape scratch (grows only)

    def __init__(out self):
        self.container_stack = List[UInt32](capacity=2048)  # MAX_DEPTH * 2
        self.count_stack = List[UInt32](capacity=1024)
        self.padded = List[UInt8]()
        self.positions = List[UInt32]()
        self._tape = Tape()  # empty Lists -> no allocation until first parse grows them
        self._od_scratch = List[UInt8]()  # empty -> allocated on first On-Demand string read

    def __init__(out self, *, deinit take: Self):
        self.container_stack = take.container_stack^
        self.count_stack = take.count_stack^
        self.padded = take.padded^
        self.positions = take.positions^
        self._tape = take._tape^
        self._od_scratch = take._od_scratch^

    def parse(mut self, data: List[UInt8]) raises -> Document[origin_of(self._tape)]:
        """Parse JSON bytes into a Document view over this parser's tape.

        The returned Document borrows this parser's tape; it is valid only while
        this parser is alive and is neither reparsed nor moved.
        """
        var input_len = len(data)

        # Reusable padded buffer: input + 128 zero bytes (enough for SIMD overread).
        # Grow only when the current input needs more room than prior parses.
        var num_chunks = (input_len + 63) // 64
        var padded_len = num_chunks * 64 + 128
        if len(self.padded) < padded_len:
            # Only the grow path allocates; a warm parser on same-size input
            # reuses the existing buffer and contributes 0 to allocs/op.
            record_alloc()
            self.padded = List[UInt8](unsafe_uninit_length=padded_len)
        memcpy(dest=self.padded.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
        memset(self.padded.unsafe_ptr() + input_len, 0, padded_len - input_len)

        # Reusable structural-offset buffer: grows only when a larger input needs
        # more room than prior parses; warm same-size reparses contribute 0 allocs.
        structural_index(self.padded, input_len, self.positions)
        self.container_stack.resize(0, UInt32(0))
        self.count_stack.resize(0, UInt32(0))
        try:
            build_tape(self.padded, input_len, self.positions, self.container_stack, self.count_stack, self._tape)
        except e:
            raise format_parse_error(e.code, e.position)
        return Document(self._tape)

    def document(mut self) -> Document[origin_of(self._tape)]:
        """Return a Document viewing this parser's most recent parse.

        Must be called only after at least one successful `parse(...)`. The
        returned Document borrows this parser's tape; it is valid only while the
        parser is alive and is neither reparsed nor moved. A subsequent
        `parse(...)` reuses the tape, so any earlier Document then reflects the
        new data (reparse invalidation) — obtain a fresh Document after each
        parse.

        Takes `mut self` to bind the borrow's origin as mutable, which the
        Document's origin parameter requires; it does not modify the parser.
        Lets embedders avoid reaching into the parser's internal tape field: a
        caller names the return type with `type_of(parser.document())`.
        """
        return Document(self._tape)

    def iter(mut self, data: List[UInt8]) raises -> ObjectHandle[origin_of(self)]:
        """Run Stage 1 and return a lazy On-Demand handle over the root object.

        Pads the input (input + 128 zero bytes, reusing the same grow-only buffer
        as `parse`), runs `structural_index` into this parser's `positions`, and
        builds NO tape. Returns an `ObjectHandle` borrowing this parser; a leaf is
        parsed only when its value is read.

        The returned handle (and any handle it yields) borrows this parser; it is
        valid only while the parser is alive and is neither reparsed via `iter`/
        `parse` nor moved. Callers use the handle by inference and never name its
        type. M0 assumes the root JSON value is an object (`positions[0]` is `'{'`).
        """
        var input_len = len(data)

        # Reusable padded buffer: input + 128 zero bytes (SIMD overread headroom).
        # Same grow-only buffer the tape path uses; a warm parser reuses it.
        var num_chunks = (input_len + 63) // 64
        var padded_len = num_chunks * 64 + 128
        if len(self.padded) < padded_len:
            record_alloc()
            self.padded = List[UInt8](unsafe_uninit_length=padded_len)
        memcpy(dest=self.padded.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
        memset(self.padded.unsafe_ptr() + input_len, 0, padded_len - input_len)

        # Stage 1 only — no tape is built on the On-Demand path.
        structural_index(self.padded, input_len, self.positions)
        # Root object: its first key is positions[1] (positions[0] is the '{').
        return ObjectHandle(self, input_len, 1)

    def validate(mut self, data: List[UInt8]) raises -> None:
        """Validate JSON bytes strictly (RFC 8259); build NO tape, return no value.

        Runs Stage 1 (reusing the same grow-only padded/positions buffers as
        `parse`/`iter`), then walks the structural index with a strict
        recursive-descent grammar that materialises nothing. Returns normally iff
        the document is valid RFC 8259; raises a `ParseError` (formatted, like
        `parse`) on any malformed input — empty/whitespace-only document,
        truncated or mismatched container, trailing content, a glued or invalid
        number, a leading/double/trailing comma, a missing colon/comma, a
        non-string key, a bare structural byte, an unclosed string, or a bad
        escape. The nesting-depth bound matches the tape builder's, so the
        validator and the DOM reject deeply-nested input at the same depth.

        Unlike `iter`, this is a whole-document validator, not lazy navigation:
        every structural is grammar-checked and every leaf is parsed for
        validity. It allocates no `Document` and exposes no handle.
        """
        var input_len = len(data)

        # Reusable padded buffer: input + 128 zero bytes (SIMD overread headroom).
        # Same grow-only buffer the tape and On-Demand paths use.
        var num_chunks = (input_len + 63) // 64
        var padded_len = num_chunks * 64 + 128
        if len(self.padded) < padded_len:
            record_alloc()
            self.padded = List[UInt8](unsafe_uninit_length=padded_len)
        memcpy(dest=self.padded.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
        memset(self.padded.unsafe_ptr() + input_len, 0, padded_len - input_len)

        # Stage 1 only — no tape is built on the validate path.
        structural_index(self.padded, input_len, self.positions)

        # The shared leaf parsers (parse_string, _parse_number via the strings
        # path) write into / read from a scratch buffer sized input_len + 64;
        # grow it once like get_string does, reusing the parser-owned buffer.
        var needed = input_len + 64
        if len(self._od_scratch) < needed:
            self._od_scratch = List[UInt8](unsafe_uninit_length=needed)

        try:
            _validate_document(
                self.padded.unsafe_ptr(),
                self.positions,
                len(self.positions),
                input_len,
                self._od_scratch,
            )
        except e:
            raise format_parse_error(e.code, e.position)
