#!/usr/bin/env bash
# REST-workload decode bench on the VPS, under controlled conditions:
# same uv-pinned Mojo 1.0.0b1 toolchain, pinned to one core, gated on a
# host-load audit so a noisy neighbour can't pollute the timing.
#
# Two invocations of bench/rest.mojo per round:
#   1. counter compiled OUT  -> GB/s, ns/op, docs/s, cyc/byte, ins/byte
#      (zero alloc-counter overhead in the timed region)
#   2. counter compiled IN   -> allocs/op column reads true per-call allocs
#      (confirms the zero-alloc-per-warm-parse contract on real hardware)
#
# Invoke INSIDE the steam-run FHS sandbox (provides /lib64 dynamic linker),
# exactly like run_h2h_vps.sh:
#   export NIXPKGS_ALLOW_UNFREE=1
#   nix run --impure nixpkgs#steam-run -- bash bench/run_rest_vps.sh
set -euo pipefail

OURS_DIR="$HOME/json-simd-mojo"
CORE="${BENCH_CORE:-4}"
ROUNDS="${BENCH_ROUNDS:-3}"

cd "$OURS_DIR"

echo "=== host audit (gate) ==="
bash scripts/audit_host.sh || { echo "host busy — aborting"; exit 1; }

echo "=== uv sync (toolchain: Mojo 1.0.0b1) ==="
uv sync >/dev/null 2>&1
echo "uv sync done"

run_perf() {
  # Timing + cycles/instructions; alloc counter compiled out (zero overhead).
  taskset -c "$CORE" uv run -- mojo run -I . -D ASSERT=none bench/rest.mojo
}
run_alloc() {
  # Same harness with the alloc counter compiled in; only the alloc column
  # is authoritative here (the counter syscalls perturb wall-clock slightly).
  taskset -c "$CORE" uv run -- mojo run -I . -D ASSERT=none \
    -D BENCH_ALLOC_COUNT bench/rest.mojo
}

echo "=== warm JIT caches (untimed) ==="
run_perf  >/dev/null 2>&1 || true

echo "=== perf/timing rounds (${ROUNDS}x, core ${CORE}) ==="
for r in $(seq 1 "$ROUNDS"); do
  echo "--- round $r ---"
  run_perf
done

echo "=== alloc verification pass (core ${CORE}) ==="
run_alloc

echo "=== done ==="
