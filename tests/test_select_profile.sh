#!/bin/bash

# tests/test_select_profile.sh

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SH="${SCRIPT_DIR}/../modules/common.sh"

# Source the common module
source "$COMMON_SH"

# Helper function for assertions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        RET=1
    else
        echo "PASS: $message"
    fi
}

assert_return() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $message"
        echo "  Expected Return Code: '$expected'"
        echo "  Actual Return Code:   '$actual'"
        RET=1
    else
        echo "PASS: $message"
    fi
}

echo "--- Testing select_profile Logic ---"
RET=0

# Setup common profile data
PROFILES_NAME=("Instance1" "Instance2")
PROFILES_HOST=("127.0.0.1" "192.168.1.5")
PROFILES_PORT=("5432" "5432")
PROFILES_ADMIN=("postgres" "postgres")
PROFILES_DATA_DIR=("/var/lib/pgsql/data" "/var/lib/pgsql/data")
PROFILES_PSQL_VERS=("/usr/bin/psql" "/usr/bin/psql")

# Test Case 1: Automation Mode (TARGET_PROFILE_IDX set)
echo "Test Case 1: Automation Mode"
TARGET_PROFILE_IDX=1
unset IDX
select_profile > /dev/null
res=$?
assert_return "0" "$res" "Should return 0 in automation mode"
assert_equals "1" "$IDX" "IDX should be set to TARGET_PROFILE_IDX"

# Test Case 2: Interactive Mode - Valid Selection (Index 0)
echo "Test Case 2: Interactive Mode - Valid Selection (Index 0)"
unset TARGET_PROFILE_IDX
unset IDX
select_profile <<< "0" > /dev/null
res=$?
assert_return "0" "$res" "Should return 0 for valid input '0'"
assert_equals "0" "$IDX" "IDX should be 0"

# Test Case 3: Interactive Mode - Valid Selection (Index 1)
echo "Test Case 3: Interactive Mode - Valid Selection (Index 1)"
unset TARGET_PROFILE_IDX
unset IDX
select_profile <<< "1" > /dev/null
res=$?
assert_return "0" "$res" "Should return 0 for valid input '1'"
assert_equals "1" "$IDX" "IDX should be 1"

# Test Case 4: Interactive Mode - Invalid Selection (Out of bounds)
echo "Test Case 4: Interactive Mode - Invalid Selection (99)"
unset TARGET_PROFILE_IDX
unset IDX
select_profile <<< "99" > /dev/null
res=$?
assert_return "1" "$res" "Should return 1 for invalid input '99'"

# Test Case 5: Interactive Mode - Invalid Non-Numeric Selection (abc)
echo "Test Case 5: Interactive Mode - Invalid Non-Numeric Selection (abc)"
unset TARGET_PROFILE_IDX
unset IDX
select_profile <<< "abc" > /dev/null
res=$?
assert_return "1" "$res" "Should return 1 for non-numeric input 'abc'"

# Test Case 6: No Profiles Configured
echo "Test Case 6: No Profiles Configured"
# Backup profiles
PROFILES_NAME_BACKUP=("${PROFILES_NAME[@]}")
PROFILES_NAME=()
unset TARGET_PROFILE_IDX
unset IDX
select_profile > /dev/null
res=$?
assert_return "1" "$res" "Should return 1 when no profiles exist"
# Restore profiles
PROFILES_NAME=("${PROFILES_NAME_BACKUP[@]}")

# Test Case 7: Empty Input
echo "Test Case 7: Empty Input"
unset TARGET_PROFILE_IDX
unset IDX
select_profile <<< "" > /dev/null
res=$?
assert_return "1" "$res" "Should return 1 for empty input"

# Test Case 8: Automation Mode with Invalid Index
echo "Test Case 8: Automation Mode with Invalid Index"
TARGET_PROFILE_IDX="invalid"
unset IDX
select_profile > /dev/null
res=$?
assert_return "1" "$res" "Should return 1 when TARGET_PROFILE_IDX is invalid"

# Test Case 9: Verify Custom Prompt
echo "Test Case 9: Verify Custom Prompt"
unset TARGET_PROFILE_IDX
unset IDX
output=$(select_profile "Custom Prompt Text" <<< "0")
res=$?
assert_return "0" "$res" "Should return 0 for valid input with custom prompt"
if [[ "$output" == *"Custom Prompt Text"* ]]; then
    echo "PASS: Output contains custom prompt"
else
    echo "FAIL: Output does not contain custom prompt. Got: '$output'"
    RET=1
fi

# Test Case 10: Verify Default Prompt
echo "Test Case 10: Verify Default Prompt"
unset TARGET_PROFILE_IDX
unset IDX
output=$(select_profile <<< "0")
res=$?
assert_return "0" "$res" "Should return 0 for valid input with default prompt"
if [[ "$output" == *"Select Instance"* ]]; then
    echo "PASS: Output contains default prompt"
else
    echo "FAIL: Output does not contain default prompt. Got: '$output'"
    RET=1
fi

# Test Case 11: Verify List Output Format
echo "Test Case 11: Verify List Output Format"
unset TARGET_PROFILE_IDX
unset IDX
output=$(select_profile <<< "0")
# PROFILES_NAME=("Instance1" "Instance2")
# PROFILES_HOST=("127.0.0.1" "192.168.1.5")
expected_line1="0) Instance1 [Host: 127.0.0.1]"
expected_line2="1) Instance2 [Host: 192.168.1.5]"

if [[ "$output" == *"$expected_line1"* && "$output" == *"$expected_line2"* ]]; then
    echo "PASS: Output lists profiles correctly"
else
    echo "FAIL: Output does not list profiles correctly. Got: '$output'"
    RET=1
fi

# Test Case 12: Automation Mode - Out of Bounds Numeric Index
echo "Test Case 12: Automation Mode - Out of Bounds Numeric Index"
TARGET_PROFILE_IDX=99
unset IDX
select_profile > /dev/null
res=$?
assert_return "1" "$res" "Should return 1 for out of bounds index 99 in automation mode"

# Test Case 13: Sparse Arrays
echo "Test Case 13: Sparse Arrays"
PROFILES_NAME_BACKUP=("${PROFILES_NAME[@]}")
PROFILES_NAME=()
PROFILES_NAME[1]="Sparse1"
PROFILES_NAME[3]="Sparse2"
unset IDX
unset TARGET_PROFILE_IDX
# Select index 2 (missing)
select_profile <<< "2" > /dev/null
res=$?
assert_return "1" "$res" "Should return 1 for missing index 2 in sparse array"

# Select index 3 (valid)
unset IDX
select_profile <<< "3" > /dev/null
res=$?
assert_return "0" "$res" "Should return 0 for valid index 3 in sparse array"
assert_equals "3" "$IDX" "IDX should be 3"
PROFILES_NAME=("${PROFILES_NAME_BACKUP[@]}")

# Test Case 14: Leading Zeros
echo "Test Case 14: Leading Zeros"
unset IDX
unset TARGET_PROFILE_IDX
select_profile <<< "01" > /dev/null
res=$?
assert_return "0" "$res" "Should return 0 for input '01'"
# Check if IDX points to correct profile (index 1 is Instance2)
if [[ "${PROFILES_NAME[$IDX]}" == "Instance2" ]]; then
    echo "PASS: IDX correctly selects profile 'Instance2'"
else
    echo "FAIL: IDX selected '${PROFILES_NAME[$IDX]}' instead of 'Instance2'"
    RET=1
fi

# Test Case 15: Input with Leading/Trailing Spaces
echo "Test Case 15: Input with Leading/Trailing Spaces"
unset IDX
unset TARGET_PROFILE_IDX
select_profile <<< " 1 " > /dev/null
res=$?
assert_return "0" "$res" "Should return 0 for input with spaces ' 1 ' (trimmed by read)"
assert_equals "1" "$IDX" "IDX should be trimmed to '1'"

# Test Case 15b: Input with Internal Spaces
echo "Test Case 15b: Input with Internal Spaces"
unset IDX
unset TARGET_PROFILE_IDX
select_profile <<< "1 2" > /dev/null
res=$?
assert_return "1" "$res" "Should return 1 for input with internal spaces '1 2'"

# Test Case 16: Empty Host
echo "Test Case 16: Empty Host"
PROFILES_HOST_BACKUP=("${PROFILES_HOST[@]}")
PROFILES_HOST[0]=""
unset IDX
unset TARGET_PROFILE_IDX
output=$(select_profile <<< "0")
if [[ "$output" == *"Host: ]"* ]]; then
    echo "PASS: Output handles empty host correctly"
else
    echo "FAIL: Output format wrong for empty host. Got: '$output'"
    RET=1
fi
PROFILES_HOST=("${PROFILES_HOST_BACKUP[@]}")


if [[ "$RET" -eq 0 ]]; then
    echo "All select_profile tests passed!"
else
    echo "Some select_profile tests failed!"
fi
exit $RET
