"""Generative property test for the round-trip JSON encoder.

A deterministic, fixed-seed generator builds many random *valid* JSON
documents and asserts that each survives `parse -> to_string -> parse`
with a byte-identical tape. This reaches escaping / number / structure edge
combinations the fixed corpus and hand-written vectors cannot enumerate.

Invariants this harness relies on:

- Every generated document is syntactically valid JSON, so the first parse
  never raises. A raised parse is a *generator* bug, not an encoder bug.
- If `tapes_equal` is ever false, the encoder lost or corrupted information
  on the way out -- a real bug. We never weaken the assertion to make it pass.

Determinism comes from a single `seed(...)` call in `main`; no wall-clock or
entropy seeding is used, so a failure is reproducible from the printed input.
"""
from std.random import seed, random_ui64
from std.math import isfinite
from std.memory import bitcast
from std.testing import assert_true
from jsonette.parser import Parser
from jsonette.serialize.tape_writer import to_string
from jsonette.serialize.roundtrip import tapes_equal


comptime _SEED = 0x5152534A  # "RSJ" + marker; any fixed constant works.
comptime _ITERATIONS = 2000


def _pick(n: UInt64) -> Int:
    """Return a uniform Int in `[0, n)` (n must be >= 1)."""
    return Int(random_ui64(0, n - 1))


def gen_json_string() -> String:
    """Build a valid, quoted, escaped JSON string literal of length 0..8.

    Each character is drawn from a set chosen to stress the escaper: plain
    letters and spaces, the two backslash-escaped specials (`"` and `\\`),
    a forward slash, the five short control escapes plus a `\\u00XX` form,
    and a raw 2-byte UTF-8 sequence (U+00E9, 'e' acute). Every alternative
    appends *already-valid* JSON string content, so the surrounding quotes
    always yield a parseable literal.
    """
    var out = String('"')
    var length = _pick(9)  # 0..8 inclusive
    for _ in range(length):
        var kind = _pick(12)
        if kind == 0:
            out += "a"
        elif kind == 1:
            out += "Z"
        elif kind == 2:
            out += " "
        elif kind == 3:
            out += "\\\""  # an escaped double quote inside the literal
        elif kind == 4:
            out += "\\\\"  # an escaped backslash inside the literal
        elif kind == 5:
            out += "/"
        elif kind == 6:
            out += "\\n"
        elif kind == 7:
            out += "\\t"
        elif kind == 8:
            out += "\\r"
        elif kind == 9:
            out += "\\b"
        elif kind == 10:
            # A control byte spelled as a \u00XX escape (here ).
            out += "\\u0001"
        else:
            # Raw 2-byte UTF-8 for U+00E9 (bytes 0xC3 0xA9); valid string content.
            out += chr(0xE9)
    out += '"'
    return out^


def gen_int() -> String:
    """Emit decimal text for a random integer the parser accepts.

    Mixes small magnitudes with values near the Int64/UInt64 bounds and
    sometimes negates (within Int64 range, so the value stays representable).
    """
    var bits = random_ui64(0, 0xFFFFFFFFFFFFFFFF)
    var shape = _pick(4)
    if shape == 0:
        # Small unsigned, 0..999.
        return String(bits % 1000)
    elif shape == 1:
        # Small signed, -999..-1.
        return String("-") + String((bits % 999) + 1)
    elif shape == 2:
        # Full-width unsigned, up to UInt64 max.
        return String(bits)
    else:
        # Signed near Int64 range: clamp magnitude into [0, Int64.max].
        var mag = bits & 0x7FFFFFFFFFFFFFFF
        if random_ui64(0, 1) == 1:
            return String("-") + String(mag)
        return String(mag)


def gen_float() -> String:
    """Emit decimal text for a random *finite* Float64.

    Random bits are reinterpreted as a Float64 and rejected until finite
    (NaN/Inf have no JSON form). `String(f)` produces the stdlib shortest
    round-trip form, so the generated input is always parseable.
    """
    while True:
        var bits = random_ui64(0, 0xFFFFFFFFFFFFFFFF)
        var f = Float64(bitcast[DType.float64](SIMD[DType.uint64, 1](bits)))
        if isfinite(f):
            return String(f)


def gen_value(depth_budget: Int) -> String:
    """Return a valid JSON fragment, recursing up to `depth_budget` deep.

    At zero budget only scalars are produced, guaranteeing termination.
    Otherwise a kind is chosen uniformly across object / array / string /
    int / float / bool / null.
    """
    if depth_budget <= 0:
        var leaf = _pick(5)
        if leaf == 0:
            return gen_json_string()
        elif leaf == 1:
            return gen_int()
        elif leaf == 2:
            return gen_float()
        elif leaf == 3:
            return String("true") if random_ui64(0, 1) == 1 else String("false")
        else:
            return String("null")

    var kind = _pick(7)
    if kind == 0:
        # object: { 0..3 members }
        var out = String("{")
        var n = _pick(4)  # 0..3
        for i in range(n):
            if i > 0:
                out += ","
            out += gen_json_string()
            out += ":"
            out += gen_value(depth_budget - 1)
        out += "}"
        return out^
    elif kind == 1:
        # array: [ 0..3 elements ]
        var out = String("[")
        var n = _pick(4)  # 0..3
        for i in range(n):
            if i > 0:
                out += ","
            out += gen_value(depth_budget - 1)
        out += "]"
        return out^
    elif kind == 2:
        return gen_json_string()
    elif kind == 3:
        return gen_int()
    elif kind == 4:
        return gen_float()
    elif kind == 5:
        return String("true") if random_ui64(0, 1) == 1 else String("false")
    else:
        return String("null")


def _fuzz_one(s: String) raises:
    """Assert `s` round-trips: parse, re-emit, re-parse, compare tapes."""
    var b = List[UInt8]()
    for x in s.as_bytes():
        b.append(x)
    var p1 = Parser()
    var d1 = p1.parse(b)
    var emitted = to_string(d1)
    var eb = List[UInt8]()
    for x in emitted.as_bytes():
        eb.append(x)
    var p2 = Parser()
    var d2 = p2.parse(eb)
    assert_true(
        tapes_equal(d1, d2),
        msg=String("fuzz round-trip mismatch on input: ") + s
        + String(" | emitted: ") + emitted,
    )


def main() raises:
    seed(_SEED)
    for _ in range(_ITERATIONS):
        _fuzz_one(gen_value(5))
    print("test_fuzz_roundtrip: all passed")
