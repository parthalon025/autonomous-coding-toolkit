#!/usr/bin/env bash
# common.sh — Shared utility functions for Code Factory scripts
#
# Source this in any script: source "$SCRIPT_DIR/lib/common.sh"
#
# Functions:
#   detect_project_type <dir>              -> "python"|"node"|"make"|"unknown"
#   strip_json_fences                      -> stdin filter: remove ```json wrappers
#   check_memory_available <threshold_gb>  -> exit 0 if available >= threshold, 1 otherwise
#   require_command <cmd> [install_hint]   -> exit 1 with message if cmd not found

detect_project_type() {
    local dir="$1"
    if [[ -f "$dir/pyproject.toml" || -f "$dir/setup.py" || -f "$dir/pytest.ini" ]]; then
        echo "python"
    elif [[ -f "$dir/package.json" ]]; then
        echo "node"
    elif [[ -f "$dir/Makefile" ]]; then
        echo "make"
    else
        echo "unknown"
    fi
}

strip_json_fences() {
    sed '/^```json$/d; /^```$/d'
}

check_memory_available() {
    local threshold_gb="${1:-4}"
    local available_gb
    available_gb=$(free -g 2>/dev/null | awk '/Mem:/{print $7}' || echo "999")
    if [[ "$available_gb" -ge "$threshold_gb" ]]; then
        return 0
    else
        echo "WARNING: Low memory (${available_gb}G available, need ${threshold_gb}G)" >&2
        return 1
    fi
}

require_command() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $cmd" >&2
        if [[ -n "$hint" ]]; then
            echo "  Install with: $hint" >&2
        fi
        return 1
    fi
}
