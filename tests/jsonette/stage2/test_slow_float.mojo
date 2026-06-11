"""Unit tests for the correctly-rounded decimal->double slow path."""

from jsonette.stage2.slow_float import parse_float_slow


def _bits_of(s: String, negative: Bool) -> UInt64:
    var buf = List[UInt8](unsafe_uninit_length=0)
    for b in s.as_bytes():
        buf.append(b)
    for _ in range(16):
        buf.append(UInt8(0))
    return parse_float_slow(buf.unsafe_ptr(), 0, len(s.as_bytes()), negative)


def _check(s: String, expected: UInt64, negative: Bool = False) raises:
    var got = _bits_of(s, negative)
    if got != expected:
        print("MISMATCH:", s, "expected", expected, "got", got)
        raise Error("slow float mismatch for " + s)


def _ones_with_zeros(zeros: Int) -> String:
    """Build "1." + `zeros` zeros + "1".

    This equals 1.0 in double precision: the trailing 1 sits far below the ULP
    of 1.0, so it cannot change the rounded value — it only sets the sticky
    truncation flag when its position exceeds the significant-digit cap.
    """
    var s = String("1.")
    for _ in range(zeros):
        s += "0"
    s += "1"
    return s^


def main() raises:
    _check("5e-324", UInt64(0x0000000000000001))
    _check("1e-310", UInt64(0x000012688B70E62B))
    _check("0.30000000000000004", UInt64(0x3FD3333333333334))
    _check("1.7976931348623157e308", UInt64(0x7FEFFFFFFFFFFFFF))
    _check("1e309", UInt64(0x7FF0000000000000))
    _check("1e-400", UInt64(0x0000000000000000))
    _check("18446744073709551616", UInt64(0x43F0000000000000))  # 2^64
    _check(
        "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890",
        UInt64(0x54820FE0BA17F469),
    )

    # Regression: fraction digits discarded past the MAX_DIGITS significant-digit
    # cap must NOT corrupt the decimal point. Each value below is exactly 1.0 in
    # double precision; a dp-tracking bug instead yields 0.1, 1e-22, etc.
    var one = UInt64(0x3FF0000000000000)
    _check(_ones_with_zeros(50), one)   # control: under the cap
    _check(_ones_with_zeros(799), one)  # past the 800 significant-digit cap
    _check(_ones_with_zeros(820), one)  # well past the cap

    print("test_slow_float: all passed")
