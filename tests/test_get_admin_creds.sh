#!/bin/bash

# tests/test_get_admin_creds.sh

# Exit on error to fail fast
set -e

# Path to the script under test
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SH="${TEST_DIR}/../modules/Setup.sh"

# Source Setup.sh to load functions
# We suppress initial output if any
source "$SETUP_SH" > /dev/null 2>&1

# Reset Environment
PROFILES_NAME=()
PROFILES_HOST=()
PROFILES_PORT=()
PROFILES_ADMIN=()
PROFILES_DATA_DIR=()
PROFILES_PSQL_VERS=()

unset PGPASSWORD

# Define Helper Assertions
assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [[ "$expected" != "$actual" ]]; then
        echo "FAILED: $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        return 1
    fi
}

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local message="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "FAILED: $message"
        echo "  Needle:   '$needle'"
        echo "  Haystack: '$haystack'"
        return 1
    fi
}

assert_unset() {
    local var_name="$1"
    local message="$2"
    if [[ -n "${!var_name}" ]]; then
        echo "FAILED: $message"
        echo "  Variable '$var_name' is set to '${!var_name}'"
        return 1
    fi
}

# --- Test Runner ---
FAILURES=0

run_test() {
    local name="$1"
    shift
    echo "Running Test: $name"
    # Run test in subshell to isolate environment changes
    if ( "$@" ); then
        echo "PASSED: $name"
    else
        echo "FAILED: $name"
        FAILURES=$((FAILURES + 1))
    fi
    echo "---------------------------------------------------"
}

# --- Test Cases ---

test_simple_password() {
    # Setup
    PROFILES_ADMIN=("admin_user")
    IDX=0
    unset PGPASSWORD

    # Run in subshell, write PGPASSWORD to a temp file
    local PASS_FILE=$(mktemp)
    local OUT_FILE=$(mktemp)

    (
        get_admin_creds <<< "secret123" > "$OUT_FILE" 2>&1
        echo "$PGPASSWORD" > "$PASS_FILE"
    )

    local ACTUAL_PASS=$(cat "$PASS_FILE")
    local ACTUAL_OUT=$(cat "$OUT_FILE")
    rm "$PASS_FILE" "$OUT_FILE"

    assert_eq "secret123" "$ACTUAL_PASS" "PGPASSWORD should be set to input" || return 1
    assert_contains "Enter password for admin user 'admin_user'" "$ACTUAL_OUT" "Prompt should contain username" || return 1
}

test_special_chars() {
    # Setup
    PROFILES_ADMIN=("admin_user")
    IDX=0
    unset PGPASSWORD

    # Password with spaces, quotes, and backslashes
    local RAW_PASS='pass with spaces "quotes" and \backslashes'

    local PASS_FILE=$(mktemp)

    (
        get_admin_creds <<< "$RAW_PASS" > /dev/null 2>&1
        # Use printf to avoid echo interpreting flags
        printf "%s" "$PGPASSWORD" > "$PASS_FILE"
    )

    local ACTUAL_PASS=$(cat "$PASS_FILE")
    rm "$PASS_FILE"

    assert_eq "$RAW_PASS" "$ACTUAL_PASS" "PGPASSWORD should preserve special characters" || return 1
}

test_empty_password() {
    # Setup
    PROFILES_ADMIN=("admin_user")
    IDX=0
    export PGPASSWORD="pre_existing_value"

    local PASS_FILE=$(mktemp)

    (
        get_admin_creds <<< "" > /dev/null 2>&1
        if [[ -z "$PGPASSWORD" ]]; then
            echo "UNSET" > "$PASS_FILE"
        else
            echo "SET:$PGPASSWORD" > "$PASS_FILE"
        fi
    )

    local ACTUAL_STATE=$(cat "$PASS_FILE")
    rm "$PASS_FILE"

    assert_eq "UNSET" "$ACTUAL_STATE" "PGPASSWORD should be unset on empty input" || return 1
}

test_whitespace_preservation() {
    # Setup
    PROFILES_ADMIN=("admin_user")
    IDX=0
    unset PGPASSWORD

    # Password with leading/trailing spaces
    local RAW_PASS="  spacey_pass  "
    local EXPECTED_PASS="  spacey_pass  "

    local PASS_FILE=$(mktemp)

    (
        get_admin_creds <<< "$RAW_PASS" > /dev/null 2>&1
        printf "%s" "$PGPASSWORD" > "$PASS_FILE"
    )

    local ACTUAL_PASS=$(cat "$PASS_FILE")
    rm "$PASS_FILE"

    assert_eq "$EXPECTED_PASS" "$ACTUAL_PASS" "Leading/Trailing spaces should be preserved" || return 1
}

# --- Execution ---

run_test "Simple Password" test_simple_password
run_test "Special Characters (Spaces, Quotes, Backslashes)" test_special_chars
run_test "Empty Password (Peer Auth)" test_empty_password
run_test "Whitespace Preservation" test_whitespace_preservation

if [[ "$FAILURES" -eq 0 ]]; then
    echo "All tests passed successfully."
    exit 0
else
    echo "$FAILURES tests failed."
    exit 1
fi
