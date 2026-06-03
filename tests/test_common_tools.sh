#!/bin/bash

# tests/test_common_tools.sh
# Tests for resolve_tool, require_tool, and require_tools in modules/common.sh

# Exit on error
set -e

# Path to common.sh
COMMON_SH="$(dirname "$0")/../modules/common.sh"

# Create a temporary workspace
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock Bin Directory
MOCK_BIN_DIR="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN_DIR"
export PATH="$MOCK_BIN_DIR:$PATH"

# Create a mock binary
cat << 'EOF' > "$MOCK_BIN_DIR/mock_tool"
#!/bin/bash
echo "I exist"
EOF
chmod +x "$MOCK_BIN_DIR/mock_tool"

# Source common.sh
# We need to source it cleanly. If we already sourced it, variables might persist.
# But this script runs in a separate process usually.
source "$COMMON_SH"

echo "--- Testing resolve_tool ---"

# Test 1: Binary exists
echo "Test 1: Binary exists (resolve_tool)"
unset BIN_MOCK_TOOL
resolve_tool "mock_tool"
if [[ "$BIN_MOCK_TOOL" != "$MOCK_BIN_DIR/mock_tool" ]]; then
    echo "FAILED: Expected BIN_MOCK_TOOL='$MOCK_BIN_DIR/mock_tool', got '$BIN_MOCK_TOOL'"
    exit 1
fi
echo "PASS: BIN_MOCK_TOOL set correctly."

# Test 2: Binary missing
echo "Test 2: Binary missing (resolve_tool)"
if resolve_tool "missing_tool"; then
    echo "FAILED: resolve_tool should have returned 1"
    exit 1
fi
if [[ -n "$BIN_MISSING_TOOL" ]]; then
    echo "FAILED: BIN_MISSING_TOOL should be unset, got '$BIN_MISSING_TOOL'"
    exit 1
fi
echo "PASS: resolve_tool returned failure and variable is unset."

echo "--- Testing require_tool ---"

# Test 3: Binary exists
echo "Test 3: Binary exists (require_tool)"
if ! require_tool "mock_tool"; then
    echo "FAILED: require_tool failed"
    exit 1
fi
echo "PASS: require_tool succeeded."

# Test 4: Binary missing
echo "Test 4: Binary missing (require_tool)"
OUTPUT_FILE="$TEST_DIR/output.txt"
ERROR_FILE="$TEST_DIR/error.txt"

if require_tool "missing_tool" > "$OUTPUT_FILE" 2> "$ERROR_FILE"; then
    echo "FAILED: require_tool should have failed"
    exit 1
fi

ERR_MSG=$(cat "$ERROR_FILE")
if [[ "$ERR_MSG" != *"[ERR]: 'missing_tool' binary not found"* ]]; then
    echo "FAILED: Unexpected error message: '$ERR_MSG'"
    exit 1
fi
echo "PASS: Correctly failed with error message."

echo "--- Testing require_tools ---"

# Test 5: Multiple existing binaries
echo "Test 5: Multiple binaries (require_tools)"
cat << 'EOF' > "$MOCK_BIN_DIR/tool2"
#!/bin/bash
EOF
chmod +x "$MOCK_BIN_DIR/tool2"

if ! require_tools "mock_tool" "tool2"; then
    echo "FAILED: require_tools failed"
    exit 1
fi
if [[ "$BIN_MOCK_TOOL" != "$MOCK_BIN_DIR/mock_tool" ]]; then echo "FAILED: BIN_MOCK_TOOL bad"; exit 1; fi
if [[ "$BIN_TOOL2" != "$MOCK_BIN_DIR/tool2" ]]; then echo "FAILED: BIN_TOOL2 bad"; exit 1; fi
echo "PASS: Multiple binaries resolved."

# Test 6: One missing binary
echo "Test 6: One missing binary (require_tools)"
if require_tools "mock_tool" "missing_tool" 2> "$ERROR_FILE"; then
    echo "FAILED: require_tools should have failed"
    exit 1
fi
# mock_tool should still be set, as logic continues or fails?
# require_tools implementation:
# for TOOL in "$@"; do require_tool "$TOOL" || FAILED=1; done
# So it iterates all.
if [[ "$BIN_MOCK_TOOL" != "$MOCK_BIN_DIR/mock_tool" ]]; then echo "FAILED: BIN_MOCK_TOOL should still be set"; exit 1; fi

ERR_MSG=$(cat "$ERROR_FILE")
if [[ "$ERR_MSG" != *"[ERR]: 'missing_tool' binary not found"* ]]; then
    echo "FAILED: Unexpected error message: '$ERR_MSG'"
    exit 1
fi
echo "PASS: require_tools failed as expected."

echo "ALL TESTS PASSED"
