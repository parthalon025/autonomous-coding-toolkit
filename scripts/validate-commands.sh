#!/usr/bin/env bash
# validate-commands.sh — Validate command file frontmatter
# Exit 0 if clean, exit 1 if violations found. Use --warn to print but exit 0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="${COMMANDS_DIR:-$SCRIPT_DIR/../commands}"
WARN_ONLY=false
violations=0

usage() {
    echo "Usage: validate-commands.sh [--warn] [--help]"
    echo "  Validates all commands/*.md files"
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

if [[ ! -d "$COMMANDS_DIR" ]]; then
    echo "validate-commands: commands directory not found: $COMMANDS_DIR" >&2
    exit 1
fi

for cmd_file in "$COMMANDS_DIR"/*.md; do
    [[ -f "$cmd_file" ]] || continue
    fname="$(basename "$cmd_file")"

    # Check 1: First line must be ---
    first_line=$(head -1 "$cmd_file")
    if [[ "$first_line" != "---" ]]; then
        report_violation "$fname" 1 "First line must be '---', got '$first_line'"
        continue
    fi

    # Check 2: Second --- delimiter must exist (frontmatter is closed)
    closing_line=$(sed -n '2,$ { /^---$/= }' "$cmd_file" | head -1)
    if [[ -z "$closing_line" ]]; then
        report_violation "$fname" 0 "Frontmatter not closed (missing second '---')"
        continue
    fi

    # Extract frontmatter (between first two --- lines)
    frontmatter=$(sed -n '2,/^---$/{ /^---$/d; p; }' "$cmd_file")

    # Check 3: Required fields
    if ! echo "$frontmatter" | grep -q "^description:"; then
        report_violation "$fname" 0 "Missing required field: description"
    fi
done

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "validate-commands: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
else
    echo "validate-commands: PASS"
    exit 0
fi
