"""Uint128 and umul128 primitives for the Eisel-Lemire float parsing algorithm."""


@fieldwise_init
struct Uint128(Movable, Copyable):
    """128-bit unsigned integer as two 64-bit halves."""

    var hi: UInt64
    var lo: UInt64


def umul128(a: UInt64, b: UInt64) -> Uint128:
    """64x64 -> 128 unsigned multiply via 32-bit split."""
    var a_lo = a & 0xFFFFFFFF
    var a_hi = a >> 32
    var b_lo = b & 0xFFFFFFFF
    var b_hi = b >> 32

    var ll = a_lo * b_lo
    var lh = a_lo * b_hi
    var hl = a_hi * b_lo
    var hh = a_hi * b_hi

    var mid_sum = (ll >> 32) + (lh & 0xFFFFFFFF) + (hl & 0xFFFFFFFF)
    var hi = hh + (lh >> 32) + (hl >> 32) + (mid_sum >> 32)
    var lo = (ll & 0xFFFFFFFF) | ((mid_sum & 0xFFFFFFFF) << 32)

    return Uint128(hi=hi, lo=lo)
