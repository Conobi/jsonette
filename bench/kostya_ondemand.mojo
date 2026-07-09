# kostya_ondemand

"""Port of the kostya JSON benchmark to jsonette's On-Demand path.

Companion to ``kostya_dom.mojo`` — same corpus, same self-check, same output
format, but the parse path is jsonette's On-Demand navigator (Stage 1 only, no
tape, leaves parsed lazily as they are read). Mirrors the C++ reference
``test_simdjson.cpp`` (simdjson On-Demand), which is currently the fastest
entry on the kostya table at ~60 ms because it skips ``name`` and ``opts``
entirely — those bytes never leave the input buffer.

Methodology, matched to the C++ reference:

  * Input read into an owned byte buffer OUTSIDE every timed region.
  * Self-check first: both field-order permutations must yield ``Coordinate(2.0,
    0.5, 0.25)`` before any timing runs.
  * Each timed iteration constructs a FRESH ``Reader`` via ``iter(data)`` (Stage
    1 only), navigates ``coordinates`` by array iteration, and reads exactly the
    three floats per element via ``Object.field("x")`` / ``.field("y")`` /
    ``.field("z")``. **Caveat for cross-language interpretation:** simdjson's
    ``ondemand::object::operator[]`` is a persistent forward cursor
    (``find_field_unordered`` resumes from the last position, so in-order x/y/z
    access is effectively one sweep per object), while jsonette's
    ``Object.field(key)`` re-scans from the object's start on every call and
    materialises no key strings. Both jsonette APIs (``field()`` and the
    forward-iteration alternative ``next_field()``) are strictly more work per
    field than simdjson's persistent-cursor lookup — ``field()`` was measured
    to be the faster of the two on this workload, so it's what we use;
    the "same-semantics" On-Demand comparison would need a persistent-cursor
    lookup API in jsonette, which is a future addition, not a bench-side fix.
  * Three passes over the same fresh-parse workload, mirroring
    ``bench/rest.mojo`` and ``kostya_dom.mojo``:

      1. Min-time wall clock (no perf-counter syscalls in the region).
      2. Min cycles / instructions via ``PerfGroup`` (``cyc/B`` and ``ins/B``).
      3. Memory footprint (``mem_base_MiB`` + ``mem_peak_MiB`` +
         ``mem_delta_MiB``) via ``VmHWM`` in ``/proc/self/status``, matched
         across all three implementations.
      4. Optional per-parse allocation count (``allocs/op``) when
         ``-D BENCH_ALLOC_COUNT`` is set (jsonette-only detail).

  * We report the FIRST iteration's wall time (directly comparable to kostya's
    per-iteration median) plus a min-time across ``ITERS`` iterations. An O(1)
    sink prevents DCE.

Build and run:

    uv run -- python3 scripts/gen_kostya_json.py                        # once per host
    uv run -- mojo run -I . -D ASSERT=none bench/kostya_ondemand.mojo    # wall-clock + perf
    uv run -- mojo run -I . -D ASSERT=none -D BENCH_ALLOC_COUNT \
        bench/kostya_ondemand.mojo                                       # + allocs/op
"""

from std.time import perf_counter_ns
from jsonette.ondemand.reader import iter
from jsonette._alloc_count import (
    reset_alloc_count,
    get_alloc_count,
    ALLOC_COUNT_ENABLED,
)

from bench._metrics import PerfGroup, vm_hwm_kb


comptime WARMUP: Int = 3
comptime ITERS: Int = 10


struct Coordinate(Copyable, Movable):
    """The (x, y, z) mean the benchmark computes, matched to the reference schema."""

    var x: Float64
    var y: Float64
    var z: Float64

    def __init__(out self, x: Float64, y: Float64, z: Float64):
        """Store the three components verbatim (no scaling, no defaults)."""
        self.x = x
        self.y = y
        self.z = z

    def approx_eq(self, other: Coordinate, tol: Float64 = 1e-12) -> Bool:
        """True iff each component is within ``tol`` of ``other``'s (float parity check)."""
        return (
            abs(self.x - other.x) <= tol
            and abs(self.y - other.y) <= tol
            and abs(self.z - other.z) <= tol
        )


def read_file(path: String) raises -> List[UInt8]:
    """Slurp a file into an owned byte buffer (untimed by contract)."""
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


def fmt_f(x: Float64, decimals: Int) -> String:
    """Round-half-up fixed-point float formatting (no scientific notation).

    Mirrors ``bench/rest.mojo``'s ``fmt_f`` so a number formatted here is
    directly comparable to one from the REST bench (the previous byte-slice
    implementation truncated instead of rounding). Assumes ``x >= 0`` and a
    magnitude below the scientific-notation threshold; every current call
    site (sizes, times, MB/s, cyc/B, ins/B) satisfies both.
    """
    var scale = 1
    for _ in range(decimals):
        scale *= 10
    var scaled = Int(x * Float64(scale) + 0.5)
    var whole = scaled // scale
    var frac = scaled % scale
    var fs = String(frac)
    while fs.byte_length() < decimals:
        fs = "0" + fs
    if decimals == 0:
        return String(whole)
    return String(whole) + "." + fs


def calc(data: List[UInt8]) raises -> Coordinate:
    """Run Stage 1 fresh, walk ``coordinates`` lazily, return the mean coordinate.

    This is the timed region: ``iter`` runs the structural indexer (no tape),
    then the walk visits each coordinate object and looks up three floats per
    element by name. ``name`` and ``opts`` are never accessed and therefore
    never materialised — that is the point of On-Demand access. See the module
    docstring for how this compares to simdjson's persistent-cursor lookup.
    """
    var reader = iter(data)
    var arr = reader.root().field("coordinates").get_array()
    var x = 0.0
    var y = 0.0
    var z = 0.0
    var count = 0
    while not arr.at_end():
        var coord = arr.next_element()
        var obj = coord.get_object()
        x += obj.field("x").get_float()
        y += obj.field("y").get_float()
        z += obj.field("z").get_float()
        count += 1
    var n = Float64(count)
    return Coordinate(x / n, y / n, z / n)


def selfcheck() raises:
    """Run the two-string schema self-check the reference tests use.

    Both permutations of the field order (``x,y,z`` and ``y,x,z``) must yield
    ``Coordinate(2.0, 0.5, 0.25)`` — the parity gate before we time anything.
    """
    var want = Coordinate(2.0, 0.5, 0.25)
    var cases = List[String]()
    cases.append(String('{"coordinates":[{"x":2.0,"y":0.5,"z":0.25}]}'))
    cases.append(String('{"coordinates":[{"y":0.5,"x":2.0,"z":0.25}]}'))
    for ref s in cases:
        var buf = List[UInt8]()
        for b in s.as_bytes():
            buf.append(b)
        var got = calc(buf)
        if not got.approx_eq(want):
            raise "selfcheck failed: expected (2.0, 0.5, 0.25), got (" \
                + String(got.x) + ", " + String(got.y) + ", " + String(got.z) + ")"


def main() raises:
    """Run selfcheck, then time the On-Demand walk on ``/tmp/1.json``.

    Prints the ``Coordinate(x=..., y=..., z=...)`` line followed by the metric
    block: wall-clock (``first_time_s`` / ``min_time_s``), ``MB/s`` / ``ns/op``
    for cross-language comparison, and — when perf counters are open —
    ``cyc/B`` / ``ins/B`` plus ``allocs/op`` (the latter only reflects the real
    fresh-parse cost when built with ``-D BENCH_ALLOC_COUNT``).
    """
    selfcheck()
    var perf = PerfGroup()
    perf.open()
    var path = String("/tmp/1.json")
    var data = read_file(path)
    var size = len(data)
    print(
        "kostya On-Demand  size=" + fmt_f(Float64(size) / (1024.0 * 1024.0), 2)
        + " MiB  WARMUP=" + String(WARMUP) + "  ITERS=" + String(ITERS)
        + "  perf=" + String(perf.available)
        + "  alloc_count=" + String(ALLOC_COUNT_ENABLED)
    )

    # Baseline RSS captured AFTER file load + self-check, BEFORE any timed
    # work — matches kostya's ``base + increase`` methodology.
    var mem_base_kib = vm_hwm_kb()

    var first_ns: Int = 0
    var min_ns = Int(0x7FFFFFFFFFFFFFFF)
    var sink: Float64 = 0.0
    var result = Coordinate(0.0, 0.0, 0.0)

    for _ in range(WARMUP):
        var r = calc(data)
        sink += r.x + r.y + r.z

    # Pass 1 — min-time wall clock (no counter syscalls in the region).
    for i in range(ITERS):
        var t0 = perf_counter_ns()
        var r = calc(data)
        var t1 = perf_counter_ns()
        var dt = Int(t1 - t0)
        if i == 0:
            first_ns = dt
            result = r.copy()
        if dt < min_ns:
            min_ns = dt
        sink += r.x + r.y + r.z

    # Pass 2 — min cycles / instructions (separate so ioctl/read don't pollute P1).
    var best_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    var best_ins = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            perf.reset()
            perf.enable()
            var r = calc(data)
            perf.disable()
            sink += r.x + r.y + r.z
            var c = perf.cycles()
            var i = perf.instructions()
            if c < best_cyc:
                best_cyc = c
            if i < best_ins:
                best_ins = i

    # Pass 3 — allocs/op from one fresh call (deterministic per parse).
    reset_alloc_count()
    var alloc_run = calc(data)
    sink += alloc_run.x + alloc_run.y + alloc_run.z
    var allocs = get_alloc_count()

    print(
        "Coordinate(x=" + String(result.x) + ", y=" + String(result.y)
        + ", z=" + String(result.z) + ")"
    )
    var first_s = Float64(first_ns) / 1.0e9
    var min_s = Float64(min_ns) / 1.0e9
    var mbs = Float64(size) / (Float64(min_ns) / 1.0e9) / 1.0e6
    print("first_time_s=" + fmt_f(first_s, 6))
    print("min_time_s=" + fmt_f(min_s, 6))
    print("MB/s=" + fmt_f(mbs, 1))
    print("ns/op=" + String(min_ns))
    if perf.available:
        var cyc_b = Float64(best_cyc) / Float64(size)
        var ins_b = Float64(best_ins) / Float64(size)
        print("cyc/B=" + fmt_f(cyc_b, 2))
        print("ins/B=" + fmt_f(ins_b, 2))
    else:
        print("cyc/B=n/a")
        print("ins/B=n/a")
    var mem_peak_kib = vm_hwm_kb()
    print("mem_base_MiB=" + fmt_f(Float64(mem_base_kib) / 1024.0, 1))
    print("mem_peak_MiB=" + fmt_f(Float64(mem_peak_kib) / 1024.0, 1))
    var mem_delta_kib = mem_peak_kib - mem_base_kib
    if mem_delta_kib < 0:
        mem_delta_kib = 0
    print("mem_delta_MiB=" + fmt_f(Float64(mem_delta_kib) / 1024.0, 1))
    # Opt-in per-parse allocation count (comptime-gated to keep the counter
    # out of the wall-clock and cyc/B numbers when it's not asked for). C++
    # and Rust have no equivalent hook, so this row is jsonette-only.
    if ALLOC_COUNT_ENABLED:
        print("allocs/op=" + String(allocs))
    print("sink=" + String(sink))
    perf.close()
