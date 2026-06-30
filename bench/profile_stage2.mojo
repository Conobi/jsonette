"""Stage-2 cost attribution: parse_string vs _parse_number vs dispatch remainder.

Partitions the structural positions into string / number / other, then micro-
benches parse_string over all string positions and _parse_number over all number
positions (isolated, min cyc), and compares to the full build_tape stage-2 total.
The remainder (stage2_total - strings - numbers) is the dispatch + container +
literal cost. Locates the stage-2 hot spot before optimizing.

Run:  uv run -- mojo run -I . -D ASSERT=none bench/profile_stage2.mojo
"""

from std.time import perf_counter_ns
from jsonette.stage1.indexer import structural_index
from jsonette.stage2.strings import parse_string
from jsonette.stage2.numbers import _parse_number
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
    var padded = List[UInt8](capacity=num_chunks * 64 + 128)
    for i in range(input_len):
        padded.append(data[i])
    while len(padded) < num_chunks * 64 + 128:
        padded.append(UInt8(0))
    return padded^


def f3(x: Float64) -> String:
    var s = Int(x * 1000.0 + 0.5)
    var fs = String(s % 1000)
    while fs.byte_length() < 3:
        fs = "0" + fs
    return String(s // 1000) + "." + fs


def scan_strings(str_pos: List[Int], ptr: UnsafePointer[UInt8, _], input_len: Int, sp: UnsafePointer[mut=True, UInt8, _]) raises -> Int:
    """Parse every string into the SAME buffer region (buf_start=0); return a sink."""
    var sink = 0
    for k in range(len(str_pos)):
        var r = parse_string(ptr, str_pos[k], input_len, sp, 0)
        sink += r[0]
    return sink


def scan_numbers(num_pos: List[Int], ptr: UnsafePointer[UInt8, _], input_len: Int) raises -> UInt64:
    var sink: UInt64 = 0
    for k in range(len(num_pos)):
        var r = _parse_number(ptr + num_pos[k], input_len - num_pos[k])
        sink += r.value + UInt64(r.tag)
    return sink


def profile(name: String, data: List[UInt8], mut perf: PerfGroup) raises:
    var size = len(data)
    var padded = pad_buffer(data)
    var positions = List[UInt32]()
    structural_index(padded, size, positions)
    var ptr = padded.unsafe_ptr()

    var sbuf = List[UInt8](unsafe_uninit_length=size + 64)
    var sp = sbuf.unsafe_ptr()
    var sink: UInt64 = 0

    # Partition structurals, mirroring build_tape's string-skip: stage-1 emits
    # BOTH opening and closing quotes as structurals, so parse each opening quote
    # and skip positions up to its closing quote (else closing quotes get parsed
    # as bogus string starts).
    var str_pos = List[Int]()
    var num_pos = List[Int]()
    var other = 0
    var si = 0
    while si < len(positions):
        var p = Int(positions[si])
        var b = ptr[p]
        if b == UInt8(0x22):
            str_pos.append(p)
            var r = parse_string(ptr, p, size, sp, 0)
            var string_end = p + r[0] - 1
            si += 1
            while si < len(positions) and Int(positions[si]) <= string_end:
                si += 1
        elif b == UInt8(0x2D) or (b >= UInt8(0x30) and b <= UInt8(0x39)):
            num_pos.append(p)
            si += 1
        else:
            other += 1
            si += 1

    # --- full stage-2 (build_tape) total cyc ---
    var positions2 = List[UInt32]()
    structural_index(padded, size, positions2)
    var n_struct = len(positions2)
    var cs = List[UInt32](capacity=4096)
    var tape = Tape()
    for _ in range(WARMUP):
        positions2.resize(n_struct, UInt32(0)); cs.resize(0, UInt32(0))
        build_tape(padded, size, positions2, cs, tape)
        sink += tape.elements.unsafe_get(0)
    var s2_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            positions2.resize(n_struct, UInt32(0)); cs.resize(0, UInt32(0))
            perf.reset(); perf.enable()
            build_tape(padded, size, positions2, cs, tape)
            perf.disable()
            sink += tape.elements.unsafe_get(0)
            if perf.cycles() < s2_cyc:
                s2_cyc = perf.cycles()

    # --- strings isolated ---
    for _ in range(WARMUP):
        sink += UInt64(scan_strings(str_pos, ptr, size, sp))
    var str_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available and len(str_pos) > 0:
        for _ in range(ITERS):
            perf.reset(); perf.enable()
            var s = scan_strings(str_pos, ptr, size, sp)
            perf.disable()
            sink += UInt64(s)
            if perf.cycles() < str_cyc:
                str_cyc = perf.cycles()
    else:
        str_cyc = 0

    # --- numbers isolated ---
    for _ in range(WARMUP):
        sink += scan_numbers(num_pos, ptr, size)
    var num_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available and len(num_pos) > 0:
        for _ in range(ITERS):
            perf.reset(); perf.enable()
            var s = scan_numbers(num_pos, ptr, size)
            perf.disable()
            sink += s
            if num_cyc > perf.cycles():
                num_cyc = perf.cycles()
    else:
        num_cyc = 0

    var rem = Int(s2_cyc) - Int(str_cyc) - Int(num_cyc)
    var s2f = Float64(s2_cyc)
    print("==== " + name + " (" + String(size) + " B) ====")
    print("  counts: strings=" + String(len(str_pos)) + " numbers=" + String(len(num_pos)) + " other=" + String(other))
    print("  stage2_total: " + f3(s2f / Float64(size)) + " cyc/B")
    print("  strings:  " + f3(Float64(str_cyc) / s2f * 100.0) + "% of s2   "
        + (f3(Float64(str_cyc) / Float64(len(str_pos))) if len(str_pos) > 0 else "n/a") + " cyc/str")
    print("  numbers:  " + f3(Float64(num_cyc) / s2f * 100.0) + "% of s2   "
        + (f3(Float64(num_cyc) / Float64(len(num_pos))) if len(num_pos) > 0 else "n/a") + " cyc/num")
    print("  dispatch+containers (remainder): " + f3(Float64(rem) / s2f * 100.0) + "%")
    print("  [sink=" + String(sink) + "]")
    print()


def main() raises:
    var perf = PerfGroup()
    perf.open()
    print("stage-2 attribution  WARMUP=" + String(WARMUP) + " ITERS=" + String(ITERS)
        + " (min cyc)  perf=" + String(perf.available))
    print()
    profile(String("twitter"), read_file(String("tests/fixtures/corpus/twitter.json")), perf)
    profile(String("citm_catalog"), read_file(String("tests/fixtures/corpus/citm_catalog.json")), perf)
    profile(String("canada"), read_file(String("tests/fixtures/corpus/canada.json")), perf)
    profile(String("github_events"), read_file(String("tests/fixtures/corpus/github_events.json")), perf)
    perf.close()
