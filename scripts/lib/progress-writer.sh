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

# Write a batch header with timestamp to progress.txt
# Usage: write_batch_progress <worktree> <batch_num> <title>
write_batch_progress() {
    local worktree="$1" batch_num="$2" title="$3"
    local progress_file="$worktree/progress.txt"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Ensure trailing newline before new batch header (if file exists and is non-empty)
    if [[ -s "$progress_file" ]]; then
        # Add blank line separator between batches
        echo "" >> "$progress_file"
    fi

    echo "## Batch ${batch_num}: ${title} (${timestamp})" >> "$progress_file"
}

# Append a named section under the most recent batch header
# Usage: append_progress_section <worktree> <section> <content>
# section: "Files Modified", "Decisions", "Issues Encountered", "State"
append_progress_section() {
    local worktree="$1" section="$2" content="$3"
    local progress_file="$worktree/progress.txt"

    echo "### ${section}" >> "$progress_file"
    echo "$content" >> "$progress_file"
}

# Extract a single batch's content from progress.txt using awk
# Returns everything from "## Batch N:" up to (but not including) the next "## Batch" or EOF
# Usage: read_batch_progress <worktree> <batch_num>
read_batch_progress() {
    local worktree="$1" batch_num="$2"
    local progress_file="$worktree/progress.txt"

    if [[ ! -f "$progress_file" ]]; then
        return 0
    fi

    awk -v batch="$batch_num" '
        /^## Batch [0-9]+:/ {
            # Extract batch number: split "## Batch N: ..." on spaces
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
    ' "$progress_file"
}
