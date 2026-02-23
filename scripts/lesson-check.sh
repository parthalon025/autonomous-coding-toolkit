#!/usr/bin/env bash
# lesson-check.sh — Syntactic anti-pattern detector from lessons learned
# Dynamically loads checks from docs/lessons/[0-9]*.md (syntactic pattern.type only).
# Exit 0 if clean, exit 1 with file:line: [lesson-N] format if violations found.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LESSONS_DIR="$SCRIPT_DIR/../docs/lessons"

# ---------------------------------------------------------------------------
# parse_lesson <file>
# shellcheck disable=SC2034  # lesson_severity parsed for future severity filtering
# Sets: lesson_id, lesson_title, lesson_severity, pattern_type, pattern_regex,
#       lesson_languages (space-separated list)
# Returns 1 if the lesson cannot be parsed or has no syntactic pattern.
# ---------------------------------------------------------------------------
parse_lesson() {
    local file="$1"
    lesson_id=""
    lesson_title=""
    lesson_severity=""
    pattern_type=""
    pattern_regex=""
    lesson_languages=""

    # Parse YAML frontmatter with sed + read (no eval — safe with special chars).
    # Extract text between first two --- delimiters, then parse key: value lines.
    local in_pattern=false
    local line
    while IFS= read -r line; do
        # Detect entry/exit of pattern: block
        if [[ "$line" =~ ^pattern: ]]; then
            in_pattern=true
            continue
        fi
        if [[ "$in_pattern" == true && "$line" =~ ^[^[:space:]] && ! "$line" =~ ^pattern: ]]; then
            in_pattern=false
        fi

        if [[ "$in_pattern" == false ]]; then
            # Top-level fields
            if [[ "$line" =~ ^id:[[:space:]]+(.*) ]]; then
                lesson_id="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^title:[[:space:]]+(.*) ]]; then
                lesson_title="${BASH_REMATCH[1]}"
                lesson_title="${lesson_title#\"}"
                lesson_title="${lesson_title%\"}"
                lesson_title="${lesson_title#\'}"
                lesson_title="${lesson_title%\'}"
            elif [[ "$line" =~ ^severity:[[:space:]]+(.*) ]]; then
                lesson_severity="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^languages:[[:space:]]+(.*) ]]; then
                lesson_languages="${BASH_REMATCH[1]}"
                lesson_languages="${lesson_languages//[\[\]]/}"
                lesson_languages="${lesson_languages//,/ }"
                lesson_languages="${lesson_languages## }"
                lesson_languages="${lesson_languages%% }"
            fi
        else
            # Nested pattern: fields (indented)
            if [[ "$line" =~ ^[[:space:]]+type:[[:space:]]+(.*) ]]; then
                pattern_type="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]+regex:[[:space:]]+(.*) ]]; then
                pattern_regex="${BASH_REMATCH[1]}"
                pattern_regex="${pattern_regex#\"}"
                pattern_regex="${pattern_regex%\"}"
                pattern_regex="${pattern_regex#\'}"
                pattern_regex="${pattern_regex%\'}"
            fi
        fi
    done < <(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$file" 2>/dev/null)

    # Unescape YAML double-escaped backslashes: \\s → \s, \\d → \d, etc.
    pattern_regex="${pattern_regex//\\\\/\\}"

    [[ -z "$pattern_type" || "$pattern_type" != "syntactic" ]] && return 1
    [[ -z "$pattern_regex" ]] && return 1

    # Convert PCRE shorthand classes to POSIX ERE equivalents for grep -E portability.
    # This lets lesson authors use \s, \d, \w, \b in regex: fields while keeping
    # the scanner portable (grep -P is unavailable on macOS).
    pattern_regex="${pattern_regex//\\d/[0-9]}"
    pattern_regex="${pattern_regex//\\s/[[:space:]]}"
    pattern_regex="${pattern_regex//\\w/[_[:alnum:]]}"
    pattern_regex="${pattern_regex//\\b/\\b}"  # ERE \b is a GNU extension, widely available

    return 0
}

# ---------------------------------------------------------------------------
# Build the --help text dynamically from lesson files
# ---------------------------------------------------------------------------
build_help() {
    local checks_text=""
    local lfile
    for lfile in "$LESSONS_DIR"/[0-9]*.md; do
        [[ -f "$lfile" ]] || continue
        if parse_lesson "$lfile"; then
            local lang_display="$lesson_languages"
            [[ "$lang_display" == "all" ]] && lang_display="all files"
            checks_text+="  [lesson-${lesson_id}]  ${lesson_title} (${lang_display})"$'\n'
        fi
    done

    cat <<USAGE
Usage: lesson-check.sh [file ...]
  Check files for known anti-patterns from lessons learned.
  Files can be passed as arguments or piped via stdin (one per line).
  If neither, defaults to git diff --name-only in current directory.

Checks (syntactic only — loaded from ${LESSONS_DIR}):
${checks_text}
Output: file:line: [lesson-N] description
Exit:   0 if clean, 1 if violations found
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    build_help
    exit 0
fi

violations=0

# ---------------------------------------------------------------------------
# Gather file list: args → stdin pipe → git diff fallback
# ---------------------------------------------------------------------------
files=()
if [[ $# -gt 0 ]]; then
    files=("$@")
elif [[ ! -t 0 ]]; then
    while IFS= read -r f; do
        [[ -n "$f" ]] && files+=("$f")
    done
else
    while IFS= read -r f; do
        [[ -n "$f" ]] && files+=("$f")
    done < <(git diff --name-only 2>/dev/null || true)
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "lesson-check: no files to check" >&2
    exit 0
fi

# Pre-filter: only keep files that actually exist on disk
existing_files=()
for f in "${files[@]}"; do
    [[ -f "$f" ]] && existing_files+=("$f")
done

if [[ ${#existing_files[@]} -eq 0 ]]; then
    echo "lesson-check: no files to check" >&2
    exit 0
fi

# ---------------------------------------------------------------------------
# Language → file extension mapping
# ---------------------------------------------------------------------------
# Returns 1 (mismatch) if the file doesn't match the lesson's languages.
file_matches_languages() {
    local filepath="$1"
    local languages="$2"   # space-separated

    # "all" matches everything
    [[ "$languages" == "all" ]] && return 0

    local lang
    for lang in $languages; do
        case "$lang" in
            python)     [[ "$filepath" == *.py ]]  && return 0 ;;
            javascript) [[ "$filepath" == *.js ]]  && return 0 ;;
            typescript) [[ "$filepath" == *.ts ]]  && return 0 ;;
            shell)      [[ "$filepath" == *.sh ]]  && return 0 ;;
        esac
    done
    return 1
}

# ---------------------------------------------------------------------------
# Main loop: iterate lesson files, run syntactic checks
# ---------------------------------------------------------------------------
lfile=""
for lfile in "$LESSONS_DIR"/[0-9]*.md; do
    [[ -f "$lfile" ]] || continue
    parse_lesson "$lfile" || continue

    # Build list of target files that match this lesson's languages
    target_files=()
    local_f=""
    for local_f in "${existing_files[@]}"; do
        file_matches_languages "$local_f" "$lesson_languages" && target_files+=("$local_f")
    done
    [[ ${#target_files[@]} -eq 0 ]] && continue

    # Run grep against matching files; format output as file:line: [lesson-N] title
    local_id="$lesson_id"
    local_title="$lesson_title"
    while IFS=: read -r matched_file lineno _rest; do
        [[ -z "$matched_file" ]] && continue
        echo "${matched_file}:${lineno}: [lesson-${local_id}] ${local_title}"
        ((violations++)) || true
    done < <(grep -EHn "$pattern_regex" "${target_files[@]}" 2>/dev/null || true)
done

# ---------------------------------------------------------------------------
# Summary and exit
# ---------------------------------------------------------------------------
if [[ $violations -gt 0 ]]; then
    echo ""
    echo "lesson-check: $violations violation(s) found"
    exit 1
else
    echo "lesson-check: clean"
    exit 0
fi
