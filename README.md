# jsonette

A SIMD-accelerated JSON parser for [Mojo](https://www.modular.com/mojo).

Conventional parsers walk JSON one byte at a time, stalling on a branch
misprediction at every quote, comma and brace. jsonette is a faithful Mojo port
of [simdjson](https://github.com/simdjson/simdjson)'s two-stage
structural-indexing algorithm (Langdale & Lemire,
[*Parsing Gigabytes of JSON per Second*](https://arxiv.org/abs/1902.08318)): it
classifies 64 bytes per branchless SIMD pass instead, then materialises a flat
tape you read through a Python-like surface.

> [!NOTE]
> **Early — v0.1.0.** jsonette parses, validates, navigates and serialises JSON
> today against a strict RFC 8259 grammar and a passing conformance suite. It
> requires **Mojo 1.0.0b2**, and the public API may still change before 1.0. The
> primary target is **x86-64 (AVX2 / SSE4.2)**. No throughput numbers are
> published yet — see *Benchmarking*.

## Why jsonette

- **Two-stage SIMD parsing.** Stage 1 builds a structural index over 64-byte
  chunks; Stage 2 walks it once into a depth-first tape. No per-byte branching on
  the hot path.
- **Zero-copy DOM.** `parse(s)` returns an owning `Document`; index it with
  `v["key"]` / `v[i]`, iterate arrays and objects, and use `len` / `in` / `==` /
  `print` — none of which allocate per node. The syntax compiles to tape-index
  arithmetic, not a per-node object graph.
- **Strict RFC 8259, validated in one pass.** Malformed input — including
  ill-formed UTF-8 — is rejected as the tape is built, not in a separate scan.
- **Four ways to work with a document.** The DOM above, a typed `decode[T]` into
  a struct, an owned mutable `JsonValue` tree, and a lazy On-Demand reader that
  parses only the fields you touch.
- **Built for hostile input.** A JSON parser reads bytes it didn't write, so
  untrusted input is a design target, not an afterthought: bounded recursion, a
  32-bit size ceiling, and stale-handle traps (see *Correctness & safety*).

## Install

jsonette manages its Mojo toolchain and dependencies with
[`uv`](https://docs.astral.sh/uv/) (pinned to `mojo-compiler==1.0.0b2`):

```bash
uv sync                              # install the toolchain + dev dependencies
uv run -- bash scripts/build.sh      # precompile the jsonette package
```

To use jsonette from another Mojo project, add it to the include path with
`-I /path/to/jsonette` and import from `jsonette`.

> The import package is **`jsonette`**, not `json`: Mojo's implicit stdlib
> imports make a top-level `json` package collide with `std.json`, so every
> import uses the `jsonette.*` prefix.

## Usage

### Parse and navigate — zero-copy, Python-like

```mojo
from jsonette import parse

def main() raises:
    var doc = parse(String('{"user":{"name":"Ada","age":36},"scores":[95,87]}'))

    # Index like a dict/list — no `.root()` hop, no lifetime annotations.
    print(doc["user"]["name"].get_string())     # Ada
    print(doc["scores"][0].get_int())            # 95

    # Operators — each is a zero-allocation tape read.
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

## Correctness & safety

No speed numbers are published yet, so here is what *is* pinned down by the suite:

- **Conformance.** Passes the [Seriot JSONTestSuite](https://github.com/nst/JSONTestSuite)
  — both the must-accept and must-reject corpora — with full UTF-8
  well-formedness checking.
- **Differential-tested.** The DOM, the On-Demand reader and a standalone
  validator must agree on which inputs are valid for every vector, and
  navigation results are cross-checked against Python's `json` as an oracle.
  Floats take an Eisel–Lemire fast path that is checked against a slow,
  arbitrary-precision path on adversarial inputs.
- **Zero allocation on a warm parse.** A `Document` owns its buffers and
  `doc.reparse(...)` reuses them; a test gate asserts **0 allocations** on a warm
  parse (4 on the cold one), and under `-D ASSERT=all` a generation token aborts
  on any use of a `Value` or iterator left stale by a reparse.
- **Hardening limits.** Nesting is bounded at **1024**, input at **< 4 GiB**
  (structural offsets are 32-bit), and the encoder refuses non-finite floats
  rather than emitting invalid JSON. See [`SECURITY.md`](SECURITY.md).

## Scope & non-goals

jsonette is a whole-buffer, single-threaded, strict parser. By design it does
**not** (yet) do:

- **Streaming / chunk-fed parsing** — the buffer must be fully in memory;
  On-Demand is lazy, not incremental, and there is no NDJSON feeder.
- **Lenient parsing** — no comments, trailing commas, or leniency flags; strict
  RFC 8259 only.
- **JSONPath, JSON Patch / Merge Patch, or JSON Schema.**
- **Arbitrary-precision integers** — values outside `Int64` / `UInt64` raise
  rather than silently truncating.
- **GPU parsing**, or an **ARM NEON / SVE** backend — x86-64 is the current target.
- **Multi-threaded parsing** — parallelise across documents in the caller.

## Benchmarking

There are no published throughput numbers yet. Runnable harnesses measure
jsonette against [simdjson](https://github.com/simdjson/simdjson) (C++, under
`scripts/cpp_bench/`), [serde_json](https://crates.io/crates/serde_json) (Rust,
under `scripts/rust_bench/`) and [ehsanmok/json](https://github.com/ehsanmok/json)
(a sibling Mojo parser, under `bench/`) over standard corpora (`twitter`,
`citm_catalog`, `canada`, …) with a simdjson-style min-time methodology. Numbers
will be published once the API settles.

## Project layout

```
jsonette/    Library source: stage1/ (SIMD structural index), stage2/ (tape
             builder, Eisel–Lemire floats, string unescape), serialize/
             (encoder + reflection), ondemand/ (lazy reader + validator).
tests/       Conformance, differential-vs-Python, float, fuzz and adversarial
             suites, plus allocation and stale-handle gates.
bench/       Mojo benchmark + profiling harnesses, incl. the ehsanmok/json
             head-to-head over standard corpora.
scripts/     build.sh, run_tests.sh, the test-vector / corpus downloaders, and
             the simdjson (C++) and serde_json (Rust) reference benches.
```

## Running the tests

The test fixtures (conformance vectors and the benchmark corpus) are **not**
checked into the repository, so a fresh clone downloads them first:

```bash
uv run -- python scripts/download_test_vectors.py   # RFC 8259 conformance vectors
uv run -- python scripts/download_corpus.py         # benchmark corpus
uv run -- bash scripts/run_tests.sh                 # run the whole suite
```

Run a single test with
`uv run -- mojo run -I . -D ASSERT=all tests/jsonette/test_value.mojo`. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) to contribute.

## References

- Geoff Langdale & Daniel Lemire, *Parsing Gigabytes of JSON per Second*,
  [arXiv:1902.08318](https://arxiv.org/abs/1902.08318) — the algorithm this
  implements.
- [simdjson](https://github.com/simdjson/simdjson) — the C++ reference
  implementation.

## License

[MIT](LICENSE).
