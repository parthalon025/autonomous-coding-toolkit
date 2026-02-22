#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-parser.sh"
source "$SCRIPT_DIR/../lib/run-plan-scoring.sh"

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

# Gate failed = score 0
score=$(score_candidate 0 50 100 0 0 0)
assert_eq "score: gate failed = 0" "0" "$score"

# Gate passed, good metrics
score=$(score_candidate 1 50 100 2 0 0)
TESTS=$((TESTS + 1))
if [[ "$score" -gt 0 ]]; then
    echo "PASS: score: gate passed = positive ($score)"
else
    echo "FAIL: score: gate passed should be positive ($score)"
    FAILURES=$((FAILURES + 1))
fi

# More tests = higher score
score_a=$(score_candidate 1 50 100 0 0 0)
score_b=$(score_candidate 1 80 100 0 0 0)
TESTS=$((TESTS + 1))
if [[ "$score_b" -gt "$score_a" ]]; then
    echo "PASS: score: more tests = higher score ($score_b > $score_a)"
else
    echo "FAIL: score: more tests should be higher ($score_b <= $score_a)"
    FAILURES=$((FAILURES + 1))
fi

# Lesson violations = penalty
score_clean=$(score_candidate 1 50 100 0 0 0)
score_dirty=$(score_candidate 1 50 100 0 2 0)
TESTS=$((TESTS + 1))
if [[ "$score_clean" -gt "$score_dirty" ]]; then
    echo "PASS: score: lesson violations penalized ($score_clean > $score_dirty)"
else
    echo "FAIL: score: lesson violations not penalized ($score_clean <= $score_dirty)"
    FAILURES=$((FAILURES + 1))
fi

# select_winner picks highest score
winner=$(select_winner "500 300 700 0")
assert_eq "select_winner: picks index of highest" "2" "$winner"

# select_winner returns -1 when all zero
winner=$(select_winner "0 0 0")
assert_eq "select_winner: all zero = -1 (no winner)" "-1" "$winner"

# === classify_batch_type ===

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Test: Create files = new-file
cat > "$WORK/plan-new.md" << 'PLAN'
## Batch 1: Setup
- Create: `src/lib.py`
- Create: `src/util.py`
- Test: `tests/test_lib.py`

**Step 1:** Write files
PLAN

result=$(classify_batch_type "$WORK/plan-new.md" 1)
assert_eq "classify: Create dominant = new-file" "new-file" "$result"

# Test: Modify only = refactoring
cat > "$WORK/plan-refactor.md" << 'PLAN'
## Batch 1: Refactor auth
- Modify: `src/auth.py:20-50`
- Modify: `src/session.py:10-30`

**Step 1:** Update auth
PLAN

result=$(classify_batch_type "$WORK/plan-refactor.md" 1)
assert_eq "classify: Modify only = refactoring" "refactoring" "$result"

# Test: Run commands only = test-only
cat > "$WORK/plan-test.md" << 'PLAN'
## Batch 1: Verify
Run: pytest tests/ -v
Run: bash scripts/quality-gate.sh --project-root .

**Step 1:** Run tests
PLAN

result=$(classify_batch_type "$WORK/plan-test.md" 1)
assert_eq "classify: Run only = test-only" "test-only" "$result"

# Test: Integration title = integration
cat > "$WORK/plan-integ.md" << 'PLAN'
## Batch 1: Integration Wiring
- Modify: `src/main.py`
- Create: `src/glue.py`

**Step 1:** Wire components
PLAN

result=$(classify_batch_type "$WORK/plan-integ.md" 1)
assert_eq "classify: integration title = integration" "integration" "$result"

# === get_prompt_variants ===

# Test: no history = vanilla first
result=$(get_prompt_variants "new-file" "/nonexistent/outcomes.json" 3)
first_line=$(echo "$result" | head -1)
assert_eq "variants: first is vanilla" "vanilla" "$first_line"

# Test: returns exactly N lines
count=$(echo "$result" | wc -l)
assert_eq "variants: returns N lines" "3" "$count"

# Test: with learned history, slot 2 picks winner
cat > "$WORK/outcomes.json" << 'JSON'
[{"batch_type": "new-file", "prompt_variant": "check all imports before running tests", "won": true, "score": 500}]
JSON

result=$(get_prompt_variants "new-file" "$WORK/outcomes.json" 3)
second_line=$(echo "$result" | sed -n '2p')
assert_eq "variants: learned winner in slot 2" "check all imports before running tests" "$second_line"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
