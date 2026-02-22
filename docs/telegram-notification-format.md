# Telegram Notification Format

Standard notification templates for `run-plan.sh` and Code Factory pipeline execution.

## STARTED

Sent once at pipeline launch.

```
🔧 <Feature Name> - STARTED

Project: <project-name>
Plan: <plan-filename>.md
Repo: github.com/parthalon025/<repo-name>

<N> batches, <M> tasks:
- B1: <batch title>
- B2: <batch title>
- ...

Running headless with retry on failure.
```

## Batch Complete (Success)

Sent after each batch passes the quality gate.

```
✅ <Feature Name> — B<N>/<total> complete (<duration>s)

*<Batch Title>*

Tasks completed:
• T<N>: <description of what was built/changed>
• T<N+1>: <description>
• ...

Tests: <file count> files, <assertion count> assertions (↑<delta>)
Quality gate: PASSED

Errors during batch: <none | list>
Lessons triggered: <none | lesson IDs>

B<N+1> starting: <next batch title>
```

## Batch Complete (Failure)

Sent when a batch fails after all retries.

```
❌ <Feature Name> — B<N>/<total> FAILED

*<Batch Title>*

Attempt <N> of <max>:
Error: <error description>
Quality gate: FAILED (<reason>)

Errors captured:
• <specific error 1>
• <specific error 2>

Lessons triggered: <lesson IDs if applicable>
Action: <retry|stop|skip>
```

## COMPLETED

Sent when all batches finish.

```
🏁 <Feature Name> - COMPLETED

Project: <project-name>
Duration: <total time>

Batches: <N>/<N> passed
Tests: <final count> (<total delta from start>)
Commits: <commit count>

Errors during run:
• B1: <none | error summary>
• B2: <none | error summary>
• ...

Lessons triggered: <none | lesson IDs and descriptions>
```

## Key Fields

| Field | Source | Purpose |
|-------|--------|---------|
| Tasks completed | Batch commit diff | What was built — not what was planned |
| Tests | `run-all-tests.sh` output | File count + assertion delta |
| Errors during batch | Quality gate output, retry logs | What went wrong |
| Lessons triggered | `lesson-check.sh` output | Anti-patterns detected in new code |
| Duration | `.run-plan-state.json` durations | Wall clock per batch |
