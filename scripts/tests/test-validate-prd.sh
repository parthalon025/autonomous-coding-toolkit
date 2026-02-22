#!/usr/bin/env bash
# Test validate-prd.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

VALIDATOR="$SCRIPT_DIR/../validate-prd.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Helper: create a PRD file
create_prd() {
    local name="$1" content="$2"
    mkdir -p "$WORK/tasks"
    printf '%s\n' "$content" > "$WORK/tasks/$name"
}

# Helper: run validator against a temp PRD file
run_validator() {
    local exit_code=0
    PRD_FILE="$WORK/tasks/prd.json" bash "$VALIDATOR" "$@" 2>&1 || exit_code=$?
    echo "EXIT:$exit_code"
}

# === Test: Valid PRD passes ===
create_prd "prd.json" '[
  {
    "id": 1,
    "title": "First task",
    "acceptance_criteria": ["test -f foo.txt"],
    "passes": false,
    "blocked_by": []
  },
  {
    "id": 2,
    "title": "Second task",
    "acceptance_criteria": ["test -f bar.txt"],
    "passes": false,
    "blocked_by": [1]
  }
]'

output=$(run_validator)
assert_contains "valid PRD: PASS" "validate-prd: PASS" "$output"
assert_contains "valid PRD: exit 0" "EXIT:0" "$output"

# === Test: Invalid JSON fails ===
create_prd "prd.json" 'this is not json at all {'

output=$(run_validator)
assert_contains "invalid JSON: reports violation" "Invalid JSON" "$output"
assert_contains "invalid JSON: exit 1" "EXIT:1" "$output"

# === Test: Not an array fails ===
create_prd "prd.json" '{"id": 1, "title": "Not an array"}'

output=$(run_validator)
assert_contains "not array: reports violation" "must be a JSON array" "$output"
assert_contains "not array: exit 1" "EXIT:1" "$output"

# === Test: Missing id field fails ===
create_prd "prd.json" '[
  {
    "title": "No ID",
    "acceptance_criteria": ["test -f foo.txt"],
    "blocked_by": []
  }
]'

output=$(run_validator)
assert_contains "missing id: reports violation" "missing or non-numeric 'id'" "$output"
assert_contains "missing id: exit 1" "EXIT:1" "$output"

# === Test: Missing title field fails ===
create_prd "prd.json" '[
  {
    "id": 1,
    "acceptance_criteria": ["test -f foo.txt"],
    "blocked_by": []
  }
]'

output=$(run_validator)
assert_contains "missing title: reports violation" "missing or empty 'title'" "$output"
assert_contains "missing title: exit 1" "EXIT:1" "$output"

# === Test: Missing acceptance_criteria fails ===
create_prd "prd.json" '[
  {
    "id": 1,
    "title": "No criteria",
    "blocked_by": []
  }
]'

output=$(run_validator)
assert_contains "missing criteria: reports violation" "missing or empty 'acceptance_criteria'" "$output"
assert_contains "missing criteria: exit 1" "EXIT:1" "$output"

# === Test: Empty acceptance_criteria fails ===
create_prd "prd.json" '[
  {
    "id": 1,
    "title": "Empty criteria",
    "acceptance_criteria": [],
    "blocked_by": []
  }
]'

output=$(run_validator)
assert_contains "empty criteria: reports violation" "missing or empty 'acceptance_criteria'" "$output"
assert_contains "empty criteria: exit 1" "EXIT:1" "$output"

# === Test: blocked_by references non-existent ID fails ===
create_prd "prd.json" '[
  {
    "id": 1,
    "title": "First",
    "acceptance_criteria": ["true"],
    "blocked_by": []
  },
  {
    "id": 2,
    "title": "Second",
    "acceptance_criteria": ["true"],
    "blocked_by": [99]
  }
]'

output=$(run_validator)
assert_contains "bad blocked_by: reports violation" "references non-existent ID 99" "$output"
assert_contains "bad blocked_by: exit 1" "EXIT:1" "$output"

# === Test: Self-referencing blocked_by fails ===
create_prd "prd.json" '[
  {
    "id": 1,
    "title": "Self-blocking",
    "acceptance_criteria": ["true"],
    "blocked_by": [1]
  }
]'

output=$(run_validator)
assert_contains "self-ref: reports violation" "blocks itself" "$output"
assert_contains "self-ref: exit 1" "EXIT:1" "$output"

# === Test: Single file argument ===
create_prd "custom.json" '[
  {
    "id": 1,
    "title": "Custom file",
    "acceptance_criteria": ["true"],
    "blocked_by": []
  }
]'

exit_code=0
output=$(bash "$VALIDATOR" "$WORK/tasks/custom.json" 2>&1) || exit_code=$?
output="${output}
EXIT:${exit_code}"
assert_contains "single file arg: PASS" "validate-prd: PASS" "$output"
assert_contains "single file arg: exit 0" "EXIT:0" "$output"

# === Test: --warn exits 0 even with violations ===
create_prd "prd.json" 'not json'

output=$(run_validator --warn)
assert_contains "--warn: still reports violation" "Invalid JSON" "$output"
assert_contains "--warn: exits 0" "EXIT:0" "$output"

# === Test: --help exits 0 ===
output=$(run_validator --help)
assert_contains "--help: shows usage" "Usage:" "$output"
assert_contains "--help: exits 0" "EXIT:0" "$output"

# === Test: Missing PRD file fails ===
rm -f "$WORK/tasks/prd.json"
output=$(PRD_FILE="$WORK/tasks/nonexistent.json" bash "$VALIDATOR" 2>&1 || echo "EXIT:$?")
assert_contains "missing file: error message" "PRD file not found" "$output"
assert_contains "missing file: exit 1" "EXIT:1" "$output"

report_results
