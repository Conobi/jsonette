"""Allocation-event counter contract.

Built WITH `-D BENCH_ALLOC_COUNT`, the parser records one allocation event per
heap allocation on the per-parse-call path:

    positions list (parser, reused)   -> 1 on a COLD parse (must grow), 0 when warm
    padded input buffer (parser)       -> 1 on a COLD parse (must grow), 0 when warm
    tape.elements (parser-owned tape)  -> 1 on a COLD parse (must grow), 0 when warm
    tape.string_buf (parser-owned tape)-> 1 on a COLD parse (must grow), 0 when warm

So a cold parse records 4 and a warm parse on same-size input records 0. The
tape is now owned by the Parser and reused across parses (Document is a
non-owning view over it), so a warm steady-state loop performs ZERO heap
allocations per parse — every one of the four grow-only buffers contributes 0.

Built WITHOUT the define (default/production build), every counter call is
comptime-elided: the build still compiles and `get_alloc_count()` reads 0.
"""

from std.testing import assert_equal, assert_true
from jsonette.document import parse
from jsonette._alloc_count import (
    ALLOC_COUNT_ENABLED,
    reset_alloc_count,
    get_alloc_count,
)


def _make_bytes(s: String) -> List[UInt8]:
    """Copy a String's UTF-8 bytes into a fresh List[UInt8]."""
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def test_alloc_count_warm_reuse() raises:
    """Cold parse records 4 allocs; warm same-size reparse records 0.

    The warm zero-alloc path is `Document.reparse`, which rebuilds into the
    owning parser's reused buffers (a fresh `parse` would allocate a new parser).
    Also reads a value from each parse so we know instrumentation did not break
    parsing. When the counter is disabled, both counts are 0 and only the parse
    correctness is asserted.
    """
    # Same byte length on both calls so the padded buffer is reused while warm.
    var json1 = _make_bytes(String('{"a": 1, "b": 2}'))
    var json2 = _make_bytes(String('{"c": 3, "d": 4}'))
    assert_equal(len(json1), len(json2))

    # Call 1 (cold): the padded buffer must be allocated.
    reset_alloc_count()
    var doc = parse(json1)
    var count1 = get_alloc_count()
    assert_equal(doc.root().field(String("a")).get_uint(), UInt64(1))

    # Call 2 (warm reparse, same size): every buffer reused, so it contributes 0.
    reset_alloc_count()
    doc.reparse(json2)
    var count2 = get_alloc_count()
    assert_equal(doc.root().field(String("c")).get_uint(), UInt64(3))

    comptime if ALLOC_COUNT_ENABLED:
        # Cold: positions + padded + tape.elements + tape.string_buf = 4
        assert_equal(count1, 4)
        # Warm: every buffer (incl. the parser-owned tape) is reused = 0 allocs.
        assert_equal(count2, 0)
        assert_true(count2 <= count1)
    else:
        # Disabled build: counter is elided and reads 0.
        assert_equal(count1, 0)
        assert_equal(count2, 0)


def test_alloc_count_string_warm_reuse() raises:
    """Warm reparse(String) on same-size input adds 0 allocs (as_bytes is a view).

    The String convenience overload must forward a non-owning `as_bytes()` view to
    the byte path; it must not allocate a per-call buffer. So a warm same-size
    `reparse(String)` records 0, matching the List path.
    """
    # Same byte length on both calls so the padded buffer is reused while warm.
    var json1 = String('{"a": 1, "b": 2}')
    var json2 = String('{"c": 3, "d": 4}')
    assert_equal(json1.byte_length(), json2.byte_length())

    # Call 1 (cold): the padded buffer must be allocated.
    reset_alloc_count()
    var doc = parse(json1)
    var count1 = get_alloc_count()
    assert_equal(doc.root().field(String("a")).get_uint(), UInt64(1))

    # Call 2 (warm reparse, same size, String path): every buffer reused, so 0.
    reset_alloc_count()
    doc.reparse(json2)
    var count2 = get_alloc_count()
    assert_equal(doc.root().field(String("c")).get_uint(), UInt64(3))

    comptime if ALLOC_COUNT_ENABLED:
        # Cold: positions + padded + tape.elements + tape.string_buf = 4
        assert_equal(count1, 4)
        # Warm: every buffer is reused and as_bytes() does not allocate = 0.
        assert_equal(count2, 0)
        assert_true(count2 <= count1)
    else:
        # Disabled build: counter is elided and reads 0.
        assert_equal(count1, 0)
        assert_equal(count2, 0)


def main() raises:
    test_alloc_count_warm_reuse()
    test_alloc_count_string_warm_reuse()
    print("test_alloc_count: all passed")
