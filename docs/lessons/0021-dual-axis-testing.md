---
id: 21
title: "Dual-axis testing: horizontal sweep + vertical trace"
severity: should-fix
languages: [all]
category: integration-boundaries
pattern:
  type: semantic
  description: "Testing only endpoints (horizontal) or only data flow (vertical) misses entire bug classes"
fix: "Run both horizontal sweep (every endpoint) and vertical trace (one input through all layers)"
example:
  bad: |
    # Only test endpoints exist
    def test_api_responses():
        assert client.get('/users').status_code == 200
        assert client.get('/users/1').status_code == 200
    # Missing: verify data actually flows and transforms correctly
  good: |
    # Horizontal: every endpoint responds
    assert client.get('/users').status_code == 200
    # Vertical: one user through all layers
    response = client.post('/users', data={'name': 'Alice'})
    user_id = response.json()['id']
    assert client.get(f'/users/{user_id}').json()['name'] == 'Alice'
---

## Observation

Many test suites validate that endpoints exist and return 2xx status codes, but never verify that data flows end-to-end. A bug where data enters the pipeline but never reaches the database passes horizontal testing but fails in production.

## Insight

Integration bugs exist at layer boundaries: serialization, deserialization, state transitions, and persistence. Horizontal testing (every endpoint exists) confirms the surface. Vertical testing (one input through all layers) confirms the pipeline. Both are required because they catch different bug classes:

- **Horizontal** → missing endpoints, wrong status codes
- **Vertical** → data transformation bugs, missing persistence, state inconsistency

Testing only one axis misses 50% of integration bugs.

## Lesson

After implementing a multi-layer system (API → logic → database, or UI → service → cache), always run dual-axis testing:

1. **Horizontal sweep**: Hit every endpoint/CLI command/UI action. Confirm each responds correctly.
2. **Vertical trace**: Submit one real input and trace it through every layer to the final output. Confirm data flows end-to-end and state accumulates correctly.

Execute vertical first (catches more bugs per minute), then horizontal (completeness check). Both must pass before claiming readiness. Document the vertical trace as a test case you can re-run.
