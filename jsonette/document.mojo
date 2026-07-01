"""Document: the owning DOM handle and the top-level `parse` entry points.

A `Document` owns a fully built tape (via its `Parser`) plus a generation
counter. It is the value returned by `parse(...)`; callers navigate it through
`root()`, which hands back a self-bound `Value` view over the already-built tape
(no re-parse, callable repeatedly). `reparse(data)` rebuilds into the same
buffers for zero warm allocations and bumps the generation counter, which
invalidates any outstanding `Value` (trapped under `-D ASSERT=all`).

The module also defines the free `parse` functions (bytes and `String`
overloads) that construct an owning `Document` — the default DOM entry point.
"""

from std.collections import Optional

from jsonette.parser import Parser
from jsonette.value import Value, _FieldIter, _ElemIter


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

    def __init__(out self, *, deinit move: Self):
        self._parser = move._parser^
        self._gen = move._gen

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

    def __getitem__(mut self, key: String) raises -> Value[origin_of(self)]:
        """Facade for `root().field(key)` — `doc["k"]` with no `.root()` hop."""
        return self.root().field(key)

    def __getitem__(mut self, idx: Int) raises -> Value[origin_of(self)]:
        """Facade for `root().elem(idx)` — `doc[i]` with no `.root()` hop."""
        return self.root().elem(idx)

    def field(mut self, key: String) raises -> Value[origin_of(self)]:
        """Facade for `root().field(key)`."""
        return self.root().field(key)

    def elem(mut self, idx: Int) raises -> Value[origin_of(self)]:
        """Facade for `root().elem(idx)`."""
        return self.root().elem(idx)

    def get(mut self, key: String) raises -> Optional[Value[origin_of(self)]]:
        """Facade for `root().get(key)` (alias of `try_field`)."""
        return self.root().try_field(key)

    def get(mut self, idx: Int) raises -> Optional[Value[origin_of(self)]]:
        """Facade for `root().get(idx)` (alias of `try_elem`)."""
        return self.root().try_elem(idx)

    def try_field(mut self, key: String) raises -> Optional[Value[origin_of(self)]]:
        """Facade for `root().try_field(key)`."""
        return self.root().try_field(key)

    def try_elem(mut self, idx: Int) raises -> Optional[Value[origin_of(self)]]:
        """Facade for `root().try_elem(idx)`."""
        return self.root().try_elem(idx)

    def has_field(mut self, key: String) raises -> Bool:
        """Facade for `root().has_field(key)`."""
        return self.root().has_field(key)

    def __contains__(mut self, key: String) -> Bool:
        """Facade for `key in root()` (total; False on a non-object root)."""
        return self.root().__contains__(key)

    def len(mut self) raises -> Int:
        """Facade for `root().len()` (raises on a non-container root). NOTE: `len(doc)`
        is not supported (Sized needs borrowed self); use `doc.len()` or
        `len(doc["field"])`."""
        return self.root().len()

    def __eq__(mut self, other: String) -> Bool:
        """Facade for `root() == other` (total; False on a non-string root)."""
        return self.root().__eq__(other)

    def __ne__(mut self, other: String) -> Bool:
        """Facade for `root() != other`."""
        return self.root().__ne__(other)

    def string_eq(mut self, expected: String) raises -> Bool:
        """Facade for `root().string_eq(expected)`."""
        return self.root().string_eq(expected)

    def fields(mut self) raises -> _FieldIter[origin_of(self)]:
        """Facade for `root().fields()`."""
        return self.root().fields()

    def elems(mut self) raises -> _ElemIter[origin_of(self)]:
        """Facade for `root().elems()`."""
        return self.root().elems()

    def keys(mut self) raises -> List[String]:
        """Facade for `root().keys()`."""
        return self.root().keys()

    def items(mut self) raises -> List[Tuple[String, Value[origin_of(self)]]]:
        """Facade for `root().items()`."""
        return self.root().items()


def parse(data: Span[UInt8, _]) raises -> Document:
    """Parse JSON bytes into an owning Document (the default DOM entry)."""
    var p = Parser()
    p._build(data)
    return Document(p^)


def parse(data: String) raises -> Document:
    """Parse a JSON String (convenience; no manual byte buffer)."""
    return parse(data.as_bytes())
