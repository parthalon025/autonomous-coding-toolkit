#!/usr/bin/env bash
# Test scripts/lib/ollama.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

OLLAMA_LIB="$SCRIPT_DIR/../lib/ollama.sh"

# === Test: Health check curl has timeout flags (#25) ===
# Read the source and verify --connect-timeout and --max-time are present on the health check line
health_line=$(grep -F 'OLLAMA_QUEUE_URL/health' "$OLLAMA_LIB")
# Use [[ ]] to check for substrings since grep chokes on --flag patterns
TESTS=$((TESTS + 1))
if [[ "$health_line" == *"--connect-timeout"* ]]; then
    echo "PASS: health check: has --connect-timeout"
else
    echo "FAIL: health check: has --connect-timeout"; FAILURES=$((FAILURES + 1))
fi
TESTS=$((TESTS + 1))
if [[ "$health_line" == *"--max-time"* ]]; then
    echo "PASS: health check: has --max-time"
else
    echo "FAIL: health check: has --max-time"; FAILURES=$((FAILURES + 1))
fi

# === Test: API call curl has --max-time ===
api_line=$(grep -F 'curl -s "$api_url"' "$OLLAMA_LIB")
TESTS=$((TESTS + 1))
if [[ "$api_line" == *"--max-time"* ]]; then
    echo "PASS: api call: has --max-time"
else
    echo "FAIL: api call: has --max-time"; FAILURES=$((FAILURES + 1))
fi

# === Test: ollama_build_payload produces valid JSON ===
# Source common.sh first (required dependency), then ollama.sh
COMMON_LIB="$SCRIPT_DIR/../lib/common.sh"
if [[ -f "$COMMON_LIB" ]]; then
    source "$COMMON_LIB"
fi
source "$OLLAMA_LIB"
payload=$(ollama_build_payload "test-model" "test prompt")
model=$(echo "$payload" | jq -r '.model')
assert_eq "build_payload: model" "test-model" "$model"
prompt=$(echo "$payload" | jq -r '.prompt')
assert_eq "build_payload: prompt" "test prompt" "$prompt"

report_results
