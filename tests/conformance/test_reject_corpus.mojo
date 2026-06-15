"""Reject-corpus characterization gate: how permissive is the DOM `parse()` today.

Every `n_*` vector in the JSONTestSuite fixtures is RFC 8259 *must-reject*. A
strict parser rejects all 188 — and `parse()` now does: Stage 2 (`build_tape`) is a
strict RFC-8259 grammar state machine that rejects malformed input as it builds the
tape (a single pass, each leaf parsed once). This test holds that line, so:

  * `EXPECTED_GAPS` is 0 — every must-reject vector is rejected, and
  * any regression that makes `parse()` accept an invalid vector again (e.g. a
    future touch-once inline-grammar migration that drops a check) FAILS the suite
    at once. Should the count ever change, the gate prints the offending vectors
    (`KNOWN-GAP:`) so the regression is named, not silent.

The AUTHORITATIVE invalidity oracle is Python `json.loads`
(see `tests/oracle/parse_reject_oracle.py`): it rejects all of these EXCEPT
`NaN`/`Infinity`/`-Infinity` (Python extensions), which jsonette also rejects
(RFC-correct) — so those three sit in the rejected 123, not in the gaps.

Reads vectors from disk; assumes cwd = repo root (`run_tests.sh` does `cd`, and the
documented single-test invocation runs `-I .` from the root).
"""
from std.os import listdir
from jsonette.document import parse


comptime EXPECTED_TOTAL = 188
comptime EXPECTED_GAPS = 0  # parse() now rejects every must-reject vector


def _accepts(path: String) raises -> Bool:
    """True iff `parse()` returns normally on the file's bytes (else it raised)."""
    var f = open(path, "r")
    var b = f.read_bytes()
    f.close()
    try:
        _ = parse(b)
        return True
    except:
        return False


def main() raises:
    var vector_dir = String("tests/fixtures/test_vectors")
    var entries = listdir(vector_dir)
    var total = 0
    var gaps = 0
    for i in range(len(entries)):
        var name = entries[i]
        if not (name.startswith("n_") and name.endswith(".json")):
            continue
        total += 1
        if _accepts(vector_dir + "/" + name):
            print("KNOWN-GAP:", name)
            gaps += 1
    var rejected = total - gaps
    print("reject-corpus: total", total, "rejected", rejected, "known-gaps", gaps)
    if total != EXPECTED_TOTAL:
        raise (
            "corpus size changed ("
            + String(total)
            + " != "
            + String(EXPECTED_TOTAL)
            + "); classify the new vectors and update EXPECTED_TOTAL"
        )
    if gaps != EXPECTED_GAPS:
        raise (
            "DOM permissiveness changed: known-gaps "
            + String(gaps)
            + " != "
            + String(EXPECTED_GAPS)
            + " — if a strictness fix closed gaps, LOWER EXPECTED_GAPS (good!);"
            + " if it rose, a regression made parse() accept new invalid input"
        )
    print(
        "test_reject_corpus:",
        rejected,
        "/",
        total,
        "correctly rejected;",
        gaps,
        "known gaps pinned",
    )
