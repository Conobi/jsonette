#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "Removing stale .mojopkg files..."
rm -f *.mojopkg

echo "Building simdjson..."
mojo package simdjson -o simdjson.mojopkg

echo "All packages built."
ls -lh *.mojopkg
