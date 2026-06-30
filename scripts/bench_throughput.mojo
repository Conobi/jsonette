from std.time import perf_counter_ns
from jsonette.document import parse


def read_file(path: String) raises -> List[UInt8]:
    """Read a file into a List[UInt8]."""
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


def bench_file(path: String, name: String) raises:
    """Benchmark parsing a single file."""
    var data = read_file(path)
    var size = len(data)
    print("Benchmarking:", name, "(", size, "bytes )")

    # Cold parse once (allocates the buffers); the warmup + measured loops
    # reuse them via `reparse` (the warm, steady-state throughput path).
    var doc = parse(data)

    # Warmup
    for _ in range(5):
        doc.reparse(data)

    # Measured iterations
    comptime ITERATIONS: Int = 20
    var start = perf_counter_ns()
    for _ in range(ITERATIONS):
        doc.reparse(data)
    var end = perf_counter_ns()

    var elapsed_ns = end - start
    var total_bytes = size * ITERATIONS
    # bytes/ns = GB/s; * 1000 = MB/s
    var mb_per_sec = Float64(total_bytes) / Float64(elapsed_ns) * 1000.0
    print("  Iterations:", ITERATIONS)
    print("  Total time:", elapsed_ns // 1000000, "ms")
    print("  Throughput:", mb_per_sec, "MB/s")
    print()


def main() raises:
    print("=== jsonette Throughput Benchmark ===")
    print()
    bench_file(String("tests/fixtures/corpus/twitter.json"), String("twitter.json"))
    bench_file(String("tests/fixtures/corpus/canada.json"), String("canada.json"))
