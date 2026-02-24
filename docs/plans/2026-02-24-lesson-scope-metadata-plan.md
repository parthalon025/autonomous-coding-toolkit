# Lesson Scope Metadata Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add project-level scope filtering to lesson-check.sh so domain-specific lessons (HA, Telegram, etc.) only fire on relevant projects, reducing false positives as lesson count grows past 100.

**Architecture:** lesson-check.sh gains a `scope:` field in YAML frontmatter (demand side) and reads `## Scope Tags` from the project's CLAUDE.md (supply side). A new `scope_matches()` function gates lessons before the existing language/grep check. A new `scope-infer.sh` script handles bulk tagging of existing lessons.

**Tech Stack:** Bash, YAML frontmatter parsing, grep, jq (none — pure bash)

---

## Batch 1: Scope Parsing & Matching (Core Engine)

### Task 1: Add scope parsing tests to test-lesson-check.sh

**Files:**
- Modify: `scripts/tests/test-lesson-check.sh`

**Step 1: Write failing tests for scope field parsing**

Add these tests after the existing Test 8 block (before the Summary section at line 153):

```bash
# --- Test 9: Scope field parsed from lesson YAML ---
# Create a lesson with scope: [language:python] and verify it's respected
cat > "$WORK/scoped-lesson.md" <<'LESSON'
---
id: 999
title: "Test scoped lesson"
severity: should-fix
scope: [language:python]
languages: [python]
category: silent-failures
pattern:
  type: syntactic
  regex: "test_scope_marker"
  description: "test marker"
fix: "test"
---
LESSON

# Create a CLAUDE.md with scope tags
cat > "$WORK/CLAUDE.md" <<'CMD'
# Test Project

## Scope Tags
language:python, framework:pytest
CMD

# Python file with the marker — should be detected (scope matches)
cat > "$WORK/scoped.py" <<'PY'
test_scope_marker = True
PY

output=$(cd "$WORK" && LESSONS_DIR="$WORK" bash "$LESSON_CHECK" "$WORK/scoped.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-999\]'; then
    pass "Scoped lesson detected when project scope matches"
else
    fail "Scoped lesson should detect violation when project scope matches, got: $output"
fi

# --- Test 10: Scoped lesson skipped when project scope doesn't match ---
cat > "$WORK/CLAUDE-noscope.md" <<'CMD'
# Different Project

## Scope Tags
domain:ha-aria
CMD

output=$(cd "$WORK" && LESSONS_DIR="$WORK" PROJECT_CLAUDE_MD="$WORK/CLAUDE-noscope.md" bash "$LESSON_CHECK" "$WORK/scoped.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-999\]'; then
    fail "Scoped lesson should be SKIPPED when project scope doesn't match"
else
    pass "Scoped lesson correctly skipped for non-matching project scope"
fi

# --- Test 11: Lesson without scope defaults to universal (backward compat) ---
# Use the real lesson 1 (no scope field) — should still work as before
output=$(bash "$LESSON_CHECK" "$WORK/bad.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-1\]'; then
    pass "Lesson without scope: field defaults to universal (backward compatible)"
else
    fail "Missing scope: should default to universal, got: $output"
fi

# --- Test 12: --show-scope displays detected project scope ---
output=$(cd "$WORK" && bash "$LESSON_CHECK" --show-scope 2>&1 || true)
if echo "$output" | grep -q 'language:python'; then
    pass "--show-scope displays detected project scope"
else
    fail "--show-scope should display detected scope from CLAUDE.md, got: $output"
fi

# --- Test 13: --all-scopes bypasses scope filtering ---
# Use a lesson scoped to domain:ha-aria on a python project — should be skipped normally
cat > "$WORK/ha-lesson.md" <<'LESSON'
---
id: 998
title: "HA-only test lesson"
severity: should-fix
scope: [domain:ha-aria]
languages: [python]
category: silent-failures
pattern:
  type: syntactic
  regex: "ha_scope_marker"
  description: "test marker"
fix: "test"
---
LESSON

cat > "$WORK/ha_file.py" <<'PY'
ha_scope_marker = True
PY

# Without --all-scopes: lesson 998 should be skipped (project is python, not ha-aria)
output=$(cd "$WORK" && LESSONS_DIR="$WORK" bash "$LESSON_CHECK" "$WORK/ha_file.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-998\]'; then
    fail "domain:ha-aria lesson should be skipped on a python-only project"
else
    pass "domain:ha-aria lesson correctly skipped on non-matching project"
fi

# With --all-scopes: lesson 998 should fire
output=$(cd "$WORK" && LESSONS_DIR="$WORK" bash "$LESSON_CHECK" --all-scopes "$WORK/ha_file.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-998\]'; then
    pass "--all-scopes bypasses scope filtering"
else
    fail "--all-scopes should bypass scope filtering, got: $output"
fi

# --- Test 14: --scope override replaces CLAUDE.md detection ---
output=$(cd "$WORK" && LESSONS_DIR="$WORK" bash "$LESSON_CHECK" --scope "domain:ha-aria" "$WORK/ha_file.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-998\]'; then
    pass "--scope override enables matching for specified scope"
else
    fail "--scope override should enable domain:ha-aria matching, got: $output"
fi
```

**Step 2: Run tests to verify they fail**

Run: `bash scripts/tests/test-lesson-check.sh`
Expected: Tests 9-14 FAIL (scope features not yet implemented)

**Step 3: Commit test file**

```bash
git add scripts/tests/test-lesson-check.sh
git commit -m "test: add scope filtering tests for lesson-check.sh (red)"
```

---

### Task 2: Add scope parsing to parse_lesson()

**Files:**
- Modify: `scripts/lesson-check.sh:17-88` (parse_lesson function)

**Step 1: Add lesson_scope variable initialization and parsing**

In `parse_lesson()`, add `lesson_scope=""` after the existing `lesson_languages=""` (line 24), then add a parsing case in the top-level fields block (after the `languages:` elif on line 52):

```bash
# Add after line 24:
lesson_scope=""

# Add after the languages elif block (after line 57):
elif [[ "$line" =~ ^scope:[[:space:]]+(.*) ]]; then
    lesson_scope="${BASH_REMATCH[1]}"
    lesson_scope="${lesson_scope//[\[\]]/}"
    lesson_scope="${lesson_scope//,/ }"
    lesson_scope="${lesson_scope## }"
    lesson_scope="${lesson_scope%% }"
```

The parsing follows the exact same pattern as `lesson_languages` — strip brackets, replace commas with spaces, trim.

**Default when missing:** After the `return 1` checks at lines 76-77, add:

```bash
# Default scope to universal when omitted (backward compatible)
[[ -z "$lesson_scope" ]] && lesson_scope="universal"
```

**Step 2: Run existing tests to verify no regression**

Run: `bash scripts/tests/test-lesson-check.sh`
Expected: Tests 1-8 still pass, tests 9-14 still fail (matching not implemented yet)

**Step 3: Commit**

```bash
git add scripts/lesson-check.sh
git commit -m "feat: parse scope: field from lesson YAML frontmatter"
```

---

### Task 3: Add detect_project_scope() and scope_matches()

**Files:**
- Modify: `scripts/lesson-check.sh` (add two new functions after file_matches_languages)

**Step 1: Add detect_project_scope()**

Insert after `file_matches_languages()` (after line 183):

```bash
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
```

**Step 2: Run tests**

Run: `bash scripts/tests/test-lesson-check.sh`
Expected: Tests 1-8 pass, tests 9-14 still fail (gate not wired in main loop yet)

**Step 3: Commit**

```bash
git add scripts/lesson-check.sh
git commit -m "feat: add detect_project_scope() and scope_matches() functions"
```

---

### Task 4: Wire scope filtering into main loop and CLI flags

**Files:**
- Modify: `scripts/lesson-check.sh` (CLI parsing, main loop gate, --help)

**Step 1: Add CLI flag parsing**

Replace the existing `--help` check block (lines 118-121) with expanded flag parsing:

```bash
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
        --scope) SCOPE_OVERRIDE="$2"; shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
set -- "${args[@]+"${args[@]}"}"
```

**Step 2: Add scope detection before main loop**

After the `existing_files` check (after line 160), add:

```bash
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

if [[ "$SHOW_SCOPE" == true ]]; then
    if [[ -n "$project_scope" ]]; then
        echo "Detected project scope: $project_scope"
    else
        echo "No project scope detected (all lessons will apply)"
    fi
    exit 0
fi
```

**Step 3: Add scope gate in main loop**

In the main loop (line 191: `parse_lesson "$lfile" || continue`), add the scope check right after:

```bash
    parse_lesson "$lfile" || continue

    # Scope filtering: skip lessons that don't match this project
    if [[ "$ALL_SCOPES" == false ]]; then
        scope_matches "$lesson_scope" "$project_scope" || continue
    fi
```

**Step 4: Update build_help() to show scope**

In `build_help()`, update the checks_text line (line 101) to include scope:

```bash
            local scope_display="$lesson_scope"
            checks_text+="  [lesson-${lesson_id}]  ${lesson_title} (${lang_display}) [scope: ${scope_display}]"$'\n'
```

And add scope flags to the usage text:

```bash
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
```

**Step 5: Run all tests**

Run: `bash scripts/tests/test-lesson-check.sh`
Expected: All tests 1-14 PASS

**Step 6: Commit**

```bash
git add scripts/lesson-check.sh
git commit -m "feat: wire scope filtering into lesson-check main loop with CLI flags"
```

---

## Batch 2: Scope Inference Script & Template Update

### Task 5: Write test-scope-infer.sh

**Files:**
- Create: `scripts/tests/test-scope-infer.sh`

**Step 1: Write test file**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

INFER="$SCRIPT_DIR/../scope-infer.sh"

# --- Test: --help exits 0 ---
assert_exit "--help exits 0" 0 "$INFER" --help

# --- Test: --dry-run shows proposed scope without modifying files ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Create a lesson with no scope field, mentioning "HA" and "entity"
cat > "$WORK/0099-test-ha-lesson.md" <<'LESSON'
---
id: 99
title: "HA entity resolution fails on restart"
severity: should-fix
languages: [python]
category: data-model
pattern:
  type: semantic
  description: "HA entity lookup returns stale area"
fix: "Refresh entity registry on restart"
---

## Observation
Home Assistant entity area resolution uses a cached registry.
LESSON

dry_output=$("$INFER" --dir "$WORK" --dry-run 2>&1 || true)
assert_contains "--dry-run mentions ha-aria" "domain:ha-aria" "$dry_output"

# Verify file was NOT modified (dry run)
TESTS=$((TESTS + 1))
if grep -q '^scope:' "$WORK/0099-test-ha-lesson.md" 2>/dev/null; then
    echo "FAIL: --dry-run should not modify lesson files"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: --dry-run does not modify lesson files"
fi

# --- Test: --apply writes scope field to lesson ---
"$INFER" --dir "$WORK" --apply > /dev/null 2>&1 || true

TESTS=$((TESTS + 1))
if grep -q '^scope:' "$WORK/0099-test-ha-lesson.md" 2>/dev/null; then
    echo "PASS: --apply writes scope field to lesson"
else
    echo "FAIL: --apply should write scope field to lesson"
    FAILURES=$((FAILURES + 1))
fi

# Verify inferred scope is correct
scope_line=$(grep '^scope:' "$WORK/0099-test-ha-lesson.md" 2>/dev/null || true)
assert_contains "--apply infers domain:ha-aria" "domain:ha-aria" "$scope_line"

# --- Test: Lesson with existing scope is not modified ---
cat > "$WORK/0098-already-scoped.md" <<'LESSON'
---
id: 98
title: "Already scoped lesson"
severity: should-fix
scope: [language:python]
languages: [python]
category: silent-failures
pattern:
  type: semantic
  description: "test"
fix: "test"
---
LESSON

apply_output=$("$INFER" --dir "$WORK" --apply 2>&1 || true)
scope_line=$(grep '^scope:' "$WORK/0098-already-scoped.md" 2>/dev/null || true)
assert_contains "existing scope preserved" "language:python" "$scope_line"

# --- Test: Python-only lesson with no domain signals → language:python ---
cat > "$WORK/0097-python-only.md" <<'LESSON'
---
id: 97
title: "Generic Python anti-pattern"
severity: should-fix
languages: [python]
category: async-traps
pattern:
  type: syntactic
  regex: "some_pattern"
  description: "test"
fix: "test"
---

## Observation
This is a generic Python lesson with no domain signals.
LESSON

"$INFER" --dir "$WORK" --apply > /dev/null 2>&1 || true
scope_line=$(grep '^scope:' "$WORK/0097-python-only.md" 2>/dev/null || true)
assert_contains "python-only → language:python" "language:python" "$scope_line"

# --- Test: No signals → universal ---
cat > "$WORK/0096-universal.md" <<'LESSON'
---
id: 96
title: "Generic coding practice"
severity: nice-to-have
languages: [all]
category: test-anti-patterns
pattern:
  type: syntactic
  regex: "some_other_pattern"
  description: "test"
fix: "test"
---

## Observation
This applies to all projects everywhere.
LESSON

"$INFER" --dir "$WORK" --apply > /dev/null 2>&1 || true
scope_line=$(grep '^scope:' "$WORK/0096-universal.md" 2>/dev/null || true)
assert_contains "no signals → universal" "universal" "$scope_line"

# --- Test: Summary output shows counts ---
WORK2=$(mktemp -d)
trap 'rm -rf "$WORK" "$WORK2"' EXIT

cat > "$WORK2/0001-test.md" <<'LESSON'
---
id: 1
title: "Test lesson"
severity: should-fix
languages: [python]
category: silent-failures
pattern:
  type: syntactic
  regex: "test"
  description: "test"
fix: "test"
---
Generic content.
LESSON

summary_output=$("$INFER" --dir "$WORK2" --dry-run 2>&1 || true)
assert_contains "summary shows count" "Inferred scope for" "$summary_output"

report_results
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-scope-infer.sh`
Expected: FAIL (script doesn't exist yet)

**Step 3: Commit**

```bash
git add scripts/tests/test-scope-infer.sh
git commit -m "test: add scope-infer.sh tests (red)"
```

---

### Task 6: Implement scope-infer.sh

**Files:**
- Create: `scripts/scope-infer.sh`

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
# scope-infer.sh — Infer scope tags for lessons missing them
# Reads lesson content and applies heuristics to propose scope tags.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    if echo "$title_and_body" | grep -qE '(home assistant|\\bha\\b|entity.*area|automation.*trigger|hass|ha-aria)'; then
        echo "domain:ha-aria"
        return
    fi

    # Domain: telegram
    if echo "$title_and_body" | grep -qE '(telegram|bot.*poll|getupdates|chat_id|telegram-brief|telegram-capture)'; then
        echo "domain:telegram"
        return
    fi

    # Domain: notion
    if echo "$title_and_body" | grep -qE '(\\bnotion\\b|notion.*sync|notion.*database|notion-tools|notion_api)'; then
        echo "domain:notion"
        return
    fi

    # Domain: ollama
    if echo "$title_and_body" | grep -qE '(\\bollama\\b|ollama.*queue|local.*llm|ollama-queue)'; then
        echo "domain:ollama"
        return
    fi

    # Framework: systemd
    if echo "$title_and_body" | grep -qE '(systemd|systemctl|\.service|\.timer|journalctl|envfile)'; then
        echo "framework:systemd"
        return
    fi

    # Framework: pytest
    if echo "$title_and_body" | grep -qE '(\\bpytest\\b|conftest|fixture|parametrize)'; then
        echo "framework:pytest"
        return
    fi

    # Framework: preact/jsx
    if echo "$title_and_body" | grep -qE '(\\bpreact\\b|\\bjsx\\b|esbuild.*jsx|jsx.*factory)'; then
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
```

**Step 2: Make executable**

```bash
chmod +x scripts/scope-infer.sh
```

**Step 3: Run tests**

Run: `bash scripts/tests/test-scope-infer.sh`
Expected: ALL PASS

**Step 4: Commit**

```bash
git add scripts/scope-infer.sh scripts/tests/test-scope-infer.sh
git commit -m "feat: add scope-infer.sh for bulk scope tagging of lessons"
```

---

### Task 7: Update TEMPLATE.md with scope field

**Files:**
- Modify: `docs/lessons/TEMPLATE.md`

**Step 1: Add scope field to the template**

Insert the `scope:` field after `languages:` in the YAML block. The template should show it as optional with a comment:

```yaml
languages: [<python|javascript|typescript|shell|all>]
scope: [<universal|language:X|framework:X|domain:X|project:X>]  # optional, defaults to universal
```

**Step 2: Add scope to the Field Guide**

Add a new section after Categories:

```markdown
### Scope (Project-Level Filtering)
Scope controls which projects a lesson applies to. Language filtering (`languages:`) picks files; scope filtering picks projects. Both are orthogonal.

| Tag Format | Example | Matches |
|------------|---------|---------|
| `universal` | `[universal]` | All projects (default) |
| `language:<lang>` | `[language:python]` | Projects with that language |
| `framework:<name>` | `[framework:pytest]` | Projects using that framework |
| `domain:<name>` | `[domain:ha-aria]` | Domain-specific projects |
| `project:<name>` | `[project:autonomous-coding-toolkit]` | Exact project match |

Default when omitted: `[universal]` — backward compatible.
```

**Step 3: Run existing tests to verify no regression**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: All tests pass

**Step 4: Commit**

```bash
git add docs/lessons/TEMPLATE.md
git commit -m "docs: add scope field to lesson TEMPLATE.md"
```

---

## Batch 3: Apply Scope Tags to Existing Lessons

### Task 8: Run scope-infer.sh --dry-run and review

**Step 1: Run dry-run**

```bash
bash scripts/scope-infer.sh --dir docs/lessons --dry-run
```

Expected: See proposed scope for all 67 lessons. Review the output to verify heuristics are reasonable.

**Step 2: Fix any obvious misclassifications**

If a lesson is proposed with the wrong scope, either:
- Adjust the heuristics in `scope-infer.sh`, OR
- Plan to manually fix after --apply

**Step 3: No commit (review only)**

---

### Task 9: Apply scope tags to the first 10 lessons manually

Apply the scope assignments from the design doc for lessons 0001-0010. These were manually reviewed.

**Files:**
- Modify: `docs/lessons/0001-bare-exception-swallowing.md` through `docs/lessons/0010-local-outside-function-bash.md`

**Step 1: Add scope field to each lesson**

For each file, insert `scope: [<value>]` after the `languages:` line in the YAML frontmatter:

| File | Scope to add |
|------|-------------|
| `0001-bare-exception-swallowing.md` | `scope: [language:python]` |
| `0002-async-def-without-await.md` | `scope: [language:python]` |
| `0003-create-task-without-callback.md` | `scope: [language:python]` |
| `0004-hardcoded-test-counts.md` | `scope: [universal]` |
| `0005-sqlite-without-closing.md` | `scope: [language:python]` |
| `0006-venv-pip-path.md` | `scope: [language:python, framework:pytest]` |
| `0007-runner-state-self-rejection.md` | `scope: [project:autonomous-coding-toolkit]` |
| `0008-quality-gate-blind-spot.md` | `scope: [project:autonomous-coding-toolkit]` |
| `0009-parser-overcount-empty-batches.md` | `scope: [project:autonomous-coding-toolkit]` |
| `0010-local-outside-function-bash.md` | `scope: [language:bash]` |

**Step 2: Run scope-infer.sh --apply for remaining lessons**

```bash
bash scripts/scope-infer.sh --dir docs/lessons --apply
```

This will add scope to lessons 0011-0067 (the first 10 already have scope and will be skipped).

**Step 3: Run full test suite**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: All tests pass (scope field is backward-compatible)

**Step 4: Commit**

```bash
git add docs/lessons/
git commit -m "feat: add scope tags to all 67 toolkit lessons"
```

---

### Task 10: Run full test suite and verify

**Step 1: Run all tests**

```bash
bash scripts/tests/run-all-tests.sh
```

Expected: All test files pass, including the new scope tests.

**Step 2: Test behavioral scenarios**

```bash
# From the toolkit root:
cd /path/to/autonomous-coding-toolkit
bash scripts/lesson-check.sh --show-scope

# Should show the toolkit's scope tags from CLAUDE.md
# (If no ## Scope Tags section exists yet, it will fall back to language detection)

# Test with --all-scopes
bash scripts/lesson-check.sh --all-scopes scripts/lesson-check.sh
```

**Step 3: Final commit if needed**

```bash
git add -A
git commit -m "chore: Phase 5A scope metadata implementation complete"
```

---

## Summary

| Batch | Tasks | What it delivers |
|-------|-------|-----------------|
| 1 | Tasks 1-4 | Core scope engine: parsing, matching, CLI flags, filtering gate |
| 2 | Tasks 5-7 | Scope inference script + template update |
| 3 | Tasks 8-10 | Apply scope tags to all 67 lessons + full verification |

**Out of scope for this plan (deferred):**
- Lesson-scanner agent updates (workspace lessons — separate plan)
- `/capture-lesson` skill integration (scope inference at creation time)
- Propagation tracking (`validated_in` field)
- Workspace lessons bulk tagging (76 files in ~/Documents/docs/lessons/)

These are listed in the design doc and can be planned as follow-on batches.
