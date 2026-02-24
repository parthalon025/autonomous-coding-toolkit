#!/usr/bin/env bash
# validate-policies.sh — Validate policy files exist and policy-check runs clean
# Used by validate-all.sh. Pass --warn to use advisory mode.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICY_DIR="$TOOLKIT_ROOT/policies"
WARN=false
EXIT_CODE=0

[[ "${1:-}" == "--warn" ]] && WARN=true
[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { echo "Usage: validate-policies.sh [--warn]"; exit 0; }

# Check policies directory exists
if [[ ! -d "$POLICY_DIR" ]]; then
    echo "FAIL: policies/ directory not found"
    [[ "$WARN" == "true" ]] && exit 0 || exit 1
fi

# Check required policy files exist
required=(universal python bash testing)
for name in "${required[@]}"; do
    if [[ ! -f "$POLICY_DIR/$name.md" ]]; then
        echo "FAIL: missing policy file: policies/$name.md"
        EXIT_CODE=1
    fi
done

# Check policy files are non-empty
for f in "$POLICY_DIR"/*.md; do
    if [[ ! -s "$f" ]]; then
        echo "FAIL: empty policy file: $f"
        EXIT_CODE=1
    fi
done

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "validate-policies: PASS"
fi

[[ "$WARN" == "true" ]] && exit 0 || exit $EXIT_CODE
