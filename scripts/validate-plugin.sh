#!/usr/bin/env bash
# validate-plugin.sh — Validate .claude-plugin/plugin.json and marketplace.json consistency
# Exit 0 if clean, exit 1 if violations found. Use --warn to print but exit 0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="${PLUGIN_DIR:-$SCRIPT_DIR/../.claude-plugin}"
WARN_ONLY=false
violations=0

usage() {
    echo "Usage: validate-plugin.sh [--warn] [--help]"
    echo "  Validates .claude-plugin/plugin.json and marketplace.json"
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

if [[ ! -d "$PLUGIN_DIR" ]]; then
    echo "validate-plugin: plugin directory not found: $PLUGIN_DIR" >&2
    exit 1
fi

# Check files exist
if [[ ! -f "$PLUGIN_DIR/plugin.json" ]]; then
    report_violation "plugin.json" "plugin.json not found"
fi
if [[ ! -f "$PLUGIN_DIR/marketplace.json" ]]; then
    report_violation "marketplace.json" "marketplace.json not found"
fi

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "validate-plugin: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
fi

# Validate JSON
if ! jq empty "$PLUGIN_DIR/plugin.json" 2>/dev/null; then
    report_violation "plugin.json" "plugin.json is not valid JSON"
fi
if ! jq empty "$PLUGIN_DIR/marketplace.json" 2>/dev/null; then
    report_violation "marketplace.json" "marketplace.json is not valid JSON"
fi

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "validate-plugin: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
fi

# Extract fields
plugin_name=$(jq -r '.name' "$PLUGIN_DIR/plugin.json")
plugin_version=$(jq -r '.version' "$PLUGIN_DIR/plugin.json")
market_name=$(jq -r '.name' "$PLUGIN_DIR/marketplace.json")
market_version=$(jq -r '.plugins[0].version' "$PLUGIN_DIR/marketplace.json")

# Check name match
if [[ "$plugin_name" != "$market_name" ]]; then
    report_violation "plugin.json" "name mismatch: plugin.json='$plugin_name' marketplace.json='$market_name'"
fi

# Check version match
if [[ "$plugin_version" != "$market_version" ]]; then
    report_violation "plugin.json" "version mismatch: plugin.json='$plugin_version' marketplace.json='$market_version'"
fi

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "validate-plugin: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
else
    echo "validate-plugin: PASS"
    exit 0
fi
