---
id: 25
title: "Defense-in-depth: validate at all entry points"
severity: should-fix
languages: [all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Input validation exists at one entry point but not others (API, CLI, WebSocket, cron)"
fix: "Centralize validation in a shared function called by all entry points"
example:
  bad: |
    # REST API: validates user_id
    @app.post('/users/<user_id>')
    def update_user(user_id):
        validate_user_id(user_id)  # Validation here
        return process_update(user_id)

    # But CLI skips validation
    def cli_update(user_id):
        return process_update(user_id)  # No validation!
  good: |
    # Shared validation
    def process_update(user_id):
        validate_user_id(user_id)  # Always validated
        # ... actual logic

    # REST API
    @app.post('/users/<user_id>')
    def update_user(user_id):
        return process_update(user_id)

    # CLI
    def cli_update(user_id):
        return process_update(user_id)  # Validation inherited
---

## Observation

Services often have multiple entry points: REST API, CLI, WebSocket, scheduled jobs. Validation logic gets implemented at one entry point (usually REST, where frameworks make it easy) but bypassed at others. Invalid data flows to the core logic, causing unexpected behavior.

## Insight

Entry point diversity is a feature (flexibility), but it creates a validation surface. Each entry point is a potential bypass. Without centralized validation, the defense is only as strong as the most permissive entry point.

## Lesson

Apply defense-in-depth to input validation:

1. **Centralize**: Move validation into the core logic function, not the entry point handler.
2. **All entry points**: Every path to the core logic must pass through validation — API, CLI, WebSocket, cron, admin UI.
3. **Explicit validation**: Don't rely on type hints or schema inference; call a validation function explicitly.

Pattern:

```
REST API → validate() → process()
CLI      → validate() → process()
WebSocket → validate() → process()
```

If validation is expensive (e.g., database lookup), cache the result. If validation differs per entry point, that's a smell — it means the entry points have different semantics. Either merge them or document the difference explicitly.

Test all entry points with the same invalid input set to verify they all reject it consistently.
