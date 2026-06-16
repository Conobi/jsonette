"""Head-to-head full-parse bench — THEIRS (ehsanmok/json native CPU parser).

Mirror of `h2h_ours.mojo` with byte-identical methodology. Targets the
PURE-MOJO two-pass parser `parse_cpu_native_tape` (what `loads[target="cpu"]`
dispatches to) — NOT the `cpu-simdjson` C++ FFI shim and NOT the GPU path —
so this is a Mojo-vs-Mojo comparison.

`parse_cpu_native_tape` consumes an owned `String` (it moves the input into
the Document for zero-copy string views), so each repeated call is handed
`content.copy()`. That per-call copy mirrors our per-call padded-buffer
memcpy: both marshal the whole document once per parse.

O(1) DCE sink: `Int(v.is_object())` (a single tape-tag read at the root).

Compile/run with `-I . -I <ehsanmok-json-dir> -D ASSERT=none`.
"""

from std.time import perf_counter_ns
from json.cpu import parse_cpu_native_tape


comptime WARMUP: Int = 10
comptime ITERS: Int = 200


def read_text(path: String) raises -> String:
    var f = open(path, "r")
    var content = f.read()
    f.close()
    return content^


def fmt_gbs(bytes: Int, ns: Int) -> String:
    return String(Float64(bytes) / Float64(ns))  # bytes/ns == GB/s


def fmt_us(ns: Int) -> String:
    return String(Float64(ns) / 1000.0)


def bench(name: String, content: String) raises:
    var size = content.byte_length()
    var sink: UInt64 = 0
    for _ in range(WARMUP):
        var v = parse_cpu_native_tape(content.copy())
        sink += UInt64(1) if v.is_object() else UInt64(0)
    var best = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var v = parse_cpu_native_tape(content.copy())
        var t1 = perf_counter_ns()
        sink += UInt64(1) if v.is_object() else UInt64(0)
        var dt = Int(t1 - t0)
        if dt < best:
            best = dt
    print(
        "  theirs " + name + ": " + String(size) + " bytes  min "
        + fmt_us(best) + " us  " + fmt_gbs(size, best)
        + " GB/s  [sink=" + String(sink) + "]"
    )


def main() raises:
    print(
        "THEIRS (ehsanmok/json native CPU) full-parse  WARMUP=" + String(WARMUP)
        + " ITERS=" + String(ITERS) + " (min-time)"
    )
    var twitter = read_text(String("tests/fixtures/corpus/twitter.json"))
    var canada = read_text(String("tests/fixtures/corpus/canada.json"))
    bench(String("twitter"), twitter)
    bench(String("canada"), canada)
