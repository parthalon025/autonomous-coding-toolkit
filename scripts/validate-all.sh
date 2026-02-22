#!/usr/bin/env bash
# validate-all.sh — Run all repo-level validators and report summary
# Exit 0 if all pass, exit 1 if any fail. Use --warn to pass through to validators.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS_ARGS=()

usage() {
    echo "Usage: validate-all.sh [--warn] [--help]"
    echo "  Runs all repo-level validators (lessons, skills, commands, plugin, hooks)"
    echo "  --warn   Pass --warn to all validators (print violations but exit 0)"
    exit 0
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage
[[ "${1:-}" == "--warn" ]] && PASS_ARGS=("--warn")

validators=(
    validate-lessons
    validate-skills
    validate-commands
    validate-plugin
    validate-hooks
)

total=${#validators[@]}
passed=0
failed_names=()

for name in "${validators[@]}"; do
    script="$SCRIPT_DIR/${name}.sh"
    if [[ ! -f "$script" ]]; then
        echo "  $name: SKIP (not found)"
        continue
    fi

    exit_code=0
    bash "$script" "${PASS_ARGS[@]}" >/dev/null 2>&1 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "  $name: PASS"
        ((passed++)) || true
    else
        echo "  $name: FAIL"
        failed_names+=("$name")
    fi
done

echo ""
echo "$passed/$total validators passed"

if [[ ${#failed_names[@]} -gt 0 ]]; then
    echo "Failed: ${failed_names[*]}"
    exit 1
fi
