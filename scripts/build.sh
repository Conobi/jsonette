#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "Removing stale package files..."
rm -f *.mojoc *.mojopkg

echo "Building jsonette..."
mojo precompile jsonette -o jsonette.mojoc

echo "All packages built."
ls -lh *.mojoc
