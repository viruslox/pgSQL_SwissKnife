#!/bin/bash

# tests/test_create_instance.sh

# Exit on error
set -e

# Path to the script under test
SETUP_SH="$(dirname "$0")/../modules/Setup.sh"

# 1. Source Setup.sh
# It should not execute its main loop or binary checks because it's being sourced.
source "$SETUP_SH"

# Helper for assertions
assert_output_contains() {
    local output="$1"
    local expected="$2"
    if [[ "$output" != *"$expected"* ]]; then
        echo "FAILED: Output does not contain '$expected'"
        echo "Actual Output:"
        echo "$output"
        return 1
    fi
}

assert_file_exists() {
    if [ ! -f "$1" ]; then
        echo "FAILED: File '$1' does not exist."
        return 1
    fi
}

assert_grep() {
    local pattern="$1"
    local file="$2"
    local message="$3"
    if ! grep -q "$pattern" "$file"; then
        echo "FAILED: $message"
        echo "File content:"
        cat "$file"
        return 1
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

# Create Mock initdb
create_mock_initdb() {
    local EXIT_CODE="${1:-0}"
    cat << EOF > "$MOCK_BIN_DIR/initdb"
#!/bin/bash
TARGET_DIR=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -D)
            TARGET_DIR="\$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ -z "\$TARGET_DIR" ]; then
    echo "Error: No target directory specified."
    exit 1
fi

mkdir -p "\$TARGET_DIR"
# Create a dummy postgresql.conf with some content to be modified
echo "# PostgreSQL Configuration" > "\$TARGET_DIR/postgresql.conf"
echo "" >> "\$TARGET_DIR/postgresql.conf"
echo "listen_addresses = 'localhost'" >> "\$TARGET_DIR/postgresql.conf"
# Add dummy settings to ensure grep/sed works
echo "port = 5432" >> "\$TARGET_DIR/postgresql.conf"
echo "unix_socket_directories = '/tmp'" >> "\$TARGET_DIR/postgresql.conf"

exit $EXIT_CODE
EOF
    chmod +x "$MOCK_BIN_DIR/initdb"
}

# Override get_bin_path
# This allows us to control whether initdb is "found" or not without complex environment setup.
get_bin_path() {
    local P_IDX="$1"
    local BIN_NAME="$2"
    if [[ "$BIN_NAME" == "initdb" ]]; then
        if [[ "$MOCK_INITDB_MISSING" == "true" ]]; then
            RET_VAL=""
            return 1
        else
            RET_VAL="$MOCK_BIN_DIR/initdb"
            return 0
        fi
    fi
    # Call original if needed, but for this test we only care about initdb
    RET_VAL=""
    return 1
}

run_test_case() {
    local TEST_NAME="$1"
    local SETUP_FUNC="$2"
    local EXPECTED_OUTPUT="$3"
    local INPUT_STREAM="$4"

    echo "---------------------------------------------------"
    echo "Running Test: $TEST_NAME"

    # Reset Environment
    rm -rf "$TEST_DIR/data"
    DATA_DIR="$TEST_DIR/data"
    PROFILES_NAME=("TestProfile")
    PROFILES_HOST=("localhost")
    PROFILES_PORT=("5432")
    PROFILES_ADMIN=("postgres")
    PROFILES_DATA_DIR=("$DATA_DIR")
    PROFILES_PSQL_VERS=("")
    TARGET_PROFILE_IDX=0
    MOCK_INITDB_MISSING="false"

    # Override BACKUP_DIR to keep repo clean
    BACKUP_DIR="$TEST_DIR/backups"
    mkdir -p "$BACKUP_DIR"

    # Run Setup Function for this test
    if [[ -n "$SETUP_FUNC" ]]; then
        $SETUP_FUNC
    fi

    # Run create_instance
    # Capture output
    if [[ -n "$INPUT_STREAM" ]]; then
        OUTPUT=$(echo -e "$INPUT_STREAM" | create_instance 2>&1)
    else
        OUTPUT=$(create_instance 2>&1)
    fi

    # Assertions
    if [[ -n "$EXPECTED_OUTPUT" ]]; then
        assert_output_contains "$OUTPUT" "$EXPECTED_OUTPUT" || exit 1
    fi

    # Check for success marker if not expecting failure
    if [[ "$EXPECTED_OUTPUT" == *"[SUCCESS]"* ]]; then
        if [[ "$OUTPUT" != *"[SUCCESS]"* ]]; then
             echo "FAILED: Expected success but got:"
             echo "$OUTPUT"
             exit 1
        fi
    fi

    echo "PASSED: $TEST_NAME"
}

# TEST CASE 1: Happy Path
test_happy_path() {
    create_mock_initdb 0
}
run_test_case "Happy Path" test_happy_path "[SUCCESS]: Instance initialized." ""

# Verify artifacts for Happy Path
assert_file_exists "$DATA_DIR/postgresql.conf" || exit 1
assert_grep "port = 5432" "$DATA_DIR/postgresql.conf" "Port setting missing/incorrect" || exit 1
assert_grep "unix_socket_directories = '$DATA_DIR'" "$DATA_DIR/postgresql.conf" "Socket dir setting missing/incorrect" || exit 1
assert_grep "logging_collector = on" "$DATA_DIR/postgresql.conf" "Logging collector setting missing" || exit 1

# Check that comments are removed
if grep -q "^# PostgreSQL Configuration" "$DATA_DIR/postgresql.conf"; then
    echo "FAILED: Comments were not removed from postgresql.conf"
    exit 1
fi

# TEST CASE 2: Missing initdb
test_missing_initdb() {
    MOCK_INITDB_MISSING="true"
}
run_test_case "Missing initdb" test_missing_initdb "[ERR]: 'initdb' not found for this profile." ""

# TEST CASE 3: Missing PROFILES_DATA_DIR
test_missing_data_dir() {
    PROFILES_DATA_DIR=("")
    create_mock_initdb 0
}
run_test_case "Missing Data Dir" test_missing_data_dir "[ERR]: No Data Directory defined for this profile." ""

# TEST CASE 4: Existing Directory - Cancel
test_existing_dir_cancel() {
    create_mock_initdb 0
    mkdir -p "$DATA_DIR"
    touch "$DATA_DIR/dummy_file"
}
# Input "3" for Cancel
run_test_case "Existing Directory - Cancel" test_existing_dir_cancel "Target directory '$DATA_DIR' exists and is not empty." "3"
# Verify initdb was NOT called (no SUCCESS message)
if [[ "$OUTPUT" == *"[SUCCESS]"* ]]; then
    echo "FAILED: initdb should not have run on Cancel."
    exit 1
fi

# TEST CASE 5: Existing Directory - Delete
test_existing_dir_delete() {
    create_mock_initdb 0
    mkdir -p "$DATA_DIR"
    touch "$DATA_DIR/dummy_file"
}
# Input "2" for Delete
run_test_case "Existing Directory - Delete" test_existing_dir_delete "[INFO]: Purging directory..." "2"
assert_output_contains "$OUTPUT" "[SUCCESS]: Instance initialized." || exit 1

# TEST CASE 6: Existing Directory - Backup
test_existing_dir_backup() {
    create_mock_initdb 0
    mkdir -p "$DATA_DIR"
    touch "$DATA_DIR/dummy_file"
}
# Input "1" for Backup
run_test_case "Existing Directory - Backup" test_existing_dir_backup "[INFO]: Archiving to" "1"
assert_output_contains "$OUTPUT" "[SUCCESS]: Instance initialized." || exit 1
# Verify backup file created
BACKUP_FILES=$(find "$BACKUP_DIR" -name "raw_backup_*.tar.gz")
if [[ -z "$BACKUP_FILES" ]]; then
    echo "FAILED: Backup file not found in $BACKUP_DIR."
    exit 1
fi

# TEST CASE 7: initdb Failure
test_initdb_failure() {
    create_mock_initdb 1
}
run_test_case "initdb Failure" test_initdb_failure "[FAIL]: initdb failed." ""

echo "---------------------------------------------------"
echo "All tests passed successfully!"
