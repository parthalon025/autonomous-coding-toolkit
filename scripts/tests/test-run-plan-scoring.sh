#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
