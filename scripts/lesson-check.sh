#!/usr/bin/env bash
# lesson-check.sh — Syntactic anti-pattern detector from lessons learned
# Dynamically loads checks from docs/lessons/[0-9]*.md (syntactic pattern.type only).
# Exit 0 if clean, exit 1 with file:line: [lesson-N] format if violations found.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LESSONS_DIR="${LESSONS_DIR:-$SCRIPT_DIR/../docs/lessons}"

# Project-local lessons (Tier 3) — loaded alongside bundled lessons.
# Set PROJECT_ROOT to the project being checked for project-specific anti-patterns.
PROJECT_LESSONS_DIR=""
if [[ -n "${PROJECT_ROOT:-}" && -d "${PROJECT_ROOT}/docs/lessons" ]]; then
    _canonical_bundled="$(cd "$LESSONS_DIR" 2>/dev/null && pwd)"
    _canonical_project="$(cd "${PROJECT_ROOT}/docs/lessons" 2>/dev/null && pwd)"
    if [[ "$_canonical_project" != "$_canonical_bundled" ]]; then
        PROJECT_LESSONS_DIR="${PROJECT_ROOT}/docs/lessons"
    fi
fi

# ---------------------------------------------------------------------------
# parse_lesson <file>
# shellcheck disable=SC2034  # lesson_severity, lesson_scope parsed for future filtering
# Sets: lesson_id, lesson_title, lesson_severity, pattern_type, pattern_regex,
#       lesson_languages (space-separated list), lesson_scope (space-separated tags)
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
    lesson_scope=""

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
            elif [[ "$line" =~ ^scope:[[:space:]]+(.*) ]]; then
                lesson_scope="${BASH_REMATCH[1]}"
                lesson_scope="${lesson_scope//[\[\]]/}"
                lesson_scope="${lesson_scope//,/ }"
                lesson_scope="${lesson_scope## }"
                lesson_scope="${lesson_scope%% }"
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

    # Default scope to universal when omitted (backward compatible)
    [[ -z "$lesson_scope" ]] && lesson_scope="universal"

    # Convert PCRE shorthand classes to POSIX ERE equivalents for grep -E portability.
    # This lets lesson authors use \s, \d, \w, \b in regex: fields while keeping
    # the scanner portable (grep -P is unavailable on macOS).
    pattern_regex="${pattern_regex//\\d/[0-9]}"
    pattern_regex="${pattern_regex//\\s/[[:space:]]}"
    pattern_regex="${pattern_regex//\\w/[_[:alnum:]]}"
    pattern_regex="${pattern_regex//\\b/\\b}"  # no-op: \b passes through unchanged; GNU grep -E supports \b as word boundary (not BSD/macOS)

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
            local scope_display="$lesson_scope"
            checks_text+="  [lesson-${lesson_id}]  ${lesson_title} (${lang_display}) [scope: ${scope_display}]"$'\n'
        fi
    done

    cat <<USAGE
Usage: lesson-check.sh [OPTIONS] [file ...]
  Check files for known anti-patterns from lessons learned.
  Files can be passed as arguments or piped via stdin (one per line).
  If neither, defaults to git diff --name-only in current directory.

Options:
  --help, -h       Show this help
  --all-scopes     Bypass scope filtering (check all lessons regardless of project)
  --show-scope     Display detected project scope and exit
  --scope <tags>   Override project scope (comma-separated, e.g. "language:python,domain:ha-aria")

Checks (syntactic only — loaded from ${LESSONS_DIR}):
${checks_text}
Output: file:line: [lesson-N] description
Exit:   0 if clean, 1 if violations found
USAGE
}

# ---------------------------------------------------------------------------
# detect_project_scope [claude_md_path]
# Reads ## Scope Tags from CLAUDE.md. Falls back to detect_project_type().
# Sets global: project_scope (space-separated tags)
# ---------------------------------------------------------------------------
detect_project_scope() {
    local claude_md="${1:-}"
    project_scope=""

    # Try explicit path first, then search current directory upward
    if [[ -z "$claude_md" ]]; then
        claude_md="CLAUDE.md"
        # Walk up to find CLAUDE.md (max 5 levels)
        local search_dir="$PWD"
        for _ in 1 2 3 4 5; do
            if [[ -f "$search_dir/CLAUDE.md" ]]; then
                claude_md="$search_dir/CLAUDE.md"
                break
            fi
            search_dir="$(dirname "$search_dir")"
        done
    fi

    # Parse ## Scope Tags section from CLAUDE.md
    if [[ -f "$claude_md" ]]; then
        local in_scope_section=false
        local line
        while IFS= read -r line; do
            if [[ "$line" =~ ^##[[:space:]]+Scope[[:space:]]+Tags ]]; then
                in_scope_section=true
                continue
            fi
            if [[ "$in_scope_section" == true ]]; then
                # Stop at next heading
                if [[ "$line" =~ ^## ]]; then
                    break
                fi
                # Skip empty lines
                [[ -z "${line// /}" ]] && continue
                # Parse comma-separated tags
                local tag
                for tag in ${line//,/ }; do
                    tag="${tag## }"
                    tag="${tag%% }"
                    [[ -n "$tag" ]] && project_scope+="$tag "
                done
            fi
        done < "$claude_md"
        project_scope="${project_scope%% }"
    fi

    # Fallback: detect project type → language tag
    if [[ -z "$project_scope" ]]; then
        source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || true
        if type detect_project_type &>/dev/null; then
            local ptype
            ptype=$(detect_project_type "$PWD")
            case "$ptype" in
                python)  project_scope="language:python" ;;
                node)    project_scope="language:javascript" ;;
                bash)    project_scope="language:bash" ;;
                *)       project_scope="" ;;
            esac
        fi
    fi

    # If still empty, everything matches (universal behavior)
}

# ---------------------------------------------------------------------------
# scope_matches <lesson_scope> <project_scope>
# Returns 0 if lesson should run on this project, 1 if it should be skipped.
# A lesson matches if ANY of its scope tags intersects the project's scope set,
# or if the lesson scope includes "universal".
# ---------------------------------------------------------------------------
scope_matches() {
    local l_scope="$1"    # space-separated lesson scope tags
    local p_scope="$2"    # space-separated project scope tags

    # universal matches everything
    local tag
    for tag in $l_scope; do
        [[ "$tag" == "universal" ]] && return 0
    done

    # If project has no scope, everything matches (backward compat)
    [[ -z "$p_scope" ]] && return 0

    # Check intersection
    local ltag ptag
    for ltag in $l_scope; do
        for ptag in $p_scope; do
            [[ "$ltag" == "$ptag" ]] && return 0
        done
    done

    return 1
}

# ---------------------------------------------------------------------------
# CLI flag parsing
# ---------------------------------------------------------------------------
ALL_SCOPES=false
SHOW_SCOPE=false
SCOPE_OVERRIDE=""

# Parse flags before file arguments
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) build_help; exit 0 ;;
        --all-scopes) ALL_SCOPES=true; shift ;;
        --show-scope) SHOW_SCOPE=true; shift ;;
        --scope)
            [[ -z "${2:-}" ]] && { echo "lesson-check: --scope requires an argument" >&2; exit 1; }
            SCOPE_OVERRIDE="$2"; shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
set -- "${args[@]+"${args[@]}"}"

# Handle --show-scope early (no files needed)
if [[ "$SHOW_SCOPE" == true ]]; then
    project_scope=""
    if [[ -n "$SCOPE_OVERRIDE" ]]; then
        project_scope="${SCOPE_OVERRIDE//,/ }"
    else
        detect_project_scope "${PROJECT_CLAUDE_MD:-}"
    fi
    if [[ -n "$project_scope" ]]; then
        echo "Detected project scope: $project_scope"
    else
        echo "No project scope detected (all lessons will apply)"
    fi
    exit 0
fi

violations=0
declare -A seen_violations

# ---------------------------------------------------------------------------
# Gather file list: args → stdin pipe → git diff fallback
# ---------------------------------------------------------------------------
files=()
if [[ $# -gt 0 ]]; then
    files=("$@")
elif [[ -p /dev/stdin ]]; then
    # stdin is a named pipe (shell pipe) — safe to read without blocking.
    # Using [[ -p /dev/stdin ]] instead of [[ ! -t 0 ]] avoids hanging when
    # stdin is a socket (e.g. systemd/cron), which satisfies ! -t 0 but
    # never sends EOF (#34). A socket is not a pipe, so -p /dev/stdin is false
    # and we fall through to the git diff fallback instead of blocking forever.
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
# Detect project scope (unless --all-scopes)
# ---------------------------------------------------------------------------
project_scope=""
if [[ "$ALL_SCOPES" == false ]]; then
    if [[ -n "$SCOPE_OVERRIDE" ]]; then
        project_scope="${SCOPE_OVERRIDE//,/ }"
    else
        detect_project_scope "${PROJECT_CLAUDE_MD:-}"
    fi
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
# run_lesson_checks <lessons_dir> <target_files...>
# Iterate lesson files in a directory, run syntactic checks against target files.
# Populates seen_violations associative array for dedup across directories.
# ---------------------------------------------------------------------------
run_lesson_checks() {
    local lessons_dir="$1"
    shift
    local target_files_all=("$@")

    local lfile=""
    for lfile in "$lessons_dir"/[0-9]*.md; do
        [[ -f "$lfile" ]] || continue
        parse_lesson "$lfile" || continue

        # Scope filtering: skip lessons that don't match this project
        if [[ "$ALL_SCOPES" == false ]]; then
            scope_matches "$lesson_scope" "$project_scope" || continue
        fi

        # Build list of target files that match this lesson's languages
        local matched_targets=()
        local local_f=""
        for local_f in "${target_files_all[@]}"; do
            file_matches_languages "$local_f" "$lesson_languages" && matched_targets+=("$local_f")
        done
        [[ ${#matched_targets[@]} -eq 0 ]] && continue

        # Run grep against matching files; format output as file:line: [lesson-N] title
        local local_id="$lesson_id"
        local local_title="$lesson_title"
        while IFS=: read -r matched_file lineno _rest; do
            [[ -z "$matched_file" ]] && continue
            local dedup_key="lesson-${local_id}:${matched_file}:${lineno}"
            [[ -n "${seen_violations[$dedup_key]+_}" ]] && continue
            seen_violations["$dedup_key"]=1
            echo "${matched_file}:${lineno}: [lesson-${local_id}] ${local_title}"
            ((violations++)) || true
        done < <(grep -EHn "$pattern_regex" "${matched_targets[@]}" 2>/dev/null || true)
    done
}

# ---------------------------------------------------------------------------
# Main loop: iterate lesson files, run syntactic checks
# ---------------------------------------------------------------------------
run_lesson_checks "$LESSONS_DIR" "${existing_files[@]}"

# Load project-local lessons (Tier 3)
if [[ -n "$PROJECT_LESSONS_DIR" ]]; then
    run_lesson_checks "$PROJECT_LESSONS_DIR" "${existing_files[@]}"
fi

# ---------------------------------------------------------------------------
# Enhancement: query lessons-db for additional coverage if available
# ---------------------------------------------------------------------------
if command -v lessons-db &>/dev/null && command -v jq &>/dev/null; then
    _ldb_args=()
    for _f in "${existing_files[@]}"; do
        _ldb_args+=("-f" "$_f")
    done
    _ldb_output=$(lessons-db check "${_ldb_args[@]}" --json 2>/dev/null) || true
    if [[ -n "$_ldb_output" && "$_ldb_output" != "[]" ]]; then
        while IFS= read -r entry; do
            _file=$(echo "$entry" | jq -r '.file_path')
            _line=$(echo "$entry" | jq -r '.line_number // 0')
            _id=$(echo "$entry" | jq -r '.lesson_id')
            _title=$(echo "$entry" | jq -r '.one_liner // .title')
            _dedup_key="lesson-${_id}:${_file}:${_line}"
            if [[ -z "${seen_violations[$_dedup_key]+_}" ]]; then
                echo "${_file}:${_line}: [lesson-${_id}] ${_title} (via lessons-db)"
                ((violations++)) || true
                seen_violations["$_dedup_key"]=1
            fi
        done < <(echo "$_ldb_output" | jq -c '.[]')
    fi
fi

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
