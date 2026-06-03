#!/bin/bash

# tests/run_tests.sh

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED_TESTS=()
PASSED_COUNT=0
TOTAL_COUNT=0

echo "Starting tests..."
echo "----------------"

for test_file in "$TEST_DIR"/test_*.sh; do
    if [ -x "$test_file" ]; then
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        echo "Running $(basename "$test_file")..."
        if "$test_file"; then
            echo "SUCCESS: $(basename "$test_file")"
            PASSED_COUNT=$((PASSED_COUNT + 1))
        else
            echo "FAILED: $(basename "$test_file")"
            FAILED_TESTS+=("$(basename "$test_file")")
        fi
        echo "----------------"
    fi
done

echo "Test Summary:"
echo "Total: $TOTAL_COUNT"
echo "Passed: $PASSED_COUNT"
echo "Failed: ${#FAILED_TESTS[@]}"

if [ ${#FAILED_TESTS[@]} -ne 0 ]; then
    echo "Failed tests: ${FAILED_TESTS[*]}"
    exit 1
fi

echo "All tests passed!"
exit 0
