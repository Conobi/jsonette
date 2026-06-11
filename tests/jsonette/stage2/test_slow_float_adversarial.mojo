"""Adversarial slow-path inputs — locks the DoS bound and over-cap correctness.

The slow path is bounded: `MAX_DIGITS=800` caps the significand and the `dp`
clamps early-out on over/underflow exponents, so per-token work is independent
of input length. These cases prove (a) extreme exponents early-out to inf/0,
(b) over-cap significands are still correctly-rounded (the decimal point must
survive truncation), and (c) a 100k-digit token parses correctly AND fast — if
the slow path scaled with digit count this test would hang. Expected bits are
the oracle's (Python `float`), confirmed independently.
"""
from jsonette.stage2.slow_float import parse_float_slow


def _bits(s: String, negative: Bool) -> UInt64:
    """Parse `s` through the slow path (NUL-padded), return the float bits."""
    var buf = List[UInt8](unsafe_uninit_length=0)
    for b in s.as_bytes():
        buf.append(b)
    for _ in range(16):
        buf.append(UInt8(0))  # SWAR over-read padding
    return parse_float_slow(buf.unsafe_ptr(), 0, len(s.as_bytes()), negative)


def _check(s: String, expected: UInt64, negative: Bool = False) raises:
    """Assert the slow path rounds `s` to `expected` IEEE-754 bits."""
    var got = _bits(s, negative)
    if got != expected:
        raise Error(
            "adversarial slow-float mismatch: expected "
            + String(expected) + " got " + String(got)
        )


def _repeat(c: String, n: Int) -> String:
    """Build a string of `n` copies of single-char `c`."""
    var s = String("")
    for _ in range(n):
        s += c
    return s^


def main() raises:
    var inf = UInt64(0x7FF0000000000000)
    var neg_inf = UInt64(0xFFF0000000000000)
    var one = UInt64(0x3FF0000000000000)
    var zero = UInt64(0)

    # Extreme exponents early-out via the dp clamps (bounded, no big-int work).
    _check("1e1000000", inf)
    _check("1e-1000000", zero)
    _check("1e1000000", neg_inf, negative=True)  # -1e1000000

    # Over-cap significands, correctly rounded (dp must survive truncation).
    _check("1." + _repeat("0", 2000) + "5", one)  # ~1.0; trailing 5 is sub-ULP
    _check("0." + _repeat("9", 2000), one)        # 0.999...9 rounds up to 1.0
    _check(_repeat("9", 2000), inf)               # 10^2000 - 1 -> inf

    # Bound demonstration: 100k significant digits. Ingestion is O(len) but the
    # expensive shift phase is capped at MAX_DIGITS, so this is fast, not a hang.
    _check("1." + _repeat("0", 100000) + "1", one)

    # Sticky-trunc tie, PAST the cap (verifies part 2 of the MAX_DIGITS proof,
    # not just the magnitude bound). `tie` is the exact half-ulp midpoint between
    # 1.0 and 1+2^-52 (== 1 + 2^-53, a finite 54-digit decimal):
    #   - the exact tie rounds to even -> 1.0;
    #   - the SAME value with one nonzero digit past the 800-digit cap is strictly
    #     above the midpoint, so the sticky `trunc` flag must round it UP to
    #     1+2^-52. If past-cap trunc were dropped, this would wrongly stay 1.0.
    var tie = String("1.00000000000000011102230246251565404236316680908203125")
    _check(tie, one)  # exact tie -> ties-to-even -> 1.0
    _check(tie + _repeat("0", 800) + "1", UInt64(0x3FF0000000000001))  # round up

    print("test_slow_float_adversarial: all passed")
