"""Head-to-head full-parse bench — OURS (jsonette).

Mirror of `h2h_theirs.mojo` (ehsanmok/json native CPU parser) with
byte-identical methodology so the two min-time numbers are directly
comparable:

  * WARMUP=10, ITERS=200, min-time over iterations (simdjson convention).
  * Input read ONCE outside every timed region.
  * One input-copy charged per parse call: ours copies the input into
    the reused padded buffer inside `Parser.parse`; theirs copies the
    owned `String` it consumes. Both marshal the whole document once
    per call, so the comparison is apples-to-apples.
  * O(1) DCE sink (`doc._tape[].elements[0]`), printed at the end.

Run with -D ASSERT=none on the fixed-freq bench VPS.
"""

from std.time import perf_counter_ns
from jsonette.parser import Parser


comptime WARMUP: Int = 10
comptime ITERS: Int = 200


def read_file(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


def fmt_gbs(bytes: Int, ns: Int) -> String:
    return String(Float64(bytes) / Float64(ns))  # bytes/ns == GB/s


def fmt_us(ns: Int) -> String:
    return String(Float64(ns) / 1000.0)


def bench(name: String, data: List[UInt8]) raises:
    var size = len(data)
    var parser = Parser()
    var sink: UInt64 = 0
    for _ in range(WARMUP):
        var doc = parser.parse(data)
        sink += doc._tape[].elements[0]
    var best = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var doc = parser.parse(data)
        var t1 = perf_counter_ns()
        sink += doc._tape[].elements[0]
        var dt = Int(t1 - t0)
        if dt < best:
            best = dt
    print(
        "  ours " + name + ": " + String(size) + " bytes  min "
        + fmt_us(best) + " us  " + fmt_gbs(size, best)
        + " GB/s  [sink=" + String(sink) + "]"
    )


def main() raises:
    print(
        "OURS (jsonette) full-parse  WARMUP=" + String(WARMUP)
        + " ITERS=" + String(ITERS) + " (min-time)"
    )
    var twitter = read_file(String("tests/fixtures/corpus/twitter.json"))
    var canada = read_file(String("tests/fixtures/corpus/canada.json"))
    bench(String("twitter"), twitter)
    bench(String("canada"), canada)
