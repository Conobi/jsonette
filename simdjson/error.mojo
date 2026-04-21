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


@fieldwise_init
struct ParseError(Movable, Writable):
    """Typed parse error for internal hot-path functions.

    Using typed `raises ParseError` on internal functions lets the compiler
    eliminate the dynamic error-type check on the happy path, reducing
    overhead compared to generic `raises`.
    """

    var code: UInt8
    var position: Int
    var message: String

    def write_to[W: Writer](self, mut writer: W):
        writer.write(self.message)
