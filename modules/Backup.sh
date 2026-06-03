#!/bin/bash

# PostgreSQL SwissKnife -> Backup Strategy

REQUIRE_CONFIG=true
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config

DEFAULT_RETENTION_DAYS=30
DEFAULT_MIN_COPIES=5

require_tools psql pg_dump xargs || exit 1
resolve_tool gzip || true

# Profile Selection
select_profile "Select Instance for Backup" || exit 1

PROFILE_NAME="${PROFILES_NAME[$IDX]}"
SAFE_NAME=$(echo "$PROFILE_NAME" | tr -cd '[:alnum:]')

if [[ -z "$SAFE_NAME" ]]; then
    echo "[ERR]: Invalid profile name '$PROFILE_NAME'. Resulted in empty safe name."
    exit 1
fi

setup_connection

# Directory Setup: Use a subfolder for this specific profile
if [[ -z "$SUITE_DIR" ]]; then
    echo "[ERR]: SUITE_DIR is not set."
    exit 1
fi

# Resolve SUITE_DIR to absolute path safely
ABS_SUITE_DIR="$(cd "${SUITE_DIR}" 2>/dev/null && pwd)"
if [[ -z "$ABS_SUITE_DIR" ]]; then
    echo "[ERR]: Could not resolve SUITE_DIR ('$SUITE_DIR') to an absolute path."
    exit 1
fi

BACKUP_ROOT="${ABS_SUITE_DIR}/backups"

# Prevent Path Traversal: Ensure BACKUP_ROOT is absolute
if [[ "$BACKUP_ROOT" != /* ]]; then
    echo "[ERR]: Path traversal detected. BACKUP_ROOT must be absolute: $BACKUP_ROOT"
    exit 1
fi

BACKUP_DIR="${BACKUP_ROOT}/${SAFE_NAME}"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M)


echo "=== Starting Backup Strategy: $PROFILE_NAME ==="
echo "Target Dir: $BACKUP_DIR"

# Ensure all created files (dumps, logs) have restricted permissions
umask 077

# --- Database Discovery ---
DB_LIST=$(get_database_list) || exit 1

export SUITE_DIR SAFE_NAME TIMESTAMP BACKUP_DIR BIN_GZIP BIN_PG_DUMP DB_HOST DB_PORT DB_USER PGPASSWORD

perform_backup() {
    local DB="$1"
    # Sanitize DB name to prevent path traversal
    local SAFE_DB=$(echo "$DB" | tr -cd '[:alnum:]_-')

    local LOG_FILE="${SUITE_DIR}/logs/${SAFE_NAME}_${TIMESTAMP}_${SAFE_DB}.log"
    local MSG="[INFO]: Dumping '$DB'... "
    
    # -Fp (Plain), -C (Create DB statement), --no-acl (optional, depends on needs)
    local DUMP_STATUS=0
    if [[ -x "$BIN_GZIP" ]]; then
        local DUMP_FILE="${BACKUP_DIR}/${TIMESTAMP}_${SAFE_DB}.sql.gz"
        "$BIN_PG_DUMP" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB" -Fp -C 2> "$LOG_FILE" | "$BIN_GZIP" > "$DUMP_FILE"
        
        local P_STATUS=("${PIPESTATUS[@]}")
        if [[ ${P_STATUS[0]} -eq 0 && ${P_STATUS[1]} -eq 0 ]]; then
            DUMP_STATUS=0
        else
            DUMP_STATUS=1
        fi
    else
        local DUMP_FILE="${BACKUP_DIR}/${TIMESTAMP}_${SAFE_DB}.sql"
        "$BIN_PG_DUMP" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB" -Fp -C > "$DUMP_FILE" 2> "$LOG_FILE"
        DUMP_STATUS=$?
    fi

    if [[ $DUMP_STATUS -eq 0 ]]; then
        MSG+="Success."
        rm "$LOG_FILE" # Remove log if successful
    else
        MSG+="FAILED. Check ${LOG_FILE}"
    fi
    echo "$MSG"
}
export -f perform_backup

# Run backups in parallel (auto-detect jobs)
JOBS=$(nproc 2>/dev/null || echo 4)
echo "$DB_LIST" | xargs -P "$JOBS" -I {} bash -c 'perform_backup "$@"' _ {}

echo "--- Checking Retention Policy ---"

# Count existing backup files (compressed or sql)
FILE_COUNT=$(find "$BACKUP_DIR" -type f -name "*.sql*" | wc -l)

if [[ "$FILE_COUNT" -gt "$DEFAULT_MIN_COPIES" ]]; then
    echo "[INFO]: File count ($FILE_COUNT) > Min ($DEFAULT_MIN_COPIES). Processing cleanup..."
    
    # Delete files older than X days
    # Note: We use -mtime. +30 means "more than 30 days ago"
    CLEANED_COUNT=$(find "$BACKUP_DIR" -type f -name "*.sql*" -mtime +$DEFAULT_RETENTION_DAYS -print -delete | wc -l)
    
    if [[ "$CLEANED_COUNT" -gt 0 ]]; then
        echo "[INFO]: Deleted $CLEANED_COUNT expired backup(s)."
    else
        echo "[INFO]: No expired backups found."
    fi
else
    echo "[SKIP]: Total backups ($FILE_COUNT) <= Min Limit ($DEFAULT_MIN_COPIES). No deletion."
fi

echo "=== Backup Procedure Complete ==="
exit 0