#!/usr/bin/env bash
# validate-skills.sh — Validate skill directory structure and SKILL.md frontmatter
# Exit 0 if clean, exit 1 if violations found. Use --warn to print but exit 0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${SKILLS_DIR:-$SCRIPT_DIR/../skills}"
WARN_ONLY=false
violations=0

usage() {
    echo "Usage: validate-skills.sh [--warn] [--help]"
    echo "  Validates all skills/*/SKILL.md files"
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

if [[ ! -d "$SKILLS_DIR" ]]; then
    echo "validate-skills: skills directory not found: $SKILLS_DIR" >&2
    exit 1
fi

for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue
    dir_name="$(basename "$skill_dir")"
    skill_file="$skill_dir/SKILL.md"

    if [[ ! -f "$skill_file" ]]; then
        report_violation "$dir_name" 0 "Missing SKILL.md"
        continue
    fi

    # Check 1: First line must be ---
    first_line=$(head -1 "$skill_file")
    if [[ "$first_line" != "---" ]]; then
        report_violation "$dir_name/SKILL.md" 1 "First line must be '---', got '$first_line'"
        continue
    fi

    # Extract frontmatter (between first two --- lines)
    frontmatter=$(sed -n '2,/^---$/{ /^---$/d; p; }' "$skill_file")

    # Check 2: Required fields
    for field in name description; do
        if ! echo "$frontmatter" | grep -q "^${field}:"; then
            report_violation "$dir_name/SKILL.md" 0 "Missing required field: $field"
        fi
    done

    # Check 3: name must match directory name
    skill_name=$(echo "$frontmatter" | sed -n 's/^name:[[:space:]]*\(.*\)/\1/p' | tr -d ' "'"'"'')
    if [[ -n "$skill_name" && "$skill_name" != "$dir_name" ]]; then
        report_violation "$dir_name/SKILL.md" 0 "name '$skill_name' does not match directory '$dir_name'"
    fi

    # Check 4: Referenced .md files in body must exist
    # Body starts after the second ---
    body=$(sed -n '/^---$/,$ p' "$skill_file" | tail -n +2)
    body=$(echo "$body" | sed -n '/^---$/,$ p' | tail -n +2)
    if [[ -n "$body" ]]; then
        # Strip fenced code blocks and inline backtick-delimited content
        # (paths like `docs/plans/foo.md`) — only bare .md refs are companion files
        cleaned=$(echo "$body" | sed '/^```/,/^```/d' | sed 's/`[^`]*`//g')
        referenced=$(echo "$cleaned" | grep -oE '[a-zA-Z0-9_-]+\.md' | sort -u || true)
        for ref in $referenced; do
            [[ "$ref" == "SKILL.md" ]] && continue
            if [[ ! -f "$skill_dir/$ref" ]]; then
                report_violation "$dir_name/SKILL.md" 0 "Referenced file not found: $ref"
            fi
        done
    fi
done

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "validate-skills: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
else
    echo "validate-skills: PASS"
    exit 0
fi
