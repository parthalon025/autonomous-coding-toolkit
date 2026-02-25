#!/usr/bin/env bash
# module-size-check.sh — Enforce module size limits across the toolkit
#
# Usage:
#   module-size-check.sh [options] [path...]
#
# Options:
#   --max-lines N      Maximum allowed lines per file (default: 300)
#   --exclude PATTERN  Glob pattern to exclude (repeatable)
#   --json             Output as JSON (for quality-gate integration)
#   --fix-suggestions  Include suggested split strategies in output
#   --warn-at N        Warn (don't fail) for files between warn-at and max-lines
#   --project-root DIR Project root (default: git root or cwd)
#
# If no paths given, scans scripts/**/*.sh (excluding tests/).
#
# Exit codes:
#   0 — all files within limit
#   1 — one or more files exceed limit
#   2 — usage error
set -euo pipefail

MAX_LINES=300
WARN_AT=250
EXCLUDES=()
JSON=false
FIX_SUGGESTIONS=false
PROJECT_ROOT=""
PATHS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-lines) MAX_LINES="$2"; shift 2 ;;
        --exclude) EXCLUDES+=("$2"); shift 2 ;;
        --json) JSON=true; shift ;;
        --fix-suggestions) FIX_SUGGESTIONS=true; shift ;;
        --warn-at) WARN_AT="$2"; shift 2 ;;
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --help|-h)
            head -20 "$0" | tail -18
            exit 0
            ;;
        -*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) PATHS+=("$1"); shift ;;
    esac
done

# Resolve project root
if [[ -z "$PROJECT_ROOT" ]]; then
    PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

# Default scan paths
if [[ ${#PATHS[@]} -eq 0 ]]; then
    PATHS=("$PROJECT_ROOT/scripts")
fi

# Collect files
files=()
for path in "${PATHS[@]}"; do
    if [[ -f "$path" ]]; then
        files+=("$path")
    elif [[ -d "$path" ]]; then
        while IFS= read -r f; do
            files+=("$f")
        done < <(find "$path" -name '*.sh' -not -path '*/tests/*' -not -path '*/.git/*' | sort)
    fi
done

# Apply excludes
if [[ ${#EXCLUDES[@]} -gt 0 ]]; then
    filtered=()
    for f in "${files[@]}"; do
        skip=false
        for pattern in "${EXCLUDES[@]}"; do
            if [[ "$f" == *"$pattern"* ]]; then
                skip=true
                break
            fi
        done
        [[ "$skip" == false ]] && filtered+=("$f")
    done
    files=("${filtered[@]}")
fi

# Check each file
violations=0
warnings=0
json_entries=()

for file in "${files[@]}"; do
    lines=$(wc -l < "$file")
    rel_path="${file#"$PROJECT_ROOT/"}"

    if [[ $lines -gt $MAX_LINES ]]; then
        violations=$((violations + 1))
        over=$((lines - MAX_LINES))

        if [[ "$JSON" == true ]]; then
            json_entries+=("{\"file\":\"$rel_path\",\"lines\":$lines,\"limit\":$MAX_LINES,\"over\":$over,\"severity\":\"error\"}")
        else
            echo "ERROR: $rel_path: $lines lines (limit: $MAX_LINES, over by $over)"
            if [[ "$FIX_SUGGESTIONS" == true ]]; then
                # Count functions as a rough split indicator
                func_count=$(grep -cE '^[a-zA-Z_][a-zA-Z_0-9]*\(\)\s*\{' "$file" 2>/dev/null || echo "0")
                if [[ $func_count -gt 1 ]]; then
                    echo "  Suggestion: $func_count functions detected — extract into separate lib modules"
                else
                    echo "  Suggestion: look for inline blocks (loops, conditionals) that can become functions"
                fi
            fi
        fi
    elif [[ $lines -gt $WARN_AT ]]; then
        warnings=$((warnings + 1))
        if [[ "$JSON" == true ]]; then
            json_entries+=("{\"file\":\"$rel_path\",\"lines\":$lines,\"limit\":$MAX_LINES,\"severity\":\"warning\"}")
        else
            echo "WARNING: $rel_path: $lines lines (approaching limit of $MAX_LINES)"
        fi
    fi
done

# Output
if [[ "$JSON" == true ]]; then
    echo "["
    for ((i = 0; i < ${#json_entries[@]}; i++)); do
        if [[ $i -lt $((${#json_entries[@]} - 1)) ]]; then
            echo "  ${json_entries[$i]},"
        else
            echo "  ${json_entries[$i]}"
        fi
    done
    echo "]"
fi

# Summary
total=${#files[@]}
if [[ "$JSON" != true ]]; then
    echo ""
    echo "Scanned $total files: $violations errors, $warnings warnings (limit: $MAX_LINES, warn: $WARN_AT)"
fi

if [[ $violations -gt 0 ]]; then
    exit 1
fi
exit 0
