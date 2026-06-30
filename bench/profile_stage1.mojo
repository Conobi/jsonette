"""Stage-1 internal profile: classify (SIMD) vs emit (scalar bit-scatter).

Decision bench for whether a branchless structural-index extraction is worth
prototyping. Splits each parse into:

  * full(API)        — Parser.parse (re-pads each call)
  * stage1_full      — structural_index (classify + emit + compaction)
  * stage1_classify  — the indexer loop MINUS the emit/compaction (DCE-guarded
                       by XOR-accumulating the per-chunk structurals bitmask)
  * stage2           — build_tape on a pre-built positions list

`emit` cost is derived as stage1_full - stage1_classify (the scalar tzcnt/blsr
bit-scatter + the <input_len compaction filter). Reports min-time ns + GB/s and
min hardware cyc/byte (PerfGroup) for each phase.

Run:  uv run -- mojo run -I . -D ASSERT=none bench/profile_stage1.mojo
"""

from std.time import perf_counter_ns
from jsonette.parser import Parser
from jsonette.stage1.indexer import structural_index
from jsonette.stage1.simd_ops import SimdInput
from jsonette.stage1.classifier import classify
from jsonette.stage1.string_mask import EscapeScanner, StringScanner
from jsonette.stage2.builder import build_tape
from jsonette.tape import Tape
from bench._metrics import PerfGroup


comptime WARMUP: Int = 20
comptime ITERS: Int = 200


def read_file(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


def pad_buffer(data: List[UInt8]) -> List[UInt8]:
    var input_len = len(data)
    var num_chunks = (input_len + 63) // 64
    var padded_len = num_chunks * 64 + 128
    var padded = List[UInt8](capacity=padded_len)
    for i in range(input_len):
        padded.append(data[i])
    while len(padded) < padded_len:
        padded.append(UInt8(0))
    return padded^


def stage1_classify_only(padded: List[UInt8], input_len: Int) -> UInt64:
    """Run the stage-1 inner loop WITHOUT emit/compaction; return a DCE sink.

    Mirrors indexer.structural_index's per-chunk body exactly, replacing the
    `emit(...)` bit-scatter with `sink ^= structurals`. Isolates the SIMD
    classification + bitmask logic from the scalar structural-index extraction.
    """
    if input_len == 0:
        return 0
    var num_chunks = (input_len + 63) // 64
    var escape_scanner = EscapeScanner()
    var string_scanner = StringScanner()
    var prev_scalar_carry: UInt64 = 0
    var ptr = padded.unsafe_ptr()
    var sink: UInt64 = 0
    for chunk_idx in range(num_chunks):
        var base_idx = chunk_idx * 64
        var input = SimdInput.load(ptr + base_idx)
        var block = classify(input)
        var backslash = input.eq(UInt8(0x5C))
        var all_quotes = input.eq(UInt8(0x22))
        var escaped = escape_scanner.next(backslash)
        var in_string = string_scanner.next(all_quotes, escaped)
        var real_quotes = all_quotes & ~escaped
        var structural_ops = (block.op & ~in_string) | real_quotes
        var scalar = ~(block.whitespace | block.op | real_quotes | in_string)
        var scalar_start = scalar & ~((scalar << 1) | prev_scalar_carry)
        var structurals = structural_ops | scalar_start
        sink ^= structurals
        prev_scalar_carry = (scalar >> 63) & 1
    return sink


def f3(x: Float64) -> String:
    var scaled = Int(x * 1000.0 + 0.5)
    var w = scaled // 1000
    var fr = scaled % 1000
    var fs = String(fr)
    while fs.byte_length() < 3:
        fs = "0" + fs
    return String(w) + "." + fs


def row(label: String, size: Int, ns: Int, cyc: UInt64) -> String:
    var gbs = Float64(size) / Float64(ns)
    var cb = Float64(cyc) / Float64(size)
    var s = label
    while s.byte_length() < 18:
        s += " "
    return (
        s + "min " + f3(Float64(ns) / 1000.0) + " us   "
        + f3(gbs) + " GB/s   " + f3(cb) + " cyc/B"
    )


def profile(name: String, data: List[UInt8], mut perf: PerfGroup) raises:
    var size = len(data)
    var padded = pad_buffer(data)
    var sink: UInt64 = 0
    print("==== " + name + " (" + String(size) + " bytes) ====")

    # --- full parse via public API ---
    var parser = Parser()
    for _ in range(WARMUP):
        sink += parser.parse(data)._tape[].elements[0]
    var full_ns = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var d = parser.parse(data)
        var t1 = perf_counter_ns()
        sink += d._tape[].elements[0]
        if Int(t1 - t0) < full_ns:
            full_ns = Int(t1 - t0)
    var full_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            perf.reset(); perf.enable()
            var d = parser.parse(data)
            perf.disable()
            sink += d._tape[].elements[0]
            if perf.cycles() < full_cyc:
                full_cyc = perf.cycles()

    # --- stage 1 full ---
    for _ in range(WARMUP):
        var p = List[UInt32]()
        structural_index(padded, size, p)
        sink += UInt64(len(p))
    var s1_ns = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var p = List[UInt32]()
        var t0 = perf_counter_ns()
        structural_index(padded, size, p)
        var t1 = perf_counter_ns()
        sink += UInt64(len(p))
        if Int(t1 - t0) < s1_ns:
            s1_ns = Int(t1 - t0)
    var s1_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            var p = List[UInt32]()
            perf.reset(); perf.enable()
            structural_index(padded, size, p)
            perf.disable()
            sink += UInt64(len(p))
            if perf.cycles() < s1_cyc:
                s1_cyc = perf.cycles()

    # --- stage 1 classify-only (no emit) ---
    for _ in range(WARMUP):
        sink += stage1_classify_only(padded, size)
    var cl_ns = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var s = stage1_classify_only(padded, size)
        var t1 = perf_counter_ns()
        sink += s
        if Int(t1 - t0) < cl_ns:
            cl_ns = Int(t1 - t0)
    var cl_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            perf.reset(); perf.enable()
            var s = stage1_classify_only(padded, size)
            perf.disable()
            sink += s
            if perf.cycles() < cl_cyc:
                cl_cyc = perf.cycles()

    # --- stage 2 (pre-built positions) ---
    var positions = List[UInt32]()
    structural_index(padded, size, positions)
    var n_struct = len(positions)
    var cs = List[UInt32](capacity=4096)
    var tape = Tape()
    for _ in range(WARMUP):
        positions.resize(n_struct, UInt32(0)); cs.resize(0, UInt32(0))
        build_tape(padded, size, positions, cs, tape)
        sink += tape.elements.unsafe_get(0)
    var s2_ns = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        positions.resize(n_struct, UInt32(0)); cs.resize(0, UInt32(0))
        var t0 = perf_counter_ns()
        build_tape(padded, size, positions, cs, tape)
        var t1 = perf_counter_ns()
        sink += tape.elements.unsafe_get(0)
        if Int(t1 - t0) < s2_ns:
            s2_ns = Int(t1 - t0)
    var s2_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            positions.resize(n_struct, UInt32(0)); cs.resize(0, UInt32(0))
            perf.reset(); perf.enable()
            build_tape(padded, size, positions, cs, tape)
            perf.disable()
            sink += tape.elements.unsafe_get(0)
            if perf.cycles() < s2_cyc:
                s2_cyc = perf.cycles()

    # --- derived emit = s1_full - classify ---
    var emit_ns = s1_ns - cl_ns
    var emit_cyc = s1_cyc - cl_cyc if perf.available else UInt64(0)

    print("  " + row("full(API):", size, full_ns, full_cyc))
    print("  " + row("stage1_full:", size, s1_ns, s1_cyc))
    print("  " + row("  classify:", size, cl_ns, cl_cyc))
    print("  " + row("  emit(derived):", size, emit_ns if emit_ns > 0 else 1, emit_cyc))
    print("  " + row("stage2:", size, s2_ns, s2_cyc))
    print("  structurals: " + String(n_struct)
        + "   emit cyc/struct: " + (f3(Float64(emit_cyc) / Float64(n_struct)) if perf.available and n_struct > 0 else "n/a"))
    if perf.available:
        var s1c = Float64(s1_cyc)
        print("  within stage1 (cyc): classify " + f3(Float64(cl_cyc) / s1c * 100.0)
            + "%  emit " + f3(Float64(emit_cyc) / s1c * 100.0) + "%")
        var tot = Float64(s1_cyc + s2_cyc)
        print("  s1:s2 (cyc): " + f3(Float64(s1_cyc) / tot * 100.0)
            + "% : " + f3(Float64(s2_cyc) / tot * 100.0) + "%")
    print("  [sink=" + String(sink) + "]")
    print()


def main() raises:
    var perf = PerfGroup()
    perf.open()
    print("stage-1 internal profile  WARMUP=" + String(WARMUP)
        + " ITERS=" + String(ITERS) + " (min)  perf=" + String(perf.available))
    print()
    profile(String("twitter.json"), read_file(String("tests/fixtures/corpus/twitter.json")), perf)
    profile(String("citm_catalog.json"), read_file(String("tests/fixtures/corpus/citm_catalog.json")), perf)
    profile(String("canada.json"), read_file(String("tests/fixtures/corpus/canada.json")), perf)
    profile(String("github_events.json"), read_file(String("tests/fixtures/corpus/github_events.json")), perf)
    perf.close()
