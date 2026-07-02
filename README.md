# jsonette

A SIMD-accelerated JSON parser for [Mojo](https://www.modular.com/mojo).

jsonette is a faithful Mojo port of the [simdjson](https://github.com/simdjson/simdjson)
two-stage structural-indexing algorithm described in Langdale & Lemire,
[*Parsing Gigabytes of JSON per Second*](https://arxiv.org/abs/1902.08318). It
classifies 64 bytes per SIMD vector pass instead of branching byte-by-byte,
targeting memory-bandwidth-limited throughput.

## Status

Early — version **0.1.0**. jsonette parses, validates, navigates and serializes
JSON today, with a strict RFC 8259 grammar and a passing conformance suite. It
pairs a **Python-like surface** — indexing, iteration, `len` / `in` / `==`,
`print` — with a **zero-copy core**: the pleasant syntax compiles to tape-index
arithmetic with no per-node allocation. It requires **Mojo 1.0.0b2**, and the
public API may still change before 1.0. No specific speed numbers are published
yet.

## Features

- **SIMD two-stage parsing** — Stage 1 builds a structural index over 64-byte
  chunks; Stage 2 walks it to materialise a flat, depth-first tape.
- **Strict RFC 8259 validation** — malformed input is rejected as the tape is
  built (single pass), including full UTF-8 well-formedness checking.
- **Pythonic, zero-copy DOM** — `parse(s)` returns an owning `Document`; navigate
  it (or a borrowing `Value`) with `v["key"]` / `v[i]`, `for x in array`,
  `len(v)`, `"key" in v`, `v == "text"` (non-allocating), and `print(v)` — none
  of which allocate per node. Typed leaves via `get_int` / `get_string` / … (raise
  on mismatch) or `as_int` / `as_string` / … (return `Optional`); `v.get(key)`
  for a pythonic optional lookup.
- **Three ways to read, one to build** —
  - zero-copy **DOM** — `parse(...) -> Document`, navigate a borrowing `Value`;
  - **typed** — `decode[T](...)` deserialises straight into an owned struct, and
    `dumps(x)` encodes a struct (or `List`/`Dict`/`Optional`) via reflection;
  - **owned untyped** — `loads(...) -> JsonValue`, an owned, origin-free tree you
    can store, return and mutate; build one with `JsonValue.object()` / `append` /
    `[]=` and serialize it with `dumps`;
  - lazy, forward-only **On-Demand** under `jsonette.ondemand` for reading just
    the fields you touch.
- **Serialize any value** — `to_string(v)` / `to_json[pretty=True](v)` emit a whole
  `Document` or any sub-tree; `print(v)` / `String(v)` work on any node.

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

### Parse and navigate — zero-copy, Python-like

```mojo
from jsonette import parse

def main() raises:
    var doc = parse(String('{"user":{"name":"Ada","age":36},"scores":[95,87]}'))

    # Index like a dict/list — no `.root()` hop, no lifetime annotations.
    print(doc["user"]["name"].get_string())     # Ada
    print(doc["scores"][0].get_int())            # 95

    # Python operators — each is a zero-allocation tape read.
    print(len(doc["scores"]))                    # 2
    print("user" in doc)                         # True
    if doc["user"]["name"] == "Ada":             # non-allocating string compare
        print("hello, Ada")
    for score in doc["scores"]:                  # iterate an array
        print(score.get_int())                   # 95, then 87
    for key, value in doc["user"].items():       # iterate an object
        print(key)                               # name, then age
    print(doc["user"])                           # {"name":"Ada","age":36}

    # Optional access — None on a missing key or wrong type, no exception.
    var maybe_age = doc["user"].get("age")       # Optional[Value]
```

Leaves come out typed: `get_int` / `get_uint` / `get_float` / `get_bool` /
`get_string` raise on a type mismatch, while `as_int` / `as_string` / … return an
`Optional`. `parse` takes a `String` or a `Span[UInt8]`, and a `Document` owns its
buffers — call `doc.reparse(...)` to parse new input into the same buffers for a
warm, allocation-free reparse.

### Decode into a struct, or encode one

```mojo
from jsonette import decode, dumps, JsonDeserializable

struct User(Copyable, Movable, Defaultable, JsonDeserializable):
    var name: String
    var age: Int
    var active: Bool
    def __init__(out self):
        self.name = String(""); self.age = 0; self.active = False

def main() raises:
    # Deserialize straight into an owned struct — no lifetime to track.
    var u = decode[User](String('{"name":"Ada","age":36,"active":true}'))
    print(u.name)                                # Ada

    # Encode any struct (and List / Dict / Optional fields) via reflection.
    print(dumps(u))                              # {"name":"Ada","age":36,"active":true}
```

### Build JSON, or load it owned

```mojo
from jsonette import loads, dumps, JsonValue

def main() raises:
    # Build a value tree, then serialize it.
    var items = JsonValue.array()
    items.append(JsonValue("a"))
    items.append(JsonValue(2))
    var payload = JsonValue.object()
    payload["ok"] = True
    payload["items"] = items^
    print(dumps(payload))                        # {"ok":true,"items":["a",2]}

    # Or parse into an owned, origin-free tree you can store and return.
    var v = loads(String('{"name":"Ada"}'))
    print(dumps(v))                              # {"name":"Ada"}
```

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
