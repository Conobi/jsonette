"""Minimal parse loop mirroring scripts/cpp_bench/bench.cpp for perf-stat A/B.

Loads a file, 10 warmup parses + 500 timed parses, prints a sink. NO internal
perf machinery — measure it from outside with `perf stat` so the comparison
against the C++ simdjson bench (same structure) is apples-to-apples: same
machine, same iteration count, external counters, user-space only.

Build then measure:
  uv run -- mojo build -I . -D ASSERT=none bench/parse_loop.mojo -o /tmp/parse_loop
  perf stat -e instructions:u,cycles:u,branches:u,branch-misses:u /tmp/parse_loop tests/fixtures/corpus/twitter.json
"""

from std.sys import argv
from jsonette.document import parse


def read_file(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


def main() raises:
    var args = argv()
    if len(args) < 2:
        print("usage: parse_loop <file>")
        return
    var path = String(args[1])
    var data = read_file(path)
    # Cold parse once (allocates the buffers); the warmup + timed loops reuse
    # them via `reparse` (the warm parse path the external perf-stat measures).
    var doc = parse(data)
    var sink: UInt64 = 0
    for _ in range(10):  # warmup
        doc.reparse(data)
        sink += UInt64(len(doc._parser._tape.elements))
    for _ in range(500):  # timed region (count from outside)
        doc.reparse(data)
        sink += UInt64(len(doc._parser._tape.elements))
    print(path, " bytes=", len(data), " sink=", sink)
