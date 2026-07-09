#!/bin/bash
# build.sh — compile the kostya-shaped C++ simdjson references.
#
# Uses the simdjson single-header amalgamation checked into
# ``scripts/cpp_bench/`` so no external clone is needed on the bench host.
# Flags mirror kostya's ``common/commands.mk``: -O3 -march=native -flto.
#
# Usage:  bash scripts/kostya_bench/build.sh
#
# Outputs (next to this script):
#   kostya_ondemand
#   kostya_dom

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIMD_DIR="$(cd "$SCRIPT_DIR/../cpp_bench" && pwd)"

CXX="${CXX:-g++}"

# On NixOS (or any host where g++ isn't on PATH) fall back to a nix-provided
# toolchain — the VPS ships neither system gcc nor one inside the steam-run
# FHS sandbox, so bare "g++" fails there. This keeps the same command working
# for both dev machines (system g++) and NixOS bench hosts.
if ! command -v "$CXX" >/dev/null 2>&1; then
  if command -v nix >/dev/null 2>&1; then
    echo "no system $CXX — re-entering with nix shell nixpkgs#gcc"
    exec nix shell nixpkgs#gcc --command bash "$0" "$@"
  fi
  echo "no $CXX and no nix — cannot build" >&2
  exit 1
fi

FLAGS=(
  -std=c++20
  -O3
  -march=native
  -flto=auto
  -DNDEBUG
  -I "$SIMD_DIR"
)

echo "using CXX=$CXX"
"$CXX" --version | head -1

"$CXX" "${FLAGS[@]}" "$SCRIPT_DIR/kostya_ondemand.cpp" "$SIMD_DIR/simdjson.cpp" \
    -o "$SCRIPT_DIR/kostya_ondemand"
echo "built $SCRIPT_DIR/kostya_ondemand"

"$CXX" "${FLAGS[@]}" "$SCRIPT_DIR/kostya_dom.cpp" "$SIMD_DIR/simdjson.cpp" \
    -o "$SCRIPT_DIR/kostya_dom"
echo "built $SCRIPT_DIR/kostya_dom"

# --- Rust/serde variants -----------------------------------------------------
# We ship three: untyped (serde_json::Value), typed struct (derive), and
# custom visitor (streaming accumulator). All three are what "Rust + serde"
# can look like on this benchmark; we build all three so the caller can pick
# the honest reference for whichever tier they want to compare against.
RUST_DIR="$SCRIPT_DIR/rust"
if [[ -f "$RUST_DIR/Cargo.toml" ]]; then
  if ! command -v cargo >/dev/null 2>&1; then
    if command -v nix >/dev/null 2>&1; then
      echo "no system cargo — building Rust variants under nix shell nixpkgs#cargo nixpkgs#rustc"
      env RUSTFLAGS="-C target-cpu=native" \
        nix shell nixpkgs#cargo nixpkgs#rustc --command \
          cargo build --release --manifest-path "$RUST_DIR/Cargo.toml" >/dev/null
    else
      echo "no cargo and no nix — skipping Rust variants" >&2
    fi
  else
    env RUSTFLAGS="-C target-cpu=native" \
      cargo build --release --manifest-path "$RUST_DIR/Cargo.toml" >/dev/null
  fi
  for bin in kostya_serde_untyped kostya_serde_typed kostya_serde_custom; do
    src="$RUST_DIR/target/release/$bin"
    dst="$SCRIPT_DIR/$bin"
    if [[ -f "$src" ]]; then
      cp -f "$src" "$dst"
      echo "built $dst"
    fi
  done
fi
