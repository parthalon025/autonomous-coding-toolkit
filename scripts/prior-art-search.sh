#!/usr/bin/env bash
# prior-art-search.sh — Search GitHub and local codebase for prior art
#
# Usage: prior-art-search.sh [--dry-run] [--local-only] [--github-only] <query>
#
# Searches:
#   1. GitHub repos (gh search repos)
#   2. GitHub code (gh search code)
#   3. Local ~/Documents/projects/ (grep -r)
#
# Output: Ranked results with source, relevance, and URL/path
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=false
LOCAL_ONLY=false
GITHUB_ONLY=false
QUERY=""
MAX_RESULTS=10
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Documents/projects}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --local-only) LOCAL_ONLY=true; shift ;;
        --github-only) GITHUB_ONLY=true; shift ;;
        --max-results) MAX_RESULTS="$2"; shift 2 ;;
        --projects-dir) PROJECTS_DIR="$2"; shift 2 ;;
        -h|--help)
            cat <<'USAGE'
prior-art-search.sh — Search for prior art before building

Usage: prior-art-search.sh [OPTIONS] <query>

Options:
  --dry-run          Show what would be searched without executing
  --local-only       Only search local projects
  --github-only      Only search GitHub
  --max-results N    Max results per source (default: 10)
  --projects-dir P   Local projects directory

Output: Results ranked by relevance with source attribution
USAGE
            exit 0
            ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) QUERY="$1"; shift ;;
    esac
done

if [[ -z "$QUERY" ]]; then
    echo "Error: Query required" >&2
    echo "Usage: prior-art-search.sh <query>" >&2
    exit 1
fi

echo "=== Prior Art Search ==="
echo "Search query: $QUERY"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] Would search:"
    [[ "$LOCAL_ONLY" != true ]] && echo "  - GitHub repos: gh search repos '$QUERY' --limit $MAX_RESULTS"
    [[ "$LOCAL_ONLY" != true ]] && echo "  - GitHub code: gh search code '$QUERY' --limit $MAX_RESULTS"
    [[ "$GITHUB_ONLY" != true ]] && echo "  - Local projects: grep -rl in $PROJECTS_DIR"
    if command -v ast-grep >/dev/null 2>&1; then
        echo "  - Structural code search (ast-grep): scan with built-in patterns"
    else
        echo "  - Structural code search (ast-grep): not installed — would skip"
    fi
    exit 0
fi

# Search 1: GitHub repos
if [[ "$LOCAL_ONLY" != true ]]; then
    echo "--- GitHub Repos ---"
    if command -v gh >/dev/null 2>&1; then
        gh search repos "$QUERY" --limit "$MAX_RESULTS" --json name,url,description,stargazersCount \
            --jq '.[] | "★ \(.stargazersCount) | \(.name) — \(.description // "no description") | \(.url)"' \
            2>/dev/null || echo "  (GitHub search unavailable)"
    else
        echo "  gh CLI not installed — skipping"
    fi
    echo ""

    echo "--- GitHub Code ---"
    if command -v gh >/dev/null 2>&1; then
        gh search code "$QUERY" --limit "$MAX_RESULTS" --json repository,path \
            --jq '.[] | "\(.repository.nameWithOwner)/\(.path)"' \
            2>/dev/null || echo "  (GitHub code search unavailable)"
    else
        echo "  gh CLI not installed — skipping"
    fi
    echo ""
fi

# Search 2: Local projects
if [[ "$GITHUB_ONLY" != true ]]; then
    echo "--- Local Projects ---"
    if [[ -d "$PROJECTS_DIR" ]]; then
        grep -rl --include='*.py' --include='*.sh' --include='*.ts' --include='*.js' \
            "$QUERY" "$PROJECTS_DIR" 2>/dev/null | head -"$MAX_RESULTS" || echo "  No local matches"
    else
        echo "  Projects directory not found: $PROJECTS_DIR"
    fi
    echo ""
fi

# Search 3: Structural code search (ast-grep)
if command -v ast-grep >/dev/null 2>&1; then
    echo "--- Structural Code Search (ast-grep) ---"
    PATTERNS_DIR="$SCRIPT_DIR/patterns"
    if [[ -d "$PATTERNS_DIR" ]]; then
        for pattern_file in "$PATTERNS_DIR"/*.yml; do
            [[ -f "$pattern_file" ]] || continue
            pattern_name=$(basename "$pattern_file" .yml)
            matches=$(ast-grep scan --rule "$pattern_file" . 2>/dev/null | head -5 || true)
            if [[ -n "$matches" ]]; then
                echo "  Pattern '$pattern_name': $(echo "$matches" | wc -l) matches"
            fi
        done
    fi
    echo ""
else
    echo "--- Structural Code Search ---"
    echo "  ast-grep not installed — skipping structural analysis"
    echo "  Install: npm i -g @ast-grep/cli"
    echo ""
fi

echo "=== Search Complete ==="
