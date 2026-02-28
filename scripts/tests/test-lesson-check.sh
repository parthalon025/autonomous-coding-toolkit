#!/usr/bin/env bash
# Test lesson-check.sh — anti-pattern detector
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LESSON_CHECK="$SCRIPT_DIR/../lesson-check.sh"

FAILURES=0
TESTS=0

pass() {
    TESTS=$((TESTS + 1))
    echo "PASS: $1"
}

fail() {
    TESTS=$((TESTS + 1))
    echo "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

# --- Setup temp workspace ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- Test 1: Detects bare except in Python file (lesson 1, uses \s) ---
# Uses LESSON_CHECK_NO_DB=1 to test the markdown fallback path, which validates
# PCRE-to-ERE conversion (\s) and per-lesson ID numbering from markdown files.
cat > "$WORK/bad.py" <<'PY'
try:
    do_something()
except:
    pass
PY

# PROJECT_CLAUDE_MD=/dev/null isolates from toolkit's scope tags (language:bash would filter out python lessons)
# cd into $WORK so detect_project_type doesn't find toolkit's package.json and infer language:javascript
output=$(cd "$WORK" && PROJECT_CLAUDE_MD="/dev/null" LESSON_CHECK_NO_DB=1 bash "$LESSON_CHECK" "$WORK/bad.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-1\]'; then
    pass "Detects bare except in Python file (lesson 1, \\s ERE conversion)"
else
    fail "Should detect bare except in Python file, got: $output"
fi

# --- Test 2: Clean file passes ---
cat > "$WORK/good.py" <<'PY'
try:
    do_something()
except ValueError:
    pass
PY

output=$(PROJECT_CLAUDE_MD="/dev/null" LESSON_CHECK_NO_DB=1 bash "$LESSON_CHECK" "$WORK/good.py" 2>&1 || true)
if echo "$output" | grep -q 'clean'; then
    pass "Clean file reports clean"
else
    fail "Should report clean for good file, got: $output"
fi

# --- Test 3: PCRE shorthand \d works via ERE conversion (lesson 28, hardcoded IP) ---
# Uses LESSON_CHECK_NO_DB=1 to test the PCRE-to-ERE conversion path in lesson-check-lib.sh.
cat > "$WORK/bad_ip.js" <<'JS'
const url = "http://192.168.1.1/api";
JS

output=$(PROJECT_CLAUDE_MD="/dev/null" LESSON_CHECK_NO_DB=1 bash "$LESSON_CHECK" "$WORK/bad_ip.js" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-28\]'; then
    pass "PCRE \\d converted to ERE [0-9] detects hardcoded IPs"
else
    fail "Should detect hardcoded IP via lesson 28, got: $output"
fi

# --- Test 4: Language filtering — Python lesson skips .sh files ---
cat > "$WORK/not_python.sh" <<'SH'
except:
SH

output=$(PROJECT_CLAUDE_MD="/dev/null" LESSON_CHECK_NO_DB=1 bash "$LESSON_CHECK" "$WORK/not_python.sh" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-1\]'; then
    fail "Python-only lesson 1 should not match .sh files"
else
    pass "Python-only lesson correctly skips .sh files"
fi

# --- Test 5: --help works ---
output=$(bash "$LESSON_CHECK" --help 2>&1 || true)
if echo "$output" | grep -q 'Usage:'; then
    pass "--help shows usage"
else
    fail "--help should show usage, got: $output"
fi

# --- Test 6: No files to check (no args, no pipe, no git diff) ---
output=$(cd "$WORK" && bash "$LESSON_CHECK" 2>&1 || true)
if echo "$output" | grep -q 'no files to check'; then
    pass "No files gracefully reports nothing to check"
else
    fail "Should report no files to check, got: $output"
fi

# --- Test 6b: stdin pipe detection — uses -p /dev/stdin not -t 0 (#34) ---
# This prevents hanging when stdin is a socket (e.g. systemd/cron).
# The fix: only read stdin when [[ -p /dev/stdin ]] (a named pipe), not
# whenever [[ ! -t 0 ]] (which includes sockets that never send EOF).
TESTS=$((TESTS + 1))
if grep -q '\-p /dev/stdin' "$LESSON_CHECK"; then
    echo "PASS: lesson-check uses -p /dev/stdin (pipe-safe, not socket-blocking)"
else
    echo "FAIL: lesson-check should use [[ -p /dev/stdin ]] not [[ ! -t 0 ]] for stdin detection (bug #34)"
    FAILURES=$((FAILURES + 1))
fi

# Verify the old ! -t 0 pattern is NOT present in executable code (it caused the socket hang).
# Filter comment-only lines before checking.
TESTS=$((TESTS + 1))
if grep -v '^\s*#' "$LESSON_CHECK" | grep -q '! -t 0'; then
    echo "FAIL: lesson-check still uses '! -t 0' in executable code, which blocks on socket stdin (bug #34)"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: lesson-check does not use '! -t 0' in executable code (socket-safe)"
fi

# --- Test 7: No grep -P in any script (portability) ---
TESTS=$((TESTS + 1))
# Scan for grep -P or grep -<flags>P usage in scripts/ (excluding comments)
offenders=$(grep -rn 'grep -[a-zA-Z]*P' "$REPO_ROOT/scripts/" \
    --include='*.sh' \
    | grep -v 'test-lesson-check.sh' \
    | grep -v ':#' \
    | grep -v ':.*# .*grep' \
    || true)
if [[ -z "$offenders" ]]; then
    echo "PASS: No grep -P found in scripts/ (portability)"
else
    echo "FAIL: grep -P found in scripts/ — not portable to macOS:"
    echo "$offenders"
    FAILURES=$((FAILURES + 1))
fi

# --- Test 8: All scripts use #!/usr/bin/env bash shebang ---
TESTS=$((TESTS + 1))
bad_shebangs=""
while IFS= read -r script; do
    first_line=$(head -1 "$script")
    if [[ "$first_line" == "#!/bin/bash" ]]; then
        bad_shebangs+="  $script"$'\n'
    fi
done < <(find "$REPO_ROOT/scripts" -name '*.sh' -type f)
if [[ -z "$bad_shebangs" ]]; then
    echo "PASS: All scripts use #!/usr/bin/env bash"
else
    echo "FAIL: Scripts with non-portable #!/bin/bash shebang:"
    echo "$bad_shebangs"
    FAILURES=$((FAILURES + 1))
fi

# --- Test 9: Scope field parsed from lesson YAML ---
# Create a lesson with scope: [language:python] and verify it's respected
cat > "$WORK/0999-scoped-lesson.md" <<'LESSON'
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

output=$(cd "$WORK" && LESSONS_DIR="$WORK" LESSON_CHECK_NO_DB=1 bash "$LESSON_CHECK" "$WORK/scoped.py" 2>&1 || true)
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

output=$(cd "$WORK" && LESSONS_DIR="$WORK" LESSON_CHECK_NO_DB=1 PROJECT_CLAUDE_MD="$WORK/CLAUDE-noscope.md" bash "$LESSON_CHECK" "$WORK/scoped.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-999\]'; then
    fail "Scoped lesson should be SKIPPED when project scope doesn't match"
else
    pass "Scoped lesson correctly skipped for non-matching project scope"
fi

# --- Test 11: Lesson without scope defaults to universal (backward compat) ---
# Use the real lesson 1 (no scope field) — should still work as before.
# Uses LESSON_CHECK_NO_DB=1 to test the markdown fallback path's scope defaulting.
# Isolate from repo's own CLAUDE.md by pointing PROJECT_CLAUDE_MD to /dev/null
# cd into $WORK so detect_project_type doesn't find toolkit's package.json
output=$(cd "$WORK" && PROJECT_CLAUDE_MD="/dev/null" LESSON_CHECK_NO_DB=1 bash "$LESSON_CHECK" "$WORK/bad.py" 2>&1 || true)
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
cat > "$WORK/0998-ha-lesson.md" <<'LESSON'
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
output=$(cd "$WORK" && LESSONS_DIR="$WORK" LESSON_CHECK_NO_DB=1 bash "$LESSON_CHECK" "$WORK/ha_file.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-998\]'; then
    fail "domain:ha-aria lesson should be skipped on a python-only project"
else
    pass "domain:ha-aria lesson correctly skipped on non-matching project"
fi

# With --all-scopes: lesson 998 should fire
output=$(cd "$WORK" && LESSONS_DIR="$WORK" LESSON_CHECK_NO_DB=1 bash "$LESSON_CHECK" --all-scopes "$WORK/ha_file.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-998\]'; then
    pass "--all-scopes bypasses scope filtering"
else
    fail "--all-scopes should bypass scope filtering, got: $output"
fi

# --- Test 14: --scope override replaces CLAUDE.md detection ---
output=$(cd "$WORK" && LESSONS_DIR="$WORK" LESSON_CHECK_NO_DB=1 bash "$LESSON_CHECK" --scope "domain:ha-aria" "$WORK/ha_file.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-998\]'; then
    pass "--scope override enables matching for specified scope"
else
    fail "--scope override should enable domain:ha-aria matching, got: $output"
fi

# --- Test 15: PROJECT_ROOT loads project-local lessons ---
PROJECT_WORK=$(mktemp -d)
mkdir -p "$PROJECT_WORK/docs/lessons"

# Create a project-local lesson
cat > "$PROJECT_WORK/docs/lessons/0001-project-local-test.md" <<'LESSON'
---
id: 8001
title: "Project-local test pattern"
severity: should-fix
languages: [python]
scope: [universal]
category: test
pattern:
  type: syntactic
  regex: "project_local_marker_xyzzy"
---
LESSON

# Create a Python file with the marker
cat > "$PROJECT_WORK/target.py" <<'PY'
project_local_marker_xyzzy = True
PY

output=$(cd "$PROJECT_WORK" && PROJECT_ROOT="$PROJECT_WORK" PROJECT_CLAUDE_MD="/dev/null" LESSON_CHECK_NO_DB=1 bash "$LESSON_CHECK" "$PROJECT_WORK/target.py" 2>&1 || true)
if echo "$output" | grep -q '\[lesson-8001\]'; then
    pass "PROJECT_ROOT loads project-local lessons (Tier 3)"
else
    fail "PROJECT_ROOT should load project-local lessons, got: $output"
fi
rm -rf "$PROJECT_WORK"

# --- Test 16: seen_violations dedup prevents duplicate reports ---
DEDUP_WORK=$(mktemp -d)
mkdir -p "$DEDUP_WORK/docs/lessons"

# Create a lesson in both bundled and project-local dirs that would match
cat > "$DEDUP_WORK/0001-dedup-test.md" <<'LESSON'
---
id: 9001
title: "Dedup test pattern"
severity: should-fix
languages: [python]
scope: [universal]
category: test
pattern:
  type: syntactic
  regex: "dedup_test_marker"
---
LESSON

cp "$DEDUP_WORK/0001-dedup-test.md" "$DEDUP_WORK/docs/lessons/0001-dedup-test.md"

cat > "$DEDUP_WORK/target.py" <<'PY'
dedup_test_marker = True
PY

# Use same dir for LESSONS_DIR and PROJECT_ROOT so both loops scan the same lesson
output=$(cd "$DEDUP_WORK" && LESSONS_DIR="$DEDUP_WORK" PROJECT_ROOT="$DEDUP_WORK" PROJECT_CLAUDE_MD="/dev/null" LESSON_CHECK_NO_DB=1 bash "$LESSON_CHECK" "$DEDUP_WORK/target.py" 2>&1 || true)
# Count how many times the violation appears — should be exactly 1 due to dedup
match_count=$(echo "$output" | grep -c '\[lesson-9001\]' || true)
if [[ "$match_count" -eq 1 ]]; then
    pass "seen_violations dedup prevents duplicate violation reports"
else
    fail "Expected exactly 1 violation report for dedup, got $match_count: $output"
fi
rm -rf "$DEDUP_WORK"

# --- Test 17: lessons-db block skipped when lessons-db not on PATH ---
# Create a wrapper script that shadows lessons-db with a nonexistent path.
# Output should be identical to standalone behavior (no "via lessons-db" lines).
LDB_WORK=$(mktemp -d)
cat > "$LDB_WORK/bad.py" <<'PY'
try:
    do_something()
except:
    pass
PY

# Build a PATH that excludes the directory containing lessons-db
_ldb_dir=$(dirname "$(command -v lessons-db 2>/dev/null)" 2>/dev/null || echo "")
_filtered_path="$PATH"
if [[ -n "$_ldb_dir" ]]; then
    _filtered_path=$(echo "$PATH" | tr ':' '\n' | grep -vxF "$_ldb_dir" | tr '\n' ':')
    _filtered_path="${_filtered_path%:}"  # trim trailing colon
fi

output_no_ldb=$(cd "$LDB_WORK" && PATH="$_filtered_path" PROJECT_CLAUDE_MD="/dev/null" bash "$LESSON_CHECK" "$LDB_WORK/bad.py" 2>&1 || true)
if echo "$output_no_ldb" | grep -q 'via lessons-db'; then
    fail "lessons-db block should be skipped when lessons-db not on PATH"
else
    pass "lessons-db block skipped when lessons-db not on PATH"
fi
rm -rf "$LDB_WORK"

# --- Test 18: lessons-db block requires both lessons-db AND jq ---
# Verify the source code checks for both commands
TESTS=$((TESTS + 1))
if grep -q 'command -v lessons-db' "$LESSON_CHECK" && grep -q 'command -v jq' "$LESSON_CHECK"; then
    echo "PASS: lessons-db block guards on both lessons-db and jq availability"
else
    echo "FAIL: lessons-db block should check for both lessons-db and jq"
    FAILURES=$((FAILURES + 1))
fi

# --- Summary ---
echo ""
echo "lesson-check tests: $TESTS run, $((TESTS - FAILURES)) passed, $FAILURES failed"

if [[ $FAILURES -gt 0 ]]; then
    exit 1
fi
exit 0
