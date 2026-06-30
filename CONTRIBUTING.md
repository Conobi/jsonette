# Contributing to jsonette

Thanks for your interest in jsonette. This guide covers the development setup,
the conventions the codebase follows, and a few notes on its structure.

## Development setup

jsonette uses [`uv`](https://docs.astral.sh/uv/) to manage the Mojo toolchain
(pinned to `mojo-compiler==1.0.0b2`) and dependencies.

```bash
uv sync                              # install the toolchain + dev dependencies
uv run -- bash scripts/build.sh      # build jsonette.mojopkg
```

### Running the tests

The test fixtures (conformance vectors and the benchmark corpus) are **not**
checked into the repository, so download them once before running the full
suite:

```bash
uv run -- python scripts/download_test_vectors.py   # RFC 8259 conformance vectors
uv run -- python scripts/download_corpus.py         # benchmark corpus
uv run -- bash scripts/run_tests.sh                 # run the whole suite
```

To run a single test:

```bash
uv run -- mojo run -I . -D ASSERT=all tests/jsonette/test_value.mojo
```

The suite is run with `-D ASSERT=all`, which enables the internal invariant and
generation-token checks. Please make sure the full suite is green before opening
a pull request, and add tests for new behaviour or bug fixes.

## Commit conventions

Commits follow [Conventional Commits](https://www.conventionalcommits.org/) with
a lowercase, imperative subject:

```
feat: add structural classifier for 64-byte chunks
fix: correct carry propagation across chunk boundary
test: add tape builder tests for nested objects
docs: note clmul alternative for string masking
```

- The type prefix (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `perf:`,
  `chore:`, ...) is **required**.
- Do **not** use scopes. Write `refactor:`, not `refactor(stage1):`.

## Mojo conventions

The codebase targets **Mojo 1.0.0b2** and follows these rules:

- Use **`def`** for all functions and methods (`fn` is deprecated).
- Every public symbol carries a **docstring**. If you change a function's
  behaviour, update its docstring in the same commit.
- Use **`comptime`** for compile-time constants (not `@parameter`).
- Mark hot-path accessors with `@always_inline("nodebug")`. Bounds checking is on
  by default; only use `unsafe_get()` / `unsafe_ptr()` where indices are trusted
  (e.g. tape-driven offsets).

## Project structure

The public API lives at the top level of the `jsonette/` package: the free
`parse` / `iter` entry points, `Document`, `Value`, and the `serialize`
encoder (`to_string`, `to_json`, `dumps`).

The parsing internals are **private** and may change without notice:

- `jsonette/stage1/` — SIMD structural indexing (classify 64-byte chunks into
  bitsets, emit structural positions).
- `jsonette/stage2/` — the tape builder (walks the structural index into a flat,
  depth-first tape).
- `jsonette/ondemand/` — the lazy On-Demand reader's machinery.

When changing these, keep stages independently testable and avoid branching
inside the 64-byte SIMD loop — the hot path stays branchless.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
