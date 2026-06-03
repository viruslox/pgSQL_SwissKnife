#!/bin/bash

# tests/test_create_database.sh

# Exit on error
set -e

# Path to the script under test
SETUP_SH="$(dirname "$0")/../modules/Setup.sh"

# 1. Source Setup.sh (but prevent main loop)
if [ -f "$SETUP_SH" ]; then
    source "$SETUP_SH"
else
    echo "FAILED: Setup.sh not found."
    exit 1
fi

# 2. Setup Test Environment

# Create a temporary workspace
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock Bin Directory
MOCK_BIN_DIR="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN_DIR"

# Logs for mock calls
PSQL_LOG="$TEST_DIR/psql.log"
CREATEDB_LOG="$TEST_DIR/createdb.log"
PG_DUMP_LOG="$TEST_DIR/pg_dump.log"

# Mock psql
cat << 'EOF' > "$MOCK_BIN_DIR/psql"
#!/bin/bash
# Log arguments
echo "$@" >> "$PSQL_LOG"

# Simulate existence
if [[ "$@" == *"SELECT 1 FROM pg_database"* ]]; then
    # Check if query contains datname='existing_db'
    if [[ "$@" == *"datname='existing_db'"* ]]; then
        echo "1"
    else
        echo ""
    fi
    exit 0
fi

# Default success
exit 0
EOF
sed -i "s|\$PSQL_LOG|$PSQL_LOG|g" "$MOCK_BIN_DIR/psql"
chmod +x "$MOCK_BIN_DIR/psql"

# Mock createdb
cat << 'EOF' > "$MOCK_BIN_DIR/createdb"
#!/bin/bash
echo "$@" >> "$CREATEDB_LOG"
exit 0
EOF
sed -i "s|\$CREATEDB_LOG|$CREATEDB_LOG|g" "$MOCK_BIN_DIR/createdb"
chmod +x "$MOCK_BIN_DIR/createdb"

# Mock pg_dump
cat << 'EOF' > "$MOCK_BIN_DIR/pg_dump"
#!/bin/bash
echo "$@" >> "$PG_DUMP_LOG"
exit 0
EOF
sed -i "s|\$PG_DUMP_LOG|$PG_DUMP_LOG|g" "$MOCK_BIN_DIR/pg_dump"
chmod +x "$MOCK_BIN_DIR/pg_dump"

# Add mock bin to PATH
export PATH="$MOCK_BIN_DIR:$PATH"

# Mock Profile Data
DATA_DIR="$TEST_DIR/data"
mkdir -p "$DATA_DIR"
PROFILES_NAME=("TestProfile")
PROFILES_HOST=("localhost")
PROFILES_PORT=("5432")
PROFILES_ADMIN=("postgres")
PROFILES_DATA_DIR=("$DATA_DIR")
PROFILES_PSQL_VERS=("$MOCK_BIN_DIR") # Point directly to mocks

# Set Automation Mode
TARGET_PROFILE_IDX=0

# Helper function to run test case
run_test_case() {
    local CASE_NAME="$1"
    local INPUTS="$2"

    echo "--------------------------------"
    echo "Running Case: $CASE_NAME"

    # Clear logs
    > "$PSQL_LOG"
    > "$CREATEDB_LOG"
    > "$PG_DUMP_LOG"

    # Run create_database with inputs
    # Inputs: Password (empty) -> DB Name -> Action (if needed)
    # Disable set -e because create_database relies on non-fatal command failures (like get_bin_path)
    set +e
    echo -e "$INPUTS" | create_database
    set -e
}

# Case 1: Create New Database
# Input: (password), new_db
run_test_case "New Database" "\nnew_db"

# Assertions
if ! grep -q "new_db" "$CREATEDB_LOG"; then
    echo "FAILED: createdb was not called for new_db."
    echo "CREATEDB Log Content:"
    cat "$CREATEDB_LOG"
    exit 1
fi
if grep -q "DROP DATABASE" "$PSQL_LOG"; then
    echo "FAILED: unexpected DROP DATABASE."
    exit 1
fi

# Case 2: Existing Database - Skip (Option 3)
# Input: (password), existing_db, 3
run_test_case "Existing Database - Skip" "\nexisting_db\n3"

# Assertions
if grep -q "existing_db" "$CREATEDB_LOG"; then
    echo "FAILED: createdb called for skipped database."
    exit 1
fi
if grep -q "DROP DATABASE" "$PSQL_LOG"; then
    echo "FAILED: unexpected DROP DATABASE."
    exit 1
fi

# Case 3: Existing Database - Drop and Recreate (Option 2)
# Input: (password), existing_db, 2
run_test_case "Existing Database - Drop" "\nexisting_db\n2"

# Assertions
if ! grep -q "DROP DATABASE \"existing_db\"" "$PSQL_LOG"; then
    echo "FAILED: DROP DATABASE \"existing_db\" not called."
    # Debug
    echo "PSQL Log Content:"
    cat "$PSQL_LOG"
    exit 1
fi
if ! grep -q "existing_db" "$CREATEDB_LOG"; then
    echo "FAILED: createdb not called after drop."
    exit 1
fi

# Case 4: Fallback to psql (createdb missing)
rm "$MOCK_BIN_DIR/createdb"
# Input: (password), psql_db
run_test_case "Fallback to psql" "\npsql_db"

# Assertions
if grep -q "CREATE DATABASE \"psql_db\"" "$PSQL_LOG"; then
    echo "SUCCESS: Fallback to psql worked."
else
    echo "FAILED: psql CREATE DATABASE \"psql_db\" not called."
    echo "PSQL Log Content:"
    cat "$PSQL_LOG"
    exit 1
fi

echo "--------------------------------"
echo "ALL TESTS PASSED"
exit 0
