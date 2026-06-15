"""Stale-iterator trap: iterating while reparsing must abort under -D ASSERT=all.
Run by run_tests.sh as a NEGATIVE check (it MUST exit non-zero with the gen message);
NOT a member of the normal pass-list."""
from jsonette.document import parse
def main() raises:
    var doc = parse(String("[10,11,12,13,14,15]"))
    var n = 0
    for v in doc.root().elems():
        _ = v
        doc.reparse(String("[0]"))   # invalidates the iterator mid-loop
        n += 1
    print("NO ABORT — iterations:", n)
