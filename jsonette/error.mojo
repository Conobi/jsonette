@fieldwise_init
struct ErrorCode(Movable, Copyable):
    """Error codes for parse failures."""

    var value: UInt8

    comptime DEPTH_EXCEEDED = ErrorCode(1)
    comptime TAPE_ERROR = ErrorCode(2)
    comptime STRING_ERROR = ErrorCode(3)
    comptime NUMBER_ERROR = ErrorCode(4)
    comptime UNCLOSED_STRING = ErrorCode(5)
    comptime UNEXPECTED_VALUE = ErrorCode(6)
    comptime TRAILING_CONTENT = ErrorCode(7)
    comptime EMPTY_DOCUMENT = ErrorCode(8)
    comptime UNCLOSED_CONTAINER = ErrorCode(9)
    comptime INVALID_LITERAL = ErrorCode(10)
    comptime INVALID_UTF8 = ErrorCode(11)
    comptime INPUT_TOO_LARGE = ErrorCode(12)
    """Input exceeds the 4 GiB structural-index limit (Stage-1 positions are
    UInt32). Raised before any parsing so oversized input cannot wrap an offset."""


@fieldwise_init
struct ParseError(Movable, Writable):
    """Lightweight parse error — no String allocation on the hot path.

    Using typed `raises ParseError` on internal functions lets the compiler
    eliminate the dynamic error-type check on the happy path, reducing
    overhead compared to generic `raises`.

    The `message` field was removed to avoid 32+ String constructions in
    the inlined hot path.  `write_to` formats lazily from code + position
    only when the error is actually caught and converted to `Error`.
    """

    var code: UInt8
    var position: Int

    def __init__(out self, *, deinit move: Self):
        self.code = move.code
        self.position = move.position

    def write_to[W: Writer](self, mut writer: W):
        writer.write(format_parse_error(self.code, self.position))


def format_parse_error(code: UInt8, position: Int) -> String:
    """Construct human-readable error message. Called only at catch site."""
    var name: String
    if code == ErrorCode.DEPTH_EXCEEDED.value:
        name = "DEPTH_EXCEEDED"
    elif code == ErrorCode.TAPE_ERROR.value:
        name = "TAPE_ERROR"
    elif code == ErrorCode.STRING_ERROR.value:
        name = "STRING_ERROR"
    elif code == ErrorCode.NUMBER_ERROR.value:
        name = "NUMBER_ERROR"
    elif code == ErrorCode.UNCLOSED_STRING.value:
        name = "UNCLOSED_STRING"
    elif code == ErrorCode.UNEXPECTED_VALUE.value:
        name = "UNEXPECTED_VALUE"
    elif code == ErrorCode.TRAILING_CONTENT.value:
        name = "TRAILING_CONTENT"
    elif code == ErrorCode.EMPTY_DOCUMENT.value:
        name = "EMPTY_DOCUMENT"
    elif code == ErrorCode.UNCLOSED_CONTAINER.value:
        name = "UNCLOSED_CONTAINER"
    elif code == ErrorCode.INVALID_LITERAL.value:
        name = "INVALID_LITERAL"
    elif code == ErrorCode.INVALID_UTF8.value:
        name = "INVALID_UTF8"
    elif code == ErrorCode.INPUT_TOO_LARGE.value:
        name = "INPUT_TOO_LARGE"
    else:
        name = "UNKNOWN_ERROR"
    return name + " at position " + String(position)
