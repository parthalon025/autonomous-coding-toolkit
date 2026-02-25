#!/usr/bin/env bash
# Test scripts/telemetry.sh — telemetry capture, show, export, reset
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TELEMETRY="$REPO_ROOT/scripts/telemetry.sh"

source "$SCRIPT_DIR/test-helpers.sh"

# --- Setup ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/logs"

# --- Test 1: record writes to telemetry.jsonl ---
bash "$TELEMETRY" record --project-root "$WORK" \
    --batch-number 1 --passed true --strategy superpowers \
    --duration 120 --cost 0.42 --test-delta 5 2>&1 || true
assert_eq "record creates telemetry.jsonl" "true" \
    "$([ -f "$WORK/logs/telemetry.jsonl" ] && echo true || echo false)"

# --- Test 2: record appends valid JSON ---
line=$(head -1 "$WORK/logs/telemetry.jsonl")
echo "$line" | jq . >/dev/null 2>&1
assert_eq "record writes valid JSON" "0" "$?"

# --- Test 3: show produces dashboard output ---
output=$(bash "$TELEMETRY" show --project-root "$WORK" 2>&1 || true)
assert_contains "show displays header" "Telemetry Dashboard" "$output"

# --- Test 4: export produces anonymized output ---
bash "$TELEMETRY" export --project-root "$WORK" > "$WORK/export.json" 2>&1 || true
assert_eq "export creates output" "true" "$([ -s "$WORK/export.json" ] && echo true || echo false)"

# --- Test 5: reset clears telemetry ---
bash "$TELEMETRY" reset --project-root "$WORK" --yes 2>&1 || true
if [[ -f "$WORK/logs/telemetry.jsonl" ]]; then
    line_count=$(wc -l < "$WORK/logs/telemetry.jsonl")
    assert_eq "reset clears telemetry" "0" "$line_count"
else
    pass "reset removes telemetry file"
fi

report_results
