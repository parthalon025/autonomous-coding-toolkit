#!/usr/bin/env bash
# install.sh — Install autonomous-coding-toolkit globally for Claude Code
#
# Symlinks skills, agents, commands, and scripts into their global locations:
#   ~/.claude/skills/       <- skills/
#   ~/.claude/agents/       <- agents/
#   ~/.claude/commands/     <- commands/
#   ~/.local/bin/           <- scripts/*.sh (CLI tools)
#
# Safe: skips existing non-symlinked items, replaces stale symlinks pointing
# elsewhere, and reports everything it does.
#
# Usage:
#   ./install.sh            # install (default, skips conflicts)
#   ./install.sh --force    # install, replacing conflicts (backs up to *.bak)
#   ./install.sh --uninstall # remove all symlinks created by this script
#   ./install.sh --status    # show what's installed vs missing
set -euo pipefail

FORCE=0

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

SKILLS_DIR="${HOME}/.claude/skills"
AGENTS_DIR="${HOME}/.claude/agents"
COMMANDS_DIR="${HOME}/.claude/commands"
BIN_DIR="${HOME}/.local/bin"

# CLI scripts to expose on PATH
BIN_SCRIPTS=(
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
skipped=0
replaced=0
errors=0

# --- Helpers ---

log_install() { echo "  + $1"; }
log_skip()    { echo "  ~ $1 (exists, not ours — skipped)"; }
log_replace() { echo "  * $1 (updated stale symlink)"; }
log_force()   { echo "  ! $1 (backed up to .bak, replaced)"; }
log_remove()  { echo "  - $1"; }

symlink_item() {
    local src="$1" dest="$2" label="$3"

    if [[ -L "$dest" ]]; then
        local current
        current=$(readlink -f "$dest" 2>/dev/null || true)
        local target
        target=$(readlink -f "$src" 2>/dev/null || true)
        if [[ "$current" == "$target" ]]; then
            return 0  # already correct
        fi
        # Stale symlink pointing elsewhere — replace
        ln -sfn "$src" "$dest"
        log_replace "$label"
        replaced=$((replaced + 1))
    elif [[ -e "$dest" ]]; then
        if [[ "$FORCE" -eq 1 ]]; then
            mv "$dest" "${dest}.bak"
            ln -s "$src" "$dest"
            log_force "$label"
            replaced=$((replaced + 1))
        else
            log_skip "$label"
            skipped=$((skipped + 1))
        fi
    else
        ln -s "$src" "$dest"
        log_install "$label"
        installed=$((installed + 1))
    fi
}

remove_if_ours() {
    local src="$1" dest="$2" label="$3"
    if [[ -L "$dest" ]]; then
        local current
        current=$(readlink -f "$dest" 2>/dev/null || true)
        local target
        target=$(readlink -f "$src" 2>/dev/null || true)
        if [[ "$current" == "$target" ]]; then
            rm "$dest"
            log_remove "$label"
            installed=$((installed + 1))
        fi
    fi
}

# --- Install ---

do_install() {
    echo "Installing autonomous-coding-toolkit..."
    echo ""

    mkdir -p "$SKILLS_DIR" "$AGENTS_DIR" "$COMMANDS_DIR" "$BIN_DIR"

    echo "Skills:"
    for skill in "$REPO_ROOT"/skills/*/; do
        [[ -d "$skill" ]] || continue
        name=$(basename "$skill")
        symlink_item "$skill" "$SKILLS_DIR/$name" "skills/$name"
    done

    echo ""
    echo "Agents:"
    for agent in "$REPO_ROOT"/agents/*.md; do
        [[ -f "$agent" ]] || continue
        name=$(basename "$agent")
        symlink_item "$agent" "$AGENTS_DIR/$name" "agents/$name"
    done

    echo ""
    echo "Commands:"
    for cmd in "$REPO_ROOT"/commands/*.md; do
        [[ -f "$cmd" ]] || continue
        name=$(basename "$cmd")
        symlink_item "$cmd" "$COMMANDS_DIR/$name" "commands/$name"
    done

    echo ""
    echo "Scripts (~/.local/bin):"
    for name in "${BIN_SCRIPTS[@]}"; do
        script="${REPO_ROOT}/scripts/${name}.sh"
        if [[ -f "$script" ]]; then
            symlink_item "$script" "$BIN_DIR/$name" "bin/$name"
        fi
    done

    echo ""
    echo "Git hooks:"
    local git_hooks_dir="${REPO_ROOT}/.git/hooks"
    if [[ -d "$git_hooks_dir" ]]; then
        local hook_src="${REPO_ROOT}/hooks/post-commit"
        local hook_dest="${git_hooks_dir}/post-commit"
        if [[ -f "$hook_src" ]]; then
            cp "$hook_src" "$hook_dest"
            chmod +x "$hook_dest"
            echo "  + post-commit (lessons-db auto-import)"
            installed=$((installed + 1))
        fi
    else
        echo "  ~ no .git directory found — skipping git hook installation"
    fi

    echo ""
    echo "Done: $installed installed, $replaced updated, $skipped skipped"
}

# --- Uninstall ---

do_uninstall() {
    installed=0
    echo "Uninstalling autonomous-coding-toolkit..."
    echo ""

    echo "Skills:"
    for skill in "$REPO_ROOT"/skills/*/; do
        [[ -d "$skill" ]] || continue
        name=$(basename "$skill")
        remove_if_ours "$skill" "$SKILLS_DIR/$name" "skills/$name"
    done

    echo ""
    echo "Agents:"
    for agent in "$REPO_ROOT"/agents/*.md; do
        [[ -f "$agent" ]] || continue
        name=$(basename "$agent")
        remove_if_ours "$agent" "$AGENTS_DIR/$name" "agents/$name"
    done

    echo ""
    echo "Commands:"
    for cmd in "$REPO_ROOT"/commands/*.md; do
        [[ -f "$cmd" ]] || continue
        name=$(basename "$cmd")
        remove_if_ours "$cmd" "$COMMANDS_DIR/$name" "commands/$name"
    done

    echo ""
    echo "Scripts:"
    for name in "${BIN_SCRIPTS[@]}"; do
        script="${REPO_ROOT}/scripts/${name}.sh"
        if [[ -f "$script" ]]; then
            remove_if_ours "$script" "$BIN_DIR/$name" "bin/$name"
        fi
    done

    echo ""
    echo "Removed $installed symlinks"
}

# --- Status ---

do_status() {
    echo "autonomous-coding-toolkit install status"
    echo "Repo: $REPO_ROOT"
    echo ""

    local ok=0 missing=0 stale=0 conflict=0

    check_item() {
        local src="$1" dest="$2" label="$3"
        if [[ -L "$dest" ]]; then
            local current
            current=$(readlink -f "$dest" 2>/dev/null || true)
            local target
            target=$(readlink -f "$src" 2>/dev/null || true)
            if [[ "$current" == "$target" ]]; then
                ok=$((ok + 1))
            else
                echo "  STALE  $label -> $(readlink "$dest")"
                stale=$((stale + 1))
            fi
        elif [[ -e "$dest" ]]; then
            echo "  CONFLICT $label (exists, not a symlink)"
            conflict=$((conflict + 1))
        else
            echo "  MISSING  $label"
            missing=$((missing + 1))
        fi
    }

    echo "Skills:"
    for skill in "$REPO_ROOT"/skills/*/; do
        [[ -d "$skill" ]] || continue
        name=$(basename "$skill")
        check_item "$skill" "$SKILLS_DIR/$name" "skills/$name"
    done

    echo "Agents:"
    for agent in "$REPO_ROOT"/agents/*.md; do
        [[ -f "$agent" ]] || continue
        name=$(basename "$agent")
        check_item "$agent" "$AGENTS_DIR/$name" "agents/$name"
    done

    echo "Commands:"
    for cmd in "$REPO_ROOT"/commands/*.md; do
        [[ -f "$cmd" ]] || continue
        name=$(basename "$cmd")
        check_item "$cmd" "$COMMANDS_DIR/$name" "commands/$name"
    done

    echo "Scripts:"
    for name in "${BIN_SCRIPTS[@]}"; do
        script="${REPO_ROOT}/scripts/${name}.sh"
        if [[ -f "$script" ]]; then
            check_item "$script" "$BIN_DIR/$name" "bin/$name"
        fi
    done

    echo ""
    echo "OK: $ok  Missing: $missing  Stale: $stale  Conflict: $conflict"
}

# --- Main ---

case "${1:-}" in
    --uninstall) do_uninstall ;;
    --status)    do_status ;;
    --force)     FORCE=1; do_install ;;
    *)           do_install ;;
esac
