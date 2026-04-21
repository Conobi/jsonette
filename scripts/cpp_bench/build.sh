#!/bin/bash
# Build C++ simdjson benchmark for comparison
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
g++ -O3 -mavx2 -I "$SCRIPT_DIR" "$SCRIPT_DIR/bench.cpp" "$SCRIPT_DIR/simdjson.cpp" -o "$SCRIPT_DIR/bench"
echo "Built: $SCRIPT_DIR/bench"
