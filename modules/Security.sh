#!/bin/bash

# PostgreSQL SwissKnife -> Security Audit

REQUIRE_CONFIG=true
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config

AUDIT_BASE_DIR="${SUITE_DIR}/audits"
require_tools psql || exit 1

# Profile Selection
select_profile "--- Select Instance for Audit ---" || exit 1

PROFILE_NAME="${PROFILES_NAME[$IDX]}"
setup_connection
mkdir -p "$AUDIT_BASE_DIR"
REPORT_FILE="${AUDIT_BASE_DIR}/Audit_${PROFILE_NAME}_$(date +%Y%m%d_%H%M).txt"


echo "[INFO]: Starting audit for $PROFILE_NAME..."
echo "[INFO]: Generating report at $REPORT_FILE"

(
    umask 077
    {
        echo "========================================================"
        echo " PostgreSQL Security Audit Report"
        echo "========================================================"
        echo "Target:  $PROFILE_NAME"
        echo "Host:    $DB_HOST:$DB_PORT"
        echo "User:    $DB_USER"
        echo "Date:    $(date)"
        echo "========================================================"
        echo ""

        # 1. Superuser Check
        IS_SUPER=$("$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "SELECT usesuper FROM pg_user WHERE usename = current_user;")

        if [[ "$IS_SUPER" == "t" ]]; then
            echo "[PRIVILEGE]: Connected as SUPERUSER. Full audit enabled."
        else
            echo "[PRIVILEGE]: Connected as STANDARD user. Some checks (pg_shadow) will be skipped."
        fi
        echo ""

        # 2. Version & SSL
        echo "--- Server Information ---"
        "$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT version();"
        echo "SSL Active: "$("$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "SELECT ssl_is_used();")
        echo ""

        # 3. Critical Settings
        echo "--- Critical Settings (pg_settings) ---"
        "$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "
            SELECT name, setting, source
            FROM pg_settings
            WHERE name IN ('listen_addresses', 'port', 'max_connections', 'log_connections', 'password_encryption', 'ssl');"
        echo ""

        # 4. Superuser List
        echo "--- List of Superusers (High Risk) ---"
        "$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "
            SELECT usename, usecreatedb, usecreaterole, passwd
            FROM pg_shadow
            WHERE usesuper = true;" 2>/dev/null || echo "[WARN]: Cannot read pg_shadow (Permission Denied). Listing from pg_user:"

        if [[ "$IS_SUPER" != "t" ]]; then
            "$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT usename, usesuper FROM pg_user WHERE usesuper = true;"
        fi
        echo ""

        # 5. Empty Passwords (Superuser Only)
        if [[ "$IS_SUPER" == "t" ]]; then
            echo "--- Users with NULL Passwords ---"
            NULL_PASS=$("$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "SELECT usename FROM pg_shadow WHERE passwd IS NULL;")
            if [[ -z "$NULL_PASS" ]]; then
                echo "[PASS]: No users found with null passwords."
            else
                echo "[FAIL]: The following users have NO password:"
                echo "$NULL_PASS"
            fi
        else
            echo "--- Users with NULL Passwords ---"
            echo "[SKIP]: Requires Superuser privileges."
        fi
        echo ""

        # 6. Database List & Owner
        echo "--- Databases & Owners ---"
        "$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "
            SELECT datname, pg_catalog.pg_get_userbyid(datdba) as owner, pg_encoding_to_char(encoding) as encoding
            FROM pg_database
            WHERE datistemplate = false;"
        echo ""

    } > "$REPORT_FILE" 2>&1
)

echo "[SUCCESS]: Audit Complete."
exit 0
