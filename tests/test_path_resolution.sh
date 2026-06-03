#!/bin/bash
set -e

# Mock Environment Setup
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock Bin Directory
MOCK_BIN_DIR="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN_DIR"
export PATH="$MOCK_BIN_DIR:$PATH"

# Create Mock psql (returns db1 for get_database_list)
cat << 'EOF' > "$MOCK_BIN_DIR/psql"
#!/bin/bash
if [[ "$*" == *"SELECT datname FROM pg_database"* ]]; then
    echo "db1"
    exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/psql"

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
cat
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/gzip"

# Mock Config
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

# Copy modules to the test dir
MODULES_DIR="$TEST_DIR/modules"
mkdir -p "$MODULES_DIR"

if [ -d "../modules" ]; then
    cp -r ../modules/* "$MODULES_DIR/"
else
    cp -r modules/* "$MODULES_DIR/"
fi

# Run Backup.sh
export TARGET_PROFILE_IDX=0
BACKUP_SCRIPT="$MODULES_DIR/Backup.sh"

# Capture output
OUTPUT_LOG="$TEST_DIR/output.log"
bash "$BACKUP_SCRIPT" > "$OUTPUT_LOG" 2>&1 || { cat "$OUTPUT_LOG"; exit 1; }

# Parse "Target Dir: ..."
TARGET_DIR=$(grep "Target Dir: " "$OUTPUT_LOG" | cut -d ' ' -f 3)

echo "Extracted Target Dir: '$TARGET_DIR'"
echo "Test Dir: '$TEST_DIR'"

# Check if it starts with / (Absolute) AND is within TEST_DIR
if [[ "$TARGET_DIR" == "$TEST_DIR/backups/TestProfile" ]]; then
    echo "SUCCESS: Target Dir is correct and absolute: $TARGET_DIR"
else
    echo "FAILURE: Target Dir is incorrect."
    echo "Expected: $TEST_DIR/backups/TestProfile"
    echo "Actual:   $TARGET_DIR"
    exit 1
fi
