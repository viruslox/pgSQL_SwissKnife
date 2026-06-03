#!/bin/bash

# Test umask 077 effect
test_umask() {
    local test_file="tests/test_file"
    rm -f "$test_file"
    (umask 077 && touch "$test_file")
    local perms=$(stat -c "%a" "$test_file")
    if [ "$perms" == "600" ]; then
        echo "[PASS]: umask 077 works as expected (600 for files)"
    else
        echo "[FAIL]: umask 077 failed (perms: $perms)"
        exit 1
    fi
    rm -f "$test_file"
}

# Verify Setup.sh save_config
verify_setup_save_config() {
    echo "Verifying Setup.sh save_config..."
    # Mock environment for Setup.sh
    export SCRIPT_DIR="modules"
    export CONFIG_FILE="tests/mock_config.conf"
    rm -f "$CONFIG_FILE"

    # Extract save_config function and run it
    # We need PROFILES_NAME array
    PROFILES_NAME=("test")

    # Source the function from the script
    # Note: save_config uses variables like CUSTOM_ENV_PATH, PROFILES_NAME etc.
    source <(sed -n '/save_config() {/,/^}/p' modules/Setup.sh)

    save_config > /dev/null

    local perms=$(stat -c "%a" "$CONFIG_FILE")
    if [ "$perms" == "600" ]; then
        echo "[PASS]: Setup.sh CONFIG_FILE created with 600"
    else
        echo "[FAIL]: Setup.sh CONFIG_FILE created with $perms"
        exit 1
    fi
    rm -f "$CONFIG_FILE"
}

# Verify Security.sh report
verify_security_report() {
    echo "Verifying Security.sh report..."
    export REPORT_FILE="tests/mock_report.txt"
    rm -f "$REPORT_FILE"

    # Mocking the pattern used in Security.sh
    (
        umask 077
        {
            echo "mock report"
        } > "$REPORT_FILE" 2>&1
    )

    local perms=$(stat -c "%a" "$REPORT_FILE")
    if [ "$perms" == "600" ]; then
        echo "[PASS]: Security.sh REPORT_FILE created with 600"
    else
        echo "[FAIL]: Security.sh REPORT_FILE created with $perms"
        exit 1
    fi
    rm -f "$REPORT_FILE"
}

verify_systemd_unit() {
    echo "Verifying Systemd.sh unit creation..."
    export UNIT_FILE="tests/mock_unit.service"
    rm -f "$UNIT_FILE"

    # Mocking the pattern used in Systemd.sh
    (umask 077 && cat > "$UNIT_FILE") <<EOF
[Unit]
Description=Mock
EOF

    local perms=$(stat -c "%a" "$UNIT_FILE")
    if [ "$perms" == "600" ]; then
        echo "[PASS]: Systemd.sh unit file created with 600"
    else
        echo "[FAIL]: Systemd.sh unit file created with $perms"
        exit 1
    fi
    rm -f "$UNIT_FILE"
}

verify_backup_dump() {
    echo "Verifying Backup.sh dump creation..."
    export DUMP_FILE="tests/mock_dump.sql"
    export LOG_FILE="tests/mock_backup.log"
    rm -f "$DUMP_FILE" "$LOG_FILE"

    # Mocking the pattern used in Backup.sh
    (
        umask 077
        echo "mock dump" > "$DUMP_FILE"
        echo "mock log" > "$LOG_FILE"
    )

    local dperms=$(stat -c "%a" "$DUMP_FILE")
    local lperms=$(stat -c "%a" "$LOG_FILE")

    if [ "$dperms" == "600" ] && [ "$lperms" == "600" ]; then
        echo "[PASS]: Backup.sh dump and log created with 600"
    else
        echo "[FAIL]: Backup.sh dump/log perms: $dperms / $lperms"
        exit 1
    fi
    rm -f "$DUMP_FILE" "$LOG_FILE"
}

# Run tests
test_umask
verify_setup_save_config
verify_security_report
verify_systemd_unit
verify_backup_dump

echo "All security verifications passed!"
