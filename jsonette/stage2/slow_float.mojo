"""Correctly-rounded decimal-to-double slow path.

A self-contained, round-to-nearest-ties-to-even decimal->binary converter for
JSON number tokens that the Eisel-Lemire fast path cannot decide (subnormals,
>19 significant digits, out-of-table exponents) and for bare integers that
overflow UInt64.

The algorithm is the "simple decimal conversion" (Nigel Tao / Ken Thompson /
Go strconv.decimal): keep all significant digits in a big-endian decimal digit
array and shift it by powers of two (via a left-shift cheat table) until the
value sits in [0.5, 1), then extract 1 + 52 mantissa bits with banker's
rounding. Only bounded fixed-size integer arithmetic is needed; no
arbitrary-precision rationals.
"""

comptime MAX_DIGITS: Int = 800
"""Big-endian digit array capacity (matches Go strconv.decimal).

This cap is BOTH a correctness bound and an adversarial-input (DoS) bound; both
halves are load-bearing for correct round-to-nearest-ties-to-even:

1. cap >= worst-case boundary length. Correct rounding compares the value to the
   half-ulp boundaries between adjacent doubles. Those boundaries are exact
   decimals of <= ~767 significant digits (worst case near the smallest denormal
   2^-1074). With >= that many retained digits, the kept digits alone decide
   every NON-tie comparison. 800 >= 767, with margin.
2. sticky `trunc` decides the exact tie. When the kept digits exactly equal a
   boundary's, the discarded tail decides; truncation only drops digits, so the
   true value is >= the retained value, and `trunc` (set ONLY on a nonzero
   discarded digit) reports "strictly greater" -> round up. Trailing zeros leave
   `trunc` false and do not spuriously round up.

Discarding digits past 800 therefore changes no correctly-rounded result, and
bounds per-token slow-path work to O(800) digits independent of input length:
an adversarial `1.<10^6 digits>` token cannot scale CPU with its digit count.
"""

comptime MAX_SHIFT: Int = 60
"""Largest single binary shift without overflowing UInt64 (9<<60 fits)."""

# Float64 layout constants.
comptime MANT_BITS: Int = 52
comptime EXP_BITS: Int = 11
comptime BIAS: Int = -1023


struct Decimal(Movable, Copyable):
    """Big-endian decimal mantissa with a tracked decimal point.

    `d[0:nd]` are ASCII-free digit values (0..9), most significant first.
    `dp` is the position of the decimal point relative to `d[0]`; `trunc` flags
    that nonzero digits were discarded beyond the array capacity.
    """

    var d: InlineArray[UInt8, MAX_DIGITS]
    var nd: Int
    var dp: Int
    var neg: Bool
    var trunc: Bool

    def __init__(out self):
        """Construct an empty (zero) decimal."""
        self.d = InlineArray[UInt8, MAX_DIGITS](uninitialized=True)
        self.nd = 0
        self.dp = 0
        self.neg = False
        self.trunc = False


@always_inline
def _trim(mut a: Decimal):
    """Drop trailing zero digits; meaningless given the tracked decimal point."""
    while a.nd > 0 and a.d[a.nd - 1] == 0:
        a.nd -= 1
    if a.nd == 0:
        a.dp = 0


def parse_decimal_token(
    ptr: UnsafePointer[UInt8, _],
    token_start: Int,
    token_end: Int,
    negative: Bool,
) -> Decimal:
    """Parse a JSON number token's bytes into a `Decimal`.

    Reads significant digits, the optional fraction, and an optional `e`/`E`
    exponent over `ptr[token_start:token_end]`. A leading `-` may already be
    stripped (signalled by `negative`); any `-`/`+` inside the range is handled.
    Excess digits beyond capacity set `trunc`. The decimal point `dp` is folded
    with the parsed exponent so the result represents the exact token value.
    """
    var a = Decimal()
    a.neg = negative

    var i = token_start
    # Skip an in-range leading sign (caller usually strips '-').
    if i < token_end and (ptr[i] == UInt8(0x2D) or ptr[i] == UInt8(0x2B)):
        if ptr[i] == UInt8(0x2D):
            a.neg = True
        i += 1

    var saw_dot = False
    var seen_digit = False
    # Number of STORED digits after the decimal point (digits dropped past the
    # MAX_DIGITS cap are excluded, so `nd - frac` is the stored integer-digit
    # count even when the fraction is truncated).
    var frac = 0
    while i < token_end:
        var c = ptr[i]
        if c == UInt8(0x2E):  # '.'
            saw_dot = True
            i += 1
            continue
        if c == UInt8(0x65) or c == UInt8(0x45):  # 'e' / 'E'
            break
        if c < UInt8(0x30) or c > UInt8(0x39):
            break
        seen_digit = True
        var digit = c - UInt8(0x30)
        if a.nd == 0 and digit == 0:
            # Leading integer zeros only move the decimal point.
            if saw_dot:
                a.dp -= 1
            i += 1
            continue
        if a.nd < MAX_DIGITS:
            a.d[a.nd] = digit
            a.nd += 1
            # Count only STORED fraction digits. Fraction digits discarded past
            # the cap must NOT move the decimal point: otherwise dp (computed
            # below as nd - frac) is short by the number of dropped fraction
            # digits and the magnitude comes out wrong by 10^k.
            if saw_dot:
                frac += 1
        elif digit != 0:
            a.trunc = True
        i += 1

    if not seen_digit:
        # No significant digits -> value is zero.
        a.nd = 0
        a.dp = 0
        return a^

    # `dp` after the integer digits, before folding the explicit exponent.
    # Stored integer-digit count = (stored digits) - (stored fraction digits);
    # leading zeros may have decremented dp already. Because `frac` counts only
    # stored fraction digits, this stays correct under cap truncation. (Integer
    # runs long enough to truncate exceed 10^800 and saturate to inf regardless.)
    a.dp += a.nd - frac

    # Optional explicit exponent.
    if i < token_end and (ptr[i] == UInt8(0x65) or ptr[i] == UInt8(0x45)):
        i += 1
        var exp_neg = False
        if i < token_end and (ptr[i] == UInt8(0x2B) or ptr[i] == UInt8(0x2D)):
            exp_neg = ptr[i] == UInt8(0x2D)
            i += 1
        var exp = 0
        while i < token_end and ptr[i] >= UInt8(0x30) and ptr[i] <= UInt8(0x39):
            if exp < 100000:  # clamp; anything this large saturates dp anyway
                exp = exp * 10 + Int(ptr[i] - UInt8(0x30))
            i += 1
        if exp_neg:
            a.dp -= exp
        else:
            a.dp += exp

    _trim(a)
    return a^


@always_inline
def _prefix_less_than(a: Decimal, cutoff: StaticString) -> Bool:
    """Is the leading prefix of `a.d` lexicographically below `cutoff`?

    `cutoff` is a `StaticString` (a view into static storage), so the slow path
    allocates nothing here — the previous `String` return from `_left_cutoff`
    heap-allocated on every shift step.
    """
    var cb = cutoff.as_bytes()
    # Iterate over the cutoff's LOGICAL byte length, not len(cb): if the byte
    # source ever carries a trailing NUL terminator, a NUL byte would compare
    # below every digit and wrongly flip the result when the digit count equals
    # the cutoff length. byte_length() excludes any terminator.
    var n = cutoff.byte_length()
    for i in range(n):
        if i >= a.nd:
            return True
        var ad = a.d[i] + UInt8(0x30)  # back to ASCII for comparison
        if ad != cb[i]:
            return ad < cb[i]
    return False


# Left-shift cheat table (Go strconv.decimal `leftcheats`): for a shift of k
# (multiply by 2^k), entry k gives the number of new digits introduced, minus
# one if the digit prefix is below `cutoff`. Indices 0..60.
def _build_left_delta() -> InlineArray[Int, 61]:
    """Build the left-shift new-digit-count table (delta of `leftcheats`)."""
    var t = InlineArray[Int, 61](fill=0)
    var vals = [
        0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7, 7,
        8, 8, 8, 9, 9, 9, 10, 10, 10, 10, 11, 11, 11, 12, 12, 12, 13, 13, 13,
        13, 14, 14, 14, 15, 15, 15, 16, 16, 16, 16, 17, 17, 17, 18, 18, 18, 19,
    ]
    for i in range(61):
        t[i] = vals[i]
    return t^


comptime _LEFT_DELTA = _build_left_delta()


def _left_cutoff(k: Int) -> StaticString:
    """Return the prefix cutoff (leading digits of 5^k) for shift k.

    Returns a `StaticString` backed by static storage — no heap allocation
    (these literals were `String(...)` before, which allocated per shift step).
    """
    if k == 0:
        return ""
    if k == 1:
        return "5"
    if k == 2:
        return "25"
    if k == 3:
        return "125"
    if k == 4:
        return "625"
    if k == 5:
        return "3125"
    if k == 6:
        return "15625"
    if k == 7:
        return "78125"
    if k == 8:
        return "390625"
    if k == 9:
        return "1953125"
    if k == 10:
        return "9765625"
    if k == 11:
        return "48828125"
    if k == 12:
        return "244140625"
    if k == 13:
        return "1220703125"
    if k == 14:
        return "6103515625"
    if k == 15:
        return "30517578125"
    if k == 16:
        return "152587890625"
    if k == 17:
        return "762939453125"
    if k == 18:
        return "3814697265625"
    if k == 19:
        return "19073486328125"
    if k == 20:
        return "95367431640625"
    if k == 21:
        return "476837158203125"
    if k == 22:
        return "2384185791015625"
    if k == 23:
        return "11920928955078125"
    if k == 24:
        return "59604644775390625"
    if k == 25:
        return "298023223876953125"
    if k == 26:
        return "1490116119384765625"
    if k == 27:
        return "7450580596923828125"
    if k == 28:
        return "37252902984619140625"
    if k == 29:
        return "186264514923095703125"
    if k == 30:
        return "931322574615478515625"
    if k == 31:
        return "4656612873077392578125"
    if k == 32:
        return "23283064365386962890625"
    if k == 33:
        return "116415321826934814453125"
    if k == 34:
        return "582076609134674072265625"
    if k == 35:
        return "2910383045673370361328125"
    if k == 36:
        return "14551915228366851806640625"
    if k == 37:
        return "72759576141834259033203125"
    if k == 38:
        return "363797880709171295166015625"
    if k == 39:
        return "1818989403545856475830078125"
    if k == 40:
        return "9094947017729282379150390625"
    if k == 41:
        return "45474735088646411895751953125"
    if k == 42:
        return "227373675443232059478759765625"
    if k == 43:
        return "1136868377216160297393798828125"
    if k == 44:
        return "5684341886080801486968994140625"
    if k == 45:
        return "28421709430404007434844970703125"
    if k == 46:
        return "142108547152020037174224853515625"
    if k == 47:
        return "710542735760100185871124267578125"
    if k == 48:
        return "3552713678800500929355621337890625"
    if k == 49:
        return "17763568394002504646778106689453125"
    if k == 50:
        return "88817841970012523233890533447265625"
    if k == 51:
        return "444089209850062616169452667236328125"
    if k == 52:
        return "2220446049250313080847263336181640625"
    if k == 53:
        return "11102230246251565404236316680908203125"
    if k == 54:
        return "55511151231257827021181583404541015625"
    if k == 55:
        return "277555756156289135105907917022705078125"
    if k == 56:
        return "1387778780781445675529539585113525390625"
    if k == 57:
        return "6938893903907228377647697925567626953125"
    if k == 58:
        return "34694469519536141888238489627838134765625"
    if k == 59:
        return "173472347597680709441192448139190673828125"
    return "867361737988403547205962240695953369140625"  # k == 60


def _left_shift(mut a: Decimal, k: Int):
    """Binary left shift (multiply by 2^k); k <= MAX_SHIFT."""
    var delta = _LEFT_DELTA[k]
    if _prefix_less_than(a, _left_cutoff(k)):
        delta -= 1

    var r = a.nd  # read index (exclusive, walk down)
    var w = a.nd + delta  # write index (exclusive, walk down)

    var n: UInt64 = 0
    r -= 1
    while r >= 0:
        n += UInt64(a.d[r]) << UInt64(k)
        var quo = n // 10
        var rem = n - 10 * quo
        w -= 1
        if w < MAX_DIGITS:
            a.d[w] = UInt8(rem)
        elif rem != 0:
            a.trunc = True
        n = quo
        r -= 1

    while n > 0:
        var quo = n // 10
        var rem = n - 10 * quo
        w -= 1
        if w < MAX_DIGITS:
            a.d[w] = UInt8(rem)
        elif rem != 0:
            a.trunc = True
        n = quo

    a.nd += delta
    if a.nd >= MAX_DIGITS:
        a.nd = MAX_DIGITS
    a.dp += delta
    _trim(a)


def _right_shift(mut a: Decimal, k: Int):
    """Binary right shift (divide by 2^k); k <= MAX_SHIFT."""
    var r = 0  # read pointer
    var w = 0  # write pointer

    # Pick up enough leading digits to cover the first shift.
    var n: UInt64 = 0
    while (n >> UInt64(k)) == 0:
        if r >= a.nd:
            if n == 0:
                a.nd = 0
                return
            while (n >> UInt64(k)) == 0:
                n = n * 10
                r += 1
            break
        n = n * 10 + UInt64(a.d[r])
        r += 1
    a.dp -= r - 1

    var mask: UInt64 = (UInt64(1) << UInt64(k)) - 1

    while r < a.nd:
        var c = UInt64(a.d[r])
        var dig = n >> UInt64(k)
        n &= mask
        a.d[w] = UInt8(dig)
        w += 1
        n = n * 10 + c
        r += 1

    while n > 0:
        var dig = n >> UInt64(k)
        n &= mask
        if w < MAX_DIGITS:
            a.d[w] = UInt8(dig)
            w += 1
        elif dig > 0:
            a.trunc = True
        n = n * 10

    a.nd = w
    _trim(a)


def _shift(mut a: Decimal, k: Int):
    """Binary shift left (k>0) or right (k<0) by |k| bits."""
    if a.nd == 0:
        return
    if k > 0:
        var rem = k
        while rem > MAX_SHIFT:
            _left_shift(a, MAX_SHIFT)
            rem -= MAX_SHIFT
        _left_shift(a, rem)
    elif k < 0:
        var rem = k
        while rem < -MAX_SHIFT:
            _right_shift(a, MAX_SHIFT)
            rem += MAX_SHIFT
        _right_shift(a, -rem)


@always_inline
def _should_round_up(a: Decimal, nd: Int) -> Bool:
    """Round-half-to-even decision when chopping `a` to `nd` digits."""
    if nd < 0 or nd >= a.nd:
        return False
    if a.d[nd] == 5 and nd + 1 == a.nd:  # exactly halfway
        if a.trunc:
            return True
        return nd > 0 and (a.d[nd - 1] % 2) != 0
    return a.d[nd] >= 5


def _rounded_integer(a: Decimal) -> UInt64:
    """Integer part of `a`, rounded half-to-even. No overflow guarantees.

    Precondition: `a.dp <= 20`. Callers reach this only after scaling the
    decimal into [0.5, 1) and extracting 1 + 52 mantissa bits, so `dp` is small.
    The `dp > 20` branch returns a sentinel that would corrupt the mantissa if
    ever hit; the assert documents and enforces the invariant under ASSERT=all
    without changing runtime behaviour when assertions are off.
    """
    debug_assert(a.dp <= 20, "_rounded_integer precondition violated: a.dp > 20")
    if a.dp > 20:
        return UInt64(0xFFFFFFFFFFFFFFFF)
    var i = 0
    var n: UInt64 = 0
    while i < a.dp and i < a.nd:
        n = n * 10 + UInt64(a.d[i])
        i += 1
    while i < a.dp:
        n *= 10
        i += 1
    if _should_round_up(a, a.dp):
        n += 1
    return n


# Decimal-power-of-ten to binary-power-of-two step table (Go `powtab`).
def _build_powtab() -> InlineArray[Int, 9]:
    """Build the decimal-exponent to binary-shift step table."""
    var t = InlineArray[Int, 9](fill=0)
    var vals = [1, 3, 6, 9, 13, 16, 19, 23, 26]
    for i in range(9):
        t[i] = vals[i]
    return t^


comptime _POWTAB = _build_powtab()


def decimal_to_double_bits(mut a: Decimal) -> UInt64:
    """Convert a parsed `Decimal` to correctly-rounded IEEE-754 double bits.

    Implements Go strconv's `floatBits` for float64: scale by powers of two
    into [0.5, 1), handle subnormals by shifting down, extract 53 mantissa bits
    with banker's rounding, then assemble sign/exponent/mantissa. Overflow ->
    +/-inf bits; underflow -> +/-0.
    """
    comptime MB: UInt64 = UInt64(MANT_BITS)
    var exp = 0
    var mant: UInt64

    if a.nd == 0:
        # Zero.
        return (UInt64(1) << 63) if a.neg else UInt64(0)

    # Obvious overflow / underflow shortcuts.
    if a.dp > 310:
        return _overflow_bits(a.neg)
    if a.dp < -330:
        return (UInt64(1) << 63) if a.neg else UInt64(0)

    # Scale by powers of two until in [0.5, 1).
    while a.dp > 0:
        var n: Int
        if a.dp >= 9:  # len(_POWTAB)
            n = 27
        else:
            n = _POWTAB[a.dp]
        _shift(a, -n)
        exp += n
    while a.dp < 0 or (a.dp == 0 and a.d[0] < 5):
        var n: Int
        if -a.dp >= 9:
            n = 27
        else:
            n = _POWTAB[-a.dp]
        _shift(a, n)
        exp -= n

    # Range is [0.5,1) but float range is [1,2).
    exp -= 1

    # Minimum representable exponent is BIAS+1; move up if smaller (subnormal).
    if exp < BIAS + 1:
        var n = BIAS + 1 - exp
        _shift(a, -n)
        exp += n

    if exp - BIAS >= (1 << EXP_BITS) - 1:
        return _overflow_bits(a.neg)

    # Extract 1 + MANT_BITS bits.
    _shift(a, 1 + MANT_BITS)
    mant = _rounded_integer(a)

    # Rounding may have carried into an extra bit.
    if mant == (UInt64(2) << MB):
        mant >>= 1
        exp += 1
        if exp - BIAS >= (1 << EXP_BITS) - 1:
            return _overflow_bits(a.neg)

    # Denormalized?
    if (mant & (UInt64(1) << MB)) == 0:
        exp = BIAS

    # Assemble bits.
    var bits = mant & ((UInt64(1) << MB) - 1)
    var biased = UInt64((exp - BIAS) & ((1 << EXP_BITS) - 1))
    bits |= biased << MB
    if a.neg:
        bits |= UInt64(1) << 63
    return bits


@always_inline
def _overflow_bits(neg: Bool) -> UInt64:
    """+/-inf IEEE-754 bit pattern."""
    var bits = UInt64(0x7FF0000000000000)
    if neg:
        bits |= UInt64(1) << 63
    return bits


def parse_float_slow(
    ptr: UnsafePointer[UInt8, _],
    token_start: Int,
    token_end: Int,
    negative: Bool,
) -> UInt64:
    """Correctly-rounded decimal->double over a JSON number token.

    Parses `ptr[token_start:token_end]` (with `negative` indicating a stripped
    leading minus) and returns the IEEE-754 Float64 bits of the exact decimal
    value, rounded to nearest with ties to even.
    """
    var a = parse_decimal_token(ptr, token_start, token_end, negative)
    return decimal_to_double_bits(a)
