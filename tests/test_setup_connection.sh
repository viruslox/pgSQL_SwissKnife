#!/bin/bash

# tests/test_setup_connection.sh

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
        exit 1
    else
        echo "PASS: $message"
    fi
}

assert_unset() {
    local var_name="$1"
    local message="$2"
    if [[ -n "${!var_name}" ]]; then
        echo "FAIL: $message"
        echo "  Expected '$var_name' to be unset, but it is set to '${!var_name}'"
        exit 1
    else
        echo "PASS: $message"
    fi
}

echo "--- Testing setup_connection Logic ---"

# --- NON-INTERACTIVE TESTS ---

# Test Case 1: Basic setup from profiles (Remote Host)
echo "Test Case 1: Basic setup from profiles (Remote Host)"
PROFILES_HOST=("192.168.1.10")
PROFILES_PORT=("5432")
PROFILES_ADMIN=("postgres")
PROFILES_DATA_DIR=("/var/lib/postgresql/13/main")
IDX=0
TARGET_PROFILE_IDX=0 # skip interactive prompt
unset PGPASSWORD

setup_connection

assert_equals "192.168.1.10" "$DB_HOST" "DB_HOST should match profile host"
assert_equals "5432" "$DB_PORT" "DB_PORT should match profile port"
assert_equals "postgres" "$DB_USER" "DB_USER should match profile admin"

# Test Case 2: Switch to socket (localhost) with no password
echo "Test Case 2: Switch to socket (localhost) with no password"
PROFILES_HOST=("localhost")
PROFILES_PORT=("5432")
PROFILES_ADMIN=("postgres")
PROFILES_DATA_DIR=("/var/run/postgresql")
IDX=0
TARGET_PROFILE_IDX=0
unset PGPASSWORD

setup_connection

assert_equals "/var/run/postgresql" "$DB_HOST" "DB_HOST should switch to socket dir for localhost"

# Test Case 3: Switch to socket (127.0.0.1) with no password
echo "Test Case 3: Switch to socket (127.0.0.1) with no password"
PROFILES_HOST=("127.0.0.1")
PROFILES_DATA_DIR=("/tmp")
IDX=0
TARGET_PROFILE_IDX=0
unset PGPASSWORD

setup_connection

assert_equals "/tmp" "$DB_HOST" "DB_HOST should switch to socket dir for 127.0.0.1"

# Test Case 4: Switch to socket (::1) with no password
echo "Test Case 4: Switch to socket (::1) with no password"
PROFILES_HOST=("::1")
PROFILES_DATA_DIR=("/tmp")
IDX=0
TARGET_PROFILE_IDX=0
unset PGPASSWORD

setup_connection

assert_equals "/tmp" "$DB_HOST" "DB_HOST should switch to socket dir for ::1"

# Test Case 5: No switch if Password is set (localhost)
echo "Test Case 5: No switch if Password is set (localhost)"
PROFILES_HOST=("localhost")
PROFILES_DATA_DIR=("/var/run/postgresql")
IDX=0
TARGET_PROFILE_IDX=0
export PGPASSWORD="secretpassword"

setup_connection

assert_equals "localhost" "$DB_HOST" "DB_HOST should remain localhost if PGPASSWORD is set"
unset PGPASSWORD

# Test Case 6: No switch if Data Dir is empty (localhost)
echo "Test Case 6: No switch if Data Dir is empty (localhost)"
PROFILES_HOST=("localhost")
PROFILES_DATA_DIR=("")
IDX=0
TARGET_PROFILE_IDX=0
unset PGPASSWORD

setup_connection

assert_equals "localhost" "$DB_HOST" "DB_HOST should remain localhost if DATA_DIR is empty"

# Test Case 7: No switch for Remote Host even if no password
echo "Test Case 7: No switch for Remote Host even if no password"
PROFILES_HOST=("10.0.0.5")
PROFILES_DATA_DIR=("/var/run/postgresql")
IDX=0
TARGET_PROFILE_IDX=0
unset PGPASSWORD

setup_connection

assert_equals "10.0.0.5" "$DB_HOST" "DB_HOST should remain remote IP"


# --- INTERACTIVE TESTS ---

# Test Case 8: Interactive Password Input (No Switch)
echo "Test Case 8: Interactive Password Input (No Switch)"
PROFILES_HOST=("localhost")
PROFILES_DATA_DIR=("/var/run/postgresql")
IDX=0
export TEST_INTERACTIVE=true
unset TARGET_PROFILE_IDX
unset PGPASSWORD

setup_connection <<< "secretpassword"

assert_equals "secretpassword" "$PGPASSWORD" "PGPASSWORD should be set from interactive input"
assert_equals "localhost" "$DB_HOST" "DB_HOST should NOT switch to socket when password is provided"

# Test Case 9: Interactive Empty Password (Switch to Socket)
echo "Test Case 9: Interactive Empty Password (Switch to Socket)"
PROFILES_HOST=("localhost")
PROFILES_DATA_DIR=("/var/run/postgresql")
IDX=0
export TEST_INTERACTIVE=true
unset TARGET_PROFILE_IDX
export PGPASSWORD="oldpassword" # Should be cleared

setup_connection <<< ""

assert_unset "PGPASSWORD" "PGPASSWORD should be unset when empty input is provided"
assert_equals "/var/run/postgresql" "$DB_HOST" "DB_HOST should switch to socket when password is empty"

# Test Case 10: Interactive Override Pre-existing Password
echo "Test Case 10: Interactive Override Pre-existing Password"
PROFILES_HOST=("localhost")
PROFILES_DATA_DIR=("/var/run/postgresql")
IDX=0
export TEST_INTERACTIVE=true
unset TARGET_PROFILE_IDX
export PGPASSWORD="oldpassword"

setup_connection <<< "newpassword"

assert_equals "newpassword" "$PGPASSWORD" "PGPASSWORD should be updated from interactive input"
assert_equals "localhost" "$DB_HOST" "DB_HOST should NOT switch to socket when password is provided"


# --- AUTOMATION OVERRIDE TESTS ---

# Test Case 11: Automation Overrides Interactive (Prompt Skipped)
echo "Test Case 11: Automation Overrides Interactive (Prompt Skipped)"
PROFILES_HOST=("localhost")
PROFILES_DATA_DIR=("/var/run/postgresql")
IDX=0
# Both set: Automation should win
export TEST_INTERACTIVE=true
export TARGET_PROFILE_IDX=0
export PGPASSWORD="initial"

# We provide input "changed" via here-string.
# If prompt is NOT skipped, PGPASSWORD would become "changed".
# If prompt IS skipped, PGPASSWORD should remain "initial".
setup_connection <<< "changed"

assert_equals "initial" "$PGPASSWORD" "PGPASSWORD should NOT be updated (prompt skipped)"
# Since PGPASSWORD is "initial" (not empty), no socket switch
assert_equals "localhost" "$DB_HOST" "DB_HOST should remain localhost"

echo "All setup_connection tests passed!"
