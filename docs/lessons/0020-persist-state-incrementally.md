---
id: 20
title: "Persist state incrementally before expensive work"
severity: should-fix
languages: [all]
category: silent-failures
pattern:
  type: semantic
  description: "Long-running process saves state only at the end, losing all progress on crash"
fix: "Checkpoint state after each logical unit of work"
example:
  bad: |
    def process_large_dataset(items):
        results = []
        for item in items:
            result = expensive_operation(item)
            results.append(result)
        save_results(results)  # All progress lost if crash occurs here
  good: |
    def process_large_dataset(items):
        for i, item in enumerate(items):
            result = expensive_operation(item)
            save_checkpoint(result, i)  # State saved after each unit
---

## Observation

Long-running processes that accumulate work and save state only at the end are vulnerable to catastrophic data loss. A 2-hour batch job that crashes during the final save step restarts from zero, repeating 2 hours of work.

## Insight

State persistence is a trade-off between granularity and overhead. The instinct is to minimize I/O by batching writes, but this violates the fundamental reliability principle: *work that has been completed should not be lost*. Progress checkpoints have minimal overhead (typically <5% in database-backed systems) and prevent the infinite-restart failure mode.

## Lesson

Checkpoint state after each logical unit of work, not just at the end. Use one of these patterns:

- **Database transactions**: Commit after each logical unit, not at the end
- **State files**: Write incremental snapshots (e.g., `batch_001_complete.json`)
- **Message queue acknowledgment**: Ack each message after processing, not at the end of the batch
- **Progress markers**: Track completed work in a separate file, read on startup to resume

Always verify the checkpoint write succeeds before proceeding. If a process crashes, it should resume from the last checkpoint, never restart from zero.
