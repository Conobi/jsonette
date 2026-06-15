from jsonette.parser import Parser
from jsonette.value import Value


struct Document(Movable):
    """Owns a Parser (buffers + tape) + a generation counter. The public DOM handle.

    `root()` returns a self-bound `Value` over the already-built tape (no re-parse,
    callable repeatedly). `reparse(data)` rebuilds into the same buffers (zero warm
    allocs). A `Value` borrows this Document; it cannot outlive it (compiler-enforced)
    and must not be used across a `reparse` (contract; trapped by the gen-token under
    `-D ASSERT=all`).
    """

    var _parser: Parser
    var _gen: Int

    def __init__(out self, var parser: Parser):
        self._parser = parser^
        self._gen = 0

    def __init__(out self, *, deinit take: Self):
        self._parser = take._parser^
        self._gen = take._gen

    def root(mut self) -> Value[origin_of(self)]:
        """Return the root Value (tape index 1). No re-parse; call repeatedly."""
        return Value[origin_of(self)](self, 1, self._gen)

    def reparse(mut self, data: Span[UInt8, _]) raises:
        """Rebuild from new bytes, reusing buffers (zero warm allocs); bumps the gen."""
        self._parser._build(data)
        self._gen += 1

    def reparse(mut self, data: String) raises:
        """Reparse from a JSON String (convenience), reusing buffers."""
        self.reparse(data.as_bytes())


def parse(data: Span[UInt8, _]) raises -> Document:
    """Parse JSON bytes into an owning Document (the default DOM entry)."""
    var p = Parser()
    p._build(data)
    return Document(p^)


def parse(data: String) raises -> Document:
    """Parse a JSON String (convenience; no manual byte buffer)."""
    return parse(data.as_bytes())
