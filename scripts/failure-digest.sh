#!/usr/bin/env bash
# failure-digest.sh — Parse failed batch logs into structured failure digest
#
# Usage: failure-digest.sh <log-file>
#
# Extracts:
#   - Failed test names (FAILED pattern)
#   - Error types and messages (Traceback, Error:, Exception:)
#   - Test summary line (N failed, M passed)
#
# Output: Structured text digest suitable for retry prompts
set -euo pipefail

LOG_FILE="${1:-}"

if [[ "$LOG_FILE" == "--help" || "$LOG_FILE" == "-h" ]]; then
    echo "failure-digest.sh — Parse batch log into structured failure digest"
    echo "Usage: failure-digest.sh <log-file>"
    exit 0
fi

if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
    echo "Error: Log file required" >&2
    exit 1
fi

echo "=== Failure Digest ==="
echo "Log: $(basename "$LOG_FILE")"
echo ""

# Extract failed test names
echo "--- Failed Tests ---"
grep -E '^FAILED ' "$LOG_FILE" 2>/dev/null | sed 's/^FAILED /  /' || echo "  (none found)"
echo ""

# Extract error types and messages
echo "--- Errors ---"
grep -E '(Error|Exception|FAIL):' "$LOG_FILE" 2>/dev/null | grep -v '^FAILED ' | head -20 | sed 's/^/  /' || echo "  (none found)"
echo ""

# Extract tracebacks (last frame + error line)
echo "--- Stack Traces (last frame) ---"
grep -B1 -E '^\w+Error:|^\w+Exception:' "$LOG_FILE" 2>/dev/null | head -20 | sed 's/^/  /' || echo "  (none found)"
echo ""

# Extract test summary
echo "--- Summary ---"
grep -E '[0-9]+ (failed|passed|error)' "$LOG_FILE" 2>/dev/null | tail -1 | sed 's/^/  /' || echo "  (no summary found)"
echo ""

echo "=== End Digest ==="
