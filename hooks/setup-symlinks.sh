#!/usr/bin/env bash
# setup-symlinks.sh — Auto-create ~/.local/bin symlinks on first session
# Runs via SessionStart hook. Guard file prevents re-running after initial setup.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
GUARD_FILE="${PLUGIN_ROOT}/.symlinks-installed"
BIN_DIR="${HOME}/.local/bin"

# Skip if already done
[[ -f "$GUARD_FILE" ]] && exit 0

# Ensure bin dir exists
mkdir -p "$BIN_DIR"

# Scripts to expose on PATH (user-facing CLI tools only)
SCRIPTS=(
    run-plan
    quality-gate
    lesson-check
    policy-check
    research-gate
    auto-compound
    entropy-audit
    batch-audit
    batch-test
    mab-run
    scope-infer
    pipeline-status
    setup-ralph-loop
)

installed=0
for name in "${SCRIPTS[@]}"; do
    script="${PLUGIN_ROOT}/scripts/${name}.sh"
    link="${BIN_DIR}/${name}"
    if [[ -f "$script" ]] && [[ ! -e "$link" ]]; then
        ln -sf "$script" "$link"
        installed=$((installed + 1))
    fi
done

# Mark as done
touch "$GUARD_FILE"

if [[ $installed -gt 0 ]]; then
    echo "Autonomous Coding Toolkit: installed $installed commands to ~/.local/bin"
fi
