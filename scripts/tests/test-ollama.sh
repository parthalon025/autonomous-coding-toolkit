#!/usr/bin/env bash
# Test ollama.sh shared library functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/ollama.sh"

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

# === ollama_build_payload tests ===

val=$(ollama_build_payload "deepseek-r1:8b" "Hello world")
model=$(echo "$val" | jq -r '.model')
assert_eq "ollama_build_payload: model set" "deepseek-r1:8b" "$model"

stream=$(echo "$val" | jq -r '.stream')
assert_eq "ollama_build_payload: stream false" "false" "$stream"

# === ollama_parse_response tests ===

val=$(echo '{"response":"hello"}' | ollama_parse_response)
assert_eq "ollama_parse_response: extracts response" "hello" "$val"

val=$(echo '{}' | ollama_parse_response)
assert_eq "ollama_parse_response: empty on missing field" "" "$val"

# === ollama_extract_json tests ===

val=$(echo '```json
{"key":"value"}
```' | ollama_extract_json)
key=$(echo "$val" | jq -r '.key')
assert_eq "ollama_extract_json: strips fences and validates" "value" "$key"

val=$(echo 'not json at all' | ollama_extract_json)
assert_eq "ollama_extract_json: returns empty on invalid" "" "$val"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
