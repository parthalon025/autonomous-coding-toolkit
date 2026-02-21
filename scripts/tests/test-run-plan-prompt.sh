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

# --- Setup: fixture plan + temp git worktree ---
TMPDIR_ROOT=$(mktemp -d)
trap "rm -rf '$TMPDIR_ROOT'" EXIT

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

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
