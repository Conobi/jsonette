"""Comptime-gated heap-allocation event counter.

A process-global counter of heap *allocation events* (count, not bytes) used by
benchmarks to measure allocations-per-parse-call (allocs/op). The parser
increments it at each allocation site via `record_alloc()`.

The counter is gated by the compile-time define `BENCH_ALLOC_COUNT`. When the
define is absent (the production/default build), `ALLOC_COUNT_ENABLED` is False
and every public function's body is elided by a `comptime if` branch — no
branch, no global access, no code is generated. Build with
`-D BENCH_ALLOC_COUNT` to turn the counter on.

The backing storage is a single process-global cell obtained from a named
`pop.global_alloc` instruction inside the `@no_inline` helper `_counter_ptr()`.
Because the helper is never inlined, that instruction exists exactly once in the
binary and resolves to one stable address, so writes from indexer/tape/parser
and reads from the bench all hit the same cell. Single-threaded only (the bench
is single-thread); a plain `Int` cell is sufficient.
"""

from std.memory import UnsafePointer
from std.sys.defines import is_defined

comptime ALLOC_COUNT_ENABLED = is_defined["BENCH_ALLOC_COUNT"]()
"""True when built with `-D BENCH_ALLOC_COUNT`; gates all counter code out otherwise."""

comptime _CounterPtr = UnsafePointer[Int, MutUntrackedOrigin]


@no_inline
def _counter_ptr() -> _CounterPtr:
    """Return a stable pointer to the single process-global counter cell.

    Uses a named `pop.global_alloc` instruction. `@no_inline` guarantees this
    instruction is emitted exactly once, so every call resolves to the same
    address (the cell persists across function and module boundaries). Only ever
    reached when `ALLOC_COUNT_ENABLED` is True.
    """
    var raw = __mlir_op.`pop.global_alloc`[
        name = "jsonette_alloc_counter".value,
        count = __mlir_attr.`1:index`,
        _type = __mlir_type[`!kgen.pointer<`, Int, `>`],
    ]()
    return _CounterPtr(raw)


@always_inline("nodebug")
def record_alloc():
    """Increment the allocation-event counter by 1.

    Compiles to nothing when `ALLOC_COUNT_ENABLED` is False. Call this exactly at
    each heap-allocation site that should contribute to allocs/op.
    """
    comptime if ALLOC_COUNT_ENABLED:
        var p = _counter_ptr()
        p[] += 1


@always_inline("nodebug")
def reset_alloc_count():
    """Set the allocation-event counter to 0.

    Call before a measured parse to zero out prior counts. No-op when
    `ALLOC_COUNT_ENABLED` is False.
    """
    comptime if ALLOC_COUNT_ENABLED:
        _counter_ptr()[] = 0


@always_inline("nodebug")
def get_alloc_count() -> Int:
    """Return the current allocation-event count.

    Returns 0 when `ALLOC_COUNT_ENABLED` is False (the body is elided and never
    touches the global).
    """
    comptime if ALLOC_COUNT_ENABLED:
        return _counter_ptr()[]
    else:
        return 0
