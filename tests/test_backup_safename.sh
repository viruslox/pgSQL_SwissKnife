#!/bin/bash
# Test Backup.sh with empty SAFE_NAME

set -e

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Mock Binaries
MOCK_BIN_DIR="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN_DIR"
export PATH="$MOCK_BIN_DIR:$PATH"

# Mock psql, pg_dump, gzip
echo -e '#!/bin/bash\nexit 0' > "$MOCK_BIN_DIR/psql"
echo -e '#!/bin/bash\nexit 0' > "$MOCK_BIN_DIR/pg_dump"
echo -e '#!/bin/bash\ncat' > "$MOCK_BIN_DIR/gzip"
chmod +x "$MOCK_BIN_DIR"/*

# Setup Modules
MODULES_DIR="$TEST_DIR/modules"
mkdir -p "$MODULES_DIR"

if [ -f "../modules/Backup.sh" ]; then
    cp "../modules/Backup.sh" "$MODULES_DIR/"
else
    cp "modules/Backup.sh" "$MODULES_DIR/"
fi

# Mock common.sh
cat << 'EOF' > "$MODULES_DIR/common.sh"
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"

load_config() {
    PROFILES_NAME=("!!!")
    PROFILES_HOST=("localhost")
    PROFILES_PORT=("5432")
    PROFILES_ADMIN=("postgres")
    PROFILES_DATA_DIR=("/tmp")
    PROFILES_PSQL_VERS=("")
    IDX=0
}
select_profile() {
    IDX=0
    return 0
}
require_binary() {
    echo "$1"
}
# Mock resolve_tool and require_tools
resolve_tool() {
    local VAR_NAME="BIN_$(echo "$1" | tr '[:lower:]' '[:upper:]')"
    printf -v "$VAR_NAME" "%s" "$1"
    return 0
}
require_tool() {
    return 0
}
require_tools() {
    return 0
}
setup_connection() {
    :
}
get_database_list() {
    echo "db1"
}
EOF
chmod +x "$MODULES_DIR/common.sh"

cd "$MODULES_DIR"

echo "Running Backup.sh with invalid profile name '!!!'..."
output=$(bash ./Backup.sh 2>&1 || true)

if echo "$output" | grep -q "Resulted in empty safe name"; then
    echo "Backup.sh failed as expected with correct error."
    exit 0
else
    echo "Backup.sh failed but NOT for the expected reason."
    echo "Output: $output"
    exit 1
fi
