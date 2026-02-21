---
id: 34
title: "Caller-side missing await silently discards work"
severity: blocker
languages: [python, javascript]
category: async-traps
pattern:
  type: semantic
  description: "Async function called without await, coroutine created but never executed"
fix: "Always await async calls; use create_task() with done_callback for fire-and-forget"
example:
  bad: |
    async def save_to_database(data):
        await db.save(data)
        print("Saved!")

    async def main():
        save_to_database(data)  # Missing await!
        # Function never executed, "Saved!" never prints
        print("Done")  # Prints immediately, before save completes

    # Result: data may never be saved
  good: |
    async def main():
        # Option 1: await (blocking)
        await save_to_database(data)

        # Option 2: fire-and-forget with task
        task = asyncio.create_task(save_to_database(data))
        task.add_done_callback(handle_save_error)

        print("Done")
---

## Observation

Calling an async function without `await` creates a coroutine object but doesn't execute it. The work is discarded, often silently. In Python, the event loop may warn "coroutine was never awaited"; in JavaScript, it's silent.

## Insight

Async functions are lazy — they return a coroutine/promise that must be awaited to execute. Missing `await` is a type error (object of wrong type is created), but Python's runtime allows it. This is a language design quirk: async functions look like regular functions but require explicit awaiting.

## Lesson

**Always await async calls:**

1. **Default: await**: `await save_to_database(data)`
2. **Fire-and-forget**: If you don't want to block, use `asyncio.create_task()` with error handling:

```python
task = asyncio.create_task(save_to_database(data))
task.add_done_callback(lambda t: t.result() if t.exception() is None else None)
```

3. **Never just call**: `save_to_database(data)` is a bug

Linting:

- Python: Use `pylint` with `no-unused-variable` or linters that detect unawaited coroutines
- JavaScript: Use TypeScript or ESLint with `no-floating-promises` rule

Test: Verify that a fire-and-forget task completes before the program exits. Use a counter or log to verify the callback was called.

This is critical in production: losing async work silently is a data loss bug.
