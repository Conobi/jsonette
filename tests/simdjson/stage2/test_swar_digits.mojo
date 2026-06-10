"""Exhaustive equivalence: production SWAR digit fns vs the reference impl.

`_are_8_digits` / `_parse_8_digits` are behaviour-preserving rewrites. This
harness pins that: for every byte value in every one of the 8 lanes (others held
at a digit), plus the all-9s max-carry row and random all-digit draws, the
production result must equal the reference (old) result.
"""
from simdjson.stage2.numbers import _are_8_digits, _parse_8_digits


def _ref_are_8(ptr: UnsafePointer[UInt8, _], pos: Int) -> Bool:
    var sub = (ptr + pos).load[width=8]() - SIMD[DType.uint8, 8](0x30)
    return sub.reduce_max() <= 9


def _ref_parse_8(ptr: UnsafePointer[UInt8, _], pos: Int) -> UInt64:
    var chunk = (ptr + pos).load[width=8]()
    var d = (chunk - SIMD[DType.uint8, 8](0x30)).cast[DType.uint64]()
    var g1 = d[0] * 1000 + d[1] * 100 + d[2] * 10 + d[3]
    var g2 = d[4] * 1000 + d[5] * 100 + d[6] * 10 + d[7]
    return g1 * 10000 + g2


def _buf8() -> List[UInt8]:
    var b = List[UInt8]()
    for _ in range(8):
        b.append(UInt8(0x30))  # "00000000"
    for _ in range(8):
        b.append(UInt8(0))     # NUL over-read padding
    return b^


def main() raises:
    # Per-lane exhaustive: every byte value in each lane, others = '5'.
    for lane in range(8):
        var b = _buf8()
        for i in range(8):
            b[i] = UInt8(0x35)  # '5'
        for v in range(256):
            b[lane] = UInt8(v)
            var p = b.unsafe_ptr()
            var ref_digit = _ref_are_8(p, 0)
            if _are_8_digits(p, 0) != ref_digit:
                raise Error("detect mismatch lane " + String(lane) + " v " + String(v))
            # parse equivalence only defined when all 8 are digits
            if ref_digit and _parse_8_digits(p, 0) != _ref_parse_8(p, 0):
                raise Error("parse mismatch lane " + String(lane) + " v " + String(v))

    # All-9s maximum-carry row.
    var b9 = _buf8()
    for i in range(8):
        b9[i] = UInt8(0x39)  # '9'
    var p9 = b9.unsafe_ptr()
    if _parse_8_digits(p9, 0) != 99999999:
        raise Error("all-9s parse wrong")
    if not _are_8_digits(p9, 0):
        raise Error("all-9s detect wrong")

    # Deterministic pseudo-random all-digit draws (LCG; no Math.random).
    var seed: UInt64 = 0x2545F4914F6CDD1D
    for _ in range(100000):
        seed = seed * 6364136223846793005 + 1442695040888963407
        var b = _buf8()
        var s = seed
        for i in range(8):
            b[i] = UInt8(0x30) + UInt8(s % 10)
            s //= 10
        var p = b.unsafe_ptr()
        if _parse_8_digits(p, 0) != _ref_parse_8(p, 0):
            raise Error("random parse mismatch")
    print("test_swar_digits: all passed")
