#!/bin/bash
set -e

# Create workspace
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Copy Performance.sh to workspace
cp modules/Performance.sh "$TEST_DIR/Performance.sh"
chmod +x "$TEST_DIR/Performance.sh"

# Mock common.sh
cat > "$TEST_DIR/common.sh" << 'EOF'
#!/bin/bash

load_config() {
    export PROFILES_NAME=("TestProfile")
    export IDX=0
}

require_tools() {
    return 0
}

select_profile() {
    export IDX=0
    return 0
}

setup_connection() {
    export DB_HOST="localhost"
    export DB_PORT="5432"
    export DB_USER="testuser"
    export DB_NAME="testdb"
}

export BIN_PSQL="$TEST_BIN_PSQL"
EOF

# Mock psql
MOCK_PSQL="$TEST_DIR/psql"
cat > "$MOCK_PSQL" << 'EOF'
#!/bin/bash
# Check if "-v target_db=..." is passed
for arg in "$@"; do
    if [[ "$arg" == target_db=* ]]; then
        echo "FAIL: target_db variable passed" >&2
        exit 1
    fi
done

# Check if query contains current_database()
found_query=false
next_is_query=false
QUERY=""

for arg in "$@"; do
    if [[ "$arg" == "-c" ]]; then
        next_is_query=true
        continue
    fi
    if $next_is_query; then
        QUERY="$arg"
        next_is_query=false
    fi
done

if [[ "$QUERY" != *"pg_database_size(current_database())"* ]]; then
    echo "FAIL: Query does not contain pg_database_size(current_database())" >&2
    echo "Query was: $QUERY" >&2
    exit 1
fi

if [[ "$QUERY" == *"pg_database_size(:'target_db') "* ]]; then
    echo "FAIL: Query still contains pg_database_size(:'target_db')" >&2
    exit 1
fi

# Print mock output for the script to consume
echo "Hit Ratio: 100%"
echo "---SEPARATOR---"
echo "Active: 5 / Max: 100"
echo "---SEPARATOR---"
# No slow queries
echo ""
echo "---SEPARATOR---"
echo "100 MB"
EOF
chmod +x "$MOCK_PSQL"

# Export BIN_PSQL for common.sh to pick up
export TEST_BIN_PSQL="$MOCK_PSQL"

# Run Performance.sh
# Input: Target Database Name (we provide 'testdb')
echo "testdb" | "$TEST_DIR/Performance.sh" > "$TEST_DIR/output.txt" 2>&1

# Check exit code
if [ $? -ne 0 ]; then
    echo "Performance.sh failed. Output:"
    cat "$TEST_DIR/output.txt"
    exit 1
fi

echo "SUCCESS: Performance.sh passed syntax checks."
