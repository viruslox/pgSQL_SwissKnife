#!/bin/bash

# PostgreSQL SwissKnife
# Use: Setup instances, databases, and users based on stored profiles.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
migrate_legacy_config
load_config

BACKUP_DIR="${SUITE_DIR}/backups/purged_$(date +%F)"

if [[ "$BACKUP_DIR" != /* ]]; then
    echo "[ERR]: Path traversal detected. BACKUP_DIR must be absolute: $BACKUP_DIR"
    exit 1
fi

# Track started databases for cleanup
STARTED_DBS=()

check_and_start_local_db() {
    # Expects IDX to be set
    local DATA_DIR="${PROFILES_DATA_DIR[$IDX]}"
    if [[ -z "$DATA_DIR" ]]; then
        return 0
    fi

    # Check if running
    get_bin_path "$IDX" "pg_ctl"
    local CUR_PG_CTL="$RET_VAL"
    if [[ ! -x "$CUR_PG_CTL" ]]; then
        # Can't check or start
        return 0
    fi

    if "$CUR_PG_CTL" status -D "$DATA_DIR" >/dev/null 2>&1; then
        # Already running
        return 0
    fi

    echo "[NOTICE]: Local database at '$DATA_DIR' is NOT running."
    read -p "Do you want to start it temporarily? [y/N]: " START_OPT
    if [[ ! "$START_OPT" =~ ^[Yy]$ ]]; then
        return 1
    fi

    echo "[INFO]: Starting database..."
    # Determine Log Dir
    local LOG_DIR="${SUITE_DIR}/logs/${PROFILES_NAME[$IDX]}"
    mkdir -p "$LOG_DIR"

    if "$CUR_PG_CTL" start -D "$DATA_DIR" -l "$LOG_DIR/startup.log"; then
        echo "[SUCCESS]: Database started."
        STARTED_DBS+=("$CUR_PG_CTL|$DATA_DIR")
        # Give it a moment
        sleep 2
    else
        echo "[ERR]: Failed to start database. Check log:"
        if [ -f "$LOG_DIR/startup.log" ]; then
            cat "$LOG_DIR/startup.log"
        else
            echo "Log file not found at $LOG_DIR/startup.log"
        fi
        return 1
    fi
    return 0
}

cleanup_started_dbs() {
    if [ ${#STARTED_DBS[@]} -eq 0 ]; then
        return
    fi
    
    echo ""
    echo "--- Cleanup ---"
    for ITEM in "${STARTED_DBS[@]}"; do
        IFS='|' read -r PG_CTL_PATH DATA_DIR <<< "$ITEM"
        echo "Local database at '$DATA_DIR' is still running (started by this session)."
        read -p "Do you want to stop it? [y/N]: " STOP_OPT
        if [[ "$STOP_OPT" =~ ^[Yy]$ ]]; then
             echo "[INFO]: Stopping database..."
             "$PG_CTL_PATH" stop -D "$DATA_DIR" -m fast
        fi
    done
}

trap cleanup_started_dbs EXIT

update_postgres_conf() {
    local CONF="$1"
    local KEY="$2"
    local VAL="$3"
    if grep -qE "^\s*${KEY}\s*=" "$CONF"; then
        sed -i -E "s|^\s*${KEY}\s*=.*|${KEY} = ${VAL}|" "$CONF"
    else
        echo "${KEY} = ${VAL}" >> "$CONF"
    fi
}

save_config() {
    (
        umask 077
        {
            echo "# PostgreSQL Profiles - Generated on $(date)"
            echo "# Do not edit manually unless you respect bash array syntax."

            if [[ -n "$CUSTOM_ENV_PATH" ]]; then
                echo ""
                echo "CUSTOM_ENV_PATH=\"$CUSTOM_ENV_PATH\""
                echo "export PATH=\"\$CUSTOM_ENV_PATH:\$PATH\""
                echo ""
            fi

            for i in "${!PROFILES_NAME[@]}"; do
                echo "PROFILES_NAME[$i]=\"${PROFILES_NAME[$i]}\""
                echo "PROFILES_HOST[$i]=\"${PROFILES_HOST[$i]}\""
                echo "PROFILES_PORT[$i]=\"${PROFILES_PORT[$i]}\""
                echo "PROFILES_ADMIN[$i]=\"${PROFILES_ADMIN[$i]}\""
                echo "PROFILES_DATA_DIR[$i]=\"${PROFILES_DATA_DIR[$i]}\""
                echo "PROFILES_PSQL_VERS[$i]=\"${PROFILES_PSQL_VERS[$i]}\""
                echo ""
            done
        } > "$CONFIG_FILE"
    )
    chmod 600 "$CONFIG_FILE"
    echo "[SUCCESS]: Configuration saved to $CONFIG_FILE"
}


# Check binaries
BIN_PSQL=$(which psql 2>/dev/null || true)

if [[ ! -x "$BIN_PSQL" && "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Search for psql binaries
    echo "Searching for 'psql' binaries..."
    # Using array to capture output line by line
    mapfile -t FOUND_PSQLS < <(find_tool_candidates psql)

    if [ ${#FOUND_PSQLS[@]} -eq 0 ]; then
        echo "[ERR]: 'psql' binary not found. Install postgresql:"
        echo "apt install postgresql"
        echo "#IF You prefer set up the service on Your own:"
        echo "systemctl stop postgresql"
        echo "systemctl disable postgresql"
        echo "systemctl mask postgresql"
        exit 1
    elif [ ${#FOUND_PSQLS[@]} -eq 1 ]; then
        BIN_PSQL="${FOUND_PSQLS[0]}"
        echo "Found one PostgreSQL version: $BIN_PSQL"
    else
        echo "Multiple PostgreSQL versions found:"
        for i in "${!FOUND_PSQLS[@]}"; do
            echo "  $i) ${FOUND_PSQLS[$i]}"
        done
        read -p "Select Version Index: " IDX
        if [[ -z "${FOUND_PSQLS[$IDX]}" ]]; then
            echo "[ERR]: Invalid selection."
            exit 1
        fi
        BIN_PSQL="${FOUND_PSQLS[$IDX]}"
    fi

    # Set CUSTOM_ENV_PATH based on selection
    if [[ -x "$BIN_PSQL" ]]; then
        PSQL_DIR=$(dirname "$BIN_PSQL")
        CUSTOM_ENV_PATH="$PSQL_DIR"
        export PATH="$CUSTOM_ENV_PATH:$PATH"
        echo "[INFO]: Using PostgreSQL from $PSQL_DIR"
        save_config
    fi
fi

BIN_INITDB=$(which initdb 2>/dev/null || true)
BIN_PG_DUMP=$(which pg_dump 2>/dev/null || true)
BIN_CREATEDB=$(which createdb 2>/dev/null || true)

# Detect Custom Path for psql if not already set (if we found it via 'which' but it's non-standard)
if [[ -x "$BIN_PSQL" && -z "$CUSTOM_ENV_PATH" ]]; then
    PSQL_DIR=$(dirname "$BIN_PSQL")
    # Check if it's a standard path
    if [[ "$PSQL_DIR" != "/usr/bin" && "$PSQL_DIR" != "/bin" && "$PSQL_DIR" != "/usr/local/bin" ]]; then
        CUSTOM_ENV_PATH="$PSQL_DIR"
        # Only export and update path if we are running directly
        if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
            export PATH="$CUSTOM_ENV_PATH:$PATH"
        fi
    fi
fi



get_bin_path() {
    local P_IDX="$1"
    local BIN_NAME="$2"
    local BASE_PATH="${PROFILES_PSQL_VERS[$P_IDX]}"
    RET_VAL=""

    if [[ -n "$BASE_PATH" && -x "$BASE_PATH/$BIN_NAME" ]]; then
        RET_VAL="$BASE_PATH/$BIN_NAME"
        return
    fi

    # Fallback 1: Check Global PATH
    local FOUND=$(which "$BIN_NAME" 2>/dev/null)
    if [[ -x "$FOUND" ]]; then
         RET_VAL="$FOUND"
         return
    fi

    # Fallback 2: Check relative to global BIN_PSQL (if set)
    if [[ -n "$BIN_PSQL" ]]; then
         local DIR=$(dirname "$BIN_PSQL")
         if [[ -x "$DIR/$BIN_NAME" ]]; then
             RET_VAL="$DIR/$BIN_NAME"
             return
         fi
         # Fallback 3: Resolve symlink of BIN_PSQL if it's a symlink
         if [[ -L "$BIN_PSQL" ]]; then
             local REAL_PSQL=$(readlink -f "$BIN_PSQL")
             local REAL_DIR=$(dirname "$REAL_PSQL")
              if [[ -x "$REAL_DIR/$BIN_NAME" ]]; then
                 RET_VAL="$REAL_DIR/$BIN_NAME"
                 return
             fi
         fi
    fi

    # 4. Interactive Search (New)
    >&2 echo "[WARN]: '$BIN_NAME' not found for profile '${PROFILES_NAME[$P_IDX]}'."
    >&2 echo "Searching system for '$BIN_NAME'..."

    local FOUND_BINS
    mapfile -t FOUND_BINS < <(find_tool_candidates "$BIN_NAME")

    local SELECTED_BIN=""

    if [ ${#FOUND_BINS[@]} -eq 0 ]; then
        >&2 echo "[ERR]: '$BIN_NAME' not found anywhere."
        return 1
    elif [ ${#FOUND_BINS[@]} -eq 1 ]; then
        SELECTED_BIN="${FOUND_BINS[0]}"
        >&2 echo "Found: $SELECTED_BIN"
    else
        >&2 echo "Multiple '$BIN_NAME' versions found:"
        for i in "${!FOUND_BINS[@]}"; do
            >&2 echo "  $i) ${FOUND_BINS[$i]}"
        done

        >&2 echo -n "Select Version Index: "
        read -r SEL_IDX
        if [[ -z "${FOUND_BINS[$SEL_IDX]}" ]]; then
            >&2 echo "[ERR]: Invalid selection."
            return 1
        fi
        SELECTED_BIN="${FOUND_BINS[$SEL_IDX]}"
    fi

    if [[ -x "$SELECTED_BIN" ]]; then
        local BIN_DIR=$(dirname "$SELECTED_BIN")

        >&2 echo "[INFO]: Updating profile '${PROFILES_NAME[$P_IDX]}' with path: $BIN_DIR"
        PROFILES_PSQL_VERS[$P_IDX]="$BIN_DIR"

        # Save config but silence stdout
        save_config > /dev/null

        # Update PATH
        export PATH="$BIN_DIR:$PATH"

        RET_VAL="$SELECTED_BIN"
    fi
}

get_admin_creds() {
    # Handles logic for Peer Auth vs Password Auth
    echo "[AUTH] Enter password for admin user '${PROFILES_ADMIN[$IDX]}':"
    echo "       (Press Enter if using Peer Auth / OS User)"
    IFS= read -rs DB_PASS
    
    if [[ -z "$DB_PASS" ]]; then
        unset PGPASSWORD
    else
        export PGPASSWORD="$DB_PASS"
    fi
    echo ""
}

update_conffile() {
    echo "--- Configuration Editor ---"
    echo "Existing profiles: ${#PROFILES_NAME[@]}"
    
    read -p "Enter Profile Index to edit or 'n' for new: " CHOICE
    
    if [[ "$CHOICE" == "n" ]]; then
        IDX=${#PROFILES_NAME[@]} 
    else
        IDX=$CHOICE
    fi

    echo "Editing Profile [$IDX]..."
    
    read -p "Profile Name [${PROFILES_NAME[$IDX]}]: " VAL; [ -n "$VAL" ] && PROFILES_NAME[$IDX]=$VAL
    read -p "DB Host/IP [${PROFILES_HOST[$IDX]}]: " VAL; [ -n "$VAL" ] && PROFILES_HOST[$IDX]=$VAL
    read -p "DB Port [${PROFILES_PORT[$IDX]}]: " VAL; [ -n "$VAL" ] && PROFILES_PORT[$IDX]=$VAL
    read -p "Admin Username [${PROFILES_ADMIN[$IDX]}]: " VAL; [ -n "$VAL" ] && PROFILES_ADMIN[$IDX]=$VAL
    read -p "Data Dir (Local only) [${PROFILES_DATA_DIR[$IDX]}]: " VAL; [ -n "$VAL" ] && PROFILES_DATA_DIR[$IDX]=$VAL
    read -p "PostgreSQL Bin Path (optional) [${PROFILES_PSQL_VERS[$IDX]}]: " VAL; [ -n "$VAL" ] && PROFILES_PSQL_VERS[$IDX]=$VAL

    save_config
}

self_update() {
    echo "--- Self Update ---"

    # Check for git
    if ! command -v git &> /dev/null; then
         echo "[ERR]: 'git' is not installed. Please install git."
         return
    fi

    # Check if .git exists
    if [ ! -d "../.git" ]; then
         echo "[ERR]: Not a git repository. Cannot auto-update."
         return
    fi

    echo "[INFO]: Pulling latest changes from remote..."
    git -C .. pull

    if [ $? -eq 0 ]; then
        echo "[SUCCESS]: Updated successfully. Please restart the script."
        exit 0
    else
        echo "[FAIL]: Update failed."
    fi
}

create_instance() {
    echo "--- Create Local Instance (initdb) ---"
    select_profile "Available Profiles:" || return

    get_bin_path "$IDX" "initdb"
    local CUR_INITDB="$RET_VAL"

    if [[ ! -x "$CUR_INITDB" ]]; then
        echo "[ERR]: 'initdb' not found for this profile."
        return
    fi

    TARGET_DIR="${PROFILES_DATA_DIR[$IDX]}"

    if [[ -z "$TARGET_DIR" ]]; then
        echo "[ERR]: No Data Directory defined for this profile."
        return
    fi

    if [[ -d "$TARGET_DIR" ]]; then
        if [ "$(ls -A $TARGET_DIR)" ]; then
            echo "[WARN]: Target directory '$TARGET_DIR' exists and is not empty."
            echo "1) Backup (tar.gz) and Recreate"
            echo "2) DELETE (rm -rf) and Recreate"
            echo "3) Cancel"
            read -p "Select: " ACT
            
            case "$ACT" in
                1)
                    mkdir -p "$BACKUP_DIR"
                    BAK_FILE="$BACKUP_DIR/raw_backup_$(date +%Y%m%d_%H%M).tar.gz"
                    echo "[INFO]: Archiving to $BAK_FILE..."
                    tar -czf "$BAK_FILE" -C "$TARGET_DIR" .
                    rm -rf "$TARGET_DIR"/*
                    ;;
                2)
                    echo "[INFO]: Purging directory..."
                    rm -rf "$TARGET_DIR"/*
                    ;;
                *) return ;;
            esac
        fi
    else
        mkdir -p "$TARGET_DIR"
    fi

    echo "[INFO]: Initializing database in $TARGET_DIR..."
    "$CUR_INITDB" -D "$TARGET_DIR" --auth-local=peer --auth-host=scram-sha-256
    
    if [[ $? -eq 0 ]]; then
        echo "[SUCCESS]: Instance initialized."

        # Configuration Setup
        CONF_FILE="$TARGET_DIR/postgresql.conf"
        cp "$CONF_FILE" "${CONF_FILE}.backup"

        # Clean up comments and empty lines
        sed -i -E '/^\s*#/d; /^\s*$/d' "$CONF_FILE"

        # Relocate system paths to target directory
        sed -i -E "s|'/(var\|run\|tmp)|'$TARGET_DIR/\1|g" "$CONF_FILE"
        mkdir -p "$TARGET_DIR/var" "$TARGET_DIR/run" "$TARGET_DIR/tmp"

        # Apply custom settings (Idempotent)
        update_postgres_conf "$CONF_FILE" "port" "${PROFILES_PORT[$IDX]}"
        update_postgres_conf "$CONF_FILE" "unix_socket_directories" "'$TARGET_DIR'"
        update_postgres_conf "$CONF_FILE" "logging_collector" "on"
        
        LOG_DIR="${SUITE_DIR}/logs/${PROFILES_NAME[$IDX]}"
        mkdir -p "$LOG_DIR"
        update_postgres_conf "$CONF_FILE" "log_directory" "'$LOG_DIR'"
        update_postgres_conf "$CONF_FILE" "log_filename" "'postgresql-%Y-%m-%d_%H%M%S.log'"

        echo "To start: pg_ctl -D $TARGET_DIR start"
    else
        echo "[FAIL]: initdb failed."
    fi
}

create_database() {
    echo "--- Create Database ---"
    select_profile "Available Profiles:" || return
    check_and_start_local_db || return
    get_admin_creds

    get_bin_path "$IDX" "psql"
    local CUR_PSQL="$RET_VAL"
    get_bin_path "$IDX" "pg_dump"
    local CUR_PG_DUMP="$RET_VAL"
    get_bin_path "$IDX" "createdb"
    local CUR_CREATEDB="$RET_VAL"

    DB_HOST="${PROFILES_HOST[$IDX]}"
    if [[ -z "$PGPASSWORD" && -n "${PROFILES_DATA_DIR[$IDX]}" ]]; then
        if [[ "$DB_HOST" == "localhost" || "$DB_HOST" == "127.0.0.1" || "$DB_HOST" == "::1" ]]; then
             DB_HOST="${PROFILES_DATA_DIR[$IDX]}"
             echo "[INFO]: Switching to Socket Connection for Peer Auth: $DB_HOST"
        fi
    fi

    read -p "Enter Target Database Name: " TGT_DB

    # Sanitize Database Name
    SAFE_DB=$(echo "$TGT_DB" | tr -cd '[:alnum:]_-')
    if [[ "$SAFE_DB" != "$TGT_DB" ]]; then
         echo "[WARN]: Sanitized database name from '$TGT_DB' to '$SAFE_DB'"
         TGT_DB="$SAFE_DB"
    fi
    if [[ -z "$TGT_DB" ]]; then
        echo "[ERR]: Database name cannot be empty."
        return
    fi

    # Check existence
    EXISTS=$("$CUR_PSQL" -h "$DB_HOST" -p "${PROFILES_PORT[$IDX]}" -U "${PROFILES_ADMIN[$IDX]}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$TGT_DB'")

    if [[ "$EXISTS" == "1" ]]; then
        echo "[WARN]: Database '$TGT_DB' already exists."
        echo "1) Dump and Recreate"
        echo "2) Drop and Recreate"
        echo "3) Skip"
        read -p "Select: " ACT

        case "$ACT" in
            1)
                mkdir -p "$BACKUP_DIR"
                DUMP_FILE="$BACKUP_DIR/${TGT_DB}_pre_drop_$(date +%Y%m%d).sql"
                echo "[INFO]: Dumping to $DUMP_FILE..."
                (umask 077 && "$CUR_PG_DUMP" -h "$DB_HOST" -p "${PROFILES_PORT[$IDX]}" -U "${PROFILES_ADMIN[$IDX]}" "$TGT_DB" > "$DUMP_FILE")
                ;& # Fallthrough to drop
            2)
                echo "[INFO]: Dropping database..."
                "$CUR_PSQL" -h "$DB_HOST" -p "${PROFILES_PORT[$IDX]}" -U "${PROFILES_ADMIN[$IDX]}" -d postgres -c "DROP DATABASE \"$TGT_DB\";"
                ;;
            *) return ;;
        esac
    fi

    echo "[INFO]: Creating database '$TGT_DB'..."
    if [[ -n "${PROFILES_DATA_DIR[$IDX]}" && -x "$CUR_CREATEDB" ]]; then
        "$CUR_CREATEDB" -h "$DB_HOST" -p "${PROFILES_PORT[$IDX]}" -U "${PROFILES_ADMIN[$IDX]}" "$TGT_DB"
    else
        "$CUR_PSQL" -h "$DB_HOST" -p "${PROFILES_PORT[$IDX]}" -U "${PROFILES_ADMIN[$IDX]}" -d postgres -c "CREATE DATABASE \"$TGT_DB\";"
    fi
}

create_user() {
    echo "--- Create / Update User ---"
    select_profile "Available Profiles:" || return
    check_and_start_local_db || return
    get_admin_creds

    get_bin_path "$IDX" "psql"
    local CUR_PSQL="$RET_VAL"

    DB_HOST="${PROFILES_HOST[$IDX]}"
    if [[ -z "$PGPASSWORD" && -n "${PROFILES_DATA_DIR[$IDX]}" ]]; then
        if [[ "$DB_HOST" == "localhost" || "$DB_HOST" == "127.0.0.1" || "$DB_HOST" == "::1" ]]; then
             DB_HOST="${PROFILES_DATA_DIR[$IDX]}"
             echo "[INFO]: Switching to Socket Connection for Peer Auth: $DB_HOST"
        fi
    fi

    read -p "Enter Username to create/update: " TGT_USER
    
    # Sanitize Username
    SAFE_USER=$(echo "$TGT_USER" | tr -cd '[:alnum:]_-')
    if [[ "$SAFE_USER" != "$TGT_USER" ]]; then
         echo "[WARN]: Sanitized username from '$TGT_USER' to '$SAFE_USER'"
         TGT_USER="$SAFE_USER"
    fi
    if [[ -z "$TGT_USER" ]]; then
        echo "[ERR]: Username cannot be empty."
        return
    fi

    read -s -p "Enter Password for $TGT_USER: " TGT_PASS
    echo ""

    read -p "Do you want to grant access to a specific database? [y/N]: " GRANT_OPT
    TGT_DB_GRANT=""
    
    if [[ "$GRANT_OPT" =~ ^[Yy]$ ]]; then
         # Temporarily set environment variables for get_database_list
         BIN_PSQL="$CUR_PSQL"
         DB_PORT="${PROFILES_PORT[$IDX]}"
         DB_USER="${PROFILES_ADMIN[$IDX]}"
         # DB_HOST is already set
         
         echo "Fetching database list..."
         DB_LIST=$(get_database_list)
         if [[ $? -eq 0 ]]; then
             echo "Available Databases:"
             echo "$DB_LIST"
         fi
         
         read -p "Enter Database to grant access to: " TGT_DB_GRANT
    fi

    # Escape Password (single quotes)
    ESCAPED_PASS="${TGT_PASS//\'/''}"

    # Check existence
    USER_EXISTS=$("$CUR_PSQL" -h "$DB_HOST" -p "${PROFILES_PORT[$IDX]}" -U "${PROFILES_ADMIN[$IDX]}" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$TGT_USER'")

    if [[ "$USER_EXISTS" == "1" ]]; then
        echo "[INFO]: User '$TGT_USER' exists. Updating password..."
        "$CUR_PSQL" -h "$DB_HOST" -p "${PROFILES_PORT[$IDX]}" -U "${PROFILES_ADMIN[$IDX]}" -d postgres -c "ALTER USER \"$TGT_USER\" WITH PASSWORD '$ESCAPED_PASS';"
    else
        echo "[INFO]: Creating new user '$TGT_USER'..."
        "$CUR_PSQL" -h "$DB_HOST" -p "${PROFILES_PORT[$IDX]}" -U "${PROFILES_ADMIN[$IDX]}" -d postgres -c "CREATE USER \"$TGT_USER\" WITH PASSWORD '$ESCAPED_PASS';"
    fi

    # Grants
    if [[ -n "$TGT_DB_GRANT" ]]; then
        # Sanitize DB Grant Name
        SAFE_DB_GRANT=$(echo "$TGT_DB_GRANT" | tr -cd '[:alnum:]_-')
        if [[ "$SAFE_DB_GRANT" != "$TGT_DB_GRANT" ]]; then
             echo "[WARN]: Sanitized grant database name to '$SAFE_DB_GRANT'"
             TGT_DB_GRANT="$SAFE_DB_GRANT"
        fi

        echo "[INFO]: Granting privileges on $TGT_DB_GRANT..."
        "$CUR_PSQL" -h "$DB_HOST" -p "${PROFILES_PORT[$IDX]}" -U "${PROFILES_ADMIN[$IDX]}" -d "$TGT_DB_GRANT" -c "GRANT ALL PRIVILEGES ON DATABASE \"$TGT_DB_GRANT\" TO \"$TGT_USER\"; GRANT USAGE ON SCHEMA public TO \"$TGT_USER\";"
    fi
}

# MAIN
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    while true; do
        echo ""
        echo "=== PostgreSQL Setup Tool ==="
        echo "1) Configure profiles (Edit/Add)"
        echo "2) Create local service instance (initdb)"
        echo "3) Create database (Dump/Drop/Create)"
        echo "4) Create/Update DB user"
        echo "5) Self Update (git pull)"
        echo "6) Exit"
        read -p "Select: " OPT

        case "$OPT" in
            1) update_conffile ;;
            2) create_instance ;;
            3) create_database ;;
            4) create_user ;;
            5) self_update ;;
            6) echo "Exiting."; exit 0 ;;
            *) echo "[ERR]: Invalid option." ;;
        esac
    done
fi
