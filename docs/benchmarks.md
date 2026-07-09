# Benchmarks

Two different benchmarks live in this repo. They answer different questions,
and quoting one number without saying which is misleading — so this page
names them.

## The two measurements

|                          | `bench/rest.mojo`                                     | `bench/kostya_*.mojo`                                                    |
| ------------------------ | ----------------------------------------------------- | ------------------------------------------------------------------------ |
| **Question**             | "How fast does *this* parser go on the hot path?"     | "How fast is parse-then-work, cross-language?"                           |
| **Parser lifecycle**     | One `Parser` reused across iterations via `reparse`   | Fresh parser per iteration (`parse` / `iter`)                            |
| **Work per iteration**   | Full parse — nothing done with the data               | Parse **plus** iterate `coordinates`, look up `x/y/z`, accumulate `f64`  |
| **Corpus**               | Nine files: `twitter.json`, `canada.json`, `citm_catalog.json`, four synthetic REST payloads, two API dumps | One file: 524 288 objects of `{x, y, z, name, opts}` (Kostya's schema) |
| **Contenders**           | jsonette only                                         | jsonette + C++/simdjson (OD & DOM) + Rust/serde (untyped, typed, custom) |
| **Metrics**              | GB/s, ns/op, docs/s, cyc/B, ins/B, allocs/op, peak RSS | first_time_s, min_time_s, MB/s, ns/op, cyc/B, ins/B, allocs/op          |
| **Reference**            | simdjson server convention (min-time over N iters)    | github.com/kostya/benchmarks (self-check, cross-language table)          |

`rest.mojo` characterises jsonette *internally* — good for spotting a
regression in the hot path, for judging whether an allocator change churns
more memory, for tracking `cyc/B` over commits. `kostya_*.mojo` compares
jsonette *externally* — it's the benchmark to quote when someone says
"almost the same perf as simdjson" or asks how we stack up against Rust
serde with a typed struct.

## Running

### REST-shaped, warm-parser (jsonette only)

```bash
uv sync                                                # once
uv run -- python3 scripts/download_corpus.py           # fills tests/fixtures/corpus/
uv run -- mojo run -I . -D ASSERT=none bench/rest.mojo
# with allocs/op column populated:
uv run -- mojo run -I . -D ASSERT=none -D BENCH_ALLOC_COUNT bench/rest.mojo
```

### kostya, cross-language

```bash
uv sync                                                # once
uv run -- python3 scripts/gen_kostya_json.py           # writes /tmp/1.json (deterministic)
bash scripts/kostya_bench/build.sh                     # builds C++ and Rust references
# Falls back to `nix shell nixpkgs#gcc nixpkgs#cargo nixpkgs#rustc` on NixOS
# hosts where those aren't on PATH.

# Run everything (pins to core 4 by default; override with BENCH_CORE=N):
bash scripts/kostya_bench/run.sh

# Or run one contender at a time:
scripts/kostya_bench/kostya_ondemand           # C++/simdjson On-Demand
scripts/kostya_bench/kostya_dom                # C++/simdjson DOM
scripts/kostya_bench/kostya_serde_custom       # Rust/serde custom visitor
scripts/kostya_bench/kostya_serde_typed        # Rust/serde derive
scripts/kostya_bench/kostya_serde_untyped      # Rust/serde_json::Value
uv run -- mojo run -I . -D ASSERT=none bench/kostya_ondemand.mojo
uv run -- mojo run -I . -D ASSERT=none bench/kostya_dom.mojo
# The `-D BENCH_ALLOC_COUNT` flag populates the Mojo allocs/op field:
uv run -- mojo run -I . -D ASSERT=none -D BENCH_ALLOC_COUNT bench/kostya_dom.mojo
```

`scripts/gen_kostya_json.py` is a deterministic port of Kostya's
`generate_json.rb` (RNG-seeded, so re-runs produce byte-identical output).
Sizes are configurable via `-n <count>` — the default matches the reference
(524 288 coordinates, ~110 MiB).

Every contender:
- Runs the two-string self-check on `Coordinate(2.0, 0.5, 0.25)` before
  timing, and aborts if the parse doesn't recover it.
- Prints the final `Coordinate(x=..., y=..., z=...)` at the end — every one
  must produce the same value to full `f64` precision.
- Loads the file **once**, outside every timed region.

## What the numbers mean

**`first_time_s`** — wall clock of the *first* measured iteration. This is
directly comparable to a single-shot run of Kostya's own scripts
(`analyze.rb` measures this per invocation before medianing across 10 runs).

**`min_time_s`** — minimum wall clock across `ITERS` fresh-parse iterations.
Best estimate of "the hardware could do it this fast under this
methodology" — the noise floor of the machine. This is the field to quote
when comparing implementations on the same host.

**`MB/s`** — `size / min_time_s`. Convenient for cross-checking against
published throughput numbers.

**`ns/op`** — same info in different units (per-operation latency).

**`cyc/B` / `ins/B`** — CPU cycles and retired instructions per input byte
during a fresh parse. Hardware-independent efficiency floor. Populated for
all three implementations via the same syscall (`perf_event_open`):
`bench/_metrics.mojo`'s `PerfGroup` (Mojo), `scripts/kostya_bench/kostya_perf.h`
(C++), and the `perf-event` crate wrapper in
`scripts/kostya_bench/rust/src/lib.rs` (Rust). Reports `n/a` on hosts that
refuse `perf_event_open` (paranoia level too strict, no `CAP_PERFMON`, or a
sandbox that blocks the syscall).

**`mem_base_MiB` / `mem_peak_MiB` / `mem_delta_MiB`** — memory footprint via
`VmHWM` (peak resident set size) from `/proc/self/status`. `mem_base_MiB`
is captured right after the file load and self-check, before any timed
iteration; `mem_peak_MiB` at end of `main()`. `mem_delta_MiB` is the
increase the benchmark work actually caused — matched to kostya's own
`base + increase` methodology. All three implementations read the same file
the same way (Mojo via `bench/_metrics.mojo::vm_hwm_kb`, C++ via
`kostya_perf.h::read_vm_hwm_kib`, Rust via a local helper in `lib.rs`), so
the numbers are directly comparable. On languages with a heavy runtime
baseline (e.g. `mojo run`'s JIT) the `mem_base` figure captures that
baseline; `mem_delta` isolates what the parse+walk work added on top.

**`allocs/op`** — per-parse heap allocation count, printed only when the
Mojo binary is built with `-D BENCH_ALLOC_COUNT` (jsonette-only detail; the
counter is a comptime-gated no-op otherwise). C++ / Rust don't have a
matching hook — for a rough cross-language allocation signal, read the
`mem_delta_MiB` column instead.

## Host conditions

Repeatable numbers require:
- **A pinned core.** Every runner in this repo uses `taskset -c $BENCH_CORE`.
- **A quiet host.** `scripts/audit_host.sh` gates on 1-minute load average
  (`AUDIT_THRESHOLD=0.5` by default). Bench VPSes should sit under that.
- **A fixed-frequency CPU.** Turbo boost and frequency scaling ruin
  cyc/B numbers. On Linux, `cpupower frequency-set -g performance` before
  the bench.

The published head-to-head numbers in this repo come from a bench VPS
(Xeon Platinum 8260, AVX-512). Dev-laptop numbers are internally consistent
but not verdict-grade — SIMD codegen differs enough between Ice Lake and
Skylake-SP that laptop measurements can lie about VPS behaviour.
