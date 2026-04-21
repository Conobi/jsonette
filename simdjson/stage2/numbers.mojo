from std.memory import bitcast


@fieldwise_init
struct NumberResult(Movable, Copyable):
    """Result of parsing a JSON number."""
    var tag: UInt8        # 0x6C='l' signed, 0x75='u' unsigned, 0x64='d' float
    var value: UInt64     # raw bits (Int64, UInt64, or Float64 bitcast)
    var bytes_consumed: Int


def _is_digit(b: UInt8) -> Bool:
    return b >= UInt8(0x30) and b <= UInt8(0x39)


def _digit_value(b: UInt8) -> UInt64:
    return UInt64(b) - UInt64(0x30)


def parse_number(ptr: UnsafePointer[UInt8, _], max_len: Int) raises -> NumberResult:
    """Parse a JSON number starting at ptr[0].

    Returns tag ('l'/'u'/'d'), raw value bits, and bytes consumed.
    Handles integers and basic floats. Stops at non-number character.
    """
    var pos = 0
    var negative = False

    # Optional leading minus
    if ptr[pos] == UInt8(0x2D):  # '-'
        negative = True
        pos += 1

    if pos >= max_len or not _is_digit(ptr[pos]):
        raise "NUMBER_ERROR: expected digit after '-'"

    # Leading zero check: "01" is invalid, "0" and "0.x" are ok
    if ptr[pos] == UInt8(0x30) and pos + 1 < max_len and _is_digit(ptr[pos + 1]):
        raise "NUMBER_ERROR: leading zeros not allowed"

    # Parse integer digits
    var integer_part: UInt64 = 0
    var digit_count = 0
    while pos < max_len and _is_digit(ptr[pos]):
        var digit = _digit_value(ptr[pos])
        # Overflow check: if integer_part > (MAX - digit) / 10
        if integer_part > (UInt64.MAX - digit) // 10:
            raise "NUMBER_ERROR: integer overflow"
        integer_part = integer_part * 10 + digit
        digit_count += 1
        pos += 1

    # Check for float indicators
    var is_float = False
    if pos < max_len and (ptr[pos] == UInt8(0x2E) or ptr[pos] == UInt8(0x65) or ptr[pos] == UInt8(0x45)):
        is_float = True

    if is_float:
        return _parse_float(ptr, pos, max_len, negative, integer_part, digit_count)
    else:
        return _finish_integer(negative, integer_part, pos)


def _finish_integer(negative: Bool, integer_part: UInt64, pos: Int) raises -> NumberResult:
    if negative:
        # Int64 range: -9223372036854775808 to 9223372036854775807
        # integer_part == 2^63 is valid (it's INT64_MIN's absolute value)
        comptime INT64_MIN_ABS: UInt64 = UInt64(1) << 63
        if integer_part > INT64_MIN_ABS:
            raise "NUMBER_ERROR: signed integer overflow"
        # Special case: 2^63 can't be negated via Int64 (overflow), use bitcast
        var raw: UInt64
        if integer_part == INT64_MIN_ABS:
            raw = INT64_MIN_ABS  # Two's complement: 0x8000000000000000 = INT64_MIN
        else:
            var signed_val = Int64(0) - Int64(integer_part)
            raw = UInt64(bitcast[DType.uint64](SIMD[DType.int64, 1](signed_val)))
        return NumberResult(tag=UInt8(0x6C), value=raw, bytes_consumed=pos)
    else:
        return NumberResult(tag=UInt8(0x75), value=integer_part, bytes_consumed=pos)


def _parse_float(
    ptr: UnsafePointer[UInt8, _],
    mut pos: Int,
    max_len: Int,
    negative: Bool,
    integer_part: UInt64,
    digit_count: Int,
) raises -> NumberResult:
    var value = Float64(integer_part)

    if pos < max_len and ptr[pos] == UInt8(0x2E):
        pos += 1
        if pos >= max_len or not _is_digit(ptr[pos]):
            raise "NUMBER_ERROR: expected digit after '.'"
        var frac: Float64 = 0.0
        var frac_scale: Float64 = 1.0
        while pos < max_len and _is_digit(ptr[pos]):
            frac = frac * 10.0 + Float64(_digit_value(ptr[pos]))
            frac_scale *= 10.0
            pos += 1
        value += frac / frac_scale

    if pos < max_len and (ptr[pos] == UInt8(0x65) or ptr[pos] == UInt8(0x45)):
        pos += 1
        var exp_negative = False
        if pos < max_len and (ptr[pos] == UInt8(0x2B) or ptr[pos] == UInt8(0x2D)):
            exp_negative = ptr[pos] == UInt8(0x2D)
            pos += 1
        if pos >= max_len or not _is_digit(ptr[pos]):
            raise "NUMBER_ERROR: expected digit in exponent"
        var exponent: Int = 0
        while pos < max_len and _is_digit(ptr[pos]):
            exponent = exponent * 10 + Int(_digit_value(ptr[pos]))
            pos += 1
        if exp_negative:
            for _ in range(exponent):
                value /= 10.0
        else:
            for _ in range(exponent):
                value *= 10.0

    if negative:
        value = -value

    var raw = bitcast[DType.uint64](SIMD[DType.float64, 1](value))
    return NumberResult(tag=UInt8(0x64), value=UInt64(raw), bytes_consumed=pos)
