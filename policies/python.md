# Python Policies

Positive patterns for Python codebases. Derived from lessons #25, #30, #33, #37, #43.

## Async Discipline

**Only use `async def` when the function performs I/O.**
Unnecessary async adds complexity without benefit. If there's no `await` inside, it shouldn't be async.

```python
# Pattern: async def must contain await
async def fetch_user(user_id: str) -> User:
    return await db.get(user_id)  # I/O justifies async
```

## Await at Call Sites

**Verify every call to an async function is awaited.**
Missing `await` returns a coroutine object instead of the result — often passes truthiness checks silently.

```python
# Pattern: await at every async call site
user = await fetch_user(user_id)  # not: user = fetch_user(user_id)
```

## SQLite Closing

**Use `closing()` context manager for sqlite3 connections.**
Without it, connections leak on exceptions. The `closing()` wrapper guarantees cleanup.

```python
from contextlib import closing
import sqlite3

with closing(sqlite3.connect("db.sqlite")) as conn:
    cursor = conn.execute("SELECT ...")
```

## Task Error Visibility

**Add a `done_callback` to every `create_task` call.**
Unobserved task exceptions vanish silently. The callback surfaces errors immediately.

```python
task = asyncio.create_task(background_work())
task.add_done_callback(lambda t: t.result() if not t.cancelled() else None)
```

## Subscriber Lifecycle

**Store callback references on `self` and unsubscribe in `shutdown()`.**
Anonymous lambda callbacks can't be unsubscribed. Leaked subscriptions cause duplicate processing after restart.

```python
class MyService:
    def __init__(self, bus):
        self._unsub = bus.subscribe("event", self._handle)

    async def shutdown(self):
        self._unsub()
```

## Install via Module

**Use `.venv/bin/python -m pip` instead of `.venv/bin/pip`.**
Direct pip invocation can resolve to Homebrew Python on mixed-runtime systems, installing packages into the wrong environment.

```bash
# Pattern: always invoke pip through python -m
.venv/bin/python -m pip install pytest-xdist
```
