"""Honest Stage-1 vs Stage-2 throughput split for the simdjson-mojo parser.

Methodology:
- Min-time over many iterations (simdjson convention): WARMUP warmups + ITERS timed.
- GB/s = input_bytes / min_iteration_time.
- The padded buffer is built ONCE, outside every timed region.
- Stage 2 is measured on a PRE-BUILT positions list (true stage-2 isolation).
  build_tape appends sentinels to its positions arg, so we truncate the list
  back to its original length each iteration (O(1) length reset, no realloc).
- Full parse is measured two ways:
    (a) Parser.parse(data)  -> public API; re-pads (memcpy+memset+alloc) each call.
    (b) s1+s2 on the pre-padded buffer -> matches the stage-split sum exactly.

Run with -D ASSERT=none for a meaningful profile; compare to -D ASSERT=all.
"""

from std.time import perf_counter_ns
from simdjson.parser import Parser
from simdjson.stage1.indexer import structural_index
from simdjson.stage2.builder import build_tape
from simdjson.tape import Tape


comptime WARMUP: Int = 5
comptime ITERS: Int = 100


def read_file(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


def pad_buffer(data: List[UInt8]) -> List[UInt8]:
    """Build the padded buffer exactly as Parser.parse does (input + 128 zeros)."""
    var input_len = len(data)
    var num_chunks = (input_len + 63) // 64
    var padded_len = num_chunks * 64 + 128
    var padded = List[UInt8](capacity=padded_len)
    for i in range(input_len):
        padded.append(data[i])
    while len(padded) < padded_len:
        padded.append(UInt8(0))
    return padded^


def fmt_gbs(bytes: Int, ns: Int) -> String:
    # bytes/ns == GB/s
    var gbs = Float64(bytes) / Float64(ns)
    return String(gbs)


def fmt_us(ns: Int) -> String:
    return String(Float64(ns) / 1000.0)


def profile(name: String, data: List[UInt8]) raises:
    var size = len(data)
    var padded = pad_buffer(data)
    var sink: UInt64 = 0  # DCE guard: accumulate result bits so work can't be elided

    print("==== " + name + " (" + String(size) + " bytes) ====")

    # --- (a) Full parse via public API (re-pads each call) ---
    var parser = Parser()
    for _ in range(WARMUP):
        var doc = parser.parse(data)
        sink += doc._tape[].elements[0]
    var full_min = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var doc = parser.parse(data)
        var t1 = perf_counter_ns()
        sink += doc._tape[].elements[0]
        var dt = Int(t1 - t0)
        if dt < full_min:
            full_min = dt
    print("  full_parse(API):  min " + fmt_us(full_min) + " us   " + fmt_gbs(size, full_min) + " GB/s")

    # --- (b) Stage 1 only ---
    for _ in range(WARMUP):
        var p = List[UInt32]()
        structural_index(padded, size, p)
        sink += UInt64(len(p))
    var s1_min = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var p = List[UInt32]()
        structural_index(padded, size, p)
        var t1 = perf_counter_ns()
        sink += UInt64(len(p)) + UInt64(p.unsafe_get(0))
        var dt = Int(t1 - t0)
        if dt < s1_min:
            s1_min = dt
    print("  stage1_only:      min " + fmt_us(s1_min) + " us   " + fmt_gbs(size, s1_min) + " GB/s")

    # --- (c) Stage 2 only (pre-built positions; truncate sentinels each iter) ---
    var positions = List[UInt32]()
    structural_index(padded, size, positions)
    var n_struct = len(positions)
    var cs = List[UInt32](capacity=4096)
    var ks = List[UInt32](capacity=1024)
    var tape = Tape()

    for _ in range(WARMUP):
        positions.resize(n_struct, UInt32(0))
        cs.resize(0, UInt32(0))
        ks.resize(0, UInt32(0))
        build_tape(padded, size, positions, cs, ks, tape)
        sink += UInt64(len(tape.elements)) + tape.elements.unsafe_get(0)
    var s2_min = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        positions.resize(n_struct, UInt32(0))
        cs.resize(0, UInt32(0))
        ks.resize(0, UInt32(0))
        var t0 = perf_counter_ns()
        build_tape(padded, size, positions, cs, ks, tape)
        var t1 = perf_counter_ns()
        sink += UInt64(len(tape.elements)) + tape.elements.unsafe_get(0)
        var dt = Int(t1 - t0)
        if dt < s2_min:
            s2_min = dt
    print("  stage2_only:      min " + fmt_us(s2_min) + " us   " + fmt_gbs(size, s2_min) + " GB/s")

    # --- (d) s1+s2 on pre-padded buffer (sum-of-stages full parse, no per-call pad) ---
    for _ in range(WARMUP):
        positions.resize(n_struct, UInt32(0))
        var p = List[UInt32]()
        structural_index(padded, size, p)
        cs.resize(0, UInt32(0))
        ks.resize(0, UInt32(0))
        build_tape(padded, size, p, cs, ks, tape)
        sink += tape.elements.unsafe_get(0)
    var sum_min = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var p = List[UInt32]()
        structural_index(padded, size, p)
        cs.resize(0, UInt32(0))
        ks.resize(0, UInt32(0))
        build_tape(padded, size, p, cs, ks, tape)
        var t1 = perf_counter_ns()
        sink += tape.elements.unsafe_get(0)
        var dt = Int(t1 - t0)
        if dt < sum_min:
            sum_min = dt
    print("  s1+s2(prepadded): min " + fmt_us(sum_min) + " us   " + fmt_gbs(size, sum_min) + " GB/s")

    # --- Split (based on isolated s1 and s2 mins) ---
    var denom = Float64(s1_min + s2_min)
    var s1_pct = Float64(s1_min) / denom * 100.0
    var s2_pct = Float64(s2_min) / denom * 100.0
    print("  structurals: " + String(n_struct))
    print("  split (s1:s2 by isolated min): " + String(s1_pct) + "% : " + String(s2_pct) + "%")
    print("  [sink=" + String(sink) + "]")
    print()


# --- Deterministic synthetic corpora for string vs number attribution ---


def gen_string_heavy(n: Int) raises -> List[UInt8]:
    """Array of objects with string keys + long string values, no numbers."""
    var s = String("[")
    for i in range(n):
        if i > 0:
            s += ","
        s += '{"name":"abcdefghijklmnopqrstuvwxyz","city":"somewhere over there","tag":"loremipsumdolorsitametconsectetur"}'
    s += "]"
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def gen_number_heavy(n: Int) raises -> List[UInt8]:
    """Array of objects with numeric values only, short keys."""
    var s = String("[")
    for i in range(n):
        if i > 0:
            s += ","
        s += '{"a":123456,"b":-98765,"c":3.14159265,"d":1234.5678,"e":42,"f":-0.0001}'
    s += "]"
    var buf = List[UInt8]()
    for b in s.as_bytes():
        buf.append(b)
    return buf^


def main() raises:
    print("simdjson-mojo stage split profile")
    print("WARMUP=" + String(WARMUP) + " ITERS=" + String(ITERS) + " (min-time)")
    print()
    profile(String("twitter.json"), read_file(String("tests/fixtures/corpus/twitter.json")))
    profile(String("canada.json"), read_file(String("tests/fixtures/corpus/canada.json")))
    profile(String("synth_string_heavy"), gen_string_heavy(3000))
    profile(String("synth_number_heavy"), gen_number_heavy(3000))
