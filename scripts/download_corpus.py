#!/usr/bin/env python3
"""Download (and generate) the benchmark corpus.

Two groups:

* ``FILES`` — real-world JSON downloaded from upstream corpora. The REST-shaped
  files (API responses) are the representative workload for this parser: many
  small-to-medium object-heavy documents with repeated string keys, ints,
  bools and timestamps — not the float-heavy scientific blobs.
* ``SYNTHETIC`` — deterministically generated "list response" payloads at a few
  small sizes. REST servers are dominated by per-call fixed overhead, so the
  small bodies (~1-50 KB) probe the latency floor a server actually hits.
"""
import json
import os
import urllib.request

CORPUS_DIR = "tests/fixtures/corpus"

# Upstream real-world JSON. The REST-shaped files come from simdjson-data's
# jsonexamples; canada/twitter are kept for continuity with older benches.
SIMDJSON_DATA = "https://raw.githubusercontent.com/simdjson/simdjson-data/master/jsonexamples"
FILES = {
    # --- REST API responses (the representative workload) ---
    "twitter.json": f"{SIMDJSON_DATA}/twitter.json",
    "github_events.json": f"{SIMDJSON_DATA}/github_events.json",
    "apache_builds.json": f"{SIMDJSON_DATA}/apache_builds.json",
    "update-center.json": f"{SIMDJSON_DATA}/update-center.json",
    "instruments.json": f"{SIMDJSON_DATA}/instruments.json",
    "citm_catalog.json": f"{SIMDJSON_DATA}/citm_catalog.json",
    # --- kept for continuity / float-path coverage ---
    "canada.json": "https://raw.githubusercontent.com/miloyip/nativejson-benchmark/master/data/canada.json",
}


def _make_record(i: int) -> dict:
    """One typical REST entity: ints, strings, a bool, a timestamp, a list."""
    return {
        "id": 1000000 + i,
        "username": f"user_{i}",
        "email": f"user_{i}@example.com",
        "active": i % 3 != 0,
        "created_at": "2026-06-01T12:34:56Z",
        "score": 0.0 + (i % 100) * 1.5,
        "roles": ["member"] if i % 2 else ["member", "admin"],
        "bio": "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
    }


def _make_list_response(n: int) -> dict:
    """A paginated list response, the canonical REST decode payload."""
    return {
        "page": 1,
        "per_page": n,
        "total": n,
        "data": [_make_record(i) for i in range(n)],
    }


# name -> number of records; sizes chosen to land near 1 KB / 8 KB / 64 KB.
SYNTHETIC = {
    "rest_small.json": 3,
    "rest_medium.json": 30,
    "rest_large.json": 240,
}


def download_files():
    for name, url in FILES.items():
        path = os.path.join(CORPUS_DIR, name)
        if os.path.exists(path):
            print(f"  SKIP {name} (already exists)")
            continue
        print(f"  DOWNLOAD {name}...")
        try:
            urllib.request.urlretrieve(url, path)
        except Exception as exc:  # noqa: BLE001 — surface URL drift, keep going
            print(f"  FAIL {name}: {exc}")
            continue
        size = os.path.getsize(path)
        print(f"  OK {name} ({size:,} bytes)")


def generate_synthetic():
    for name, n in SYNTHETIC.items():
        path = os.path.join(CORPUS_DIR, name)
        if os.path.exists(path):
            print(f"  SKIP {name} (already exists)")
            continue
        # Compact (no whitespace) — what an API actually sends on the wire.
        with open(path, "w", encoding="utf-8") as f:
            json.dump(_make_list_response(n), f, separators=(",", ":"))
        size = os.path.getsize(path)
        print(f"  GEN  {name} ({size:,} bytes)")


def main():
    os.makedirs(CORPUS_DIR, exist_ok=True)
    download_files()
    generate_synthetic()


if __name__ == "__main__":
    main()
