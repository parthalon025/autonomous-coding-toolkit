#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PULL="$SCRIPT_DIR/../pull-community-lessons.sh"

# --- Test: --help exits 0 ---
assert_exit "--help exits 0" 0 "$PULL" --help

# --- Test: missing upstream remote exits 1 gracefully ---
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

cd "$TEST_TMPDIR" && git init -q && git commit --allow-empty -m "init" -q
pull_output=$("$PULL" --remote nonexistent 2>&1) || true
pull_exit=0
"$PULL" --remote nonexistent > /dev/null 2>&1 || pull_exit=$?
assert_eq "missing remote exits 1" "1" "$pull_exit"
assert_contains "missing remote error message" "not found" "$pull_output"

# --- Test: --dry-run without remote shows status ---
dry_output=$("$PULL" --remote nonexistent --dry-run 2>&1) || true
# Should still fail because remote doesn't exist (dry-run doesn't skip validation)
assert_contains "--dry-run mentions remote name" "nonexistent" "$dry_output"

# --- Test: happy path — copies new lessons from upstream ---
# Create an "upstream" bare repo with a lesson file
UPSTREAM_DIR=$(mktemp -d)
LOCAL_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR" "$UPSTREAM_DIR" "$LOCAL_DIR"' EXIT

# Set up upstream repo with a lesson
git init -q --bare "$UPSTREAM_DIR/upstream.git"
CLONE_DIR=$(mktemp -d)
git clone -q "$UPSTREAM_DIR/upstream.git" "$CLONE_DIR/work"
cd "$CLONE_DIR/work"
git config user.email "test@test.com"
git config user.name "Test"
mkdir -p docs/lessons
cat > docs/lessons/0099-upstream-lesson.md << 'LESSON'
---
title: Test upstream lesson
tier: lesson
scope: universal
---
## Key Takeaway
This came from upstream.
LESSON
git add docs/lessons/0099-upstream-lesson.md
git commit -q -m "add upstream lesson"
git push -q origin main 2>/dev/null
cd - > /dev/null

# Set up local repo with upstream remote pointing to bare repo
git clone -q "$UPSTREAM_DIR/upstream.git" "$LOCAL_DIR/local"
cd "$LOCAL_DIR/local"
git config user.email "test@test.com"
git config user.name "Test"
git remote add upstream "$UPSTREAM_DIR/upstream.git"

# Remove the lesson locally (simulate it being new)
rm -f docs/lessons/0099-upstream-lesson.md
git add -u && git commit -q -m "remove lesson locally" || true

# Run pull-community-lessons
pull_output=$("$PULL" --remote upstream 2>&1) || true

TESTS=$((TESTS + 1))
if [[ -f "docs/lessons/0099-upstream-lesson.md" ]]; then
    echo "PASS: happy path: upstream lesson copied to local"
else
    echo "FAIL: happy path: upstream lesson should be copied to local docs/lessons/"
    echo "  output: $pull_output"
    FAILURES=$((FAILURES + 1))
fi

# Verify content
TESTS=$((TESTS + 1))
if grep -q "This came from upstream" "docs/lessons/0099-upstream-lesson.md" 2>/dev/null; then
    echo "PASS: happy path: lesson content is correct"
else
    echo "FAIL: happy path: lesson content should match upstream"
    FAILURES=$((FAILURES + 1))
fi

cd - > /dev/null
rm -rf "$CLONE_DIR"

# --- Test: strategy-perf.json max() merge ---
# Local has (3W, 2L), upstream has (5W, 1L) → merged should be (5W, 2L) per max()
MERGE_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR" "$UPSTREAM_DIR" "$LOCAL_DIR" "$MERGE_DIR"' EXIT

# Setup upstream with perf data
git init -q --bare "$MERGE_DIR/upstream.git"
MERGE_CLONE=$(mktemp -d)
git clone -q "$MERGE_DIR/upstream.git" "$MERGE_CLONE/work"
cd "$MERGE_CLONE/work"
git config user.email "test@test.com"
git config user.name "Test"
mkdir -p logs docs/lessons
cat > logs/strategy-perf.json << 'PERF'
{
  "new-file": {"superpowers": {"wins": 5, "losses": 1}, "ralph": {"wins": 2, "losses": 3}},
  "refactoring": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "integration": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "test-only": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "calibration_count": 0,
  "calibration_complete": false
}
PERF
git add . && git commit -q -m "add perf data" && git push -q origin main 2>/dev/null
cd - > /dev/null

# Local repo with different perf data
git clone -q "$MERGE_DIR/upstream.git" "$MERGE_DIR/local"
cd "$MERGE_DIR/local"
git config user.email "test@test.com"
git config user.name "Test"
git remote add upstream "$MERGE_DIR/upstream.git"
mkdir -p logs
cat > logs/strategy-perf.json << 'PERF_LOCAL'
{
  "new-file": {"superpowers": {"wins": 3, "losses": 2}, "ralph": {"wins": 4, "losses": 1}},
  "refactoring": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "integration": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "test-only": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "calibration_count": 0,
  "calibration_complete": false
}
PERF_LOCAL

"$PULL" --remote upstream > /dev/null 2>&1 || true

# Check max() merge: max(3,5)=5 for sp wins, max(2,1)=2 for sp losses
sp_wins=$(jq '."new-file".superpowers.wins' logs/strategy-perf.json 2>/dev/null)
sp_losses=$(jq '."new-file".superpowers.losses' logs/strategy-perf.json 2>/dev/null)
ralph_wins=$(jq '."new-file".ralph.wins' logs/strategy-perf.json 2>/dev/null)

assert_eq "max merge: superpowers wins = max(3,5) = 5" "5" "$sp_wins"
assert_eq "max merge: superpowers losses = max(2,1) = 2" "2" "$sp_losses"
assert_eq "max merge: ralph wins = max(4,2) = 4" "4" "$ralph_wins"

cd - > /dev/null
rm -rf "$MERGE_CLONE" "$MERGE_DIR"

report_results
