"""On-Demand M0 — deterministic differential fuzzer over random flat objects.

Generates many random flat top-level objects (random field counts, key spellings,
and string/integer values), serialises each to JSON, parses it lazily via
`Parser.iter`, and asserts every field reads back exactly the value that was
generated. This exercises `find_field` + `get_string`/`get_int` across far more
shapes than the hand-written cases — the "fuzzers find nothing new" convergence
signal. Fully deterministic (seeded LCG) so failures reproduce.

Keys are made unique within each object (`k<i>_<letters>`) so `find_field`'s
first-match has a single correct target. Integer values span the full Int64 range
(including INT64_MIN), so the round-trip stresses the number path's hard cases.
"""

from std.memory import bitcast
from std.testing import assert_equal
from jsonette.parser import Parser


comptime ITERS: Int = 1500


struct _Rng(Copyable, Movable):
    """A tiny seeded LCG (deterministic, reproducible)."""

    var state: UInt64

    def __init__(out self, seed: UInt64):
        self.state = seed

    def next(mut self) -> UInt64:
        self.state = self.state * 6364136223846793005 + 1442695040888963407
        return self.state


def _letters(mut rng: _Rng, count: Int) -> String:
    """Build a String of `count` lowercase ASCII letters from the RNG."""
    var out = String("")
    for _ in range(count):
        out += chr(Int(97 + Int(rng.next() % 26)))
    return out


def _check_one(mut rng: _Rng) raises:
    """Generate one random flat object and verify every field round-trips."""
    var nfields = 1 + Int(rng.next() % 6)  # 1..6 fields
    var keys = List[String]()
    var is_str = List[Bool]()
    var svals = List[String]()
    var ivals = List[Int64]()

    var json = String("{")
    for i in range(nfields):
        if i > 0:
            json += ","
        var key = String("k") + String(i) + "_" + _letters(rng, 1 + Int(rng.next() % 4))
        keys.append(key)
        json += '"' + key + '":'
        if rng.next() % 2 == 0:
            var sval = _letters(rng, Int(rng.next() % 10))  # 0..9 letters
            is_str.append(True); svals.append(sval); ivals.append(Int64(0))
            json += '"' + sval + '"'
        else:
            var iv = bitcast[DType.int64](rng.next())  # full Int64 range
            is_str.append(False); svals.append(String("")); ivals.append(iv)
            json += String(iv)
    json += "}"

    var data = List[UInt8]()
    for b in json.as_bytes():
        data.append(b)
    var parser = Parser()
    var root = parser.iter(data)
    for i in range(nfields):
        if is_str[i]:
            assert_equal(
                root.find_field(keys[i]).get_string(), svals[i],
                "string field mismatch in: " + json,
            )
        else:
            assert_equal(
                root.find_field(keys[i]).get_int(), ivals[i],
                "int field mismatch in: " + json,
            )


def main() raises:
    var rng = _Rng(0x9E3779B97F4A7C15)
    for _ in range(ITERS):
        _check_one(rng)
    print("test_fuzz_flat: all passed (" + String(ITERS) + " random flat objects)")
