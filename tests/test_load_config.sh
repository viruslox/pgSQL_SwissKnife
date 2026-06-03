#!/bin/bash

# tests/test_load_config.sh

# Path to the script under test
COMMON_SH="$(dirname "$0")/../modules/common.sh"

# 1. Source common.sh
# We need to do this to get the load_config function
source "$COMMON_SH"

echo "--- Testing load_config error handling ---"

# 2. Test Case: Missing config file with REQUIRE_CONFIG=true
echo "Test Case: Missing config file with REQUIRE_CONFIG=true"

# Set a non-existent config file
CONFIG_FILE="/tmp/non_existent_config_$(date +%s)"
REQUIRE_CONFIG=true

# Call load_config in a subshell to catch the exit
# Redirect both stdout and stderr to a temp file to verify the error message
ERROR_MSG_FILE=$(mktemp)
(load_config > "$ERROR_MSG_FILE" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 1 ]; then
    echo "FAILED: expected exit code 1, got $EXIT_CODE"
    rm -f "$ERROR_MSG_FILE"
    exit 1
fi

if ! grep -q "\[ERR\]: Configuration file not found. Run Setup.sh." "$ERROR_MSG_FILE"; then
    echo "FAILED: expected error message not found"
    cat "$ERROR_MSG_FILE"
    rm -f "$ERROR_MSG_FILE"
    exit 1
fi

rm -f "$ERROR_MSG_FILE"
echo "Success: load_config correctly exited with 1 and printed error message."

# 3. Test Case: Missing config file with REQUIRE_CONFIG=false (default)
echo "Test Case: Missing config file with REQUIRE_CONFIG=false"
REQUIRE_CONFIG=false
(load_config)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "FAILED: expected exit code 0 when REQUIRE_CONFIG=false, got $EXIT_CODE"
    exit 1
fi

echo "Success: load_config correctly exited with 0 when config is not required."

# 4. Test Case: Config file exists
echo "Test Case: Config file exists"
CONFIG_FILE=$(mktemp)
echo "TEST_VAR='loaded'" > "$CONFIG_FILE"
REQUIRE_CONFIG=true

# Source it normally to see if TEST_VAR is set
load_config
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "FAILED: expected exit code 0 when config file exists, got $EXIT_CODE"
    rm -f "$CONFIG_FILE"
    exit 1
fi

if [ "$TEST_VAR" != "loaded" ]; then
    echo "FAILED: config file was not sourced correctly"
    rm -f "$CONFIG_FILE"
    exit 1
fi

echo "Success: load_config correctly sourced the config file."

rm -f "$CONFIG_FILE"

echo "All load_config tests passed!"
