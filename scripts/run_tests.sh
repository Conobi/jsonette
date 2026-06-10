#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TESTS=(
    tests/simdjson/stage1/test_simd_primitives.mojo
    tests/simdjson/stage1/test_classifier.mojo
    tests/simdjson/stage1/test_string_mask.mojo
    tests/simdjson/stage1/test_indexer.mojo
    tests/simdjson/test_tape.mojo
    tests/simdjson/stage2/test_numbers.mojo
    tests/simdjson/stage2/test_swar_digits.mojo
    tests/simdjson/stage2/test_strings.mojo
    tests/simdjson/stage2/test_builder.mojo
    tests/simdjson/stage2/test_eisel_lemire.mojo
    tests/simdjson/stage2/test_slow_float.mojo
    tests/simdjson/stage2/test_slow_float_adversarial.mojo
    tests/simdjson/stage2/test_float_differential.mojo
    tests/simdjson/test_parser.mojo
    tests/simdjson/test_value.mojo
    tests/simdjson/serialize/test_writer.mojo
    tests/simdjson/serialize/test_roundtrip.mojo
    tests/simdjson/serialize/test_float_lock.mojo
    tests/simdjson/serialize/test_adversarial.mojo
    tests/simdjson/serialize/test_reflect.mojo
    tests/simdjson/test_alloc_count.mojo
    tests/conformance/test_accept.mojo
    tests/conformance/test_reject.mojo
)

cd "$PROJECT_DIR"
rm -f *.mojopkg

PASSED=0
FAILED=0
WARNED=0

for test in "${TESTS[@]}"; do
    if [ ! -f "$test" ]; then
        echo "SKIP $test (not found)"
        continue
    fi
    echo -n "RUN  $test ... "
    if mojo run -I . -D ASSERT=all "$test" > /tmp/mojo_test_out.txt 2>&1; then
        # A test can pass while the compiler still emits warnings on stderr;
        # surface them so the codebase stays warning-free.
        if grep -qi "warning" /tmp/mojo_test_out.txt; then
            echo "PASS (with warnings)"
            grep -i "warning" /tmp/mojo_test_out.txt
            WARNED=$((WARNED + 1))
        else
            echo "PASS"
        fi
        PASSED=$((PASSED + 1))
    else
        echo "FAIL"
        cat /tmp/mojo_test_out.txt
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "Results: $PASSED passed, $FAILED failed, $WARNED with warnings"
[ $FAILED -eq 0 ] || exit 1
[ $WARNED -eq 0 ] || exit 1
