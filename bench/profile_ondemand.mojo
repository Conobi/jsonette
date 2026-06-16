"""M5 thesis check: does On-Demand's deferred materialisation cut instructions?

The DOM `parse()` materialises EVERYTHING — full tape + every string copied +
every number parsed — whether or not the caller reads it. On-Demand `iter()`
runs only stage 1 (the structural index) and materialises a leaf only on access.
So the floor for any selective access is `iter()`'s cost; reading K fields adds
only those K leaves.

This measures, per corpus file, retired instructions + cycles for:
  - DOM   : `Parser._build(data)`           (full materialisation)
  - iter  : `Reader.reparse(data)`          (stage 1 only — navigable, nothing parsed)
and reports the ratio. instructions/byte is the thesis metric (deterministic,
laptop-reliable); cyc/B is laptop-indicative (VPS for a verdict).

Run:  uv run -- mojo run -I . -D ASSERT=none bench/profile_ondemand.mojo
"""

from jsonette.parser import Parser
from jsonette.ondemand.ondemand import Value
from jsonette.ondemand.reader import Reader, iter
from bench._metrics import PerfGroup


comptime WARMUP: Int = 20
comptime ITERS: Int = 300


def consume_value[o: Origin[mut=True]](v: Value[o]) raises -> UInt64:
    """Recursively read EVERY key + leaf reachable from `v` (the full-walk worst
    case for On-Demand: it parses everything, like the DOM, but builds no tape)."""
    if v.is_object():
        var obj = v.get_object()
        var s = UInt64(0)
        while not obj.at_end():
            var f = obj.next_field()
            s += UInt64(f.key().byte_length())
            s += consume_value(f.value())
        return s
    elif v.is_array():
        var arr = v.get_array()
        var s = UInt64(0)
        while not arr.at_end():
            s += consume_value(arr.next_element())
        return s
    elif v.is_string():
        return UInt64(v.get_string().byte_length())
    elif v.is_number():
        return UInt64(Int(v.get_float()))
    elif v.is_bool():
        return UInt64(1) if v.get_bool() else UInt64(0)
    else:
        return UInt64(1)  # null


def _sel_twitter(mut rdr: Reader, ref data: List[UInt8]) raises -> UInt64:
    """Selective: pluck 3 real values from a big doc, parsing only those leaves.

    Reads `search_metadata.count`, `statuses[0].id`, `statuses[0].text` — the rest
    of the document (all other statuses, all other fields) is skipped via the
    structural index, never parsed. The headline On-Demand access pattern.
    """
    rdr.reparse(data)
    var s = UInt64(0)
    var sm = rdr.root().field("search_metadata").get_object()
    s += sm.field("count").get_uint()
    var statuses = rdr.root().field("statuses").get_array()
    var first = statuses.next_element().get_object()
    s += first.field("id").get_uint()
    s += UInt64(first.field("text").get_string().byte_length())
    return s


def _sel_citm(mut rdr: Reader, ref data: List[UInt8]) raises -> UInt64:
    """Selective: pluck the first name from two non-empty top-level name maps.

    (`areaNames` n=17, `seatCategoryNames` n=64 — both id→string. The big
    `events`/`performances` collections are skipped via the structural index.)
    """
    rdr.reparse(data)
    var s = UInt64(0)
    var an = rdr.root().field("areaNames").get_object()
    s += UInt64(an.next_field().value().get_string().byte_length())
    var scn = rdr.root().field("seatCategoryNames").get_object()
    s += UInt64(scn.next_field().value().get_string().byte_length())
    return s


def _sel_canada(mut rdr: Reader, ref data: List[UInt8]) raises -> UInt64:
    """Selective: pluck `type` and `features[0].geometry.type` from a 2 MB doc.

    The millions of coordinate numbers are never parsed — they are skipped via
    depth-aware structural-index navigation.
    """
    rdr.reparse(data)
    var s = UInt64(0)
    s += UInt64(rdr.root().field("type").get_string().byte_length())
    var features = rdr.root().field("features").get_array()
    var f0 = features.next_element().get_object()
    s += UInt64(f0.field("type").get_string().byte_length())
    var geom = f0.field("geometry").get_object()
    s += UInt64(geom.field("type").get_string().byte_length())
    return s


def _selective(name: String, mut rdr: Reader, ref data: List[UInt8]) raises -> UInt64:
    """Dispatch to the per-corpus selective-read scenario."""
    if name == "twitter":
        return _sel_twitter(rdr, data)
    elif name == "citm_catalog":
        return _sel_citm(rdr, data)
    else:
        return _sel_canada(rdr, data)


def read_file(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


def f2(x: Float64) -> String:
    var scaled = Int(x * 100.0 + 0.5)
    var whole = scaled // 100
    var frac = scaled % 100
    var fs = String(frac)
    if frac < 10:
        fs = "0" + fs
    return String(whole) + "." + fs


def profile(name: String, data: List[UInt8], mut perf: PerfGroup) raises:
    var size = len(data)
    var parser = Parser()
    var rdr = iter(data)
    var sink: UInt64 = 0

    for _ in range(WARMUP):
        parser._build(data)
        sink += UInt64(len(parser._tape.elements))
        rdr.reparse(data)
        sink += UInt64(len(rdr._parser.positions))
        sink += _selective(name, rdr, data)

    if not perf.available:
        print("==== " + name + ": perf unavailable ===="); return

    var BIG = UInt64(0xFFFFFFFFFFFFFFFF)

    # DOM full parse
    var dom_ins = BIG
    var dom_cyc = BIG
    for _ in range(ITERS):
        perf.reset(); perf.enable()
        parser._build(data)
        perf.disable()
        sink += UInt64(len(parser._tape.elements))
        var ins = perf.instructions()
        var cyc = perf.cycles()
        if ins < dom_ins: dom_ins = ins
        if cyc < dom_cyc: dom_cyc = cyc

    # On-Demand iter() only (stage 1; nothing materialised)
    var it_ins = BIG
    var it_cyc = BIG
    for _ in range(ITERS):
        perf.reset(); perf.enable()
        rdr.reparse(data)
        perf.disable()
        sink += UInt64(len(rdr._parser.positions))
        var ins = perf.instructions()
        var cyc = perf.cycles()
        if ins < it_ins: it_ins = ins
        if cyc < it_cyc: it_cyc = cyc

    # On-Demand SELECTIVE (pluck 2-3 real values; the headline access pattern)
    var sel_ins = BIG
    var sel_cyc = BIG
    for _ in range(ITERS):
        perf.reset(); perf.enable()
        var sv = _selective(name, rdr, data)
        perf.disable()
        sink += sv
        var ins = perf.instructions()
        var cyc = perf.cycles()
        if ins < sel_ins: sel_ins = ins
        if cyc < sel_cyc: sel_cyc = cyc

    # On-Demand FULL walk (read every key + leaf — the worst case; no tape built)
    var fw_ins = BIG
    var fw_cyc = BIG
    for _ in range(ITERS):
        perf.reset(); perf.enable()
        rdr.reparse(data)
        var root = rdr.root().get_object()
        var s = UInt64(0)
        while not root.at_end():
            var f = root.next_field()
            s += UInt64(f.key().byte_length())
            s += consume_value(f.value())
        perf.disable()
        sink += s
        var ins = perf.instructions()
        var cyc = perf.cycles()
        if ins < fw_ins: fw_ins = ins
        if cyc < fw_cyc: fw_cyc = cyc

    var b = Float64(size)
    print("==== " + name + "  " + String(size) + "B ====")
    print("  DOM parse():       " + f2(Float64(dom_ins) / b) + " ins/B   "
        + f2(Float64(dom_cyc) / b) + " cyc/B")
    print("  OD iter() only:    " + f2(Float64(it_ins) / b) + " ins/B   "
        + f2(Float64(it_cyc) / b) + " cyc/B")
    print("  OD selective(2-3): " + f2(Float64(sel_ins) / b) + " ins/B   "
        + f2(Float64(sel_cyc) / b) + " cyc/B")
    print("  OD full-walk:      " + f2(Float64(fw_ins) / b) + " ins/B   "
        + f2(Float64(fw_cyc) / b) + " cyc/B")
    print("  => selective floor: " + f2(Float64(dom_ins) / Float64(it_ins))
        + "x fewer ins than DOM (" + f2(Float64(it_ins) / Float64(dom_ins) * 100.0) + "% of DOM)")
    print("  => selective(2-3):  " + f2(Float64(dom_ins) / Float64(sel_ins))
        + "x fewer ins than DOM (" + f2(Float64(sel_ins) / Float64(dom_ins) * 100.0) + "% of DOM)")
    print("  => full-walk vs DOM: " + f2(Float64(fw_ins) / Float64(dom_ins) * 100.0)
        + "% of DOM ins (read-everything worst case)")
    print("  [sink=" + String(sink) + "]")
    print()


def main() raises:
    var perf = PerfGroup()
    perf.open()
    print("on-demand thesis check  WARMUP=" + String(WARMUP) + " ITERS="
        + String(ITERS) + " (min)  perf=" + String(perf.available))
    print()
    profile(String("twitter"), read_file(String("tests/fixtures/corpus/twitter.json")), perf)
    profile(String("citm_catalog"), read_file(String("tests/fixtures/corpus/citm_catalog.json")), perf)
    profile(String("canada"), read_file(String("tests/fixtures/corpus/canada.json")), perf)
    perf.close()
