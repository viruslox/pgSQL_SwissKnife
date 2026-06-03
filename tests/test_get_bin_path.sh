#!/bin/bash

# tests/test_get_bin_path.sh

# Exit on error
set -e

# Path to the script under test
SETUP_SH="$(dirname "$0")/../modules/Setup.sh"

# 1. Source Setup.sh
# It should not execute its main loop or binary checks because it's being sourced.
source "$SETUP_SH"

# 2. Set up Test Environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create mock bin directories
mkdir -p "$TEST_DIR/bin"
mkdir -p "$TEST_DIR/mock_bin"
mkdir -p "$TEST_DIR/usr/bin"
mkdir -p "$TEST_DIR/opt/pg/bin"

# Update PATH: mock_bin first (for find), then bin (for standard binaries)
export PATH="$TEST_DIR/mock_bin:$TEST_DIR/bin:$PATH"

# Mock find
cat << 'EOF' > "$TEST_DIR/mock_bin/find"
#!/bin/bash
if [[ -n "$MOCK_FIND_RESULTS" ]]; then
    # Return mocked results
    # Use printf to print each result on a new line
    # (Use word splitting on MOCK_FIND_RESULTS to separate paths)
    for res in $MOCK_FIND_RESULTS; do
        echo "$res"
    done
fi
EOF
chmod +x "$TEST_DIR/mock_bin/find"

# Mock save_config (to prevent writing to real file and verify calls)
save_config() {
    echo "save_config called"
}

# Helper to assert return value
assert_ret_val() {
    local expected="$1"
    local message="$2"
    if [[ "$RET_VAL" != "$expected" ]]; then
        echo "FAILED: $message. Expected '$expected', got '$RET_VAL'"
        exit 1
    fi
}

# Initialize required arrays
PROFILES_NAME=("ProfileOne")
PROFILES_PSQL_VERS=("")
PROFILES_HOST=("localhost")

echo "--- Starting Tests for get_bin_path ---"

# --- Case 1: Binary defined in Profile ---
echo "Test Case 1: Binary defined in Profile"
PROFILES_PSQL_VERS[0]="$TEST_DIR/bin"
touch "$TEST_DIR/bin/testbin"
chmod +x "$TEST_DIR/bin/testbin"

get_bin_path 0 "testbin"
assert_ret_val "$TEST_DIR/bin/testbin" "Should find binary in profile path"

# --- Case 2: Binary found in global PATH ---
echo "Test Case 2: Binary found in global PATH"
PROFILES_PSQL_VERS[0]=""
# Ensure it's not in profile, but in PATH (which includes TEST_DIR/bin)
touch "$TEST_DIR/bin/globalbin"
chmod +x "$TEST_DIR/bin/globalbin"

get_bin_path 0 "globalbin"
assert_ret_val "$TEST_DIR/bin/globalbin" "Should find binary in global PATH"

# --- Case 3: Binary found relative to BIN_PSQL ---
echo "Test Case 3: Binary found relative to BIN_PSQL"
# Create a separate directory for this test
mkdir -p "$TEST_DIR/pg_home/bin"
touch "$TEST_DIR/pg_home/bin/psql"
touch "$TEST_DIR/pg_home/bin/createdb"
chmod +x "$TEST_DIR/pg_home/bin/psql"
chmod +x "$TEST_DIR/pg_home/bin/createdb"

BIN_PSQL="$TEST_DIR/pg_home/bin/psql"
get_bin_path 0 "createdb"
assert_ret_val "$TEST_DIR/pg_home/bin/createdb" "Should find binary relative to BIN_PSQL"
unset BIN_PSQL

# --- Case 3b: Binary found via BIN_PSQL symlink ---
echo "Test Case 3b: Binary found via BIN_PSQL symlink"
mkdir -p "$TEST_DIR/real_pg/bin"
mkdir -p "$TEST_DIR/sym_pg/bin"
touch "$TEST_DIR/real_pg/bin/psql"
touch "$TEST_DIR/real_pg/bin/pg_dump"
chmod +x "$TEST_DIR/real_pg/bin/psql"
chmod +x "$TEST_DIR/real_pg/bin/pg_dump"

# Create symlink: sym_pg/bin/psql -> real_pg/bin/psql
ln -s "$TEST_DIR/real_pg/bin/psql" "$TEST_DIR/sym_pg/bin/psql"

BIN_PSQL="$TEST_DIR/sym_pg/bin/psql"
# pg_dump is only in real_pg/bin, not sym_pg/bin
get_bin_path 0 "pg_dump"
assert_ret_val "$TEST_DIR/real_pg/bin/pg_dump" "Should find binary via BIN_PSQL symlink resolution"
unset BIN_PSQL

# --- Case 4: Interactive Search - Single Result ---
echo "Test Case 4: Interactive Search - Single Result"
MOCK_BIN_PATH="$TEST_DIR/opt/pg/bin/foundbin"
mkdir -p "$(dirname "$MOCK_BIN_PATH")"
touch "$MOCK_BIN_PATH"
chmod +x "$MOCK_BIN_PATH"

export MOCK_FIND_RESULTS="$MOCK_BIN_PATH"
get_bin_path 0 "foundbin"
assert_ret_val "$MOCK_BIN_PATH" "Should find binary via search"

# Verify profile update
if [[ "${PROFILES_PSQL_VERS[0]}" != "$(dirname "$MOCK_BIN_PATH")" ]]; then
    echo "FAILED: Profile not updated correctly. Got '${PROFILES_PSQL_VERS[0]}'"
    exit 1
fi

# --- Case 5: Interactive Search - Multiple Results ---
echo "Test Case 5: Interactive Search - Multiple Results"
BIN1="$TEST_DIR/opt/pg/bin/multi1"
BIN2="$TEST_DIR/opt/pg/bin/multi2"
touch "$BIN1" "$BIN2"
chmod +x "$BIN1" "$BIN2"

export MOCK_FIND_RESULTS="$BIN1 $BIN2"
# Use redirection to avoid subshell so RET_VAL is preserved
get_bin_path 0 "multi" <<< "0"
assert_ret_val "$BIN1" "Should select first binary from multiple results"

# --- Case 6: Not Found ---
echo "Test Case 6: Not Found"
export MOCK_FIND_RESULTS=""
if get_bin_path 0 "nonexistent"; then
    echo "FAILED: Should have returned error for nonexistent binary"
    exit 1
fi

echo "All tests passed!"
