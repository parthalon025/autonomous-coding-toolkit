#!/usr/bin/env bash
# Test prompt builder functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-parser.sh"
source "$SCRIPT_DIR/../lib/run-plan-prompt.sh"

FAILURES=0
TESTS=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        echo "  in: ${haystack:0:300}..."
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "FAIL: $desc"
        echo "  expected NOT to contain: $needle"
        echo "  in: ${haystack:0:300}..."
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

# --- Setup: fixture plan + temp git worktree ---
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

FIXTURE="$TMPDIR_ROOT/plan.md"
cat > "$FIXTURE" << 'EOF'
# Feature X Implementation Plan

**Goal:** Build feature X

---

## Batch 1: Foundation (Tasks 1-2)

### Task 1: Create Data Model

**Files:**
- Create: `src/models.py`
- Test: `tests/test_models.py`

**Step 1: Write the failing test**

```python
def test_model():
    m = Model("test")
    assert m.name == "test"
```

**Step 2: Implement**

Create the Model class.

### Task 2: Add Validation

**Files:**
- Modify: `src/models.py`

Add validation to Model.

## Batch 2: Integration (Tasks 3-4)

### Task 3: Wire Together

Wire the models into the API.

### Task 4: End-to-End Test

Write integration test.
EOF

# Create a temp git repo so git branch works
WORKTREE="$TMPDIR_ROOT/worktree"
mkdir -p "$WORKTREE"
git -C "$WORKTREE" init -b test-branch --quiet
git -C "$WORKTREE" config user.email "test@test.com"
git -C "$WORKTREE" config user.name "Test"
touch "$WORKTREE/.gitkeep"
git -C "$WORKTREE" add .gitkeep
git -C "$WORKTREE" commit -m "init" --quiet

# --- Test: build_batch_prompt for batch 1 ---
prompt=$(build_batch_prompt "$FIXTURE" 1 "$WORKTREE" "/usr/bin/python3" "scripts/quality-gate.sh --project-root ." 0)

assert_contains "has batch number" "Batch 1" "$prompt"
assert_contains "has batch title" "Foundation (Tasks 1-2)" "$prompt"
assert_contains "has plan file reference" "plan.md" "$prompt"
assert_contains "has worktree path" "$WORKTREE" "$prompt"
assert_contains "has python path" "/usr/bin/python3" "$prompt"
assert_contains "has branch name" "test-branch" "$prompt"
assert_contains "has task text - Task 1" "Task 1: Create Data Model" "$prompt"
assert_contains "has task text - Task 2" "Task 2: Add Validation" "$prompt"
assert_contains "has TDD instruction" "TDD" "$prompt"
assert_contains "has quality gate command" "scripts/quality-gate.sh --project-root ." "$prompt"
assert_contains "has previous test count" "0+" "$prompt"
assert_contains "has progress.txt instruction" "progress.txt" "$prompt"

# --- Test: build_batch_prompt for batch 2 ---
prompt2=$(build_batch_prompt "$FIXTURE" 2 "$WORKTREE" "/opt/python3.12" "make test" 15)

assert_contains "batch 2 has batch number" "Batch 2" "$prompt2"
assert_contains "batch 2 has batch title" "Integration (Tasks 3-4)" "$prompt2"
assert_contains "batch 2 has task text - Task 3" "Task 3: Wire Together" "$prompt2"
assert_contains "batch 2 has task text - Task 4" "Task 4: End-to-End Test" "$prompt2"
assert_contains "batch 2 has different python" "/opt/python3.12" "$prompt2"
assert_contains "batch 2 has different quality gate" "make test" "$prompt2"
assert_contains "batch 2 has prev test count" "15+" "$prompt2"

# --- Test: batch 2 does NOT contain batch 1 tasks ---
TESTS=$((TESTS + 1))
if [[ "$prompt2" == *"Create Data Model"* ]]; then
    echo "FAIL: batch 2 prompt should not contain batch 1 tasks"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: batch 2 prompt does not leak batch 1 tasks"
fi

# =============================================================================
# build_stable_prefix tests
# =============================================================================

stable=$(build_stable_prefix "$FIXTURE" "$WORKTREE" "/usr/bin/python3" "scripts/quality-gate.sh")

assert_contains "stable prefix has worktree path" "$WORKTREE" "$stable"
assert_contains "stable prefix has python path" "/usr/bin/python3" "$stable"
assert_contains "stable prefix has branch name" "test-branch" "$stable"
assert_contains "stable prefix has TDD rule" "TDD" "$stable"
assert_contains "stable prefix has quality gate" "scripts/quality-gate.sh" "$stable"
assert_contains "stable prefix has progress.txt rule" "progress.txt" "$stable"

# #48: stable prefix must NOT contain prev_test_count — that belongs in variable suffix
assert_not_contains "stable prefix does NOT contain test count line" "tests must pass" "$stable"

# --- Test: build_stable_prefix with bad worktree emits warning but returns 'unknown' ---
TESTS=$((TESTS + 1))
bad_worktree_output=$(build_stable_prefix "$FIXTURE" "/nonexistent/path/xyz" "python3" "gate.sh" 2>&1)
if [[ "$bad_worktree_output" == *"WARNING"* && "$bad_worktree_output" == *"unknown"* ]]; then
    echo "PASS: build_stable_prefix warns on missing worktree and uses 'unknown' branch"
else
    echo "FAIL: build_stable_prefix should warn on missing worktree"
    echo "  output: $bad_worktree_output"
    FAILURES=$((FAILURES + 1))
fi

# =============================================================================
# build_variable_suffix tests
# =============================================================================

suffix=$(build_variable_suffix "$FIXTURE" 1 "$WORKTREE" 7)

assert_contains "variable suffix has batch number" "Batch 1" "$suffix"
assert_contains "variable suffix has batch title" "Foundation" "$suffix"
assert_contains "variable suffix has task text" "Task 1: Create Data Model" "$suffix"
# #48: test count is in the variable suffix, not the stable prefix
assert_contains "variable suffix has test count" "7+" "$suffix"

# Different test count gives different suffix (confirms test count varies per batch)
suffix_b2=$(build_variable_suffix "$FIXTURE" 2 "$WORKTREE" 20)
assert_contains "variable suffix b2 has test count 20+" "20+" "$suffix_b2"

# =============================================================================
# Cross-batch context tests
# =============================================================================

# --- Setup: add progress.txt and a commit to the worktree ---
echo "Batch 1: Implemented auth module" > "$WORKTREE/progress.txt"
echo "code" > "$WORKTREE/code.py"
git -C "$WORKTREE" add code.py progress.txt
git -C "$WORKTREE" commit -q -m "feat: add auth"

# --- Test: prompt includes recent commits ---
prompt3=$(build_batch_prompt "$FIXTURE" 2 "$WORKTREE" "python3" "scripts/quality-gate.sh" 42)
assert_contains "cross-batch: has Recent commits" "Recent commits" "$prompt3"

# --- Test: prompt includes progress.txt content ---
assert_contains "cross-batch: has Previous progress" "Previous progress" "$prompt3"
assert_contains "cross-batch: has progress content" "Implemented auth module" "$prompt3"

# --- Test: prompt includes commit message ---
assert_contains "cross-batch: has commit in log" "feat: add auth" "$prompt3"

# =============================================================================
# #47: corrupted state file — jq failure emits warning, prev_gate stays empty
# =============================================================================

echo "NOT VALID JSON {{{" > "$WORKTREE/.run-plan-state.json"
TESTS=$((TESTS + 1))
jq_warn_output=$(build_variable_suffix "$FIXTURE" 2 "$WORKTREE" 0 2>&1)
if [[ "$jq_warn_output" == *"WARNING"* && "$jq_warn_output" == *"corrupted"* ]]; then
    echo "PASS: build_variable_suffix warns on corrupted state file"
else
    echo "FAIL: build_variable_suffix should warn on corrupted state file"
    echo "  output: ${jq_warn_output:0:200}"
    FAILURES=$((FAILURES + 1))
fi
# Clean up corrupted state file
rm -f "$WORKTREE/.run-plan-state.json"

# =============================================================================
# #50: unreadable progress.txt — error is NOT silently swallowed (no 2>/dev/null || true)
# The fix removes the error suppression so stderr shows the permission denial.
# We verify by running tail directly under the same condition — the error must be visible.
# (Command substitution $() cannot propagate exit codes from within sourced functions
#  reliably across bash versions, so we test the absence of suppression via the source.)
# =============================================================================

TESTS=$((TESTS + 1))
# Check that progress_tail assignment in build_variable_suffix does NOT use || true
# by inspecting the source code — the fix is the removal of the error suppression.
PROMPT_SRC="$SCRIPT_DIR/../lib/run-plan-prompt.sh"
if grep -q 'tail.*progress\.txt.*|| true' "$PROMPT_SRC" 2>/dev/null || \
   grep -q 'tail.*progress\.txt.*2>/dev/null.*|| true' "$PROMPT_SRC" 2>/dev/null; then
    echo "FAIL: build_variable_suffix still has suppressed tail error (|| true present)"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: build_variable_suffix does not suppress tail errors on progress.txt"
fi

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
