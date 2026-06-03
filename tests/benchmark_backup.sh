#!/bin/bash
# tests/benchmark_backup.sh

set -e

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
# Mock psql that returns a list of 10 databases
if [[ "$@" == *"SELECT datname FROM pg_database"* ]]; then
    for i in {1..10}; do
        echo "db$i"
    done
    exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/psql"

# Create Mock pg_dump that sleeps for 0.5 seconds
cat << 'EOF' > "$MOCK_BIN_DIR/pg_dump"
#!/bin/bash
sleep 0.5
echo "DUMP CONTENT"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/pg_dump"

# Create Mock gzip
cat << 'EOF' > "$MOCK_BIN_DIR/gzip"
#!/bin/bash
cat
EOF
chmod +x "$MOCK_BIN_DIR/gzip"

# Mock Config
CONFIG_DIR="$TEST_DIR/config"
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/PostgreSQL_SwissKnife.conf"

cat << EOF > "$CONFIG_FILE"
PROFILES_NAME=("BenchmarkProfile")
PROFILES_HOST=("localhost")
PROFILES_PORT=("5432")
PROFILES_ADMIN=("postgres")
PROFILES_DATA_DIR=("$TEST_DIR/data")
PROFILES_PSQL_VERS=("")
EOF

# Copy modules to the test dir
MODULES_DIR="$TEST_DIR/modules"
mkdir -p "$MODULES_DIR"
cp -r modules/* "$MODULES_DIR/"

# Create logs directory
mkdir -p "$TEST_DIR/logs"

BACKUP_SCRIPT="$MODULES_DIR/Backup.sh"

echo "Starting Benchmark..."
START_TIME=$(date +%s%N)

# Run Backup.sh
export TARGET_PROFILE_IDX=0
bash "$BACKUP_SCRIPT" > "$TEST_DIR/backup.log" 2>&1 || { echo "Backup failed"; cat "$TEST_DIR/backup.log"; exit 1; }

END_TIME=$(date +%s%N)
DURATION=$(( (END_TIME - START_TIME) / 1000000 ))

echo "Backup took ${DURATION} ms"

# Verify that 10 backups were created
BACKUP_DIR="$TEST_DIR/backups/BenchmarkProfile"
FILE_COUNT=$(find "$BACKUP_DIR" -type f -name "*.sql*" | wc -l)

if [[ "$FILE_COUNT" -ne 10 ]]; then
    echo "FAILED: Expected 10 backup files, found $FILE_COUNT"
    cat "$TEST_DIR/backup.log"
    exit 1
fi
echo "Benchmark and Verification Successful"
