#!/usr/bin/env bash
# Test AGENTS.md generation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-parser.sh"
source "$SCRIPT_DIR/../lib/run-plan-prompt.sh"

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
    if echo "$haystack" | grep -qF "$needle"; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        FAILURES=$((FAILURES + 1))
    fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Create a test plan
cat > "$WORK/plan.md" << 'PLAN'
## Batch 1: Setup foundation
- Create: `src/lib.py`
- Test: `tests/test_lib.py`

**Step 1:** Create files

## Batch 2: Core Logic
- Create: `src/core.py`
- Modify: `src/lib.py`

**Step 1:** Add core
PLAN

# Generate AGENTS.md
generate_agents_md "$WORK/plan.md" "$WORK" "headless"

# Test: file created
TESTS=$((TESTS + 1))
if [[ -f "$WORK/AGENTS.md" ]]; then
    echo "PASS: AGENTS.md created"
else
    echo "FAIL: AGENTS.md should be created"
    FAILURES=$((FAILURES + 1))
fi

output=$(cat "$WORK/AGENTS.md")
assert_contains "has batch count" "2 batches" "$output"
assert_contains "has mode" "headless" "$output"
assert_contains "has tools" "Bash" "$output"
assert_contains "has plan name" "plan.md" "$output"
assert_contains "has batch 1 title" "Setup foundation" "$output"
assert_contains "has batch 2 title" "Core Logic" "$output"
assert_contains "has guidelines" "quality gate" "$output"

# Test: team mode
generate_agents_md "$WORK/plan.md" "$WORK" "team"
output=$(cat "$WORK/AGENTS.md")
assert_contains "team mode updated" "team" "$output"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
