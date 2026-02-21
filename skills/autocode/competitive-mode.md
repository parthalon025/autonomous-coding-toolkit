# Competitive Mode — Dual-Track Execution

Reference doc for competitive batch execution. Used by `run-plan` when `--mode competitive` is specified or batches are tagged `⚠ CRITICAL`.

## Pre-Flight Exploration

Before spawning competitors, dispatch TWO agents in parallel:

### a) Codebase Explorer (subagent_type=Explore) — internal context:
- Search for files/functions/components mentioned in the batch spec
- Find existing patterns, imports, constants, and conventions relevant to the batch
- Check config key names, API endpoint signatures, and shared module exports
- Note file sizes of files to be modified (flag any already near 300 lines)
- Identify reusable utilities, helpers, and shared components already in the codebase

### b) External Research (subagent_type=general-purpose) — prior art & best practices:
- Search GitHub (via `gh search repos` and WebSearch) for similar implementations
  in the same ecosystem (e.g., "preact dashboard conflict detection", "home assistant
  automation suggestion UI", "python pipeline pattern matching")
- Search for established libraries/patterns that solve the batch's problem domain
  (don't reinvent the wheel — if a well-tested utility exists, reference it)
- Check Context7 docs for relevant framework APIs (via resolve-library-id + query-docs)
- Look for common pitfalls and anti-patterns specific to the batch's technology
- Return: relevant code examples, library recommendations, common patterns to follow,
  and anti-patterns to avoid

### Combine into CONTEXT BRIEF:
Existing codebase patterns, available imports, correct key names, file sizes, external prior art, recommended libraries/patterns, and gotchas. This brief is injected into BOTH competitor prompts as "PRE-FLIGHT CONTEXT" to prevent schema mismatches, import duplication, reinventing existing solutions, and convention violations.

---

## Competitive Execution Flow

1. Create two git worktrees: `git worktree add .worktrees/competitor-a HEAD` and `git worktree add .worktrees/competitor-b HEAD`
2. Spawn Teammate-A in worktree-a with TDD strategy (see Competitor A Prompt below)
   - Include the PRE-FLIGHT CONTEXT from pre-flight exploration
3. Spawn Teammate-B in worktree-b with iterative strategy (see Competitor B Prompt below)
   - Include the PRE-FLIGHT CONTEXT from pre-flight exploration
4. Both run in parallel (separate worktrees = no conflicts)
5. When both finish, spawn a judge teammate (see Judge Prompt below)
6. Save judge verdict to `<worktree>/.judge-history/batch-N-verdict.md`
7. Apply verdict:
   - If single winner: Cherry-pick winner's commits into main worktree
   - If HYBRID: Apply per-task or per-file attribution from judge's HYBRID ANALYSIS
8. ALWAYS apply loser's valuable contributions from the judge's MANDATORY MERGE section:
   - Extract the specific changes listed by the judge (with code snippets)
   - Apply them to the main worktree (Edit tool or manual cherry-pick)
   - Commit as: "fix: integration improvements from competitive review"
   - This step is NOT optional — skip only if judge explicitly states winner is strictly superior
9. Merge instruction verification: After applying merge snippets, run tests.
   If any snippet fails to apply or breaks tests, log the failure in the verdict file
   and fix manually. Track merge success rate for judge quality feedback.
10. Adversarial review (optional, recommended for critical batches):
    Spawn a second judge agent with: "Review this verdict for accuracy, missed issues,
    and merge quality: [paste verdict]. Check: Are scores justified? Did the judge miss
    valuable contributions from the loser? Are merge snippets syntactically correct?"
    If adversarial judge finds issues, revise the merge before committing.
11. Feed judge's LESSONS FOR NEXT ROUND into competitor prompts for next batch.
12. Clean up competitor worktrees: `git worktree remove .worktrees/competitor-a` etc.

Non-competitive batches fall back to team mode (single implementer + reviewer).

---

## Leader Rules (keep context lean)

- Never read implementation files directly — teammates do that
- Track only: batch number, test counts, pass/fail status
- Each teammate gets full context via prompt (never "read the plan file")
- If context reaches 40% usage, serialize state and suggest /clear + resume
- State file: `<worktree>/.run-plan-state.json`

---

## Competitor A Prompt Template (TDD Strategy)

```
You are Competitor A implementing Batch N: [title]

STRATEGY: Methodical TDD — write comprehensive tests first, verify they fail, then implement.

[full task text — provided by leader, do not read the plan file]

Context:
- Worktree: [path]
- Python: [path]
- Previous batch test count: [N]

PRE-FLIGHT CONTEXT (from exploration agents — use this to avoid reinventing the wheel):
[Leader injects the combined context brief here:]
- CODEBASE: existing patterns, available imports, correct key names, file sizes, API signatures
- EXTERNAL: prior art from GitHub/web, recommended libraries, common patterns, anti-patterns
- GOTCHAS: known issues, pitfalls, and lessons specific to this batch's technology
IMPORTANT: If prior art or existing utilities are listed, USE them. Do not rewrite what already exists.

CODE QUALITY STANDARDS: (see code-quality-standards.md)

CRITICAL RULES (learned from competitive rounds):
- BEFORE writing any test: read the existing source files referenced in the task to understand real interfaces, existing types, and API endpoints. Do NOT assume interfaces — verify them.
- ALWAYS import and use existing types/models from the codebase. Never redefine a type that already exists.
- For integration tests: use real components, not mocks. Only mock at true external boundaries (LLM, network I/O). Mocking away the components you're supposed to test defeats the purpose.
- For CLI/API tasks: verify you're calling the correct endpoints by reading the route registration code, not guessing from endpoint names.
- Check capability registries and module registration — if you add a new module, register it.
- HA automation dicts use BOTH singular and plural keys — REST API returns singular (`trigger`, `action`), new format uses plural (`triggers`, `actions`). Always check both: `get("triggers") or get("trigger", [])`.
- Config keys MUST be consumed — if you register a config key, add a corresponding `get_config_value()` call. Dead config keys that do nothing are worse than missing ones.
- Trace integration boundaries: when two modules produce/consume the same data structure, verify key names match across the boundary. Read both sides before writing either.

LEARNED FROM COMPETITOR B (adopt these strengths):
- Hunt for integration seams: when wiring modules together, check that called methods actually exist on the target class, that return types match what callers expect (e.g., list[dict] vs list[str]), and that registries include your new modules.
- Build production-ready API responses: include counts, remaining items, live fallbacks when cache is empty. Richer responses win over minimal ones.
- Non-fatal error wrapping: cache updates and optional pipeline stages (LLM, notifications) should catch exceptions and log rather than crash the pipeline.
- Fix bugs you discover along the way — seam fixes from you are valuable even if your main implementation isn't chosen.

Process per task:
1. Read 2-3 existing files in the same package to absorb style patterns
2. Read existing source files to understand interfaces
3. Write comprehensive failing tests against REAL interfaces (cover edge cases, error paths, not just happy path)
4. Verify tests fail
5. Implement minimal code to pass — matching codebase style exactly
6. Verify all tests pass
7. Self-review for style consistency: does your code look like it belongs in this codebase?
8. Commit with descriptive message (one commit per task, not one big batch commit)

After all tasks:
- Run full test suite
- Self-review: completeness, spec compliance, YAGNI, style consistency
- Report: files changed, tests added, test count, any issues, any integration seams fixed
```

---

## Competitor B Prompt Template (Iterative Strategy)

```
You are Competitor B implementing Batch N: [title]

STRATEGY: Iterative rapid-build — implement working code first with clean architecture, then add tests to lock down behavior.

[full task text — provided by leader, do not read the plan file]

Context:
- Worktree: [path]
- Python: [path]
- Previous batch test count: [N]

PRE-FLIGHT CONTEXT (from exploration agents — use this to avoid reinventing the wheel):
[Leader injects the combined context brief here:]
- CODEBASE: existing patterns, available imports, correct key names, file sizes, API signatures
- EXTERNAL: prior art from GitHub/web, recommended libraries, common patterns, anti-patterns
- GOTCHAS: known issues, pitfalls, and lessons specific to this batch's technology
IMPORTANT: If prior art or existing utilities are listed, USE them. Do not rewrite what already exists.

CODE QUALITY STANDARDS: (see code-quality-standards.md)

CRITICAL RULES (learned from competitive rounds):
- BEFORE building anything: read the existing source files to find existing types, models, and patterns. ALWAYS import and use existing types — never create a parallel type that duplicates an existing one.
- When the spec references a data model (e.g., ShadowResult, AutomationCandidate): find where it's already defined and use that exact type. Check models.py and similar files.
- For scoring formulas and weighted calculations: implement EXACTLY as specified. Do not reinterpret weights or add bonuses not in the spec.
- For integration tests: test against real pipeline components, not mocks. If you're testing an "end-to-end pipeline", the test must exercise the real pipeline, not a mock version.
- Check capability registries — register new modules in capabilities.py.
- Fix real integration seams you discover (missing methods, type mismatches) — these are valuable contributions even if you don't win.
- HA automation dicts use BOTH singular and plural keys — REST API returns singular (`trigger`, `action`), new format uses plural (`triggers`, `actions`). Always check both: `get("triggers") or get("trigger", [])`.
- Config keys MUST be consumed — if you register a config key, add a corresponding `get_config_value()` call. Dead config keys that do nothing are worse than missing ones.
- Trace integration boundaries: when two modules produce/consume the same data structure, verify key names match across the boundary. Read both sides before writing either.

LEARNED FROM COMPETITOR A (adopt these strengths):
- Comprehensive test coverage: aim for thorough edge case testing, not just happy path. Test error paths, empty inputs, boundary conditions, and failure fallbacks. More tests with meaningful assertions = higher judge scores.
- Deterministic IDs: use content-based hashing (SHA-256 of key fields) for generated IDs rather than relying on input fields that may be empty or non-unique.
- Granular commits: one commit per task with a descriptive message, not one big batch commit. This makes cherry-picking cleaner.
- Test real components: when writing "integration" tests, use the real hub, real template engine, real validator — only mock true external boundaries. Tests that mock everything are unit tests in disguise and will be scored lower.
- Spec-faithful scoring: the spec's weights mean exactly what they say. pattern × 0.5 means confidence feeds the 0.5 bucket for pattern-source detections, not a flat 0.5 multiplier on everything.

Process per task:
1. Read 2-3 existing files in the same package to absorb style patterns
2. Read existing source files to understand interfaces and types
3. Build clean implementation using existing types — matching codebase style exactly
4. Write tests against real components (cover edge cases and error paths)
5. Verify all tests pass
6. Self-review for style consistency: does your code look like it belongs?
7. Commit with descriptive message (one commit per task)

After all tasks:
- Run full test suite
- Self-review: spec compliance, integration correctness, test coverage depth, style consistency
- Report: files changed, tests added, test count, any integration seams fixed
```

---

## Mode A Implementer Prompt Template

```
You are implementing Batch N: [title]

[full task text — provided by leader, do not read the plan file]

Context:
- Worktree: [path]
- Python: [path]
- Previous batch test count: [N]

CODE COHESION RULES (your code must look like ONE author wrote the whole codebase):
- BEFORE writing anything: read 2-3 existing files in the same package to absorb the project's style.
- Match naming conventions, docstring format, import ordering, error handling patterns, and logging style exactly.
- DRY: check if utilities already exist before writing new ones. YAGNI: no extra features beyond the spec.

Process per task:
1. Read 2-3 existing files in the same package to absorb style
2. Read existing source to understand interfaces
3. Write failing test
4. Verify it fails
5. Implement — matching codebase style exactly
6. Verify test passes
7. Commit

After all tasks:
- Self-review: completeness, quality, YAGNI, style consistency
- Report: files changed, tests added, test count, any issues
```

---

## Judge Prompt Template

```
Evaluate two competing implementations of Batch N: [title].

Competitor A (TDD): [worktree-a path]
Competitor B (Iterative): [worktree-b path]

PRIOR JUDGE HISTORY (learn from past rounds — if available):
[Leader inserts summaries from <worktree>/.judge-history/batch-*.md here.
Include: verdict, scores, what was missed, merge success/failure notes.
If no history exists yet, omit this section.]

SCORE ANCHORS (use these to calibrate — do NOT inflate scores):
- 10/10: Perfect — every spec requirement met, zero issues, exemplary
- 8/10: Strong — all requirements met, minor style/coverage gaps
- 6/10: Acceptable — most requirements met, some gaps or wrong approaches
- 4/10: Weak — significant gaps, spec violations, or broken functionality
- 2/10: Failing — fundamental misunderstanding or broken implementation

Process:
1. FIRST — Run full test suite in BOTH worktrees. Record pass/fail counts.
   Compare total test count against baseline [N]. If tests decreased or pre-existing tests fail, flag immediately.
   Gate: If either competitor has test failures, note this upfront — it caps their Spec Compliance at 6/10 max.

2. STRUCTURED CHECKS (before reading code):
   a. Anti-mock check: In any test file with "integration" or "e2e" in the name, count MagicMock/patch/Mock() usage. Integration tests with >3 mocks are unit tests in disguise — penalize under Test Coverage.
   b. Type duplication check: Check if either competitor defines new dataclasses/types. If a type already exists elsewhere in the codebase (e.g., in models.py), redefining it = automatic -2 on Spec Compliance.
   c. Endpoint verification (for API/CLI tasks): Verify every endpoint/route reference in the implementation against actual route registration code. Wrong endpoints = -2 on Spec Compliance.
   d. Dead config check: If either competitor registers config keys (in config_defaults or similar), verify each key has a corresponding `get_config_value()` call. Dead config keys = -1 on Spec Compliance.
   e. Integration boundary check: For modules that produce/consume shared data structures, verify key names match across the boundary. Watch for singular/plural HA automation key mismatches.

3. Read implementation AND test files in both competitors.

4. Score on: Spec compliance (0.35), Code quality (0.25), Test coverage (0.25), Cohesion (0.15)
   - Test coverage scoring must consider test DEPTH, not just count. Report: "A: N tests, avg M assertions/test; B: N tests, avg M assertions/test". Tests with only 1 assertion are smoke tests. Tests with 3+ meaningful assertions are thorough.
   - Cohesion scoring: Does the new code look like it was written by the same author as the existing codebase? Check:
     * FILE SIZE: Any file over 300 lines? Deduct points. Check with `wc -l` on all changed files.
     * MODULARITY: Does each file have one clear responsibility? Are functions under 30 lines?
     * Naming conventions match (snake_case, _private prefix, UPPER_CONSTANTS)
     * Import style matches (absolute, grouped: stdlib → third-party → local)
     * Docstring format matches existing modules
     * Error handling follows codebase patterns (logged before fallback, specific exceptions)
     * File structure follows codebase patterns (constants → public API → private helpers)
     * No reinvented utilities that already exist in shared modules
     * Type hints on all function signatures
     * Guard clauses over nested conditionals, no deep nesting (>3 levels)
     * No magic numbers — named constants used
     * Frontend: component patterns, hook usage, CSS class naming match sibling components

5. Integration Seam Checklist — check BOTH competitors:
   - [ ] New modules registered in capabilities.py?
   - [ ] New methods called by existing code actually exist on the target class?
   - [ ] Return types match what callers expect (e.g., list[dict] vs list[str])?
   - [ ] Import paths correct (no circular imports)?
   - [ ] Config keys registered in CONFIG_DEFAULTS?
   - [ ] UI components using correct prop names from their target components?

6. MANDATORY — Best-of-Both Synthesis:
   The goal is NOT just to pick a winner. The goal is to produce the BEST POSSIBLE result by combining strengths from both competitors. For EVERY batch, you MUST:
   a. Identify specific improvements from the loser that the winner lacks
   b. List exact files and changes with CODE SNIPPETS to apply from the loser
   c. Categories to check: integration seam fixes, missing registrations, richer API responses, better error handling, additional test edge cases, type fixes, missing methods
   d. If the loser found and fixed real bugs (missing methods, type mismatches, wrong return types), these MUST be included regardless of who wins

7. HYBRID EVALUATION — Can the best result be a combination?
   Before declaring a single winner, evaluate whether a HYBRID of both implementations would be superior:
   a. Per-task split: Could Task X use A's implementation and Task Y use B's?
   b. Per-component split: Could specific components/functions from each be combined?
   c. If a hybrid IS better: specify exactly which files/functions to take from each competitor
   d. If one competitor is clearly better across all dimensions: say so and explain why hybrid adds no value

   VERDICT OPTIONS:
   - "Competitor A wins" — use A's commits, merge from B
   - "Competitor B wins" — use B's commits, merge from A
   - "HYBRID" — take specific pieces from each (specify per-file or per-task attribution)

8. Deliver verdict with ALL of these sections:

TEST RESULTS:
- Competitor A: [N] passed, [N] failed, [N] skipped (baseline: [N])
- Competitor B: [N] passed, [N] failed, [N] skipped (baseline: [N])

STRUCTURED CHECKS:
- Anti-mock: A=[N mocks in integration tests], B=[N mocks in integration tests]
- Type duplication: [any issues found]
- Endpoint verification: [any issues found]
- Integration seams: [checklist results]

VERDICT: Competitor [A|B] wins | HYBRID

SCORES:
- Spec compliance (0.35): A=[score]/10, B=[score]/10
- Code quality (0.25): A=[score]/10, B=[score]/10
- Test coverage depth (0.25): A=[score]/10 (N tests, avg M asserts), B=[score]/10 (N tests, avg M asserts)
- Cohesion (0.15): A=[score]/10, B=[score]/10
- Weighted total: A=[score], B=[score]

COHESION & MODULARITY:
- File sizes: A=[list files >300 lines], B=[list files >300 lines]
- Functions >30 lines: A=[count], B=[count]
- Nesting depth >3: A=[count], B=[count]
- Type hints coverage: A=[pass/issues], B=[pass/issues]
- Naming consistency: A=[pass/issues], B=[pass/issues]
- Import style match: A=[pass/issues], B=[pass/issues]
- Error handling pattern: A=[pass/issues], B=[pass/issues]
- DRY (no reinvented utilities): A=[pass/issues], B=[pass/issues]
- Magic numbers: A=[count], B=[count]

REASONING: [2-3 sentences]

HYBRID ANALYSIS:
[If HYBRID verdict: specify exactly which files/functions/tasks come from each competitor.
If not hybrid: explain why one competitor is clearly better across all dimensions.]

CHERRY-PICK: [commits from winner, or per-task attribution for hybrid]

MANDATORY MERGE FROM LOSER:
[List EVERY valuable contribution from the loser. For each, specify:
- File path and what to extract
- Exact code snippet to apply
- Where to insert it (after which function/line)
- Why it's valuable (seam fix, better error handling, missing registration, etc.)
If truly nothing: explain why the winner's implementation is strictly superior in every dimension.
If HYBRID: this section covers pieces NOT already included in the hybrid attribution.]

LESSONS FOR NEXT ROUND:
- Competitor A should: [specific improvement]
- Competitor B should: [specific improvement]
```

---

## Reviewer Prompt Template

```
Review Batch N implementation against specification.
Spec: [full batch text]
Changes: git diff [base_sha]..HEAD
Check: spec compliance, code quality, lesson scan
Report: approved or issues with file:line references
```
