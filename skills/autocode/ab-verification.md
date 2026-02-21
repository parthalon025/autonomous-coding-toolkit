# A/B Verification

Post-completion dual-axis verification for plans with 3+ batches. Catches non-overlapping bug classes that neither strategy alone finds.

## When to Run

After ALL batches are complete, regardless of execution mode. Cost: ~5 minutes, 2 agent runs.

## Process

Dispatch TWO verification agents in parallel:

### Verifier A (Systematic / Bottom-Up)

subagent_type=general-purpose

Check:
- File sizes: flag any file over 300 lines (Python or JSX)
- Test coverage gaps: modules with no corresponding test file
- Anti-patterns: bare `except`, silent `return []`, `sqlite3.connect()` without `closing()`
- Dead config keys: keys registered in config_defaults but never consumed via `get_config_value()`
- Import health: circular imports, unused imports, duplicate exports
- Metrics: total test count, ruff/lint clean, file count by type

### Verifier B (Holistic / Top-Down)

subagent_type=general-purpose

Check:
- Integration boundaries: trace data from producer → consumer, verify key names match
- Module lifecycle: `__init__` vs `initialize()` discipline, subscribe/unsubscribe pairing
- Data flow: follow one real input through every layer to the final output
- Security: no secrets, no hardcoded IPs, no debug artifacts
- Dashboard cohesion: frontend props match backend response keys, shared constants not duplicated

## Report Format

```
A/B VERIFICATION — [date]
Verifier A (bottom-up): [N] critical, [N] important, [N] minor
Verifier B (top-down): [N] critical, [N] important, [N] minor
Overlap: [N] (should be 0)
Combined critical issues: [list]
Combined important issues: [list]
```

## Rules

- If ANY critical issues found: fix them before proceeding to finishing-a-development-branch
- Create fix tasks, implement, re-run affected tests
- Save report to `.ab-verification-report.md`
