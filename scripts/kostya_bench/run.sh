#!/bin/bash
# run.sh — run the kostya JSON benchmark across all four contenders.
#
# Contenders (matched by methodology in each source file):
#   * jsonette DOM              (bench/kostya_dom.mojo)
#   * jsonette On-Demand        (bench/kostya_ondemand.mojo)
#   * C++/simdjson DOM          (scripts/kostya_bench/kostya_dom)
#   * C++/simdjson On-Demand    (scripts/kostya_bench/kostya_ondemand)
#
# The Mojo variants MUST be launched via ``uv run`` so the pinned Mojo
# toolchain in ``pyproject.toml`` is what compiles them (jsonette targets
# 1.0.0b2 and downgrading is a footgun).
#
# Usage (from repo root):
#   bash scripts/kostya_bench/run.sh
#
# Env:
#   BENCH_CORE=N       pin every contender to CPU N (default 4).
#   BENCH_CORPUS=PATH  override /tmp/1.json.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

CORE="${BENCH_CORE:-4}"
CORPUS="${BENCH_CORPUS:-/tmp/1.json}"

if [[ ! -f "$CORPUS" ]]; then
  echo "no corpus at $CORPUS — generating (524288 coordinates, seed=default)"
  uv run -- python3 scripts/gen_kostya_json.py -o "$CORPUS"
fi
size_mib="$(du -m "$CORPUS" | awk '{print $1}')"
echo "corpus: $CORPUS  (~${size_mib} MiB)"
echo "core:   $CORE"
echo

# Build the C++ references if they are missing. When they are already there
# (e.g. the caller ran build.sh via ``nix shell nixpkgs#gcc``) we skip the
# rebuild — the runner may be invoked inside a steam-run FHS sandbox where
# gcc is unavailable, and we do not want that missing tool to abort the
# whole benchmark.
if [[ ! -x scripts/kostya_bench/kostya_ondemand || ! -x scripts/kostya_bench/kostya_dom ]]; then
  echo "building C++ references (need g++ on PATH or nix)"
  bash scripts/kostya_bench/build.sh
fi

run_one() {
  local label="$1"; shift
  echo "----- $label -----"
  taskset -c "$CORE" "$@"
  echo
}

# Order: cheapest to warmest — C++/Rust first (warm the disk cache), then Mojo.
run_one "C++/simdjson On-Demand"   scripts/kostya_bench/kostya_ondemand
run_one "C++/simdjson DOM"         scripts/kostya_bench/kostya_dom
for bin in kostya_serde_custom kostya_serde_typed kostya_serde_untyped; do
  path="scripts/kostya_bench/$bin"
  [[ -x "$path" ]] || continue
  case "$bin" in
    kostya_serde_custom)  label="Rust/serde Custom"  ;;
    kostya_serde_typed)   label="Rust/serde Typed"   ;;
    kostya_serde_untyped) label="Rust/serde Untyped" ;;
  esac
  run_one "$label" "$path"
done
run_one "jsonette On-Demand"       uv run -- mojo run -I . -D ASSERT=none bench/kostya_ondemand.mojo
run_one "jsonette DOM"             uv run -- mojo run -I . -D ASSERT=none bench/kostya_dom.mojo

echo "=== done ==="
