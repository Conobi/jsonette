<h1 align="center">jsonette</h1>

<p align="center">
  <em>A SIMD-accelerated JSON parser for <a href="https://www.modular.com/mojo">Mojo</a>.</em>
</p>

<p align="center">
  <a href="https://www.modular.com/mojo"><img alt="Mojo 1.0.0b2" src="https://img.shields.io/badge/Mojo-1.0.0b2-orange"></a>
  <a href="LICENSE"><img alt="license MIT" src="https://img.shields.io/badge/license-MIT-green"></a>
</p>

jsonette is a faithful port of [simdjson](https://github.com/simdjson/simdjson)'s two-stage
structural indexing ([Langdale & Lemire](https://arxiv.org/abs/1902.08318)): it replaces
byte-by-byte branching with a branchless classifier that scans 64 bytes per SIMD pass into
a flat tape, read through a Python-like API.

> [!NOTE]
> **Early.** Requires Mojo 1.0.0b2, x86-64. Parses, validates and serialises JSON today;
> the public API may still change before 1.0.

## Install

```bash
uv sync
uv run -- bash scripts/build.sh      # precompile the package
```

Use it from another Mojo project with `-I /path/to/jsonette`.

> [!IMPORTANT]
> The import package is `jsonette`, not `json` — a top-level `json` would collide with
> `std.json`.

## Usage

Parse and navigate a document with zero-copy, Python-like access:

```mojo
from jsonette import parse

def main() raises:
    var doc = parse(String('{"user":{"name":"Ada"},"scores":[95,87]}'))
    print(doc["user"]["name"].get_string())   # Ada — index it like a dict
    print(len(doc["scores"]))                 # 2
    for score in doc["scores"]:
        print(score.get_int())                # 95, then 87
```

`doc["k"]`, `doc[i]`, `len`, `in`, `==` and iteration never allocate per node. Or decode
straight into your own struct — reflection walks the fields:

```mojo
from jsonette import decode, dumps, JsonDeserializable

struct User(Copyable, Movable, Defaultable, JsonDeserializable):
    var name: String
    var age: Int
    def __init__(out self):
        self.name = String(""); self.age = 0

def main() raises:
    var u = decode[User](String('{"name":"Ada","age":36}'))
    print(u.name)              # Ada
    print(dumps(u))            # {"name":"Ada","age":36}
```

You can also build and mutate an owned `JsonValue`, or read lazily through
`jsonette.ondemand`; serialise any node with `dumps` or `to_json[pretty=True]`.

## Correctness & scope

jsonette is strict RFC 8259, whole-buffer, single-threaded and x86-first, and it's built
for untrusted input. Parsing validates UTF-8 in the same pass, nesting is bounded at 1024
and input at 4 GiB, and the result is conformance-checked against the
[Seriot suite](https://github.com/nst/JSONTestSuite) and differentially against Python's
`json` — while a warm reparse allocates nothing. It does **not** do streaming, lenient
parsing, JSONPath/Patch/Schema, big integers, or GPU/ARM. See [`SECURITY.md`](SECURITY.md)
for the hardening details.

## Benchmarks

Two shapes: **warm-parser throughput** (REST-server workload — one parser reused across
many documents) and **cold parse + walk** (a fresh parser per document; kostya's
cross-language JSON benchmark). Both run on the same pinned Xeon 8260 core, host-load
audit passed. Full methodology in [`docs/benchmarks.md`](docs/benchmarks.md).

### Warm-parser throughput

Full-parse throughput — MB/s, higher is better:

| document | jsonette | simdjson (C++) | serde_json (Rust) | ehsanmok/json (Mojo) |
|---|--:|--:|--:|--:|
| twitter (631 KB) | **698** | 1,973 | 162 | 444 |
| citm_catalog (1.7 MB) | **857** | 2,109 | 280 | — |
| canada (2.3 MB, float-heavy) | **333** | 594 | 102 | 39 |

jsonette beats serde_json and the sibling Mojo parser
[ehsanmok/json](https://github.com/ehsanmok/json); simdjson's hand-tuned C++ stays ~2–3×
ahead — a conservative gap, since it reuses its DOM buffer where jsonette re-copies the
input per parse. Reproduce with the harnesses under [`bench/`](bench/). *(ehsanmok v0.2.1,
measured in the head-to-head harness; citm_catalog not run there.)*

### Cold parse + walk ([kostya's JSON benchmark](https://github.com/kostya/benchmarks))

Parse a 110 MiB file of 524,288 `{x, y, z, name, opts}` objects, iterate `coordinates`,
sum x/y/z. Fresh parser per iteration (matching the reference implementations), 3 warmup +
10 measured, min-of-N. `perf_event_open` in every language, `VmHWM` for the memory
column. All seven contenders produce the same coordinate to bit precision.

| contender | ms | MB/s | cyc/B | ins/B | mem Δ MiB |
|---|--:|--:|--:|--:|--:|
| C++/simdjson On-Demand | 152 | 757 | 2.83 | 7.34 | 60 |
| Rust/serde Custom (visitor) | 217 | 529 | 5.84 | 17.55 | **0.1** |
| Rust/serde Typed (derive) | 223 | 516 | 5.96 | 17.57 | 12 |
| **jsonette On-Demand** | 259 | 444 | 6.62 | 18.48 | 75 |
| C++/simdjson DOM | 290 | 397 | 3.91 | 8.96 | 177 |
| **jsonette DOM** | 310 | 372 | 7.89 | 23.75 | 194 |
| Rust/serde Untyped (`Value`) | 1,083 | 106 | 28.41 | 48.97 | 840 |

jsonette On-Demand lands faster than C++/simdjson DOM at ~24 % more memory per parse;
jsonette DOM sits in the same tier as C++/simdjson DOM at ~10 % more memory. The
Rust/serde Custom streaming visitor is the memory champion at 0.1 MiB delta. Reproduce
with `bash scripts/kostya_bench/run.sh` (falls back to `nix shell nixpkgs#gcc nixpkgs#cargo
nixpkgs#rustc` on NixOS hosts).

## License

[MIT](LICENSE). See [`CONTRIBUTING.md`](CONTRIBUTING.md) to contribute.
