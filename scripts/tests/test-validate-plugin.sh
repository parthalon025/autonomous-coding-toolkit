#!/usr/bin/env bash
# Test validate-plugin.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

VALIDATOR="$SCRIPT_DIR/../validate-plugin.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Helper: create plugin files
create_plugin() {
    local plugin_json="$1" marketplace_json="$2"
    mkdir -p "$WORK/.claude-plugin"
    echo "$plugin_json" > "$WORK/.claude-plugin/plugin.json"
    echo "$marketplace_json" > "$WORK/.claude-plugin/marketplace.json"
}

# Helper: run validator against temp dir
run_validator() {
    local exit_code=0
    PLUGIN_DIR="$WORK/.claude-plugin" bash "$VALIDATOR" "$@" 2>&1 || exit_code=$?
    echo "EXIT:$exit_code"
}

# === Test: Matching name and version passes ===
create_plugin \
    '{"name":"my-toolkit","version":"1.0.0","description":"Test"}' \
    '{"name":"my-toolkit","plugins":[{"name":"my-toolkit","version":"1.0.0"}]}'

output=$(run_validator)
assert_contains "matching: PASS" "validate-plugin: PASS" "$output"
assert_contains "matching: exit 0" "EXIT:0" "$output"

# === Test: Mismatched name fails ===
create_plugin \
    '{"name":"toolkit-a","version":"1.0.0","description":"Test"}' \
    '{"name":"toolkit-b","plugins":[{"name":"toolkit-b","version":"1.0.0"}]}'

output=$(run_validator)
assert_contains "name mismatch: reports violation" "name mismatch" "$output"
assert_contains "name mismatch: exit 1" "EXIT:1" "$output"

# === Test: Mismatched version fails ===
create_plugin \
    '{"name":"my-toolkit","version":"1.0.0","description":"Test"}' \
    '{"name":"my-toolkit","plugins":[{"name":"my-toolkit","version":"2.0.0"}]}'

output=$(run_validator)
assert_contains "version mismatch: reports violation" "version mismatch" "$output"
assert_contains "version mismatch: exit 1" "EXIT:1" "$output"

# === Test: Missing plugin.json fails ===
rm -rf "$WORK/.claude-plugin"
mkdir -p "$WORK/.claude-plugin"
echo '{"name":"x","plugins":[{"name":"x","version":"1.0.0"}]}' > "$WORK/.claude-plugin/marketplace.json"

output=$(run_validator)
assert_contains "missing plugin.json: error" "plugin.json not found" "$output"
assert_contains "missing plugin.json: exit 1" "EXIT:1" "$output"

# === Test: Missing marketplace.json fails ===
rm -rf "$WORK/.claude-plugin"
mkdir -p "$WORK/.claude-plugin"
echo '{"name":"x","version":"1.0.0"}' > "$WORK/.claude-plugin/plugin.json"

output=$(run_validator)
assert_contains "missing marketplace.json: error" "marketplace.json not found" "$output"
assert_contains "missing marketplace.json: exit 1" "EXIT:1" "$output"

# === Test: Invalid JSON in plugin.json fails ===
create_plugin '{invalid json' '{"name":"x","plugins":[{"name":"x","version":"1.0.0"}]}'

output=$(run_validator)
assert_contains "invalid plugin.json: error" "plugin.json is not valid JSON" "$output"
assert_contains "invalid plugin.json: exit 1" "EXIT:1" "$output"

# === Test: Invalid JSON in marketplace.json fails ===
create_plugin '{"name":"x","version":"1.0.0"}' '{invalid json'

output=$(run_validator)
assert_contains "invalid marketplace.json: error" "marketplace.json is not valid JSON" "$output"
assert_contains "invalid marketplace.json: exit 1" "EXIT:1" "$output"

# === Test: --warn exits 0 even with violations ===
create_plugin \
    '{"name":"a","version":"1.0.0"}' \
    '{"name":"b","plugins":[{"name":"b","version":"1.0.0"}]}'

output=$(run_validator --warn)
assert_contains "--warn: still reports violation" "name mismatch" "$output"
assert_contains "--warn: exits 0" "EXIT:0" "$output"

# === Test: --help exits 0 ===
output=$(run_validator --help)
assert_contains "--help: shows usage" "Usage:" "$output"
assert_contains "--help: exits 0" "EXIT:0" "$output"

# === Test: Missing plugin directory fails ===
rm -rf "$WORK/.claude-plugin"
output=$(PLUGIN_DIR="$WORK/nonexistent" bash "$VALIDATOR" 2>&1 || echo "EXIT:$?")
assert_contains "missing dir: error message" "plugin directory not found" "$output"
assert_contains "missing dir: exit 1" "EXIT:1" "$output"

report_results
