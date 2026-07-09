#!/usr/bin/env python3
"""Deterministic generator for the kostya JSON benchmark corpus.

Mirrors ``json/generate_json.rb`` from https://github.com/kostya/benchmarks/
but seeds the RNG so the file is byte-identical across runs (essential for
verdict-grade comparisons). The default output size (524_288 coordinates)
matches the canonical kostya element count and produces roughly ~110 MiB
of JSON with the Python indent-2 encoding (the Ruby upstream generator lands
higher — around 200 MiB — because ``JSON.pretty_generate`` inserts more
whitespace; per-byte throughput is unaffected by that difference).

Usage:
    uv run -- python3 scripts/gen_kostya_json.py                 # /tmp/1.json, 524288
    uv run -- python3 scripts/gen_kostya_json.py -o small.json -n 1000

The schema per element is intentionally the reference schema (x, y, z, name,
opts): the ``name`` string and the nested ``opts`` object are what make the
benchmark distinguish structural-index cost from selective-field cost.
"""

from __future__ import annotations

import argparse
import json
import random
import string
import sys
from pathlib import Path


def build_corpus(count: int, seed: int) -> dict:
    """Return the top-level document dict for ``count`` coordinates."""
    rng = random.Random(seed)
    letters = string.ascii_lowercase
    coords = []
    for _ in range(count):
        name = "".join(rng.sample(letters, 6)) + " " + str(rng.randrange(10_000))
        coords.append({
            "x": rng.random() * -10e-30,
            "y": rng.random() * 10e30,
            "z": rng.random(),
            "name": name,
            "opts": {"1": [1, True]},
        })
    return {"coordinates": coords, "info": "some info"}


def main() -> int:
    """Parse args, build the corpus, dump it pretty-printed to disk."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("-o", "--out", default="/tmp/1.json", help="Output path.")
    ap.add_argument("-n", "--count", type=int, default=524_288,
                    help="Number of coordinate objects (kostya default: 524288).")
    ap.add_argument("-s", "--seed", type=int, default=0xC0FFEE,
                    help="RNG seed for byte-identical reproducibility.")
    args = ap.parse_args()

    doc = build_corpus(args.count, args.seed)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2)
    size = out.stat().st_size
    print(f"wrote {out} ({size / (1024 * 1024):.1f} MiB, {args.count} coordinates, seed={args.seed})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
