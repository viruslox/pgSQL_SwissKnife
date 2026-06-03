#!/bin/bash

# PostgreSQL SwissKnife -> Performance Monitor

# --- Execution Helper ---
run_query() {
    local query="$1"
    shift
    "$BIN_PSQL" -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A "$@" -c "$query"
    if [[ $? -ne 0 ]]; then
        echo "[FAIL]: Query failed. Check connection or permissions."
        exit 1
    fi
}

# Helper to trim output
clean() {
    local var="$1"
    while [[ "$var" == $'\n'* ]]; do var="${var#$'\n'}"; done
    while [[ "$var" == *$'\n' ]]; do var="${var%$'\n'}"; done
    [[ -n "$var" ]] && printf "%s\n" "$var"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    REQUIRE_CONFIG=true
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
    load_config

    # Binary resolution is handled by common.sh (require_tools -> resolve_tool)
    require_tools psql || exit 1

    # Profile Selection
    select_profile "Select Target Instance" || exit 1

    # Connection Setup
    setup_connection

    echo -n "Target Database Name [default: postgres]: "
    read DB_NAME
    DB_NAME=${DB_NAME:-"postgres"}

    echo "Performance audit: ${PROFILES_NAME[$IDX]} ($DB_NAME)"
    echo "Time: $(date +%Y-%m-%dT%H:%M:%S)"

    # Consolidated Query Execution
    FULL_QUERY="
    SELECT
      'Hit Ratio: ' ||
      ROUND(sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read) + 0.0001) * 100, 2) || '%'
    FROM pg_statio_user_tables;
    SELECT '---SEPARATOR---';
    SELECT 'Active: ' || count(*) || ' / Max: ' || current_setting('max_connections')
    FROM pg_stat_activity
    WHERE state = 'active';
    SELECT '---SEPARATOR---';
    SELECT pid || ' | ' || usename || ' | ' || (now() - query_start)::text || ' | ' || left(query, 50)
    FROM pg_stat_activity
    WHERE state = 'active' AND (now() - query_start) > interval '1 second';
    SELECT '---SEPARATOR---';
    SELECT pg_size_pretty(pg_database_size(current_database()));
    "

    RAW_OUTPUT=$(run_query "$FULL_QUERY")
    if [[ $? -ne 0 ]]; then
        echo "$RAW_OUTPUT"
        exit 1
    fi

    # Parse Output
    METRIC1=""
    METRIC2=""
    METRIC3=""
    METRIC4=""
    IDX=1

    while IFS= read -r line; do
        if [[ "$line" == "---SEPARATOR---" ]]; then
            ((IDX++))
        else
            if [[ $IDX -eq 1 ]]; then METRIC1="${METRIC1}${METRIC1:+$'\n'}${line}";
            elif [[ $IDX -eq 2 ]]; then METRIC2="${METRIC2}${METRIC2:+$'\n'}${line}";
            elif [[ $IDX -eq 3 ]]; then METRIC3="${METRIC3}${METRIC3:+$'\n'}${line}";
            elif [[ $IDX -eq 4 ]]; then METRIC4="${METRIC4}${METRIC4:+$'\n'}${line}";
            fi
        fi
    done <<< "$RAW_OUTPUT"

    # 1. Cache Hit Ratio
    echo ""
    echo "[METRIC]: Cache Hit Ratio (Target: >99%)"
    clean "$METRIC1"

    # 2. Active Connections
    echo ""
    echo "[METRIC]: Active Connections"
    clean "$METRIC2"

    # 3. Slow Queries (>1 second)
    echo ""
    echo "[METRIC]: Slow Queries (> 1s)"
    SLOW_Q=$(clean "$METRIC3")

    if [[ -z "$SLOW_Q" ]]; then
        echo "[OK]: No slow queries detected."
    else
        echo "PID | User | Duration | Query Snippet"
        echo "$SLOW_Q"
    fi

    # 4. DB Size
    echo ""
    echo "[METRIC]: Database Size"
    clean "$METRIC4"

    echo ""
    echo "Performance audit complete"
    exit 0
fi
