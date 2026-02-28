#!/usr/bin/env bash
# promote-mab-lessons.sh — Auto-promote MAB patterns with sufficient occurrences to docs/lessons/
#
# Usage: promote-mab-lessons.sh [--worktree <dir>] [--min-occurrences N] [--dry-run] [--help]
set -euo pipefail

WORKTREE="."
MIN_OCCURRENCES=3
DRY_RUN=false

usage() {
    cat <<'USAGE'
promote-mab-lessons.sh — Promote recurring MAB patterns to lesson files

Usage: promote-mab-lessons.sh [--worktree <dir>] [--min-occurrences N] [--dry-run] [--help]

Options:
  --worktree <dir>       Project root (default: .)
  --min-occurrences N    Minimum occurrences to promote (default: 3)
  --dry-run              Show what would be promoted without creating files
  -h, --help             Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --worktree) WORKTREE="$2"; shift 2 ;;
        --min-occurrences) MIN_OCCURRENCES="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

LESSONS_FILE="$WORKTREE/logs/mab-lessons.json"
LESSONS_DIR="$WORKTREE/docs/lessons"

if [[ ! -f "$LESSONS_FILE" ]]; then
    echo "No mab-lessons.json found at $LESSONS_FILE"
    exit 0
fi

# Find next lesson number
next_num() {
    local existing
    existing=$(find "$LESSONS_DIR" -maxdepth 1 -name '*.md' 2>/dev/null \
        | sed 's/.*\///; s/-.*//' \
        | grep -E '^[0-9]+$' \
        | sort -n \
        | tail -1 || echo "0")
    echo $((existing + 1))
}

# Slugify a pattern string
slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-50
}

promoted=0

# Read eligible patterns (not yet promoted, >= threshold)
while IFS= read -r line; do
    pattern=$(echo "$line" | jq -r '.pattern')
    context=$(echo "$line" | jq -r '.context // "general"')
    winner=$(echo "$line" | jq -r '.winner // "unknown"')
    occurrences=$(echo "$line" | jq -r '.occurrences // 0')

    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would promote: \"$pattern\" ($occurrences occurrences, context=$context)"
        promoted=$((promoted + 1))
        continue
    fi

    # Create lesson file
    mkdir -p "$LESSONS_DIR"
    num=$(next_num)
    slug=$(slugify "$pattern")
    filename=$(printf "%04d-%s.md" "$num" "$slug")

    promoted_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # Determine pattern type: if pattern looks like a regex (contains regex metacharacters),
    # treat as syntactic; otherwise semantic with empty regex.
    p_type="semantic"
    p_regex=""
    if echo "$pattern" | grep -qE '[][\\.*+?{}^$|]'; then
        p_type="syntactic"
        p_regex="$pattern"
    fi
    # Use printf to avoid shell expansion of LLM-sourced variables (security)
    printf '%s\n' \
        "---" \
        "id: $num" \
        "title: \"$pattern\"" \
        "severity: should-fix" \
        "languages: [all]" \
        "scope: [universal]" \
        "category: mab-promoted" \
        "pattern:" \
        "  type: $p_type" \
        "  regex: \"$p_regex\"" \
        "source: mab-auto-promoted" \
        "promoted_at: $promoted_at" \
        "context: $context" \
        "winning_strategy: $winner" \
        "occurrences: $occurrences" \
        "---" \
        "" \
        "# $pattern" \
        "" \
        "**Context:** $context batch type" \
        "**Winning strategy:** $winner" \
        "**Occurrences:** $occurrences competing runs" \
        "" \
        "## Description" \
        "" \
        "This pattern was automatically promoted from MAB competing agent runs." \
        "The $winner strategy consistently produced better results when this" \
        "pattern was followed." \
        "" \
        "## Recommendation" \
        "" \
        "Apply this pattern when working on $context batches." \
        > "$LESSONS_DIR/$filename"

    # Enhancement: insert detection pattern into lessons-db if available
    if command -v lessons-db &>/dev/null && [[ -n "$p_regex" ]]; then
        lessons-db rule generate "$num" 2>/dev/null || true
    fi

    echo "  Promoted: $filename"
    promoted=$((promoted + 1))

    # Mark as promoted in JSON
    tmp=$(mktemp)
    jq --arg p "$pattern" \
        '[.[] | if .pattern == $p then .promoted = true else . end]' \
        "$LESSONS_FILE" > "$tmp" && mv "$tmp" "$LESSONS_FILE"

done < <(jq -c --argjson min "$MIN_OCCURRENCES" \
    '.[] | select(.promoted != true and .occurrences >= $min)' \
    "$LESSONS_FILE" 2>/dev/null)

echo ""
echo "Promoted $promoted patterns"
if [[ "$DRY_RUN" == true ]]; then
    echo "(dry run — no files created)"
fi
