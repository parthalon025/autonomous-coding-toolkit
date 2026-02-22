#!/usr/bin/env bash
# Test validate-skills.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

VALIDATOR="$SCRIPT_DIR/../validate-skills.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Helper: create a skill directory with SKILL.md
create_skill() {
    local name="$1" content="$2"
    mkdir -p "$WORK/skills/$name"
    echo "$content" > "$WORK/skills/$name/SKILL.md"
}

# Helper: create a companion file in a skill directory
create_companion() {
    local skill="$1" file="$2"
    echo "# Companion" > "$WORK/skills/$skill/$file"
}

# Helper: run validator against temp skills dir
run_validator() {
    local exit_code=0
    SKILLS_DIR="$WORK/skills" bash "$VALIDATOR" "$@" 2>&1 || exit_code=$?
    echo "EXIT:$exit_code"
}

# === Test: Valid skill passes ===
rm -rf "$WORK/skills"
create_skill "my-skill" '---
name: my-skill
description: "A test skill"
---
Body text here.'

output=$(run_validator)
assert_contains "valid skill: PASS" "validate-skills: PASS" "$output"
assert_contains "valid skill: exit 0" "EXIT:0" "$output"

# === Test: Missing name field fails ===
rm -rf "$WORK/skills"
create_skill "no-name" '---
description: "Missing name"
---
Body.'

output=$(run_validator)
assert_contains "missing name: reports violation" "Missing required field: name" "$output"
assert_contains "missing name: exit 1" "EXIT:1" "$output"

# === Test: Missing description field fails ===
rm -rf "$WORK/skills"
create_skill "no-desc" '---
name: no-desc
---
Body.'

output=$(run_validator)
assert_contains "missing description: reports violation" "Missing required field: description" "$output"
assert_contains "missing description: exit 1" "EXIT:1" "$output"

# === Test: Name mismatch with directory fails ===
rm -rf "$WORK/skills"
create_skill "actual-dir" '---
name: wrong-name
description: "Name does not match directory"
---
Body.'

output=$(run_validator)
assert_contains "name mismatch: reports violation" "name 'wrong-name' does not match directory 'actual-dir'" "$output"
assert_contains "name mismatch: exit 1" "EXIT:1" "$output"

# === Test: Referenced .md file missing fails ===
rm -rf "$WORK/skills"
create_skill "has-ref" '---
name: has-ref
description: "References a companion file"
---
See details in companion-doc.md for more.'

output=$(run_validator)
assert_contains "missing ref: reports violation" "Referenced file not found: companion-doc.md" "$output"
assert_contains "missing ref: exit 1" "EXIT:1" "$output"

# === Test: Referenced .md file exists passes ===
rm -rf "$WORK/skills"
create_skill "has-ref-ok" '---
name: has-ref-ok
description: "References a companion file that exists"
---
See details in companion-doc.md for more.'
create_companion "has-ref-ok" "companion-doc.md"

output=$(run_validator)
assert_contains "existing ref: PASS" "validate-skills: PASS" "$output"
assert_contains "existing ref: exit 0" "EXIT:0" "$output"

# === Test: Missing frontmatter start fails ===
rm -rf "$WORK/skills"
create_skill "no-front" 'name: no-front
description: "No frontmatter markers"'

output=$(run_validator)
assert_contains "missing ---: reports violation" "First line must be '---'" "$output"
assert_contains "missing ---: exit 1" "EXIT:1" "$output"

# === Test: --warn exits 0 even with violations ===
rm -rf "$WORK/skills"
create_skill "warn-test" '---
description: "Missing name"
---
Body.'

output=$(run_validator --warn)
assert_contains "--warn: still reports violation" "Missing required field: name" "$output"
assert_contains "--warn: exits 0" "EXIT:0" "$output"

# === Test: --help exits 0 ===
output=$(run_validator --help)
assert_contains "--help: shows usage" "Usage:" "$output"
assert_contains "--help: exits 0" "EXIT:0" "$output"

# === Test: Missing skills directory fails ===
rm -rf "$WORK/skills"
output=$(SKILLS_DIR="$WORK/nonexistent" bash "$VALIDATOR" 2>&1 || echo "EXIT:$?")
assert_contains "missing dir: error message" "skills directory not found" "$output"
assert_contains "missing dir: exit 1" "EXIT:1" "$output"

report_results
