---
name: verify
description: Self-verification checklist — run before declaring work complete, committing, or creating PRs
disable-model-invocation: true
---

## Dependencies
- Bash tool (git, test runners, linters)

Run a verification pass on the work just completed. Do NOT skip steps.

## Step 1: Check what changed

1. `git diff --stat` — list modified files
2. `git diff --cached --stat` — list staged files
3. If no git repo, list files you created or modified this session

## Step 2: Run automated checks (if available)

Try each in order, skip if not applicable:

1. **Tests:** Look for test runner config. Run tests. Report pass/fail count.
2. **Linter:** Look for linter config. Run linter. Report issue count.
3. **Type check:** Look for `tsconfig.json` or `mypy.ini`. Run type checker.
4. **Build:** If there's a build step, run it.

## Step 2.5: Integration Wiring + Lesson Scanner

**Run this step if the session built multiple components across batches.**

1. **Integration wiring check:** Confirm every shared module built this session is imported/called by its consumer.
2. **Lesson scanner:** Dispatch `lesson-scanner` agent against modified files.
3. **Contract tests:** For parallel feature lists, verify a contract test exists.

## Step 3: Pipeline testing (if service has API, UI, or multi-layer data flow)

### 3a: Horizontal sweep — every endpoint/interface works

Hit every API endpoint, CLI command, and static file with a known input. Confirms the **surface exists and responds.**

### 3b: Vertical trace — one input flows through the entire stack

Submit one real input and trace it through every layer. Confirms **data flows end-to-end and state accumulates correctly.**

### Why both axes are required

Horizontal catches: missing routes, broken static files, schema errors, 500s.
Vertical catches: path prefix mismatches, missing state updates, aggregate bugs.

**If time-constrained:** Run the vertical trace — it catches more integration bugs per minute.

## Step 4: Manual verification checklist

For each file changed, verify:

- [ ] Does the change do what was asked?
- [ ] No secrets committed
- [ ] No debug artifacts left
- [ ] File permissions correct
- [ ] If config changed: service reloaded/restarted?

## Step 5: Report

Present as:

```
VERIFICATION — <date>
Files changed: N
Tests: X passed, Y failed (or N/A)
Lint: X issues (or N/A)
Types: clean (or N/A)
Pipeline (horizontal): X/Y endpoints pass (or N/A)
Pipeline (vertical): data traced input→output / [list gaps] (or N/A)
Manual checks: all clear / [list issues]
```

## Anti-patterns

- NEVER say "looks good" without running actual commands
- NEVER skip the git diff
- NEVER declare work complete if any test fails
