---
id: 18
title: "Every layer passes its test while full pipeline is broken"
severity: should-fix
languages: [all]
category: integration-boundaries
pattern:
  type: semantic
  description: "Each pipeline layer passes unit tests independently while the full pipeline is broken at integration seams"
fix: "Add at least one end-to-end test tracing a single input through every layer"
example:
  bad: |
    # Layer 1: Data fetch (passes)
    test_fetch: reads from mock DB, returns [User, User, User] ✓

    # Layer 2: Transform (passes)
    test_transform: receives list, returns transformed list ✓

    # Layer 3: Store (passes)
    test_store: receives list, writes to mock storage ✓

    # Integration: Broken!
    # Layer 2 returns dict, Layer 3 expects list → crash
  good: |
    # Unit tests for each layer (all pass)
    test_fetch, test_transform, test_store (as above)

    # Plus: E2E test tracing one record through all layers
    test_full_pipeline:
      input = create_test_user()
      result = fetch(input)  # Layer 1
      result = transform(result)  # Layer 2
      store(result)  # Layer 3
      assert result_in_storage(result)  # Verify end-to-end
---

## Observation
A multi-layer pipeline (data fetch → transform → store → API → UI) has each layer passing its unit tests independently. The full pipeline is broken at the integration seams: layer 1 returns a list, layer 2 expects a dict; layer 3 stores to file, layer 4 queries a database; fields have different names at each boundary.

## Insight
The root cause is testing each layer in isolation with mocked inputs/outputs. Each layer is correct for its inputs, but the outputs of one layer don't match the inputs of the next. The seams are never tested because each test stops at layer boundaries.

## Lesson
Always add at least one end-to-end test that traces a single input through every layer of the pipeline. Don't mock layer outputs — let real data flow through the entire system. This catches integration mismatches immediately. E2E tests are not a replacement for unit tests, they're a mandatory complement.
