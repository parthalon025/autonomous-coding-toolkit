#!/usr/bin/env bash
set -euo pipefail

# Test runner that executes all test-*.sh files in the same directory
# Reports per-file pass/fail and exits non-zero if any fail.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL=0
PASSED=0
FAILED=0

# Collect all test files
mapfile -t TEST_FILES < <(find "$SCRIPT_DIR" -maxdepth 1 -name "test-*.sh" -type f | sort)

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "No test files found matching test-*.sh" >&2
  exit 1
fi

# Run each test
for test_file in "${TEST_FILES[@]}"; do
  test_name="$(basename "$test_file")"
  TOTAL=$((TOTAL + 1))

  # Print header
  echo "═══════════════════════════════════════════"
  echo "  Running: $test_name"
  echo "═══════════════════════════════════════════"

  # Run test and capture exit code
  if bash "$test_file"; then
    PASSED=$((PASSED + 1))
    echo ""
  else
    FAILED=$((FAILED + 1))
    echo ""
  fi
done

# Print summary
echo "═══════════════════════════════════════════"
echo "  TOTAL: $TOTAL test files"
echo "  PASSED: $PASSED"
echo "  FAILED: $FAILED"
echo "═══════════════════════════════════════════"

# Exit non-zero if any failed
if [[ $FAILED -gt 0 ]]; then
  exit 1
fi

exit 0
