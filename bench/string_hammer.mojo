"""Hammer parse_string on a single 30B string so perf annotate can attribute
its retired instructions to specific asm lines (dynamic, not a static histogram).

Build then record+annotate:
  uv run -- mojo build -I . -D ASSERT=none bench/string_hammer.mojo -o /tmp/string_hammer
  perf record -e instructions:u -c 50000 -o /tmp/ph.data /tmp/string_hammer
  perf annotate --stdio -i /tmp/ph.data
"""

from jsonette.stage2.strings import parse_string


def main() raises:
    var content = 30
    var total = content + 2
    var bufcap = total + 128
    var src = List[UInt8](unsafe_uninit_length=bufcap)
    var sp = src.unsafe_ptr()
    sp[0] = UInt8(0x22)
    for k in range(content):
        sp[1 + k] = UInt8(0x61)
    sp[1 + content] = UInt8(0x22)
    for k in range(total, bufcap):
        sp[k] = UInt8(0)
    var dst = List[UInt8](unsafe_uninit_length=bufcap + 64)
    var dp = dst.unsafe_ptr()

    var sink: UInt64 = 0
    for _ in range(50_000_000):
        var r = parse_string(sp, 0, total, dp, 0)
        sink += UInt64(r[1])
    print(sink)
