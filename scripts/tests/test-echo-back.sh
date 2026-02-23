#!/usr/bin/env bash
# Test spec echo-back gate function
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-parser.sh"
source "$SCRIPT_DIR/../lib/run-plan-headless.sh" 2>/dev/null || true

# Source just the echo_back_check function if full sourcing fails
# (run-plan-headless.sh references globals that may not be set)
type echo_back_check &>/dev/null || {
    echo "ERROR: echo_back_check function not available"
    exit 1
}

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc (expected: $expected, got: $actual)"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

LOG_DIR="$TMPDIR_ROOT/logs"
mkdir -p "$LOG_DIR"

# =============================================================================
# Mock claude command: returns canned responses based on prompt content
# =============================================================================

MOCK_SCRIPT="$TMPDIR_ROOT/mock-claude"
cat > "$MOCK_SCRIPT" << 'MOCK'
#!/usr/bin/env bash
# Mock claude CLI for testing echo-back
# Reads prompt from -p arg, returns canned response

prompt=""
model=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p) prompt="$2"; shift 2 ;;
        --model) model="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Retry restatement (check BEFORE initial restatement — both contain "restate")
if [[ "$prompt" == *"Re-read the specification"* && -z "$model" ]]; then
    echo "This batch builds the authentication system as specified."
    exit 0
fi

# Echo-back restatement request → return matching restatement
if [[ "$prompt" == *"restate in one paragraph"* && -z "$model" ]]; then
    if [[ "$prompt" == *"data model"* ]]; then
        echo "This batch creates a data model with validation and tests."
    elif [[ "$prompt" == *"MISMATCH_TEST"* ]]; then
        echo "This batch does something completely unrelated to the spec."
    else
        echo "This batch implements the specified functionality."
    fi
    exit 0
fi

# Haiku verification → check if restatement mentions key terms
if [[ -n "$model" && "$model" == "haiku" ]]; then
    if [[ "$prompt" == *"unrelated"* ]]; then
        echo "NO - The restatement does not match the original spec."
    else
        echo "YES - The restatement captures the key goals."
    fi
    exit 0
fi

echo "Unknown mock scenario"
exit 0
MOCK
chmod +x "$MOCK_SCRIPT"

# =============================================================================
# Test 1: Matching restatement passes
# =============================================================================

batch_text="Create data model with validation.
Add tests for the model."

exit_code=0
echo_back_check "$batch_text" "$LOG_DIR" 1 "$MOCK_SCRIPT" >/dev/null 2>&1 || exit_code=$?
assert_eq "matching restatement passes" "0" "$exit_code"

# =============================================================================
# Test 2: Mismatched restatement triggers retry
# =============================================================================

mismatch_text="MISMATCH_TEST: Build the authentication system."

exit_code=0
echo_back_check "$mismatch_text" "$LOG_DIR" 2 "$MOCK_SCRIPT" >/dev/null 2>&1 || exit_code=$?
# The retry restatement doesn't mention "unrelated", so haiku says YES → passes on retry
assert_eq "mismatch with successful retry passes" "0" "$exit_code"

# =============================================================================
# Test 3: Empty restatement skips check
# =============================================================================

EMPTY_MOCK="$TMPDIR_ROOT/mock-empty"
cat > "$EMPTY_MOCK" << 'MOCK'
#!/usr/bin/env bash
# Returns empty for all calls
exit 0
MOCK
chmod +x "$EMPTY_MOCK"

exit_code=0
echo_back_check "some batch text" "$LOG_DIR" 3 "$EMPTY_MOCK" >/dev/null 2>&1 || exit_code=$?
assert_eq "empty restatement skips gracefully" "0" "$exit_code"

# =============================================================================
# Test 4: Log file is created
# =============================================================================

TESTS=$((TESTS + 1))
if [[ -f "$LOG_DIR/batch-1-echo-back.log" ]]; then
    echo "PASS: echo-back log file created"
else
    echo "FAIL: echo-back log file not created"
    FAILURES=$((FAILURES + 1))
fi

# =============================================================================
# Test 5: Persistent failure mock (both attempts fail)
# =============================================================================

FAIL_MOCK="$TMPDIR_ROOT/mock-fail"
cat > "$FAIL_MOCK" << 'MOCK'
#!/usr/bin/env bash
prompt=""
model=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p) prompt="$2"; shift 2 ;;
        --model) model="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ "$prompt" == *"restate"* || "$prompt" == *"Re-read"* ]]; then
    echo "This is completely wrong and unrelated."
    exit 0
fi

if [[ -n "$model" && "$model" == "haiku" ]]; then
    echo "NO - The restatement is completely wrong."
    exit 0
fi

exit 0
MOCK
chmod +x "$FAIL_MOCK"

exit_code=0
echo_back_check "Build the user dashboard" "$LOG_DIR" 5 "$FAIL_MOCK" >/dev/null 2>&1 || exit_code=$?
assert_eq "persistent mismatch fails" "1" "$exit_code"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
