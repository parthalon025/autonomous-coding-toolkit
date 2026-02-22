#!/usr/bin/env bash
# Test validate-lessons.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

VALIDATOR="$SCRIPT_DIR/../validate-lessons.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Helper: create a lesson file in the temp lessons dir
create_lesson() {
    local name="$1" content="$2"
    local dir="$WORK/lessons"
    mkdir -p "$dir"
    echo "$content" > "$dir/$name"
}

# Helper: run validator against temp lessons dir
run_validator() {
    local exit_code=0
    LESSONS_DIR="$WORK/lessons" bash "$VALIDATOR" "$@" 2>&1 || exit_code=$?
    echo "EXIT:$exit_code"
}

# === Test: Valid lesson passes ===
rm -rf "$WORK/lessons"
create_lesson "0001-test.md" '---
id: 1
title: "Test lesson"
severity: blocker
languages: [python]
pattern:
  type: syntactic
  regex: "foo"
---
Body text here.'

output=$(run_validator)
assert_contains "valid lesson: PASS" "validate-lessons: PASS" "$output"
assert_contains "valid lesson: exit 0" "EXIT:0" "$output"

# === Test: Missing --- start line fails ===
rm -rf "$WORK/lessons"
create_lesson "0002-bad-start.md" 'id: 1
title: "No frontmatter marker"
severity: blocker
languages: [python]
---'

output=$(run_validator)
assert_contains "missing ---: reports violation" "First line must be" "$output"
assert_contains "missing ---: FAIL" "FAIL" "$output"
assert_contains "missing ---: exit 1" "EXIT:1" "$output"

# === Test: Missing required field fails ===
rm -rf "$WORK/lessons"
create_lesson "0003-missing-field.md" '---
id: 3
severity: blocker
languages: [python]
pattern:
  type: semantic
---'

output=$(run_validator)
assert_contains "missing title: reports violation" "Missing required field: title" "$output"
assert_contains "missing title: exit 1" "EXIT:1" "$output"

# === Test: Duplicate IDs fail ===
rm -rf "$WORK/lessons"
create_lesson "0004-dup-a.md" '---
id: 42
title: "First"
severity: blocker
languages: [python]
pattern:
  type: semantic
---'
create_lesson "0005-dup-b.md" '---
id: 42
title: "Second"
severity: blocker
languages: [python]
pattern:
  type: semantic
---'

output=$(run_validator)
assert_contains "duplicate IDs: reports violation" "Duplicate lesson ID: 42" "$output"
assert_contains "duplicate IDs: exit 1" "EXIT:1" "$output"

# === Test: Invalid severity fails ===
rm -rf "$WORK/lessons"
create_lesson "0006-bad-severity.md" '---
id: 6
title: "Bad severity"
severity: critical
languages: [python]
pattern:
  type: semantic
---'

output=$(run_validator)
assert_contains "invalid severity: reports violation" "Invalid severity" "$output"
assert_contains "invalid severity: exit 1" "EXIT:1" "$output"

# === Test: Syntactic without regex fails ===
rm -rf "$WORK/lessons"
create_lesson "0007-no-regex.md" '---
id: 7
title: "Missing regex"
severity: blocker
languages: [python]
pattern:
  type: syntactic
---'

output=$(run_validator)
assert_contains "syntactic no regex: reports violation" "Syntactic lesson missing regex field" "$output"
assert_contains "syntactic no regex: exit 1" "EXIT:1" "$output"

# === Test: --warn exits 0 even with violations ===
rm -rf "$WORK/lessons"
create_lesson "0008-warn-test.md" '---
id: 8
severity: blocker
languages: [python]
pattern:
  type: semantic
---'

output=$(run_validator --warn)
assert_contains "--warn: still reports violation" "Missing required field: title" "$output"
assert_contains "--warn: exits 0" "EXIT:0" "$output"

# === Test: --help exits 0 ===
output=$(run_validator --help)
assert_contains "--help: shows usage" "Usage:" "$output"
assert_contains "--help: exits 0" "EXIT:0" "$output"

# === Test: Missing lessons directory fails ===
SAVE_DIR="$WORK/lessons"
rm -rf "$WORK/lessons"
output=$(LESSONS_DIR="$WORK/nonexistent" bash "$VALIDATOR" 2>&1 || echo "EXIT:$?")
assert_contains "missing dir: error message" "lessons directory not found" "$output"
assert_contains "missing dir: exit 1" "EXIT:1" "$output"

report_results
