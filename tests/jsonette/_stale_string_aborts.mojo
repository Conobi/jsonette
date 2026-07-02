"""Stale-Value serialization trap: String(v)/to_string(v) after reparse MUST abort.

Run by run_tests.sh as a NEGATIVE check (it MUST exit non-zero with the gen
message under -D ASSERT=all); NOT a member of the normal pass-list.

Regression gate for the per-Value serialization surface — String(v)/print(v)
(via Value.write_to) and the free to_string(v)/to_json(v) overloads. They reach
the tape through `_write_value(v._doc[], v._idx, w)`, so they must call
Value._check() first: a stale Value used after reparse has to be trapped by the
generation token like every other Value access (__len__, __eq__, __contains__,
items, elems, ...). Without that check a stale Value silently emits the rebuilt
tape's value at the stale index (or `null`); with it, the first serialization
below aborts with "stale Value used after reparse".
"""
from jsonette.document import parse
from jsonette.serialize.tape_writer import to_string


def main() raises:
    var doc = parse(String('{"a":1,"b":2,"c":42}'))
    var c = doc.root().field("c")  # Value at the original '42' node
    doc.reparse(String('{"x":1,"y":2,"z":99}'))  # invalidates c; bumps the gen
    # Using the stale `c` on the serialization path MUST trap under -D ASSERT=all.
    print("String(stale c) =", String(c))         # aborts here: stale Value
    print("to_string(stale c) =", to_string(c))   # unreached once the trap fires
    print("NO ABORT — serialization bypassed the gen-token")  # unreached = bug
