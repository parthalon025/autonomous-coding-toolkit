#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PULL="$SCRIPT_DIR/../pull-community-lessons.sh"

# --- Test: --help exits 0 ---
assert_exit "--help exits 0" 0 "$PULL" --help

# --- Test: missing upstream remote exits 1 gracefully ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR" && git init -q && git commit --allow-empty -m "init" -q
pull_output=$("$PULL" --remote nonexistent 2>&1) || true
pull_exit=0
"$PULL" --remote nonexistent > /dev/null 2>&1 || pull_exit=$?
assert_eq "missing remote exits 1" "1" "$pull_exit"
assert_contains "missing remote error message" "not found" "$pull_output"

# --- Test: --dry-run without remote shows status ---
dry_output=$("$PULL" --remote nonexistent --dry-run 2>&1) || true
# Should still fail because remote doesn't exist (dry-run doesn't skip validation)
assert_contains "--dry-run mentions remote name" "nonexistent" "$dry_output"

report_results
