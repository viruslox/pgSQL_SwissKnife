#!/bin/bash

# tests/repro_issue.sh

# Exit on error
set -e

# Path to the script under test
PERFORMANCE_SH="$(dirname "$0")/../modules/Performance.sh"
CONFIG_FILE="$(dirname "$0")/../config/pgSQL_SwissKnife.conf"

# 1. Setup Test Environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock Bin Directory
MOCK_BIN_DIR="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN_DIR"
export PATH="$MOCK_BIN_DIR:$PATH"

# Create Config File
mkdir -p "$(dirname "$CONFIG_FILE")"
cat << 'EOF' > "$CONFIG_FILE"
PROFILES_NAME=("test_instance")
PROFILES_HOST=("localhost")
PROFILES_PORT=("5432")
PROFILES_ADMIN=("postgres")
PROFILES_DATA_DIR=("/var/lib/postgresql/data")
PROFILES_PSQL_VERS=("14")
EOF

# Create Mock psql
# It logs arguments to a file for inspection
LOG_FILE="$TEST_DIR/psql_args.log"
cat << EOF > "$MOCK_BIN_DIR/psql"
#!/bin/bash
echo "\$@" >> "$LOG_FILE"
# Output some dummy data to satisfy run_query
echo "Hit Ratio: 99%"
echo "---SEPARATOR---"
echo "Active: 1 / Max: 100"
echo "---SEPARATOR---"
echo "123 | user | 00:00:01 | SELECT 1"
echo "---SEPARATOR---"
echo "10 MB"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/psql"

# 2. Run Performance.sh with injection payload
export TARGET_PROFILE_IDX=0
export TEST_INTERACTIVE=true # Force interactive paths if needed, though run_query doesn't depend on it

# Payload: malicious_db
PAYLOAD="malicious_db"

# Feed input to read DB_NAME
echo "$PAYLOAD" | "$PERFORMANCE_SH" > /dev/null

# 3. Analyze Log
ARGS=$(cat "$LOG_FILE")

echo "Captured arguments: $ARGS"

# Check 1: Payload should NOT be directly in SQL
if [[ "$ARGS" == *"pg_database_size('$PAYLOAD')"* ]]; then
    echo "FAIL: Payload found directly in SQL string (Vulnerable)."
    exit 1
fi

# Check 2: Payload SHOULD be passed as variable
if [[ "$ARGS" == *"-v target_db=$PAYLOAD"* ]]; then
    echo "PASS: Payload passed as psql variable."
else
    echo "FAIL: Payload NOT passed as variable."
    exit 1
fi

# Check 3: Query should use the variable
if [[ "$ARGS" == *":'target_db'"* ]]; then
    echo "PASS: Query uses variable syntax."
else
    echo "FAIL: Query does not use variable syntax."
    exit 1
fi

echo "Vulnerability Fixed & Verified."
exit 0
