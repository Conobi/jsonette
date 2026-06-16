#!/usr/bin/env bash
# On-Demand vs DOM perf bench on the VPS, verdict-grade conditions: same
# uv-pinned Mojo 1.0.0b1 toolchain, pinned to one core, gated on a host-load
# audit so a noisy neighbour can't pollute the timing. Measures ins/B + cyc/B
# for DOM parse vs OD iter()-floor vs OD selective(2-3) vs OD full-walk.
#
# Invoke INSIDE the steam-run FHS sandbox (provides /lib64 dynamic linker):
#   export NIXPKGS_ALLOW_UNFREE=1
#   nix run --impure nixpkgs#steam-run -- bash bench/run_ondemand_vps.sh
set -euo pipefail

OURS_DIR="$HOME/jsonette"
CORE="${BENCH_CORE:-4}"
ROUNDS="${BENCH_ROUNDS:-2}"

cd "$OURS_DIR"

echo "=== host audit (gate) ==="
bash scripts/audit_host.sh || { echo "host busy — aborting"; exit 1; }

echo "=== uv sync (toolchain: Mojo 1.0.0b1) ==="
uv sync >/dev/null 2>&1
echo "uv sync done"

run() {
  taskset -c "$CORE" uv run -- mojo run -I . -D ASSERT=none bench/profile_ondemand.mojo
}

echo "=== warm JIT caches (untimed) ==="
run >/dev/null 2>&1 || true

echo "=== perf rounds (${ROUNDS}x, core ${CORE}) ==="
for r in $(seq 1 "$ROUNDS"); do
  echo "--- round $r ---"
  run
done

echo "=== done ==="
