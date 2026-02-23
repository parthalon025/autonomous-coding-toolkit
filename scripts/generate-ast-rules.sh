#!/usr/bin/env bash
# generate-ast-rules.sh — Generate ast-grep rules from lesson YAML frontmatter
#
# Reads lesson files with pattern.type: semantic and supported languages,
# generates ast-grep YAML rule files in the output directory.
# Syntactic patterns are skipped (grep handles them via lesson-check.sh).
#
# Usage: generate-ast-rules.sh --lessons-dir <dir> [--output-dir <dir>] [--list]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LESSONS_DIR=""
OUTPUT_DIR=""
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lessons-dir) LESSONS_DIR="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --list) LIST_ONLY=true; shift ;;
        -h|--help)
            echo "Usage: generate-ast-rules.sh --lessons-dir <dir> [--output-dir <dir>] [--list]"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$LESSONS_DIR" ]]; then
    echo "ERROR: --lessons-dir required" >&2
    exit 1
fi

# Default output directory to scripts/patterns/ (where existing patterns live)
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$SCRIPT_DIR/patterns"
fi

generated=0
skipped_syntactic=0
skipped_unconvertible=0

for lesson_file in "$LESSONS_DIR"/*.md; do
    [[ -f "$lesson_file" ]] || continue
    base=$(basename "$lesson_file")
    [[ "$base" == "TEMPLATE.md" || "$base" == "SUMMARY.md" || "$base" == "FRAMEWORK.md" ]] && continue

    # Extract frontmatter fields via sed
    local_id=$(sed -n '/^---$/,/^---$/{/^id:/s/^id: *//p}' "$lesson_file" | head -1)
    local_type=$(sed -n '/^---$/,/^---$/{/^  type:/s/^  type: *//p}' "$lesson_file" | head -1)
    local_title=$(sed -n '/^---$/,/^---$/{/^title:/s/^title: *"*//p}' "$lesson_file" | head -1 | sed 's/"$//')
    local_langs=$(sed -n '/^---$/,/^---$/{/^languages:/s/^languages: *//p}' "$lesson_file" | head -1)

    # Skip syntactic patterns (grep handles these)
    if [[ "$local_type" == "syntactic" ]]; then
        skipped_syntactic=$((skipped_syntactic + 1))
        continue
    fi

    # Only generate for languages ast-grep supports
    if [[ "$local_langs" != *"python"* && "$local_langs" != *"javascript"* && "$local_langs" != *"typescript"* ]]; then
        skipped_unconvertible=$((skipped_unconvertible + 1))
        continue
    fi

    local_basename=$(basename "$lesson_file" .md)

    if [[ "$LIST_ONLY" == true ]]; then
        echo "  Would generate: $local_basename.yml (lesson $local_id: $local_title)"
        generated=$((generated + 1))
        continue
    fi

    mkdir -p "$OUTPUT_DIR"

    # Determine primary language
    local_lang=$(echo "$local_langs" | sed 's/\[//;s/\]//;s/,.*//;s/ //g')

    # Generate ast-grep rule YAML
    cat > "$OUTPUT_DIR/$local_basename.yml" << RULE
id: $local_basename
message: "$local_title"
severity: warning
language: $local_lang
note: "Auto-generated from lesson $local_id. See docs/lessons/$local_basename.md"
RULE

    generated=$((generated + 1))
done

if [[ "$LIST_ONLY" == true ]]; then
    echo ""
    echo "Summary: $generated convertible, $skipped_syntactic syntactic (grep), $skipped_unconvertible unsupported language"
else
    echo "Generated $generated ast-grep rules in $OUTPUT_DIR"
    echo "Skipped: $skipped_syntactic syntactic (grep handles), $skipped_unconvertible unsupported language"
fi
