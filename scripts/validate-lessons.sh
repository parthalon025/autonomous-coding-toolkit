#!/usr/bin/env bash
# validate-lessons.sh — Validate lesson file format and frontmatter
# Exit 0 if clean, exit 1 if violations found. Use --warn to print but exit 0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LESSONS_DIR="${LESSONS_DIR:-$SCRIPT_DIR/../docs/lessons}"
WARN_ONLY=false
violations=0

usage() {
    echo "Usage: validate-lessons.sh [--warn] [--help]"
    echo "  Validates all lesson files in docs/lessons/"
    echo "  --warn   Print violations but exit 0"
    exit 0
}

report_violation() {
    local file="$1" line="$2" msg="$3"
    echo "${file}:${line}: ${msg}"
    ((violations++)) || true
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage
[[ "${1:-}" == "--warn" ]] && WARN_ONLY=true

if [[ ! -d "$LESSONS_DIR" ]]; then
    echo "validate-lessons: lessons directory not found: $LESSONS_DIR" >&2
    exit 1
fi

seen_ids=()

for lesson in "$LESSONS_DIR"/[0-9]*.md; do
    [[ -f "$lesson" ]] || continue
    fname="$(basename "$lesson")"

    # Check 1: First line must be ---
    first_line=$(head -1 "$lesson")
    if [[ "$first_line" != "---" ]]; then
        report_violation "$fname" 1 "First line must be '---', got '$first_line' (code block wrapping?)"
        continue  # Can't parse frontmatter if start is wrong
    fi

    # Extract frontmatter (between first two --- lines)
    frontmatter=$(sed -n '2,/^---$/{ /^---$/d; p; }' "$lesson")

    # Check 2: Required fields
    for field in id title severity languages; do
        if ! echo "$frontmatter" | grep -q "^${field}:"; then
            report_violation "$fname" 0 "Missing required field: $field"
        fi
    done

    # Check 3: pattern.type must exist
    if ! echo "$frontmatter" | grep -q "type:"; then
        report_violation "$fname" 0 "Missing pattern.type field"
    fi

    # Check 4: Extract and validate ID
    lesson_id=$(echo "$frontmatter" | sed -n 's/^id:[[:space:]]*\(.*\)/\1/p' | tr -d ' "'"'"'')
    if [[ -n "$lesson_id" ]]; then
        # Check for duplicate IDs
        for seen in "${seen_ids[@]+"${seen_ids[@]}"}"; do
            if [[ "$seen" == "$lesson_id" ]]; then
                report_violation "$fname" 0 "Duplicate lesson ID: $lesson_id"
            fi
        done
        seen_ids+=("$lesson_id")
    fi

    # Check 5: Severity must be valid
    severity=$(echo "$frontmatter" | sed -n 's/^severity:[[:space:]]*\(.*\)/\1/p' | tr -d ' ')
    if [[ -n "$severity" ]]; then
        case "$severity" in
            blocker|should-fix|nice-to-have) ;;
            *) report_violation "$fname" 0 "Invalid severity '$severity' (must be blocker|should-fix|nice-to-have)" ;;
        esac
    fi

    # Check 6: Syntactic lessons must have regex
    pattern_type=$(echo "$frontmatter" | grep "type:" | tail -1 | sed 's/.*type:[[:space:]]*//' | tr -d ' ')
    if [[ "$pattern_type" == "syntactic" ]]; then
        if ! echo "$frontmatter" | grep -q "regex:"; then
            report_violation "$fname" 0 "Syntactic lesson missing regex field"
        fi
    fi
done

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "validate-lessons: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
else
    echo "validate-lessons: PASS"
    exit 0
fi
