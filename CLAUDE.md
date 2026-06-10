# json-simd-mojo

SIMD-accelerated JSON parser for Mojo, implementing the two-stage structural indexing algorithm from Langdale & Lemire (arXiv:1902.08318). Targets multi-gigabyte-per-second throughput by processing 64 bytes per SIMD vector pass.

## Commands

```bash
uv sync                                                        # Install dev dependencies
uv run -- bash scripts/build.sh                                # Build simdjson.mojopkg
uv run -- bash scripts/run_tests.sh                            # Run all tests
uv run -- mojo run -I . -D ASSERT=all tests/<path>.mojo        # Run single test
```

## Package Name

The source directory is `simdjson/` (not `json/`). Mojo's implicit stdlib imports cause `json` to collide with `std.json`. All imports use `simdjson.*` (e.g., `from simdjson.parser import Parser`).

## Vision

A faithful Mojo port of the simdjson algorithm: parse structurally valid JSON at memory-bandwidth-limited speed by replacing byte-at-a-time branching with branchless SIMD classification across 64-byte chunks. The public API surfaces a DOM (document object model) and an on-demand iterator; the SIMD internals are private.

Two parsing stages:

- **Stage 1 — Structural indexing** (`simdjson/stage1/`): classify 64-byte chunks into backslash/quote/structural/whitespace bitsets using `SIMD[DType.uint8, 64]`; produce a flat `List[UInt32]` of structural character positions.
- **Stage 2 — Tape building** (`simdjson/stage2/`): walk the structural index and materialise a depth-first tape of JSON values; no allocation per value.

An encoder (`simdjson/serialize/`) surfaces `to_string`/`to_json` for round-tripping a parsed Document and `dumps[T]` for serializing arbitrary structs via reflection.

## Architecture

```
simdjson/                            # Public API
├── __init__.mojo                    # Re-exports: Parser, Document, Value, Error
├── parser.mojo                      # Parser struct — entry point
├── document.mojo                    # Document struct (owns Tape + input buffer)
├── tape.mojo                        # Tape: flat value array (depth-first)
├── value.mojo                       # Value view: borrows from Document
├── error.mojo                       # ParseError + ErrorCode
├── stage1/                          # Structural indexing (SIMD)
│   ├── __init__.mojo
│   ├── classifier.mojo              # Chunk classifier: backslash / quote / structural / whitespace
│   ├── string_mask.mojo             # In-string bitmask via carry-less SIMD
│   └── indexer.mojo                 # Walks chunks → emits structural positions
├── stage2/                          # Tape builder
│   ├── __init__.mojo
│   └── builder.mojo                 # State machine over structural index
└── serialize/                       # JSON encoder (output side)
    ├── writer.mojo                  # JsonWriter sink: escaping, numbers, indent
    ├── tape_writer.mojo             # Document tape → JSON (round-trip)
    ├── roundtrip.mojo               # tape-equality helper for round-trip tests
    └── reflect_writer.mojo          # dumps[T] for user structs via std.reflection

tests/
├── simdjson/
│   ├── stage1/
│   │   ├── test_classifier.mojo
│   │   ├── test_string_mask.mojo
│   │   └── test_indexer.mojo
│   ├── stage2/
│   │   └── test_builder.mojo
│   ├── test_parser.mojo
│   └── test_value.mojo

scripts/
├── build.sh
└── run_tests.sh

plans/                               # Dated implementation plans (YYYY-MM-DD-<slug>.md)
specs/                               # Dated specs (YYYY-MM-DD-<slug>.md)
research/                            # Notes, benchmarks, paper excerpts
```

## Design Principles

### SIMD-first, scalar fallback only at edges
The hot path processes 64 bytes per iteration via `SimdInput` (2 × `SIMD[DType.uint8, 32]` on AVX2, 4 × `SIMD[DType.uint8, 16]` on SSE4.2). The logical block is always 64 bytes producing one `UInt64` bitmask; the hardware width is abstracted. Scalar code only handles the tail chunk (< 64 bytes, zero-padded) and error recovery. Never branch inside the 64-byte loop.

### Branchless classification
Stage 1 produces bitsets, not per-byte decisions. Structural characters are detected by parallel byte comparison (`== ord('"')`, `== ord('{')`, etc.), OR-combined into a single 64-bit integer via `reduce_or` and bitmask arithmetic. No per-byte `if`.

### Zero-copy tape
Stage 2 writes a flat `List[UInt64]` tape (the simdjson tape format). `Value` is a view into that tape — no heap allocation per JSON node. The `Parser` owns the tape and input buffer; `Value` borrows from it.

### Carry-less string masking
String content is excluded from structural character detection using a carry-less multiply on the quote bitmask to propagate the in-string state across 64-byte boundaries. Mojo's `SIMD` and raw bit operations implement this without CLMUL intrinsic dependency.

### Stage 1 and Stage 2 are separate, testable passes
`indexer.mojo` returns `List[UInt32]` of structural positions. `builder.mojo` takes that list and the original input. Each stage has its own test suite. You can fuzz Stage 1 independently.

### No I/O in the parser
`Parser.parse(ref data: List[UInt8]) -> Value` takes a pre-loaded buffer. Callers own I/O. No file handles, no streams inside `simdjson/`.

## Mojo Conventions (1.0.0b1)

- `def` for all functions and methods (`fn` is deprecated — warning in 1.0.0b1, error in next release).
- Move constructor: `def __init__(out self, *, deinit take: Self)`.
- `comptime` for constants (not `@parameter`).
- Trait methods use `def`.
- `@always_inline("nodebug")` on hot-path accessors.
- Bounds checking is on by default for CPU collections. Hot-path accessors use `unsafe_get()` / `unsafe_ptr()` to bypass checks where indices are trusted (e.g., tape-driven offsets).
- `UnsafePointer` is non-null by design. Express nullability with `Optional[UnsafePointer[...]]`.
- `String.__len__()` is deprecated — use `byte_length()` or `count_codepoints()`.
- When in doubt about a stdlib API (`SIMD`, `UnsafePointer`, `List`, `Span`), use `mcp__mojo-mcp__lookup` / `validate` before writing; use `mcp__mojo-mcp__execute` as the single source of truth for whether code compiles.

## Commit Style

Lowercase imperative subject with conventional-commit prefix:

```
feat: add structural classifier for 64-byte chunks
fix: correct carry propagation across chunk boundary
test: add tape builder tests for nested objects
docs: note clmul alternative for string masking
```

## Key References

- Langdale & Lemire, "Parsing Gigabytes of JSON per Second" — arXiv:1902.08318 (the paper this implements)
- simdjson C++ reference implementation — github.com/simdjson/simdjson
- Lemire's blog on SIMD JSON structural indexing
- Mojo `SIMD` stdlib docs — use `mcp__mojo-mcp__lookup SIMD` for current API surface
