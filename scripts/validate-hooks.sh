#!/usr/bin/env bash
# validate-hooks.sh — Validate hooks/hooks.json and referenced scripts
# Exit 0 if clean, exit 1 if violations found. Use --warn to print but exit 0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="${HOOKS_DIR:-$SCRIPT_DIR/../hooks}"
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$SCRIPT_DIR/..}"
WARN_ONLY=false
violations=0

usage() {
    echo "Usage: validate-hooks.sh [--warn] [--help]"
    echo "  Validates hooks/hooks.json and referenced scripts"
    echo "  --warn   Print violations but exit 0"
    exit 0
}

report_violation() {
    local file="$1" msg="$2"
    echo "${file}: ${msg}"
    ((violations++)) || true
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage
[[ "${1:-}" == "--warn" ]] && WARN_ONLY=true

if [[ ! -d "$HOOKS_DIR" ]]; then
    echo "validate-hooks: hooks directory not found: $HOOKS_DIR" >&2
    exit 1
fi

hooks_file="$HOOKS_DIR/hooks.json"
if [[ ! -f "$hooks_file" ]]; then
    report_violation "hooks.json" "hooks.json not found"
    echo ""
    echo "validate-hooks: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
fi

# Validate JSON
if ! jq empty "$hooks_file" 2>/dev/null; then
    report_violation "hooks.json" "hooks.json is not valid JSON"
    echo ""
    echo "validate-hooks: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
fi

# Extract all command paths from hooks — walks the entire JSON tree for "command" keys
commands=$(jq -r '.. | objects | select(.type == "command") | .command' "$hooks_file" 2>/dev/null || true)

while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    # Resolve ${CLAUDE_PLUGIN_ROOT} to toolkit root
    resolved="${cmd//\$\{CLAUDE_PLUGIN_ROOT\}/$TOOLKIT_ROOT}"

    # Extract the script path (last token that looks like a file path)
    # Handles "bash /path/to/script.sh" and "/path/to/script.sh" alike
    script_path="$resolved"
    for token in $resolved; do
        if [[ "$token" == /* || "$token" == \$* ]]; then
            script_path="$token"
            break
        fi
    done

    # Skip if the resolved path is just a bare command (e.g., "bash" — not a file check target)
    if [[ "$script_path" != */* ]]; then
        continue
    fi

    if [[ ! -f "$script_path" ]]; then
        report_violation "hooks.json" "script not found: $cmd (resolved: $script_path)"
    elif [[ ! -x "$script_path" ]]; then
        report_violation "hooks.json" "script not executable: $cmd (resolved: $script_path)"
    fi
done <<< "$commands"

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "validate-hooks: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
else
    echo "validate-hooks: PASS"
    exit 0
fi
