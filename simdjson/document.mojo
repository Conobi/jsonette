from simdjson.tape import Tape
from simdjson.value import Value


struct Document[o: Origin[mut=True]](Movable):
    """Non-owning view over a Parser-owned tape.

    The Document borrows the Parser's tape through an origin-parameterized
    `Pointer`; it allocates nothing of its own. It is valid ONLY while its Parser
    is alive and is neither reparsed nor moved (mirrors simdjson, and matches
    one-request-at-a-time server usage). The origin parameter `o` ties the view's
    lifetime to the Parser's tape so the borrow checker enforces this.
    """

    var _tape: Pointer[Tape, Self.o]

    def __init__(out self, ref [Self.o] tape: Tape):
        """Borrow the given Parser-owned tape (no allocation)."""
        self._tape = Pointer(to=tape)

    def __init__(out self, *, deinit take: Self):
        """Move constructor: transfer the borrowed-tape pointer."""
        self._tape = take._tape

    def root(self) -> Value:
        """Return a Value pointing to the root JSON value (tape index 1)."""
        return Value(1)
