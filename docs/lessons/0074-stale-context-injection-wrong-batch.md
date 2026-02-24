---
id: 74
title: "Stale context injection sends wrong batch's state to next agent"
severity: should-fix
languages: [shell]
scope: [project:autonomous-coding-toolkit]
category: context-retrieval
pattern:
  type: semantic
  description: "Context injection (CLAUDE.md modifications, AGENTS.md generation) from a previous batch persists into the next batch because the injection writes to tracked files and the git-clean check fails, or the injection is not cleaned up between batches."
fix: "Context injection must be idempotent and batch-scoped. Clean up injected context after each batch. Use temporary files or environment variables instead of modifying tracked files."
example:
  bad: |
    # Batch 3 context injected into CLAUDE.md
    # Batch 3 fails, retries
    # Batch 4 starts — still sees Batch 3's context in CLAUDE.md
    # Agent makes decisions based on stale context
  good: |
    # Context injected into /tmp/batch-context.md
    # Passed via --context flag or environment variable
    # Automatically cleaned up between batches
    # Each batch starts with fresh, correct context
---

## Observation
Context injection that modified tracked files (like appending to CLAUDE.md) created dirty git state between batches. The next batch's agent inherited the previous batch's context injection, making decisions based on stale information. When batch 3 failed and batch 4 started, batch 4 still saw batch 3's failure context.

## Insight
Context injection into version-controlled files conflates two lifetimes: the file's permanent content and the batch's temporary context. The git-clean quality gate catches this as "uncommitted changes" but the root cause is architectural — using the wrong persistence mechanism for ephemeral data.

## Lesson
Never inject batch-scoped context into tracked files. Use temporary files, environment variables, or the context budget in `run-plan-context.sh` which is designed for ephemeral, per-batch context injection.
