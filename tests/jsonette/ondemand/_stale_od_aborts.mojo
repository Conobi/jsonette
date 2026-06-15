"""Stale On-Demand handle: iterating while reparsing must abort under -D ASSERT=all.
Run by run_tests.sh as a NEGATIVE check (MUST exit non-zero with the gen message)."""
from jsonette.ondemand.reader import iter
def main() raises:
    var rdr = iter(String("[10,11,12,13,14,15]"))
    var arr = rdr.root().get_array()
    var n = 0
    while not arr.at_end():
        var v = arr.next_element()
        _ = v
        rdr.reparse(String("[0]"))   # invalidates the iterator mid-loop
        n += 1
    print("NO ABORT — iterations:", n)
