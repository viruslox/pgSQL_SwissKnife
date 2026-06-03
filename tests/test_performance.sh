#!/bin/bash

# tests/test_performance.sh

# Exit on error
set -e

# Path to the script under test
PERFORMANCE_SH="$(dirname "$0")/../modules/Performance.sh"

# 1. Setup Test Environment
# Create a temporary workspace
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock Bin Directory
MOCK_BIN_DIR="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN_DIR"
export PATH="$MOCK_BIN_DIR:$PATH"

# Create Mock psql
cat << 'EOF' > "$MOCK_BIN_DIR/psql"
#!/bin/bash
# Mock psql that validates arguments and simulates success/failure

# Basic validation (order is preserved mostly)
# Expected flags: -h, -p, -U, -d, -t, -A
# Then optionally -v
# Then -c <QUERY>

args=("$@")

# Basic check for required flags
has_h=false
has_p=false
has_U=false
has_d=false
has_t=false
has_A=false
has_c=false

QUERY=""
VAR_KEY=""
VAR_VAL=""

for ((i=0; i<${#args[@]}; i++)); do
    arg="${args[i]}"
    case "$arg" in
        -h) has_h=true ;;
        -p) has_p=true ;;
        -U) has_U=true ;;
        -d) has_d=true ;;
        -t) has_t=true ;;
        -A) has_A=true ;;
        -v)
            VAR_KEY="${args[i+1]%=*}"
            VAR_VAL="${args[i+1]#*=}"
            ((i++))
            ;;
        -c)
            has_c=true
            QUERY="${args[i+1]}"
            ((i++))
            ;;
    esac
done

if ! $has_h || ! $has_p || ! $has_U || ! $has_d || ! $has_t || ! $has_A || ! $has_c; then
    echo "FAILED: Missing required arguments to psql: ${args[*]}"
    exit 1
fi

# Check if we should simulate failure based on query content
if [[ "$QUERY" == "FAIL_ME" ]]; then
    exit 1
fi

# Echo back the variable if present, so we can verify it
if [[ -n "$VAR_KEY" ]]; then
    echo "VAR: $VAR_KEY=$VAR_VAL"
fi

# Success output
echo "MOCK_OUTPUT"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/psql"

# Set global variables expected by run_query
export BIN_PSQL="$MOCK_BIN_DIR/psql"
export DB_HOST="localhost"
export DB_PORT="5432"
export DB_USER="testuser"
export DB_NAME="testdb"

# 2. Source Performance.sh
# It should not execute its main loop because of the guard we added.
source "$PERFORMANCE_SH"

# 3. Test Cases

echo "Running run_query tests..."

# Test 1: Happy Path (No extra vars)
echo "Test 1: Happy Path"
OUTPUT=$(run_query "SELECT 1")
if [ $? -ne 0 ]; then
    echo "FAILED: run_query returned error code"
    exit 1
fi

if [[ "$OUTPUT" != "MOCK_OUTPUT" ]]; then
    echo "FAILED: run_query output mismatch. Got: '$OUTPUT'"
    exit 1
fi

# Test 2: Error Path
echo "Test 2: Error Path"
# run_query calls exit 1 on failure, so we must run it in subshell to catch it
if (run_query "FAIL_ME") 2>/dev/null; then
    echo "FAILED: run_query should have exited with 1"
    exit 1
else
    echo "SUCCESS: run_query failed as expected"
fi

# Verify error message
ERROR_MSG=$( (run_query "FAIL_ME") 2>&1 ) || true
if [[ "$ERROR_MSG" != *"[FAIL]: Query failed. Check connection or permissions."* ]]; then
     echo "FAILED: Incorrect error message. Got: '$ERROR_MSG'"
     exit 1
fi

# Test 3: Variable Passing
echo "Test 3: Variable Passing"
OUTPUT=$(run_query "SELECT :myvar" -v myvar="testvalue")
if [ $? -ne 0 ]; then
    echo "FAILED: run_query (with vars) returned error code"
    exit 1
fi

if [[ "$OUTPUT" != *"VAR: myvar=testvalue"* ]]; then
    echo "FAILED: Variable not passed correctly. Got: '$OUTPUT'"
    exit 1
fi

echo "All tests passed for run_query!"

# 4. Clean Function Tests
echo "Running clean() tests..."

# Test helper
assert_clean() {
    local input="$1"
    local expected="$2"
    local label="$3"
    local expected_exit="${4:-0}"  # Default to 0 unless specified

    local actual
    local ret

    # Capture exit code carefully
    set +e
    actual=$(clean "$input")
    ret=$?
    set -e

    # Verify exit code
    if [[ $ret -ne $expected_exit ]]; then
        echo "[FAIL] $label - Exit Code Mismatch"
        echo "  Expected Exit: $expected_exit"
        echo "  Actual Exit:   $ret"
        echo "  Actual Output: '$actual'"
        exit 1
    fi

    # We use | cat -e to see invisible characters and ensure perfect match
    local actual_e=$(printf "%s" "$actual" | cat -e)
    local expected_e=$(printf "%s" "$expected" | cat -e)

    if [[ "$actual_e" == "$expected_e" ]]; then
        echo "[PASS] $label"
    else
        echo "[FAIL] $label - Content Mismatch"
        echo "  Input:    '$(echo -n "$input" | cat -e)'"
        echo "  Expected: '$expected_e'"
        echo "  Actual:   '$actual_e'"
        exit 1
    fi
}

assert_clean "word" "word" "Basic word" 0
assert_clean $'\n\nword\n\n' "word" "Leading and trailing newlines" 0
assert_clean $'\n\nline1\n\nline2\n\n' "line1"$'\n'$'\n'"line2" "Preserve inner newlines" 0
assert_clean "  word  " "  word  " "Preserve spaces" 0
assert_clean $'\n  word  \n' "  word  " "Trim newlines but keep spaces" 0
assert_clean $'\n\n\n' "" "Only newlines becomes empty" 1
assert_clean "" "" "Empty string remains empty" 1
assert_clean "line1"$'\n'" " "line1"$'\n'" " "Trailing space line is preserved" 0
assert_clean " "$'\n'"line1" " "$'\n'"line1" "Leading space line is preserved" 0

# New Tests for Edge Cases
assert_clean $'\t' $'\t' "Tabs are preserved" 0
assert_clean $'\r' $'\r' "Carriage returns are preserved" 0
assert_clean $'\n\t\n' $'\t' "Tabs surrounded by newlines" 0
assert_clean $'\n\r\n' $'\r' "CR surrounded by newlines" 0
assert_clean "special*chars?" "special*chars?" "Special characters preserved" 0
assert_clean $'\n  \n' "  " "Spaces surrounded by newlines" 0

# Test dash-prefixed strings (bug reproduction)
assert_clean "-n" "-n" "String starting with -n" 0
assert_clean "-e" "-e" "String starting with -e" 0

echo "All clean() tests passed!"

echo "All tests in test_performance.sh passed!"
