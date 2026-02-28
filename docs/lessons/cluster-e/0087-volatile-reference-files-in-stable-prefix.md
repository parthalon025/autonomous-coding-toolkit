---
id: 87
title: "Frequently-changing files in stable context prefix defeat prompt caching"
severity: nice-to-have
languages: [all]
scope: [project:autonomous-coding-toolkit]
category: context-retrieval
pattern:
  type: semantic
  description: "Files that change frequently (progress.txt, state files, current batch tasks) are included in the stable prefix section of the batch prompt. Any change to these files invalidates the cache for the entire prefix, eliminating the 83% cost reduction from prompt caching."
fix: "The stable prefix must contain only truly stable content: CLAUDE.md, lesson summaries, skill definitions. All per-batch content (progress.txt, prior summaries, current tasks) goes in the variable suffix."
positive_alternative: "Classify every context section as stable (unchanged across batches) or variable (changes per batch). Stable → prefix. Variable → suffix. Never mix. If unsure, it's variable."
example:
  bad: |
    STABLE_PREFIX = [CLAUDE.md] + [progress.txt] + [lessons]
    # progress.txt changes every batch — cache miss every batch
    # Cost savings: $0 (same as no caching)
  good: |
    STABLE_PREFIX = [CLAUDE.md] + [lessons] + [skill definitions]
    VARIABLE_SUFFIX = [progress.txt] + [prior summaries] + [current batch]
    # STABLE_PREFIX unchanged for 5 batches → 83% cache hit rate
---

## Observation

The prompt caching implementation placed `progress.txt` in the stable prefix because it "rarely changes." In practice, `progress.txt` is appended after every batch. Cache hit rate was 0% because the prefix changed every batch. The cost savings modeled at 83% were not realized — the run cost the same as before caching was implemented.

## Insight

Prompt caching works by hashing the prefix and returning a cache hit if the hash matches. Any change to any byte of the prefix is a cache miss. "Rarely changes" is not "never changes" — and append-only files like `progress.txt` change every batch by definition. The discipline of separating stable from variable content must be absolute.

## Lesson

Draw a hard line between stable and variable context. Stable = content that is identical across all batches of a run (CLAUDE.md, lesson database, skill definitions). Variable = content that changes per batch (progress.txt, prior batch summaries, current batch tasks, referenced file contents). Progress.txt is variable. Prior summaries are variable. Batch tasks are variable. When in doubt, classify as variable.
