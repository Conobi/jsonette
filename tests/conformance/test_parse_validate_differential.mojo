"""Differential lock: the strict tape builder and the strict validator must agree.

After the touch-once change, `parse()` and `Parser.validate()` are INDEPENDENT
code paths that both implement strict RFC 8259:

  * `parse()` -> `build_tape` walks the structural index as a grammar state machine
    AND materialises the tape in one pass.
  * `Parser.validate()` -> `_validate_document` is a separate recursive-descent walk
    that builds no tape and is gated against the Python `json.loads` oracle
    (tests/jsonette/ondemand/test_validate_conformance.mojo).

This test asserts the two paths reach the SAME accept/reject verdict on every
JSONTestSuite vector (188 must-reject + 95 must-accept + the rest) and on the
large real-world corpora. A state-machine transcription slip that over- or
under-rejects in the builder but not the validator (or vice versa) fails here —
so the proven validator stands guard over the hand-written builder grammar.

Reads from disk; assumes cwd = repo root (run_tests.sh does `cd`).
"""
from std.os import listdir
from jsonette.document import parse
from jsonette.parser import Parser


def _read(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var b = f.read_bytes()
    f.close()
    return b^


def _parse_accepts(data: List[UInt8]) raises -> Bool:
    try:
        _ = parse(data)
        return True
    except:
        return False


def _validate_accepts(data: List[UInt8]) raises -> Bool:
    var p = Parser()
    try:
        p.validate(data)
        return True
    except:
        return False


def main() raises:
    var vectors = String("tests/fixtures/test_vectors")
    var total = 0
    var mismatches = 0
    var entries = listdir(vectors)
    for i in range(len(entries)):
        var name = entries[i]
        if not name.endswith(".json"):
            continue
        var data = _read(vectors + "/" + name)
        var pa = _parse_accepts(data)
        var va = _validate_accepts(data)
        total += 1
        if pa != va:
            print("MISMATCH:", name, "parse-accepts=", pa, "validate-accepts=", va)
            mismatches += 1

    # The large real-world corpora are all valid: both paths must accept.
    var corpus = String("tests/fixtures/corpus")
    var big = List[String]()
    big.append(String("twitter.json"))
    big.append(String("canada.json"))
    big.append(String("citm_catalog.json"))
    for i in range(len(big)):
        var data = _read(corpus + "/" + big[i])
        var pa = _parse_accepts(data)
        var va = _validate_accepts(data)
        total += 1
        if pa != va or not pa:
            print("MISMATCH (corpus):", big[i], "parse-accepts=", pa, "validate-accepts=", va)
            mismatches += 1

    print("parse-vs-validate differential:", total, "inputs,", mismatches, "mismatches")
    if mismatches != 0:
        raise (
            "parse() and Parser.validate() disagree on "
            + String(mismatches)
            + " inputs — the builder grammar diverged from the validator oracle"
        )
