#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TESTS=(
    tests/jsonette/stage1/test_simd_primitives.mojo
    tests/jsonette/stage1/test_classifier.mojo
    tests/jsonette/stage1/test_string_mask.mojo
    tests/jsonette/stage1/test_indexer.mojo
    tests/jsonette/test_tape.mojo
    tests/jsonette/stage2/test_numbers.mojo
    tests/jsonette/stage2/test_swar_digits.mojo
    tests/jsonette/stage2/test_strings.mojo
    tests/jsonette/stage2/test_builder.mojo
    tests/jsonette/stage2/test_eisel_lemire.mojo
    tests/jsonette/stage2/test_slow_float.mojo
    tests/jsonette/stage2/test_slow_float_adversarial.mojo
    tests/jsonette/stage2/test_float_differential.mojo
    tests/jsonette/test_parser.mojo
    tests/jsonette/test_value.mojo
    tests/jsonette/test_gen_token.mojo
    tests/jsonette/test_dom_differential.mojo
    tests/jsonette/ondemand/test_flat_object.mojo
    tests/jsonette/ondemand/test_any_root.mojo
    tests/jsonette/ondemand/test_fuzz_flat.mojo
    tests/jsonette/ondemand/test_leaf_types.mojo
    tests/jsonette/ondemand/test_leaf_errors.mojo
    tests/jsonette/ondemand/test_lazy_contract.mojo
    tests/jsonette/ondemand/test_iteration.mojo
    tests/jsonette/ondemand/test_nested_object.mojo
    tests/jsonette/ondemand/test_array.mojo
    tests/jsonette/ondemand/test_fuzz_nested.mojo
    tests/jsonette/ondemand/test_validate.mojo
    tests/jsonette/ondemand/test_validate_conformance.mojo
    tests/jsonette/serialize/test_writer.mojo
    tests/jsonette/serialize/test_roundtrip.mojo
    tests/jsonette/serialize/test_float_lock.mojo
    tests/jsonette/serialize/test_adversarial.mojo
    tests/jsonette/serialize/test_reflect.mojo
    tests/jsonette/serialize/test_fuzz_roundtrip.mojo
    tests/jsonette/test_alloc_count.mojo
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

# Alloc-count gate: the registered run above compiles its real assertions OUT
# (no -D BENCH_ALLOC_COUNT), so re-run it WITH the define to actually exercise
# cold=4 / warm=0. A failure here fails the suite.
ALLOC_TEST=tests/jsonette/test_alloc_count.mojo
echo -n "RUN  $ALLOC_TEST (-D BENCH_ALLOC_COUNT) ... "
if mojo run -I . -D ASSERT=all -D BENCH_ALLOC_COUNT "$ALLOC_TEST" > /tmp/mojo_test_out.txt 2>&1; then
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

# Stale-iterator negative gate: this program MUST abort (exit non-zero) with the
# gen-token message under -D ASSERT=all. A clean exit (no abort) fails the suite.
STALE_TEST=tests/jsonette/_stale_iter_aborts.mojo
echo -n "RUN  $STALE_TEST (negative: must abort) ... "
if mojo run -I . -D ASSERT=all "$STALE_TEST" > /tmp/mojo_test_out.txt 2>&1; then
    echo "FAIL (expected abort, exited 0)"
    cat /tmp/mojo_test_out.txt
    FAILED=$((FAILED + 1))
elif grep -qi "stale" /tmp/mojo_test_out.txt; then
    echo "PASS (aborted with gen message)"
    PASSED=$((PASSED + 1))
else
    echo "FAIL (non-zero exit but no 'stale' message)"
    cat /tmp/mojo_test_out.txt
    FAILED=$((FAILED + 1))
fi

# Stale On-Demand-handle negative gate: iterating an On-Demand array while
# reparsing MUST abort (exit non-zero) with the gen-token message under
# -D ASSERT=all. A clean exit (no abort) fails the suite.
STALE_OD_TEST=tests/jsonette/ondemand/_stale_od_aborts.mojo
echo -n "RUN  $STALE_OD_TEST (negative: must abort) ... "
if mojo run -I . -D ASSERT=all "$STALE_OD_TEST" > /tmp/mojo_test_out.txt 2>&1; then
    echo "FAIL (expected abort, exited 0)"
    cat /tmp/mojo_test_out.txt
    FAILED=$((FAILED + 1))
elif grep -qi "stale" /tmp/mojo_test_out.txt; then
    echo "PASS (aborted with gen message)"
    PASSED=$((PASSED + 1))
else
    echo "FAIL (non-zero exit but no 'stale' message)"
    cat /tmp/mojo_test_out.txt
    FAILED=$((FAILED + 1))
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed, $WARNED with warnings"
[ $FAILED -eq 0 ] || exit 1
[ $WARNED -eq 0 ] || exit 1
