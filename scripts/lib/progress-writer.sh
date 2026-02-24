#!/usr/bin/env bash
# progress-writer.sh — Structured progress.txt writer/reader
#
# Provides structured batch progress tracking with machine-readable sections.
# Format:
#   ## Batch N: <title> (YYYY-MM-DDTHH:MM:SSZ)
#   ### Files Modified
#   - path/to/file (created|modified|deleted)
#   ### Decisions
#   - decision: rationale
#   ### Issues Encountered
#   - issue → resolution
#   ### State
#   - Tests: N passing
#   - Duration: Ns
#   - Cost: $N.NN
#
# Functions:
#   write_batch_progress <worktree> <batch_num> <title>
#   append_progress_section <worktree> <section> <content>
#   read_batch_progress <worktree> <batch_num>
#
# NOTE: write_batch_progress and append_progress_section are called by
# run-plan-headless.sh at batch start and after quality gate passes.

# Write a batch header with timestamp to progress.txt
# Usage: write_batch_progress <worktree> <batch_num> <title>
# Returns: 0 on success, 1 on I/O error
write_batch_progress() {
  local worktree="$1" batch_num="$2" title="$3"
  local progress_file="$worktree/progress.txt"
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Ensure trailing newline before new batch header (if file exists and is non-empty)
  if [[ -s "$progress_file" ]]; then
    # Add blank line separator between batches
    echo "" >> "$progress_file" || {
      echo "ERROR: Failed to write to $progress_file" >&2
      return 1
    }
  fi

  echo "## Batch ${batch_num}: ${title} (${timestamp})" >> "$progress_file" || {
    echo "ERROR: Failed to write batch header to $progress_file" >&2
    return 1
  }
}

# Append a named section under the most recent batch header
# Usage: append_progress_section <worktree> <section> <content>
# section: "Files Modified", "Decisions", "Issues Encountered", "State"
# Returns: 0 on success, 1 on I/O error
append_progress_section() {
  local worktree="$1" section="$2" content="$3"
  local progress_file="$worktree/progress.txt"

  echo "### ${section}" >> "$progress_file" || {
    echo "ERROR: Failed to write section header to $progress_file" >&2
    return 1
  }
  echo "$content" >> "$progress_file" || {
    echo "ERROR: Failed to write section content to $progress_file" >&2
    return 1
  }
}

# Extract a single batch's content from progress.txt using awk
# Returns everything from "## Batch N: <title> (timestamp)" up to (but not
# including) the next "## Batch" header or EOF.
#
# The pattern requires the timestamp in parens at end to avoid false matches
# when progress content itself mentions "## Batch N:" in notes.
#
# Exit codes:
#   0 — batch found (content printed, may be empty if batch has no body)
#   1 — batch not found in file
#   2 — progress.txt file does not exist
#
# Usage: read_batch_progress <worktree> <batch_num>
read_batch_progress() {
  local worktree="$1" batch_num="$2"
  local progress_file="$worktree/progress.txt"

  # Validate batch_num is a positive integer
  if [[ ! "$batch_num" =~ ^[0-9]+$ ]]; then
    echo "ERROR: batch_num must be a positive integer, got: '$batch_num'" >&2
    return 1
  fi

  if [[ ! -f "$progress_file" ]]; then
    return 2
  fi

  # Use the timestamp-anchored pattern to avoid false matches on content.
  # Header format: ## Batch N: <title> (YYYY-MM-DDTHH:MM:SSZ)
  # The awk sets found=1 when the target header is matched, then prints
  # subsequent lines until another timestamped batch header is encountered.
  local found
  found=$(awk -v batch="$batch_num" '
    /^## Batch [0-9]+: .+ \([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\)$/ {
      # Extract batch number: field 3, strip trailing colon
      n = $3
      sub(/:$/, "", n)
      if (n == batch) {
        printing = 1
        print
        next
      } else if (printing) {
        exit
      }
    }
    printing { print }
  ' "$progress_file")

  if [[ -z "$found" ]]; then
    # Check whether the batch header exists at all (empty body vs not found)
    if grep -qE "^## Batch ${batch_num}: .+ \([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\)$" "$progress_file" 2>/dev/null; then
      # Batch exists but has no body content — return 0, print nothing
      return 0
    else
      return 1
    fi
  fi

  echo "$found"
  return 0
}
