# Lessons Learned — Summary

79 lessons captured from autonomous coding workflows. Each is a standalone markdown file with YAML frontmatter, grep-detectable patterns (syntactic) or AI-reviewable descriptions (semantic), and concrete fix guidance.

## Quick Reference

| ID | Title | Category | Severity | Type |
|----|-------|----------|----------|------|
| 0001 | Bare exception swallowing hides failures | silent-failures | blocker | syntactic |
| 0002 | async def without await returns truthy coroutine | async-traps | blocker | semantic |
| 0003 | asyncio.create_task without done_callback swallows exceptions | silent-failures | should-fix | semantic |
| 0004 | Hardcoded count assertions break when datasets grow | test-anti-patterns | should-fix | syntactic |
| 0005 | sqlite3 connections leak without closing() context manager | silent-failures | should-fix | syntactic |
| 0006 | .venv/bin/pip installs to wrong site-packages | integration-boundaries | should-fix | syntactic |
| 0007 | Runner state file rejected by own git-clean check | integration-boundaries | should-fix | semantic |
| 0008 | Quality gate blind spot for non-standard test suites | silent-failures | should-fix | semantic |
| 0009 | Plan parser over-count burns empty API calls | silent-failures | should-fix | semantic |
| 0010 | `local` outside function silently misbehaves in bash | silent-failures | blocker | syntactic |
| 0011 | Batch execution writes tests for unimplemented code | integration-boundaries | should-fix | semantic |
| 0012 | API rejects markdown with unescaped special chars | integration-boundaries | nice-to-have | semantic |
| 0013 | `export` prefix in env files breaks naive parsing | silent-failures | should-fix | syntactic |
| 0014 | Decorator registries are import-time side effects | silent-failures | should-fix | semantic |
| 0015 | Frontend-backend schema drift invisible until e2e trace | integration-boundaries | should-fix | semantic |
| 0016 | Event-driven systems must seed current state on startup | integration-boundaries | should-fix | semantic |
| 0017 | Copy-pasted logic between modules diverges silently | integration-boundaries | should-fix | semantic |
| 0018 | Every layer passes its test while full pipeline is broken | integration-boundaries | should-fix | semantic |
| 0019 | systemd EnvironmentFile ignores `export` keyword | silent-failures | should-fix | syntactic |
| 0020 | Persist state incrementally before expensive work | silent-failures | should-fix | semantic |
| 0021 | Dual-axis testing: horizontal sweep + vertical trace | integration-boundaries | should-fix | semantic |
| 0022 | Build tool JSX factory shadowed by arrow params | silent-failures | blocker | syntactic |
| 0023 | Static analysis spiral — chasing lint fixes creates more bugs | test-anti-patterns | should-fix | semantic |
| 0024 | Shared pipeline features must share implementation | integration-boundaries | should-fix | semantic |
| 0025 | Defense-in-depth: validate at all entry points | integration-boundaries | should-fix | semantic |
| 0026 | Linter with no rules enabled = false enforcement | silent-failures | should-fix | semantic |
| 0027 | JSX silently drops wrong prop names | silent-failures | should-fix | semantic |
| 0028 | Never embed infrastructure details in client-side code | silent-failures | blocker | syntactic |
| 0029 | Never write secret values into committed files | silent-failures | blocker | syntactic |
| 0030 | Cache/registry updates must merge, never replace | integration-boundaries | should-fix | semantic |
| 0031 | Verify units at every boundary (0-1 vs 0-100) | integration-boundaries | should-fix | semantic |
| 0032 | Module lifecycle: subscribe after init, unsubscribe on shutdown | resource-lifecycle | should-fix | semantic |
| 0033 | Async iteration over mutable collections needs snapshot | async-traps | blocker | syntactic |
| 0034 | Caller-side missing await silently discards work | async-traps | blocker | semantic |
| 0035 | Duplicate registration IDs cause silent overwrite | silent-failures | should-fix | semantic |
| 0036 | WebSocket dirty disconnects raise RuntimeError, not close | resource-lifecycle | should-fix | semantic |
| 0037 | Parallel agents sharing worktree corrupt staging area | integration-boundaries | blocker | semantic |
| 0038 | Subscribe without stored ref = cannot unsubscribe | resource-lifecycle | should-fix | syntactic |
| 0039 | Fallback `or default()` hides initialization bugs | silent-failures | should-fix | semantic |
| 0040 | Process all events when 5% are relevant — filter first | performance | should-fix | semantic |
| 0041 | Ambiguous base dir variable causes path double-nesting | integration-boundaries | should-fix | semantic |
| 0042 | Spec compliance without quality review misses defensive gaps | integration-boundaries | should-fix | semantic |
| 0043 | Exact count assertions on extensible collections break on addition | test-anti-patterns | should-fix | syntactic |
| 0044 | Relative `file:` deps break in git worktrees | integration-boundaries | should-fix | semantic |
| 0045 | Iterative "how would you improve" catches 35% more design gaps | integration-boundaries | should-fix | semantic |
| 0046 | Plan-specified test assertions can have math bugs | test-anti-patterns | should-fix | semantic |
| 0047 | pytest runs single-threaded by default — add xdist | performance | should-fix | semantic |
| 0048 | Multi-batch plans need explicit integration wiring batch | integration-boundaries | should-fix | semantic |
| 0049 | A/B verification finds zero-overlap bug classes | integration-boundaries | should-fix | semantic |
| 0050 | Editing files sourced by a running process breaks function signatures | integration-boundaries | blocker | semantic |
| 0051 | Infrastructure fixes in a plan cannot benefit the run executing that plan | integration-boundaries | should-fix | semantic |
| 0052 | Uncommitted changes from parallel work fail the quality gate git-clean check | integration-boundaries | blocker | semantic |
| 0053 | Missing jq -c flag causes string comparison failures in tests | test-anti-patterns | should-fix | syntactic |
| 0054 | Markdown parser matches headers inside code blocks and test fixtures | silent-failures | should-fix | semantic |
| 0055 | LLM agents compensate for garbled batch prompts using cross-batch context | integration-boundaries | nice-to-have | semantic |
| 0056 | grep -c exits 1 on zero matches, breaking || fallback arithmetic | silent-failures | should-fix | syntactic |
| 0057 | New generated artifacts break git-clean quality gates | integration-boundaries | should-fix | semantic |
| 0058 | Dead config keys never consumed by any module | silent-failures | should-fix | semantic |
| 0059 | Contract test shared structures across producer and consumer | test-anti-patterns | should-fix | semantic |
| 0060 | set -e kills long-running bash scripts silently on inter-step failures | silent-failures | blocker | semantic |
| 0061 | Context injection into tracked files creates dirty git state when subprocess commits | integration-boundaries | should-fix | semantic |
| 0062 | Sibling bugs hide next to the fix | integration-boundaries | should-fix | semantic |
| 0063 | One boolean flag serving two lifetimes is a conflation bug | silent-failures | should-fix | semantic |
| 0064 | Tests that pass for the wrong reason provide false confidence | test-anti-patterns | should-fix | syntactic |
| 0065 | pipefail grep count double output | silent-failures | should-fix | syntactic |
| 0066 | local keyword outside function | silent-failures | blocker | syntactic |
| 0067 | stdin hang non-interactive shell | silent-failures | should-fix | semantic |
| 0068 | Agent builds the wrong thing correctly | specification-drift | blocker | semantic |
| 0069 | Plan quality dominates execution quality 3:1 | specification-drift | should-fix | semantic |
| 0070 | Spec echo-back prevents 60% of agent failures | specification-drift | should-fix | semantic |
| 0071 | Positive instructions outperform negative ones for LLMs | specification-drift | should-fix | semantic |
| 0072 | Lost in the Middle — context placement affects accuracy 20pp | context-retrieval | should-fix | semantic |
| 0073 | Unscoped lessons cause 67% false positive rate at scale | context-retrieval | should-fix | semantic |
| 0074 | Stale context injection sends wrong batch's state | context-retrieval | should-fix | semantic |
| 0075 | Research artifacts must persist — ephemeral research is wasted | context-retrieval | should-fix | semantic |
| 0076 | Wrong decomposition contaminates all downstream batches | planning-control-flow | blocker | semantic |
| 0077 | Cherry-pick merges from parallel worktrees need manual resolution | planning-control-flow | should-fix | semantic |
| 0078 | Static review without live test optimizes for wrong risk class | planning-control-flow | should-fix | semantic |
| 0079 | Multi-batch plans need explicit integration wiring batch | planning-control-flow | should-fix | semantic |

## Root Cause Clusters

### Cluster A: Silent Failures

Something fails but produces no error, no log, no crash. The system continues with wrong data or missing functionality. You only discover the failure when a downstream consumer produces garbage — hours or days later.

**Lessons:** 0001, 0003, 0005, 0008, 0009, 0010, 0013, 0014, 0019, 0020, 0022, 0026, 0027, 0028, 0029, 0035, 0039, 0054, 0056, 0058, 0060, 0063

**Also silent (async/lifecycle):** 0002, 0033, 0034 (async bugs are silent failures with extra steps), 0032, 0036, 0038 (lifecycle bugs cause silent resource leaks)

**Pattern:** The failure mode is always the same — no exception, no log line, no crash. The operation appears to succeed. The root cause varies: swallowed exceptions (0001, 0003), wrong tool configuration (0008, 0026), implicit behavior (0010, 0014, 0019, 0022), or missing validation (0028, 0029).

**Defense:** Every `except` block logs before returning. Every tool configuration is tested against a known-bad input. Every implicit behavior is documented with an explicit test.

### Cluster B: Integration Boundaries

Each component works alone. The bug hides at the seam between two components — where one produces output and another consumes it. Unit tests pass. Integration fails.

**Lessons:** 0006, 0007, 0011, 0012, 0015, 0016, 0017, 0018, 0021, 0024, 0025, 0030, 0031, 0037, 0041, 0042, 0044, 0045, 0048, 0049, 0050, 0051, 0052, 0055, 0057, 0059, 0061, 0062

**Pattern:** Producer and consumer agree on the interface but disagree on semantics — units (0031), schema shape (0015), path depth (0041), or lifecycle timing (0016). Each passes its own tests because each tests against its own assumptions, not the other's reality.

**Defense:** Dual-axis testing (0021) — horizontal sweep confirms every interface exists, vertical trace confirms data flows end-to-end. Contract tests between producer and consumer. Shared schema definitions instead of independent copies.

### Cluster C: Cold-Start Assumptions

Works in steady state, fails on restart or first boot. The system depends on state that accumulates during runtime — event history, caches, registries — and produces wrong results when that state is empty.

**Lessons:** 0016, 0020, 0035, 0039

**Pattern:** The system is designed for the happy path (events flowing, caches warm, registries populated) and never tested from a cold start. First-boot behavior is an afterthought — or never thought of at all.

**Defense:** Test every component from empty state. Seed current state on startup via REST/query (0016). Checkpoint state incrementally (0020). Validate initialization rather than falling back silently (0039).

### Cluster D: Specification Drift

The agent builds the wrong thing correctly. Code passes tests, but tests validate the agent's interpretation — not the user's intent. The spec was misunderstood, and no echo-back step caught it.

**Lessons:** 0068, 0069, 0070, 0071

**Pattern:** The agent reads requirements, forms an interpretation, writes code and tests against that interpretation, and everything passes. The divergence from user intent is invisible because the feedback loop is closed — the agent grades its own homework.

**Defense:** Echo back requirements before implementing. Score plan quality before execution. Use positive instructions ("do Y") instead of negative ("don't do X"). The echo-back gate catches 60%+ of failures.

### Cluster E: Context & Retrieval

Information is available but buried, misscoped, or placed in the wrong position within the context window. The agent has access to the right data but doesn't use it effectively.

**Lessons:** 0072, 0073, 0074, 0075

**Pattern:** Critical requirements are lost in the middle of long context (0072), irrelevant lessons fire due to missing scope (0073), stale context from a previous batch pollutes the current one (0074), or research findings exist only in conversation and are lost on context reset (0075).

**Defense:** Place task at top, requirements at bottom (U-shaped attention). Scope lessons to projects. Use ephemeral context injection for batch-scoped data. Always write research to files.

### Cluster F: Planning & Control Flow

The plan itself is wrong — wrong decomposition, wrong integration assumptions, or wrong verification strategy. Individual batches execute correctly but the overall result is broken.

**Lessons:** 0076, 0077, 0078, 0079

**Pattern:** Decomposition errors compound downstream (0076), parallel worktree merges need semantic conflict resolution (0077), static review alone misses runtime bugs (0078), and components built in separate batches are never wired together (0079).

**Defense:** Validate decomposition before execution. Add explicit integration wiring batches. Combine static review with live testing. Use interactive conflict resolution for cherry-picks.

## Six Rules to Build By

1. **Log before fallback.** Every `except`, every `catch`, every `|| true` — log the failure before returning a default. Silent fallbacks are the #1 source of invisible bugs. (0001, 0003, 0039)

2. **Test from cold start.** If your system depends on accumulated state, test it from empty. Seed current state on boot, checkpoint incrementally, and verify initialization completed before proceeding. (0016, 0020, 0035)

3. **One source of truth.** When two components need the same logic, schema, or configuration — one owns it, the other imports it. Independent copies diverge. Always. (0015, 0017, 0024, 0030)

4. **Verify at boundaries.** Every time data crosses a boundary (module to module, service to service, human to machine), verify the contract: types, units, format, completeness. Don't trust, verify. (0025, 0031, 0042)

5. **Trace end-to-end.** Unit tests are necessary but not sufficient. At least one test must trace a single input through every layer to the final output. If it takes too long to write, the architecture has too many layers. (0018, 0021, 0048)

6. **Make failures visible.** Every gate, check, and quality tool must be tested against a known-bad input to prove it actually catches something. A tool that reports "0 issues" on any input is worse than no tool. (0008, 0026, 0043)

## Diagnostic Shortcuts

When you see this symptom, check these lessons first.

| Symptom | Check First |
|---------|-------------|
| Feature works but produces no output on restart | 0016, 0020 |
| Tests pass but feature doesn't work end-to-end | 0018, 0021, 0048 |
| Exception happens but no log entry appears | 0001, 0003, 0034 |
| Script works on one machine, fails on another | 0010, 0019 |
| Quality gate reports "no issues" on bad code | 0008, 0026 |
| Frontend shows stale or wrong data | 0015, 0031 |
| Registry/cache missing entries after update | 0030, 0035 |
| WebSocket connection drops without error | 0036, 0038 |
| Async function appears to do nothing | 0002, 0034 |
| Build works locally but fails in CI/worktree | 0037, 0044 |
| Component renders blank in JSX | 0022, 0027 |
| API rejects message that looks correct | 0012, 0013 |
| Secret value appears in git log | 0029 |
| Test suite takes 10x longer than expected | 0047 |
| Test breaks every time collection grows | 0004, 0043 |
| Lint fix creates new lint failures | 0023 |
| Plan looks complete but integration is broken | 0011, 0042, 0045, 0049 |
| Quality gate fails but batch agent didn't cause it | 0050, 0052 |
| Infrastructure fix committed but not taking effect | 0051 |
| Parser finds more batches/tasks than plan actually has | 0054 |
| jq assertion fails with multiline vs compact mismatch | 0053 |
| Agent implements correct work despite garbled prompt | 0055 |
| Bash arithmetic fails with "syntax error in expression" | 0056 |
| Quality gate fails with "uncommitted changes" after adding new feature | 0007, 0052, 0057, 0061 |
| Long-running bash script dies silently between steps | 0060 |
| Config key exists but has no effect | 0058 |
| Fixed a bug but same bug exists in sibling function | 0062 |
| Boolean flag means different things at different times | 0063 |
| Test passes but reversing the fix doesn't break it | 0064 |
