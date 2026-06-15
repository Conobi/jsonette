#!/usr/bin/env python3
"""Independent invalidity oracle for the DOM reject corpus.

`tests/conformance/test_reject_corpus.mojo` pins which JSONTestSuite `n_*`
vectors the permissive DOM `parse()` wrongly ACCEPTS (the "known gaps"). That
test establishes *what jsonette does*; this script establishes *what the truth
is*, using an oracle that shares none of jsonette's code: Python's `json.loads`.

It confirms every `n_*` vector is genuinely invalid (so each accepted gap is a
real bug, not a JSONTestSuite quirk) and surfaces the only disagreements between
`json.loads` and RFC 8259 — `NaN` / `Infinity` / `-Infinity`, which Python
accepts as extensions but jsonette correctly rejects (they land in the rejected
123, never in the gaps).

Run from anywhere:  python3 tests/oracle/parse_reject_oracle.py
"""
import glob
import json
import os

VECTOR_DIR = os.path.join(os.path.dirname(__file__), "..", "fixtures", "test_vectors")

# Vectors that are RFC-invalid but which `json.loads` accepts as Python
# extensions. jsonette rejects these (RFC-correct), so they are NOT gaps.
PY_EXTENSIONS = {
    "n_number_NaN.json",
    "n_number_infinity.json",
    "n_number_minus_infinity.json",
}


def main() -> int:
    paths = sorted(glob.glob(os.path.join(VECTOR_DIR, "n_*.json")))
    loads_accepts = []
    for p in paths:
        raw = open(p, "rb").read()
        try:
            json.loads(raw)
            loads_accepts.append(os.path.basename(p))
        except Exception:
            pass

    print(f"n_* (RFC must-reject) vectors: {len(paths)}")
    print(f"json.loads accepts          : {len(loads_accepts)}")
    for n in loads_accepts:
        tag = "expected Python extension" if n in PY_EXTENSIONS else "UNEXPECTED"
        print(f"  {n}  [{tag}]")

    unexpected = set(loads_accepts) - PY_EXTENSIONS
    if unexpected:
        print("\nFAIL: json.loads accepted a vector that is not a known Python "
              f"extension: {sorted(unexpected)}")
        return 1
    print("\nOK: every n_* vector is invalid per json.loads except the documented "
          "Python extensions. So every vector the DOM accepts is a genuine gap.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
