"""REST-workload decode benchmark for the simdjson-mojo parser.

Models a web server that reuses ONE parser across many request/response
documents: most payloads are small-to-medium and object-heavy, so per-call
fixed overhead — not steady-state GB/s — dominates. The harness therefore
reports, per corpus file:

  * GB/s        — throughput (bytes / min parse time)
  * ns/op       — per-document latency (the figure a server cares about)
  * docs/s      — documents parsed per second (1e9 / ns/op)
  * cyc/byte    — CPU cycles per input byte (hardware-independent efficiency)
  * ins/byte    — retired instructions per input byte
  * allocs/op   — heap allocations per warm parse call (server memory churn)
  * peak RSS    — whole-run peak resident memory (printed once at the end)

Methodology (simdjson convention):
  * One `Parser` is reused across all iterations (server semantics; the padded
    input buffer is amortised after warmup).
  * Each file is read into memory ONCE, outside every timed region.
  * Min-time over `ITERS` iterations after `WARMUP` warmups.
  * Timing and perf-counter passes are SEPARATE so the counter syscalls
    (ioctl/read) never pollute the wall-clock measurement.
  * `allocs/op` is deterministic per call, so it is read from a single warm
    parse rather than timed.

Builds and runs:
  * Throughput + perf + latency (counter compiled out, zero overhead):
        uv run -- mojo run -I . -D ASSERT=none bench/rest.mojo
  * Same, plus real allocs/op (counter compiled in):
        uv run -- mojo run -I . -D ASSERT=none -D BENCH_ALLOC_COUNT bench/rest.mojo
  Without `-D BENCH_ALLOC_COUNT` the allocs/op column reads 0 (a reminder to
  rerun with the flag). cyc/byte and ins/byte read "n/a" where perf_event_open
  is unavailable (e.g. a locked-down host); use the fixed-freq bench VPS.
"""

from std.time import perf_counter_ns
from simdjson.parser import Parser
from simdjson._alloc_count import (
    reset_alloc_count,
    get_alloc_count,
    ALLOC_COUNT_ENABLED,
)

from bench._metrics import PerfGroup, peak_rss_kb, vm_hwm_kb


comptime WARMUP: Int = 20
comptime ITERS: Int = 200
comptime CORPUS = "tests/fixtures/corpus/"


def corpus_files() -> List[String]:
    """REST-shaped corpus, small -> large.

    Synthetic list responses probe the per-call latency floor; the rest are
    real API / config payloads representative of REST traffic.
    """
    var files = List[String]()
    files.append(String("rest_small.json"))
    files.append(String("rest_medium.json"))
    files.append(String("rest_large.json"))
    files.append(String("github_events.json"))
    files.append(String("apache_builds.json"))
    files.append(String("instruments.json"))
    files.append(String("update-center.json"))
    files.append(String("twitter.json"))
    files.append(String("citm_catalog.json"))
    return files^


def read_file(path: String) raises -> List[UInt8]:
    """Read a file into an owned byte buffer."""
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


def fmt_f(x: Float64, decimals: Int) -> String:
    """Format a non-negative float to a fixed number of decimal places."""
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


def lpad(s: String, w: Int) -> String:
    """Right-justify `s` to width `w` for tabular numeric columns."""
    var out = s
    while out.byte_length() < w:
        out = " " + out
    return out


def rpad(s: String, w: Int) -> String:
    """Left-justify `s` to width `w` for the file-name column."""
    var out = s
    while out.byte_length() < w:
        out = out + " "
    return out


def bench(name: String, data: List[UInt8], mut perf: PerfGroup) raises -> UInt64:
    """Benchmark one document; print a metrics row; return a DCE sink value.

    Reuses a fresh warm `Parser` (server semantics). Runs three passes over the
    same parser: a min-time wall-clock pass, a min-cycles/instructions perf pass
    (skipped if perf is unavailable), and a single warm parse to read allocs/op.

    Args:
        name: Corpus file name (for the row label).
        data: The document bytes, already loaded.
        perf: An opened (or unavailable) perf counter group.

    Returns:
        An accumulated sink value to keep the parses from being optimised away.
    """
    var size = len(data)
    var parser = Parser()
    var sink: UInt64 = 0

    # Warmup: amortise the padded buffer and warm caches/branch predictors.
    for _ in range(WARMUP):
        var doc = parser.parse(data)
        sink += doc._tape[].elements[0]

    # Pass 1 — min-time wall clock (no counter syscalls in the region).
    var best_ns = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var doc = parser.parse(data)
        var t1 = perf_counter_ns()
        sink += doc._tape[].elements[0]
        var dt = Int(t1 - t0)
        if dt < best_ns:
            best_ns = dt

    # Pass 2 — min cycles / instructions (separate so syscalls don't pollute P1).
    var best_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    var best_ins = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            perf.reset()
            perf.enable()
            var doc = parser.parse(data)
            perf.disable()
            sink += doc._tape[].elements[0]
            var c = perf.cycles()
            var i = perf.instructions()
            if c < best_cyc:
                best_cyc = c
            if i < best_ins:
                best_ins = i

    # Pass 3 — allocs/op from a single warm parse (deterministic per call).
    reset_alloc_count()
    var doc = parser.parse(data)
    sink += doc._tape[].elements[0]
    var allocs = get_alloc_count()

    # Derived metrics.
    var gbs = Float64(size) / Float64(best_ns)  # bytes/ns == GB/s
    var docs_s = 1.0e9 / Float64(best_ns)
    var cyc_b = String("n/a")
    var ins_b = String("n/a")
    if perf.available:
        cyc_b = fmt_f(Float64(best_cyc) / Float64(size), 2)
        ins_b = fmt_f(Float64(best_ins) / Float64(size), 2)

    print(
        rpad(name, 20)
        + lpad(String(size), 9)
        + lpad(fmt_f(gbs, 3), 9)
        + lpad(String(best_ns), 10)
        + lpad(String(Int(docs_s)), 10)
        + lpad(cyc_b, 9)
        + lpad(ins_b, 9)
        + lpad(String(allocs), 7)
    )
    return sink


def main() raises:
    """Run the REST decode benchmark over the corpus and print a table."""
    var perf = PerfGroup()
    perf.open()
    print(
        "REST decode bench  WARMUP=" + String(WARMUP) + " ITERS="
        + String(ITERS) + " (min-time)  perf=" + String(perf.available)
    )
    print(
        rpad("file", 20) + lpad("bytes", 9) + lpad("GB/s", 9)
        + lpad("ns/op", 10) + lpad("docs/s", 10) + lpad("cyc/B", 9)
        + lpad("ins/B", 9) + lpad("alloc", 7)
    )

    var sink: UInt64 = 0
    var files = corpus_files()
    for ref f in files:
        sink += bench(f, read_file(String(CORPUS) + f), perf)

    perf.close()
    print(
        "peak RSS: " + fmt_f(Float64(peak_rss_kb()) / 1024.0, 1) + " MB"
        + "  (VmHWM " + fmt_f(Float64(vm_hwm_kb()) / 1024.0, 1) + " MB)"
        + "  [sink=" + String(sink) + "]"
    )
    comptime if not ALLOC_COUNT_ENABLED:
        print(
            "note: allocs/op shows 0 (counter disabled) — rebuild with"
            + " -D BENCH_ALLOC_COUNT to measure per-call allocations"
        )
