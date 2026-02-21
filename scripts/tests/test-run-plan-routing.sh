#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-parser.sh"
source "$SCRIPT_DIR/../lib/run-plan-routing.sh"

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

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Plan with clear parallel batches
cat > "$WORK/parallel-plan.md" << 'PLAN'
## Batch 1: Foundation

**Files:**
- Create: `src/lib.sh`

### Task 1: Create lib
Write lib.

## Batch 2: Feature A

**Files:**
- Create: `src/feature-a.sh`
context_refs: src/lib.sh

### Task 2: Build feature A

## Batch 3: Feature B

**Files:**
- Create: `src/feature-b.sh`
context_refs: src/lib.sh

### Task 3: Build feature B

## Batch 4: Integration

**Files:**
- Modify: `src/feature-a.sh`
- Modify: `src/feature-b.sh`
context_refs: src/feature-a.sh, src/feature-b.sh

### Task 4: Wire together
PLAN

# Test dependency graph building
deps=$(build_dependency_graph "$WORK/parallel-plan.md")
assert_eq "dep graph: B2 depends on B1" "true" "$(echo "$deps" | jq '.["2"] | contains(["1"])')"
assert_eq "dep graph: B3 depends on B1" "true" "$(echo "$deps" | jq '.["3"] | contains(["1"])')"
assert_eq "dep graph: B4 depends on B2 and B3" "true" "$(echo "$deps" | jq '.["4"] | (contains(["2"]) and contains(["3"]))')"

# Test parallelism score
score=$(compute_parallelism_score "$WORK/parallel-plan.md")
TESTS=$((TESTS + 1))
if [[ "$score" -gt 40 ]]; then
    echo "PASS: parallelism score: $score > 40 (batches 2,3 can run parallel)"
else
    echo "FAIL: parallelism score: $score <= 40"
    FAILURES=$((FAILURES + 1))
fi

# Test mode recommendation
mode=$(recommend_execution_mode "$score" "false" 21)
assert_eq "recommend: team for high score" "team" "$mode"

# Sequential plan (each batch depends on previous)
cat > "$WORK/sequential-plan.md" << 'PLAN'
## Batch 1: Setup

**Files:**
- Create: `src/main.sh`

### Task 1: Setup

## Batch 2: Extend

**Files:**
- Modify: `src/main.sh`
context_refs: src/main.sh

### Task 2: Extend

## Batch 3: Finalize

**Files:**
- Modify: `src/main.sh`
context_refs: src/main.sh

### Task 3: Finalize
PLAN

score=$(compute_parallelism_score "$WORK/sequential-plan.md")
TESTS=$((TESTS + 1))
if [[ "$score" -lt 30 ]]; then
    echo "PASS: sequential plan score: $score < 30"
else
    echo "FAIL: sequential plan score: $score >= 30"
    FAILURES=$((FAILURES + 1))
fi

mode=$(recommend_execution_mode "$score" "false" 21)
assert_eq "recommend: headless for low score" "headless" "$mode"

# Test model routing
model=$(classify_batch_model "$WORK/parallel-plan.md" 1)
assert_eq "model: batch with Create files = sonnet" "sonnet" "$model"

# Verification batch
cat > "$WORK/verify-plan.md" << 'PLAN'
## Batch 1: Verify everything

### Task 1: Run all tests

**Step 1: Run tests**
Run: `bash scripts/tests/run-all-tests.sh`

**Step 2: Check line counts**
Run: `wc -l scripts/*.sh`
PLAN

model=$(classify_batch_model "$WORK/verify-plan.md" 1)
assert_eq "model: batch with only Run commands = haiku" "haiku" "$model"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
