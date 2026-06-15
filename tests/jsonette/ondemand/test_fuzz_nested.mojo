"""On-Demand M2 — deterministic fuzzer over random nested object/array paths.

Builds a random nesting chain (object and array levels, each with a sibling that
is skipped — sometimes itself a container, to exercise the depth-aware
`_skip_value` over container siblings) down to a target integer, then navigates
root -> target via `get_object`/`field` and `get_array`/`next_element` and
checks the leaf. Random depths/shapes across many iterations — the "fuzzers find
nothing new" signal for nested navigation. Deterministic (seeded LCG).
"""

from std.memory import bitcast
from std.testing import assert_equal
from jsonette.ondemand.reader import iter


comptime ITERS: Int = 1200


struct _Rng(Copyable, Movable):
    var state: UInt64

    def __init__(out self, seed: UInt64):
        self.state = seed

    def next(mut self) -> UInt64:
        self.state = self.state * 6364136223846793005 + 1442695040888963407
        return self.state


def _noise(mut rng: _Rng) -> String:
    """A random valid JSON fragment used as a skipped sibling (incl. containers)."""
    var k = rng.next() % 4
    if k == 0:
        return String(bitcast[DType.int64](rng.next()))  # int
    elif k == 1:
        return String('"nz"')  # string
    elif k == 2:
        return String("[1,2]")  # array sibling (depth-aware skip)
    else:
        return String('{"q":3}')  # object sibling (depth-aware skip)


def _check_one(mut rng: _Rng) raises:
    var depth = 1 + Int(rng.next() % 4)  # 1..4 nesting levels
    var target = bitcast[DType.int64](rng.next())  # full Int64 range

    # Build innermost -> out, recording each level's kind (True = object).
    var inner = String(target)
    var is_obj = List[Bool]()
    for _ in range(depth):
        var obj = rng.next() % 2 == 0
        is_obj.append(obj)
        if obj:
            inner = '{"nz":' + _noise(rng) + ',"p":' + inner + "}"
        else:
            inner = "[" + _noise(rng) + "," + inner + "]"  # target at index 1
    var json = '{"root":' + inner + "}"

    var data = List[UInt8]()
    for b in json.as_bytes():
        data.append(b)
    var rdr = iter(data)

    # Navigate root -> target: levels are recorded innermost-first, so walk them
    # in reverse (outermost first) starting from the "root" field.
    var v = rdr.root().field(String("root"))
    for i in range(depth - 1, -1, -1):
        if is_obj[i]:
            v = v.get_object().field(String("p"))
        else:
            var arr = v.get_array()
            _ = arr.next_element()  # skip the index-0 noise sibling
            v = arr.next_element()  # index 1 = the nested value / target
    assert_equal(v.get_int(), target, "nested target mismatch in: " + json)


def main() raises:
    var rng = _Rng(0xD1B54A32D192ED03)
    for _ in range(ITERS):
        _check_one(rng)
    print("test_fuzz_nested: all passed (" + String(ITERS) + " random nested paths)")
