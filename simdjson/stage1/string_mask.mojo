from simdjson.stage1.simd_ops import prefix_xor


struct EscapeScanner:
    """Determines which bytes are escaped (follow an odd-length run of backslashes).

    Uses simdjson's ODD_BITS trick: split backslash-run starts by parity,
    add-propagate through runs, filter carries by opposite parity.
    """

    var next_is_escaped: UInt64

    def __init__(out self):
        self.next_is_escaped = 0

    def next(mut self, backslash: UInt64) -> UInt64:
        """Given a 64-bit backslash bitmask, return 64-bit escaped bitmask."""
        comptime ODD_BITS: UInt64 = 0xAAAAAAAAAAAAAAAA

        # Starts of backslash runs: a backslash NOT preceded by another backslash
        var prev_carry = self.next_is_escaped
        var starts = backslash & ~((backslash << 1) | prev_carry)

        # Split by parity
        var even_starts = starts & ~ODD_BITS
        var odd_starts = starts & ODD_BITS

        # Add-propagate through runs. Bits that "fall off" the run are escaped.
        var even_carries = (even_starts + backslash) & ~backslash
        var odd_carries = (odd_starts + backslash) & ~backslash

        # Filter by opposite parity (odd-length runs only)
        var even_result = even_carries & ODD_BITS
        var odd_result = odd_carries & ~ODD_BITS
        var escaped = even_result | odd_result

        # Detect overflow (carry into next block).
        # Only odd-parity overflow sets the carry; even-parity overflow cancels it.
        # This matches simdjson C++: next_escaped = (odd_carry>>63) & ~(even_carry>>63)
        var even_overflow: Bool = (even_starts != 0) and (
            (even_starts + backslash) < even_starts
        )
        var odd_overflow: Bool = (odd_starts != 0) and (
            (odd_starts + backslash) < odd_starts
        )
        self.next_is_escaped = UInt64(1) if (
            odd_overflow and not even_overflow
        ) else UInt64(0)

        return escaped


struct StringScanner:
    """Computes in-string bitmask using prefix_xor on real (non-escaped) quotes."""

    var prev_in_string: UInt64

    def __init__(out self):
        self.prev_in_string = 0

    def next(mut self, quote: UInt64, escaped: UInt64) -> UInt64:
        """Given quote and escaped bitmasks, return in-string bitmask.

        A bit is set if that byte position is inside a JSON string
        (between an opening quote and closing quote, exclusive of quotes themselves).
        """
        var real_quotes = quote & ~escaped
        var in_string = prefix_xor(real_quotes) ^ self.prev_in_string
        # Arithmetic right-shift bit 63 to broadcast carry (0 or ~0)
        self.prev_in_string = UInt64(Int64(Int(in_string)) >> 63)
        return in_string
