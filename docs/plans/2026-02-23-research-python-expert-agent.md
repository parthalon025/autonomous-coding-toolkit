# Research: Python Expert Claude Code Agent

**Date:** 2026-02-23
**Status:** Complete
**Confidence:** High on tool landscape; Medium on agent structure (novel combination)
**Cynefin domain:** Complicated — knowable with expert analysis

---

## BLUF

A Python expert agent for Justin's stack (HA, Telegram, Notion, Ollama) should be built as a **review-mode Claude Code subagent** that extends the existing `lesson-scanner` with three new scan groups: async discipline, WebSocket lifecycle, and type safety. The tooling ecosystem (ruff RUF006/RUF029, flake8-async ASYNC2xx, semgrep) provides the detection vocabulary; the agent's value-add is contextual judgment on patterns the linters cannot classify (e.g., "is this `async def` waiting on I/O or not?"). Build as `.claude/agents/python-expert.md`.

---

## Section 1: Claude Code Custom Agents — Pattern Survey

### Sources

- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) — 100+ production subagents
- [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) — architect agent pattern
- [Anthropic subagent docs](https://code.claude.com/docs/en/sub-agents)

### Findings

**Structural pattern (frontmatter + prose):**
```yaml
---
name: python-expert
description: "Use this agent when you need to review Python code for async discipline, resource lifecycle, and type safety in asyncio/MQTT/SQLite/WebSocket contexts."
tools: Read, Grep, Glob, Bash
model: sonnet
---
```

The description field controls automatic dispatch — Claude routes to the agent when user intent matches. Be specific: generic descriptions cause false invocations.

**python-pro agent (VoltAgent) — key elements:**
- Type hints for all function signatures and class attributes
- Async/await for I/O-bound operations (but no mechanism to enforce the "only if I/O" constraint)
- Task groups and exception handling mentioned but not operationalized
- No project-specific scan patterns — too generic

**code-reviewer agent (VoltAgent) — model choice:**
- Uses `model: opus` — correct for architectural review where judgment depth matters
- Checklist-driven review with cyclomatic complexity, coverage, resource leaks
- Performance analysis section includes "async patterns" and "resource leaks" — aligned with our needs

**architect agent (everything-claude-code):**
- Uses `model: opus`, read-only tools (`Read, Grep, Glob`)
- Trade-off analysis format: Pros / Cons / Alternatives / Decision
- Explicitly scoped to planning, not code production — separation of concerns

**Gap in all surveyed agents:** None encode project-specific lesson numbers, specific API patterns (MQTT subscribe teardown, sqlite3.closing()), or scan groups with grep patterns. They describe *what* to check but not *how* to mechanically find it. The lesson-scanner agent (existing) is more operationally precise than any public example.

**Adoption decision:** Use lesson-scanner's grep-pattern-per-scan-group structure as the model. The python-expert agent should extend lesson-scanner's format with three new groups, not replace it.

---

## Section 2: Async Discipline Tools

### Sources

- [flake8-async (python-trio)](https://github.com/python-trio/flake8-async) — the canonical asyncio linter
- [ruff ASYNC rules](https://docs.astral.sh/ruff/rules/) — flake8-async rules ported to ruff
- [ruff RUF029 unused-async](https://docs.astral.sh/ruff/rules/unused-async/) — detects `async def` without I/O
- [ruff RUF006 asyncio-dangling-task](https://docs.astral.sh/ruff/rules/asyncio-dangling-task/) — detects create_task without reference
- [flake8-async ASYNC300 create-task-no-reference](https://github.com/python-trio/flake8-async/issues/207)
- [SuperFastPython asyncio linting guide](https://superfastpython.com/lint-asyncio-code/)

### Key Rules Mapped to Production Failures

**Lesson #25 / #30 — `async def` without I/O:**
- **RUF029** (ruff preview): "Checks for functions declared `async` that do not `await` or otherwise use features requiring the function to be declared async." This is exactly Lesson #25.
- Status: Preview mode (`--preview` flag required). Not in ruff stable yet.
- Workaround: The existing lesson-scanner Scan 1a (reads function body for `await` presence) is the operative check until RUF029 stabilizes.

**Lesson #43 — `create_task` without done_callback:**
- **RUF006**: "Checks for `asyncio.create_task` and `asyncio.ensure_future` calls that do not store a reference to the returned result."
- Rule is stable (added v0.0.247). Detects the reference-not-stored case.
- Limitation: RUF006 does not require `add_done_callback` — it accepts storing the reference in any variable. The lesson requires both: store reference AND add_done_callback for error visibility.
- Agent check must go beyond RUF006: for each `create_task` call, verify that the task variable has `.add_done_callback(` within 5 lines.

**Lesson #25 / #30 — blocking calls in async context:**
- **ASYNC210**: "Async functions should not call blocking HTTP methods"
- **ASYNC220–222**: Blocking subprocess methods in async context
- **ASYNC230**: "Async functions should not open files with blocking methods like `open`" — directly relevant to HA/Notion sync code
- **ASYNC251**: "Blocking call to `time.sleep()` in async context"
- All are stable in ruff (no `--preview` needed).

**Missing await at call sites (Lesson #25, #30):**
- No static rule catches a missing `await` for a project-specific async function — these are unknown to linters.
- Python's `asyncio` emits `RuntimeWarning: coroutine 'X' was never awaited` at runtime, but this is silent in logs unless `asyncio.get_event_loop().set_debug(True)` is set.
- Agent approach: grep for calls to known async functions without preceding `await`. Requires project-specific pattern list.

**Recommended ruff configuration (pyproject.toml):**
```toml
[tool.ruff.lint]
select = [
    "ASYNC",  # flake8-async rules (blocking calls, async discipline)
    "RUF006", # asyncio-dangling-task (create_task without reference)
    "RUF029", # unused-async (async def without I/O) -- requires --preview
    "B",      # flake8-bugbear (general design problems)
]
```

---

## Section 3: SQLite Lifecycle

### Sources

- [Python docs sqlite3](https://docs.python.org/3/library/sqlite3.html)
- [Robin's Blog — sqlite3 context manager gotcha](https://blog.rtwilson.com/a-python-sqlite3-context-manager-gotcha/)
- [alexwlchan TIL — sqlite3 context manager doesn't close](https://alexwlchan.net/til/2024/sqlite3-context-manager-doesnt-close-connections/)
- [Python discuss — implicitly close sqlite3 with context managers](https://discuss.python.org/t/implicitly-close-sqlite3-connections-with-context-managers/33320)
- [Simple sqlite3 context manager gist](https://gist.github.com/miku/6522074)

### Findings

**The core misunderstanding (Lesson #33):**
```python
# WRONG — does NOT close the connection on exit
with sqlite3.connect("db.sqlite3") as conn:
    conn.execute(...)
# conn is still open here

# RIGHT — closes on exit
from contextlib import closing
with closing(sqlite3.connect("db.sqlite3")) as conn:
    conn.execute(...)
```

The `sqlite3.Connection.__exit__` method commits or rolls back the transaction but explicitly does *not* close the connection. This is documented but widely misread. Python's discussion forum has an open thread (2023) about adding implicit close to the context manager — not yet resolved as of 2025.

**Detection pattern (already in lesson-scanner Scan 3c):**
```
pattern: sqlite3\.connect\(
glob: **/*.py
```
Read ±5 lines. If not wrapped in `closing(...)` or an explicit `conn.close()` in a `finally` block, flag as Should-Fix.

**Async SQLite:**
For async code (HA, Telegram bots), the standard is `aiosqlite`, which provides an async context manager that *does* close the connection:
```python
async with aiosqlite.connect("db.sqlite3") as db:
    await db.execute(...)
# connection closed here
```
The agent should flag synchronous `sqlite3.connect` inside `async def` as a blocking I/O violation (ASYNC230 covers `open`; sqlite3 is not yet covered by ruff — check manually).

---

## Section 4: Python Code Review Bots — Architectural Review

### Sources

- [DeepSource Python anti-patterns](https://deepsource.com/blog/8-new-python-antipatterns)
- [semgrep-rules (semgrep/semgrep-rules)](https://github.com/semgrep/semgrep-rules)
- [Trail of Bits semgrep rules](https://github.com/trailofbits/semgrep-rules)
- [quantifiedcode/python-anti-patterns](https://github.com/quantifiedcode/python-anti-patterns)
- [charlax/professional-programming antipatterns](https://github.com/charlax/professional-programming/blob/master/antipatterns/error-handling-antipatterns.md)

### Findings

**Semgrep vs ruff vs pylint — decision matrix:**

| Tool | Strength | Weakness | Use case |
|------|----------|----------|----------|
| ruff | Fast, stable, 800+ rules, CI-friendly | Cannot do cross-file analysis, no custom AST traversal | Pre-commit gate, CI |
| semgrep | Semantic pattern matching, cross-file, custom rules | Slower, YAML rule syntax | Architectural checks, custom patterns |
| pylint | Mature, configurable | Slow, noisy | Optional second pass |
| Agent (LLM) | Contextual judgment, project-specific knowledge | Cannot run at CI speed | Review gate on PR/commit |

**Semgrep rules relevant to Justin's stack:**
- `python.lang.security.audit.dangerous-asyncio-create-exec-audit` — asyncio exec injection
- Custom rule opportunity: write a semgrep rule for `sqlite3.connect` not wrapped in `closing()`
- Trail of Bits rules: focus on security rather than lifecycle, but include good error handling patterns

**DeepSource patterns (anti-patterns beyond basic linting):**
1. Using mutable default arguments (`def f(x=[])`)
2. Using `type()` instead of `isinstance()`
3. Comparison to `None` with `==` instead of `is`
4. Bare `raise` in wrong context
5. Not using context managers for file/resource handling

**charlax error-handling anti-patterns (directly relevant):**
- Silencing errors: `except Exception: pass` (Lesson #7)
- Catching too broadly, then re-raising wrong exception
- Not logging before returning fallback (Lesson #7)
- Missing `exc_info=True` on exception log calls (Lesson #43)

**Architectural review dimension missing from all tools:**
None of the tools above can detect:
- "Is this MQTT subscription paired with an unsubscribe in shutdown?" (Lesson #37)
- "Is this callback stored as `self._unsub = subscribe(...)` so it can be cancelled?" (Lesson #37)
- "Does this class with a subscriber have a `shutdown()` or `async_will_remove_from_hass()`?" (Lesson #37)
These require reading class structure across methods — semantic analysis that only an LLM agent can do.

---

## Section 5: Python Anti-Pattern Detection — Resource Lifecycle

### Sources

- [flake8-bugbear (PyCQA)](https://github.com/PyCQA/flake8-bugbear) — design problem warnings
- [HA MQTT async example](https://github.com/home-assistant/example-custom-config/blob/master/custom_components/mqtt_basic_async/__init__.py)
- [HA async developer docs](https://developers.home-assistant.io/docs/asyncio_working_with_async/)
- [asyncdef/eventemitter](https://github.com/asyncdef/eventemitter) — async event emitter patterns
- [aiopubsub (PyPI)](https://pypi.org/project/aiopubsub/) — pub/sub lifecycle patterns

### Findings

**Subscriber lifecycle pattern (Lesson #37):**

The canonical HA pattern stores the unsubscribe reference:
```python
class MyEntity:
    def __init__(self):
        self._unsub_state = None  # must be stored on self

    async def async_added_to_hass(self):
        # Store reference — if you don't store it, you can't unsubscribe
        self._unsub_state = async_track_state_change_event(
            self.hass, self.entity_id, self._handle_state_change
        )

    async def async_will_remove_from_hass(self):
        if self._unsub_state:
            self._unsub_state()  # teardown paired with setup
            self._unsub_state = None
```

The HA example code (`mqtt_basic_async/__init__.py`) uses `await hass.components.mqtt.async_subscribe(topic, message_received)` but the returned unsubscribe callable is not stored — this is the exact anti-pattern from Lesson #37.

**Detection approach:**
1. Grep for `.subscribe(`, `.async_track_state_change(`, `.listen(`, `.on_event(`
2. For each file with subscribe calls, check that:
   - The result is assigned to `self._something`
   - The class has a method containing the corresponding cancel/unsubscribe call
3. Files with subscribe but no teardown = Blocker

**WebSocket send guard (Lesson #34):**

The websockets library recommends EAFP (try/except over state-check):
```python
# WRONG — race condition between check and send
if ws.open:
    await ws.send(data)

# RIGHT — EAFP with ConnectionClosed handling
try:
    await ws.send(data)
except websockets.exceptions.ConnectionClosed:
    logger.warning("WebSocket send failed: connection closed")
    self._ws = None
```

Static detection: grep for `await.*\.send(` inside `async def` and verify try/except wrapping. Unguarded sends are Should-Fix.

**Resource lifecycle checklist (consolidated from lessons #33, #34, #37, #43):**

| Resource | Open pattern | Must close with | Agent check |
|----------|-------------|-----------------|-------------|
| sqlite3 | `sqlite3.connect()` | `contextlib.closing()` or explicit `finally: conn.close()` | Scan 3c (existing) |
| aiosqlite | `async with aiosqlite.connect()` | Built-in (context manager closes) | Flag if used outside `async with` |
| WebSocket | `await ws.send()` | try/except ConnectionClosed | New scan group |
| MQTT sub | `.subscribe()` | Return value stored + `unsubscribe()` in shutdown | New scan group |
| asyncio task | `create_task()` | Store ref + `.add_done_callback()` | Extend Scan 3d |

---

## Section 6: Type Safety and Runtime Validation

### Sources

- [Python typing guide 2025 (Medium)](https://khaled-jallouli.medium.com/python-typing-in-2025-a-comprehensive-guide-d61b4f562b99)
- [Type-Safe Python: Pyright + Pydantic (Medium)](https://medium.com/pythoneers/type-safe-python-leveraging-pyright-and-pydantic-for-reliable-applications-2a081e137d00)
- [Type Safety in Python: MyPy, Pydantic, Runtime Validation (dasroot.net)](https://dasroot.net/posts/2026/02/type-safety-python-mypy-pydantic-runtime-validation/)
- [Beartype runtime type checking](https://codecut.ai/beartype-fast-efficient-runtime-type-checking-for-python/)
- [awesome-python-typing (typeddjango)](https://github.com/typeddjango/awesome-python-typing/blob/master/README.md)

### Findings

**Two-layer model (static + runtime):**

Static analysis (mypy/pyright) catches type errors at write time. Runtime validation (pydantic/beartype) catches bad external data (MQTT payloads, API responses, HA state values) at execution time. Both layers are needed; neither replaces the other.

**Tool selection for Justin's stack:**

| Layer | Tool | Rationale |
|-------|------|-----------|
| Static | pyright (strict mode) | Faster than mypy, VSCode integration, catches `Optional` unwrapping |
| Runtime boundary | Pydantic v2 | Parses MQTT payloads, HA state data, Notion API responses — all external |
| Runtime hot paths | beartype | Zero-overhead decorator for internal functions where pydantic is too heavy |
| Type stubs | types-requests, types-aiofiles | Cover third-party libs without inline stubs |

**Patterns to enforce:**

1. **All public function signatures typed:** No bare `Any` without `# type: ignore` comment explaining why
2. **External data through Pydantic:** Any data from MQTT, HA state machine, Telegram updates, Notion API must pass through a `BaseModel` before use in business logic
3. **`Optional[X]` unwrapped before use:** Pyright strict mode catches `T | None` used as `T`, but the agent should verify `.get()` usage on dicts and explicit None guards
4. **TypedDict for dicts with known schema:** HA state attributes, MQTT payloads — `TypedDict` is lighter than `BaseModel` for read-only structures

**Detection patterns for agent:**
```
# Missing return type annotation
pattern: def \w+\([^)]*\)\s*:(?!\s*->)
# Missing argument type annotations (functions with args but no types)
pattern: def \w+\(\w+\s*[,)](?!\s*:\s*\w)
```
Flag untyped public functions as Nice-to-Have. Flag untyped boundary functions (ones that receive external data) as Should-Fix.

---

## Section 7: Synthesis — Best Patterns to Adopt

### What works, consolidated across all sources

**Detection vocabulary (what to check):**

| Anti-pattern | Detection tool | Lesson |
|-------------|----------------|--------|
| `async def` without I/O | RUF029 (preview) + agent body scan | #25, #30 |
| Blocking call in async | ASYNC210/ASYNC230/ASYNC251 (ruff) | #25 |
| `create_task` with no reference | RUF006 (ruff stable) | #43 |
| `create_task` with reference but no `done_callback` | Agent scan (ruff insufficient) | #43 |
| Missing `await` at call site | Runtime warning + agent context read | #25 |
| `sqlite3.connect` without `closing()` | Lesson-scanner Scan 3c | #33 |
| WebSocket send without try/except | Agent scan | #34 |
| Subscribe without stored reference | Agent scan | #37 |
| Subscribe without paired unsubscribe | Agent scan | #37 |
| Bare except with pass/return | Hookify (blocked) + lesson-scanner 3a | #7 |
| Exception log without `exc_info=True` | Lesson-scanner 3e | #43 |
| Untyped external boundary functions | Agent annotation check | — |

**Agent vs. linter division of labor:**

- **Linters (ruff, flake8-async):** Syntactic patterns with near-zero false positives. Run in pre-commit hook. Do not duplicate in agent.
- **Lesson-scanner agent:** Semantic patterns requiring ±context read (async def body scan, subscription teardown, create_task callback). Already exists — extend, don't replace.
- **Python-expert agent:** Project-specific judgment that requires understanding the codebase as a system. WebSocket lifecycle, subscriber patterns in HA context, type safety at external boundaries.

**Model selection:** sonnet for scan groups (mechanical); opus for architectural review pass (judgment). Two modes or two agents.

---

## Section 8: Recommended Agent Structure

### Option A: Extend lesson-scanner (recommended)

Add three new scan groups to the existing `lesson-scanner.md`:

**Scan Group 7: WebSocket Lifecycle (Lesson #34)**
- Pattern: `await.*\.(send|recv)\(` inside `async def`
- Check: is it wrapped in `try: ... except.*ConnectionClosed`?
- Flag unguarded sends: Should-Fix

**Scan Group 8: Async SQLite (Lesson #33)**
- Pattern: `sqlite3\.connect\(` inside `async def`
- Flag: synchronous sqlite3 in async context is blocking I/O — use aiosqlite
- Pattern: `aiosqlite\.connect\(` outside `async with`
- Flag: connection not used as context manager — may not close on exception

**Scan Group 9: Type Boundary Violations**
- Pattern: `def \w+\([^)]*mqtt\|payload\|state\|update\|event[^)]*\)` without `BaseModel` in body
- Flag: external data entering business logic without Pydantic validation — Nice-to-Have

Rationale: extending lesson-scanner keeps all scan logic in one place, numbered consistently, and means `/audit` runs everything.

### Option B: Standalone python-expert agent (if scan volume grows)

Create `/home/justin/.claude/agents/python-expert.md` as a dedicated review agent that invokes lesson-scanner as a sub-step and adds deeper architectural judgment (class structure analysis, cross-file subscriber lifecycle, type coverage assessment). Use `model: opus`.

**When to choose Option B:** When you want the agent to do a full architectural review that produces recommendations, not just a violation list. If the primary use is "scan this codebase before commit," Option A is sufficient.

### Recommended config additions (pyproject.toml for all Python projects)

```toml
[tool.ruff]
target-version = "py312"

[tool.ruff.lint]
select = [
    "E", "W",      # pycodestyle
    "F",           # pyflakes
    "B",           # flake8-bugbear
    "ASYNC",       # flake8-async (blocking calls in async context)
    "RUF006",      # asyncio-dangling-task
    "UP",          # pyupgrade
    "SIM",         # flake8-simplify
]
# Enable when ruff preview stabilizes:
# "RUF029",       # unused-async (async def without I/O)

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["B"]

[tool.pyright]
pythonVersion = "3.12"
typeCheckingMode = "strict"
```

### Immediate next actions (ranked by impact)

1. **Add RUF006 to ruff config** in ha-aria, autonomous-coding-toolkit, and any Telegram bot repos — catches Lesson #43 create_task pattern at commit time, zero agent cost.
2. **Add ASYNC rules to ruff config** — catches blocking calls in async context (ASYNC210, ASYNC230, ASYNC251) without running the agent.
3. **Extend lesson-scanner with Scan Group 7 (WebSocket lifecycle)** — the one scan group not yet covered by any existing tool.
4. **Write python-expert agent** if architectural review (beyond grep patterns) is needed for ha-aria specifically — that codebase has the highest density of subscriber lifecycle complexity.

---

## References

- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents)
- [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code)
- [python-trio/flake8-async](https://github.com/python-trio/flake8-async)
- [ruff rules index](https://docs.astral.sh/ruff/rules/)
- [ruff RUF006 asyncio-dangling-task](https://docs.astral.sh/ruff/rules/asyncio-dangling-task/)
- [ruff RUF029 unused-async](https://docs.astral.sh/ruff/rules/unused-async/)
- [semgrep-rules](https://github.com/semgrep/semgrep-rules)
- [quantifiedcode/python-anti-patterns](https://github.com/quantifiedcode/python-anti-patterns)
- [charlax/professional-programming antipatterns](https://github.com/charlax/professional-programming/blob/master/antipatterns/error-handling-antipatterns.md)
- [alexwlchan — sqlite3 context manager doesn't close](https://alexwlchan.net/til/2024/sqlite3-context-manager-doesnt-close-connections/)
- [Robin's Blog — sqlite3 gotcha](https://blog.rtwilson.com/a-python-sqlite3-context-manager-gotcha/)
- [HA async developer docs](https://developers.home-assistant.io/docs/asyncio_working_with_async/)
- [HA MQTT async example](https://github.com/home-assistant/example-custom-config/blob/master/custom_components/mqtt_basic_async/__init__.py)
- [websockets library docs](https://websockets.readthedocs.io/en/stable/faq/server.html)
- [awesome-python-typing](https://github.com/typeddjango/awesome-python-typing/blob/master/README.md)
- [SuperFastPython asyncio linting](https://superfastpython.com/lint-asyncio-code/)
