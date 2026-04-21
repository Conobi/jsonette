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
    tests/simdjson/stage2/test_strings.mojo
    tests/simdjson/stage2/test_builder.mojo
    tests/simdjson/stage2/test_eisel_lemire.mojo
    tests/simdjson/test_parser.mojo
    tests/simdjson/test_value.mojo
    tests/conformance/test_accept.mojo
    tests/conformance/test_reject.mojo
)

cd "$PROJECT_DIR"
rm -f *.mojopkg

PASSED=0
FAILED=0

for test in "${TESTS[@]}"; do
    if [ ! -f "$test" ]; then
        echo "SKIP $test (not found)"
        continue
    fi
    echo -n "RUN  $test ... "
    if mojo run -I . -D ASSERT=all "$test" > /tmp/mojo_test_out.txt 2>&1; then
        echo "PASS"
        PASSED=$((PASSED + 1))
    else
        echo "FAIL"
        cat /tmp/mojo_test_out.txt
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ $FAILED -eq 0 ] || exit 1
