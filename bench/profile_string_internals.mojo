"""Decompose parse_string's ~106 ins/str: fixed per-call overhead vs per-chunk.

Calls parse_string on synthetic clean ASCII strings of growing content length
and measures retired instructions per call. ins(L) is ~ fixed + chunks(L)*per_chunk,
so the intercept (L->0) is the per-call fixed overhead (prologue, SIMD splat setup,
length-prefix + null-terminator finalize, return) and the slope per 32B is the
per-chunk SIMD cost (load + 32B store + quote/backslash/control compares + masks).

twitter strings average ~30B (≈1 chunk), so if fixed overhead is large, that —
not the per-chunk work — is what 18099 short strings pay.

Run:  uv run -- mojo run -I . -D ASSERT=none bench/profile_string_internals.mojo
"""

from jsonette.stage2.strings import parse_string
from bench._metrics import PerfGroup


comptime WARMUP: Int = 50
comptime ITERS: Int = 2000


def f2(x: Float64) -> String:
    var neg = x < 0.0
    var ax = -x if neg else x
    var scaled = Int(ax * 100.0 + 0.5)
    var whole = scaled // 100
    var frac = scaled % 100
    var fs = String(frac)
    if frac < 10:
        fs = "0" + fs
    return ("-" if neg else "") + String(whole) + "." + fs


def measure_len(content_len: Int, mut perf: PerfGroup) raises -> Tuple[Int, UInt64, UInt64]:
    """Build "aaa...a" of content_len bytes and return (chunks, min_ins, min_cyc)."""
    var total = content_len + 2  # quotes
    var bufcap = total + 128
    var src = List[UInt8](unsafe_uninit_length=bufcap)
    var sp = src.unsafe_ptr()
    sp[0] = UInt8(0x22)  # opening quote
    for k in range(content_len):
        sp[1 + k] = UInt8(0x61)  # 'a'
    sp[1 + content_len] = UInt8(0x22)  # closing quote
    for k in range(total, bufcap):
        sp[k] = UInt8(0)  # pad
    var dst = List[UInt8](unsafe_uninit_length=bufcap + 64)
    var dp = dst.unsafe_ptr()

    var sink: UInt64 = 0
    for _ in range(WARMUP):
        var r = parse_string(sp, 0, total, dp, 0)
        sink += UInt64(r[1])

    var min_ins = UInt64(0xFFFFFFFFFFFFFFFF)
    var min_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        perf.reset(); perf.enable()
        var r = parse_string(sp, 0, total, dp, 0)
        perf.disable()
        var ins = perf.instructions()
        var cyc = perf.cycles()
        if ins < min_ins: min_ins = ins
        if cyc < min_cyc: min_cyc = cyc
        sink += UInt64(r[1])
    # 32B chunks scanned: ceil((content_len+1)/32) roughly (quote ends scan)
    var chunks = (content_len + 1 + 31) // 32
    _ = sink
    return (chunks, min_ins, min_cyc)


def main() raises:
    var perf = PerfGroup()
    perf.open()
    print("parse_string internals  WARMUP=" + String(WARMUP) + " ITERS="
        + String(ITERS) + " (min)  perf=" + String(perf.available))
    print()
    if not perf.available:
        print("perf unavailable"); perf.close(); return

    var lens = [1, 8, 16, 30, 62, 126, 254, 510]
    print("  contentLen  chunks   ins/call   cyc/call")
    var ins_at_1 = UInt64(0)
    var ins_at_510 = UInt64(0)
    var chunks_1 = 0
    var chunks_510 = 0
    for idx in range(len(lens)):
        var L = lens[idx]
        var res = measure_len(L, perf)
        var chunks = res[0]
        var mins = res[1]
        var mcyc = res[2]
        print("  " + String(L) + "          " + String(chunks) + "       "
            + String(mins) + "       " + String(mcyc))
        if L == 1:
            ins_at_1 = mins; chunks_1 = chunks
        if L == 510:
            ins_at_510 = mins; chunks_510 = chunks

    var per_chunk = Float64(ins_at_510 - ins_at_1) / Float64(chunks_510 - chunks_1)
    var fixed = Float64(ins_at_1) - per_chunk * Float64(chunks_1)
    print()
    print("  => per-chunk (32B) ~ " + f2(per_chunk) + " ins   |   fixed per-call ~ "
        + f2(fixed) + " ins")
    print("  => a 30B string (1 chunk) ~ " + f2(fixed + per_chunk) + " ins  (fixed is "
        + f2(fixed / (fixed + per_chunk) * 100.0) + "% of it)")
    perf.close()
