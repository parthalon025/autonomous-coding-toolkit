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
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_before() {
    local desc="$1" first="$2" second="$3" haystack="$4"
    TESTS=$((TESTS + 1))
    local pos_first pos_second
    # Find byte offset of first occurrence of each string
    pos_first=$(echo "$haystack" | grep -bo "$first" 2>/dev/null | head -1 | cut -d: -f1)
    pos_second=$(echo "$haystack" | grep -bo "$second" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -z "$pos_first" || -z "$pos_second" ]]; then
        echo "FAIL: $desc (one or both strings not found)"
        FAILURES=$((FAILURES + 1))
    elif [[ "$pos_first" -lt "$pos_second" ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc ('$first' at $pos_first, '$second' at $pos_second)"
        FAILURES=$((FAILURES + 1))
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

# =============================================================================
# XML structure tests
# =============================================================================

prompt=$(build_batch_prompt "$FIXTURE" 1 "$WORKTREE" "/usr/bin/python3" "scripts/quality-gate.sh --project-root ." 0)

# --- Core content ---
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

# --- XML tag presence ---
assert_contains "has <batch_tasks> open tag" "<batch_tasks>" "$prompt"
assert_contains "has </batch_tasks> close tag" "</batch_tasks>" "$prompt"
assert_contains "has <prior_context> open tag" "<prior_context>" "$prompt"
assert_contains "has </prior_context> close tag" "</prior_context>" "$prompt"
assert_contains "has <requirements> open tag" "<requirements>" "$prompt"
assert_contains "has </requirements> close tag" "</requirements>" "$prompt"

# --- Section ordering: batch_tasks before requirements (Lost in the Middle) ---
assert_before "batch_tasks before requirements" "<batch_tasks>" "<requirements>" "$prompt"
assert_before "batch_tasks before prior_context" "<batch_tasks>" "<prior_context>" "$prompt"
assert_before "prior_context before requirements" "<prior_context>" "<requirements>" "$prompt"

# =============================================================================
# Batch 2 tests
# =============================================================================

prompt2=$(build_batch_prompt "$FIXTURE" 2 "$WORKTREE" "/opt/python3.12" "make test" 15)

assert_contains "batch 2 has batch number" "Batch 2" "$prompt2"
assert_contains "batch 2 has batch title" "Integration (Tasks 3-4)" "$prompt2"
assert_contains "batch 2 has task text - Task 3" "Task 3: Wire Together" "$prompt2"
assert_contains "batch 2 has task text - Task 4" "Task 4: End-to-End Test" "$prompt2"
assert_contains "batch 2 has different python" "/opt/python3.12" "$prompt2"
assert_contains "batch 2 has different quality gate" "make test" "$prompt2"
assert_contains "batch 2 has prev test count" "15+" "$prompt2"

# --- Test: batch 2 does NOT contain batch 1 tasks ---
assert_not_contains "batch 2 prompt does not leak batch 1 tasks" "Create Data Model" "$prompt2"

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

# --- Test: prompt includes progress.txt content in prior_progress tag ---
assert_contains "cross-batch: has <prior_progress> tag" "<prior_progress>" "$prompt3"
assert_contains "cross-batch: has progress content" "Implemented auth module" "$prompt3"

# --- Test: prompt includes commit message ---
assert_contains "cross-batch: has commit in log" "feat: add auth" "$prompt3"

# =============================================================================
# Research warnings test
# =============================================================================

# --- Setup: create a research JSON with blocking issues ---
mkdir -p "$WORKTREE/tasks"
cat > "$WORKTREE/tasks/research-auth.json" << 'RJSON'
{
  "blocking_issues": ["OAuth library has known CVE-2025-1234", "Rate limiting not addressed in plan"]
}
RJSON

prompt4=$(build_batch_prompt "$FIXTURE" 1 "$WORKTREE" "python3" "scripts/quality-gate.sh" 0)
assert_contains "research: has <research_warnings> tag" "<research_warnings>" "$prompt4"
assert_contains "research: has CVE warning" "CVE-2025-1234" "$prompt4"
assert_contains "research: has rate limiting warning" "Rate limiting not addressed" "$prompt4"

# --- Test: no research_warnings tag when no research JSON ---
rm -rf "$WORKTREE/tasks"
prompt5=$(build_batch_prompt "$FIXTURE" 1 "$WORKTREE" "python3" "scripts/quality-gate.sh" 0)
assert_not_contains "no research: no <research_warnings> tag" "<research_warnings>" "$prompt5"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
