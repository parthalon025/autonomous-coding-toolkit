#!/usr/bin/env bash
# scope-infer.sh — Infer scope tags for lessons missing them
# Reads lesson content and applies heuristics to propose scope tags.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Defaults
LESSONS_DIR="$SCRIPT_DIR/../docs/lessons"
DRY_RUN=true
APPLY=false

usage() {
    cat <<USAGE
Usage: scope-infer.sh [--dir <lessons-dir>] [--dry-run] [--apply]

Infer scope tags for lesson files that don't have a scope: field.

Options:
  --dir <path>    Lessons directory (default: docs/lessons/)
  --dry-run       Show proposed scope without modifying files (default)
  --apply         Write scope field into lesson files
  --help, -h      Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) LESSONS_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; APPLY=false; shift ;;
        --apply) APPLY=true; DRY_RUN=false; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown flag: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# Counters
total=0
inferred=0
skipped=0
count_universal=0
count_language=0
count_domain=0
count_project=0

infer_scope() {
    local file="$1"
    local content
    content=$(cat "$file")

    # Domain signals (check title + body)
    local title_and_body
    title_and_body=$(echo "$content" | tr '[:upper:]' '[:lower:]')

    # Domain: ha-aria
    if echo "$title_and_body" | grep -qE '(home assistant|\bha\b|entity.*area|automation.*trigger|hass|ha-aria)'; then
        echo "domain:ha-aria"
        return
    fi

    # Domain: telegram
    if echo "$title_and_body" | grep -qE '(telegram|bot.*poll|getupdates|chat_id|telegram-brief|telegram-capture)'; then
        echo "domain:telegram"
        return
    fi

    # Domain: notion
    if echo "$title_and_body" | grep -qE '(\bnotion\b|notion.*sync|notion.*database|notion-tools|notion_api)'; then
        echo "domain:notion"
        return
    fi

    # Domain: ollama
    if echo "$title_and_body" | grep -qE '(\bollama\b|ollama.*queue|local.*llm|ollama-queue)'; then
        echo "domain:ollama"
        return
    fi

    # Framework: systemd
    if echo "$title_and_body" | grep -qE '(systemd|systemctl|\.service|\.timer|journalctl|envfile)'; then
        echo "framework:systemd"
        return
    fi

    # Framework: pytest
    if echo "$title_and_body" | grep -qE '(\bpytest\b|conftest|fixture|parametrize)'; then
        echo "framework:pytest"
        return
    fi

    # Framework: preact/jsx
    if echo "$title_and_body" | grep -qE '(\bpreact\b|\bjsx\b|esbuild.*jsx|jsx.*factory)'; then
        echo "framework:preact"
        return
    fi

    # Project-specific: autonomous-coding-toolkit
    if echo "$title_and_body" | grep -qE '(run-plan|quality.gate|lesson-check|mab-run|batch.*audit|ralph.*loop|headless.*mode)'; then
        echo "project:autonomous-coding-toolkit"
        return
    fi

    # Language: check the languages field
    local languages
    languages=$(sed -n '/^---$/,/^---$/{ /^languages:/p; }' "$file" 2>/dev/null | head -1)
    languages=$(echo "$languages" | sed 's/languages:[[:space:]]*//' | tr -d '[]' | tr ',' ' ' | xargs)

    if [[ "$languages" == "python" ]]; then
        echo "language:python"
        return
    elif [[ "$languages" == "shell" ]]; then
        echo "language:bash"
        return
    elif [[ "$languages" == "javascript" || "$languages" == "typescript" ]]; then
        echo "language:javascript"
        return
    fi

    # No signals → universal
    echo "universal"
}

for lesson_file in "$LESSONS_DIR"/[0-9]*.md; do
    [[ -f "$lesson_file" ]] || continue
    total=$((total + 1))

    # Check if scope already present
    if sed -n '/^---$/,/^---$/p' "$lesson_file" | grep -q '^scope:'; then
        skipped=$((skipped + 1))
        continue
    fi

    scope=$(infer_scope "$lesson_file")
    inferred=$((inferred + 1))

    # Count by type
    case "$scope" in
        universal) count_universal=$((count_universal + 1)) ;;
        language:*) count_language=$((count_language + 1)) ;;
        domain:*) count_domain=$((count_domain + 1)) ;;
        project:*) count_project=$((count_project + 1)) ;;
        framework:*) count_language=$((count_language + 1)) ;;  # group with language
    esac

    basename_file=$(basename "$lesson_file")

    if [[ "$APPLY" == true ]]; then
        # Insert scope: [$scope] after the languages: line in YAML frontmatter
        sed -i "/^languages:/a scope: [$scope]" "$lesson_file"
        echo "  APPLIED: $basename_file → scope: [$scope]"
    else
        echo "  PROPOSED: $basename_file → scope: [$scope]"
    fi
done

echo ""
echo "Inferred scope for $inferred lessons: $count_universal universal, $count_domain domain-specific, $count_language language/framework, $count_project project-specific"
echo "Skipped $skipped lessons (already have scope)"
echo "Total: $total lessons scanned"
