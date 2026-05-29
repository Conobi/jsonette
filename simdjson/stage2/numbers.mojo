from std.memory import bitcast
from simdjson.stage2.eisel_lemire import compute_float_64
from simdjson.stage2.slow_float import parse_float_slow
from simdjson.tape import TAG_INT64, TAG_UINT64, TAG_FLOAT64
from simdjson.error import ParseError, ErrorCode


@fieldwise_init
struct NumberResult(Movable, Copyable):
    """Result of parsing a JSON number."""
    var tag: UInt8        # TAG_INT64 signed, TAG_UINT64 unsigned, TAG_FLOAT64 float
    var value: UInt64     # raw bits (Int64, UInt64, or Float64 bitcast)
    var bytes_consumed: Int


@always_inline("nodebug")
def _is_digit(b: UInt8) -> Bool:
    return b >= UInt8(0x30) and b <= UInt8(0x39)


@always_inline("nodebug")
def _digit_value(b: UInt8) -> UInt64:
    return UInt64(b) - UInt64(0x30)


@always_inline("nodebug")
def _are_8_digits(ptr: UnsafePointer[UInt8, _], pos: Int) -> Bool:
    """Check if 8 bytes starting at ptr+pos are all ASCII digits ('0'-'9').

    PRECONDITION: the buffer must be readable for at least 8 bytes from
    `ptr + pos`. This SWAR load is unconditional; callers gate `pos` so that
    `pos + 8 <= max_len`, but the load itself touches up to 8 bytes which may
    fall inside the trailing NUL padding (NUL is not a digit, so the check
    fails cleanly). `Parser.parse` guarantees 128 bytes of NUL padding past
    the logical input length, which more than covers this over-read.
    """
    var chunk = (ptr + pos).load[width=8]()
    var sub = chunk - SIMD[DType.uint8, 8](0x30)
    return sub.reduce_max() <= 9


@always_inline("nodebug")
def _parse_8_digits(ptr: UnsafePointer[UInt8, _], pos: Int) -> UInt64:
    """Parse exactly 8 ASCII digits into a UInt64. Caller ensures all are digits."""
    var chunk = (ptr + pos).load[width=8]()
    var digits = (chunk - SIMD[DType.uint8, 8](0x30)).cast[DType.uint64]()
    var g1 = digits[0] * 1000 + digits[1] * 100 + digits[2] * 10 + digits[3]
    var g2 = digits[4] * 1000 + digits[5] * 100 + digits[6] * 10 + digits[7]
    return g1 * 10000 + g2


def _parse_number(ptr: UnsafePointer[UInt8, _], max_len: Int) raises ParseError -> NumberResult:
    """Parse a JSON number starting at ptr[0].

    Returns tag ('l'/'u'/'d'), raw value bits, and bytes consumed.
    Handles integers and basic floats. Stops at non-number character.

    PRECONDITION: the buffer at `ptr` must hold at least 8 NUL padding bytes
    past `max_len`. The SWAR digit fast path (`_are_8_digits` / `_parse_8_digits`)
    issues unconditional 8-byte loads and may over-read up to 8 bytes beyond
    the last digit. `Parser.parse` guarantees 128 bytes of NUL padding, so the
    over-read always lands in zeroed memory (NUL terminates the digit run).
    The `debug_assert` below documents this invariant in the callgraph; it
    compiles to nothing under `-D ASSERT=none`.
    """
    debug_assert(
        max_len >= 0,
        "_parse_number precondition: max_len must be non-negative",
    )
    var pos = 0
    var negative = False

    # Optional leading minus
    if ptr[pos] == UInt8(0x2D):  # '-'
        negative = True
        pos += 1

    if pos >= max_len or not _is_digit(ptr[pos]):
        raise ParseError(code=ErrorCode.NUMBER_ERROR.value, position=pos)

    # Leading zero check: "01" is invalid, "0" and "0.x" are ok
    if ptr[pos] == UInt8(0x30) and pos + 1 < max_len and _is_digit(ptr[pos + 1]):
        raise ParseError(code=ErrorCode.NUMBER_ERROR.value, position=pos)

    # Parse integer digits
    var integer_part: UInt64 = 0
    var digit_count = 0
    # `overflowed` marks that the integer no longer fits in UInt64. We keep
    # consuming digits (so the token is fully measured) and decide later: a
    # bare overflowing integer becomes a correctly-rounded float64 (RFC 8259),
    # while one followed by '.'/'e' falls into the normal float path anyway.
    var overflowed = False
    # SWAR fast path: parse 8 digits at a time.
    # A UInt64 holds at most 20 decimal digits, so an 8-digit batch can only
    # overflow once we already hold >= 12 digits (12 + 8 = 20). Below that, the
    # division-based overflow guard is dead work, so we skip it on the common
    # short-integer path and only accumulate.
    while pos + 8 <= max_len and _are_8_digits(ptr, pos):
        var batch = _parse_8_digits(ptr, pos)
        if digit_count >= 12 and integer_part > (UInt64.MAX - batch) // 100000000:
            overflowed = True
        else:
            integer_part = integer_part * 100000000 + batch
        digit_count += 8
        pos += 8
    # Scalar tail: remaining digits.
    # A single digit can only overflow UInt64 once 19 digits are already held
    # (UInt64.MAX has 20 digits), so gate the guard on `digit_count >= 19`.
    while pos < max_len and _is_digit(ptr[pos]):
        var digit = _digit_value(ptr[pos])
        if digit_count >= 19 and integer_part > (UInt64.MAX - digit) // 10:
            overflowed = True
        else:
            integer_part = integer_part * 10 + digit
        digit_count += 1
        pos += 1

    # Check for float indicators.
    #
    # A '.' starts a fraction only when it is followed by a digit, or when it
    # is a trailing dot at the end of the available input (so a malformed
    # token like "1." still routes into _parse_float and raises). A '.'
    # followed by an in-bounds non-digit (e.g. "1..2") is NOT part of the
    # number: by the maximal-prefix contract we stop at the integer prefix and
    # leave the stray '.' for the structural validator.
    var is_float = False
    if pos < max_len:
        var b = ptr[pos]
        if b == UInt8(0x2E):  # '.'
            if pos + 1 >= max_len or _is_digit(ptr[pos + 1]):
                is_float = True
        elif b == UInt8(0x65) or b == UInt8(0x45):  # 'e' / 'E'
            is_float = True

    comptime INT64_MIN_ABS: UInt64 = UInt64(1) << 63

    if is_float:
        return _parse_float(
            ptr, pos, max_len, negative, integer_part, digit_count, overflowed
        )
    elif overflowed or (negative and integer_part > INT64_MIN_ABS):
        # Out-of-INT64-range bare integer -> correctly-rounded float64 over the
        # token (RFC 8259). This covers both UInt64 overflow and a negative
        # magnitude in (2^63, 2^64-1] that fits UInt64 yet exceeds INT64 range.
        var bits = parse_float_slow(ptr, 0, pos, negative)
        return NumberResult(tag=TAG_FLOAT64, value=bits, bytes_consumed=pos)
    else:
        return _finish_integer(negative, integer_part, pos)


def _finish_integer(negative: Bool, integer_part: UInt64, pos: Int) raises ParseError -> NumberResult:
    if negative and integer_part != 0:
        # Int64 range: -9223372036854775808 to 9223372036854775807.
        # integer_part == 2^63 is valid (it's INT64_MIN's absolute value).
        # Magnitudes above 2^63 are routed to float64 by the caller, so this
        # path only sees in-range values.
        comptime INT64_MIN_ABS: UInt64 = UInt64(1) << 63
        # Special case: 2^63 can't be negated via Int64 (overflow), use bitcast
        var raw: UInt64
        if integer_part == INT64_MIN_ABS:
            raw = INT64_MIN_ABS  # Two's complement: 0x8000000000000000 = INT64_MIN
        else:
            var signed_val = Int64(0) - Int64(integer_part)
            raw = UInt64(bitcast[DType.uint64](SIMD[DType.int64, 1](signed_val)))
        return NumberResult(tag=TAG_INT64, value=raw, bytes_consumed=pos)
    else:
        return NumberResult(tag=TAG_UINT64, value=integer_part, bytes_consumed=pos)


def _parse_float(
    ptr: UnsafePointer[UInt8, _],
    mut pos: Int,
    max_len: Int,
    negative: Bool,
    integer_part: UInt64,
    digit_count: Int,
    overflowed: Bool,
) raises ParseError -> NumberResult:
    # Build mantissa (all significant digits) and track decimal exponent.
    var mantissa = integer_part
    var total_digits = digit_count
    var frac_digits = 0
    # `overflowed` means the integer part did not fit UInt64, so `integer_part`
    # (and thus `mantissa`) is stale/truncated and the Eisel-Lemire fast path
    # must NOT be trusted. Force the correctly-rounded slow path in that case.
    # This is currently implied by `digit_count > 19` (overflow needs >= 20
    # digits), but stating it explicitly keeps the routing invariant robust to
    # future changes in the digit-counting logic.
    var too_many_digits = (digit_count > 19) or overflowed

    if pos < max_len and ptr[pos] == UInt8(0x2E):
        pos += 1
        if pos >= max_len or not _is_digit(ptr[pos]):
            raise ParseError(code=ErrorCode.NUMBER_ERROR.value, position=pos)
        # SWAR fast path for fractional digits
        while pos + 8 <= max_len and total_digits + 8 <= 19 and _are_8_digits(ptr, pos):
            var batch = _parse_8_digits(ptr, pos)
            mantissa = mantissa * 100000000 + batch
            frac_digits += 8
            total_digits += 8
            pos += 8
        # Scalar tail
        while pos < max_len and _is_digit(ptr[pos]):
            if total_digits < 19:
                mantissa = mantissa * 10 + _digit_value(ptr[pos])
            else:
                too_many_digits = True
            frac_digits += 1
            total_digits += 1
            pos += 1

    var parsed_exponent = 0
    if pos < max_len and (ptr[pos] == UInt8(0x65) or ptr[pos] == UInt8(0x45)):
        pos += 1
        var exp_negative = False
        if pos < max_len and (ptr[pos] == UInt8(0x2B) or ptr[pos] == UInt8(0x2D)):
            exp_negative = ptr[pos] == UInt8(0x2D)
            pos += 1
        if pos >= max_len or not _is_digit(ptr[pos]):
            raise ParseError(code=ErrorCode.NUMBER_ERROR.value, position=pos)
        while pos < max_len and _is_digit(ptr[pos]):
            parsed_exponent = parsed_exponent * 10 + Int(_digit_value(ptr[pos]))
            pos += 1
        if exp_negative:
            parsed_exponent = -parsed_exponent

    var decimal_exponent = parsed_exponent - frac_digits

    # Try Eisel-Lemire fast path if mantissa fits in 19 digits.
    if not too_many_digits:
        var result = compute_float_64(mantissa, decimal_exponent, negative)
        if result.valid:
            return NumberResult(tag=TAG_FLOAT64, value=result.value, bytes_consumed=pos)

    # Fallback: correctly-rounded decimal->double over the whole token bytes.
    # The token spans ptr[0:pos]; `negative` was stripped at the front.
    var bits = parse_float_slow(ptr, 0, pos, negative)
    return NumberResult(tag=TAG_FLOAT64, value=bits, bytes_consumed=pos)
