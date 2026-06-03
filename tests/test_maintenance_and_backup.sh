#!/bin/bash

# tests/test_maintenance_and_backup.sh

# Exit on error
set -e

# Paths
MAINTENANCE_SH="$(dirname "$0")/../modules/Maintenance.sh"
BACKUP_SH="$(dirname "$0")/../modules/Backup.sh"

# Create a temporary workspace
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock Bin Directory
MOCK_BIN_DIR="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN_DIR"
export PATH="$MOCK_BIN_DIR:$PATH"

# Create Mock psql
cat << 'EOF' > "$MOCK_BIN_DIR/psql"
#!/bin/bash
# Mock psql

ARGS="$@"

# Check if the query is for listing databases (Maintenance.sh and Backup.sh)
if [[ "$ARGS" == *"SELECT datname FROM pg_database WHERE datistemplate = false"* ]]; then
    echo "db1"
    echo "db2"
    exit 0
fi

# Check if the query is for missing PKs (Maintenance.sh)
if [[ "$ARGS" == *"information_schema.table_constraints"* ]]; then
    # Return nothing (no missing PKs)
    exit 0
fi

# Check if the query is for dead tuples (Maintenance.sh)
if [[ "$ARGS" == *"n_dead_tup::float"* ]]; then
    # Return nothing (no dead tuples)
    exit 0
fi

# Default success for other queries
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/psql"

# Create Mock vacuumdb
cat << 'EOF' > "$MOCK_BIN_DIR/vacuumdb"
#!/bin/bash
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/vacuumdb"

# Create Mock pg_dump
cat << 'EOF' > "$MOCK_BIN_DIR/pg_dump"
#!/bin/bash
echo "DUMP CONTENT"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/pg_dump"

# Create Mock gzip
cat << 'EOF' > "$MOCK_BIN_DIR/gzip"
#!/bin/bash
cat # pass through
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/gzip"


# Create Mock Config
CONFIG_DIR="$TEST_DIR/config"
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/pgSQL_SwissKnife.conf"

cat << EOF > "$CONFIG_FILE"
PROFILES_NAME=("TestProfile")
PROFILES_HOST=("localhost")
PROFILES_PORT=("5432")
PROFILES_ADMIN=("postgres")
PROFILES_DATA_DIR=("$TEST_DIR/data")
PROFILES_PSQL_VERS=("")
EOF

# Copy modules to the test dir so they can find the config via relative path
MODULES_DIR="$TEST_DIR/modules"
mkdir -p "$MODULES_DIR"
cp -r "$(dirname "$0")/../modules/"* "$MODULES_DIR/"

# Now we run the modules from the test dir
MAINTENANCE_SCRIPT="$MODULES_DIR/Maintenance.sh"
BACKUP_SCRIPT="$MODULES_DIR/Backup.sh"

# Test 1: Maintenance.sh
echo "--- Testing Maintenance.sh ---"
export TARGET_PROFILE_IDX=0
bash "$MAINTENANCE_SCRIPT" > "$TEST_DIR/maintenance.log" 2>&1 || { cat "$TEST_DIR/maintenance.log"; exit 1; }

# Verify it processed db1 and db2
if ! grep -Fq "[DB]: db1" "$TEST_DIR/maintenance.log"; then
    echo "FAILED: Maintenance.sh did not process db1"
    cat "$TEST_DIR/maintenance.log"
    exit 1
fi
if ! grep -Fq "[DB]: db2" "$TEST_DIR/maintenance.log"; then
    echo "FAILED: Maintenance.sh did not process db2"
    cat "$TEST_DIR/maintenance.log"
    exit 1
fi
echo "Maintenance.sh PASSED"

# Test 2: Backup.sh
echo "--- Testing Backup.sh ---"
export TARGET_PROFILE_IDX=0
# Backup.sh writes to ../backups relative to itself.
# Since SCRIPT is in $MODULES_DIR ($TEST_DIR/modules), ../backups is $TEST_DIR/backups
bash "$BACKUP_SCRIPT" > "$TEST_DIR/backup.log" 2>&1 || { cat "$TEST_DIR/backup.log"; exit 1; }

# Verify backups were created
BACKUP_DIR="$TEST_DIR/backups/TestProfile"
if [ ! -d "$BACKUP_DIR" ]; then
    echo "FAILED: Backup directory not created at $BACKUP_DIR"
    echo "Found instead:"
    find "$TEST_DIR" -maxdepth 3 -type d
    exit 1
fi

# Verify dump files exist (gzip enabled by default mock)
# Since gzip is mocked as pass-through, and pg_dump outputs "DUMP CONTENT", checking for files.
# The script names them ${TIMESTAMP}_${DB}.sql.gz
if ls "$BACKUP_DIR"/*_db1.sql.gz >/dev/null 2>&1; then
    echo "Found db1 backup"
else
    echo "FAILED: Backup for db1 not found"
    ls -R "$TEST_DIR/backups"
    exit 1
fi

if ls "$BACKUP_DIR"/*_db2.sql.gz >/dev/null 2>&1; then
    echo "Found db2 backup"
else
    echo "FAILED: Backup for db2 not found"
    ls -R "$TEST_DIR/backups"
    exit 1
fi
echo "Backup.sh PASSED"

echo "ALL TESTS PASSED"
