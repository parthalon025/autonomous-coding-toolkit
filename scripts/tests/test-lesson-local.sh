#!/usr/bin/env bash
# Test lesson-check.sh — project-local lesson loading (Tier 3)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LESSON_CHECK="$REPO_ROOT/scripts/lesson-check.sh"

source "$SCRIPT_DIR/test-helpers.sh"

# --- Setup: project with local lessons ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Create a project-local lesson
mkdir -p "$WORK/docs/lessons"
cat > "$WORK/docs/lessons/9901-local-test.md" <<'LESSON'
---
id: 9901
title: "Test local lesson"
severity: error
languages: [python]
scope: [universal]
category: testing
pattern:
  type: syntactic
  regex: "LOCALTEST_BAD_PATTERN"
fix: "Use LOCALTEST_GOOD_PATTERN instead"
positive_alternative: "LOCALTEST_GOOD_PATTERN"
---
LESSON

# Create a file that triggers the local lesson
cat > "$WORK/bad.py" <<'PY'
x = LOCALTEST_BAD_PATTERN
PY

# --- Test: project-local lesson is loaded ---
output=$(PROJECT_ROOT="$WORK" PROJECT_CLAUDE_MD="/dev/null" bash "$LESSON_CHECK" "$WORK/bad.py" 2>&1 || true)
if echo "$output" | grep -q 'lesson-9901'; then
    pass "Project-local lesson detected violation"
else
    fail "Project-local lesson not loaded, got: $output"
fi

# --- Test: clean file passes with local lessons ---
cat > "$WORK/good.py" <<'PY'
x = LOCALTEST_GOOD_PATTERN
PY

exit_code=0
PROJECT_ROOT="$WORK" PROJECT_CLAUDE_MD="/dev/null" bash "$LESSON_CHECK" "$WORK/good.py" 2>/dev/null || exit_code=$?
assert_eq "Clean file passes with local lessons" "0" "$exit_code"

report_results
