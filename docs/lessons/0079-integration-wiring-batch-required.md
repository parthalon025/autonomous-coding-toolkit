---
id: 79
title: "Multi-batch plans need an explicit integration wiring batch"
severity: should-fix
languages: [all]
scope: [universal]
category: planning-control-flow
pattern:
  type: semantic
  description: "A multi-batch plan where each batch creates separate components but no batch is dedicated to wiring them together. Each component passes its own tests but the pipeline is disconnected."
fix: "Add an explicit integration wiring batch at the end (or at natural integration points) that connects components and runs end-to-end tests. The wiring batch should have no new feature code — only imports, configuration, and integration tests."
example:
  bad: |
    # Batch 1: Build parser (tests pass)
    # Batch 2: Build formatter (tests pass)
    # Batch 3: Build CLI (tests pass)
    # Result: CLI doesn't call parser, parser doesn't feed formatter
  good: |
    # Batch 1: Build parser (tests pass)
    # Batch 2: Build formatter (tests pass)
    # Batch 3: Wire parser → formatter, integration test
    # Batch 4: Build CLI using wired pipeline, e2e test
---

## Observation
A 5-batch plan created 5 separate components. Each batch had thorough unit tests and all passed. But the components were never wired together — no batch was responsible for integration. The final "verify" step discovered that the components couldn't communicate because they used incompatible interfaces.

## Insight
When each batch is scoped to a single component, integration is an implicit assumption — "someone will wire these together." But in autonomous execution, implicit assumptions don't get executed. Each batch follows its explicit instructions, and if no batch says "wire X to Y", it doesn't happen.

## Lesson
Every multi-batch plan with 3+ components needs at least one explicit integration wiring batch. This batch should: import all components, configure their connections, and run at least one end-to-end test that traces data through the full pipeline. No new feature code — only wiring and verification.
