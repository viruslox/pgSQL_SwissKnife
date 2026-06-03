#!/bin/bash

# tests/test_create_user.sh

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
        echo "File content:"
        cat "$file"
        exit 1
    fi
}

assert_no_grep() {
    local pattern="$1"
    local file="$2"
    local message="$3"
    if grep -q "$pattern" "$file"; then
        echo "FAILED: $message"
        echo "File content:"
        cat "$file"
        exit 1
    fi
}

# 2. Setup Test Environment

# Create a temporary workspace
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock Bin Directory
MOCK_BIN_DIR="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN_DIR"
export PATH="$MOCK_BIN_DIR:$PATH"

# Log file for psql calls
MOCK_LOG="$TEST_DIR/psql_calls.log"
# File to control existence check
MOCK_USER_EXISTS="$TEST_DIR/user_exists"

# Create Mock psql
cat << 'EOF' > "$MOCK_BIN_DIR/psql"
#!/bin/bash
ARGS=("$@")
# Log the call
echo "CALLED: psql ${ARGS[*]}" >> "$TEST_LOG"
echo "ENV: PGPASSWORD=$PGPASSWORD" >> "$TEST_LOG"

# Check for existence check query
# create_user uses: -tAc "SELECT 1 FROM pg_roles WHERE rolname=:'user'"
if [[ "${ARGS[*]}" == *"SELECT 1 FROM pg_roles"* ]]; then
    if [ -f "$USER_EXISTS_FILE" ]; then
        echo "1"
    else
        echo ""
    fi
fi

# Check for database list query
# get_database_list uses: -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false;"
if [[ "${ARGS[*]}" == *"SELECT datname FROM pg_database"* ]]; then
    echo "testdb"
    echo "otherdb"
fi
EOF

# Inject variables into the mock script
sed -i "s|\$TEST_LOG|$MOCK_LOG|g" "$MOCK_BIN_DIR/psql"
sed -i "s|\$USER_EXISTS_FILE|$MOCK_USER_EXISTS|g" "$MOCK_BIN_DIR/psql"

chmod +x "$MOCK_BIN_DIR/psql"

# Mock Profile Data
DATA_DIR="$TEST_DIR/data"
mkdir -p "$DATA_DIR"
PROFILES_NAME=("TestProfile")
PROFILES_HOST=("localhost")
PROFILES_PORT=("5432")
PROFILES_ADMIN=("postgres")
PROFILES_DATA_DIR=("$DATA_DIR")
PROFILES_PSQL_VERS=("")
# Empty PROFILES_PSQL_VERS ensures get_bin_path searches PATH and finds our mock psql

# 3. Test Cases

# Set Automation Mode to bypass select_profile prompt
TARGET_PROFILE_IDX=0

echo "--- Test Case 1: Create New User ---"
rm -f "$MOCK_LOG" "$MOCK_USER_EXISTS"

# Inputs:
# 1. Admin Password (for get_admin_creds)
# 2. Username
# 3. User Password
# 4. Grant access? (y)
# 5. Database to grant
(
    echo "adminpass"
    echo "newuser"
    echo "newuserpass"
    echo "y"
    echo "testdb"
) | create_user

# Verify
# Check that commands were called with interpolated values
assert_grep "CALLED: psql.*CREATE USER \"newuser\" WITH PASSWORD 'newuserpass'" "$MOCK_LOG" "CREATE USER not called correctly"
assert_grep "CALLED: psql.*GRANT ALL PRIVILEGES ON DATABASE \"testdb\"" "$MOCK_LOG" "GRANT PRIVILEGES not called correctly"

# Check Environment
assert_grep "ENV: PGPASSWORD=adminpass" "$MOCK_LOG" "PGPASSWORD not set correctly"

echo "SUCCESS: Test Case 1 Passed."

echo "--- Test Case 2: Update Existing User ---"
rm -f "$MOCK_LOG"
touch "$MOCK_USER_EXISTS"

# Inputs:
# 1. Admin Password
# 2. Username
# 3. New Password
# 4. Grant access? (n)
# 5. (Skipped: Database to grant)
(
    echo "adminpass"
    echo "existinguser"
    echo "updatedpass"
    echo "n"
) | create_user

# Verify
assert_grep "CALLED: psql.*ALTER USER \"existinguser\" WITH PASSWORD 'updatedpass'" "$MOCK_LOG" "ALTER USER not called correctly"
assert_no_grep "CREATE USER" "$MOCK_LOG" "CREATE USER should not be called"
assert_no_grep "GRANT ALL PRIVILEGES" "$MOCK_LOG" "GRANT should not be called"
assert_grep "ENV: PGPASSWORD=adminpass" "$MOCK_LOG" "PGPASSWORD not set correctly"

echo "SUCCESS: Test Case 2 Passed."

echo "All create_user tests passed."
