#!/usr/bin/env bash
# Test setup-ralph-loop.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SETUP_SCRIPT="$SCRIPT_DIR/../setup-ralph-loop.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Run setup-ralph-loop in a temp dir so it writes .claude/ there
run_setup() {
    (cd "$WORK" && bash "$SETUP_SCRIPT" "$@" 2>&1)
}

get_yaml_promise() {
    sed -n 's/^completion_promise: *//p' "$WORK/.claude/ralph-loop.local.md"
}

# === Test: Basic prompt creates state file ===
rm -rf "$WORK/.claude"
output=$(run_setup "Hello world")
assert_contains "basic: creates state file" "Ralph loop activated" "$output"
assert_contains "basic: shows prompt" "Hello world" "$output"

# === Test: Completion promise with double quotes is safely quoted (#22) ===
rm -rf "$WORK/.claude"
output=$(run_setup 'Build it' --completion-promise 'say "hello" done')
yaml_val=$(get_yaml_promise)
# jq produces JSON-quoted string: "say \"hello\" done"
assert_contains "double quotes: safely quoted" '\"hello\"' "$yaml_val"

# === Test: Completion promise with backslashes is safely quoted (#22) ===
rm -rf "$WORK/.claude"
output=$(run_setup 'Build it' --completion-promise 'path\to\thing')
yaml_val=$(get_yaml_promise)
# jq produces: "path\\to\\thing"
assert_contains "backslash: safely quoted" '\\' "$yaml_val"

# === Test: Completion promise with single quotes is safely quoted (#22) ===
rm -rf "$WORK/.claude"
output=$(run_setup 'Build it' --completion-promise "it's done")
yaml_val=$(get_yaml_promise)
assert_contains "single quote: safely quoted" "it's done" "$yaml_val"

# === Test: Null completion promise stays null ===
rm -rf "$WORK/.claude"
output=$(run_setup "Build it")
yaml_val=$(get_yaml_promise)
assert_eq "null promise: stays null" "null" "$yaml_val"

# === Test: --help exits 0 ===
output=$(bash "$SETUP_SCRIPT" --help 2>&1 || echo "EXIT:$?")
assert_contains "--help: shows usage" "USAGE:" "$output"
assert_not_contains "--help: exit 0" "EXIT:" "$output"

# === Test: No prompt exits 1 ===
rm -rf "$WORK/.claude"
output=$(run_setup 2>&1 || echo "EXIT:$?")
assert_contains "no prompt: exits 1" "EXIT:1" "$output"

report_results
