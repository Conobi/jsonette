"""Generation-token: correct post-reparse usage does not false-abort under ASSERT=all.

A `Value` captures the Document's generation; `Value._check()` debug_asserts it
matches on every access, trapping a stale view used across a `reparse`. Because
debug_assert aborts and the suite runs with -D ASSERT=all, this registered test
exercises the CORRECT pattern (obtain fresh Values from root() AFTER reparse) and
asserts they read the new data with no false abort.

MANUAL stale-view trap check (NOT run by the suite -- it aborts by design):
    var doc = parse(String('{"k":1}'))
    var v = doc.root().field("k")     # gen 0
    doc.reparse(String('{"k":2}'))    # gen 1; v is now stale
    _ = v.get_uint()                  # aborts: "stale Value used after reparse"
"""
from std.testing import assert_equal
from jsonette.document import parse


def test_fresh_values_after_reparse() raises:
    var doc = parse(String('{"k":1}'))
    assert_equal(doc.root().field("k").get_uint(), UInt64(1))
    doc.reparse(String('{"k":2}'))
    # Fresh Values from root() carry the new gen -> no false abort, read new data.
    assert_equal(doc.root().field("k").get_uint(), UInt64(2))
    doc.reparse(String('{"k":3}'))
    assert_equal(doc.root().field("k").get_uint(), UInt64(3))


def main() raises:
    test_fresh_values_after_reparse()
    print("test_gen_token: all passed")
