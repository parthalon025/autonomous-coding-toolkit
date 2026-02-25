# Add a REST Endpoint with Tests

**Complexity:** Simple (1 batch)
**Measures:** Basic execution, TDD compliance

## Task

Add a `/health` endpoint to the project that:
1. Returns HTTP 200 with JSON body `{"status": "ok", "timestamp": "<ISO8601>"}`
2. Has a test that verifies the response status and body structure
3. All tests pass

## Constraints

- Use the project's existing web framework (or add minimal one if none exists)
- Follow existing code style and patterns
- Test must be automated (no manual verification)
