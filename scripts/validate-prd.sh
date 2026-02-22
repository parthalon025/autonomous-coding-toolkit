#!/usr/bin/env bash
# validate-prd.sh — Validate PRD JSON structure and references
# Exit 0 if clean, exit 1 if violations found. Use --warn to print but exit 0.
# Requires: jq
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="${PRD_FILE:-$SCRIPT_DIR/../tasks/prd.json}"
WARN_ONLY=false
violations=0

usage() {
    echo "Usage: validate-prd.sh [--warn] [--help] [file]"
    echo "  Validates PRD JSON file structure"
    echo "  Without arguments, validates tasks/prd.json"
    echo "  --warn   Print violations but exit 0"
    exit 0
}

report_violation() {
    local msg="$1"
    echo "$(basename "$PRD_FILE"): ${msg}"
    ((violations++)) || true
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) usage ;;
        --warn) WARN_ONLY=true; shift ;;
        *) PRD_FILE="$1"; shift ;;
    esac
done

# Check jq is available
if ! command -v jq &>/dev/null; then
    echo "validate-prd: jq is required but not found" >&2
    exit 1
fi

# Check file exists
if [[ ! -f "$PRD_FILE" ]]; then
    echo "validate-prd: PRD file not found: $PRD_FILE" >&2
    exit 1
fi

# Check 1: Valid JSON
if ! jq empty "$PRD_FILE" 2>/dev/null; then
    report_violation "Invalid JSON (jq parse error)"
    echo ""
    echo "validate-prd: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
fi

# Check 2: Must be a JSON array
is_array=$(jq 'type == "array"' "$PRD_FILE")
if [[ "$is_array" != "true" ]]; then
    report_violation "Root must be a JSON array, got $(jq -r 'type' "$PRD_FILE")"
    echo ""
    echo "validate-prd: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
fi

# Collect all valid IDs for reference checking
all_ids=$(jq -r '.[].id // empty' "$PRD_FILE" 2>/dev/null | sort -n)

# Check each element
count=$(jq 'length' "$PRD_FILE")
for ((i = 0; i < count; i++)); do
    idx=$((i + 1))

    # Check 3: id must be a number
    id_type=$(jq -r ".[$i].id | type" "$PRD_FILE")
    id_val=$(jq -r ".[$i].id // empty" "$PRD_FILE")
    if [[ "$id_type" != "number" ]]; then
        report_violation "Task $idx: missing or non-numeric 'id'"
    fi

    # Check 4: title must be a non-empty string
    title=$(jq -r ".[$i].title // empty" "$PRD_FILE")
    if [[ -z "$title" ]]; then
        report_violation "Task $idx (id=$id_val): missing or empty 'title'"
    fi

    # Check 5: acceptance_criteria must be a non-empty array
    ac_type=$(jq -r ".[$i].acceptance_criteria | type" "$PRD_FILE")
    ac_len=$(jq ".[$i].acceptance_criteria | length" "$PRD_FILE" 2>/dev/null || echo 0)
    if [[ "$ac_type" != "array" || "$ac_len" -eq 0 ]]; then
        report_violation "Task $idx (id=$id_val): missing or empty 'acceptance_criteria'"
    fi

    # Check 6: blocked_by references must exist and not self-reference
    if jq -e ".[$i].blocked_by" "$PRD_FILE" >/dev/null 2>&1; then
        blocked_by=$(jq -r ".[$i].blocked_by[]?" "$PRD_FILE" 2>/dev/null || true)
        for ref in $blocked_by; do
            # Self-reference check
            if [[ "$ref" == "$id_val" ]]; then
                report_violation "Task $idx (id=$id_val): blocks itself"
            fi
            # Existence check
            if ! echo "$all_ids" | grep -qx "$ref"; then
                report_violation "Task $idx (id=$id_val): blocked_by references non-existent ID $ref"
            fi
        done
    fi
done

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "validate-prd: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
else
    echo "validate-prd: PASS"
    exit 0
fi
