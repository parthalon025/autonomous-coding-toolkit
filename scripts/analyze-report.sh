#!/usr/bin/env bash
# analyze-report.sh — Analyze a report and pick the #1 actionable priority
#
# Usage: analyze-report.sh <report-file> [--dry-run] [--model MODEL]
#
# Reads a markdown report (test failures, errors, user feedback, metrics)
# and uses an LLM to identify the single most impactful fix.
#
# Output: analysis.json with priority, reasoning, and suggested PRD outline
#
# Models: Uses Ollama queue (port 7683) for serialized execution.
# Default model: deepseek-r1:8b (reasoning-optimized)

set -euo pipefail

REPORT_FILE="${1:-}"
DRY_RUN=false
MODEL="deepseek-r1:8b"
OUTPUT_DIR="."

# Parse remaining args
shift || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --model) MODEL="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPORT_FILE" ]] || [[ ! -f "$REPORT_FILE" ]]; then
  echo "Usage: analyze-report.sh <report-file> [--dry-run] [--model MODEL]" >&2
  echo "" >&2
  echo "Report file not found: ${REPORT_FILE:-<none>}" >&2
  exit 1
fi

REPORT_CONTENT=$(cat "$REPORT_FILE")

PROMPT="You are analyzing a development report to identify the single most impactful priority to fix.

## Report
$REPORT_CONTENT

## Instructions
1. Read the report carefully
2. Identify ALL issues mentioned
3. Rank them by: revenue impact > user-facing bugs > developer experience > tech debt
4. Pick the #1 priority — the one fix that delivers the most value

## Output
Respond with ONLY valid JSON (no markdown fences, no explanation):
{
  \"priority\": \"Short title of the #1 issue\",
  \"reasoning\": \"Why this is #1 (2-3 sentences)\",
  \"severity\": \"critical|high|medium|low\",
  \"estimated_tasks\": 5,
  \"prd_outline\": [
    \"Task 1 title\",
    \"Task 2 title\"
  ]
}"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "=== DRY RUN ==="
  echo "Report: $REPORT_FILE"
  echo "Model: $MODEL"
  echo "Prompt length: ${#PROMPT} chars"
  echo ""
  echo "Would send to Ollama and save to $OUTPUT_DIR/analysis.json"
  exit 0
fi

# Check if ollama-queue is available, fall back to direct ollama
OLLAMA_URL="http://localhost:11434"
if curl -s -o /dev/null -w '%{http_code}' "http://localhost:7683/health" 2>/dev/null | grep -q "200"; then
  echo "Using ollama-queue for serialized execution..." >&2
  # Submit via queue API
  RESPONSE=$(curl -s "http://localhost:7683/api/generate" \
    -d "{\"model\":\"$MODEL\",\"prompt\":$(echo "$PROMPT" | jq -Rs .),\"stream\":false}" \
    --max-time 300)
else
  echo "Using direct Ollama API..." >&2
  RESPONSE=$(curl -s "$OLLAMA_URL/api/generate" \
    -d "{\"model\":\"$MODEL\",\"prompt\":$(echo "$PROMPT" | jq -Rs .),\"stream\":false}" \
    --max-time 300)
fi

# Extract response text
ANALYSIS=$(echo "$RESPONSE" | jq -r '.response // empty')

if [[ -z "$ANALYSIS" ]]; then
  echo "Error: Empty response from Ollama" >&2
  echo "Full response: $RESPONSE" >&2
  exit 1
fi

# Try to parse as JSON, wrap in error if not valid
if echo "$ANALYSIS" | jq . >/dev/null 2>&1; then
  echo "$ANALYSIS" | jq . > "$OUTPUT_DIR/analysis.json"
else
  # LLM sometimes wraps in markdown fences
  CLEANED=$(echo "$ANALYSIS" | sed 's/^```json//' | sed 's/^```//' | sed 's/```$//')
  if echo "$CLEANED" | jq . >/dev/null 2>&1; then
    echo "$CLEANED" | jq . > "$OUTPUT_DIR/analysis.json"
  else
    echo "Warning: Could not parse LLM response as JSON, saving raw" >&2
    echo "{\"raw_response\": $(echo "$ANALYSIS" | jq -Rs .)}" > "$OUTPUT_DIR/analysis.json"
  fi
fi

echo "Analysis saved to $OUTPUT_DIR/analysis.json" >&2
cat "$OUTPUT_DIR/analysis.json"
