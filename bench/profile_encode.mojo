"""Encoder profile: is to_string slow, and is it the unreserved output buffer?

Measures to_string (tape -> JSON) throughput vs the known parse cost, and A/Bs it
against the same walk into a PRE-RESERVED writer buffer to isolate the cost of
JsonWriter's grow-from-empty List (repeated realloc + memcpy). Output-byte cyc.

Run:  uv run -- mojo run -I . -D ASSERT=none bench/profile_encode.mojo
"""

from std.time import perf_counter_ns
from std.memory import bitcast
from jsonette.document import Document, parse
from jsonette.serialize.tape_writer import to_string, _write_value
from jsonette.serialize.writer import JsonWriter
from jsonette.tape import TAG_STRING, TAG_INT64, TAG_UINT64, TAG_FLOAT64
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


def f3(x: Float64) -> String:
    var s = Int(x * 1000.0 + 0.5)
    var fs = String(s % 1000)
    while fs.byte_length() < 3:
        fs = "0" + fs
    return String(s // 1000) + "." + fs


def encode_reserved[o: Origin[mut=True]](ref [o] doc: Document, cap: Int) raises -> Int:
    """Same walk as to_string, but into a pre-reserved buffer."""
    var w = JsonWriter()
    w.buf.reserve(cap)
    _ = _write_value(doc, 1, w)
    var n = len(w.buf)
    _ = w^.finish()
    return n


def profile(name: String, data: List[UInt8], mut perf: PerfGroup) raises:
    var size = len(data)
    # Single cold parse outside every timed region — only the encode path is
    # measured here, so the parse cost does not enter the numbers.
    var doc = parse(data)
    var out_size = len(to_string(doc))
    var sink: UInt64 = 0

    # --- to_string (unreserved, grows from empty): min-time + min-cyc ---
    for _ in range(WARMUP):
        sink += UInt64(len(to_string(doc)))
    var ts_ns = Int(0x7FFFFFFFFFFFFFFF)
    for _ in range(ITERS):
        var t0 = perf_counter_ns()
        var s = to_string(doc)
        var t1 = perf_counter_ns()
        sink += UInt64(len(s))
        if Int(t1 - t0) < ts_ns:
            ts_ns = Int(t1 - t0)
    var ts_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            perf.reset(); perf.enable()
            var s = to_string(doc)
            perf.disable()
            sink += UInt64(len(s))
            if perf.cycles() < ts_cyc:
                ts_cyc = perf.cycles()

    # --- reserved walk: min-cyc ---
    for _ in range(WARMUP):
        sink += UInt64(encode_reserved(doc, out_size))
    var rs_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available:
        for _ in range(ITERS):
            perf.reset(); perf.enable()
            var n = encode_reserved(doc, out_size)
            perf.disable()
            sink += UInt64(n)
            if perf.cycles() < rs_cyc:
                rs_cyc = perf.cycles()

    # --- collect string spans and number values from the tape (linear scan) ---
    var ep = doc._parser._tape.elements.unsafe_ptr()
    var sbp = doc._parser._tape.string_buf.unsafe_ptr()
    var nelem = len(doc._parser._tape.elements)
    var str_off = List[Int]()
    var str_len = List[Int]()
    var num_tag = List[UInt8]()
    var num_val = List[UInt64]()
    var idx = 1
    while idx < nelem:
        var tag = UInt8(ep[idx] >> 56)
        if tag == TAG_STRING:
            var off = Int(ep[idx] & 0x00FFFFFFFFFFFFFF)
            var sl = Int(UInt32(sbp[off]) | (UInt32(sbp[off + 1]) << 8)
                | (UInt32(sbp[off + 2]) << 16) | (UInt32(sbp[off + 3]) << 24))
            str_off.append(off); str_len.append(sl); idx += 1
        elif tag == TAG_INT64 or tag == TAG_UINT64 or tag == TAG_FLOAT64:
            num_tag.append(tag); num_val.append(ep[idx + 1]); idx += 2
        else:
            idx += 1

    # --- escaping only (reserved writer, write_escaped_buf over all strings) ---
    var esc_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available and len(str_off) > 0:
        for _ in range(ITERS):
            var w = JsonWriter(); w.buf.reserve(out_size + 16)
            ref sb = doc._parser._tape.string_buf
            perf.reset(); perf.enable()
            for k in range(len(str_off)):
                w.write_escaped_buf(sb, str_off[k] + 4, str_len[k])
            perf.disable()
            sink += UInt64(len(w.buf))
            if perf.cycles() < esc_cyc:
                esc_cyc = perf.cycles()
    else:
        esc_cyc = 0

    # --- numbers only (reserved writer, format every number value) ---
    var num_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    if perf.available and len(num_tag) > 0:
        for _ in range(ITERS):
            var w = JsonWriter(); w.buf.reserve(out_size + 16)
            perf.reset(); perf.enable()
            for k in range(len(num_tag)):
                var t = num_tag[k]
                if t == TAG_INT64:
                    w.write_int(Int64(bitcast[DType.int64](SIMD[DType.uint64, 1](num_val[k]))))
                elif t == TAG_UINT64:
                    w.write_uint(num_val[k])
                else:
                    w.write_float(Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](num_val[k]))))
            perf.disable()
            sink += UInt64(len(w.buf))
            if perf.cycles() < num_cyc:
                num_cyc = perf.cycles()
    else:
        num_cyc = 0

    var gbs = Float64(out_size) / Float64(ts_ns)
    var tsf = Float64(ts_cyc)
    print("==== " + name + "  in=" + String(size) + "B out=" + String(out_size)
        + "B  strings=" + String(len(str_off)) + " numbers=" + String(len(num_tag)) + " ====")
    print("  to_string:        " + f3(Float64(ts_ns) / 1000.0) + " us   " + f3(gbs)
        + " GB/s(out)   " + f3(tsf / Float64(out_size)) + " cyc/outB")
    print("  reserved-buffer:  growth cost " + f3(tsf / Float64(rs_cyc)) + "x  (so buffer growth is "
        + (f3((tsf / Float64(rs_cyc) - 1.0) * 100.0)) + "% of encode)")
    print("  escaping:   " + f3(Float64(esc_cyc) / tsf * 100.0) + "% of encode   "
        + (f3(Float64(esc_cyc) / Float64(len(str_off))) if len(str_off) > 0 else "n/a") + " cyc/str")
    print("  numbers:    " + f3(Float64(num_cyc) / tsf * 100.0) + "% of encode   "
        + (f3(Float64(num_cyc) / Float64(len(num_tag))) if len(num_tag) > 0 else "n/a") + " cyc/num")
    print("  [sink=" + String(sink) + "]")
    print()


def main() raises:
    var perf = PerfGroup()
    perf.open()
    print("encode profile  WARMUP=" + String(WARMUP) + " ITERS=" + String(ITERS)
        + " (min)  perf=" + String(perf.available))
    print()
    profile(String("twitter"), read_file(String("tests/fixtures/corpus/twitter.json")), perf)
    profile(String("citm_catalog"), read_file(String("tests/fixtures/corpus/citm_catalog.json")), perf)
    profile(String("canada"), read_file(String("tests/fixtures/corpus/canada.json")), perf)
    profile(String("github_events"), read_file(String("tests/fixtures/corpus/github_events.json")), perf)
    perf.close()
