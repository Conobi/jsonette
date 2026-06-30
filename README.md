# jsonette

A SIMD-accelerated JSON parser for [Mojo](https://www.modular.com/mojo).

jsonette is a faithful Mojo port of the [simdjson](https://github.com/simdjson/simdjson)
two-stage structural-indexing algorithm described in Langdale & Lemire,
[*Parsing Gigabytes of JSON per Second*](https://arxiv.org/abs/1902.08318). It
classifies 64 bytes per SIMD vector pass instead of branching byte-by-byte,
targeting memory-bandwidth-limited throughput.

## Status

Early — version **0.1.0**. The library parses, validates, navigates and
serializes JSON today, with a strict RFC 8259 grammar and a passing conformance
suite. It requires **Mojo 1.0.0b2**, and the public API may still change before
1.0. No specific speed numbers or competitive comparisons are published yet.

## Features

- **SIMD two-stage parsing** — Stage 1 builds a structural index over 64-byte
  chunks; Stage 2 walks it to materialise a flat, depth-first tape.
- **Strict RFC 8259 validation** — malformed input is rejected as the tape is
  built (single pass), including full UTF-8 well-formedness checking.
- **Two read APIs** —
  - a zero-copy **DOM** (`parse(...) -> Document`, navigate via `Value`), and
  - a lazy, forward-only **On-Demand** reader under `jsonette.ondemand` for
    reading just the fields you touch.
- **Struct (de)serialization via reflection** — `dumps[T]` encodes arbitrary
  Mojo structs (and `List`/`Dict`/`Optional`) to JSON, and `to_string`/`to_json`
  round-trip a parsed `Document` back to text.

## Package name

The import package is **`jsonette`**, not `json`. Mojo's implicit stdlib imports
make a top-level `json` package collide with `std.json`, so all imports use the
`jsonette.*` prefix (e.g. `from jsonette import parse`).

## Install & build

jsonette uses [`uv`](https://docs.astral.sh/uv/) to manage the Mojo toolchain
and dependencies (pinned to `mojo-compiler==1.0.0b2`).

```bash
uv sync                              # install the toolchain + dev dependencies
uv run -- bash scripts/build.sh      # build jsonette.mojopkg
```

To use jsonette from another Mojo project, add it to the include path with
`-I /path/to/jsonette` (or depend on it via your build) and import from
`jsonette`.

## Usage

```mojo
from jsonette import parse, dumps


struct User(Copyable, Movable):
    var name: String
    var age: Int
    var active: Bool

    def __init__(out self, name: String, age: Int, active: Bool):
        self.name = name
        self.age = age
        self.active = active


def main() raises:
    # Parse a JSON String into an owning Document.
    var doc = parse(String('{"user":{"name":"Ada","age":36},"tags":["a","b"]}'))
    var root = doc.root()

    # Navigate the DOM and read typed leaves.
    var user = root.field("user")
    print(user.field("name").get_string())    # Ada
    print(user.field("age").get_int())         # 36
    print(root.field("tags").len())            # 2

    # Iterate an array.
    for tag in root.field("tags").elems():
        print(tag.get_string())                # a, then b

    # Serialize a Mojo struct to JSON via reflection.
    var u = User(name="Grace", age=44, active=True)
    print(dumps(u))                            # {"name":"Grace","age":44,"active":true}
```

`parse` accepts either a `String` or a `Span[UInt8]`. A `Document` owns its
buffers; call `doc.reparse(...)` to parse new input into the same buffers for a
warm, allocation-free reparse. `Value` getters (`get_int`, `get_uint`,
`get_float`, `get_bool`, `get_string`) raise on a type mismatch; the `as_*`
variants (`as_int`, `as_string`, ...) return an `Optional` instead. Type
predicates are `is_object`, `is_array`, `is_string`, `is_number`, `is_bool`,
`is_null`, and friends.

For lazy reads that only touch the fields you ask for, use the On-Demand reader:

```mojo
from jsonette.ondemand import iter

def main() raises:
    var rdr = iter(String('{"name":"Ada","age":36}'))
    print(rdr.root().field("name").get_string())   # Ada
```

## Running the tests

The test fixtures (the conformance vectors and the benchmark corpus) are **not**
checked into the repository, so a fresh clone must download them before the full
suite can run:

```bash
uv run -- python scripts/download_test_vectors.py   # RFC 8259 conformance vectors
uv run -- python scripts/download_corpus.py         # benchmark corpus
uv run -- bash scripts/run_tests.sh                 # run the whole suite
```

To run a single test:

```bash
uv run -- mojo run -I . -D ASSERT=all tests/jsonette/test_value.mojo
```

## References

- Geoff Langdale & Daniel Lemire, *Parsing Gigabytes of JSON per Second*,
  [arXiv:1902.08318](https://arxiv.org/abs/1902.08318) — the algorithm this
  implements.
- [simdjson](https://github.com/simdjson/simdjson) — the C++ reference
  implementation.

## License

[MIT](LICENSE).
