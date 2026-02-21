---
id: 9
title: "Plan parser over-count burns empty API calls"
severity: should-fix
languages: [shell, all]
category: silent-failures
pattern:
  type: semantic
  description: "Plan parser counts batch headers without checking if batch has content"
fix: "Check get_batch_text is non-empty before executing a batch"
example:
  bad: |
    # Parser counts headers
    batch_count=$(grep -c "^## Batch" plan.md)
    for batch in $(seq 1 $batch_count); do
        # Each batch triggers an agent, even if empty
        run_batch "$batch"
    done
  good: |
    # Parser checks if batch has content
    for batch in $(seq 1 $batch_count); do
        text=$(get_batch_text "$batch")
        [[ -z "$text" ]] && continue  # Skip empty batches
        run_batch "$batch"
    done
---

## Observation
A plan parser counts batch headers (e.g., `## Batch 1`, `## Batch 2`) to determine how many batches to execute. If the plan has trailing or empty headers, the count includes them. Each phantom batch spawns an agent context that discovers "nothing to do" — a wasted API call, time, and context.

## Insight
The root cause is counting headers separately from extracting batch content. A header exists (line count is easy) but its content may be empty. Parser assumes every header has work, which is false for malformed or trailing headers.

## Lesson
Never count batch headers separately. Always extract the batch content first, then check if it's non-empty before executing. Skip empty batches silently. This prevents wasted agent spawns and keeps the pipeline efficient.
