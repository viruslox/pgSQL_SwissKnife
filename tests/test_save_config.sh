#!/bin/bash

# tests/test_save_config.sh

# Exit on error
set -e

# Path to the script under test
SETUP_SH="$(dirname "$0")/../modules/Setup.sh"

# 1. Source Setup.sh
# It should not execute its main loop or binary checks because it's being sourced.
source "$SETUP_SH"

# Helper for assertions
assert_grep() {
    local pattern="$1"
    local file="$2"
    local message="$3"
    if ! grep -q "$pattern" "$file"; then
        echo "FAILED: $message"
        exit 1
    fi
}

# 2. Set up mock data
export CUSTOM_ENV_PATH="/mock/bin"
export PROFILES_NAME=("ProfileOne" "ProfileTwo")
export PROFILES_HOST=("1.2.3.4" "5.6.7.8")
export PROFILES_PORT=("5432" "5433")
export PROFILES_ADMIN=("admin1" "admin2")
export PROFILES_DATA_DIR=("/data/one" "/data/two")
export PROFILES_PSQL_VERS=("/usr/local/bin" "/opt/bin")

# 3. Redirect output to a temporary file
TEST_CONFIG=$(mktemp)
trap 'rm -f "$TEST_CONFIG"' EXIT
CONFIG_FILE="$TEST_CONFIG"

# 4. Call save_config
save_config

# 5. Verifications
echo "Verifying generated config..."

# Verification: File exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "FAILED: Config file not created"
    exit 1
fi

# Verification: Permissions (should be 600)
# Use a more portable way to get permissions if stat -c %a fails
if stat -c "%a" "$CONFIG_FILE" >/dev/null 2>&1; then
    PERMS=$(stat -c "%a" "$CONFIG_FILE")
else
    # Fallback for BSD stat or others
    PERMS=$(stat -f "%Lp" "$CONFIG_FILE" 2>/dev/null || echo "unknown")
fi

if [ "$PERMS" != "600" ]; then
    echo "FAILED: Incorrect permissions: $PERMS (expected 600)"
    exit 1
fi

# Verification: Content
# Check CUSTOM_ENV_PATH
assert_grep "CUSTOM_ENV_PATH=\"/mock/bin\"" "$CONFIG_FILE" "CUSTOM_ENV_PATH missing or incorrect"
assert_grep "export PATH=\"\$CUSTOM_ENV_PATH:\$PATH\"" "$CONFIG_FILE" "PATH export missing or incorrect"

# Check Profile 0
assert_grep "PROFILES_NAME\[0\]=\"ProfileOne\"" "$CONFIG_FILE" "ProfileOne missing"
assert_grep "PROFILES_HOST\[0\]=\"1.2.3.4\"" "$CONFIG_FILE" "Host 0 missing"
assert_grep "PROFILES_PORT\[0\]=\"5432\"" "$CONFIG_FILE" "Port 0 missing"
assert_grep "PROFILES_ADMIN\[0\]=\"admin1\"" "$CONFIG_FILE" "Admin 0 missing"
assert_grep "PROFILES_DATA_DIR\[0\]=\"/data/one\"" "$CONFIG_FILE" "Data Dir 0 missing"
assert_grep "PROFILES_PSQL_VERS\[0\]=\"/usr/local/bin\"" "$CONFIG_FILE" "PSQL Vers 0 missing"

# Check Profile 1
assert_grep "PROFILES_NAME\[1\]=\"ProfileTwo\"" "$CONFIG_FILE" "ProfileTwo missing"
assert_grep "PROFILES_HOST\[1\]=\"5.6.7.8\"" "$CONFIG_FILE" "Host 1 missing"
assert_grep "PROFILES_PSQL_VERS\[1\]=\"/opt/bin\"" "$CONFIG_FILE" "PSQL Vers 1 missing"

echo "All verifications passed for save_config!"
