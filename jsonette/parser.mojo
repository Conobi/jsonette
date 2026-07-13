"""Parser: the engine that owns the reusable buffers and runs both parse stages.

`Parser` is the stateful core behind the public `parse`/`iter`/`validate` entry
points (defined in `document.mojo`, `ondemand/reader.mojo`, and exposed here).
It owns the grow-only scratch buffers — padded input, Stage-1 structural
positions, the interleaved container stack, the tape, and the On-Demand unescape
scratch — and reuses them across calls so a warm same-size reparse allocates
nothing (the zero-allocation contract).

Five private build paths drive the stages:
  * `_build` runs Stage 1 (`structural_index`) then Stage 2 (`build_tape`) to
    materialise a DOM tape.
  * `_build_index` runs Stage 1 only, for the lazy On-Demand reader.
  * `_build_nocopy` like `_build` but skips the memcpy — sets `input_ptr`
    directly to the caller's pre-padded buffer.
  * `_build_index_nocopy` like `_build_index` but skips the memcpy.
  * `validate` runs Stage 1 then a strict grammar walk that materialises nothing.

Every path first rejects input beyond the 4 GiB structural-index limit
(`_check_input_len`). The tape and validate paths also reject non-UTF-8 input
via the check fused into Stage 1 (`structural_index[validate_utf8=True]`), so
`parse` and `validate` agree on every input. No I/O happens here: the caller
supplies a pre-loaded byte buffer.
"""

from std.memory import memcpy, memset

from jsonette.tape import Tape
from jsonette.error import format_parse_error, ErrorCode
from jsonette._alloc_count import record_alloc
from jsonette.stage1.indexer import structural_index
from jsonette.stage2.builder import build_tape
from jsonette.ondemand.validate import _validate_document


# Maximum input length jsonette can index. Stage-1 structural positions are
# UInt32 and container close-indices pack into the low 32 payload bits, with
# 0xFFFFFFFF reserved as the builder's end sentinel; an input larger than this
# would wrap offsets into out-of-bounds reads or premature truncation. simdjson
# enforces the same ~4 GB cap. The guard is one comparison off the hot loop. A
# 4 GiB input cannot be unit-tested (it would need >4 GiB of RAM), so this limit
# is enforced and documented rather than exercised by a test.
comptime _MAX_INPUT_LEN: Int = 0xFFFFFFFF


def _check_input_len(input_len: Int) raises:
    """Reject input at or beyond the 4 GiB structural-index limit (UInt32 offsets).

    Raised before Stage 1 runs so an oversized buffer can never wrap a UInt32
    structural position. Cheap: one comparison, off the per-chunk hot loop.
    """
    if input_len > _MAX_INPUT_LEN:
        raise format_parse_error(ErrorCode.INPUT_TOO_LARGE.value, 0)


struct Parser(Movable):
    """JSON parser. Orchestrates Stage 1 + Stage 2.

    Movable: the parser owns its reusable buffers and tape; moving it transfers
    that ownership (the existing `deinit move` constructor is the move). Any
    `Document` borrowing the old location is invalidated by the move, enforced by
    the Document's origin parameter.

    `_input_addr` stores the raw address of the input buffer as an `Int`. All
    stage calls and On-Demand reads reconstruct a pointer from this address via
    `get_input_ptr()`. Stored as `Int` (not `UnsafePointer`) to work around a
    Mojo 1.0.0b2 miscompile reading UnsafePointer struct fields through
    origin-tracked Pointer chains. In the copy paths it holds the address of
    `padded`; in the nocopy paths it holds the caller's buffer address."""

    var container_stack: List[UInt32]  # interleaved: [open_idx, count, open_idx, count, ...]
    var padded: List[UInt8]           # reusable zero-padded input buffer (grows only)
    var positions: List[UInt32]       # reusable Stage 1 structural-offset buffer (grows only)
    var _tape: Tape                   # parser-owned tape, reused across parses (grows only)
    var _od_scratch: List[UInt8]      # reusable On-Demand string-unescape scratch (grows only)
    var _input_addr: Int              # raw address of input buffer (workaround: Int, not UnsafePointer)

    @always_inline("nodebug")
    def get_input_ptr(self) -> UnsafePointer[UInt8, MutAnyOrigin]:
        """Reconstruct a pointer to the input buffer from the stored address."""
        return UnsafePointer[UInt8, MutAnyOrigin](unsafe_from_address=self._input_addr)

    def __init__(out self):
        self.container_stack = List[UInt32](capacity=2048)  # MAX_DEPTH * 2
        self.padded = List[UInt8]()
        self.positions = List[UInt32]()
        self._tape = Tape()  # empty Lists -> no allocation until first parse grows them
        self._od_scratch = List[UInt8]()  # empty -> allocated on first On-Demand string read
        self._input_addr = Int(self.padded.unsafe_ptr())

    def __init__(out self, *, deinit move: Self):
        self.container_stack = move.container_stack^
        self.padded = move.padded^
        self.positions = move.positions^
        self._tape = move._tape^
        self._od_scratch = move._od_scratch^
        self._input_addr = move._input_addr

    def _build(mut self, data: Span[UInt8, _]) raises:
        """Build this parser's tape from `data` (Stage 1 + Stage 2). No Document returned.

        Stage 1 produces the structural index; Stage 2 (`build_tape`) walks it as a
        strict RFC-8259 grammar state machine, rejecting malformed input as it
        materialises the tape (single pass, each leaf parsed once). Reuses the
        grow-only `padded`/`positions`/`_tape` buffers; a warm same-size rebuild
        allocates nothing (the zero-alloc contract). Rejects non-UTF-8 input
        (fused into Stage 1), then raises a formatted ParseError on any
        malformed input.
        """
        var input_len = len(data)
        _check_input_len(input_len)

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
        self._input_addr = Int(self.padded.unsafe_ptr())

        # Reusable structural-offset buffer: grows only when a larger input needs
        # more room than prior parses; warm same-size reparses contribute 0 allocs.
        structural_index[validate_utf8=True](self.get_input_ptr(), input_len, self.positions)
        self.container_stack.resize(0, UInt32(0))
        try:
            build_tape(self.get_input_ptr(), input_len, self.positions, self.container_stack, self._tape)
        except e:
            raise format_parse_error(e.code, e.position)

    def _build_index(mut self, data: Span[UInt8, _]) raises:
        """Run Stage 1 only (pad + structural_index) into this parser's buffers; no tape.

        Reuses the grow-only `padded`/`positions` buffers (zero warm allocs). Rejects
        non-UTF-8 input (fused into Stage 1), so the On-Demand path validates UTF-8
        at the same cost as the tape and validate paths. The On-Demand owning `Reader`
        is built on top of this.
        """
        var input_len = len(data)
        _check_input_len(input_len)
        var num_chunks = (input_len + 63) // 64
        var padded_len = num_chunks * 64 + 128
        if len(self.padded) < padded_len:
            record_alloc()
            self.padded = List[UInt8](unsafe_uninit_length=padded_len)
        memcpy(dest=self.padded.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
        memset(self.padded.unsafe_ptr() + input_len, 0, padded_len - input_len)
        self._input_addr = Int(self.padded.unsafe_ptr())
        structural_index[validate_utf8=True](self.get_input_ptr(), input_len, self.positions)

    def _build_nocopy(mut self, data: UnsafePointer[UInt8, MutAnyOrigin], input_len: Int) raises:
        """Build tape from a caller-owned padded buffer (no memcpy).

        The caller guarantees `data` has at least ceil(input_len/64)*64 + 128
        bytes allocated and the bytes past input_len are zero (SIMD overread
        safety). This is an unsafe fast path: the caller must keep the buffer
        alive while any Document/Value built from this parser is in use.
        """
        _check_input_len(input_len)
        self._input_addr = Int(data)
        structural_index[validate_utf8=True](self.get_input_ptr(), input_len, self.positions)
        self.container_stack.resize(0, UInt32(0))
        try:
            build_tape(self.get_input_ptr(), input_len, self.positions, self.container_stack, self._tape)
        except e:
            raise format_parse_error(e.code, e.position)

    def _build_index_nocopy(mut self, data: UnsafePointer[UInt8, MutAnyOrigin], input_len: Int) raises:
        """Run Stage 1 only from a caller-owned padded buffer (no memcpy).

        Same padding contract as _build_nocopy. The caller must keep the buffer
        alive while any Reader/Value built from this parser is in use.

        NOTE: On-Demand Value methods that read input bytes through the
        Pointer[Reader,o] chain hit a Mojo 1.0.0b2 codegen bug when
        self.padded doesn't hold the data. Until that's fixed, OD nocopy
        copies into self.padded as a workaround (same cost as the copy path).
        """
        _check_input_len(input_len)
        var num_chunks = (input_len + 63) // 64
        var padded_len = num_chunks * 64 + 128
        if len(self.padded) < padded_len:
            record_alloc()
            self.padded = List[UInt8](unsafe_uninit_length=padded_len)
        memcpy(dest=self.padded.unsafe_ptr(), src=data, count=input_len)
        memset(self.padded.unsafe_ptr() + input_len, 0, padded_len - input_len)
        self._input_addr = Int(self.padded.unsafe_ptr())
        structural_index[validate_utf8=True](self.get_input_ptr(), input_len, self.positions)

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

        Rejects input that is not well-formed UTF-8 (same fused Stage 1 guard as
        `parse`), so `validate` and `parse` agree on every input.
        """
        var input_len = len(data)
        _check_input_len(input_len)

        # Reusable padded buffer: input + 128 zero bytes (SIMD overread headroom).
        # Same grow-only buffer the tape and On-Demand paths use.
        var num_chunks = (input_len + 63) // 64
        var padded_len = num_chunks * 64 + 128
        if len(self.padded) < padded_len:
            record_alloc()
            self.padded = List[UInt8](unsafe_uninit_length=padded_len)
        memcpy(dest=self.padded.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
        memset(self.padded.unsafe_ptr() + input_len, 0, padded_len - input_len)
        self._input_addr = Int(self.padded.unsafe_ptr())

        # Stage 1 only — no tape is built on the validate path.
        structural_index[validate_utf8=True](self.get_input_ptr(), input_len, self.positions)

        # The shared leaf parsers (parse_string, _parse_number via the strings
        # path) write into / read from a scratch buffer sized input_len + 64;
        # grow it once like get_string does, reusing the parser-owned buffer.
        var needed = input_len + 64
        if len(self._od_scratch) < needed:
            self._od_scratch = List[UInt8](unsafe_uninit_length=needed)

        try:
            _validate_document(
                self.get_input_ptr(),
                self.positions,
                len(self.positions),
                input_len,
                self._od_scratch,
            )
        except e:
            raise format_parse_error(e.code, e.position)
