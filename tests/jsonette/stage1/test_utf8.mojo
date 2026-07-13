"""Fused Stage 1 UTF-8 validation: boundary, carry, and differential tests.

Targets the checker's cross-chunk seams: offset sweeps across the 32/64-byte
boundaries, eof-aligned truncations (only the eof carry catches them), the
ASCII fast path's carry fold, the stale prev-block after an ASCII chunk, and a
deterministic fuzz. Every verdict is cross-checked against the stdlib
`_is_valid_utf8` oracle.
"""

from std.collections.string.string_slice import _is_valid_utf8
from std.testing import assert_equal, assert_true

from jsonette.document import parse
from jsonette.stage1.indexer import structural_index


def _pad(data: List[UInt8]) -> List[UInt8]:
    """Pad buffer for Stage 1: input + zero bytes, as the Parser does."""
    var n = len(data)
    var num_chunks = (n + 63) // 64
    var padded_len = num_chunks * 64 + 128
    var buf = List[UInt8](capacity=padded_len)
    for i in range(n):
        buf.append(data[i])
    while len(buf) < padded_len:
        buf.append(UInt8(0))
    return buf^


def _utf8_ok(data: List[UInt8]) raises -> Bool:
    """Run the fused checker over `data`; True iff it accepts the bytes."""
    var padded = _pad(data)
    var positions = List[UInt32]()
    try:
        structural_index[validate_utf8=True](padded.unsafe_ptr(), len(data), positions)
        return True
    except:
        return False


def _assert_verdict(name: String, data: List[UInt8], expected: Bool) raises:
    """Assert the fused checker's verdict AND its agreement with the stdlib oracle."""
    var got = _utf8_ok(data)
    assert_true(
        got == expected,
        name + ": expected valid=" + String(expected) + ", got " + String(got),
    )
    assert_true(
        got == _is_valid_utf8(Span(data)),
        name + ": fused checker disagrees with stdlib _is_valid_utf8",
    )


def _sweep(name: String, seq: List[UInt8], expected: Bool) raises:
    """Check `seq` at every offset 0..80 (ASCII fill on both sides), covering
    every phase of the 32-byte half-block and 64-byte chunk boundaries."""
    for offset in range(81):
        var data = List[UInt8]()
        for _ in range(offset):
            data.append(UInt8(0x61))  # 'a'
        for b in seq:
            data.append(b)
        for _ in range(8):
            data.append(UInt8(0x61))
        _assert_verdict(name + " at offset " + String(offset), data, expected)


def test_valid_sequences_all_offsets() raises:
    _sweep("2-byte C3 A9", [UInt8(0xC3), UInt8(0xA9)], True)
    _sweep("3-byte E6 97 A5", [UInt8(0xE6), UInt8(0x97), UInt8(0xA5)], True)
    _sweep(
        "4-byte F0 9F 98 80",
        [UInt8(0xF0), UInt8(0x9F), UInt8(0x98), UInt8(0x80)],
        True,
    )
    # Highest code point U+10FFFF.
    _sweep(
        "4-byte F4 8F BF BF",
        [UInt8(0xF4), UInt8(0x8F), UInt8(0xBF), UInt8(0xBF)],
        True,
    )
    # Lowest non-overlong of each length.
    _sweep("2-byte C2 80", [UInt8(0xC2), UInt8(0x80)], True)
    _sweep("3-byte E0 A0 80", [UInt8(0xE0), UInt8(0xA0), UInt8(0x80)], True)
    _sweep(
        "4-byte F0 90 80 80",
        [UInt8(0xF0), UInt8(0x90), UInt8(0x80), UInt8(0x80)],
        True,
    )
    # Surrogate-adjacent valid boundaries: U+D7FF and U+E000.
    _sweep("ED 9F BF (U+D7FF)", [UInt8(0xED), UInt8(0x9F), UInt8(0xBF)], True)
    _sweep("EE 80 80 (U+E000)", [UInt8(0xEE), UInt8(0x80), UInt8(0x80)], True)


def test_invalid_sequences_all_offsets() raises:
    _sweep("lone continuation 80", [UInt8(0x80)], False)
    _sweep("lone lead C2", [UInt8(0xC2)], False)
    _sweep("truncated 3-byte E6 97", [UInt8(0xE6), UInt8(0x97)], False)
    _sweep(
        "truncated 4-byte F0 9F 98", [UInt8(0xF0), UInt8(0x9F), UInt8(0x98)], False
    )
    _sweep("overlong C0 80", [UInt8(0xC0), UInt8(0x80)], False)
    _sweep("overlong C1 BF", [UInt8(0xC1), UInt8(0xBF)], False)
    _sweep("overlong E0 80 80", [UInt8(0xE0), UInt8(0x80), UInt8(0x80)], False)
    _sweep("overlong E0 9F BF", [UInt8(0xE0), UInt8(0x9F), UInt8(0xBF)], False)
    _sweep(
        "overlong F0 80 80 80",
        [UInt8(0xF0), UInt8(0x80), UInt8(0x80), UInt8(0x80)],
        False,
    )
    _sweep(
        "overlong F0 8F BF BF",
        [UInt8(0xF0), UInt8(0x8F), UInt8(0xBF), UInt8(0xBF)],
        False,
    )
    _sweep("surrogate ED A0 80", [UInt8(0xED), UInt8(0xA0), UInt8(0x80)], False)
    _sweep("surrogate ED BF BF", [UInt8(0xED), UInt8(0xBF), UInt8(0xBF)], False)
    _sweep(
        "too large F4 90 80 80",
        [UInt8(0xF4), UInt8(0x90), UInt8(0x80), UInt8(0x80)],
        False,
    )
    _sweep(
        "illegal lead F5 80 80 80",
        [UInt8(0xF5), UInt8(0x80), UInt8(0x80), UInt8(0x80)],
        False,
    )
    _sweep("illegal byte FF", [UInt8(0xFF)], False)
    _sweep("illegal byte FE", [UInt8(0xFE)], False)
    _sweep(
        "extra continuation C3 A9 A9", [UInt8(0xC3), UInt8(0xA9), UInt8(0xA9)], False
    )


def test_truncation_at_exact_chunk_boundary() raises:
    """Inputs ending mid-sequence exactly at a 64-byte boundary: the NUL
    padding cannot catch these in-chunk, only the eof carry does."""
    for total in [64, 128, 192]:
        # Dangling 2-byte lead as the very last byte.
        var d1 = List[UInt8]()
        for _ in range(total - 1):
            d1.append(UInt8(0x61))
        d1.append(UInt8(0xC2))
        _assert_verdict("dangling C2 at len " + String(total), d1, False)

        # Dangling 3-byte lead with one continuation: still incomplete.
        var d2 = List[UInt8]()
        for _ in range(total - 2):
            d2.append(UInt8(0x61))
        d2.append(UInt8(0xE6))
        d2.append(UInt8(0x97))
        _assert_verdict("dangling E6 97 at len " + String(total), d2, False)

        # Complete 2-byte sequence ending exactly at the boundary: valid.
        var d3 = List[UInt8]()
        for _ in range(total - 2):
            d3.append(UInt8(0x61))
        d3.append(UInt8(0xC3))
        d3.append(UInt8(0xA9))
        _assert_verdict("complete C3 A9 at len " + String(total), d3, True)

        # Complete 4-byte sequence ending exactly at the boundary: valid.
        var d4 = List[UInt8]()
        for _ in range(total - 4):
            d4.append(UInt8(0x61))
        d4.append(UInt8(0xF0))
        d4.append(UInt8(0x9F))
        d4.append(UInt8(0x98))
        d4.append(UInt8(0x80))
        _assert_verdict("complete F0 9F 98 80 at len " + String(total), d4, True)


def test_incomplete_chunk_then_ascii_chunk() raises:
    """A chunk ending mid-sequence then a pure-ASCII chunk: the ASCII fast
    path must fold the carried `prev_incomplete` into the error."""
    var data = List[UInt8]()
    for _ in range(63):
        data.append(UInt8(0x61))
    data.append(UInt8(0xE6))  # dangling 3-byte lead at position 63
    for _ in range(64):
        data.append(UInt8(0x61))  # chunk 1: pure ASCII
    _assert_verdict("dangling lead then ASCII chunk", data, False)


def test_ascii_chunk_between_non_ascii_chunks() raises:
    """Stale prev-block seam: after an ASCII chunk, a lone continuation
    opening the next chunk must be flagged and a complete sequence must not."""
    # Chunk 0: complete 2-byte char then ASCII. Chunk 1: pure ASCII.
    # Chunk 2 opens with a lone continuation byte: must reject.
    var bad = List[UInt8]()
    bad.append(UInt8(0xC3))
    bad.append(UInt8(0xA9))
    for _ in range(62):
        bad.append(UInt8(0x61))
    for _ in range(64):
        bad.append(UInt8(0x61))
    bad.append(UInt8(0x80))
    for _ in range(7):
        bad.append(UInt8(0x61))
    _assert_verdict("lone continuation after ASCII chunk", bad, False)

    # Same shape, but chunk 2 opens with a complete 3-byte char: must accept.
    var good = List[UInt8]()
    good.append(UInt8(0xC3))
    good.append(UInt8(0xA9))
    for _ in range(62):
        good.append(UInt8(0x61))
    for _ in range(64):
        good.append(UInt8(0x61))
    good.append(UInt8(0xE6))
    good.append(UInt8(0x97))
    good.append(UInt8(0xA5))
    for _ in range(5):
        good.append(UInt8(0x61))
    _assert_verdict("complete sequence after ASCII chunk", good, True)


def test_fuzz_differential_against_stdlib() raises:
    """Deterministic block fuzz (valid multibyte blocks, ASCII runs, rare raw
    random bytes): the fused checker must match the stdlib oracle."""
    var state = UInt64(0x9E3779B97F4A7C15)

    @parameter
    def next_rand(mut state: UInt64) -> UInt64:
        state = state * 6364136223846793005 + 1442695040888963407
        return state >> 33

    for trial in range(300):
        var data = List[UInt8]()
        var n_blocks = 8 + Int(next_rand(state) % 60)
        for _ in range(n_blocks):
            var pick = next_rand(state) % 8
            if pick < 3:
                # ASCII run of 1..8 bytes.
                var run = 1 + Int(next_rand(state) % 8)
                for _ in range(run):
                    data.append(UInt8(0x61 + Int(next_rand(state) % 26)))
            elif pick == 3:
                data.append(UInt8(0xC3))
                data.append(UInt8(0xA9))
            elif pick == 4:
                data.append(UInt8(0xE6))
                data.append(UInt8(0x97))
                data.append(UInt8(0xA5))
            elif pick == 5:
                data.append(UInt8(0xF0))
                data.append(UInt8(0x9F))
                data.append(UInt8(0x98))
                data.append(UInt8(0x80))
            elif pick == 6:
                data.append(UInt8(0xED))
                data.append(UInt8(0x9F))
                data.append(UInt8(0xBF))
            else:
                # Chaos: one raw byte of any value.
                data.append(UInt8(next_rand(state) & 0xFF))
        assert_true(
            _utf8_ok(data) == _is_valid_utf8(Span(data)),
            "fuzz trial " + String(trial) + " (len " + String(len(data))
            + ") disagrees with stdlib validator",
        )


def test_parse_surfaces_invalid_utf8_error() raises:
    """`parse()` reports INVALID_UTF8, and it wins over later structural errors."""
    # Invalid byte inside an otherwise-valid document.
    var doc = List[UInt8]()
    for b in String('{"k":"').as_bytes():
        doc.append(b)
    doc.append(UInt8(0xFF))
    for b in String('"}').as_bytes():
        doc.append(b)
    var raised = False
    try:
        _ = parse(doc)
    except err:
        raised = True
        assert_equal(String(err), "INVALID_UTF8 at position 0")
    assert_true(raised, "parse must reject invalid UTF-8")

    # 64-byte-aligned input ending mid-sequence inside an unclosed string:
    # the fused Stage 1 check fires before Stage 2 sees the unclosed quote.
    var doc2 = List[UInt8]()
    for b in String('{"k":"').as_bytes():
        doc2.append(b)
    while len(doc2) < 63:
        doc2.append(UInt8(0x61))
    doc2.append(UInt8(0xC2))
    var raised2 = False
    try:
        _ = parse(doc2)
    except err:
        raised2 = True
        assert_equal(String(err), "INVALID_UTF8 at position 0")
    assert_true(raised2, "parse must reject eof-truncated UTF-8")


def main() raises:
    test_valid_sequences_all_offsets()
    test_invalid_sequences_all_offsets()
    test_truncation_at_exact_chunk_boundary()
    test_incomplete_chunk_then_ascii_chunk()
    test_ascii_chunk_between_non_ascii_chunks()
    test_fuzz_differential_against_stdlib()
    test_parse_surfaces_invalid_utf8_error()
    print("All fused UTF-8 validation tests passed!")
