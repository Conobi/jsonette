#!/usr/bin/env bash
# Head-to-head VPS runner: ours (jsonette) vs theirs (ehsanmok/json
# native CPU parser), both compiled with the SAME uv-pinned Mojo 1.0.0b1
# toolchain, interleaved A/B, pinned to one core, after a host-load audit.
# Invoke INSIDE the steam-run FHS sandbox (provides /lib64 dynamic linker):
#   export NIXPKGS_ALLOW_UNFREE=1
#   nix run --impure nixpkgs#steam-run -- bash bench/run_h2h_vps.sh
set -euo pipefail

OURS_DIR="$HOME/jsonette"
THEIRS_INC="$HOME/ehsanmok-json"
CORE="${BENCH_CORE:-4}"
ROUNDS="${BENCH_ROUNDS:-3}"

cd "$OURS_DIR"

echo "=== host audit (gate) ==="
bash scripts/audit_host.sh || { echo "host busy — aborting"; exit 1; }

echo "=== uv sync (toolchain: Mojo 1.0.0b1) ==="
uv sync >/dev/null 2>&1
echo "uv sync done"

run_ours() {
  taskset -c "$CORE" uv run -- mojo run -I . -D ASSERT=none bench/h2h_ours.mojo 2>/dev/null | grep -E '^  ours'
}
run_theirs() {
  taskset -c "$CORE" uv run -- mojo run -I . -I "$THEIRS_INC" -D ASSERT=none bench/h2h_theirs.mojo 2>/dev/null | grep -E '^  theirs'
}

echo "=== warm JIT caches (untimed) ==="
run_ours   >/dev/null 2>&1 || true
run_theirs >/dev/null 2>&1 || true

echo "=== interleaved A/B (${ROUNDS} rounds, core ${CORE}) ==="
for r in $(seq 1 "$ROUNDS"); do
  echo "--- round $r ---"
  run_ours
  run_theirs
done
echo "=== done ==="
