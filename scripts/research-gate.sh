#!/usr/bin/env bash
# research-gate.sh — Blocks PRD generation if research has unresolved blocking issues
#
# Usage: research-gate.sh <research-json> [--force]
#
# Reads tasks/research-<slug>.json and checks:
#   - File exists and is valid JSON
#   - No blocking_issues with resolved: false
#
# Exit 0 = clear (proceed to PRD)
# Exit 1 = blocked (unresolved issues)
# --force = override (exit 0 regardless, with warning)

set -euo pipefail

FORCE=false

usage() {
    cat <<'EOF'
research-gate.sh — Research phase gate for PRD generation

USAGE:
  research-gate.sh <research-json> [--force]

OPTIONS:
  --force    Override blocking issues (exit 0 with warning)
  -h, --help Show this help

EXIT CODES:
  0  Clear — no unresolved blocking issues
  1  Blocked — unresolved blocking issues found
EOF
}

# Parse args
RESEARCH_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --force) FORCE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) RESEARCH_FILE="$1"; shift ;;
    esac
done

if [[ -z "$RESEARCH_FILE" ]]; then
    echo "Error: research JSON file required" >&2
    echo "Usage: research-gate.sh <research-json> [--force]" >&2
    exit 1
fi

if [[ ! -f "$RESEARCH_FILE" ]]; then
    echo "Error: file not found: $RESEARCH_FILE" >&2
    exit 1
fi

# Validate JSON
if ! jq empty "$RESEARCH_FILE" 2>/dev/null; then
    echo "Error: invalid JSON: $RESEARCH_FILE" >&2
    exit 1
fi

# Check for unresolved blocking issues
unresolved_count=$(jq '[.blocking_issues[]? | select(.resolved == false)] | length' "$RESEARCH_FILE" 2>/dev/null || echo "0")

if [[ "$unresolved_count" -gt 0 ]]; then
    echo "RESEARCH GATE: $unresolved_count unresolved blocking issue(s)"
    jq -r '.blocking_issues[]? | select(.resolved == false) | "  - \(.issue)"' "$RESEARCH_FILE" 2>/dev/null

    if [[ "$FORCE" == "true" ]]; then
        echo ""
        echo "WARNING: --force used, proceeding despite blocking issues"
        exit 0
    else
        echo ""
        echo "Resolve blocking issues or use --force to override"
        exit 1
    fi
fi

# Check for warnings (informational, never blocks)
warning_count=$(jq '[.warnings[]?] | length' "$RESEARCH_FILE" 2>/dev/null || echo "0")
if [[ "$warning_count" -gt 0 ]]; then
    echo "RESEARCH GATE: clear ($warning_count warning(s))"
    jq -r '.warnings[]? | "  ⚠ \(.)"' "$RESEARCH_FILE" 2>/dev/null
else
    echo "RESEARCH GATE: clear (no blocking issues, no warnings)"
fi

exit 0
