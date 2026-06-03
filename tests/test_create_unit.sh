#!/bin/bash

# tests/test_create_unit.sh

set -e

# Path to the script under test
SYSTEMD_SH="$(dirname "$0")/../modules/Systemd.sh"

# Mock variables used by create_unit
export SYSTEMD_USER_DIR=$(mktemp -d)
trap 'rm -rf "$SYSTEMD_USER_DIR"' EXIT

export PROFILE_NAME="Test Profile"
export SAFE_NAME="TestProfile"
export SUITE_DIR="/opt/suite"
export CONFIG_FILE="/opt/suite/config/PostgreSQL_SwissKnife.conf"
export IDX=0

# Mock systemctl
systemctl() {
    echo "MOCK systemctl $@" >> "$SYSTEMD_USER_DIR/systemctl_log.txt"
}

export -f systemctl

# Source the script
source "$SYSTEMD_SH"

# Helper for assertions
assert_grep() {
    local pattern="$1"
    local file="$2"
    local message="$3"
    if ! grep -Fq "$pattern" "$file"; then
        echo "FAILED: $message"
        echo "File content:"
        cat "$file"
        exit 1
    fi
}

echo "Running test_create_unit..."

# Call create_unit
create_unit "backup" "Backup.sh" "daily" "Test Description"

SERVICE_FILE="${SYSTEMD_USER_DIR}/pg_backup_${SAFE_NAME}.service"
TIMER_FILE="${SYSTEMD_USER_DIR}/pg_backup_${SAFE_NAME}.timer"

# Verify Service File
if [ ! -f "$SERVICE_FILE" ]; then
    echo "FAILED: Service file not created at $SERVICE_FILE"
    exit 1
fi

assert_grep "Description=Test Description (Test Profile)" "$SERVICE_FILE" "Service Description incorrect"
assert_grep "ExecStart=${SUITE_DIR}/modules/Backup.sh" "$SERVICE_FILE" "ExecStart incorrect"
assert_grep "Environment=\"CONFIG_FILE=${CONFIG_FILE}\"" "$SERVICE_FILE" "Environment CONFIG_FILE incorrect"

# Verify Timer File
if [ ! -f "$TIMER_FILE" ]; then
    echo "FAILED: Timer file not created at $TIMER_FILE"
    exit 1
fi

assert_grep "OnCalendar=daily" "$TIMER_FILE" "OnCalendar incorrect"

# Verify Permissions (should be 600)
# Use a more portable way to get permissions if stat -c %a fails
if stat -c "%a" "$SERVICE_FILE" >/dev/null 2>&1; then
    PERMS=$(stat -c "%a" "$SERVICE_FILE")
else
    # Fallback for BSD stat or others
    PERMS=$(stat -f "%Lp" "$SERVICE_FILE" 2>/dev/null || echo "unknown")
fi

if [ "$PERMS" != "600" ]; then
    echo "FAILED: Service file permissions: $PERMS (expected 600)"
    exit 1
fi

# Verify systemctl calls
LOG_FILE="$SYSTEMD_USER_DIR/systemctl_log.txt"
if [ ! -f "$LOG_FILE" ]; then
    echo "FAILED: systemctl was not called (no log file)"
    exit 1
fi

assert_grep "MOCK systemctl --user daemon-reload" "$LOG_FILE" "daemon-reload not called"
assert_grep "MOCK systemctl --user enable --now pg_backup_${SAFE_NAME}.timer" "$LOG_FILE" "enable --now not called"

echo "SUCCESS: create_unit test passed!"
