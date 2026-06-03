#!/bin/bash

# Common initialization for PostgreSQL SwissKnife modules

# Ensure we are in the modules directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${SUITE_DIR}/config/pgSQL_SwissKnife.conf"

# Ensure essential directories exist
init_suite() {
    mkdir -p "${SUITE_DIR}/config"
    mkdir -p "${SUITE_DIR}/logs"
    mkdir -p "${SUITE_DIR}/backups"
    mkdir -p "${SUITE_DIR}/audits"
}

# Migrate legacy config (called primarily by Setup.sh)
migrate_legacy_config() {
    local LEGACY_CONFIG="${HOME}/pgSQL_SwissKnife.conf"
    if [[ -f "$LEGACY_CONFIG" && ! -f "$CONFIG_FILE" ]]; then
        echo "[INFO]: Migrating configuration from $LEGACY_CONFIG to $CONFIG_FILE"
        mkdir -p "$(dirname "$CONFIG_FILE")"
        mv "$LEGACY_CONFIG" "$CONFIG_FILE"
    fi
}

# Load Configuration
load_config() {
    init_suite

    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    elif [[ "$REQUIRE_CONFIG" == "true" ]]; then
        echo "[ERR]: Configuration file not found. Run Setup.sh."
        exit 1
    fi

    # Apply Custom Path if Configured
    if [[ -n "$CUSTOM_ENV_PATH" ]]; then
        export PATH="$CUSTOM_ENV_PATH:$PATH"
    fi

    # Initialize arrays properly with quotes to handle spaces
    PROFILES_NAME=("${PROFILES_NAME[@]}")
    PROFILES_HOST=("${PROFILES_HOST[@]}")
    PROFILES_PORT=("${PROFILES_PORT[@]}")
    PROFILES_ADMIN=("${PROFILES_ADMIN[@]}")
    PROFILES_DATA_DIR=("${PROFILES_DATA_DIR[@]}")
    PROFILES_PSQL_VERS=("${PROFILES_PSQL_VERS[@]}")
}

# Finds tool candidates in common paths
find_tool_candidates() {
    local TOOL_NAME="$1"
    find /usr /opt "${HOME}" -name "$TOOL_NAME" -type f -executable 2>/dev/null
}

# Resolves a tool and sets a global variable BIN_<NAME>
# Usage: resolve_tool <binary_name>
# Returns: 0 if found, 1 if not found.
resolve_tool() {
    local TOOL_NAME="$1"
    local VAR_NAME="BIN_$(echo "$TOOL_NAME" | tr '[:lower:]' '[:upper:]')"

    # 1. Check current PATH
    local TOOL_PATH=$(which "$TOOL_NAME" 2>/dev/null)

    if [[ -x "$TOOL_PATH" ]]; then
        printf -v "$VAR_NAME" "%s" "$TOOL_PATH"
        return 0
    fi

    # 2. Search common locations
    mapfile -t CANDIDATES < <(find_tool_candidates "$TOOL_NAME")

    if [ ${#CANDIDATES[@]} -gt 0 ]; then
        # Pick the first one
        TOOL_PATH="${CANDIDATES[0]}"
        printf -v "$VAR_NAME" "%s" "$TOOL_PATH"
        return 0
    fi

    # Unset the variable if not found, to avoid stale values
    unset "$VAR_NAME"
    return 1
}

# Requires a single tool. Returns 1 if not found.
# Usage: require_tool <binary_name>
require_tool() {
    local TOOL_NAME="$1"
    if ! resolve_tool "$TOOL_NAME"; then
        echo "[ERR]: '$TOOL_NAME' binary not found. Please install it." >&2
        return 1
    fi
    return 0
}

# Requires multiple tools.
# Usage: require_tools <binary1> [binary2] ...
require_tools() {
    local FAILED=0
    for TOOL in "$@"; do
        require_tool "$TOOL" || FAILED=1
    done
    return $FAILED
}

select_profile() {
    local PROMPT_TEXT="${1:-Select Instance}"

    if [[ -n "$TARGET_PROFILE_IDX" ]]; then
        IDX=$TARGET_PROFILE_IDX
        echo "[INFO]: Running in AUTOMATION mode for profile index: $IDX"
    else
        if [ ${#PROFILES_NAME[@]} -eq 0 ]; then
            echo "[ERR]: No profiles configured."
            return 1
        fi

        echo "$PROMPT_TEXT"
        for i in "${!PROFILES_NAME[@]}"; do
            echo "  $i) ${PROFILES_NAME[$i]} [Host: ${PROFILES_HOST[$i]}]"
        done
        read -p "Select Profile Index: " IDX
    fi

    # Validate numeric input
    if [[ ! "$IDX" =~ ^[0-9]+$ ]]; then
        echo "[ERR]: Invalid profile index. Must be a number."
        return 1
    fi

    if [[ -z "${PROFILES_NAME[$IDX]}" ]]; then
        echo "[ERR]: Invalid profile index."
        return 1
    fi
    return 0
}

setup_connection() {
    DB_HOST="${PROFILES_HOST[$IDX]}"
    DB_PORT="${PROFILES_PORT[$IDX]}"
    DB_USER="${PROFILES_ADMIN[$IDX]}"

    # Auth Handling (Interactive)
    if [[ ( -t 0 || -n "$TEST_INTERACTIVE" ) && -z "$TARGET_PROFILE_IDX" ]]; then
        echo -n "Password for $DB_USER (Enter for Peer/.pgpass): "
        read -s DB_PASS
        echo ""
        if [[ -n "$DB_PASS" ]]; then
            export PGPASSWORD="$DB_PASS"
        else
            unset PGPASSWORD
        fi
    fi

    if [[ -z "$PGPASSWORD" && -n "${PROFILES_DATA_DIR[$IDX]}" ]]; then
        if [[ "$DB_HOST" == "localhost" || "$DB_HOST" == "127.0.0.1" || "$DB_HOST" == "::1" ]]; then
             DB_HOST="${PROFILES_DATA_DIR[$IDX]}"
             echo "[INFO]: Switching to Socket Connection for Peer Auth: $DB_HOST"
        fi
    fi
}

get_database_list() {
    # Fetches list of all non-template databases
    # Requires variables: BIN_PSQL, DB_HOST, DB_PORT, DB_USER
    local LIST
    LIST=$("$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null)

    if [[ -z "$LIST" ]]; then
        echo "[ERR]: Unable to retrieve database list. Check connection/auth." >&2
        return 1
    fi
    echo "$LIST"
}

# Change to SCRIPT_DIR to ensure relative paths work as expected
cd "${SCRIPT_DIR}"
