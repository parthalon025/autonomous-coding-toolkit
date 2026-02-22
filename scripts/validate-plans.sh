#!/usr/bin/env bash
# validate-plans.sh — Validate implementation plan structure
# Exit 0 if clean, exit 1 if violations found. Use --warn to print but exit 0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLANS_DIR="${PLANS_DIR:-$SCRIPT_DIR/../docs/plans}"
WARN_ONLY=false
EXPLICIT_FILES=false
violations=0
FILES=()

usage() {
    echo "Usage: validate-plans.sh [--warn] [--help] [file ...]"
    echo "  Validates plan files (files with ## Batch headers)"
    echo "  Without arguments, scans docs/plans/*.md"
    echo "  --warn   Print violations but exit 0"
    exit 0
}

report_violation() {
    local file="$1" msg="$2"
    echo "${file}: ${msg}"
    ((violations++)) || true
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) usage ;;
        --warn) WARN_ONLY=true; shift ;;
        *) FILES+=("$1"); EXPLICIT_FILES=true; shift ;;
    esac
done

# If no files given, scan PLANS_DIR
if [[ ${#FILES[@]} -eq 0 ]]; then
    if [[ ! -d "$PLANS_DIR" ]]; then
        echo "validate-plans: plans directory not found: $PLANS_DIR" >&2
        exit 1
    fi
    for f in "$PLANS_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        FILES+=("$f")
    done
fi

validated=0

for plan in "${FILES[@]}"; do
    [[ -f "$plan" ]] || continue
    fname="$(basename "$plan")"

    # Skip files without any Batch headers (design docs) — but only in scan mode
    if ! grep -q '^## Batch [0-9]' "$plan"; then
        if [[ "$EXPLICIT_FILES" == true ]]; then
            report_violation "$fname" "No batches found (missing '## Batch N:' headers)"
        fi
        continue
    fi

    validated=$((validated + 1))

    # Extract batch numbers and line numbers
    batch_numbers=()
    batch_lines=()
    while IFS=: read -r line_num line_content; do
        num=$(echo "$line_content" | sed -n 's/^## Batch \([0-9][0-9]*\).*/\1/p')
        if [[ -n "$num" ]]; then
            batch_numbers+=("$num")
            batch_lines+=("$line_num")
        fi
    done < <(grep -n '^## Batch [0-9]' "$plan")

    # Check: at least one batch
    if [[ ${#batch_numbers[@]} -eq 0 ]]; then
        report_violation "$fname" "No batches found"
        continue
    fi

    # Check: sequential batch numbers starting from 1
    expected=1
    for num in "${batch_numbers[@]}"; do
        if [[ "$num" -ne "$expected" ]]; then
            report_violation "$fname" "Non-sequential batch numbering: found Batch $num, expected Batch $expected"
            break
        fi
        expected=$((expected + 1))
    done

    # Check: each batch has at least one task
    total_lines=$(wc -l < "$plan")
    for i in "${!batch_numbers[@]}"; do
        batch_num="${batch_numbers[$i]}"
        start_line="${batch_lines[$i]}"

        # End is next batch start or EOF
        if [[ $((i + 1)) -lt ${#batch_lines[@]} ]]; then
            end_line="${batch_lines[$((i + 1))]}"
        else
            end_line=$((total_lines + 1))
        fi

        # Check for ### Task headers between start and end
        task_count=$(sed -n "${start_line},${end_line}p" "$plan" | grep -c '^### Task ' || true)
        if [[ "$task_count" -eq 0 ]]; then
            report_violation "$fname" "Batch $batch_num has no tasks"
        fi
    done
done

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "validate-plans: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
else
    echo "validate-plans: PASS"
    exit 0
fi
