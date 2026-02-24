---
id: 24
title: "Shared pipeline features must share implementation"
severity: should-fix
languages: [all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Two pipeline stages independently implement the same feature logic and produce different results"
fix: "Both stages import from one module; if different languages, add contract tests"
example:
  bad: |
    # Python: batch pipeline
    def process_batch(items):
        results = [transform(item) for item in items]
        return results

    # JavaScript: real-time pipeline (independently implemented)
    function processStream(item) {
        return transform(item);  // Slightly different logic
    }
  good: |
    # Python shared logic
    # pipeline/transform.py
    def transform(item):
        return item.value * 2

    # batch.py
    from pipeline.transform import transform
    results = [transform(item) for item in items]

    # For JavaScript, if needed separately:
    # Add contract test: both versions produce identical output on test set
---

## Observation

Pipelines often have multiple paths: batch processing, streaming, scheduled jobs. When each path independently implements logic like filtering, validation, or transformation, they diverge. One handles edge cases the other misses, producing inconsistent results.

## Insight

Feature logic encoded in multiple places creates a maintenance burden and a correctness risk. Each implementation is an opportunity for a bug; each update requires changes in N places. The root cause is treating pipeline stages as independent systems when they should share a common contract.

## Lesson

When multiple pipeline stages implement the same feature:

1. **Same language**: Extract logic to a shared module; all stages import from it.
2. **Different languages**: Implement once in the language closest to the data source (usually Python for batch), then wrap in contract tests that verify the other language's implementation produces identical output on a test dataset.
3. **External service**: Deploy once, both stages call the API.

Document the contract: "transform() must handle null, empty string, and values >1000." Then verify both implementations satisfy it. When bugs are found, fix once, verify all paths, deploy once.

This is the DRY principle applied to distributed systems: don't repeat business logic across process boundaries.
