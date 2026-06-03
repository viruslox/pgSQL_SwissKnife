#!/bin/bash

# PostgreSQL SwissKnife -> Maintenance Task

REQUIRE_CONFIG=true
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config

DEAD_TUPLE_RATIO=0.1

require_tools psql vacuumdb || exit 1

# Profile Selection
select_profile "Select Instance for Maintenance" || exit 1

# Connection Setup
setup_connection

echo "Starting Maintenance: ${PROFILES_NAME[$IDX]}"
echo "Host: $DB_HOST | User: $DB_USER | Date: $(date)"

# Get list of all non-template databases
DB_LIST=$(get_database_list) || exit 1

while IFS= read -r DB; do
    echo "---------------------------------------------------"
    echo "[DB]: $DB"

    # 1. Missing Primary Keys Check
    MISSING_PK=$("$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB" -t -A -c "
        SELECT table_name FROM information_schema.tables t
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
        AND NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints c
            WHERE c.table_name = t.table_name AND c.constraint_type = 'PRIMARY KEY'
        );" 2>/dev/null)

    if [[ -n "$MISSING_PK" ]]; then
        echo "[WARN]: Tables missing Primary Key:"
        echo "$MISSING_PK" | awk '{print "  - "$0}'
    else
        echo "[OK]: All public tables have PKs."
    fi

    # 2. Dead Tuples & Vacuum
    NEED_VACUUM=$("$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB" -t -A -c "
        SELECT relname FROM pg_stat_user_tables
        WHERE n_live_tup > 0
        AND (n_dead_tup::float / n_live_tup::float) > $DEAD_TUPLE_RATIO;" 2>/dev/null)

    if [[ -n "$NEED_VACUUM" ]]; then
        echo "[INFO]: Dead tuple threshold exceeded. Running VACUUM ANALYZE..."
        VACUUM_ARGS=()
        while IFS= read -r TBL; do
            VACUUM_ARGS+=("-t" "$TBL")
        done <<< "$NEED_VACUUM"
        echo -n "  > Vacuuming tables: $(echo "$NEED_VACUUM" | xargs) ... "
        "$BIN_VACUUMDB" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB" "${VACUUM_ARGS[@]}" -z
        echo "Done."
    else
        echo "[OK]: No tables exceed dead tuple ratio ($DEAD_TUPLE_RATIO)."
    fi
done <<< "$DB_LIST"

echo ""
echo "Maintenance complete."
exit 0