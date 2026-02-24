#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PROMOTE="$SCRIPT_DIR/../promote-mab-lessons.sh"

# --- Setup ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/logs" "$TMPDIR/docs/lessons"

# --- Test: --help exits 0 ---
assert_exit "--help exits 0" 0 "$PROMOTE" --help

# --- Test: no promotions when all below threshold ---
cat > "$TMPDIR/logs/mab-lessons.json" <<'JSON'
[
  {"pattern": "rare pattern", "context": "new-file", "winner": "superpowers", "occurrences": 1, "promoted": false},
  {"pattern": "another rare", "context": "refactoring", "winner": "ralph", "occurrences": 2, "promoted": false}
]
JSON

output=$("$PROMOTE" --worktree "$TMPDIR" --min-occurrences 3 2>&1) || true
lesson_count=$(find "$TMPDIR/docs/lessons" -name "*.md" -newer "$TMPDIR/logs/mab-lessons.json" 2>/dev/null | wc -l)
assert_eq "no promotions below threshold" "0" "$lesson_count"

# --- Test: promotes at 3+ occurrences ---
cat > "$TMPDIR/logs/mab-lessons.json" <<'JSON'
[
  {"pattern": "check imports before tests", "context": "integration", "winner": "superpowers", "occurrences": 5, "promoted": false},
  {"pattern": "rare pattern", "context": "new-file", "winner": "ralph", "occurrences": 1, "promoted": false}
]
JSON

"$PROMOTE" --worktree "$TMPDIR" --min-occurrences 3 > /dev/null 2>&1 || true

# Check a lesson file was created
promoted_files=$(find "$TMPDIR/docs/lessons" -name "*.md" 2>/dev/null)
TESTS=$((TESTS + 1))
if [[ -n "$promoted_files" ]]; then
    echo "PASS: promotes at 3+ occurrences"
else
    echo "FAIL: no lesson file created for pattern with 5 occurrences"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: promoted file has YAML frontmatter ---
if [[ -n "$promoted_files" ]]; then
    first_file=$(echo "$promoted_files" | head -1)
    first_line=$(head -1 "$first_file")
    assert_eq "promoted file starts with YAML frontmatter" "---" "$first_line"

    file_content=$(cat "$first_file")
    assert_contains "promoted file has pattern field" "pattern:" "$file_content"
fi

# --- Test: marks lessons as promoted in JSON ---
promoted_count=$(jq '[.[] | select(.promoted == true)] | length' "$TMPDIR/logs/mab-lessons.json" 2>/dev/null || echo "0")
assert_eq "promoted lesson marked in JSON" "1" "$promoted_count"

# --- Test: --dry-run creates no files ---
# Reset
rm -f "$TMPDIR/docs/lessons"/*.md
cat > "$TMPDIR/logs/mab-lessons.json" <<'JSON'
[
  {"pattern": "should not create file", "context": "test-only", "winner": "ralph", "occurrences": 10, "promoted": false}
]
JSON

"$PROMOTE" --worktree "$TMPDIR" --min-occurrences 3 --dry-run > /dev/null 2>&1 || true
dry_files=$(find "$TMPDIR/docs/lessons" -name "*.md" 2>/dev/null | wc -l)
assert_eq "--dry-run creates no files" "0" "$dry_files"

# Verify JSON not modified either
dry_promoted=$(jq '[.[] | select(.promoted == true)] | length' "$TMPDIR/logs/mab-lessons.json" 2>/dev/null || echo "0")
assert_eq "--dry-run does not mark as promoted" "0" "$dry_promoted"

report_results
