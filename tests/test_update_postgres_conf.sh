#!/bin/bash

# tests/test_update_postgres_conf.sh

# Exit on error
set -e

# Path to the script under test
SETUP_SH="$(dirname "$0")/../modules/Setup.sh"

# Source Setup.sh to load the function
source "$SETUP_SH"

# Create a temporary config file
TEST_CONFIG=$(mktemp)
trap 'rm -f "$TEST_CONFIG"' EXIT

# Helper for assertions
assert_content() {
    local pattern="$1"
    local file="$2"
    local message="$3"
    if ! grep -q "$pattern" "$file"; then
        echo "FAILED: $message"
        echo "Expected pattern: $pattern"
        echo "File content:"
        cat "$file"
        exit 1
    fi
}

assert_not_content() {
    local pattern="$1"
    local file="$2"
    local message="$3"
    if grep -q "$pattern" "$file"; then
        echo "FAILED: $message"
        echo "Unexpected pattern: $pattern"
        echo "File content:"
        cat "$file"
        exit 1
    fi
}

echo "Starting tests for update_postgres_conf..."

# 1. Test: Append a new key-value pair
echo "Test 1: Appending new key..."
echo "# Initial Config" > "$TEST_CONFIG"
update_postgres_conf "$TEST_CONFIG" "new_key" "new_value"

assert_content "^new_key = new_value$" "$TEST_CONFIG" "Failed to append new key"

# 2. Test: Update an existing key-value pair
echo "Test 2: Updating existing key..."
echo "existing_key = old_value" > "$TEST_CONFIG"
update_postgres_conf "$TEST_CONFIG" "existing_key" "updated_value"

assert_content "^existing_key = updated_value$" "$TEST_CONFIG" "Failed to update existing key"
assert_not_content "old_value" "$TEST_CONFIG" "Old value still present"

# 3. Test: Update existing key with surrounding whitespace
echo "Test 3: Updating existing key with whitespace..."
echo "  spaced_key  =  old_value  " > "$TEST_CONFIG"
update_postgres_conf "$TEST_CONFIG" "spaced_key" "updated_value"

# The function replaces the line with: key = value
# So we expect "spaced_key = updated_value"
assert_content "^spaced_key = updated_value$" "$TEST_CONFIG" "Failed to update spaced key correctly"
assert_not_content "old_value" "$TEST_CONFIG" "Old spaced value still present"

# 4. Test: Ensure other lines are preserved
echo "Test 4: Preserving other lines..."
cat <<EOF > "$TEST_CONFIG"
# Comment line
other_key = other_value
target_key = old_target_value
EOF

update_postgres_conf "$TEST_CONFIG" "target_key" "new_target_value"

assert_content "^# Comment line$" "$TEST_CONFIG" "Comment line removed"
assert_content "^other_key = other_value$" "$TEST_CONFIG" "Other key removed"
assert_content "^target_key = new_target_value$" "$TEST_CONFIG" "Target key not updated"

# 5. Test: Update value with special characters (e.g. paths)
echo "Test 5: Updating with special characters..."
echo "path_key = /old/path" > "$TEST_CONFIG"
update_postgres_conf "$TEST_CONFIG" "path_key" "/new/path/value"

assert_content "^path_key = /new/path/value$" "$TEST_CONFIG" "Failed to update path value"

# 6. Test: Update value with quotes
echo "Test 6: Updating with quotes..."
echo "quote_key = 'old_value'" > "$TEST_CONFIG"
update_postgres_conf "$TEST_CONFIG" "quote_key" "'new_value'"

assert_content "^quote_key = 'new_value'$" "$TEST_CONFIG" "Failed to update quoted value"


echo "All tests passed for update_postgres_conf!"
