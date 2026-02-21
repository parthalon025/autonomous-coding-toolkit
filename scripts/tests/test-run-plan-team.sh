#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-parser.sh"
source "$SCRIPT_DIR/../lib/run-plan-routing.sh"
source "$SCRIPT_DIR/../lib/run-plan-team.sh"

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
trap "rm -rf '$WORK'" EXIT

# Plan with parallel structure: batch 1 is foundation, 2+3 are parallel, 4 depends on both
cat > "$WORK/parallel-plan.md" << 'PLAN'
## Batch 1: Foundation

**Files:**
- Create: `src/lib.sh`

### Task 1: Create lib

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

# Test compute_parallel_groups with parallel plan
dep_graph=$(build_dependency_graph "$WORK/parallel-plan.md")
groups=$(compute_parallel_groups "$dep_graph" 1 4)

# Should produce 3 groups: [1], [2,3], [4]
group_count=$(echo "$groups" | jq 'length')
assert_eq "parallel groups: 3 groups" "3" "$group_count"

# First group has batch 1
first_group=$(echo "$groups" | jq -c '.[0] | sort')
assert_eq "parallel groups: group 1 = [1]" '[1]' "$first_group"

# Second group has batches 2 and 3 (in some order)
second_group=$(echo "$groups" | jq -c '.[1] | sort')
assert_eq "parallel groups: group 2 = [2,3]" '[2,3]' "$second_group"

# Third group has batch 4
third_group=$(echo "$groups" | jq -c '.[2] | sort')
assert_eq "parallel groups: group 3 = [4]" '[4]' "$third_group"

# Sequential plan (each depends on previous)
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

dep_graph=$(build_dependency_graph "$WORK/sequential-plan.md")
groups=$(compute_parallel_groups "$dep_graph" 1 3)

# Sequential plan: each batch is its own group
group_count=$(echo "$groups" | jq 'length')
assert_eq "sequential groups: 3 groups (no parallelism)" "3" "$group_count"

# Each group has exactly one batch
for ((g = 0; g < 3; g++)); do
    size=$(echo "$groups" | jq ".[$g] | length")
    assert_eq "sequential groups: group $((g+1)) has 1 batch" "1" "$size"
done

# Test with subset range (start_batch=2, end_batch=3)
dep_graph=$(build_dependency_graph "$WORK/parallel-plan.md")
groups=$(compute_parallel_groups "$dep_graph" 2 3)
group_count=$(echo "$groups" | jq 'length')
# Batches 2 and 3 both depend on batch 1 which is outside our range
# Since batch 1 is not in range, its deps should be treated as satisfied
assert_eq "subset range: batches 2,3 form 1 group (deps outside range)" "1" "$group_count"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
