"""IPC triage: where do the parse cycles go — bad speculation or backend?

We retire ~the same instructions/byte as C++ simdjson but ~2.4x more cycles, so
the gap lives entirely in IPC. IPC is an outcome, not a lever; this profile
splits it into its first cause. It reads cycles + instructions + branches +
branch-misses over one full `Parser.parse` (all four in one grouped region) and
reports, per corpus file:

  cyc/B, ins/B, IPC, branches/B, branch-miss rate, mispredict-cycle share.

Reading: a HIGH miss rate and a LARGE mispredict-cycle share (misses x ~16cyc
recovery / total cycles) means the gap is BAD SPECULATION — a mispredicting
dispatch tree (build_tape's byte-value if/elif chain), and branchless dispatch
becomes a named, verified lever. A LOW miss rate means it is BACKEND-bound
(dependency-chain latency, port pressure, or Mojo codegen) and must be chased
with external `perf stat -M tma_*`, not source restructuring.

Twitter is string/object-heavy (worst gap, most dispatch entropy); canada is
number-dense (tighter inner loops). The contrast is the tell.

Absolute cyc/B needs the pinned VPS; the branch-miss RATE is a microarchitectural
ratio and is trustworthy on the laptop for shape.

Run:  uv run -- mojo run -I . -D ASSERT=none bench/profile_ipc.mojo
"""

from jsonette.parser import Parser
from bench._metrics import PerfGroup


comptime WARMUP: Int = 30
comptime ITERS: Int = 400
comptime MISPREDICT_PENALTY: Float64 = 16.0  # ~Skylake branch-recovery cycles


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
    var size = len(data)
    var parser = Parser()
    var sink: UInt64 = 0

    for _ in range(WARMUP):
        var doc = parser.parse(data)
        sink += UInt64(len(doc._tape[].elements))

    if not perf.available:
        print("==== " + name + ": perf unavailable ====")
        return

    # All four counters share one grouped region; pick the min-cycle iteration
    # and report ITS tuple so cyc/ins/br/brm are mutually consistent.
    var best_cyc = UInt64(0xFFFFFFFFFFFFFFFF)
    var best_ins = UInt64(0)
    var best_br = UInt64(0)
    var best_brm = UInt64(0)
    for _ in range(ITERS):
        perf.reset(); perf.enable()
        var doc = parser.parse(data)
        perf.disable()
        sink += UInt64(len(doc._tape[].elements))
        var c = perf.cycles()
        if c < best_cyc:
            best_cyc = c
            best_ins = perf.instructions()
            best_br = perf.branches()
            best_brm = perf.branch_misses()

    var bytes = Float64(size)
    var cyc_b = Float64(best_cyc) / bytes
    var ins_b = Float64(best_ins) / bytes
    var ipc = Float64(best_ins) / Float64(best_cyc)
    var br_b = Float64(best_br) / bytes
    var miss_rate = (Float64(best_brm) / Float64(best_br) * 100.0) if best_br > 0 else 0.0
    var mispred_share = (
        Float64(best_brm) * MISPREDICT_PENALTY / Float64(best_cyc) * 100.0
    )

    print("==== " + name + "  " + String(size) + "B ====")
    print("  cyc/B " + f2(cyc_b) + "   ins/B " + f2(ins_b) + "   IPC " + f2(ipc))
    print("  branches/B " + f2(br_b) + "   miss-rate " + f2(miss_rate)
        + "%   mispredict-cyc-share ~" + f2(mispred_share) + "%")
    print("  [misses=" + String(best_brm) + " sink=" + String(sink) + "]")
    print()


def main() raises:
    var perf = PerfGroup()
    perf.open()
    print("IPC profile  WARMUP=" + String(WARMUP) + " ITERS=" + String(ITERS)
        + " (min-cyc)  perf=" + String(perf.available)
        + "  mispredict-penalty=" + String(Int(MISPREDICT_PENALTY)) + "cyc")
    print()
    profile(String("twitter"), read_file(String("tests/fixtures/corpus/twitter.json")), perf)
    profile(String("citm_catalog"), read_file(String("tests/fixtures/corpus/citm_catalog.json")), perf)
    profile(String("canada"), read_file(String("tests/fixtures/corpus/canada.json")), perf)
    profile(String("github_events"), read_file(String("tests/fixtures/corpus/github_events.json")), perf)
    perf.close()
