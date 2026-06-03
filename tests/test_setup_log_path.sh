#!/bin/bash
# tests/test_setup_log_path.sh
set -e
SETUP_SH="$(dirname "$0")/../modules/Setup.sh"

# Source Setup.sh
if [ -f "$SETUP_SH" ]; then
    source "$SETUP_SH"
else
    echo "FAILED: Setup.sh not found."
    exit 1
fi

# Setup Test Environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock SUITE_DIR (Common.sh likely sets it based on script location, but we can override or ensure structure)
# Setup.sh sources common.sh which sets SUITE_DIR based on BASH_SOURCE.
# Since we sourced Setup.sh, SUITE_DIR is set relative to Setup.sh location.
# We need to Override SUITE_DIR for the test.
SUITE_DIR="$TEST_DIR/suite"
mkdir -p "$SUITE_DIR/logs"

# Mock PROFILES
IDX=0
PROFILES_NAME=("TestProfile")
PROFILES_DATA_DIR=("$TEST_DIR/data")
mkdir -p "$TEST_DIR/data"

# Mock pg_ctl
MOCK_BIN="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN"
cat << 'EOF' > "$MOCK_BIN/pg_ctl"
#!/bin/bash
if [[ "$1" == "status" ]]; then
    # Simulate not running
    exit 1
fi
if [[ "$1" == "start" ]]; then
    # Parse -l argument
    LOG_FILE=""
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-l" ]]; then
            LOG_FILE="$2"
            shift
        fi
        shift
    done
    if [[ -n "$LOG_FILE" ]]; then
        # Ensure directory exists (pg_ctl expects it to exist or create file? Setup.sh ensures dir exists)
        echo "LOGGED TO $LOG_FILE" > "$LOG_FILE"
    fi
    exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN/pg_ctl"
export PATH="$MOCK_BIN:$PATH"

# Override get_bin_path to return our mock pg_ctl
get_bin_path() {
    RET_VAL="$MOCK_BIN/pg_ctl"
}

echo "Running check_and_start_local_db..."
# Input "y" to start
echo "y" | check_and_start_local_db

# Verify Log Directory Created
EXPECTED_LOG_DIR="$SUITE_DIR/logs/TestProfile"
if [ ! -d "$EXPECTED_LOG_DIR" ]; then
    echo "FAILED: Log directory $EXPECTED_LOG_DIR not created."
    exit 1
fi

# Verify Log File Content
EXPECTED_LOG_FILE="$EXPECTED_LOG_DIR/startup.log"
if grep -q "LOGGED TO $EXPECTED_LOG_FILE" "$EXPECTED_LOG_FILE"; then
    echo "SUCCESS: Log file created in correct location."
else
    echo "FAILED: Log file content mismatch or file missing."
    if [ -f "$EXPECTED_LOG_FILE" ]; then
        echo "Content: $(cat "$EXPECTED_LOG_FILE")"
    else
        echo "File does not exist."
    fi
    exit 1
fi

exit 0
