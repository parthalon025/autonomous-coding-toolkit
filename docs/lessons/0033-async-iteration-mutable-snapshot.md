---
id: 33
title: "Async iteration over mutable collections needs snapshot"
severity: blocker
languages: [python]
category: async-traps
pattern:
  type: syntactic
  regex: "for .+ in self\\..+:"
  description: "Iterating over instance attribute in async function without snapshot"
fix: "Snapshot before iterating: for item in list(my_set):"
example:
  bad: |
    class EventDispatcher:
        def __init__(self):
            self.subscribers = set()

        async def dispatch(self, event):
            # Iterating over mutable set in async context
            for subscriber in self.subscribers:  # Can raise "Set changed during iteration"
                await subscriber.handle(event)

        async def unsubscribe(self, subscriber):
            self.subscribers.discard(subscriber)
  good: |
    class EventDispatcher:
        def __init__(self):
            self.subscribers = set()

        async def dispatch(self, event):
            # Snapshot before iterating
            subscribers_copy = list(self.subscribers)
            for subscriber in subscribers_copy:
                await subscriber.handle(event)

        async def unsubscribe(self, subscriber):
            self.subscribers.discard(subscriber)
---

## Observation

In async contexts, iterating over a mutable collection (set, dict) that can be modified by concurrent code raises `RuntimeError: Set changed during iteration`. Synchronous iteration is safe because the event loop is blocked; async iteration is not.

## Insight

Async/await allows other tasks to run between iterations. If another task modifies the collection you're iterating over, Python raises an error. The instinct is to ignore this risk in single-threaded async code, but multiple tasks can run in the same thread.

## Lesson

When iterating over a collection in an async function:

1. **Always snapshot first**: `for item in list(collection)` creates a snapshot immune to concurrent modification
2. **Copy the right way**:
   - Sets: `list(my_set)`
   - Dicts: `dict(my_dict)` or `list(my_dict.items())`
   - Lists: `my_list.copy()` or `list(my_list)`
3. **Verify the pattern**: Grep for `for .+ in self\\.` in async functions and check for snapshots

Pattern:

```python
async def broadcast(self):
    # Snapshot before any await
    handlers_copy = list(self.handlers)
    for handler in handlers_copy:
        await handler.process()
```

Test by subscribing/unsubscribing in a concurrent task while dispatching, and verify no RuntimeError is raised.

This is Python-specific. JavaScript's for-of and async iteration have different semantics, but the same principle applies: if concurrent code modifies the collection, snapshot first.
