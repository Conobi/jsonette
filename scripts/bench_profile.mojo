"""Profile Stage 1 vs Stage 2 parsing time breakdown."""
from std.time import perf_counter_ns
from simdjson.stage1.indexer import structural_index
from simdjson.stage2.builder import build_tape


def read_file(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


def _pad_buffer(data: List[UInt8]) -> List[UInt8]:
    """Create a padded copy: input + 128 zero bytes."""
    var input_len = len(data)
    var num_chunks = (input_len + 63) // 64
    var padded_len = num_chunks * 64 + 128
    var padded = List[UInt8](capacity=padded_len)
    for i in range(input_len):
        padded.append(data[i])
    while len(padded) < padded_len:
        padded.append(UInt8(0))
    return padded^


def profile_file(path: String, name: String) raises:
    var data = read_file(path)
    var size = len(data)
    var padded = _pad_buffer(data)
    print("=== " + name + " (" + String(size) + " bytes) ===")

    comptime WARMUP: Int = 5
    comptime ITERS: Int = 20

    # Warmup both stages
    for _ in range(WARMUP):
        var pos = structural_index(padded, size)
        var tape = build_tape(padded, size, pos)

    # Time Stage 1 alone
    var s1_start = perf_counter_ns()
    for _ in range(ITERS):
        var pos = structural_index(padded, size)
    var s1_end = perf_counter_ns()
    var s1_ns = s1_end - s1_start

    # Get positions for Stage 2 timing
    var positions = structural_index(padded, size)

    # Time Stage 2 alone
    var s2_start = perf_counter_ns()
    for _ in range(ITERS):
        var tape = build_tape(padded, size, positions)
    var s2_end = perf_counter_ns()
    var s2_ns = s2_end - s2_start

    # Time full pipeline
    var full_start = perf_counter_ns()
    for _ in range(ITERS):
        var pos = structural_index(padded, size)
        var tape = build_tape(padded, size, pos)
    var full_end = perf_counter_ns()
    var full_ns = full_end - full_start

    var total_bytes = size * ITERS
    var s1_mbs = Float64(total_bytes) / Float64(s1_ns) * 1000.0
    var s2_mbs = Float64(total_bytes) / Float64(s2_ns) * 1000.0
    var full_mbs = Float64(total_bytes) / Float64(full_ns) * 1000.0
    var s1_pct = Float64(s1_ns) / Float64(full_ns) * 100.0
    var s2_pct = Float64(s2_ns) / Float64(full_ns) * 100.0

    print("  Stage 1 (SIMD index): " + String(s1_ns // 1000000) + " ms  " + String(s1_mbs) + " MB/s  (" + String(s1_pct) + "%)")
    print("  Stage 2 (tape build): " + String(s2_ns // 1000000) + " ms  " + String(s2_mbs) + " MB/s  (" + String(s2_pct) + "%)")
    print("  Full pipeline:        " + String(full_ns // 1000000) + " ms  " + String(full_mbs) + " MB/s")
    print("  Structurals:          " + String(len(positions)))
    print()


def main() raises:
    print("simdjson-mojo Stage Profile (" + String(20) + " iterations)\n")
    profile_file(String("tests/fixtures/corpus/twitter.json"), String("twitter.json"))
    profile_file(String("tests/fixtures/corpus/canada.json"), String("canada.json"))
