from simdjson.tape import Tape
from simdjson.value import Value


struct Document(Movable):
    """Owns a parsed JSON tape and provides root access."""
    var tape: Tape

    def __init__(out self, var tape: Tape):
        self.tape = tape^

    def __init__(out self):
        self.tape = Tape()

    def __init__(out self, *, deinit take: Self):
        self.tape = take.tape^

    def root(self) -> Value:
        """Return a Value pointing to the root JSON value (tape index 1)."""
        return Value(1)
