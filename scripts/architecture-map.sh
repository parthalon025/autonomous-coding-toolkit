#!/usr/bin/env bash
# architecture-map.sh — Scan project for import/source dependencies → ARCHITECTURE-MAP.json
#
# Usage: architecture-map.sh [--project-root <dir>] [--help]
#
# Scans *.sh (source/. statements), *.py (import/from), *.js/*.ts (import/require).
# Groups by directory into modules. Outputs JSON to docs/ARCHITECTURE-MAP.json.
# Skips: node_modules, .git, __pycache__, .venv, .claude, .worktrees
set -euo pipefail

PROJECT_ROOT="."

usage() {
    cat <<'USAGE'
architecture-map.sh — Scan project for dependency graph

Usage: architecture-map.sh [--project-root <dir>] [--help]

Outputs: docs/ARCHITECTURE-MAP.json

Scans shell (source/.), Python (import/from), JS/TS (import/require) files.
Groups files by directory into modules with dependency edges.
USAGE
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h) usage; exit 0 ;;
            --project-root) PROJECT_ROOT="$2"; shift 2 ;;
            *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
        esac
    done
}

# Extract dependencies from a single file
# Output: one dependency per line (relative path)
extract_deps() {
    local file="$1"
    local ext="${file##*.}"

    case "$ext" in
        sh|bash)
            # Match: source <path>, . <path>, source "<path>", . "<path>"
            grep -oE '(source|\.)\s+"?[^"[:space:]]+"?' "$file" 2>/dev/null \
                | sed -E 's/^(source|\.)\s+"?//; s/"?$//' \
                | grep -v '^\$' || true  # Skip variable expansions
            ;;
        py)
            # Match: from <module> import ..., import <module>
            grep -oE '(from\s+\S+\s+import|^import\s+\S+)' "$file" 2>/dev/null \
                | sed -E 's/^from\s+//; s/\s+import.*//; s/^import\s+//; s/\./\//g' \
                | while IFS= read -r mod; do
                    # Convert module path to file path
                    if [[ -f "$PROJECT_ROOT/$mod.py" ]]; then
                        echo "$mod.py"
                    elif [[ -f "$PROJECT_ROOT/$mod/__init__.py" ]]; then
                        echo "$mod/__init__.py"
                    fi
                done
            ;;
        js|ts|jsx|tsx)
            # Match: import ... from '<path>', require('<path>')
            grep -oE "(from\s+['\"][^'\"]+['\"]|require\(['\"][^'\"]+['\"]\))" "$file" 2>/dev/null \
                | sed -E "s/from\s+['\"]//; s/require\(['\"]//; s/['\"].*//; s/\)$//" \
                | grep -E '^\.' || true  # Only relative imports
            ;;
    esac
}

# Build the architecture map JSON
build_map() {
    local generated_at
    generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Find all relevant files, excluding common noise directories
    local -a all_files=()
    while IFS= read -r -d '' file; do
        all_files+=("$file")
    done < <(find "$PROJECT_ROOT" \
        -not -path '*/.git/*' \
        -not -path '*/node_modules/*' \
        -not -path '*/__pycache__/*' \
        -not -path '*/.venv/*' \
        -not -path '*/.claude/*' \
        -not -path '*/.worktrees/*' \
        \( -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.jsx' -o -name '*.tsx' \) \
        -print0 2>/dev/null | sort -z)

    # Group files by directory (module)
    declare -A modules

    for file in "${all_files[@]}"; do
        # Make path relative to project root
        local rel_path="${file#"$PROJECT_ROOT/"}"
        local dir
        dir=$(dirname "$rel_path")
        [[ "$dir" == "." ]] && dir="root"

        # Extract dependencies
        local deps=""
        while IFS= read -r dep; do
            [[ -z "$dep" ]] && continue
            if [[ -n "$deps" ]]; then
                deps+=","
            fi
            deps+="\"$dep\""
        done < <(extract_deps "$file" | sort -u)

        local file_json="{\"path\":\"$rel_path\",\"dependencies\":[$deps]}"

        if [[ -n "${modules[$dir]:-}" ]]; then
            modules["$dir"]+=","
        fi
        modules["$dir"]+="$file_json"
    done

    # Build modules array
    local modules_json=""
    for dir in $(echo "${!modules[@]}" | tr ' ' '\n' | sort); do
        if [[ -n "$modules_json" ]]; then
            modules_json+=","
        fi
        modules_json+="{\"name\":\"$dir\",\"files\":[${modules[$dir]}]}"
    done

    # Write output
    local output_dir="$PROJECT_ROOT/docs"
    mkdir -p "$output_dir"

    cat > "$output_dir/ARCHITECTURE-MAP.json" <<JSON
{
  "generated_at": "$generated_at",
  "project_root": "$(realpath "$PROJECT_ROOT")",
  "modules": [$modules_json]
}
JSON

    echo "Generated: $output_dir/ARCHITECTURE-MAP.json"
    echo "  Modules: $(echo "${!modules[@]}" | wc -w | tr -d ' ')"
    echo "  Files: ${#all_files[@]}"
}

parse_args "$@"
build_map
