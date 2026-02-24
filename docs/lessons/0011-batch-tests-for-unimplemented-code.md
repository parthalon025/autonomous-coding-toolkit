---
id: 11
title: "Batch execution writes tests for unimplemented code"
severity: should-fix
languages: [all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Tests in batch N reference code that won't exist until batch N+1"
fix: "Plan tasks so each batch is self-contained — tests only reference code from the same or earlier batches"
example:
  bad: |
    # Plan with forward-looking test
    ## Batch 3: Add tests for pipeline
    - Write tests that call pipeline.transform() (not written yet)

    ## Batch 4: Implement pipeline
    - Implement the transform() method
  good: |
    # Plan with self-contained batches
    ## Batch 3: Implement pipeline
    - Implement the transform() method

    ## Batch 4: Add tests for pipeline
    - Write tests that call pipeline.transform() (now exists)
---

## Observation
When a plan has batches 1-7 and batch 3's agent writes tests expecting batch 4's code, those tests fail until batch 4 runs. The agent does TDD correctly for its own batch (writes test, implements code) but accidentally creates forward dependencies when tests reference not-yet-implemented code from future batches.

## Insight
The root cause is batching by concern instead of by dependency. The planner thinks "batch 3 is tests, batch 4 is implementation" without considering that tests depend on the code existing. Tests can't pass (or even import) if the code they reference isn't in the codebase yet.

## Lesson
Plan tasks so each batch is self-contained. Tests reference only code from the same batch (TDD: write test, write code) or earlier batches (tested code). Never have batch N's tests reference batch N+1's code. If you need to test something, implement it in the same batch or an earlier batch.
