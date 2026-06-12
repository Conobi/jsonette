"""Isolated A/B of the stage-1 `emit` bit-scatter: per-bit loop vs unconditional-8.

Both scatter variants run in ONE binary over the SAME precomputed per-chunk
structurals bitmasks (real twitter/citm/canada), into the same output buffer —
a clean same-conditions A/B that isolates exactly the emit cost. Reports min-time
ns and min hardware cyc per full scatter pass, plus cyc/structural.

Run:  uv run -- mojo run -I . -D ASSERT=none bench/profile_emit.mojo
"""

from std.time import perf_counter_ns
from std.bit import count_trailing_zeros, pop_count
from jsonette.stage1.simd_ops import SimdInput
from jsonette.stage1.classifier import classify
from jsonette.stage1.string_mask import EscapeScanner, StringScanner
from bench._metrics import PerfGroup


comptime WARMUP: Int = 20
comptime ITERS: Int = 300


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
    var padded = List[UInt8](capacity=num_chunks * 64 + 128)
    for i in range(input_len):
        padded.append(data[i])
    while len(padded) < num_chunks * 64 + 128:
        padded.append(UInt8(0))
    return padded^


def collect(padded: List[UInt8], input_len: Int, mut masks: List[UInt64], mut bases: List[UInt32]):
    """Run the real stage-1 classify loop; append each chunk's structurals + base."""
    var num_chunks = (input_len + 63) // 64
    var es = EscapeScanner()
    var ss = StringScanner()
    var prev_scalar_carry: UInt64 = 0
    var ptr = padded.unsafe_ptr()
    for chunk_idx in range(num_chunks):
        var input = SimdInput.load(ptr + chunk_idx * 64)
        var block = classify(input)
        var backslash = input.eq(UInt8(0x5C))
        var all_quotes = input.eq(UInt8(0x22))
        var escaped = es.next(backslash)
        var in_string = ss.next(all_quotes, escaped)
        var real_quotes = all_quotes & ~escaped
        var structural_ops = (block.op & ~in_string) | real_quotes
        var scalar = ~(block.whitespace | block.op | real_quotes | in_string)
        var scalar_start = scalar & ~((scalar << 1) | prev_scalar_carry)
        masks.append(structural_ops | scalar_start)
        bases.append(UInt32(chunk_idx * 64))
        prev_scalar_carry = (scalar >> 63) & 1


def scatter_old(masks: List[UInt64], bases: List[UInt32], mut out: List[UInt32]) -> Int:
    """Per-bit while loop (current production emit)."""
    var p = out.unsafe_ptr()
    var w = 0
    for k in range(len(masks)):
        var b = masks[k]
        var base = bases[k]
        while b != 0:
            p[w] = base + UInt32(count_trailing_zeros(b))
            w += 1
            b = b & (b - 1)
    return w


def scatter_new(masks: List[UInt64], bases: List[UInt32], mut out: List[UInt32]) -> Int:
    """Unconditional-8 branchless scatter (the swap under test)."""
    var p = out.unsafe_ptr()
    var w = 0
    for k in range(len(masks)):
        var b = masks[k]
        if b == 0:
            continue
        var base = bases[k]
        var cnt = Int(pop_count(b))
        var lw = w
        var done = 0
        while done < cnt:
            p[lw + 0] = base + UInt32(count_trailing_zeros(b)); b = b & (b - 1)
            p[lw + 1] = base + UInt32(count_trailing_zeros(b)); b = b & (b - 1)
            p[lw + 2] = base + UInt32(count_trailing_zeros(b)); b = b & (b - 1)
            p[lw + 3] = base + UInt32(count_trailing_zeros(b)); b = b & (b - 1)
            p[lw + 4] = base + UInt32(count_trailing_zeros(b)); b = b & (b - 1)
            p[lw + 5] = base + UInt32(count_trailing_zeros(b)); b = b & (b - 1)
            p[lw + 6] = base + UInt32(count_trailing_zeros(b)); b = b & (b - 1)
            p[lw + 7] = base + UInt32(count_trailing_zeros(b)); b = b & (b - 1)
            lw += 8
            done += 8
        w += cnt
    return w


def f3(x: Float64) -> String:
    var s = Int(x * 1000.0 + 0.5)
    var fs = String(s % 1000)
    while fs.byte_length() < 3:
        fs = "0" + fs
    return String(s // 1000) + "." + fs


def profile(name: String, data: List[UInt8], mut perf: PerfGroup) raises:
    var size = len(data)
    var padded = pad_buffer(data)
    var masks = List[UInt64]()
    var bases = List[UInt32]()
    collect(padded, size, masks, bases)
    var total = 0
    for k in range(len(masks)):
        total += Int(pop_count(masks[k]))
    var out = List[UInt32](unsafe_uninit_length=total + 64)

    # Correctness: both variants must produce the same count.
    var c_old = scatter_old(masks, bases, out)
    var c_new = scatter_new(masks, bases, out)
    var ok = (c_old == total) and (c_new == total)

    var sink: UInt64 = 0

    # --- old: min-time + min-cyc ---
    for _ in range(WARMUP):
        sink += UInt64(scatter_old(masks, bases, out))
    var old_ns = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var c = scatter_old(masks, bases, out)
        var t1 = perf_counter_ns()
        sink += UInt64(c)
        if Int(t1 - t0) < old_ns:
            old_ns = Int(t1 - t0)
    var old_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            perf.reset(); perf.enable()
            var c = scatter_old(masks, bases, out)
            perf.disable()
            sink += UInt64(c)
            if perf.cycles() < old_cyc:
                old_cyc = perf.cycles()

    # --- new: min-time + min-cyc ---
    for _ in range(WARMUP):
        sink += UInt64(scatter_new(masks, bases, out))
    var new_ns = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var c = scatter_new(masks, bases, out)
        var t1 = perf_counter_ns()
        sink += UInt64(c)
        if Int(t1 - t0) < new_ns:
            new_ns = Int(t1 - t0)
    var new_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            perf.reset(); perf.enable()
            var c = scatter_new(masks, bases, out)
            perf.disable()
            sink += UInt64(c)
            if perf.cycles() < new_cyc:
                new_cyc = perf.cycles()

    print("==== " + name + "  structurals=" + String(total) + "  correct=" + String(ok) + " ====")
    print("  old(per-bit):    " + f3(Float64(old_ns) / 1000.0) + " us   "
        + f3(Float64(old_cyc) / Float64(total)) + " cyc/struct")
    print("  new(uncond-8):   " + f3(Float64(new_ns) / 1000.0) + " us   "
        + f3(Float64(new_cyc) / Float64(total)) + " cyc/struct")
    var spd = Float64(old_cyc) / Float64(new_cyc) if new_cyc > 0 else 0.0
    print("  speedup (cyc): " + f3(spd) + "x   [sink=" + String(sink) + "]")
    print()


def main() raises:
    var perf = PerfGroup()
    perf.open()
    print("emit A/B  WARMUP=" + String(WARMUP) + " ITERS=" + String(ITERS)
        + " (min)  perf=" + String(perf.available))
    print()
    profile(String("twitter"), read_file(String("tests/fixtures/corpus/twitter.json")), perf)
    profile(String("citm"), read_file(String("tests/fixtures/corpus/citm_catalog.json")), perf)
    profile(String("canada"), read_file(String("tests/fixtures/corpus/canada.json")), perf)
    profile(String("github_events"), read_file(String("tests/fixtures/corpus/github_events.json")), perf)
    perf.close()
