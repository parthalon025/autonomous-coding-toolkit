#!/usr/bin/env bash
# Test validate-commands.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

VALIDATOR="$SCRIPT_DIR/../validate-commands.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Helper: create a command file
create_command() {
    local name="$1" content="$2"
    mkdir -p "$WORK/commands"
    echo "$content" > "$WORK/commands/$name"
}

# Helper: run validator against temp commands dir
run_validator() {
    local exit_code=0
    COMMANDS_DIR="$WORK/commands" bash "$VALIDATOR" "$@" 2>&1 || exit_code=$?
    echo "EXIT:$exit_code"
}

# === Test: Valid command passes ===
rm -rf "$WORK/commands"
create_command "my-command.md" '---
description: "A test command"
---
Body text here.'

output=$(run_validator)
assert_contains "valid command: PASS" "validate-commands: PASS" "$output"
assert_contains "valid command: exit 0" "EXIT:0" "$output"

# === Test: Missing description field fails ===
rm -rf "$WORK/commands"
create_command "no-desc.md" '---
argument-hint: "<thing>"
---
Body.'

output=$(run_validator)
assert_contains "missing description: reports violation" "Missing required field: description" "$output"
assert_contains "missing description: exit 1" "EXIT:1" "$output"

# === Test: Missing frontmatter start fails ===
rm -rf "$WORK/commands"
create_command "no-front.md" 'description: "No frontmatter markers"
Some body.'

output=$(run_validator)
assert_contains "missing ---: reports violation" "First line must be '---'" "$output"
assert_contains "missing ---: exit 1" "EXIT:1" "$output"

# === Test: Missing closing --- fails ===
rm -rf "$WORK/commands"
create_command "no-close.md" '---
description: "Unclosed frontmatter"
Body text without closing delimiter.'

output=$(run_validator)
assert_contains "missing close ---: reports violation" "Frontmatter not closed" "$output"
assert_contains "missing close ---: exit 1" "EXIT:1" "$output"

# === Test: --warn exits 0 even with violations ===
rm -rf "$WORK/commands"
create_command "warn-test.md" '---
argument-hint: "<thing>"
---
Body.'

output=$(run_validator --warn)
assert_contains "--warn: still reports violation" "Missing required field: description" "$output"
assert_contains "--warn: exits 0" "EXIT:0" "$output"

# === Test: --help exits 0 ===
output=$(run_validator --help)
assert_contains "--help: shows usage" "Usage:" "$output"
assert_contains "--help: exits 0" "EXIT:0" "$output"

# === Test: Missing commands directory fails ===
rm -rf "$WORK/commands"
output=$(COMMANDS_DIR="$WORK/nonexistent" bash "$VALIDATOR" 2>&1 || echo "EXIT:$?")
assert_contains "missing dir: error message" "commands directory not found" "$output"
assert_contains "missing dir: exit 1" "EXIT:1" "$output"

report_results
