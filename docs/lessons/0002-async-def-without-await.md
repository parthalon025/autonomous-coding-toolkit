---
id: 2
title: "async def without await returns truthy coroutine"
severity: blocker
languages: [python]
scope: [language:python]
category: async-traps
pattern:
  type: semantic
  description: "async def function body contains no await, async for, or async with — returns coroutine object instead of result"
fix: "Either add await for async I/O operations, or remove the async keyword if the function does no async work"
example:
  bad: |
    async def get_data():
        return database.query("SELECT *")  # Returns coroutine, not result
  good: |
    async def get_data():
        return await database.query("SELECT *")
---

## Observation
An `async def` function that never uses `await`, `async for`, or `async with` returns a coroutine object instead of its result. Since coroutine objects are truthy, code like `if await get_data():` silently succeeds with a truthy coroutine even when the actual data would be falsy.

## Insight
This is insidious because the function appears to work — it returns something truthy, no exceptions are raised, no warnings are logged. The bug only surfaces when the return value is used for its actual content rather than truthiness.

## Lesson
Every `async def` must contain at least one `await`, `async for`, or `async with`. If it doesn't need any, remove the `async` keyword. This check requires multi-line analysis (scanning the full function body), so it's a semantic check in the lesson-scanner.
