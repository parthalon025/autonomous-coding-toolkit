---
id: 3
title: "asyncio.create_task without done_callback swallows exceptions"
severity: should-fix
languages: [python]
scope: [language:python]
category: silent-failures
pattern:
  type: semantic
  description: "create_task() call without add_done_callback within 5 lines — untracked task may swallow exceptions silently"
fix: "Add a done_callback that logs exceptions: task.add_done_callback(lambda t: t.exception() and logger.error(...))"
example:
  bad: |
    task = asyncio.create_task(process_event(data))
    # No callback — if process_event raises, you'll never know
  good: |
    task = asyncio.create_task(process_event(data))
    task.add_done_callback(lambda t: t.exception() and logger.error("Task failed", exc_info=t.exception()))
---

## Observation
`asyncio.create_task()` launches a coroutine as a background task. If the task raises an exception and nobody awaits it or checks its result, Python logs a "Task exception was never retrieved" warning at garbage collection time — which may be much later or not at all.

## Insight
Fire-and-forget tasks are a common pattern but they create invisible failure paths. The exception is silently stored in the task object and only surfaces (maybe) when the task is garbage collected.

## Lesson
Every `create_task()` call should be followed within 5 lines by `add_done_callback()` that handles exceptions. Alternatively, store the task and await it later.
