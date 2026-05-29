"""Number-parsing throughput bench for VPS speed gates (NFR-2 / NFR-3).

Two measurements, min-time over many iterations (simdjson convention), input
built ONCE outside every timed region, results accumulated into a printed sink
(DCE guard):

  (1) full_parse  — Parser.parse(data) on twitter.json + canada.json. The
      NFR-2 "no regression" signal for the whole pipeline (also captures the
      Parser padded-buffer reuse).
  (2) number_isolation — extract every number token from canada.json into a
      NUL-padded scratch buffer, then time _parse_number over all tokens. The
      NFR-3 signal: did the float/integer number path get faster?

Run with -D ASSERT=none. On the bench VPS (fixed-freq, no turbo) wall-clock
min-time is trustworthy; perf counters are not required.
"""

from std.time import perf_counter_ns
from simdjson.parser import Parser
from simdjson.stage2.numbers import _parse_number


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


def _is_num_start(b: UInt8) -> Bool:
    return b == UInt8(0x2D) or (b >= UInt8(0x30) and b <= UInt8(0x39))  # '-' or 0-9


def _is_num_char(b: UInt8) -> Bool:
    # digit, '-', '+', '.', 'e', 'E'
    return (
        (b >= UInt8(0x30) and b <= UInt8(0x39))
        or b == UInt8(0x2D)
        or b == UInt8(0x2B)
        or b == UInt8(0x2E)
        or b == UInt8(0x65)
        or b == UInt8(0x45)
    )


def bench_full_parse(name: String, data: List[UInt8]) raises:
    var size = len(data)
    var parser = Parser()
    var sink: UInt64 = 0
    for _ in range(WARMUP):
        var doc = parser.parse(data)
        sink += doc.tape.elements[0]
    var best = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var doc = parser.parse(data)
        var t1 = perf_counter_ns()
        sink += doc.tape.elements[0]
        var dt = Int(t1 - t0)
        if dt < best:
            best = dt
    print(
        "  full_parse " + name + ": " + String(size) + " bytes  min "
        + fmt_us(best) + " us  " + fmt_gbs(size, best) + " GB/s  [sink=" + String(sink) + "]"
    )


def bench_numbers(name: String, data: List[UInt8]) raises:
    # Extract maximal number tokens into a NUL-padded scratch buffer.
    var n = len(data)
    var big = List[UInt8]()
    var starts = List[Int]()
    var lens = List[Int]()
    var i = 0
    while i < n:
        var b = data[i]
        if _is_num_start(b) and (i == 0 or not _is_num_char(data[i - 1])):
            var j = i
            while j < n and _is_num_char(data[j]):
                j += 1
            var off = len(big)
            for k in range(i, j):
                big.append(data[k])
            for _ in range(16):  # >=8 NUL padding per token for the SWAR over-read
                big.append(UInt8(0))
            starts.append(off)
            lens.append(j - i)
            i = j
        else:
            i += 1

    var ntok = len(starts)
    var ptr = big.unsafe_ptr()
    var num_bytes = 0
    for t in range(ntok):
        num_bytes += lens[t]

    var sink: UInt64 = 0
    for _ in range(WARMUP):
        for t in range(ntok):
            var r = _parse_number(ptr + starts[t], lens[t])
            sink += r.value
    var best = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        for t in range(ntok):
            var r = _parse_number(ptr + starts[t], lens[t])
            sink += r.value
        var t1 = perf_counter_ns()
        var dt = Int(t1 - t0)
        if dt < best:
            best = dt

    var ns_per_tok = Float64(best) / Float64(ntok)
    print(
        "  numbers " + name + ": " + String(ntok) + " tokens, " + String(num_bytes)
        + " number-bytes  min " + fmt_us(best) + " us  " + String(ns_per_tok)
        + " ns/token  " + fmt_gbs(num_bytes, best) + " GB/s  [sink=" + String(sink) + "]"
    )


def main() raises:
    print("simdjson-mojo number bench  WARMUP=" + String(WARMUP) + " ITERS=" + String(ITERS) + " (min-time)")
    var twitter = read_file(String("tests/fixtures/corpus/twitter.json"))
    var canada = read_file(String("tests/fixtures/corpus/canada.json"))
    print("== full parse (NFR-2 no-regression) ==")
    bench_full_parse(String("twitter"), twitter)
    bench_full_parse(String("canada"), canada)
    print("== number isolation (NFR-3 speed) ==")
    bench_numbers(String("canada"), canada)
