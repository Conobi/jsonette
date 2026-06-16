"""Localize the 2.44x instruction gap vs C++ simdjson: split ins/B by phase.

Parser.parse = pad (memcpy+memset) -> structural_index (stage 1) ->
build_tape (stage 2). This drives each phase directly in its own measured loop
(PerfGroup, retired instructions + cycles, min over ITERS), so we see which
phase owns the 7.78 ins/B we retire on twitter while simdjson retires 3.19.

Stage-2 isolation: build_tape appends sentinels to `positions` but never
rewrites the real entries, so restoring is a `resize` back to the clean
structural count (done OUTSIDE the measured region). Stacks are reset outside
too — exactly the prep Parser.parse does between the stages.

Run:  uv run -- mojo run -I . -D ASSERT=none bench/profile_stage_ins.mojo
"""

from std.memory import memcpy, memset
from jsonette.stage1.indexer import structural_index
from jsonette.stage2.builder import build_tape
from jsonette.stage2.strings import parse_string
from jsonette.stage2.numbers import _parse_number
from jsonette.tape import Tape
from jsonette.error import format_parse_error
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


def f2(x: Float64) -> String:
    """Format a non-negative Float64 to 2 decimals."""
    var scaled = Int(x * 100.0 + 0.5)
    var whole = scaled // 100
    var frac = scaled % 100
    var fs = String(frac)
    if frac < 10:
        fs = "0" + fs
    return String(whole) + "." + fs


def profile(name: String, data: List[UInt8], mut perf: PerfGroup) raises:
    var input_len = len(data)
    var num_chunks = (input_len + 63) // 64
    var padded_len = num_chunks * 64 + 128

    var padded = List[UInt8](unsafe_uninit_length=padded_len)
    var positions = List[UInt32]()
    var container_stack = List[UInt32](capacity=2048)
    var count_stack = List[UInt32](capacity=1024)
    var tape = Tape()
    var sink: UInt64 = 0

    # --- warm every buffer to its grown capacity (0 allocs in the loops) ---
    for _ in range(WARMUP):
        memcpy(dest=padded.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
        memset(padded.unsafe_ptr() + input_len, 0, padded_len - input_len)
        structural_index(padded, input_len, positions)
        var cc = len(positions)
        container_stack.resize(0, UInt32(0))
        count_stack.resize(0, UInt32(0))
        try:
            build_tape(padded, input_len, positions, container_stack, count_stack, tape)
        except e:
            raise format_parse_error(e.code, e.position)
        positions.resize(cc, UInt32(0))
        sink += UInt64(len(tape.elements))

    # clean structural count for stage-2 restore
    structural_index(padded, input_len, positions)
    var clean_count = len(positions)

    if not perf.available:
        print("==== " + name + ": perf unavailable ====")
        return

    var BIG = UInt64(0xFFFFFFFFFFFFFFFF)

    # --- PHASE: pad (input copy) ---
    var pad_ins = BIG
    var pad_cyc = BIG
    for _ in range(ITERS):
        perf.reset(); perf.enable()
        memcpy(dest=padded.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
        memset(padded.unsafe_ptr() + input_len, 0, padded_len - input_len)
        perf.disable()
        var ins = perf.instructions()
        var cyc = perf.cycles()
        if ins < pad_ins: pad_ins = ins
        if cyc < pad_cyc: pad_cyc = cyc
        sink += UInt64(padded[input_len - 1])

    # --- PHASE: stage 1 (structural_index) ---
    var s1_ins = BIG
    var s1_cyc = BIG
    for _ in range(ITERS):
        perf.reset(); perf.enable()
        structural_index(padded, input_len, positions)
        perf.disable()
        var ins = perf.instructions()
        var cyc = perf.cycles()
        if ins < s1_ins: s1_ins = ins
        if cyc < s1_cyc: s1_cyc = cyc
        sink += UInt64(len(positions))

    # --- PHASE: stage 2 (build_tape) ---
    var s2_ins = BIG
    var s2_cyc = BIG
    for _ in range(ITERS):
        positions.resize(clean_count, UInt32(0))   # restore (drop sentinels) — outside measure
        container_stack.resize(0, UInt32(0))
        count_stack.resize(0, UInt32(0))
        perf.reset(); perf.enable()
        try:
            build_tape(padded, input_len, positions, container_stack, count_stack, tape)
        except e:
            raise format_parse_error(e.code, e.position)
        perf.disable()
        var ins = perf.instructions()
        var cyc = perf.cycles()
        if ins < s2_ins: s2_ins = ins
        if cyc < s2_cyc: s2_cyc = cyc
        sink += UInt64(len(tape.elements))

    # --- WITHIN STAGE 2: isolate parse_string over every string in the doc ---
    # Mirrors build_tape's walk: an opening quote is a structural whose next
    # structural is its closing quote (proven invariant), so advance by 2 there.
    # ins/B here = parse_string work + a build_tape-like per-structural dispatch.
    var sbuf = List[UInt8](unsafe_uninit_length=input_len + 64)
    var sbp = sbuf.unsafe_ptr()
    var ip = padded.unsafe_ptr()
    positions.resize(clean_count, UInt32(0))
    var pos_ptr = positions.unsafe_ptr()
    var str_ins = BIG
    var str_cyc = BIG
    var n_strings = 0
    for _ in range(ITERS):
        perf.reset(); perf.enable()
        var sbuf_pos = 0
        var i = 0
        var cnt = 0
        while i < clean_count:
            var p = Int(pos_ptr[i])
            if ip[p] == UInt8(0x22):  # opening quote
                var r = parse_string(ip, p, input_len, sbp + sbuf_pos, 0)
                sbuf_pos += r[1]
                cnt += 1
                i += 2  # skip closing quote
            else:
                i += 1
        perf.disable()
        var ins = perf.instructions()
        var cyc = perf.cycles()
        if ins < str_ins: str_ins = ins
        if cyc < str_cyc: str_cyc = cyc
        n_strings = cnt
        sink += UInt64(sbuf_pos)

    # --- WITHIN STAGE 2: isolate _parse_number over every number in the doc ---
    var num_ins = BIG
    var num_cyc = BIG
    var n_numbers = 0
    for _ in range(ITERS):
        perf.reset(); perf.enable()
        var i = 0
        var cnt = 0
        var acc = UInt64(0)
        while i < clean_count:
            var p = Int(pos_ptr[i])
            var bb = ip[p]
            if bb == UInt8(0x2D) or (bb >= UInt8(0x30) and bb <= UInt8(0x39)):
                var r = _parse_number(ip + p, input_len - p)
                acc += r.value
                cnt += 1
            i += 1
        perf.disable()
        var ins = perf.instructions()
        var cyc = perf.cycles()
        if ins < num_ins: num_ins = ins
        if cyc < num_cyc: num_cyc = cyc
        n_numbers = cnt
        sink += acc

    # --- PHASE: full parse (pad + stage1 + stage2), reference ---
    var full_ins = BIG
    var full_cyc = BIG
    for _ in range(ITERS):
        perf.reset(); perf.enable()
        memcpy(dest=padded.unsafe_ptr(), src=data.unsafe_ptr(), count=input_len)
        memset(padded.unsafe_ptr() + input_len, 0, padded_len - input_len)
        structural_index(padded, input_len, positions)
        container_stack.resize(0, UInt32(0))
        count_stack.resize(0, UInt32(0))
        try:
            build_tape(padded, input_len, positions, container_stack, count_stack, tape)
        except e:
            raise format_parse_error(e.code, e.position)
        perf.disable()
        var ins = perf.instructions()
        var cyc = perf.cycles()
        if ins < full_ins: full_ins = ins
        if cyc < full_cyc: full_cyc = cyc
        sink += UInt64(len(tape.elements))

    var b = Float64(input_len)
    var fi = Float64(full_ins)
    print("==== " + name + "  " + String(input_len) + "B  (structurals=" + String(clean_count) + ") ====")
    print("  phase           ins/B    cyc/B   %ins(full)")
    print("  pad        " + f2(Float64(pad_ins) / b) + "    " + f2(Float64(pad_cyc) / b)
        + "    " + f2(Float64(pad_ins) / fi * 100.0) + "%")
    print("  stage1     " + f2(Float64(s1_ins) / b) + "    " + f2(Float64(s1_cyc) / b)
        + "    " + f2(Float64(s1_ins) / fi * 100.0) + "%")
    print("  stage2     " + f2(Float64(s2_ins) / b) + "    " + f2(Float64(s2_cyc) / b)
        + "    " + f2(Float64(s2_ins) / fi * 100.0) + "%")
    print("   ├ strings " + f2(Float64(str_ins) / b) + "    " + f2(Float64(str_cyc) / b)
        + "    " + f2(Float64(str_ins) / fi * 100.0) + "%   ("
        + String(n_strings) + " strs, " + f2(Float64(str_ins) / Float64(n_strings) if n_strings > 0 else 0.0) + " ins/str)")
    print("   └ numbers " + f2(Float64(num_ins) / b) + "    " + f2(Float64(num_cyc) / b)
        + "    " + f2(Float64(num_ins) / fi * 100.0) + "%   ("
        + String(n_numbers) + " nums, " + f2(Float64(num_ins) / Float64(n_numbers) if n_numbers > 0 else 0.0) + " ins/num)")
    print("  --------")
    print("  FULL       " + f2(fi / b) + "    " + f2(Float64(full_cyc) / b)
        + "    (sum of phases " + f2(Float64(pad_ins + s1_ins + s2_ins) / b) + " ins/B)")
    print("  [sink=" + String(sink) + "]")
    print()


def main() raises:
    var perf = PerfGroup()
    perf.open()
    print("stage instruction profile  WARMUP=" + String(WARMUP) + " ITERS="
        + String(ITERS) + " (min)  perf=" + String(perf.available))
    print()
    profile(String("twitter"), read_file(String("tests/fixtures/corpus/twitter.json")), perf)
    profile(String("citm_catalog"), read_file(String("tests/fixtures/corpus/citm_catalog.json")), perf)
    profile(String("canada"), read_file(String("tests/fixtures/corpus/canada.json")), perf)
    profile(String("github_events"), read_file(String("tests/fixtures/corpus/github_events.json")), perf)
    perf.close()
