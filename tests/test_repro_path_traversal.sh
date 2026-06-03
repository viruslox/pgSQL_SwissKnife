#!/bin/bash

# Reproduction script for Path Traversal vulnerability
# Goal: Ensure Backup.sh handles relative SUITE_DIR safely and rejects invalid SUITE_DIR

# Setup Test Environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

echo "Test Directory: $TEST_DIR"

# Mock Binaries (psql, pg_dump, gzip)
MOCK_BIN_DIR="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN_DIR"
export PATH="$MOCK_BIN_DIR:$PATH"

# Mock psql
cat << 'EOF' > "$MOCK_BIN_DIR/psql"
#!/bin/bash
# Mock psql returning a list of databases
if [[ "$*" == *"SELECT datname FROM pg_database"* ]]; then
    echo "db1"
    exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/psql"

# Mock pg_dump
cat << 'EOF' > "$MOCK_BIN_DIR/pg_dump"
#!/bin/bash
echo "DUMP CONTENT"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/pg_dump"

# Mock gzip
cat << 'EOF' > "$MOCK_BIN_DIR/gzip"
#!/bin/bash
cat
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/gzip"

# Mock Modules Directory
MODULES_DIR="$TEST_DIR/modules"
mkdir -p "$MODULES_DIR"

# Copy Backup.sh to modules dir
if [ -f "../modules/Backup.sh" ]; then
    cp "../modules/Backup.sh" "$MODULES_DIR/"
else
    cp "modules/Backup.sh" "$MODULES_DIR/"
fi

# --- Helper to create mock common.sh ---
create_mock_common() {
    local suite_dir_val="$1"
    cat << EOF > "$MODULES_DIR/common.sh"
#!/bin/bash
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$suite_dir_val"
CONFIG_FILE="\${SCRIPT_DIR}/config.conf"

load_config() {
    PROFILES_NAME=("TestProfile")
    PROFILES_HOST=("localhost")
    PROFILES_PORT=("5432")
    PROFILES_ADMIN=("postgres")
    PROFILES_DATA_DIR=("/tmp")
    PROFILES_PSQL_VERS=("")
    IDX=0
}

select_profile() {
    IDX=0
    return 0
}

setup_connection() {
    DB_HOST="localhost"
    DB_PORT="5432"
    DB_USER="postgres"
}

get_database_list() {
    echo "db1"
}

resolve_tool() {
    local TOOL_NAME="\$1"
    local VAR_NAME="BIN_\$(echo "\$TOOL_NAME" | tr '[:lower:]' '[:upper:]')"
    printf -v "\$VAR_NAME" "%s" "$MOCK_BIN_DIR/\$TOOL_NAME"
    return 0
}

require_tool() {
    return 0
}

require_tools() {
    return 0
}
EOF
    chmod +x "$MODULES_DIR/common.sh"
}

# Create a dummy config
touch "$MODULES_DIR/config.conf"

# --- Test Case 1: Relative SUITE_DIR from correct directory ---
echo "--- Test Case 1: Relative SUITE_DIR from correct directory ---"
create_mock_common ".." # Relative to CWD (if run from modules)

cd "$MODULES_DIR"
if bash ./Backup.sh > output1.log 2>&1; then
    EXPECTED_BACKUP_DIR="$TEST_DIR/backups/TestProfile"
    if [[ -d "$EXPECTED_BACKUP_DIR" ]]; then
        echo "PASS: Backup created at correct absolute path: $EXPECTED_BACKUP_DIR"
    else
        echo "FAIL: Backup directory not found at: $EXPECTED_BACKUP_DIR"
        cat output1.log
        exit 1
    fi
else
    echo "FAIL: Backup.sh failed."
    cat output1.log
    exit 1
fi

# --- Test Case 2: Empty SUITE_DIR (Should FAIL) ---
echo "--- Test Case 2: Empty SUITE_DIR (Should FAIL) ---"
create_mock_common "" # Empty SUITE_DIR

# If SUITE_DIR is empty, cd "" stays in CWD.
# BACKUP_ROOT becomes CWD/backups.
# We run from TEST_DIR. So it would create TEST_DIR/backups.
# But we WANT it to fail because SUITE_DIR is invalid.

cd "$TEST_DIR"
# Run Backup.sh (sourced from modules)
if bash "$MODULES_DIR/Backup.sh" > output2.log 2>&1; then
    echo "FAIL: Backup.sh should have failed with empty SUITE_DIR."
    # Check if it created backup in CWD
    if [[ -d "$TEST_DIR/backups/TestProfile" ]]; then
        echo "VULNERABILITY CONFIRMED: Backup created in CWD/backups when SUITE_DIR is empty."
    fi
    exit 1
else
    echo "PASS: Backup.sh failed as expected with empty SUITE_DIR."
    grep "ERR" output2.log || true
fi

exit 0
