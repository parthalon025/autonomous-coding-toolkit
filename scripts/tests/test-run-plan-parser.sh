#!/usr/bin/env bash
# Test plan parser functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-parser.sh"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        echo "  in: ${haystack:0:200}..."
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

# --- Create test fixture ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FIXTURE="$WORK/fixture.md"
cat > "$FIXTURE" << 'EOF'
# Feature X Implementation Plan

**Goal:** Build feature X

**Tech Stack:** Python, pytest

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

## Batch 3: Dashboard ⚠ CRITICAL

### Task 5: UI Components

Build the dashboard.
EOF

# --- Test: count_batches ---
count=$(count_batches "$FIXTURE")
assert_eq "count_batches returns 3" "3" "$count"

# --- Test: get_batch_title ---
title=$(get_batch_title "$FIXTURE" 1)
assert_eq "batch 1 title" "Foundation (Tasks 1-2)" "$title"

title=$(get_batch_title "$FIXTURE" 2)
assert_eq "batch 2 title" "Integration (Tasks 3-4)" "$title"

title=$(get_batch_title "$FIXTURE" 3)
assert_eq "batch 3 title" "Dashboard ⚠ CRITICAL" "$title"

# --- Test: get_batch_text ---
text=$(get_batch_text "$FIXTURE" 1)
assert_contains "batch 1 has Task 1" "Task 1: Create Data Model" "$text"
assert_contains "batch 1 has Task 2" "Task 2: Add Validation" "$text"
assert_contains "batch 1 has code" "def test_model" "$text"

text2=$(get_batch_text "$FIXTURE" 2)
assert_contains "batch 2 has Task 3" "Task 3: Wire Together" "$text2"
assert_contains "batch 2 has Task 4" "Task 4: End-to-End Test" "$text2"

# Batch 2 should NOT contain batch 1 content
TESTS=$((TESTS + 1))
if [[ "$text2" == *"Create Data Model"* ]]; then
    echo "FAIL: batch 2 text should not contain batch 1 content"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: batch 2 text does not leak batch 1"
fi

# Batch 1 should NOT contain batch 2 content
TESTS=$((TESTS + 1))
if [[ "$text" == *"Wire Together"* ]]; then
    echo "FAIL: batch 1 text should not contain batch 2 content"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: batch 1 text does not leak batch 2"
fi

# --- Test: get_batch_task_count ---
tc=$(get_batch_task_count "$FIXTURE" 1)
assert_eq "batch 1 has 2 tasks" "2" "$tc"

tc2=$(get_batch_task_count "$FIXTURE" 2)
assert_eq "batch 2 has 2 tasks" "2" "$tc2"

tc3=$(get_batch_task_count "$FIXTURE" 3)
assert_eq "batch 3 has 1 task" "1" "$tc3"

# --- Test: is_critical_batch ---
TESTS=$((TESTS + 1))
if is_critical_batch "$FIXTURE" 3; then
    echo "PASS: batch 3 is critical"
else
    echo "FAIL: batch 3 should be critical"
    FAILURES=$((FAILURES + 1))
fi

TESTS=$((TESTS + 1))
if is_critical_batch "$FIXTURE" 1; then
    echo "FAIL: batch 1 should not be critical"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: batch 1 is not critical"
fi

TESTS=$((TESTS + 1))
if is_critical_batch "$FIXTURE" 2; then
    echo "FAIL: batch 2 should not be critical"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: batch 2 is not critical"
fi

# --- Test: nonexistent batch ---
text_empty=$(get_batch_text "$FIXTURE" 99)
assert_eq "nonexistent batch returns empty" "" "$text_empty"

title_empty=$(get_batch_title "$FIXTURE" 99)
assert_eq "nonexistent batch title returns empty" "" "$title_empty"

tc_empty=$(get_batch_task_count "$FIXTURE" 99)
assert_eq "nonexistent batch task count returns 0" "0" "$tc_empty"

# === get_batch_context_refs tests ===

# Create a plan with context_refs
cat > "$WORK/refs-plan.md" << 'PLAN'
## Batch 1: Setup

### Task 1: Create base
Content here.

## Batch 2: Build on base
context_refs: src/auth.py, tests/test_auth.py

### Task 2: Extend
Uses auth module from batch 1.
PLAN

# Batch 1 has no refs
val=$(get_batch_context_refs "$WORK/refs-plan.md" 1)
assert_eq "get_batch_context_refs: batch 1 has no refs" "" "$val"

# Batch 2 has refs
val=$(get_batch_context_refs "$WORK/refs-plan.md" 2)
echo "$val" | grep -q "src/auth.py" && echo "PASS: batch 2 refs include src/auth.py" && TESTS=$((TESTS + 1)) || {
    echo "FAIL: batch 2 refs missing src/auth.py"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1))
}

echo "$val" | grep -q "tests/test_auth.py" && echo "PASS: batch 2 refs include tests/test_auth.py" && TESTS=$((TESTS + 1)) || {
    echo "FAIL: batch 2 refs missing tests/test_auth.py"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1))
}

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
