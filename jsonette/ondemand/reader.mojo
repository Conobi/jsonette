from jsonette.parser import Parser
from jsonette.ondemand.ondemand import Value
from jsonette.error import format_parse_error, ErrorCode


struct Reader(Movable):
    """Owns a Parser (Stage-1 index, no tape) + a generation counter. The On-Demand
    handle. `root()` returns a self-bound `Value` at the document's first structural.
    `reparse(data)` re-indexes (zero warm allocs). Handles borrow this Reader; they
    cannot outlive it (compiler-enforced) and must not be used across a reparse
    (contract; gen-token traps it under -D ASSERT=all)."""

    var _parser: Parser
    var _gen: Int
    var _input_len: Int

    def __init__(out self, var parser: Parser, input_len: Int):
        self._parser = parser^
        self._gen = 0
        self._input_len = input_len

    def __init__(out self, *, deinit move: Self):
        self._parser = move._parser^
        self._gen = move._gen
        self._input_len = move._input_len

    def root(mut self) raises -> Value[origin_of(self)]:
        """Self-bound root Value at the first structural; raises EMPTY_DOCUMENT on
        an empty/whitespace-only document (parity with the DOM)."""
        if len(self._parser.positions) == 0:
            raise format_parse_error(ErrorCode.EMPTY_DOCUMENT.value, 0)
        return Value[origin_of(self)](self, 0, self._gen)

    def reparse(mut self, data: Span[UInt8, _]) raises:
        """Re-run Stage 1 from new bytes, reusing buffers (zero warm allocs); bumps the gen."""
        self._parser._build_index(data)
        self._input_len = len(data)
        self._gen += 1

    def reparse(mut self, data: String) raises:
        """Reparse from a JSON String (convenience), reusing buffers."""
        self.reparse(data.as_bytes())


def iter(data: Span[UInt8, _]) raises -> Reader:
    """Run Stage 1 and return an owning On-Demand Reader (the lazy entry)."""
    var p = Parser()
    p._build_index(data)
    return Reader(p^, len(data))


def iter(data: String) raises -> Reader:
    """Run Stage 1 from a JSON String (convenience) and return an owning Reader."""
    return iter(data.as_bytes())
