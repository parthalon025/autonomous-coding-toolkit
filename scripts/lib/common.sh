#!/usr/bin/env bash
# common.sh — Shared utility functions for Code Factory scripts
#
# Source this in any script: source "$SCRIPT_DIR/lib/common.sh"
#
# Functions:
#   detect_project_type <dir>              -> "python"|"node"|"make"|"bash"|"unknown"
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
    elif [[ -x "$dir/scripts/tests/run-all-tests.sh" ]] || compgen -G "$dir/scripts/tests/test-*.sh" >/dev/null 2>&1; then
        echo "bash"
    else
        echo "unknown"
    fi
}

strip_json_fences() {
    sed '/^```json$/d; /^```$/d'
}

check_memory_available() {
    local threshold_gb="${1:-4}"
    local threshold_mb=$((threshold_gb * 1024))
    local available_mb
    available_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $7}')
    if [[ -z "$available_mb" ]]; then
        # free command unavailable or produced no output — return -1 (unknown)
        echo "WARNING: Cannot determine available memory (free command unavailable)" >&2
        return 2
    fi
    if [[ "$available_mb" -ge "$threshold_mb" ]]; then
        return 0
    else
        local available_display
        available_display=$(awk "BEGIN {printf \"%.1f\", $available_mb / 1024}")
        echo "WARNING: Low memory (${available_display}G available, need ${threshold_gb}G)" >&2
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
