# Code Quality Standards

Shared quality standards injected into all competitor and implementer prompts. Referenced by competitive-mode.md and team-mode implementer prompts.

## File Size & Modularity

- Target ~300 lines per file MAX. If a file exceeds 300 lines, split it into focused modules.
- Each file should have ONE clear responsibility. If you can't describe the file's purpose in one sentence, it's doing too much.
- Extract logical groups into separate files: constants → constants.py, helpers → helpers.py, types → models.py.
- Functions should be short (under 30 lines). If a function needs a comment saying "Step 1... Step 2...", extract each step into a named function.
- Prefer composition over inheritance. Small, focused functions that compose together.
- For frontend: one component per file. Shared hooks/utilities in separate files. If a JSX file exceeds 300 lines, extract sub-components into their own files.

## Code Cohesion

Your code must look like ONE author wrote the whole codebase:

- BEFORE writing anything: read 2-3 existing files in the same package to absorb the project's style — naming conventions, docstring format, import ordering, error handling patterns, logging style.
- Match existing patterns EXACTLY: if the codebase uses `logger = logging.getLogger(__name__)`, do the same. If it uses `from __future__ import annotations`, include it. If functions use type hints, yours must too.
- Naming: follow the codebase's conventions. `_private_helper()` with leading underscore, `UPPER_SNAKE` for module constants, `CamelCase` for classes.
- Imports: group and order (stdlib → third-party → local). Use absolute imports (`from aria.x import Y`).
- Error handling: follow codebase patterns. `logger.warning()` before returning fallback — never bare `except: pass`. Use specific exception types.
- Docstrings: match existing format. One-line for simple helpers, multi-line for complex functions.
- File structure: constants at top, public API in middle, private helpers at bottom.
- DRY: check if utilities exist before writing new ones. Search shared modules, utils directories, sibling modules.
- YAGNI: implement exactly what the spec requires. No extra config options, no "future-proofing" abstractions.
- Frontend: match existing component patterns — same hook usage, prop naming, CSS classes, state management. Read sibling pages before writing.

## Best Practices

- Type hints on all function signatures (args and return).
- Guard clauses over nested conditionals. Return early.
- Descriptive variable names — no single-letter variables except loop counters.
- No magic numbers — extract to named constants.
- Errors should be logged with context before being handled: `logger.warning("Failed to X for entity %s: %s", entity_id, err)`.
- Tests: one test function per behavior. Descriptive test names: `test_returns_empty_list_when_no_entities`.
- Avoid deep nesting (>3 levels). Extract inner logic into helper functions.
