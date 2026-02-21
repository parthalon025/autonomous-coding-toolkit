---
id: 0048
title: "Multi-batch plans need explicit integration wiring batch"
severity: should-fix
languages: [all]
category: integration-boundaries
pattern:
  type: semantic
  description: "Multi-batch plan builds components separately but skips the step of wiring them together"
fix: "Plans with 3+ batches must include a final integration wiring batch"
example:
  bad: |
    # Plan with 3 batches:
    Batch 1: Build API endpoint
    Batch 2: Build database schema
    Batch 3: Build client code
    # Missing: wire components together

    # Result: Each piece works in isolation, but together they fail
  good: |
    # Plan with 4 batches:
    Batch 1: Build API endpoint
    Batch 2: Build database schema
    Batch 3: Build client code
    Batch 4: Integration wiring
      - Connect API to database
      - Connect client to API
      - Verify end-to-end flow
      - Run integration tests
---

## Observation
Multi-batch plans build components (API, database, client) independently. Each batch passes its own tests. But components aren't wired together during implementation. Integration happens only at the end, revealing coupling issues, interface mismatches, and missing adapters too late.

## Insight
Batch-driven development optimizes for parallel work but can miss integration points. Components are unit-tested in isolation but may fail when combined. Without an explicit wiring batch, integration is assumed to "just work."

## Lesson
Plans with 3+ batches must include a final integration wiring batch. This batch connects components built in earlier batches, verifies data flows through the full pipeline, and runs end-to-end integration tests. Include this batch in the plan before implementation starts. Test the full system (not just individual components) after wiring is complete.
