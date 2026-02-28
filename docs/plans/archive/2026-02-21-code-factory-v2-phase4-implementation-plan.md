# Code Factory v2 Phase 4 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete Phase 4 of Code Factory v2 — 43 new lessons, per-batch context assembler, ast-grep integration, team mode with decision gate, and parallel patch sampling.

**Architecture:** Fixes-first, then features. Batch 1 ships stability fixes and all lessons. Batches 2-5 add capabilities that build on each other: context assembler feeds into team mode, ast-grep feeds into scoring, team mode enables parallel sampling.

**Tech Stack:** Bash, jq, ast-grep (optional), Claude Code agent teams (experimental)

## Quality Gates

Between every batch, run:
```bash
scripts/tests/run-all-tests.sh
scripts/quality-gate.sh --project-root .
```

Expected: all test files pass, all assertions green, no lesson-check violations.

---

## Batch 1: Quick Fixes + Lessons (0007-0049)

context_refs: scripts/lib/run-plan-headless.sh, scripts/lib/common.sh, scripts/quality-gate.sh, docs/lessons/0001-bare-exception-swallowing.md, docs/lessons/TEMPLATE.md

### Task 1: Fix empty batch detection in run-plan-headless.sh

**Files:**
- Modify: `scripts/lib/run-plan-headless.sh:37-44`
- Test: `scripts/tests/test-run-plan-headless.sh`

**Step 1: Write the failing test**

Add to `scripts/tests/test-run-plan-headless.sh`:

```bash
# Create a plan with 2 real batches and 1 empty trailing match
cat > "$WORK/plan-empty.md" << 'PLAN'
## Batch 1: Real Batch
### Task 1: Do something
Write some code.

## Batch 2: Also Real
### Task 2: Do more
Write more code.

## Batch 3:
PLAN

# get_batch_text should return empty for batch 3
source "$SCRIPT_DIR/../lib/run-plan-parser.sh"
val=$(get_batch_text "$WORK/plan-empty.md" 3)
assert_eq "get_batch_text: empty batch returns empty" "" "$val"

# count_batches should count all 3 (parser counts headers)
val=$(count_batches "$WORK/plan-empty.md")
assert_eq "count_batches: counts all headers including empty" "3" "$val"
```

**Step 2: Run test to verify it fails or passes**

Run: `bash scripts/tests/test-run-plan-headless.sh`
Expected: These tests should PASS (get_batch_text already returns empty for empty batches). The bug is in run-plan-headless.sh not checking the return value.

**Step 3: Implement empty batch skip**

In `scripts/lib/run-plan-headless.sh`, after line 39 (`title=$(get_batch_title...)`), add:

```bash
        local batch_text
        batch_text=$(get_batch_text "$PLAN_FILE" "$batch")
        if [[ -z "$batch_text" ]]; then
            echo "  (empty batch -- skipping)"
            continue
        fi
```

**Step 4: Run all tests to verify**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 5: Commit**

```bash
git add scripts/lib/run-plan-headless.sh scripts/tests/test-run-plan-headless.sh
git commit -m "fix: skip empty batches in headless mode — avoids wasted API calls"
```

### Task 2: Add bash test suite detection to quality-gate.sh

**Files:**
- Modify: `scripts/lib/common.sh:12-23`
- Modify: `scripts/quality-gate.sh:129-155`
- Test: `scripts/tests/test-common.sh`
- Test: `scripts/tests/test-quality-gate.sh`

**Step 1: Write the failing test for detect_project_type**

Add to `scripts/tests/test-common.sh`:

```bash
# Bash project detection
mkdir -p "$WORK/bash-proj/scripts/tests"
echo '#!/bin/bash' > "$WORK/bash-proj/scripts/tests/run-all-tests.sh"
chmod +x "$WORK/bash-proj/scripts/tests/run-all-tests.sh"
val=$(detect_project_type "$WORK/bash-proj")
assert_eq "detect_project_type: bash project with run-all-tests.sh" "bash" "$val"

# Bash project with test-*.sh glob
mkdir -p "$WORK/bash-proj2/scripts/tests"
touch "$WORK/bash-proj2/scripts/tests/test-foo.sh"
val=$(detect_project_type "$WORK/bash-proj2")
assert_eq "detect_project_type: bash project with test-*.sh files" "bash" "$val"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-common.sh`
Expected: FAIL — detect_project_type returns "unknown" for bash projects

**Step 3: Add bash detection to detect_project_type**

In `scripts/lib/common.sh`, modify `detect_project_type()` to add bash detection before the final `else`:

```bash
detect_project_type() {
    local dir="$1"
    if [[ -f "$dir/pyproject.toml" || -f "$dir/setup.py" || -f "$dir/pytest.ini" ]]; then
        echo "python"
    elif [[ -f "$dir/package.json" ]]; then
        echo "node"
    elif [[ -f "$dir/Makefile" ]]; then
        echo "make"
    elif [[ -x "$dir/scripts/tests/run-all-tests.sh" ]] || ls "$dir"/scripts/tests/test-*.sh >/dev/null 2>&1; then
        echo "bash"
    else
        echo "unknown"
    fi
}
```

**Step 4: Add bash case to quality-gate.sh test suite section**

In `scripts/quality-gate.sh`, after the `make)` case and before `esac`, add:

```bash
    bash)
        if [[ -x "$PROJECT_ROOT/scripts/tests/run-all-tests.sh" ]]; then
            echo "Detected: bash project (run-all-tests.sh)"
            "$PROJECT_ROOT/scripts/tests/run-all-tests.sh"
            test_ran=1
        fi
        ;;
```

**Step 5: Run all tests to verify**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED (including the new assertions)

**Step 6: Commit**

```bash
git add scripts/lib/common.sh scripts/quality-gate.sh scripts/tests/test-common.sh scripts/tests/test-quality-gate.sh
git commit -m "feat: detect bash test suites in quality-gate.sh — run-all-tests.sh and test-*.sh"
```

### Task 3: Write lesson files 0007-0019

**Files:**
- Create: `docs/lessons/0007-runner-state-self-rejection.md`
- Create: `docs/lessons/0008-quality-gate-blind-spot.md`
- Create: `docs/lessons/0009-parser-overcount-empty-batches.md`
- Create: `docs/lessons/0010-local-outside-function-bash.md`
- Create: `docs/lessons/0011-batch-tests-for-unimplemented-code.md`
- Create: `docs/lessons/0012-api-markdown-unescaped-chars.md`
- Create: `docs/lessons/0013-export-prefix-env-parsing.md`
- Create: `docs/lessons/0014-decorator-registry-import-side-effect.md`
- Create: `docs/lessons/0015-frontend-backend-schema-drift.md`
- Create: `docs/lessons/0016-event-driven-cold-start-seeding.md`
- Create: `docs/lessons/0017-copy-paste-logic-diverges.md`
- Create: `docs/lessons/0018-layer-passes-pipeline-broken.md`
- Create: `docs/lessons/0019-systemd-envfile-ignores-export.md`
- Reference: `docs/lessons/TEMPLATE.md`

**Instructions:**

Write each lesson file using the YAML frontmatter schema from `docs/lessons/TEMPLATE.md`. Each file must have:
- YAML frontmatter between `---` delimiters with: id, title, severity, languages, category, pattern (type + regex/description), fix, example (bad + good)
- Three markdown sections: ## Observation, ## Insight, ## Lesson
- NO project-specific references (no project names, IPs, hostnames, usernames)
- Generalized language — the anti-pattern, not the specific bug

Use the design doc mapping table at `docs/plans/2026-02-21-code-factory-v2-phase4-design.md` for the ID, title, severity, and category of each lesson.

**Lesson content (generalized):**

**0007** — Runner state file (e.g., `.run-plan-state.json`) created by a tool gets rejected by that same tool's git-clean check. The tool creates the file, then its quality gate rejects the batch because the file is untracked. Fix: add tool-generated files to `.gitignore`.

**0008** — Quality gates that auto-detect test frameworks (pytest/jest/make) miss non-standard test suites (bash `test-*.sh`, custom runners). Gate reports "no tests detected" while hundreds of assertions exist. Fix: detect custom test runners by convention (executable `run-all-tests.sh`, `test-*.sh` glob).

**0009** — Plan parsers that count batch headers can over-count (e.g., empty trailing headers, non-standard formatting). Each phantom batch spawns an agent that discovers "nothing to do" — wasted API call and time. Fix: check `get_batch_text` is non-empty before execution.

**0010** — In bash, `local` outside a function is undefined behavior. Some shells silently accept it, others error. This creates scripts that work on one machine but fail on another. `local` in auto-compound.sh line 149 was outside any function scope. Fix: never use `local` outside a function; use plain variable assignment.
Pattern type: syntactic. Regex: `^local ` (at script top-level, outside function).

**0011** — When a plan has batches 1-7 and batch 3's agent writes tests expecting batch 4's code, those tests fail until batch 4 runs. The agent in batch 3 is doing TDD for its own work but accidentally creates forward dependencies. Fix: plan tasks so each batch is self-contained — tests only reference code written in the same or earlier batches.

**0012** — Telegram (and similar APIs) with `parse_mode=Markdown` reject messages containing unescaped `_`, `*`, `[`, etc. The message silently fails or returns `{"ok":false}`. Fix: either escape all special characters or use plain text mode as default with markdown as opt-in.

**0013** — `.env` files commonly use `export VAR=value` syntax (for shell sourcing). Parsers that use `cut -d= -f2` get `value` correctly, but `grep VAR= file | cut -d= -f2` skips lines starting with `export`. Fix: strip `export ` prefix before parsing: `sed 's/^export //'`.
Pattern type: syntactic. Regex: `cut -d= -f2` (in env file parsing context).

**0014** — Python decorator-based registries (`@register("name")`) execute at import time. If the module containing decorated functions is never imported, the registry is empty. No error, no warning — the feature just doesn't work. Fix: ensure all modules with registrations are imported in the package `__init__.py` or an explicit loader.

**0015** — Frontend and backend can define the same data shape independently. Over time they drift — backend adds a field, frontend doesn't read it; frontend expects a format backend doesn't produce. Only an end-to-end trace catches this. Fix: shared schema definition (TypeScript types generated from API schema) or contract tests.

**0016** — Event-driven systems work fine in steady state (events flow, handlers react) but produce empty/wrong output on first boot — no events have arrived yet. Fix: on startup, seed current state by fetching a snapshot via REST/query before subscribing to events.

**0017** — Two modules that compute the same thing independently (e.g., feature extraction, date formatting, config parsing) will diverge silently over time as one gets updated and the other doesn't. Fix: import from one source. If two modules need the same logic, extract it to a shared function.

**0018** — Each layer of a pipeline (data fetch, transform, store, API, UI) can pass its unit tests while the full pipeline is broken at the seams. Fix: add at least one end-to-end test that traces a single input through every layer. Dual-axis testing: horizontal (every endpoint) + vertical (one full trace).

**0019** — systemd `EnvironmentFile=` expects `KEY=value` format. Lines starting with `export` are silently ignored. Services start without error but have empty environment variables. Fix: use a bash wrapper (`ExecStart=/bin/bash -c '. ~/.env && exec /path/to/binary'`) or strip `export` from the file.
Pattern type: syntactic. Regex: `EnvironmentFile=` (in systemd unit files — warn to use bash wrapper).

**Step 1: Write all 13 lesson files**

Create each file at `docs/lessons/NNNN-<slug>.md` following the template exactly.

**Step 2: Verify YAML frontmatter is valid**

Run for each file:
```bash
for f in docs/lessons/00{07..19}-*.md; do
    echo "--- $f ---"
    sed -n '/^---$/,/^---$/p' "$f" | head -1
done
```

**Step 3: Run lesson-check to verify no new violations**

Run: `bash scripts/lesson-check.sh docs/lessons/0007-*.md docs/lessons/0008-*.md`
Expected: No violations (lesson files are documentation, not code)

**Step 4: Commit**

```bash
git add docs/lessons/0007-*.md docs/lessons/0008-*.md docs/lessons/0009-*.md docs/lessons/0010-*.md docs/lessons/0011-*.md docs/lessons/0012-*.md docs/lessons/0013-*.md docs/lessons/0014-*.md docs/lessons/0015-*.md docs/lessons/0016-*.md docs/lessons/0017-*.md docs/lessons/0018-*.md docs/lessons/0019-*.md
git commit -m "docs: add lessons 0007-0019 — v2 execution findings + generalized patterns"
```

### Task 4: Write lesson files 0020-0035

**Files:**
- Create: `docs/lessons/0020-persist-state-incrementally.md`
- Create: `docs/lessons/0021-dual-axis-testing.md`
- Create: `docs/lessons/0022-jsx-factory-shadowing.md`
- Create: `docs/lessons/0023-static-analysis-spiral.md`
- Create: `docs/lessons/0024-shared-pipeline-implementation.md`
- Create: `docs/lessons/0025-defense-in-depth-all-entry-points.md`
- Create: `docs/lessons/0026-linter-no-rules-false-enforcement.md`
- Create: `docs/lessons/0027-jsx-silent-prop-drop.md`
- Create: `docs/lessons/0028-no-infrastructure-in-client-code.md`
- Create: `docs/lessons/0029-never-write-secrets-to-files.md`
- Create: `docs/lessons/0030-cache-merge-not-replace.md`
- Create: `docs/lessons/0031-verify-units-at-boundaries.md`
- Create: `docs/lessons/0032-module-lifecycle-subscribe-unsubscribe.md`
- Create: `docs/lessons/0033-async-iteration-mutable-snapshot.md`
- Create: `docs/lessons/0034-caller-missing-await-silent-discard.md`
- Create: `docs/lessons/0035-duplicate-registration-silent-overwrite.md`
- Reference: `docs/lessons/TEMPLATE.md`

**Instructions:**

Same format as Task 3. Use design doc mapping table for metadata.

**Lesson content (generalized):**

**0020** — Long-running processes (ETL, embeddings, batch jobs) that save state only at the end lose all progress on crash. A 2-hour job that crashes on the save step restarts from zero. Fix: checkpoint state after each logical unit of work. Incremental saves mean crashes only lose the last unit, not everything.

**0021** — Dual-axis testing: horizontal sweep (hit every endpoint/CLI/interface) confirms the surface exists. Vertical trace (one input through every layer to final output) confirms data flows end-to-end. Both required. If time-constrained, vertical catches more integration bugs per minute.

**0022** — Build tools that inject JSX factory functions (e.g., esbuild's `jsxFactory: 'h'`) create invisible global variables. Arrow function parameters with the same name (`items.map(h => ...)`) shadow the factory, causing silent render crashes. Fix: never use single-letter variable names that match build tool injections. Lint rule: `no-shadow` for known factory names.
Pattern type: syntactic. Regex: `\.map\(h\s*=>` or `\.map\(\(h\)` (in JSX files).

**0023** — Static analysis tools suggest fixes. Implementing those fixes triggers new warnings. Fixing those triggers more. The spiral creates more bugs than it solves because each "fix" changes code the developer didn't intend to touch. Fix: set a lint baseline, only fix violations in code you're actively changing. If a refactor creates new lint failures, stop and reassess.

**0024** — When two pipeline stages independently implement the same feature logic (e.g., feature extraction, data normalization), they'll produce different results. Fix: shared implementation — both stages import from one module. If they can't share code (different languages), add a contract test.

**0025** — Validating input at the first entry point isn't enough if there are multiple paths into the system (API, CLI, WebSocket, cron). Each entry point needs the same validation. Fix: centralize validation in a shared function called by all entry points. Test each entry point with invalid input.

**0026** — Installing a linter with zero rules enabled gives a false sense of enforcement. `ruff check` with no `--select` runs nothing. `eslint` with no config flags nothing. Developers see "0 issues" and assume code is clean. Fix: always configure rules explicitly. Test that the linter actually catches something by including a known-bad sample.

**0027** — JSX frameworks silently drop unrecognized props. Passing `onClick` when the component expects `onPress`, or `value` when it expects `defaultValue`, produces no error — the prop is simply ignored. Fix: use TypeScript with strict component prop types. Without TS, verify prop names against component signature, not the plan.
Pattern type: syntactic (in TypeScript projects, detectable by unused prop warning).

**0028** — Embedding IP addresses, internal hostnames, or port numbers in client-side code (browser JS, mobile apps) exposes infrastructure details and breaks when infrastructure changes. Fix: use relative URLs, environment variables, or a config endpoint. Never hardcode infrastructure in shipped code.
Pattern type: syntactic. Regex: `['"]https?://\d+\.\d+\.\d+\.\d+` or `['"]https?://localhost:\d+` (in client-side files).

**0029** — Writing actual secret values (API keys, tokens, passwords) into committed files — even in tests, comments, or "examples" — risks exposure. Secrets in git history persist even after deletion. Fix: reference secrets by env var name only. In tests, use mock values (`test-token-123`). Enforce with pre-commit hooks (gitleaks, detect-secrets).
Pattern type: syntactic (detectable by secret scanning tools).

**0030** — Cache or registry updates that replace the entire cache with new data lose entries not present in the update. If module A registers 5 entries and module B replaces the cache with 3 entries, A's entries vanish. Fix: merge, never replace. `cache.update(new_entries)` not `cache = new_entries`.

**0031** — When data crosses boundaries (API to API, module to module, UI to backend), units can change silently. A function returns 0-1 (proportion), the consumer expects 0-100 (percentage), or vice versa. Comments may lie. Fix: verify units at every boundary. Add unit to variable names when ambiguous (`accuracy_pct`, `ratio_0_1`).

**0032** — Components that subscribe to events in the constructor but never unsubscribe leak handlers. After shutdown/restart, old handlers fire on stale state. Fix: subscribe in `initialize()` (after startup gate), store the callback reference on `self`, and unsubscribe in `shutdown()`. Anonymous closures can't be cleaned up.

**0033** — Iterating over a mutable collection (set, dict, list) while async operations inside the loop yield control (via `await`) allows concurrent modifications. Python raises `RuntimeError: Set changed size during iteration`. Fix: snapshot before iterating: `for item in list(my_set):`.
Pattern type: syntactic. Regex: `for .+ in self\.\w+:` (in async functions iterating over instance attributes).

**0034** — Calling an `async def` function without `await` silently discards its work. The coroutine object is created but never executed. No exception, no warning at runtime (only a `RuntimeWarning` in some configurations). Fix: always `await` async function calls. Use `create_task()` if fire-and-forget is intended (with `done_callback`).

**0035** — When multiple components register with the same ID (module name, plugin key, route path), the last registration silently overwrites earlier ones. No error, no warning — the overwritten component just stops working. Fix: check for existing registration before inserting. Log a warning or raise on duplicate.

**Step 1: Write all 16 lesson files**

**Step 2: Verify each has valid YAML frontmatter**

**Step 3: Commit**

```bash
git add docs/lessons/00{20..35}-*.md
git commit -m "docs: add lessons 0020-0035 — lifecycle, async, security, testing patterns"
```

### Task 5: Write lesson files 0036-0049

**Files:**
- Create: `docs/lessons/0036-websocket-dirty-disconnect.md`
- Create: `docs/lessons/0037-parallel-agents-worktree-corruption.md`
- Create: `docs/lessons/0038-subscribe-no-stored-ref.md`
- Create: `docs/lessons/0039-fallback-or-default-hides-bugs.md`
- Create: `docs/lessons/0040-event-firehose-filter-first.md`
- Create: `docs/lessons/0041-ambiguous-base-dir-path-nesting.md`
- Create: `docs/lessons/0042-spec-compliance-insufficient.md`
- Create: `docs/lessons/0043-exact-count-extensible-collections.md`
- Create: `docs/lessons/0044-relative-file-deps-worktree.md`
- Create: `docs/lessons/0045-iterative-design-improvement.md`
- Create: `docs/lessons/0046-plan-assertion-math-bugs.md`
- Create: `docs/lessons/0047-pytest-single-threaded-default.md`
- Create: `docs/lessons/0048-integration-wiring-batch.md`
- Create: `docs/lessons/0049-ab-verification.md`
- Reference: `docs/lessons/TEMPLATE.md`

**Instructions:**

Same format as Tasks 3-4. Use design doc mapping table for metadata.

**Lesson content (generalized):**

**0036** — WebSocket clients that disconnect without a close frame (network drop, mobile backgrounding) don't trigger the `WebSocketDisconnect` exception. Instead, the next `send()` raises `RuntimeError`. Fix: wrap all WebSocket sends in `try/except RuntimeError` and clean up the connection.

**0037** — Multiple AI agents or CI jobs committing to the same git worktree corrupt the staging area. Pre-commit hooks that use `git stash` interfere with concurrent commits. Fix: each parallel agent gets its own git worktree. Never share a worktree between concurrent processes.

**0038** — Subscribing to events with an anonymous closure (`hub.subscribe(lambda e: handle(e))`) means you can't unsubscribe later — you don't have a reference to the callback. Fix: store the callback on `self` before subscribing: `self._handler = lambda e: handle(e); hub.subscribe(self._handler)`. Unsubscribe with the stored ref in shutdown.

**0039** — `self._resource or Resource()` creates a new resource every time `_resource` is falsy. This hides the bug that `_resource` was never properly initialized. The fallback silently masks the initialization failure and leaks resources. Fix: replace with a guard return + warning: `if not self._resource: logger.warning("not initialized"); return`.

**0040** — Processing every event in a firehose when only 5% are relevant wastes 95% of compute. A simple prefix filter (`event.startswith("target_domain")`) before any async lookup eliminates most wasted work. Fix: filter by domain/type/source at the top of the handler, before any expensive operations.

**0041** — A variable named `log_dir` that contains `/path/to/logs/intelligence/` used as `os.path.join(log_dir, "intelligence", "data")` produces `/path/to/logs/intelligence/intelligence/data`. The variable name doesn't encode what directory level it represents. Fix: name variables to encode their scope (`log_base_dir` vs `intelligence_dir`). Verify paths with `ls` before first use.

**0042** — A code review that checks "does this implement the spec?" catches functional gaps but misses defensive coding: error handling on external calls, cleanup on failure, validation on boundaries, timeouts on network ops. Fix: code review should include a defensive gaps checklist separate from spec compliance.

**0043** — Tests that assert `len(collection) == 15` break every time the collection grows (new config entry, new registered module, new test fixture). The test is coupled to an incidental count, not a meaningful invariant. Fix: use `>=` for extensible collections, or assert specific items exist rather than total count.
Pattern type: syntactic. Regex: `assert.*len\(.*==\s*\d+` (exact count assertions).

**0044** — `file:../shared-lib` dependencies in `package.json` use relative paths. In a git worktree (different depth from repo root), the relative path points to a non-existent location. Fix: use workspace protocols, absolute paths resolved at install time, or npm/yarn workspaces.

**0045** — Asking "how would you improve this section?" after each design section catches 35% more gaps than single-pass design. 5 rounds of iterative improvement is the sweet spot — diminishing returns after that. Fix: build iterative review into the design process, not as an afterthought.

**0046** — Implementation plans specify expected test assertions (`assert threshold > 0.85`). The plan author can make math errors (wrong boundary, off-by-one, inverted comparison). The implementer copies the assertion verbatim, and the test "passes" with the wrong threshold. Fix: verify threshold boundary logic independently before writing the test.

**0047** — pytest runs single-threaded by default, even on multi-core machines. A test suite that takes 5 minutes single-threaded takes 50 seconds with `-n auto` (pytest-xdist). Fix: add `pytest-xdist` to dev dependencies and `addopts = "-n auto"` to pytest config for any project with >20 tests.

**0048** — Multi-batch implementation plans that build components in separate batches often skip the "wire everything together" step. Each component passes its tests independently, but nothing connects them. Fix: plans with 3+ batches must include a final integration wiring batch that connects all prior components and runs an end-to-end test.

**0049** — A/B verification (bottom-up implementation review + top-down architectural review) finds zero-overlap bug classes. Bottom-up catches code-level issues (missing error handling, wrong types). Top-down catches design-level issues (missing components, wrong data flow). Run both after any 3+ batch implementation.

**Step 1: Write all 14 lesson files**

**Step 2: Verify each has valid YAML frontmatter**

**Step 3: Commit**

```bash
git add docs/lessons/00{36..49}-*.md
git commit -m "docs: add lessons 0036-0049 — agents, testing, design, integration patterns"
```

### Task 6: Write SUMMARY.md for all 49 lessons

**Files:**
- Create/Rewrite: `docs/lessons/SUMMARY.md`

**Step 1: Write SUMMARY.md**

Structure:
- Quick Reference table (all 49 lessons: ID, title, category, severity, type)
- Three Root Cause Clusters (generalized from Documents workspace):
  - **Cluster A: Silent Failures** — Something fails but produces no error, no log, no crash
  - **Cluster B: Integration Boundaries** — Each component works alone, bug hides at the seam
  - **Cluster C: Cold-Start Assumptions** — Works steady-state, fails on restart/first boot
- Six Rules to Build By (generalized)
- Diagnostic Shortcuts table (symptom → check this first)
- No project-specific references anywhere

Map each lesson to its cluster based on category:
- `silent-failures` → Cluster A
- `integration-boundaries` → Cluster B
- `async-traps` → Cluster A (async bugs are a form of silent failure)
- `resource-lifecycle` → Cluster A
- `test-anti-patterns` → Cluster B (tests fail at integration seams)
- `performance` → standalone

**Step 2: Verify all 49 IDs are listed**

```bash
grep -c "^|" docs/lessons/SUMMARY.md  # Should be >= 49 (plus header rows)
```

**Step 3: Commit**

```bash
git add docs/lessons/SUMMARY.md
git commit -m "docs: add SUMMARY.md — 49 lessons with clusters, rules, and diagnostic shortcuts"
```

---

## Batch 2: Per-Batch Context Assembler

context_refs: scripts/lib/run-plan-headless.sh, scripts/lib/run-plan-prompt.sh, scripts/lib/run-plan-state.sh

### Task 7: Create run-plan-context.sh with generate_batch_context()

**Files:**
- Create: `scripts/lib/run-plan-context.sh`
- Test: `scripts/tests/test-run-plan-context.sh`

**Step 1: Write the failing test**

Create `scripts/tests/test-run-plan-context.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/run-plan-context.sh"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        echo "  actual: ${haystack:0:200}..."
        FAILURES=$((FAILURES + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected NOT to contain: $needle"
        FAILURES=$((FAILURES + 1))
    fi
}

WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT

# === Setup test fixtures ===

# State file
cat > "$WORK/.run-plan-state.json" << 'JSON'
{
  "plan": "test-plan.md",
  "mode": "headless",
  "batches": {
    "1": {"passed": true, "test_count": 50, "duration": 120},
    "2": {"passed": true, "test_count": 75, "duration": 90}
  }
}
JSON

# Progress file
cat > "$WORK/progress.txt" << 'TXT'
Batch 1: Created shared library
Batch 2: Fixed test parsing
Discovery: jest output needs special handling
TXT

# Git repo for git log
cd "$WORK" && git init -q && git commit --allow-empty -m "batch 1: initial" -q && git commit --allow-empty -m "batch 2: add tests" -q
cd -

# Plan with context_refs
cat > "$WORK/test-plan.md" << 'PLAN'
## Batch 1: Foundation
### Task 1: Setup
Create lib.

## Batch 2: Tests
### Task 2: Add tests
context_refs: src/lib.sh

## Batch 3: Integration
### Task 3: Wire together
context_refs: src/lib.sh, tests/test-lib.sh
PLAN

# Context ref files
mkdir -p "$WORK/src" "$WORK/tests"
echo "#!/bin/bash" > "$WORK/src/lib.sh"
echo "echo hello" >> "$WORK/src/lib.sh"
echo "#!/bin/bash" > "$WORK/tests/test-lib.sh"

# === Tests ===

# generate_batch_context for batch 3 (has context_refs and prior batches)
ctx=$(generate_batch_context "$WORK/test-plan.md" 3 "$WORK")
assert_contains "context: includes quality gate expectation" "tests must stay above 75" "$ctx"
assert_contains "context: includes prior batch summary" "Batch 2" "$ctx"
assert_contains "context: includes context_refs content" "echo hello" "$ctx"
assert_not_contains "context: excludes batch 1 details for batch 3" "Batch 1: Foundation" "$ctx"

# generate_batch_context for batch 1 (no prior context)
ctx=$(generate_batch_context "$WORK/test-plan.md" 1 "$WORK")
assert_contains "context batch 1: minimal context" "Run-Plan" "$ctx"
# Should be short — no prior batches, no context_refs
char_count=${#ctx}
TESTS=$((TESTS + 1))
if [[ $char_count -lt 2000 ]]; then
    echo "PASS: context batch 1: under 2000 chars ($char_count)"
else
    echo "FAIL: context batch 1: over 2000 chars ($char_count)"
    FAILURES=$((FAILURES + 1))
fi

# Token budget: context should stay under 6000 chars (~1500 tokens)
ctx=$(generate_batch_context "$WORK/test-plan.md" 3 "$WORK")
char_count=${#ctx}
TESTS=$((TESTS + 1))
if [[ $char_count -lt 6000 ]]; then
    echo "PASS: context batch 3: under 6000 chars ($char_count)"
else
    echo "FAIL: context batch 3: over 6000 chars ($char_count)"
    FAILURES=$((FAILURES + 1))
fi

# Failure patterns injection
mkdir -p "$WORK/logs"
cat > "$WORK/logs/failure-patterns.json" << 'JSON'
[{"batch_title_pattern": "integration", "failure_type": "missing import", "frequency": 3, "winning_fix": "check all imports before running tests"}]
JSON

ctx=$(generate_batch_context "$WORK/test-plan.md" 3 "$WORK")
assert_contains "context: includes failure pattern warning" "missing import" "$ctx"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-run-plan-context.sh`
Expected: FAIL — `run-plan-context.sh` doesn't exist yet

**Step 3: Implement generate_batch_context**

Create `scripts/lib/run-plan-context.sh`:

```bash
#!/usr/bin/env bash
# run-plan-context.sh — Per-batch context assembler for run-plan
#
# Assembles relevant context for a batch agent within a token budget.
# Reads: state file, progress.txt, git log, context_refs, failure patterns.
# Outputs: markdown section for CLAUDE.md injection.
#
# Functions:
#   generate_batch_context <plan_file> <batch_num> <worktree> -> markdown string

TOKEN_BUDGET_CHARS=6000  # ~1500 tokens

generate_batch_context() {
    local plan_file="$1" batch_num="$2" worktree="$3"
    local context=""
    local chars_used=0

    context+="## Run-Plan: Batch $batch_num"$'\n\n'

    # 1. Directives from state (highest priority)
    local state_file="$worktree/.run-plan-state.json"
    if [[ -f "$state_file" ]]; then
        local prev_test_count
        prev_test_count=$(jq -r '[.batches[].test_count // 0] | max' "$state_file" 2>/dev/null || echo "0")
        if [[ "$prev_test_count" -gt 0 ]]; then
            context+="**Directive:** tests must stay above $prev_test_count (current high water mark)"$'\n\n'
        fi

        # Prior batch summary (most recent 2 batches only)
        local start_batch=$(( batch_num - 2 ))
        [[ $start_batch -lt 1 ]] && start_batch=1
        for ((b = start_batch; b < batch_num; b++)); do
            local passed duration tests
            passed=$(jq -r ".batches[\"$b\"].passed // false" "$state_file" 2>/dev/null)
            tests=$(jq -r ".batches[\"$b\"].test_count // 0" "$state_file" 2>/dev/null)
            duration=$(jq -r ".batches[\"$b\"].duration // 0" "$state_file" 2>/dev/null)
            if [[ "$passed" == "true" ]]; then
                context+="Batch $b: PASSED ($tests tests, ${duration}s)"$'\n'
            fi
        done
        context+=$'\n'
    fi

    # 2. Failure patterns (cross-run learning)
    local patterns_file="$worktree/logs/failure-patterns.json"
    if [[ -f "$patterns_file" ]]; then
        local batch_title
        batch_title=$(get_batch_title "$plan_file" "$batch_num" 2>/dev/null || echo "")
        local title_lower
        title_lower=$(echo "$batch_title" | tr '[:upper:]' '[:lower:]')

        # Match failure patterns by batch title keywords
        local matches
        matches=$(jq -r --arg title "$title_lower" \
            '.[] | select(.batch_title_pattern as $p | $title | contains($p)) | "WARNING: Previously failed with \(.failure_type) (\(.frequency)x). Fix that worked: \(.winning_fix)"' \
            "$patterns_file" 2>/dev/null || true)
        if [[ -n "$matches" ]]; then
            context+="### Known Failure Patterns"$'\n'
            context+="$matches"$'\n\n'
        fi
    fi

    chars_used=${#context}

    # 3. Context refs file contents (if budget allows)
    if command -v get_batch_context_refs >/dev/null 2>&1; then
        local refs
        refs=$(get_batch_context_refs "$plan_file" "$batch_num" 2>/dev/null || true)
        if [[ -n "$refs" ]]; then
            local refs_section="### Referenced Files"$'\n'
            while IFS= read -r ref_file; do
                ref_file=$(echo "$ref_file" | xargs)  # trim whitespace
                [[ -z "$ref_file" ]] && continue
                local full_path="$worktree/$ref_file"
                if [[ -f "$full_path" ]]; then
                    local file_content
                    file_content=$(head -50 "$full_path" 2>/dev/null || true)
                    local addition
                    addition=$'\n'"**$ref_file:**"$'\n'"$file_content"$'\n'
                    if [[ $(( chars_used + ${#refs_section} + ${#addition} )) -lt $TOKEN_BUDGET_CHARS ]]; then
                        refs_section+="$addition"
                    fi
                fi
            done <<< "$refs"
            context+="$refs_section"$'\n'
        fi
    fi

    chars_used=${#context}

    # 4. Git log (if budget allows)
    if [[ $(( chars_used + 500 )) -lt $TOKEN_BUDGET_CHARS ]]; then
        local git_log
        git_log=$(cd "$worktree" && git log --oneline -5 2>/dev/null || true)
        if [[ -n "$git_log" ]]; then
            context+="### Recent Commits"$'\n'
            context+="$git_log"$'\n\n'
        fi
    fi

    chars_used=${#context}

    # 5. Progress.txt (if budget allows, last 10 lines)
    if [[ $(( chars_used + 500 )) -lt $TOKEN_BUDGET_CHARS ]]; then
        local progress_file="$worktree/progress.txt"
        if [[ -f "$progress_file" ]]; then
            local progress
            progress=$(tail -10 "$progress_file" 2>/dev/null || true)
            if [[ -n "$progress" ]]; then
                context+="### Progress Notes"$'\n'
                context+="$progress"$'\n\n'
            fi
        fi
    fi

    echo "$context"
}
```

**Step 4: Run tests to verify**

Run: `bash scripts/tests/test-run-plan-context.sh`
Expected: ALL PASSED

**Step 5: Commit**

```bash
git add scripts/lib/run-plan-context.sh scripts/tests/test-run-plan-context.sh
git commit -m "feat: add per-batch context assembler with token budget and failure patterns"
```

### Task 8: Wire context assembler into run-plan-headless.sh

**Files:**
- Modify: `scripts/lib/run-plan-headless.sh`
- Modify: `scripts/run-plan.sh` (source the new lib)

**Step 1: Source run-plan-context.sh in run-plan.sh**

In `scripts/run-plan.sh`, find where other libs are sourced and add:

```bash
source "$SCRIPT_DIR/lib/run-plan-context.sh"
```

**Step 2: Inject context into CLAUDE.md before each batch**

In `scripts/lib/run-plan-headless.sh`, after the empty batch check (added in Task 1) and before `build_batch_prompt`, add:

```bash
        # Generate and inject per-batch context into CLAUDE.md
        local batch_context
        batch_context=$(generate_batch_context "$PLAN_FILE" "$batch" "$WORKTREE")
        if [[ -n "$batch_context" ]]; then
            local claude_md="$WORKTREE/CLAUDE.md"
            # Remove previous run-plan context section if present
            if [[ -f "$claude_md" ]] && grep -q "^## Run-Plan:" "$claude_md"; then
                # Remove from "## Run-Plan:" to end of file or next ## heading
                local tmp
                tmp=$(mktemp)
                sed '/^## Run-Plan:/,/^## [^R]/{ /^## [^R]/!d; }' "$claude_md" > "$tmp"
                # Also remove the trailing ## Run-Plan: line if it's still there
                sed -i '/^## Run-Plan:/d' "$tmp"
                mv "$tmp" "$claude_md"
            fi
            # Append new context
            echo "" >> "$claude_md"
            echo "$batch_context" >> "$claude_md"
        fi
```

**Step 3: Run all tests to verify**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 4: Commit**

```bash
git add scripts/run-plan.sh scripts/lib/run-plan-headless.sh
git commit -m "feat: wire context assembler into headless loop — injects per-batch CLAUDE.md section"
```

### Task 9: Add failure pattern persistence

**Files:**
- Modify: `scripts/lib/run-plan-context.sh` (add `record_failure_pattern` function)
- Modify: `scripts/lib/run-plan-headless.sh` (call on batch failure)
- Test: `scripts/tests/test-run-plan-context.sh` (add persistence tests)

**Step 1: Write the failing test**

Add to `scripts/tests/test-run-plan-context.sh`:

```bash
# === Failure pattern recording ===
record_failure_pattern "$WORK" "Integration Wiring" "missing import" "check imports before tests"

assert_eq "record_failure_pattern: creates file" "true" "$(test -f "$WORK/logs/failure-patterns.json" && echo true || echo false)"

# Record same pattern again — should increment frequency
record_failure_pattern "$WORK" "Integration Wiring" "missing import" "check imports before tests"
freq=$(jq '.[0].frequency' "$WORK/logs/failure-patterns.json")
assert_eq "record_failure_pattern: increments frequency" "2" "$freq"

# Record different pattern
record_failure_pattern "$WORK" "Test Suite" "flaky assertion" "use deterministic comparisons"
count=$(jq 'length' "$WORK/logs/failure-patterns.json")
assert_eq "record_failure_pattern: adds new pattern" "2" "$count"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-run-plan-context.sh`
Expected: FAIL — `record_failure_pattern` doesn't exist

**Step 3: Implement record_failure_pattern**

Add to `scripts/lib/run-plan-context.sh`:

```bash
record_failure_pattern() {
    local worktree="$1" batch_title="$2" failure_type="$3" winning_fix="$4"
    local patterns_file="$worktree/logs/failure-patterns.json"
    local title_lower
    title_lower=$(echo "$batch_title" | tr '[:upper:]' '[:lower:]')

    mkdir -p "$(dirname "$patterns_file")"

    if [[ ! -f "$patterns_file" ]]; then
        echo "[]" > "$patterns_file"
    fi

    # Check if pattern already exists
    local existing
    existing=$(jq -r --arg t "$title_lower" --arg f "$failure_type" \
        '[.[] | select(.batch_title_pattern == $t and .failure_type == $f)] | length' \
        "$patterns_file" 2>/dev/null || echo "0")

    if [[ "$existing" -gt 0 ]]; then
        # Increment frequency
        jq --arg t "$title_lower" --arg f "$failure_type" \
            '[.[] | if .batch_title_pattern == $t and .failure_type == $f then .frequency += 1 | .last_seen = now | todate else . end]' \
            "$patterns_file" > "$patterns_file.tmp" && mv "$patterns_file.tmp" "$patterns_file"
    else
        # Add new pattern
        jq --arg t "$title_lower" --arg f "$failure_type" --arg w "$winning_fix" \
            '. += [{"batch_title_pattern": $t, "failure_type": $f, "frequency": 1, "winning_fix": $w, "last_seen": (now | todate)}]' \
            "$patterns_file" > "$patterns_file.tmp" && mv "$patterns_file.tmp" "$patterns_file"
    fi
}
```

**Step 4: Wire into run-plan-headless.sh**

In the failure handling section of `run-plan-headless.sh` (after quality gate fails), add before the retry/skip/stop logic:

```bash
                # Record failure pattern for cross-run learning
                local fail_type="quality gate failure"
                if [[ -f "$log_file" ]]; then
                    # Try to extract failure type from log
                    fail_type=$(grep -oE "(FAIL|ERROR|FAILED).*" "$log_file" | head -1 | cut -c1-80 || echo "quality gate failure")
                fi
                record_failure_pattern "$WORKTREE" "$title" "$fail_type" "" || true
```

**Step 5: Run tests to verify**

Run: `bash scripts/tests/test-run-plan-context.sh && bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 6: Commit**

```bash
git add scripts/lib/run-plan-context.sh scripts/lib/run-plan-headless.sh scripts/tests/test-run-plan-context.sh
git commit -m "feat: add cross-run failure pattern persistence — learn from past batch failures"
```

---

## Batch 3: ast-grep Integration

context_refs: scripts/prior-art-search.sh, scripts/quality-gate.sh, scripts/lesson-check.sh, docs/lessons/TEMPLATE.md

### Task 10: Create generate-ast-rules.sh

**Files:**
- Create: `scripts/generate-ast-rules.sh`
- Create: `scripts/patterns/` directory
- Test: `scripts/tests/test-generate-ast-rules.sh`

**Step 1: Write the failing test**

Create `scripts/tests/test-generate-ast-rules.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        FAILURES=$((FAILURES + 1))
    fi
}

WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT

# Create test lesson files
mkdir -p "$WORK/lessons"
cat > "$WORK/lessons/0001-test.md" << 'LESSON'
---
id: 1
title: "Bare except"
severity: blocker
languages: [python]
category: silent-failures
pattern:
  type: syntactic
  regex: "^\\s*except\\s*:"
  description: "bare except"
fix: "Use specific exception"
example:
  bad: |
    except:
        pass
  good: |
    except Exception as e:
        logger.error(e)
---
LESSON

cat > "$WORK/lessons/0033-async.md" << 'LESSON'
---
id: 33
title: "Async iteration mutable"
severity: blocker
languages: [python]
category: async-traps
pattern:
  type: semantic
  description: "async loop iterates over mutable instance attribute"
fix: "Snapshot with list()"
example:
  bad: |
    async for item in self.connections:
        await item.send(data)
  good: |
    for item in list(self.connections):
        await item.send(data)
---
LESSON

# Test: generates pattern files from lessons
"$SCRIPT_DIR/../generate-ast-rules.sh" --lessons-dir "$WORK/lessons" --output-dir "$WORK/patterns"

# Syntactic lessons should NOT generate ast-grep rules (grep handles them)
assert_eq "generate-ast-rules: skips syntactic patterns" "false" \
    "$(test -f "$WORK/patterns/0001-test.yml" && echo true || echo false)"

# Semantic lessons with supported languages should generate rules
# (only if the pattern is convertible to ast-grep format)
ls "$WORK/patterns/" > "$WORK/pattern-list.txt" 2>/dev/null || true
TESTS=$((TESTS + 1))
echo "PASS: generate-ast-rules: runs without error"

# Test: --list flag shows what would be generated
output=$("$SCRIPT_DIR/../generate-ast-rules.sh" --lessons-dir "$WORK/lessons" --list 2>&1)
assert_contains "generate-ast-rules: list shows lesson count" "lesson" "$output"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-generate-ast-rules.sh`
Expected: FAIL — script doesn't exist

**Step 3: Implement generate-ast-rules.sh**

Create `scripts/generate-ast-rules.sh`:

```bash
#!/usr/bin/env bash
# generate-ast-rules.sh — Generate ast-grep rules from lesson YAML frontmatter
#
# Reads lesson files with pattern.type: semantic and supported languages,
# generates ast-grep YAML rule files in the output directory.
#
# Usage: generate-ast-rules.sh --lessons-dir <dir> --output-dir <dir> [--list]
set -euo pipefail

LESSONS_DIR=""
OUTPUT_DIR=""
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lessons-dir) LESSONS_DIR="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --list) LIST_ONLY=true; shift ;;
        -h|--help)
            echo "Usage: generate-ast-rules.sh --lessons-dir <dir> --output-dir <dir> [--list]"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$LESSONS_DIR" ]]; then
    echo "ERROR: --lessons-dir required" >&2
    exit 1
fi

generated=0
skipped_syntactic=0
skipped_unconvertible=0

for lesson_file in "$LESSONS_DIR"/*.md; do
    [[ -f "$lesson_file" ]] || continue
    [[ "$(basename "$lesson_file")" == "TEMPLATE.md" ]] && continue
    [[ "$(basename "$lesson_file")" == "SUMMARY.md" ]] && continue
    [[ "$(basename "$lesson_file")" == "FRAMEWORK.md" ]] && continue

    # Extract frontmatter
    local_id=$(sed -n '/^---$/,/^---$/{/^id:/s/^id: *//p}' "$lesson_file" | head -1)
    local_type=$(sed -n '/^---$/,/^---$/{/^  type:/s/^  type: *//p}' "$lesson_file" | head -1)
    local_title=$(sed -n '/^---$/,/^---$/{/^title:/s/^title: *"*//p}' "$lesson_file" | head -1 | sed 's/"$//')
    local_langs=$(sed -n '/^---$/,/^---$/{/^languages:/s/^languages: *//p}' "$lesson_file" | head -1)

    # Skip syntactic patterns (grep handles these)
    if [[ "$local_type" == "syntactic" ]]; then
        skipped_syntactic=$((skipped_syntactic + 1))
        continue
    fi

    # Only generate for languages ast-grep supports
    if [[ "$local_langs" != *"python"* && "$local_langs" != *"javascript"* && "$local_langs" != *"typescript"* ]]; then
        skipped_unconvertible=$((skipped_unconvertible + 1))
        continue
    fi

    local_basename=$(basename "$lesson_file" .md)

    if [[ "$LIST_ONLY" == true ]]; then
        echo "  Would generate: $local_basename.yml (lesson $local_id: $local_title)"
        generated=$((generated + 1))
        continue
    fi

    mkdir -p "$OUTPUT_DIR"

    # Extract bad example from frontmatter for rule pattern
    local_bad_example=$(sed -n '/^  bad: |$/,/^  good: |$/{/^  bad: |$/d; /^  good: |$/d; p}' "$lesson_file" | sed 's/^    //')

    # Generate ast-grep rule YAML
    cat > "$OUTPUT_DIR/$local_basename.yml" << RULE
id: $local_basename
message: "$local_title"
severity: warning
language: $(echo "$local_langs" | sed 's/\[//;s/\]//;s/,.*//;s/ //g')
note: "Auto-generated from lesson $local_id. See docs/lessons/$local_basename.md"
RULE

    generated=$((generated + 1))
done

if [[ "$LIST_ONLY" == true ]]; then
    echo ""
    echo "Summary: $generated convertible, $skipped_syntactic syntactic (grep), $skipped_unconvertible unsupported language"
else
    echo "Generated $generated ast-grep rules in ${OUTPUT_DIR:-<none>}"
    echo "Skipped: $skipped_syntactic syntactic (grep handles), $skipped_unconvertible unsupported language"
fi
```

**Step 4: Create built-in pattern files**

Create `scripts/patterns/bare-except.yml`:
```yaml
id: bare-except
message: "Bare except clause swallows all exceptions — catch a specific exception class"
severity: error
language: python
rule:
  pattern: "except: $$$BODY"
```

Create `scripts/patterns/async-no-await.yml`:
```yaml
id: async-no-await
message: "async def with no await in body — remove async keyword or add await"
severity: warning
language: python
note: "Requires whole-function analysis — this is a simplified pattern"
```

Create `scripts/patterns/empty-catch.yml`:
```yaml
id: empty-catch
message: "Empty catch block silently swallows errors — add logging"
severity: warning
language: javascript
rule:
  pattern: "catch ($ERR) {}"
```

**Step 5: Run tests to verify**

Run: `bash scripts/tests/test-generate-ast-rules.sh && bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 6: Commit**

```bash
git add scripts/generate-ast-rules.sh scripts/patterns/ scripts/tests/test-generate-ast-rules.sh
git commit -m "feat: add ast-grep rule generation from lesson files + built-in patterns"
```

### Task 11: Add ast-grep discovery mode to prior-art-search.sh

**Files:**
- Modify: `scripts/prior-art-search.sh`
- Test: `scripts/tests/test-prior-art-search.sh`

**Step 1: Write the failing test**

Add to `scripts/tests/test-prior-art-search.sh` (or create if not present):

```bash
# ast-grep discovery mode test (skips gracefully when not installed)
output=$("$SCRIPT_DIR/../prior-art-search.sh" "error handling patterns" 2>&1 || true)
if command -v ast-grep >/dev/null 2>&1; then
    assert_contains "prior-art: ast-grep section present" "Structural" "$output"
else
    assert_contains "prior-art: ast-grep skip note" "ast-grep" "$output"
fi
```

**Step 2: Implement ast-grep discovery in prior-art-search.sh**

Add a new section after existing text search:

```bash
# === Structural code search (ast-grep) ===
if command -v ast-grep >/dev/null 2>&1; then
    echo ""
    echo "=== Structural Code Search (ast-grep) ==="
    # Run built-in patterns against local codebase
    PATTERNS_DIR="$SCRIPT_DIR/patterns"
    if [[ -d "$PATTERNS_DIR" ]]; then
        for pattern_file in "$PATTERNS_DIR"/*.yml; do
            [[ -f "$pattern_file" ]] || continue
            local_name=$(basename "$pattern_file" .yml)
            matches=$(ast-grep scan --rule "$pattern_file" . 2>/dev/null | head -5 || true)
            if [[ -n "$matches" ]]; then
                echo "  Pattern '$local_name': $(echo "$matches" | wc -l) matches"
            fi
        done
    fi
else
    echo ""
    echo "=== Structural Code Search ==="
    echo "  ast-grep not installed — skipping structural analysis"
    echo "  Install: npm i -g @ast-grep/cli"
fi
```

**Step 3: Run tests and commit**

Run: `bash scripts/tests/run-all-tests.sh`

```bash
git add scripts/prior-art-search.sh scripts/tests/test-prior-art-search.sh
git commit -m "feat: add ast-grep discovery mode to prior-art search"
```

### Task 12: Add ast-grep enforcement mode to quality-gate.sh

**Files:**
- Modify: `scripts/quality-gate.sh`
- Test: `scripts/tests/test-quality-gate.sh`

**Step 1: Add ast-grep check section to quality-gate.sh**

After the lint check and before the test suite section, add:

```bash
# === Check 2.5: ast-grep structural analysis (optional) ===
if [[ "$QUICK" != true ]] && command -v ast-grep >/dev/null 2>&1; then
    echo ""
    echo "=== Quality Gate: Structural Analysis (ast-grep) ==="
    PATTERNS_DIR="$SCRIPT_DIR/patterns"
    ast_violations=0
    if [[ -d "$PATTERNS_DIR" ]]; then
        for pattern_file in "$PATTERNS_DIR"/*.yml; do
            [[ -f "$pattern_file" ]] || continue
            matches=$(ast-grep scan --rule "$pattern_file" "$PROJECT_ROOT" 2>/dev/null || true)
            if [[ -n "$matches" ]]; then
                echo "WARNING: $(basename "$pattern_file" .yml): $(echo "$matches" | wc -l) matches"
                echo "$matches" | head -3
                ast_violations=$((ast_violations + 1))
            fi
        done
    fi
    if [[ $ast_violations -gt 0 ]]; then
        echo "ast-grep: $ast_violations pattern(s) matched (advisory)"
    else
        echo "ast-grep: clean"
    fi
fi
```

Note: ast-grep violations are advisory (warnings) by default. No `exit 1` — this doesn't fail the gate unless `--strict-ast` is added in a future iteration.

**Step 2: Run tests and commit**

Run: `bash scripts/tests/run-all-tests.sh`

```bash
git add scripts/quality-gate.sh scripts/tests/test-quality-gate.sh
git commit -m "feat: add ast-grep structural analysis to quality gate (advisory mode)"
```

---

## Batch 4: Team Mode with Decision Gate

context_refs: scripts/run-plan.sh, scripts/lib/run-plan-headless.sh, scripts/lib/run-plan-parser.sh, scripts/lib/run-plan-context.sh

### Task 13: Create run-plan-routing.sh with plan analysis

**Files:**
- Create: `scripts/lib/run-plan-routing.sh`
- Test: `scripts/tests/test-run-plan-routing.sh`

**Step 1: Write the failing test**

Create `scripts/tests/test-run-plan-routing.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-parser.sh"
source "$SCRIPT_DIR/../lib/run-plan-routing.sh"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT

# Plan with clear parallel batches
cat > "$WORK/parallel-plan.md" << 'PLAN'
## Batch 1: Foundation

**Files:**
- Create: `src/lib.sh`

### Task 1: Create lib
Write lib.

## Batch 2: Feature A

**Files:**
- Create: `src/feature-a.sh`
context_refs: src/lib.sh

### Task 2: Build feature A

## Batch 3: Feature B

**Files:**
- Create: `src/feature-b.sh`
context_refs: src/lib.sh

### Task 3: Build feature B

## Batch 4: Integration

**Files:**
- Modify: `src/feature-a.sh`
- Modify: `src/feature-b.sh`
context_refs: src/feature-a.sh, src/feature-b.sh

### Task 4: Wire together
PLAN

# Test dependency graph building
deps=$(build_dependency_graph "$WORK/parallel-plan.md")
assert_eq "dep graph: B2 depends on B1" "true" "$(echo "$deps" | jq '.["2"] | contains(["1"])')"
assert_eq "dep graph: B3 depends on B1" "true" "$(echo "$deps" | jq '.["3"] | contains(["1"])')"
assert_eq "dep graph: B4 depends on B2 and B3" "true" "$(echo "$deps" | jq '.["4"] | (contains(["2"]) and contains(["3"]))')"

# Test parallelism score
score=$(compute_parallelism_score "$WORK/parallel-plan.md")
TESTS=$((TESTS + 1))
if [[ "$score" -gt 40 ]]; then
    echo "PASS: parallelism score: $score > 40 (batches 2,3 can run parallel)"
else
    echo "FAIL: parallelism score: $score <= 40"
    FAILURES=$((FAILURES + 1))
fi

# Test mode recommendation
mode=$(recommend_execution_mode "$score" "false" 21)
assert_eq "recommend: team for high score" "team" "$mode"

# Sequential plan (each batch depends on previous)
cat > "$WORK/sequential-plan.md" << 'PLAN'
## Batch 1: Setup

**Files:**
- Create: `src/main.sh`

### Task 1: Setup

## Batch 2: Extend

**Files:**
- Modify: `src/main.sh`
context_refs: src/main.sh

### Task 2: Extend

## Batch 3: Finalize

**Files:**
- Modify: `src/main.sh`
context_refs: src/main.sh

### Task 3: Finalize
PLAN

score=$(compute_parallelism_score "$WORK/sequential-plan.md")
TESTS=$((TESTS + 1))
if [[ "$score" -lt 30 ]]; then
    echo "PASS: sequential plan score: $score < 30"
else
    echo "FAIL: sequential plan score: $score >= 30"
    FAILURES=$((FAILURES + 1))
fi

mode=$(recommend_execution_mode "$score" "false" 21)
assert_eq "recommend: headless for low score" "headless" "$mode"

# Test model routing
model=$(classify_batch_model "$WORK/parallel-plan.md" 1)
assert_eq "model: batch with Create files = sonnet" "sonnet" "$model"

# Verification batch
cat > "$WORK/verify-plan.md" << 'PLAN'
## Batch 1: Verify everything

### Task 1: Run all tests

**Step 1: Run tests**
Run: `bash scripts/tests/run-all-tests.sh`

**Step 2: Check line counts**
Run: `wc -l scripts/*.sh`
PLAN

model=$(classify_batch_model "$WORK/verify-plan.md" 1)
assert_eq "model: batch with only Run commands = haiku" "haiku" "$model"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-run-plan-routing.sh`
Expected: FAIL

**Step 3: Implement run-plan-routing.sh**

Create `scripts/lib/run-plan-routing.sh` with:
- `build_dependency_graph()` — parse Files/context_refs to build JSON dependency graph
- `compute_parallelism_score()` — 0-100 score based on independence
- `recommend_execution_mode()` — headless vs team based on score + capabilities
- `classify_batch_model()` — sonnet/haiku/opus based on batch content
- `generate_routing_plan()` — human-readable routing plan output
- Configuration constants at top of file

Target: ~200 lines. Implementation should parse `**Files:**` sections for Create/Modify paths and `context_refs:` lines for dependencies. Build a JSON object mapping batch number to list of dependent batch numbers. Score based on: how many batches can run in parallel groups.

**Step 4: Run tests to verify**

Run: `bash scripts/tests/test-run-plan-routing.sh && bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 5: Commit**

```bash
git add scripts/lib/run-plan-routing.sh scripts/tests/test-run-plan-routing.sh
git commit -m "feat: add plan analysis with dependency graph, parallelism scoring, and model routing"
```

### Task 14: Wire decision gate into run-plan.sh

**Files:**
- Modify: `scripts/run-plan.sh`

**Step 1: Source routing lib and add analysis before mode selection**

In `scripts/run-plan.sh`, after `print_banner` in `main()` and before the `case "$MODE"` block, add:

```bash
    # Analyze plan and show routing plan
    source "$SCRIPT_DIR/lib/run-plan-routing.sh"
    local score
    score=$(compute_parallelism_score "$PLAN_FILE" 2>/dev/null || echo "0")
    local available_mem
    available_mem=$(free -g 2>/dev/null | awk '/Mem:/{print $7}' || echo "999")
    local teams_available=false
    [[ -n "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]] && teams_available=true

    # Show routing plan
    generate_routing_plan "$PLAN_FILE" "$score" "$teams_available" "$available_mem" "$MODE"

    # Auto-select mode if not explicitly set
    if [[ "$MODE" == "auto" ]]; then
        MODE=$(recommend_execution_mode "$score" "$teams_available" "$available_mem")
        echo ""
        echo "Auto-selected mode: $MODE (parallelism score: $score)"
    fi
```

Add `auto` as a new mode option (default when no `--mode` specified). Update arg parsing to default `MODE="auto"` instead of `MODE="headless"`.

**Step 2: Run tests to verify nothing breaks**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 3: Commit**

```bash
git add scripts/run-plan.sh
git commit -m "feat: add decision gate — auto-select execution mode based on plan analysis"
```

### Task 15: Implement run-plan-team.sh

**Files:**
- Create: `scripts/lib/run-plan-team.sh`
- Test: `scripts/tests/test-run-plan-team.sh`

**Step 1: Write run_mode_team()**

Create `scripts/lib/run-plan-team.sh`:

This is the most complex new module. It needs to:
1. Create a team (TeamCreate)
2. Create tasks from batches (respecting dependency graph)
3. Spawn worker agents with isolated worktrees
4. Monitor batch completions and run quality gates
5. Progressive merge after each batch passes
6. Handle speculative execution

Since this runs within a Claude Code session (not headless), it generates the team setup as a prompt/script that Claude Code executes. The headless fallback generates a shell script that orchestrates multiple `claude -p` processes.

For the headless case, implement a simplified version:
- Sequential batch groups (parallel within a group)
- Each group's batches run as parallel background `claude -p` processes
- Wait for all in group, run quality gates, merge, next group

Target: ~200 lines.

**Key function:**

```bash
run_mode_team() {
    local dep_graph
    dep_graph=$(build_dependency_graph "$PLAN_FILE")

    # Build parallel groups from dependency graph
    local groups
    groups=$(compute_parallel_groups "$dep_graph" "$START_BATCH" "$END_BATCH")
    # groups is a JSON array of arrays: [[1],[2,3],[4]]

    local group_count
    group_count=$(echo "$groups" | jq 'length')

    for ((g = 0; g < group_count; g++)); do
        local group_batches
        group_batches=$(echo "$groups" | jq -r ".[$g][]")
        local batch_count
        batch_count=$(echo "$group_batches" | wc -l)

        echo ""
        echo "================================================================"
        echo "  Group $((g+1)): $(echo "$group_batches" | tr '\n' ',' | sed 's/,$//')"
        echo "  ($batch_count batches in parallel)"
        echo "================================================================"

        # Launch each batch in the group in parallel
        local pids=()
        local batch_logs=()
        for batch in $group_batches; do
            local model
            model=$(classify_batch_model "$PLAN_FILE" "$batch")
            local log_file="$WORKTREE/logs/batch-${batch}-team.log"
            batch_logs+=("$log_file")

            # Create isolated worktree for this batch
            local batch_worktree="$WORKTREE/.worktrees/batch-$batch"
            mkdir -p "$batch_worktree"
            # Use git worktree if in a git repo
            if git rev-parse --git-dir >/dev/null 2>&1; then
                git worktree add -q "$batch_worktree" HEAD 2>/dev/null || true
            fi

            local prompt
            prompt=$(build_batch_prompt "$PLAN_FILE" "$batch" "$batch_worktree" "$PYTHON" "$QUALITY_GATE_CMD" "0")

            echo "  Starting batch $batch ($model) in background..."
            CLAUDECODE= claude -p "$prompt" \
                --model "$model" \
                --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
                --permission-mode bypassPermissions \
                2>&1 > "$log_file" &
            pids+=($!)
        done

        # Wait for all batches in group
        local all_passed=true
        for i in "${!pids[@]}"; do
            local pid=${pids[$i]}
            local batch=$(echo "$group_batches" | sed -n "$((i+1))p")
            wait "$pid" || true

            # Run quality gate
            local gate_exit=0
            run_quality_gate "$WORKTREE" "$QUALITY_GATE_CMD" "$batch" "0" || gate_exit=$?
            if [[ $gate_exit -ne 0 ]]; then
                echo "  Batch $batch FAILED quality gate"
                all_passed=false
            else
                echo "  Batch $batch PASSED"
                # Merge worktree back
                # (simplified: copy changed files back)
            fi
        done

        if [[ "$all_passed" != true ]]; then
            echo "Group $((g+1)) had failures. Stopping."
            exit 1
        fi
    done
}
```

Note: This is a simplified team mode. Full agent teams integration (TeamCreate, SendMessage) requires running inside a Claude Code session, not headless bash. The headless version uses parallel `claude -p` processes with worktree isolation.

**Step 2: Write tests**

Test `compute_parallel_groups()` with the parallel and sequential plans from Task 13's test fixtures.

**Step 3: Run tests and commit**

```bash
git add scripts/lib/run-plan-team.sh scripts/tests/test-run-plan-team.sh
git commit -m "feat: implement team mode with parallel batch groups and worktree isolation"
```

### Task 16: Add routing decision log

**Files:**
- Modify: `scripts/lib/run-plan-routing.sh` (add `log_routing_decision()`)
- Modify: `scripts/lib/run-plan-team.sh` (call logger)
- Modify: `scripts/lib/run-plan-headless.sh` (call logger)

**Step 1: Implement log_routing_decision()**

Add to `scripts/lib/run-plan-routing.sh`:

```bash
log_routing_decision() {
    local worktree="$1" category="$2" message="$3"
    local log_file="$worktree/logs/routing-decisions.log"
    mkdir -p "$(dirname "$log_file")"
    echo "[$(date '+%H:%M:%S')] $category: $message" >> "$log_file"
}
```

Wire into team.sh (MODE, PARALLEL, MODEL, GATE_PASS, MERGE decisions) and headless.sh (MODE selection).

**Step 2: Run tests and commit**

```bash
git add scripts/lib/run-plan-routing.sh scripts/lib/run-plan-team.sh scripts/lib/run-plan-headless.sh
git commit -m "feat: add routing decision log for execution traceability"
```

### Task 17: Wire pipeline-status.sh to show routing results

**Files:**
- Modify: `scripts/pipeline-status.sh`

**Step 1: Add routing section to pipeline-status output**

After existing status sections, add:

```bash
# Routing decisions (if available)
if [[ -f "$PROJECT_ROOT/logs/routing-decisions.log" ]]; then
    echo ""
    echo "=== Routing Decisions ==="
    tail -20 "$PROJECT_ROOT/logs/routing-decisions.log"
fi
```

**Step 2: Run tests and commit**

```bash
git add scripts/pipeline-status.sh
git commit -m "feat: show routing decisions in pipeline-status.sh output"
```

---

## Batch 5: Parallel Patch Sampling

context_refs: scripts/lib/run-plan-team.sh, scripts/lib/run-plan-routing.sh, scripts/lib/run-plan-headless.sh, scripts/lib/run-plan-context.sh

### Task 18: Create run-plan-scoring.sh

**Files:**
- Create: `scripts/lib/run-plan-scoring.sh`
- Test: `scripts/tests/test-run-plan-scoring.sh`

**Step 1: Write the failing test**

Create `scripts/tests/test-run-plan-scoring.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-scoring.sh"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

# Gate failed = score 0
score=$(score_candidate 0 50 100 0 0 0)
assert_eq "score: gate failed = 0" "0" "$score"

# Gate passed, good metrics
score=$(score_candidate 1 50 100 2 0 0)
TESTS=$((TESTS + 1))
if [[ "$score" -gt 0 ]]; then
    echo "PASS: score: gate passed = positive ($score)"
else
    echo "FAIL: score: gate passed should be positive ($score)"
    FAILURES=$((FAILURES + 1))
fi

# More tests = higher score
score_a=$(score_candidate 1 50 100 0 0 0)
score_b=$(score_candidate 1 80 100 0 0 0)
TESTS=$((TESTS + 1))
if [[ "$score_b" -gt "$score_a" ]]; then
    echo "PASS: score: more tests = higher score ($score_b > $score_a)"
else
    echo "FAIL: score: more tests should be higher ($score_b <= $score_a)"
    FAILURES=$((FAILURES + 1))
fi

# Lesson violations = penalty
score_clean=$(score_candidate 1 50 100 0 0 0)
score_dirty=$(score_candidate 1 50 100 0 2 0)
TESTS=$((TESTS + 1))
if [[ "$score_clean" -gt "$score_dirty" ]]; then
    echo "PASS: score: lesson violations penalized ($score_clean > $score_dirty)"
else
    echo "FAIL: score: lesson violations not penalized ($score_clean <= $score_dirty)"
    FAILURES=$((FAILURES + 1))
fi

# select_winner picks highest score
winner=$(select_winner "500 300 700 0")
assert_eq "select_winner: picks index of highest" "2" "$winner"

# select_winner returns -1 when all zero
winner=$(select_winner "0 0 0")
assert_eq "select_winner: all zero = -1 (no winner)" "-1" "$winner"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test to verify it fails**

**Step 3: Implement run-plan-scoring.sh**

Create `scripts/lib/run-plan-scoring.sh`:

```bash
#!/usr/bin/env bash
# run-plan-scoring.sh — Candidate scoring for parallel patch sampling
#
# Functions:
#   score_candidate <gate_passed> <test_count> <diff_lines> <lint_warnings> <lesson_violations> <ast_violations>
#   select_winner <scores_string>  -> index of highest score (0-based), -1 if all zero

score_candidate() {
    local gate_passed="${1:-0}"
    local test_count="${2:-0}"
    local diff_lines="${3:-1}"
    local lint_warnings="${4:-0}"
    local lesson_violations="${5:-0}"
    local ast_violations="${6:-0}"

    if [[ "$gate_passed" -ne 1 ]]; then
        echo 0
        return
    fi

    # Avoid division by zero
    [[ "$diff_lines" -lt 1 ]] && diff_lines=1

    local score=$(( (test_count * 10) + (10000 / (diff_lines + 1)) + (1000 / (lint_warnings + 1)) - (lesson_violations * 200) - (ast_violations * 100) ))

    # Floor at 1 (gate passed = always positive)
    [[ "$score" -lt 1 ]] && score=1
    echo "$score"
}

select_winner() {
    local scores_str="$1"
    local max_score=0
    local max_idx=-1
    local idx=0

    for score in $scores_str; do
        if [[ "$score" -gt "$max_score" ]]; then
            max_score="$score"
            max_idx=$idx
        fi
        idx=$((idx + 1))
    done

    echo "$max_idx"
}
```

**Step 4: Run tests and commit**

```bash
git add scripts/lib/run-plan-scoring.sh scripts/tests/test-run-plan-scoring.sh
git commit -m "feat: add candidate scoring for parallel patch sampling"
```

### Task 19: Implement sampling in run-plan-headless.sh

**Files:**
- Modify: `scripts/lib/run-plan-headless.sh`
- Modify: `scripts/run-plan.sh` (add --sample flag)

**Step 1: Add --sample flag to run-plan.sh arg parsing**

Add to arg parsing:
```bash
SAMPLE_COUNT=0  # 0 = disabled

# In parse_args:
--sample) SAMPLE_COUNT="${2:-3}"; shift 2 ;;
--no-sample) SAMPLE_COUNT=0; shift ;;
```

**Step 2: Add sampling logic to retry path in run-plan-headless.sh**

In the retry section (after first failure), instead of simple retry, check if sampling is enabled:

```bash
# If sampling enabled and this is a retry, use parallel candidates
if [[ "$SAMPLE_COUNT" -gt 0 && $attempt -ge 2 ]]; then
    echo "  Sampling $SAMPLE_COUNT candidates for batch $batch..."
    local scores=""
    local candidate_logs=()

    for ((c = 0; c < SAMPLE_COUNT; c++)); do
        local variant_suffix=""
        case $c in
            0) variant_suffix="" ;;  # vanilla
            1) variant_suffix=$'\nIMPORTANT: Take a fundamentally different approach than the previous attempt.' ;;
            2) variant_suffix=$'\nIMPORTANT: Make the minimum possible change to pass the quality gate.' ;;
        esac

        local candidate_log="$WORKTREE/logs/batch-${batch}-candidate-${c}.log"
        candidate_logs+=("$candidate_log")

        CLAUDECODE= claude -p "${full_prompt}${variant_suffix}" \
            --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
            --permission-mode bypassPermissions \
            2>&1 > "$candidate_log" || true

        # Score this candidate
        local gate_exit=0
        run_quality_gate "$WORKTREE" "$QUALITY_GATE_CMD" "sample-$c" "0" || gate_exit=$?
        local gate_passed=0
        [[ $gate_exit -eq 0 ]] && gate_passed=1

        local new_tests
        new_tests=$(get_previous_test_count "$WORKTREE")
        local diff_size
        diff_size=$(cd "$WORKTREE" && git diff --stat HEAD~1 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1 || echo "100")

        local score
        score=$(score_candidate "$gate_passed" "${new_tests:-0}" "${diff_size:-100}" "0" "0" "0")
        scores+="$score "

        # If gate failed, reset for next candidate
        if [[ $gate_passed -eq 0 ]]; then
            cd "$WORKTREE" && git checkout . 2>/dev/null || true
        fi
    done

    # Pick winner
    local winner
    winner=$(select_winner "$scores")
    if [[ "$winner" -ge 0 ]]; then
        echo "  Winner: candidate $winner (scores: $scores)"
        batch_passed=true
        break
    else
        echo "  No candidate passed quality gate"
    fi
fi
```

**Step 3: Add sampling outcome logging**

After a winner is selected, append to `logs/sampling-outcomes.json`:

```bash
if [[ "$winner" -ge 0 ]]; then
    local outcomes_file="$WORKTREE/logs/sampling-outcomes.json"
    mkdir -p "$(dirname "$outcomes_file")"
    [[ ! -f "$outcomes_file" ]] && echo "[]" > "$outcomes_file"

    local variant_name="vanilla"
    [[ "$winner" -eq 1 ]] && variant_name="different-approach"
    [[ "$winner" -eq 2 ]] && variant_name="minimal-change"

    jq --arg bt "$title" --arg vn "$variant_name" --arg sc "${scores%% *}" \
        '. += [{"batch_type": $bt, "prompt_variant": $vn, "won": true, "score": ($sc | tonumber), "timestamp": (now | todate)}]' \
        "$outcomes_file" > "$outcomes_file.tmp" && mv "$outcomes_file.tmp" "$outcomes_file" || true
fi
```

**Step 4: Run all tests to verify**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 5: Commit**

```bash
git add scripts/run-plan.sh scripts/lib/run-plan-headless.sh scripts/lib/run-plan-scoring.sh
git commit -m "feat: implement parallel patch sampling with candidate scoring and outcome logging"
```

### Task 20: Verify all scripts under 300 lines

**Step 1: Check line counts**

Run: `wc -l scripts/*.sh scripts/lib/*.sh | sort -n`

If any script exceeds 300 lines, extract functions into a new lib module.

**Step 2: Run full test suite**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 3: Run quality gate**

Run: `bash scripts/quality-gate.sh --project-root .`
Expected: ALL PASSED (should now detect bash test suite)

### Task 21: Final verification — vertical pipeline trace

**Step 1: Dry-run auto-compound.sh**

Run: `bash scripts/auto-compound.sh . --dry-run`
Expected: Shows all 6+ stages of the pipeline (analyze, branch, prior-art, PRD, quality gate config, ralph loop, push/PR)

**Step 2: Run pipeline-status.sh**

Run: `bash scripts/pipeline-status.sh --project-root .`
Expected: Shows state, routing decisions, test counts

**Step 3: Verify run-plan.sh shows routing plan**

Run: `bash scripts/run-plan.sh docs/plans/2026-02-21-code-factory-v2-phase4-implementation-plan.md --dry-run`
Expected: Shows parallelism score, dependency graph, model routing, mode recommendation

**Step 4: Commit any remaining changes**

```bash
git add -A
git commit -m "chore: final verification — all scripts under 300 lines, pipeline trace clean"
```

---

## Integration Wiring (Batch 5 final)

### Task 22: Update CLAUDE.md with new capabilities

**Files:**
- Modify: `CLAUDE.md`

Add to the Quality Gates section:
- ast-grep structural analysis (optional)
- `--sample N` flag for patch sampling
- Team mode with `--mode team` or auto-detection

Add to State & Persistence section:
- `logs/failure-patterns.json` — cross-run failure learning
- `logs/routing-decisions.log` — execution traceability
- `logs/sampling-outcomes.json` — prompt variant learning

**Step 1: Update CLAUDE.md**

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with Phase 4 capabilities — context assembler, ast-grep, team mode, sampling"
```
