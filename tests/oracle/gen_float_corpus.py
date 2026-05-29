#!/usr/bin/env python3
"""Independent arbitrary-precision oracle and float-corpus generator.

Computes the correctly-rounded (round-to-nearest, ties-to-even) IEEE-754 double
of a decimal string using ONLY decimal.Decimal + fractions.Fraction. It MUST NOT
use float(str)/atof/strtod. Emits a TSV of (decimal_string, expected_hex).

Precision: 768 > 752, the significant-digit count of the longest exact
double/midpoint expansion (subnormal floor 2^-1075), with margin.
"""
import struct
import sys
from decimal import Decimal, getcontext
from fractions import Fraction

getcontext().prec = 800

MAX_FINITE = Fraction((1 << 53) - 1, 1) * Fraction(1 << (1023 - 52))
INF_BITS_POS = 0x7FF0000000000000
INF_BITS_NEG = 0xFFF0000000000000


def _pow2_frac(k: int) -> Fraction:
    return Fraction(1 << k, 1) if k >= 0 else Fraction(1, 1 << (-k))


def _floor_log2(f: Fraction) -> int:
    e = f.numerator.bit_length() - f.denominator.bit_length()
    if _pow2_frac(e) > f:
        e -= 1
    while _pow2_frac(e + 1) <= f:
        e += 1
    return e


def _round_half_even(f: Fraction) -> int:
    floor = f.numerator // f.denominator
    rem = f - floor
    if rem < Fraction(1, 2):
        return floor
    if rem > Fraction(1, 2):
        return floor + 1
    return floor if floor % 2 == 0 else floor + 1


def _half_ulp_at_max() -> Fraction:
    return _pow2_frac(971 - 1)


def _double_to_bits(neg: bool, value_frac: Fraction) -> int:
    if value_frac == 0:
        return (1 << 63) if neg else 0
    if value_frac > MAX_FINITE + _half_ulp_at_max():
        return INF_BITS_NEG if neg else INF_BITS_POS
    e = _floor_log2(value_frac)
    if e < -1022:
        scaled = value_frac / _pow2_frac(-1074)
        m = _round_half_even(scaled)
        if m == 0:
            return (1 << 63) if neg else 0
        if m >= (1 << 52):
            out = (1 << 52)
            return (out | (1 << 63)) if neg else out
        return (m | (1 << 63)) if neg else m
    ulp_exp = e - 52
    scaled = value_frac / _pow2_frac(ulp_exp)
    m = _round_half_even(scaled)
    if m >= (1 << 53):
        m >>= 1
        e += 1
    if e > 1023:
        return INF_BITS_NEG if neg else INF_BITS_POS
    biased_e = e + 1023
    mant = m & ((1 << 52) - 1)
    out = (biased_e << 52) | mant
    return (out | (1 << 63)) if neg else out


def expected_hex(decimal_str: str) -> str:
    s = decimal_str.strip()
    neg = s.startswith("-")
    body = s[1:] if (s.startswith("-") or s.startswith("+")) else s
    value = Fraction(Decimal(body))
    return "0x%016X" % _double_to_bits(neg, value)


def _adjacent_midpoint_decimals(d_bits: int):
    val = struct.unpack("<d", struct.pack("<Q", d_bits))[0]
    f_d = Fraction(val)
    f_s = Fraction(struct.unpack("<d", struct.pack("<Q", d_bits + 1))[0])
    mid = (f_d + f_s) / 2
    mid_dec = Decimal(mid.numerator) / Decimal(mid.denominator)
    mid_str = format(mid_dec.normalize(), "f")
    places = len(mid_str.split(".")[1]) if "." in mid_str else 0
    ulp_dec = Decimal(1).scaleb(-places)
    below = format((mid_dec - ulp_dec).normalize(), "f")
    above = format((mid_dec + ulp_dec).normalize(), "f")
    return [mid_str, below, above]


EDGE_CASES = [
    "5e-324", "2.2250738585072014e-308", "1e-310", "1.7976931348623157e308",
    "1e309", "1e400", "-1e400", "1e-400", "0.30000000000000004",
    "1.0000000000000002", "-0.0", "-0e0", "0.0", "0e0",
    "0.1000000000000000055511151231257827021181583404541015625",
]


def main():
    rows = [(s, expected_hex(s)) for s in EDGE_CASES]
    seed = 0x2545F4914F6CDD1D
    def nxt():
        nonlocal seed
        seed = (seed * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        return seed
    for _ in range(2000):
        mant_len = 1 + (nxt() % 25)
        digits = "".join(str(nxt() % 10) for _ in range(mant_len)).lstrip("0") or "0"
        exp = (nxt() % 661) - 330
        rows.append((f"{digits}e{exp}", expected_hex(f"{digits}e{exp}")))
    for _ in range(2000):
        bits = nxt() & 0x7FEFFFFFFFFFFFFF
        if bits == 0:
            continue
        for s in _adjacent_midpoint_decimals(bits):
            rows.append((s, expected_hex(s)))
    out = "\n".join(f"{s}\t{h}" for s, h in rows) + "\n"
    if "--check" in sys.argv:
        sys.stdout.write(out)
        return
    with open("tests/fixtures/float_corpus.tsv", "w") as f:
        f.write(out)
    sys.stderr.write(f"wrote {len(rows)} rows\n")


if __name__ == "__main__":
    main()
