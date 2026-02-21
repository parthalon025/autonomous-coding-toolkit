#!/usr/bin/env bash
# lesson-check.sh — Syntactic anti-pattern detector from lessons learned
# Dynamically loads checks from docs/lessons/[0-9]*.md (syntactic pattern.type only).
# Exit 0 if clean, exit 1 with file:line: [lesson-N] format if violations found.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LESSONS_DIR="$SCRIPT_DIR/../docs/lessons"

# ---------------------------------------------------------------------------
# parse_lesson <file>
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

    # Use awk to extract YAML frontmatter fields.
    # Frontmatter is between the first two --- delimiters.
    # Nested pattern: block is handled by tracking a flag when we see "^pattern:".
    eval "$(awk '
        BEGIN {
            in_fm=0; past_first=0; in_pattern=0;
            id=""; title=""; severity=""; ptype=""; pregex=""; langs="";
        }
        /^---$/ {
            if (!past_first) { in_fm=1; past_first=1; next }
            else if (in_fm) { in_fm=0; exit }
        }
        !in_fm { next }

        # Detect entry into the pattern: block
        /^pattern:/ { in_pattern=1; next }

        # If we hit a top-level key (no leading whitespace, ends with :), exit pattern block
        in_pattern && /^[^[:space:]]/ && !/^pattern:/ { in_pattern=0 }

        # Top-level fields
        !in_pattern && /^id:[[:space:]]+/ {
            sub(/^id:[[:space:]]+/, ""); id=$0
        }
        !in_pattern && /^title:[[:space:]]+/ {
            sub(/^title:[[:space:]]+/, "")
            # Strip surrounding quotes
            gsub(/^["'"'"']|["'"'"']$/, "")
            title=$0
        }
        !in_pattern && /^severity:[[:space:]]+/ {
            sub(/^severity:[[:space:]]+/, ""); severity=$0
        }
        !in_pattern && /^languages:[[:space:]]+/ {
            sub(/^languages:[[:space:]]+/, "")
            # Strip [ ] and split on ", " or ","
            gsub(/[\[\]]/, "")
            gsub(/,[ \t]*/, " ")
            gsub(/^[ \t]+|[ \t]+$/, "")
            langs=$0
        }

        # Nested pattern: fields (indented with spaces or tabs)
        in_pattern && /^[[:space:]]+type:[[:space:]]+/ {
            sub(/^[[:space:]]+type:[[:space:]]+/, ""); ptype=$0
        }
        in_pattern && /^[[:space:]]+regex:[[:space:]]+/ {
            sub(/^[[:space:]]+regex:[[:space:]]+/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            pregex=$0
        }

        END {
            # Shell-escape single quotes in values before wrapping
            gsub(/'/, "'"'"'\\'"'"'\\'"'"'\\'"'"''"'"'", title)
            gsub(/'/, "'"'"'\\'"'"'\\'"'"'\\'"'"''"'"'", pregex)
            gsub(/'/, "'"'"'\\'"'"'\\'"'"'\\'"'"''"'"'", langs)
            printf "lesson_id=%s\n",      id
            printf "lesson_title='"'"'%s'"'"'\n", title
            printf "lesson_severity=%s\n", severity
            printf "pattern_type=%s\n",    ptype
            printf "lesson_languages='"'"'%s'"'"'\n", langs
            printf "pattern_regex='"'"'%s'"'"'\n",    pregex
        }
    ' "$file" 2>/dev/null)"

    # Unescape YAML double-escaped backslashes: \\s → \s, \\d → \d, etc.
    # In YAML a regex stored as "\\s" has a literal backslash-backslash in the file,
    # which awk reads as two chars. We need to collapse each \\ → \.
    pattern_regex="${pattern_regex//\\\\/\\}"

    [[ -z "$pattern_type" || "$pattern_type" != "syntactic" ]] && return 1
    [[ -z "$pattern_regex" ]] && return 1
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
    done < <(grep -PHn "$pattern_regex" "${target_files[@]}" 2>/dev/null || true)
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
