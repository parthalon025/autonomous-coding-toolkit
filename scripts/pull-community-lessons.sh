#!/usr/bin/env bash
# pull-community-lessons.sh — Fetch lessons + strategy data from upstream remote
#
# Usage: pull-community-lessons.sh [--remote <name>] [--dry-run] [--help]
set -euo pipefail

REMOTE="upstream"
DRY_RUN=false

usage() {
    cat <<'USAGE'
pull-community-lessons.sh — Fetch community lessons and strategy data from upstream

Usage: pull-community-lessons.sh [--remote <name>] [--dry-run] [--help]

Options:
  --remote <name>   Git remote name (default: upstream)
  --dry-run         Show what would be fetched without changing anything
  -h, --help        Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --remote) REMOTE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Verify remote exists
if ! git remote get-url "$REMOTE" > /dev/null 2>&1; then
    echo "ERROR: Remote '$REMOTE' not found." >&2
    echo "Add it with: git remote add $REMOTE <url>" >&2
    exit 1
fi

echo "Fetching from $REMOTE..."
git fetch "$REMOTE" main 2>/dev/null || {
    echo "ERROR: Failed to fetch from $REMOTE" >&2
    exit 1
}

# Count new lessons
new_count=0
while IFS= read -r remote_lesson; do
    local_path="docs/lessons/$(basename "$remote_lesson")"
    if [[ ! -f "$local_path" ]]; then
        new_count=$((new_count + 1))
        if [[ "$DRY_RUN" == true ]]; then
            echo "  Would copy: $(basename "$remote_lesson")"
        else
            git show "$REMOTE/main:$remote_lesson" > "$local_path" 2>/dev/null || true
        fi
    fi
done < <(git ls-tree -r --name-only "$REMOTE/main" -- docs/lessons/ 2>/dev/null | grep '\.md$' || true)

# Merge strategy-perf.json additively
local_perf="logs/strategy-perf.json"
if git show "$REMOTE/main:logs/strategy-perf.json" > /dev/null 2>&1; then
    if [[ -f "$local_perf" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "  Would merge strategy-perf.json (local wins + upstream wins)"
        else
            local_data=$(cat "$local_perf")
            remote_data=$(git show "$REMOTE/main:logs/strategy-perf.json" 2>/dev/null)

            # Merge: take max(local, upstream) per counter — idempotent on repeated pulls
            tmp=$(mktemp)
            echo "$local_data" | jq --argjson remote "$remote_data" '
                def max(a; b): if a > b then a else b end;
                . as $local |
                ["new-file", "refactoring", "integration", "test-only"] | reduce .[] as $bt ($local;
                    .[$bt].superpowers.wins = max(.[$bt].superpowers.wins; $remote[$bt].superpowers.wins // 0) |
                    .[$bt].superpowers.losses = max(.[$bt].superpowers.losses; $remote[$bt].superpowers.losses // 0) |
                    .[$bt].ralph.wins = max(.[$bt].ralph.wins; $remote[$bt].ralph.wins // 0) |
                    .[$bt].ralph.losses = max(.[$bt].ralph.losses; $remote[$bt].ralph.losses // 0)
                )
            ' > "$tmp" && mv "$tmp" "$local_perf"
            echo "  Merged strategy-perf.json"
        fi
    fi
fi

echo ""
echo "Pull complete: $new_count new lessons"
if [[ "$DRY_RUN" == true ]]; then
    echo "(dry run — no changes made)"
fi
