"""JSON output sink and scalar emitters shared by both encoder layers.

`JsonWriter` accumulates UTF-8 bytes in a `List[UInt8]` and is consumed once via
`finish()`. It owns the only definition of JSON string escaping, number
formatting, and pretty-print indentation, so the tape round-trip path and the
reflection path emit byte-identical structure for the same logical value.
"""
from std.math import isfinite
from std.memory import bitcast, memcpy

comptime _HEX = String("0123456789abcdef")


struct JsonWriter:
    """Growable UTF-8 byte sink for JSON. Write-only; consume once via `finish()`.

    A non-empty `indent_unit` selects pretty mode: `newline_indent()` emits a
    newline plus `depth` indent units, and `colon()` emits `": "` instead of
    `":"`. In compact mode both are minimal.
    """

    var buf: List[UInt8]
    var indent_unit: String
    var depth: Int
    var nonfinite_null: Bool

    def __init__(out self, indent_unit: String = String(""), nonfinite_null: Bool = False):
        """Create an empty writer. Non-empty `indent_unit` enables pretty mode.

        `nonfinite_null=True` makes `write_float` emit `null` for a non-finite
        float instead of raising, so an infallible per-node write can substitute
        `null` for the single offending value. The default (False) keeps the
        strict raise-on-non-finite contract of the whole-document encoders.
        """
        self.buf = List[UInt8]()
        self.indent_unit = indent_unit
        self.depth = 0
        self.nonfinite_null = nonfinite_null

    @always_inline("nodebug")
    def _bulk_append(mut self, src: UnsafePointer[UInt8, _], n: Int):
        """Append `n` bytes from `src` to `self.buf` via memcpy."""
        if n <= 0:
            return
        var pos = len(self.buf)
        self.buf.resize(unsafe_uninit_length=pos + n)
        memcpy(dest=self.buf.unsafe_ptr() + pos, src=src, count=n)

    @always_inline("nodebug")
    def _write_uint_digits(mut self, v: UInt64):
        """Append decimal digits of `v` to `self.buf`. No sign, no leading zeros."""
        if v == 0:
            self.buf.append(0x30)
            return
        var digits = InlineArray[UInt8, 20](fill=UInt8(0))
        var n = 0
        var rem = v
        while rem > 0:
            digits[n] = UInt8(rem % 10) + 0x30
            rem //= 10
            n += 1
        var i = n - 1
        while i >= 0:
            self.buf.append(digits[i])
            i -= 1

    @always_inline("nodebug")
    def is_pretty(self) -> Bool:
        """True when an indent unit was supplied (pretty-print mode)."""
        return self.indent_unit.byte_length() > 0

    def raw(mut self, s: String):
        """Append the UTF-8 bytes of `s` verbatim (no escaping)."""
        var b = s.as_bytes()
        self._bulk_append(b.unsafe_ptr(), len(b))

    def _esc_one(mut self, c: UInt8):
        """Append one source byte in JSON-escaped form.

        `"` and `\\` are backslash-escaped; control bytes `< 0x20` use the short
        escapes (`\\b \\f \\n \\r \\t`) or `\\u00XX` for all others;
        every other byte (incl. 0x7F and UTF-8 continuation bytes) passes
        through verbatim.
        """
        if c == 0x22:
            self.buf.append(0x5C); self.buf.append(0x22)
        elif c == 0x5C:
            self.buf.append(0x5C); self.buf.append(0x5C)
        elif c >= 0x20:
            self.buf.append(c)
        elif c == 0x08:
            self.buf.append(0x5C); self.buf.append(0x62)
        elif c == 0x0C:
            self.buf.append(0x5C); self.buf.append(0x66)
        elif c == 0x0A:
            self.buf.append(0x5C); self.buf.append(0x6E)
        elif c == 0x09:
            self.buf.append(0x5C); self.buf.append(0x74)
        elif c == 0x0D:
            self.buf.append(0x5C); self.buf.append(0x72)  # \r
        else:
            self.buf.append(0x5C); self.buf.append(0x75)  # \u
            self.buf.append(0x30); self.buf.append(0x30)  # 00
            self.buf.append(_HEX.as_bytes()[Int(c >> 4)])
            self.buf.append(_HEX.as_bytes()[Int(c & 0xF)])

    def write_escaped_str(mut self, s: String):
        """Write a Mojo `String` as a quoted, escaped JSON string."""
        self.buf.append(0x22)
        for b in s.as_bytes():
            self._esc_one(b)
        self.buf.append(0x22)

    def write_escaped_buf(mut self, ref buf: List[UInt8], start: Int, length: Int):
        """Write `length` bytes of `buf` from `start` as a quoted, escaped string."""
        self.buf.append(0x22)
        for i in range(length):
            self._esc_one(buf[start + i])
        self.buf.append(0x22)

    def write_escaped_buf(mut self, ptr: UnsafePointer[UInt8, _], start: Int, length: Int):
        """Write `length` bytes from `ptr + start` as a quoted, escaped string."""
        self.buf.append(0x22)
        for i in range(length):
            self._esc_one(ptr[start + i])
        self.buf.append(0x22)

    def write_int(mut self, v: Int64):
        """Append a signed integer in decimal. No heap allocation."""
        if v == 0:
            self.buf.append(0x30)
            return
        if v > 0:
            self._write_uint_digits(UInt64(v))
            return
        self.buf.append(0x2D)
        var u = UInt64(bitcast[DType.uint64](SIMD[DType.int64, 1](v)))
        self._write_uint_digits(0 - u)

    def write_uint(mut self, v: UInt64):
        """Append an unsigned integer in decimal. No heap allocation."""
        self._write_uint_digits(v)

    def write_float(mut self, v: Float64) raises:
        """Append a float via the stdlib shortest-round-trip formatter.

        Raises on NaN/±Infinity, which JSON has no literal for. A non-finite `v`
        reaches here from two sources: a user struct field on the reflection
        path, AND a parsed JSON number whose magnitude overflowed Float64 and
        saturated to ±inf during parsing (e.g. `1e999`, which RFC 8259 permits
        and the parser accepts). Round-tripping such a document therefore raises
        by design — emitting `null` or a bogus token instead would be silent
        data loss or invalid output.

        The one exception is a writer built with `nonfinite_null=True`, which
        emits `null` for the non-finite value instead of raising — used by the
        infallible per-node `Value.write_to` so `print(value)` cannot fail.
        """
        if not isfinite(v):
            if self.nonfinite_null:
                self.raw(String("null"))
                return
            raise "JSON_ENCODE_ERROR: non-finite float (NaN/Infinity) has no JSON representation"
        self.raw(String(v))

    def write_bool(mut self, v: Bool):
        """Append `true`/`false`."""
        self.raw(String("true") if v else String("false"))

    def write_null(mut self):
        """Append `null`."""
        self.raw(String("null"))

    def colon(mut self):
        """Append the key/value separator (`": "` pretty, `":"` compact)."""
        if self.is_pretty():
            self.buf.append(0x3A); self.buf.append(0x20)
        else:
            self.buf.append(0x3A)

    def newline_indent(mut self):
        """In pretty mode, emit a newline then `depth` indent units. No-op compact."""
        if self.is_pretty():
            self.buf.append(0x0A)
            var unit = self.indent_unit
            for _ in range(self.depth):
                self.raw(unit)

    def finish(deinit self) raises -> String:
        """Consume the writer, returning the accumulated bytes as a String."""
        return String(from_utf8=self.buf^)
