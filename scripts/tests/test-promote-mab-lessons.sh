#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PROMOTE="$SCRIPT_DIR/../promote-mab-lessons.sh"

# --- Setup ---
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/docs/lessons"

# --- Test: --help exits 0 ---
assert_exit "--help exits 0" 0 "$PROMOTE" --help

# --- Test: no promotions when all below threshold ---
cat > "$TEST_TMPDIR/logs/mab-lessons.json" <<'JSON'
[
  {"pattern": "rare pattern", "context": "new-file", "winner": "superpowers", "occurrences": 1, "promoted": false},
  {"pattern": "another rare", "context": "refactoring", "winner": "ralph", "occurrences": 2, "promoted": false}
]
JSON

output=$("$PROMOTE" --worktree "$TEST_TMPDIR" --min-occurrences 3 2>&1) || true
lesson_count=$(find "$TEST_TMPDIR/docs/lessons" -name "*.md" -newer "$TEST_TMPDIR/logs/mab-lessons.json" 2>/dev/null | wc -l)
assert_eq "no promotions below threshold" "0" "$lesson_count"

# --- Test: promotes at 3+ occurrences ---
cat > "$TEST_TMPDIR/logs/mab-lessons.json" <<'JSON'
[
  {"pattern": "check imports before tests", "context": "integration", "winner": "superpowers", "occurrences": 5, "promoted": false},
  {"pattern": "rare pattern", "context": "new-file", "winner": "ralph", "occurrences": 1, "promoted": false}
]
JSON

"$PROMOTE" --worktree "$TEST_TMPDIR" --min-occurrences 3 > /dev/null 2>&1 || true

# Check a lesson file was created
promoted_files=$(find "$TEST_TMPDIR/docs/lessons" -name "*.md" 2>/dev/null)
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
promoted_count=$(jq '[.[] | select(.promoted == true)] | length' "$TEST_TMPDIR/logs/mab-lessons.json" 2>/dev/null || echo "0")
assert_eq "promoted lesson marked in JSON" "1" "$promoted_count"

# --- Test: --dry-run creates no files ---
# Reset
rm -f "$TEST_TMPDIR/docs/lessons"/*.md
cat > "$TEST_TMPDIR/logs/mab-lessons.json" <<'JSON'
[
  {"pattern": "should not create file", "context": "test-only", "winner": "ralph", "occurrences": 10, "promoted": false}
]
JSON

"$PROMOTE" --worktree "$TEST_TMPDIR" --min-occurrences 3 --dry-run > /dev/null 2>&1 || true
dry_files=$(find "$TEST_TMPDIR/docs/lessons" -name "*.md" 2>/dev/null | wc -l)
assert_eq "--dry-run creates no files" "0" "$dry_files"

# Verify JSON not modified either
dry_promoted=$(jq '[.[] | select(.promoted == true)] | length' "$TEST_TMPDIR/logs/mab-lessons.json" 2>/dev/null || echo "0")
assert_eq "--dry-run does not mark as promoted" "0" "$dry_promoted"

# --- Test: idempotency — second promotion creates no new files ---
# Reset directory
rm -f "$TEST_TMPDIR/docs/lessons"/*.md

cat > "$TEST_TMPDIR/logs/mab-lessons.json" <<'JSON'
[
  {"pattern": "idempotent test pattern", "context": "new-file", "winner": "superpowers", "occurrences": 5, "promoted": false}
]
JSON

# First run — should create lesson file and mark as promoted
"$PROMOTE" --worktree "$TEST_TMPDIR" --min-occurrences 3 > /dev/null 2>&1 || true
first_count=$(find "$TEST_TMPDIR/docs/lessons" -name "*.md" 2>/dev/null | wc -l)
first_promoted=$(jq '[.[] | select(.promoted == true)] | length' "$TEST_TMPDIR/logs/mab-lessons.json" 2>/dev/null || echo "0")

TESTS=$((TESTS + 1))
if [[ "$first_count" -ge 1 && "$first_promoted" == "1" ]]; then
    echo "PASS: idempotency: first run creates file and marks promoted"
else
    echo "FAIL: idempotency: first run should create file ($first_count) and mark promoted ($first_promoted)"
    FAILURES=$((FAILURES + 1))
fi

# Second run — promoted=true guard should prevent new files
"$PROMOTE" --worktree "$TEST_TMPDIR" --min-occurrences 3 > /dev/null 2>&1 || true
second_count=$(find "$TEST_TMPDIR/docs/lessons" -name "*.md" 2>/dev/null | wc -l)

assert_eq "idempotency: second run creates no additional files" "$first_count" "$second_count"

# --- Test: promoted YAML has all fields required by parse_lesson() ---
PARSE_TMPDIR=$(mktemp -d)
mkdir -p "$PARSE_TMPDIR/logs" "$PARSE_TMPDIR/docs/lessons"

cat > "$PARSE_TMPDIR/logs/mab-lessons.json" <<'JSON'
[
  {"pattern": "always check return \\w+ values", "context": "integration", "winner": "superpowers", "occurrences": 4, "promoted": false}
]
JSON

"$PROMOTE" --worktree "$PARSE_TMPDIR" --min-occurrences 3 > /dev/null 2>&1 || true

promoted_file=$(find "$PARSE_TMPDIR/docs/lessons" -name "*.md" 2>/dev/null | head -1)
TESTS=$((TESTS + 1))
if [[ -z "$promoted_file" ]]; then
    echo "FAIL: promoted YAML parse test: no file created"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: promoted file created for parse test"

    # Check all required YAML fields exist in the frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$promoted_file" | tail -n +2 | head -n -1)

    for field in "id:" "title:" "severity:" "languages:" "scope:" "category:" "source:" "type:" "regex:"; do
        TESTS=$((TESTS + 1))
        if echo "$frontmatter" | grep -q "$field"; then
            echo "PASS: promoted YAML contains $field"
        else
            echo "FAIL: promoted YAML missing $field"
            echo "  frontmatter: $frontmatter"
            FAILURES=$((FAILURES + 1))
        fi
    done

    # Verify the pattern with regex metacharacters was classified as syntactic
    TESTS=$((TESTS + 1))
    if echo "$frontmatter" | grep -q "type: syntactic"; then
        echo "PASS: regex-like pattern classified as syntactic"
    else
        echo "FAIL: regex-like pattern should be classified as syntactic"
        FAILURES=$((FAILURES + 1))
    fi

    # Verify parse_lesson() can actually parse the promoted file
    LESSON_CHECK_SCRIPT="$SCRIPT_DIR/../lesson-check.sh"
    # Source just the parse_lesson function
    source <(sed -n '/^parse_lesson()/,/^}/p' "$LESSON_CHECK_SCRIPT")
    TESTS=$((TESTS + 1))
    if parse_lesson "$promoted_file"; then
        echo "PASS: parse_lesson() successfully parses promoted file"
        # Verify key fields were populated
        TESTS=$((TESTS + 1))
        if [[ -n "$lesson_id" && -n "$lesson_title" && -n "$pattern_regex" ]]; then
            echo "PASS: parse_lesson() populated id=$lesson_id, title=$lesson_title"
        else
            echo "FAIL: parse_lesson() missing fields: id='$lesson_id' title='$lesson_title' regex='$pattern_regex'"
            FAILURES=$((FAILURES + 1))
        fi
    else
        echo "FAIL: parse_lesson() returned non-zero for promoted file"
        FAILURES=$((FAILURES + 1))
    fi
fi
rm -rf "$PARSE_TMPDIR"

# --- Test: behavioral pattern promoted as semantic (no regex metacharacters) ---
SEM_TMPDIR=$(mktemp -d)
mkdir -p "$SEM_TMPDIR/logs" "$SEM_TMPDIR/docs/lessons"

cat > "$SEM_TMPDIR/logs/mab-lessons.json" <<'JSON'
[
  {"pattern": "check imports before tests", "context": "integration", "winner": "superpowers", "occurrences": 5, "promoted": false}
]
JSON

"$PROMOTE" --worktree "$SEM_TMPDIR" --min-occurrences 3 > /dev/null 2>&1 || true

sem_file=$(find "$SEM_TMPDIR/docs/lessons" -name "*.md" 2>/dev/null | head -1)
TESTS=$((TESTS + 1))
if [[ -n "$sem_file" ]]; then
    sem_frontmatter=$(sed -n '/^---$/,/^---$/p' "$sem_file" | tail -n +2 | head -n -1)
    if echo "$sem_frontmatter" | grep -q "type: semantic"; then
        echo "PASS: behavioral pattern classified as semantic"
    else
        echo "FAIL: behavioral pattern should be classified as semantic"
        echo "  frontmatter: $sem_frontmatter"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo "FAIL: no file created for semantic pattern test"
    FAILURES=$((FAILURES + 1))
fi
rm -rf "$SEM_TMPDIR"

report_results
