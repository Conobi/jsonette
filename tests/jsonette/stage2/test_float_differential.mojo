from std.memory import bitcast
from jsonette.stage2.numbers import _parse_number
from jsonette.tape import TAG_INT64, TAG_UINT64, TAG_FLOAT64


def _nul_padded(s: String) -> List[UInt8]:
    var buf = List[UInt8](unsafe_uninit_length=0)
    for b in s.as_bytes():
        buf.append(b)
    for _ in range(16):
        buf.append(UInt8(0))
    return buf^


def _slice_str(s: String, start: Int, end: Int) -> String:
    """ASCII substring of s over the byte range [start, end).

    1.0.0b1 String/StringSlice do not support `[a:b]` slicing (subscript
    requires a `byte` keyword arg for codepoint access), so rebuild the
    substring from the byte span. The corpus is pure ASCII.
    """
    var out = String("")
    var bytes = s.as_bytes()
    for i in range(start, end):
        out += chr(Int(bytes[i]))
    return out


def _parse_hex_u64(h: String) -> UInt64:
    var out: UInt64 = 0
    var bytes = h.as_bytes()
    for i in range(2, len(bytes)):  # skip "0x"
        var c = bytes[i]
        var d: UInt64
        if c >= UInt8(0x30) and c <= UInt8(0x39):
            d = UInt64(c) - 0x30
        elif c >= UInt8(0x41) and c <= UInt8(0x46):
            d = UInt64(c) - 0x41 + 10
        else:
            d = UInt64(c) - 0x61 + 10
        out = (out << 4) | d
    return out


def main() raises:
    var content: String
    with open(String("tests/fixtures/float_corpus.tsv"), "r") as f:
        content = f.read()
    var mismatches = 0
    var total = 0
    # NB: splitlines() treats '\t' as a line boundary on 1.0.0b1, which would
    # tear each "<decimal>\t<hex>" TSV row in two. Split on '\n' only.
    for line_ref in content.split("\n"):
        var line = String(line_ref)
        var line_bytes = line.as_bytes()
        if len(line_bytes) == 0:
            continue
        var tab = -1
        for i in range(len(line_bytes)):
            if line_bytes[i] == UInt8(0x09):  # '\t'
                tab = i
                break
        if tab < 0:
            continue
        var dec = _slice_str(line, 0, tab)
        var expected = _parse_hex_u64(_slice_str(line, tab + 1, len(line_bytes)))
        var buf = _nul_padded(dec)
        var got_bits: UInt64
        try:
            var r = _parse_number(buf.unsafe_ptr(), len(dec.as_bytes()))
            # The oracle expresses every token as a double. Integer results
            # (in-range UINT64/INT64) carry exact integer bits, so convert them
            # to the equivalent Float64 bit pattern before comparing.
            if r.tag == TAG_UINT64:
                var f = Float64(r.value)
                got_bits = bitcast[DType.uint64](SIMD[DType.float64, 1](f))
            elif r.tag == TAG_INT64:
                var signed = bitcast[DType.int64](SIMD[DType.uint64, 1](r.value))[0]
                var f = Float64(signed)
                got_bits = bitcast[DType.uint64](SIMD[DType.float64, 1](f))
            else:
                got_bits = r.value
        except:
            print("PARSE-ERROR on:", dec)
            mismatches += 1
            total += 1
            continue
        total += 1
        if got_bits != expected:
            if mismatches < 20:
                print("MISMATCH:", dec, "expected", expected, "got", got_bits)
            mismatches += 1
    print("differential:", total - mismatches, "/", total, "correct")
    if mismatches != 0:
        raise Error("float differential mismatches: " + String(mismatches))
    print("test_float_differential: all passed")
