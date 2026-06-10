"""Per-sub-path instruction breakdown for the number parser.

`bench/profile_number.mojo` measures the number path's *time* over canada's
real (float-heavy) tokens. This harness adds two things the localization needs:

  1. Hardware **instructions/token** and **instructions/number-byte** (via the
     same `perf_event_open` group the REST bench uses), not just wall time.
  2. A **sub-path split** — separate synthetic corpora for the integer path,
     the Eisel-Lemire float fast path, and the long-mantissa float slow path —
     so we can see *which* sub-path dominates the ~18-20 ins/byte we measured
     on number-dense payloads, instead of lumping all floats together.

Each corpus is a flat buffer of maximal number tokens, every token followed by
16 NUL bytes (the SWAR over-read needs >=8). `_parse_number` is called per
token exactly as the tape builder calls it. Min-time and min-counter passes are
separate so the counter syscalls never pollute the wall-clock pass.

Run:  uv run -- mojo run -I . -D ASSERT=none bench/profile_number_perf.mojo
On a locked-down host perf is unavailable and the cyc/ins columns read n/a;
use the fixed-freq bench VPS for trustworthy figures.
"""

from std.time import perf_counter_ns
from simdjson.stage2.numbers import _parse_number
from bench._metrics import PerfGroup


comptime WARMUP: Int = 20
comptime ITERS: Int = 200
comptime PAD: Int = 16  # NUL bytes after each token for the SWAR over-read
comptime K: Int = 6000  # synthetic tokens per corpus


def read_file(path: String) raises -> List[UInt8]:
    """Read a file into an owned byte buffer."""
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


def fmt_f(x: Float64, decimals: Int) -> String:
    """Format a non-negative float to a fixed number of decimal places."""
    var scale = 1
    for _ in range(decimals):
        scale *= 10
    var scaled = Int(x * Float64(scale) + 0.5)
    var whole = scaled // scale
    var frac = scaled % scale
    var fs = String(frac)
    while fs.byte_length() < decimals:
        fs = "0" + fs
    if decimals == 0:
        return String(whole)
    return String(whole) + "." + fs


def lpad(s: String, w: Int) -> String:
    """Right-justify `s` to width `w`."""
    var out = s
    while out.byte_length() < w:
        out = " " + out
    return out


def rpad(s: String, w: Int) -> String:
    """Left-justify `s` to width `w`."""
    var out = s
    while out.byte_length() < w:
        out = out + " "
    return out


def add_token(
    mut big: List[UInt8], mut starts: List[Int], mut lens: List[Int], tok: String
):
    """Append one number token plus NUL padding; record its offset and length."""
    var off = len(big)
    for b in tok.as_bytes():
        big.append(b)
    for _ in range(PAD):
        big.append(UInt8(0))
    starts.append(off)
    lens.append(tok.byte_length())


def _is_num_start(b: UInt8) -> Bool:
    """True if `b` can begin a JSON number ('-' or a digit)."""
    return b == UInt8(0x2D) or (b >= UInt8(0x30) and b <= UInt8(0x39))


def _is_num_char(b: UInt8) -> Bool:
    """True if `b` can appear inside a JSON number token."""
    return (
        (b >= UInt8(0x30) and b <= UInt8(0x39))
        or b == UInt8(0x2D)
        or b == UInt8(0x2B)
        or b == UInt8(0x2E)
        or b == UInt8(0x65)
        or b == UInt8(0x45)
    )


def build_int(mut big: List[UInt8], mut starts: List[Int], mut lens: List[Int]):
    """Integer-path corpus: varied widths, signs, and near-2^63 magnitudes."""
    for i in range(K):
        var p = i % 4
        if p == 0:
            add_token(big, starts, lens, String(i % 10000))
        elif p == 1:
            add_token(big, starts, lens, String((i * 7919) % 1000000))
        elif p == 2:
            # 18-19 digit integers near the i64/u64 boundary (overflow guard).
            add_token(big, starts, lens, String(UInt64(9223372036854775807) - UInt64(i)))
        else:
            add_token(big, starts, lens, "-" + String(i % 100000))


def build_fastfloat(
    mut big: List[UInt8], mut starts: List[Int], mut lens: List[Int]
):
    """Eisel-Lemire fast-path corpus: short decimals, <=~12 significant digits."""
    for i in range(K):
        var a = i % 1000
        var b = (i * 13) % 1000000
        var tok = String(a) + "." + String(b)
        if i % 3 == 0:
            tok = "-" + tok
        add_token(big, starts, lens, tok)


def build_hardfloat(
    mut big: List[UInt8], mut starts: List[Int], mut lens: List[Int]
):
    """Slow-path corpus: 25 significant digits + wide exponent (defeats E-L)."""
    var long_mantissa = String("1234567890123456789012345")  # 25 digits
    for i in range(K):
        var e = (i % 600) - 300
        var tok = "0." + long_mantissa + "e" + String(e)
        add_token(big, starts, lens, tok)


def build_canada(
    mut big: List[UInt8], mut starts: List[Int], mut lens: List[Int]
) raises:
    """Real float distribution: every maximal number token from canada.json."""
    var data = read_file(String("tests/fixtures/corpus/canada.json"))
    var n = len(data)
    var i = 0
    while i < n:
        var b = data[i]
        if _is_num_start(b) and (i == 0 or not _is_num_char(data[i - 1])):
            var j = i
            while j < n and _is_num_char(data[j]):
                j += 1
            var tok = String("")
            for k in range(i, j):
                tok += chr(Int(data[k]))
            add_token(big, starts, lens, tok)
            i = j
        else:
            i += 1


def bench(
    name: String,
    big: List[UInt8],
    starts: List[Int],
    lens: List[Int],
    mut perf: PerfGroup,
) raises:
    """Time + count `_parse_number` over one corpus; print a metrics row."""
    var ntok = len(starts)
    var ptr = big.unsafe_ptr()
    var num_bytes = 0
    for t in range(ntok):
        num_bytes += lens[t]

    var sink: UInt64 = 0

    for _ in range(WARMUP):
        for t in range(ntok):
            sink += _parse_number(ptr + starts[t], lens[t]).value

    # Pass 1 — min wall-clock (no counter syscalls).
    var best_ns = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        for t in range(ntok):
            sink += _parse_number(ptr + starts[t], lens[t]).value
        var t1 = perf_counter_ns()
        var dt = Int(t1 - t0)
        if dt < best_ns:
            best_ns = dt

    # Pass 2 — min cycles / instructions.
    var best_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    var best_ins = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            perf.reset()
            perf.enable()
            for t in range(ntok):
                sink += _parse_number(ptr + starts[t], lens[t]).value
            perf.disable()
            var c = perf.cycles()
            var ins = perf.instructions()
            if c < best_cyc:
                best_cyc = c
            if ins < best_ins:
                best_ins = ins

    var ns_tok = Float64(best_ns) / Float64(ntok)
    var avg_len = Float64(num_bytes) / Float64(ntok)
    var cyc_tok = String("n/a")
    var ins_tok = String("n/a")
    var ins_b = String("n/a")
    if perf.available:
        cyc_tok = fmt_f(Float64(best_cyc) / Float64(ntok), 1)
        ins_tok = fmt_f(Float64(best_ins) / Float64(ntok), 1)
        ins_b = fmt_f(Float64(best_ins) / Float64(num_bytes), 2)

    print(
        rpad(name, 12)
        + lpad(String(ntok), 8)
        + lpad(fmt_f(avg_len, 1), 8)
        + lpad(fmt_f(ns_tok, 1), 9)
        + lpad(cyc_tok, 9)
        + lpad(ins_tok, 9)
        + lpad(ins_b, 9)
        + lpad(String(sink % 1000), 6)
    )


def main() raises:
    """Build each sub-path corpus and print an instruction-breakdown table."""
    var perf = PerfGroup()
    perf.open()
    print(
        "number sub-path breakdown  K=" + String(K) + " WARMUP=" + String(WARMUP)
        + " ITERS=" + String(ITERS) + "  perf=" + String(perf.available)
    )
    print(
        rpad("corpus", 12) + lpad("ntok", 8) + lpad("avglen", 8)
        + lpad("ns/tok", 9) + lpad("cyc/tok", 9) + lpad("ins/tok", 9)
        + lpad("ins/B", 9) + lpad("sink", 6)
    )

    var bi = List[UInt8](); var si = List[Int](); var li = List[Int]()
    build_int(bi, si, li)
    bench(String("integer"), bi, si, li, perf)

    var bf = List[UInt8](); var sf = List[Int](); var lf = List[Int]()
    build_fastfloat(bf, sf, lf)
    bench(String("fastfloat"), bf, sf, lf, perf)

    var bh = List[UInt8](); var sh = List[Int](); var lh = List[Int]()
    build_hardfloat(bh, sh, lh)
    bench(String("hardfloat"), bh, sh, lh, perf)

    var bc = List[UInt8](); var sc = List[Int](); var lc = List[Int]()
    build_canada(bc, sc, lc)
    bench(String("canada"), bc, sc, lc, perf)

    perf.close()
