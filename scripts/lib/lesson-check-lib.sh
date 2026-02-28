#!/usr/bin/env bash
# lesson-check-lib.sh — Shared functions for lesson-check.sh
# Pure function library — no side effects on source.
# Depends on: $SCRIPT_DIR (set by caller)

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
    lesson_positive_alternative=""

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
            elif [[ "$line" =~ ^positive_alternative:[[:space:]]+(.*) ]]; then
                lesson_positive_alternative="${BASH_REMATCH[1]}"
                lesson_positive_alternative="${lesson_positive_alternative#\"}"
                lesson_positive_alternative="${lesson_positive_alternative%\"}"
                lesson_positive_alternative="${lesson_positive_alternative#\'}"
                lesson_positive_alternative="${lesson_positive_alternative%\'}"
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
# file_matches_languages <filepath> <languages>
# Returns 1 (mismatch) if the file doesn't match the lesson's languages.
# ---------------------------------------------------------------------------
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
