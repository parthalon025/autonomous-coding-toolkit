#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- Setup: create fake project directories with Makefiles ---
mkdir -p "$WORK/projects/project-a"
mkdir -p "$WORK/projects/project-b"

# Each project's Makefile writes its own directory name to a shared log
cat > "$WORK/projects/project-a/Makefile" << 'EOF'
test:
	@pwd >> /tmp/batch-test-cwd-log.$$
	@echo "project-a tests passed"
EOF

cat > "$WORK/projects/project-b/Makefile" << 'EOF'
test:
	@pwd >> /tmp/batch-test-cwd-log.$$
	@echo "project-b tests passed"
EOF

# Use a unique log file
LOG_FILE="$WORK/cwd-log"

# Rewrite Makefiles to use our specific log path
cat > "$WORK/projects/project-a/Makefile" << EOF
test:
	@pwd >> $LOG_FILE
	@echo "project-a tests passed"
EOF

cat > "$WORK/projects/project-b/Makefile" << EOF
test:
	@pwd >> $LOG_FILE
	@echo "project-b tests passed"
EOF

# --- Test: cd is restored between project iterations ---
# Run batch-test across both projects
output=$("$SCRIPT_DIR/../batch-test.sh" "$WORK/projects" 2>&1) || true

# Read the logged working directories
if [[ -f "$LOG_FILE" ]]; then
    cwd_a=$(sed -n '1p' "$LOG_FILE")
    cwd_b=$(sed -n '2p' "$LOG_FILE")

    # Each project should run from its own directory
    assert_contains "batch-test: project-a runs from its own dir" "project-a" "$cwd_a"
    assert_contains "batch-test: project-b runs from its own dir" "project-b" "$cwd_b"
else
    # If log file doesn't exist, both projects failed to run
    TESTS=$((TESTS + 1))
    echo "FAIL: batch-test: cwd log file not created"
    FAILURES=$((FAILURES + 1))
    TESTS=$((TESTS + 1))
    echo "FAIL: batch-test: project-b dir check (no log)"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: output includes both projects ---
assert_contains "batch-test: output includes project-a" "project-a" "$output"
assert_contains "batch-test: output includes project-b" "project-b" "$output"
assert_contains "batch-test: output includes Done" "Done" "$output"

# --- Test: single project target works ---
single_output=$("$SCRIPT_DIR/../batch-test.sh" "$WORK/projects" "project-a" 2>&1) || true
assert_contains "batch-test: single target runs" "project-a" "$single_output"
assert_not_contains "batch-test: single target skips other" "project-b" "$single_output"

# --- Test: missing project is skipped ---
skip_output=$("$SCRIPT_DIR/../batch-test.sh" "$WORK/projects" "nonexistent" 2>&1) || true
assert_contains "batch-test: missing project skipped" "SKIP" "$skip_output"

report_results
