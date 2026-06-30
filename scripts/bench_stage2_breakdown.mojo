"""Stage 2 hotspot breakdown: classify structurals and micro-bench each category.

Loads test corpus files, runs Stage 1 to get structural positions, then:
1. Counts structurals by type (strings, numbers, containers, literals, colons, commas)
2. Micro-benchmarks each parsing category in isolation
3. Estimates time breakdown for Stage 2
"""

from std.time import perf_counter_ns
from jsonette.stage1.indexer import structural_index
from jsonette.stage2.builder import build_tape
from jsonette.stage2.strings import parse_string
from jsonette.stage2.numbers import _parse_number
from jsonette.tape import (
    Tape,
    TAG_STRING,
    TAG_TRUE,
    TAG_FALSE,
    TAG_NULL,
    TAG_OBJECT_OPEN,
    TAG_OBJECT_CLOSE,
    TAG_ARRAY_OPEN,
    TAG_ARRAY_CLOSE,
)


def read_file(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var content = f.read()
    f.close()
    var buf = List[UInt8]()
    for b in content.as_bytes():
        buf.append(b)
    return buf^


def fmt_count(n: Int) -> String:
    """Format integer with comma separators."""
    var s = String(n)
    if s.byte_length() <= 3:
        return s
    var result = String("")
    var digits = s.byte_length()
    for i in range(digits):
        if i > 0 and (digits - i) % 3 == 0:
            result += ","
        result += s[byte=i]
    return result


def fmt_pct(part: Float64, total: Float64) -> String:
    """Format as percentage with one decimal."""
    if total == 0.0:
        return "0.0"
    var pct = part / total * 100.0
    var whole = Int(pct)
    var frac = Int((pct - Float64(whole)) * 10.0)
    if frac < 0:
        frac = -frac
    return String(whole) + "." + String(frac)


def fmt_ms(ns: Int) -> String:
    """Format nanoseconds as milliseconds with 2 decimal places."""
    var ms_whole = ns // 1000000
    var ms_frac = (ns % 1000000) // 10000
    var frac_str = String(ms_frac)
    if ms_frac < 10:
        frac_str = "0" + frac_str
    return String(ms_whole) + "." + frac_str


def profile_file(path: String, name: String) raises:
    var data = read_file(path)
    var size = len(data)
    var input_ptr = data.unsafe_ptr()
    var input_len = len(data)

    # --- Stage 1: get structural positions ---
    var positions = List[UInt32]()
    structural_index(data, input_len, positions)
    var num_structurals = len(positions)

    # --- Classify structurals by type ---
    var n_strings = 0
    var n_numbers = 0
    var n_true = 0
    var n_false = 0
    var n_null = 0
    var n_obj_open = 0
    var n_obj_close = 0
    var n_arr_open = 0
    var n_arr_close = 0
    var n_colon = 0
    var n_comma = 0
    var n_other = 0

    # Collect positions by category for micro-benchmarks
    var string_positions = List[UInt32]()
    var number_positions = List[UInt32]()
    var literal_positions = List[UInt32]()
    var literal_kinds = List[UInt8]()  # 't', 'f', 'n'

    var si = 0
    while si < num_structurals:
        var pos = Int(positions[si])
        var byte = input_ptr[pos]

        if byte == TAG_STRING:  # '"'
            n_strings += 1
            string_positions.append(positions[si])
            # Skip past closing quote structurals (same as builder logic)
            # We need to know consumed bytes - do a quick scan for unescaped closing quote
            var j = pos + 1
            while j < input_len:
                var b = input_ptr[j]
                if b == UInt8(0x5C):  # backslash, skip next
                    j += 2
                elif b == UInt8(0x22):  # closing quote
                    break
                else:
                    j += 1
            var string_end = j
            si += 1
            while si < num_structurals and Int(positions[si]) <= string_end:
                si += 1
        elif byte == UInt8(0x2D) or (byte >= UInt8(0x30) and byte <= UInt8(0x39)):
            n_numbers += 1
            number_positions.append(positions[si])
            si += 1
        elif byte == TAG_TRUE:
            n_true += 1
            literal_positions.append(positions[si])
            literal_kinds.append(TAG_TRUE)
            si += 1
        elif byte == TAG_FALSE:
            n_false += 1
            literal_positions.append(positions[si])
            literal_kinds.append(TAG_FALSE)
            si += 1
        elif byte == TAG_NULL:
            n_null += 1
            literal_positions.append(positions[si])
            literal_kinds.append(TAG_NULL)
            si += 1
        elif byte == TAG_OBJECT_OPEN:
            n_obj_open += 1
            si += 1
        elif byte == TAG_OBJECT_CLOSE:
            n_obj_close += 1
            si += 1
        elif byte == TAG_ARRAY_OPEN:
            n_arr_open += 1
            si += 1
        elif byte == TAG_ARRAY_CLOSE:
            n_arr_close += 1
            si += 1
        elif byte == UInt8(0x3A):  # ':'
            n_colon += 1
            si += 1
        elif byte == UInt8(0x2C):  # ','
            n_comma += 1
            si += 1
        else:
            n_other += 1
            si += 1

    var n_literals = n_true + n_false + n_null
    var n_containers = n_obj_open + n_obj_close + n_arr_open + n_arr_close
    var total_f = Float64(num_structurals)

    print("=== " + name + " (" + fmt_count(size) + " bytes) ===")
    print("Structurals: " + fmt_count(num_structurals))
    print("  Strings:      " + fmt_count(n_strings) + " (" + fmt_pct(Float64(n_strings), total_f) + "%)")
    print("  Numbers:      " + fmt_count(n_numbers) + " (" + fmt_pct(Float64(n_numbers), total_f) + "%)")
    print("  Literals:     " + fmt_count(n_literals) + " (" + fmt_pct(Float64(n_literals), total_f) + "%)")
    print("    true:       " + fmt_count(n_true))
    print("    false:      " + fmt_count(n_false))
    print("    null:       " + fmt_count(n_null))
    print("  Containers:   " + fmt_count(n_containers) + " (" + fmt_pct(Float64(n_containers), total_f) + "%)")
    print("    { open:     " + fmt_count(n_obj_open))
    print("    } close:    " + fmt_count(n_obj_close))
    print("    [ open:     " + fmt_count(n_arr_open))
    print("    ] close:    " + fmt_count(n_arr_close))
    print("  Colons:       " + fmt_count(n_colon) + " (" + fmt_pct(Float64(n_colon), total_f) + "%)")
    print("  Commas:       " + fmt_count(n_comma) + " (" + fmt_pct(Float64(n_comma), total_f) + "%)")
    print()

    # --- Micro-benchmarks ---
    comptime WARMUP: Int = 3
    comptime ITERS: Int = 20

    # --- Full Stage 2 baseline ---
    var cs = List[UInt32](capacity=1024)
    var tape = Tape()
    for _ in range(WARMUP):
        cs.resize(0, UInt32(0))
        build_tape(data, input_len, positions, cs, tape)

    var s2_start = perf_counter_ns()
    for _ in range(ITERS):
        cs.resize(0, UInt32(0))
        build_tape(data, input_len, positions, cs, tape)
    var s2_end = perf_counter_ns()
    var s2_total_ns = Int(s2_end - s2_start)
    var s2_avg_ns = s2_total_ns // ITERS

    # --- String parsing micro-bench ---
    # Warmup
    var tmp_buf = List[UInt8](unsafe_uninit_length=input_len + 64)
    for _ in range(WARMUP):
        for idx in range(len(string_positions)):
            var spos = Int(string_positions[idx])
            var consumed = parse_string(input_ptr, spos, input_len, tmp_buf.unsafe_ptr(), 0)

    var str_start = perf_counter_ns()
    for _ in range(ITERS):
        for idx in range(len(string_positions)):
            var spos = Int(string_positions[idx])
            var consumed = parse_string(input_ptr, spos, input_len, tmp_buf.unsafe_ptr(), 0)
    var str_end = perf_counter_ns()
    var str_total_ns = Int(str_end - str_start)
    var str_avg_ns = str_total_ns // ITERS

    # --- Number parsing micro-bench ---
    for _ in range(WARMUP):
        for idx in range(len(number_positions)):
            var npos = Int(number_positions[idx])
            var result = _parse_number(input_ptr + npos, input_len - npos)

    var num_start = perf_counter_ns()
    for _ in range(ITERS):
        for idx in range(len(number_positions)):
            var npos = Int(number_positions[idx])
            var result = _parse_number(input_ptr + npos, input_len - npos)
    var num_end = perf_counter_ns()
    var num_total_ns = Int(num_end - num_start)
    var num_avg_ns = num_total_ns // ITERS

    # --- Literal validation micro-bench ---
    for _ in range(WARMUP):
        for idx in range(len(literal_positions)):
            var lpos = Int(literal_positions[idx])
            var kind = literal_kinds[idx]
            if kind == TAG_TRUE:
                _bench_validate_literal(input_ptr, lpos, input_len, String("true"))
            elif kind == TAG_FALSE:
                _bench_validate_literal(input_ptr, lpos, input_len, String("false"))
            else:
                _bench_validate_literal(input_ptr, lpos, input_len, String("null"))

    var lit_start = perf_counter_ns()
    for _ in range(ITERS):
        for idx in range(len(literal_positions)):
            var lpos = Int(literal_positions[idx])
            var kind = literal_kinds[idx]
            if kind == TAG_TRUE:
                _bench_validate_literal(input_ptr, lpos, input_len, String("true"))
            elif kind == TAG_FALSE:
                _bench_validate_literal(input_ptr, lpos, input_len, String("false"))
            else:
                _bench_validate_literal(input_ptr, lpos, input_len, String("null"))
    var lit_end = perf_counter_ns()
    var lit_total_ns = Int(lit_end - lit_start)
    var lit_avg_ns = lit_total_ns // ITERS

    # --- Container ops micro-bench (simulate open/close with stack) ---
    for _ in range(WARMUP):
        _bench_container_ops(positions, input_ptr, num_structurals)

    var cont_start = perf_counter_ns()
    for _ in range(ITERS):
        _bench_container_ops(positions, input_ptr, num_structurals)
    var cont_end = perf_counter_ns()
    var cont_total_ns = Int(cont_end - cont_start)
    var cont_avg_ns = cont_total_ns // ITERS

    # --- Compute estimated breakdown ---
    var measured_ns = str_avg_ns + num_avg_ns + lit_avg_ns + cont_avg_ns
    var dispatch_ns = 0
    if s2_avg_ns > measured_ns:
        dispatch_ns = s2_avg_ns - measured_ns

    var s2_f = Float64(s2_avg_ns)

    print("Time breakdown (avg per iteration, " + String(ITERS) + " iters):")
    print("  Full Stage 2:     " + fmt_ms(s2_avg_ns) + " ms")
    print("  String parsing:   " + fmt_ms(str_avg_ns) + " ms  (" + fmt_pct(Float64(str_avg_ns), s2_f) + "%)" + "  [" + fmt_count(n_strings) + " strings]")
    print("  Number parsing:   " + fmt_ms(num_avg_ns) + " ms  (" + fmt_pct(Float64(num_avg_ns), s2_f) + "%)" + "  [" + fmt_count(n_numbers) + " numbers]")
    print("  Literal valid.:   " + fmt_ms(lit_avg_ns) + " ms  (" + fmt_pct(Float64(lit_avg_ns), s2_f) + "%)" + "  [" + fmt_count(n_literals) + " literals]")
    print("  Container ops:    " + fmt_ms(cont_avg_ns) + " ms  (" + fmt_pct(Float64(cont_avg_ns), s2_f) + "%)" + "  [" + fmt_count(n_containers) + " open/close]")
    print("  Dispatch+other:   " + fmt_ms(dispatch_ns) + " ms  (" + fmt_pct(Float64(dispatch_ns), s2_f) + "%)" + "  [colons/commas/tape writes/overhead]")
    print()

    # Per-structural cost
    if n_strings > 0:
        print("  Per-string cost:    " + String(str_avg_ns // n_strings) + " ns")
    if n_numbers > 0:
        print("  Per-number cost:    " + String(num_avg_ns // n_numbers) + " ns")
    if n_literals > 0:
        print("  Per-literal cost:   " + String(lit_avg_ns // n_literals) + " ns")
    if n_containers > 0:
        print("  Per-container cost: " + String(cont_avg_ns // n_containers) + " ns")
    print()

    # Throughput
    var s2_mbs = Float64(size) / Float64(s2_avg_ns) * 1000.0
    print("  Stage 2 throughput: " + String(s2_mbs) + " MB/s")
    print()
    print()


def _bench_validate_literal(
    ptr: UnsafePointer[UInt8, _], pos: Int, input_len: Int, expected: String
) raises:
    """Same logic as builder._validate_literal, inlined for micro-bench."""
    var expected_bytes = expected.as_bytes()
    if pos + len(expected_bytes) > input_len:
        raise "INVALID_LITERAL: unexpected end of input at position " + String(pos)
    for i in range(len(expected_bytes)):
        if ptr[pos + i] != expected_bytes[i]:
            raise "INVALID_LITERAL: expected '" + expected + "' at position " + String(pos)


def _bench_container_ops(
    positions: List[UInt32],
    input_ptr: UnsafePointer[UInt8, _],
    num_structurals: Int,
):
    """Simulate container stack push/pop for all container structurals."""
    var container_stack = List[UInt32]()
    var count_stack = List[UInt32]()
    var tape_idx = 0

    for si in range(num_structurals):
        var pos = Int(positions[si])
        var byte = input_ptr[pos]

        if byte == TAG_OBJECT_OPEN or byte == TAG_ARRAY_OPEN:
            container_stack.append(UInt32(tape_idx))
            count_stack.append(UInt32(0))
            tape_idx += 1
        elif byte == TAG_OBJECT_CLOSE or byte == TAG_ARRAY_CLOSE:
            if len(container_stack) > 0:
                var open_idx = container_stack.pop()
                var count = count_stack.pop()
                _ = open_idx
                _ = count
            tape_idx += 1
        elif byte == UInt8(0x2C):  # ','
            if len(count_stack) > 0:
                count_stack[len(count_stack) - 1] += 1
        else:
            tape_idx += 1


def main() raises:
    print("=== jsonette Stage 2 Hotspot Breakdown ===")
    print()
    profile_file(String("tests/fixtures/corpus/twitter.json"), String("twitter.json"))
    profile_file(String("tests/fixtures/corpus/canada.json"), String("canada.json"))
