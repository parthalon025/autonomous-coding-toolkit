# Autonomous Coding Toolkit — Roadmap to Completion

**Date:** 2026-02-23
**Status:** Draft — awaiting user approval
**Scope:** Complete roadmap from current state to v1.0 release, informed by 25 research papers, 20 open bugs, and 3 unexecuted designs

---

## Current State Assessment

### What's Shipped (Production-Quality)

| Category | Count | Notes |
|----------|-------|-------|
| Bash scripts | 34+ | All under 300 lines |
| Test files | 34 | 369+ assertions, all passing |
| Quality gate checks | 7 | lesson-check, lint, tests, ast-grep, memory, test count, git clean |
| Validators | 7 | lessons, skills, commands, plans, prd, plugin, hooks |
| Lessons | 66 | 6 clusters, YAML frontmatter, syntactic + semantic |
| Execution modes | 5 | headless, team, competitive (stub), ralph loop, subagent-driven |
| Skills | 14 | Full pipeline chain + supporting skills |
| Agents | 1 (in-repo) | lesson-scanner; 6 new designed but in ~/.claude/agents/ |
| CI pipeline | `make ci` | lint → validate → test |

### What's Designed But Not Implemented

| Feature | Design Doc | Plan Doc | Batches | Status |
|---------|-----------|---------|---------|--------|
| MAB system | `2026-02-22-mab-run-design.md` | `2026-02-22-mab-run-plan.md` | 6 (26 tasks) | **Needs update** — research found bugs, new prerequisites |
| Agent suite | `2026-02-23-agent-suite-design.md` | `2026-02-23-agent-suite-plan.md` | 7 (23 tasks) | Batch 1 (lint) done; Batches 2-7 pending |
| Research phase | `2026-02-22-research-phase-integration.md` | — | ~2 | Design complete, no plan |
| Roadmap stage | `2026-02-22-research-phase-integration.md` § 3.3 | — | ~1 | Design complete, no plan |

### What's Recommended by Research (No Design Yet)

From the cross-cutting synthesis (25 papers, confidence ratings included):

| # | Item | Evidence | Effort | Confidence |
|---|------|----------|--------|------------|
| 1 | Prompt caching | 83% cost reduction (pricing analysis) | 1-2 days | **High** |
| 2 | Plan quality scorecard | Plan quality worth 3x execution (SWE-bench Pro, N=1865) | 2-3 days | **High** |
| 3 | Spec echo-back gate | Spec misunderstanding is 60%+ of failures (SWE-EVO) | 1-2 days | **Medium-High** |
| 4 | Context restructuring | Lost in the Middle: 20pp accuracy degradation (Liu et al.) | 1 day | **High** |
| 5 | Lesson scope metadata | 67% false positive rate predicted at 100+ lessons | 2-3 days | **High** |
| 6 | Fast lane onboarding | 34.7% abandon on difficult setup (N=202 OSS devs) | 1-2 days | **High** |
| 7 | Per-batch cost tracking | No measured cost data exists — all optimization is guesswork | 1-2 days | **High** |
| 8 | Structured progress.txt | Freeform text reduces cross-context value | 1 day | **Medium-High** |
| 9 | Positive policy system | Positive instructions outperform negative for LLMs (NeQA) | 3-5 days | **Medium-High** |
| 10 | Property-based testing guidance | 50x more mutations found (OOPSLA 2025, 40 projects) | 2-3 days | **High** |

### Open Bugs (20)

| Severity | Count | Issues |
|----------|-------|--------|
| Medium | 7 | #9, #10, #11, #12, #13, #14, #15, #16 |
| Low | 12 | #17-#28 |

Key clusters:
- **Sampling** (#16, #27, #28): stash/state issues in parallel patch sampling
- **Portability** (#17, #18, #23): shebang, grep -P, bash 4.4 compat
- **Edge cases** (#9, #10, #13, #20, #21, #24): empty/missing state, truncation
- **Safety** (#11, #12, #19, #22): path escaping, directory restore, glob fragility

---

## Strategic Priorities

Ordered by impact per effort, accounting for dependencies:

1. **Fix before building** — The 20 open bugs include a state schema mismatch (#10) that affects all headless runs. Fix bugs first.
2. **Pre-execution quality** — Plan quality scorecard, spec echo-back, and context restructuring are the highest-leverage investments per the 3:1 plan-vs-execution ratio.
3. **Cost infrastructure** — Prompt caching (83% savings) and per-batch cost tracking are prerequisites for MAB economics to make sense.
4. **MAB system** — Updated design, slimmed from 6 to 4 batches based on research findings.
5. **Adoption infrastructure** — Fast lane onboarding, lesson scope metadata, README rewrite.
6. **Pipeline extensions** — Research phase, roadmap stage, positive policies.
7. **Agent suite** — New agents are useful but not blocking; they serve Justin's ecosystem, not the public toolkit.

---

## Phased Roadmap

### Phase 1: Stabilize (Fix What's Broken)

**Goal:** Zero known bugs in core pipeline. All existing tests pass. CI green.
**Effort:** 1-2 sessions
**Prerequisite for:** Everything else

#### Batch 1A: Critical Bugs (Medium Severity)

| Issue | Title | Fix |
|-------|-------|-----|
| #9 | `complete_batch` called with batch_num='final' crashes jq | Validate batch_num is numeric before `--argjson` |
| #10 | `get_previous_test_count` returns empty on missing state | Return -1 (unknown), match `extract_test_count` convention |
| #11 | `batch-test.sh` cd without restore | Use subshell `(cd "$dir" && ...)` or pushd/popd |
| #12 | `generate-ast-rules.sh` writes to root when --output-dir omitted | Default to `$PWD/scripts/patterns/` |
| #13 | `entropy-audit.sh` iterates once on empty find | Use `while read` with null check instead of heredoc |
| #16 | SAMPLE_COUNT persists across batches | Reset SAMPLE_COUNT=0 at top of batch loop |

#### Batch 1B: Low Severity Bugs

| Issue | Title | Fix |
|-------|-------|-----|
| #14 | `auto-compound.sh` head -c 40 UTF-8 | Use `cut -c1-40` or `${var:0:40}` |
| #15 | No timeout on routing jq loop | Add `timeout 30` wrapper |
| #17 | Inconsistent shebangs | `#!/usr/bin/env bash` everywhere |
| #18 | `grep -P` non-portable | Replace with `grep -E` or `[[ =~ ]]` |
| #19 | ls -t fragile with spaces | Use `find -printf` or `stat --format` |
| #20 | `free -g` truncates | Use `free -m` and compare against 4096 |
| #21 | check_memory fallback '999' | Return -1 (unknown), skip check |
| #22 | setup-ralph-loop special chars | Quote with `jq --arg` instead of bash substitution |
| #23 | bash < 4.4 empty array set -u | `"${PASS_ARGS[@]+"${PASS_ARGS[@]}"}"` |
| #24 | detect_project_type nullglob | Use `compgen -G` or explicit test |
| #25 | ollama_query no timeout | Add `--connect-timeout 10 --max-time 60` to curl |
| #26 | validate-plans sed range bug | Fix sed address to stop at next `## Batch` header |
| #27 | Sampling stash no-op on clean | Check `git stash list` count before/after |
| #28 | SAMPLE_COUNT reset between batches | Same fix as #16 |

#### Quality Gate
- `make ci` passes
- All 20 issues closed
- No new test regressions

---

### Phase 2: Pre-Execution Quality (Highest Leverage)

**Goal:** Implement the three research-backed improvements that address the 3:1 plan-vs-execution quality ratio.
**Effort:** 1-2 sessions
**Prerequisite for:** Phase 4 (MAB needs better plans to judge)

#### Batch 2A: Context Restructuring

**What:** Restructure `build_batch_prompt()` in `run-plan-prompt.sh`:
1. Raise `TOKEN_BUDGET_CHARS` from 6000 to 10000
2. Place batch task text at the top, requirements/constraints at the bottom
3. Wrap sections in XML tags (`<batch_tasks>`, `<prior_progress>`, `<failure_patterns>`, `<referenced_files>`, `<requirements>`)
4. Add `<research_warnings>` section from research JSON (when present)

**Evidence:** Lost in the Middle effect degrades accuracy 20pp for middle-positioned info. Anthropic's testing shows up to 30% quality improvement with structured context.

**Tests:** Update `test-run-plan-prompt.sh` to verify XML tag presence and section ordering.

#### Batch 2B: Plan Quality Scorecard

**What:** Create `scripts/validate-plan-quality.sh` scoring 8 dimensions:

| Dimension | Check | Weight |
|-----------|-------|--------|
| Task granularity | Each task modifies < 100 lines (estimated) | 15% |
| Spec completeness | Each task has verification command | 20% |
| Single outcome | No mixed task types per batch | 10% |
| Dependency ordering | No forward references | 10% |
| File path specificity | All tasks name exact files | 15% |
| Acceptance criteria | Each batch has at least one assert | 15% |
| Batch size | 1-5 tasks per batch | 10% |
| TDD structure | Test-before-implement pattern | 5% |

Returns score 0-100. Gate execution on configurable minimum (default: 60).

**Integration:** Wire into `run-plan.sh` before batch loop. Add `--skip-plan-quality` override.

**Tests:** Create `test-validate-plan-quality.sh` with sample plans at various quality levels.

#### Batch 2C: Specification Echo-Back Gate

**What:** Before coding each batch, the agent restates what the batch accomplishes. Lightweight LLM comparison between restatement and plan's task description.

**Implementation:** Add `echo_back_check()` to `run-plan-headless.sh`:
1. First 2 lines of `claude -p` prompt: "Before implementing, restate in one paragraph what this batch must accomplish."
2. Extract first paragraph from agent output
3. Lightweight `claude -p` call (haiku): "Does this restatement match the original spec? YES/NO + reason"
4. If NO → retry with clarified prompt (max 1 retry)

**Evidence:** Catches 60%+ of specification misunderstanding failures (SWE-EVO).

**Tests:** Test with intentionally mismatched spec/restatement pairs.

#### Quality Gate
- `make ci` passes
- New validators pass on existing plans
- Context restructuring doesn't break existing test-run-plan-prompt tests

---

### Phase 3: Cost Infrastructure

**Goal:** Enable measured cost data (prerequisite for MAB economics) and implement prompt caching (83% cost reduction).
**Effort:** 1 session
**Prerequisite for:** Phase 4 (MAB)

#### Batch 3A: Per-Batch Cost Tracking

**What:** Track input tokens, output tokens, cache hits, and estimated cost per batch in `.run-plan-state.json`.

**Implementation:**
1. Parse `claude -p` stderr for token usage (Claude CLI outputs this)
2. Add `costs` object to state: `{"batch_N": {"input_tokens": N, "output_tokens": N, "cache_hits": N, "estimated_cost_usd": N}}`
3. Add `--show-costs` flag to `pipeline-status.sh`
4. Update `run-plan-notify.sh` to include cost in Telegram notifications

**Tests:** Mock claude -p output with token counts, verify state updates.

#### Batch 3B: Prompt Caching Structure

**What:** Structure prompts with stable prefix (CLAUDE.md chain, skills, lessons — rarely changes) and variable suffix (batch tasks, context — changes each batch). This enables Anthropic's prompt caching to reuse the prefix across batches.

**Implementation:**
1. In `build_batch_prompt()`, separate `STABLE_PREFIX` (CLAUDE.md, lessons, conventions) from `VARIABLE_SUFFIX` (batch tasks, context, progress)
2. Write stable prefix to a file that `claude -p` reads via `--system-prompt-file` (if supported) or prepend it with a clear separator
3. Track cache hit rate in state file

**Evidence:** 83% cost reduction modeled (pricing analysis + cache priming). A 6-batch feature drops from $6.50 to $1.76.

**Tests:** Verify prompt structure separates stable/variable. Verify state tracks cache metrics.

#### Batch 3C: Structured progress.txt

**What:** Replace freeform `progress.txt` with defined sections:

```
## Batch N: <title>
### Files Modified
- path/to/file (created|modified|deleted)

### Decisions
- <decision>: <rationale>

### Issues Encountered
- <issue> → <resolution>

### State
- Tests: N passing
- Duration: Ns
- Cost: $N.NN
```

**Tests:** Update `test-run-plan-context.sh` to verify structured parsing.

#### Quality Gate
- `make ci` passes
- Cost tracking produces data on a real 2+ batch run
- Structured progress.txt parses correctly

---

### Phase 4: Multi-Armed Bandit System (Updated)

**Goal:** Implement competing agents with LLM judge, informed by research findings.
**Effort:** 2-3 sessions
**Prerequisites:** Phase 1 (bug fixes), Phase 3 (cost tracking, caching)

#### Changes from Original Plan

The original 6-batch plan needs revision based on research findings:

| Original | Change | Reason |
|----------|--------|--------|
| LLM planner agent | Replace with Thompson Sampling | Research: Thompson Sampling is cheaper and better calibrated than LLM routing (MAB R1) |
| 6 batches, 26 tasks | Slim to 4 batches, ~18 tasks | Research: 80% infrastructure exists; prompts are just files; planner is now a function |
| Judge trusts automated routing | Add human calibration for first 10 decisions | Research: LLM-as-Judge reliability unvalidated (cross-cutting synthesis §F) |
| Default competitive mode | Selective MAB (~30% of batches) | Research: Cost break-even only if prevents 1 debugging batch per 2 features |
| `{AB_LESSONS}` placeholder | Fix to `{MAB_LESSONS}` | Bug in original plan: placeholder name doesn't match data file name |

#### Batch 4A: Foundation (Prompts + Architecture Map + Data Init)

Matches original Batch 1 but simplified:

1. Create 4 prompt files in `scripts/prompts/` (agent-a, agent-b, judge-agent, planner-agent)
2. Create `scripts/architecture-map.sh` (scans source for import/source dependencies)
3. Tests for architecture-map.sh
4. Create `scripts/lib/thompson-sampling.sh` — Beta distribution sampling for strategy routing:
   - `thompson_sample(wins, losses)` → returns sampled value (0-1)
   - `thompson_route(batch_type, strategy_perf_file)` → returns "superpowers" or "ralph" or "mab"
   - Pure bash using `bc` for floating point
5. Tests for thompson-sampling.sh

#### Batch 4B: MAB Orchestrator (mab-run.sh)

Core orchestrator, simplified from original Batch 2:

1. `scripts/mab-run.sh` — argument parsing, data init, worktree management, prompt assembly
2. Agent execution (parallel `claude -p` in separate worktrees)
3. Quality gate on both agents
4. Judge invocation (separate `claude -p` with read-only tools)
5. Winner selection (gate override: if only one passes, that one wins regardless of judge)
6. Data updates (strategy-perf.json, mab-lessons.json, mab-run-<ts>.json)
7. Human calibration mode: for first 10 decisions, present judge verdict to user for approval before merge
8. Cleanup (worktree removal)
9. Tests for mab-run.sh (dry-run, data init, argument validation)

#### Batch 4C: Integration (run-plan --mab + context injection)

Wire into existing pipeline:

1. Add `--mab` flag to `run-plan.sh`
2. Inject MAB lessons into per-batch context (`run-plan-context.sh`)
3. Add Thompson Sampling routing call before batch execution (when `--mab` is set)
4. Update `pipeline-status.sh` with MAB section
5. Tests for CLI flags and context injection

#### Batch 4D: Community Sync + Lesson Promotion + Docs

1. `scripts/pull-community-lessons.sh` — fetch lessons from upstream
2. `scripts/promote-mab-lessons.sh` — auto-promote patterns with 3+ occurrences
3. Update `docs/ARCHITECTURE.md` with MAB section
4. Update `CLAUDE.md` with MAB capabilities
5. Tests for both scripts
6. Run full `make ci`

#### Quality Gate
- `make ci` passes
- `mab-run.sh --dry-run` works end-to-end
- `architecture-map.sh` produces valid JSON on the toolkit itself
- Thompson sampling unit tests pass
- All 20+ previous bugs still fixed

---

### Phase 5: Adoption & Polish

**Goal:** Make the toolkit usable by someone who isn't Justin.
**Effort:** 1-2 sessions
**Prerequisites:** Phase 2 (plan quality), Phase 4 (MAB)

#### Batch 5A: Lesson Scope Metadata

**What:** Add `scope` field to lesson YAML frontmatter:

```yaml
scope: universal | language:python | language:bash | framework:pytest | domain:ha-aria | project-specific
```

Update `lesson-check.sh` to:
1. Detect project languages from file extensions
2. Skip lessons whose scope doesn't match the project
3. Add `--all-scopes` flag to override filtering

Update all 66 existing lessons with appropriate scope tags.

**Evidence:** Without scope, false positive rate hits 67% at ~100 lessons (Zimmermann, 622 predictions).

#### Batch 5B: Fast Lane Onboarding

**What:**
1. Create `examples/quickstart-plan.md` — a 2-batch plan that reaches first quality-gated execution in 3 commands
2. Rewrite `README.md` to under 100 lines with progressive disclosure
3. Add `Getting Started in 5 Minutes` section with:
   ```bash
   git clone ... && cd autonomous-coding-toolkit
   ./scripts/run-plan.sh examples/quickstart-plan.md --project-root /tmp/quickstart-demo
   # Watch: batch execution → quality gate → test count → DONE
   ```
4. Move detailed docs to `docs/` (ARCHITECTURE.md already there)

**Evidence:** 34.7% abandon on difficult setup.

#### Batch 5C: Expand Lessons to 6 Clusters

Add 12 starter lessons for the three new clusters:

- **Cluster D (Specification Drift):** 4 lessons — agent misinterprets requirements, builds wrong thing correctly
- **Cluster E (Context & Retrieval):** 4 lessons — wrong files read, stale context, lost information
- **Cluster F (Planning & Control Flow):** 4 lessons — wrong decomposition, dependency errors, scope creep

Update `docs/lessons/SUMMARY.md` with new clusters.

#### Quality Gate
- `make ci` passes
- Quickstart demo runs end-to-end in < 5 minutes
- Lesson scope filtering reduces false matches on non-Python projects

---

### Phase 6: Pipeline Extensions

**Goal:** Add research phase and roadmap stage to the pipeline.
**Effort:** 2-3 sessions
**Prerequisites:** Phase 2 (context restructuring), Phase 5 (lesson scope)

#### Batch 6A: Research Phase (Stage 1.5)

Per the design in `2026-02-22-research-phase-integration.md`:

1. Create `skills/research/SKILL.md` — 10-step research protocol
2. Create `scripts/research-gate.sh` — blocks PRD if blocking issues unresolved
3. Update `scripts/lib/run-plan-context.sh` — inject research warnings
4. Update `scripts/auto-compound.sh` — replace Step 2.5 with research phase
5. Update `skills/autocode/SKILL.md` — add Stage 1.5
6. Tests for research-gate.sh

Artifacts produced:
- `tasks/research-<slug>.md` — human-readable report
- `tasks/research-<slug>.json` — machine-readable for PRD scoping

#### Batch 6B: Roadmap Stage (Stage 0.5)

1. Create `skills/roadmap/SKILL.md` — multi-feature sequencing
2. Update `skills/autocode/SKILL.md` — add Stage 0.5
3. Create `examples/example-roadmap.md` — sample roadmap

#### Batch 6C: Positive Policy System

1. Create `policies/` directory with `universal.md`, `python.md`, `bash.md`, `testing.md`
2. Add `positive_alternative` field to lesson YAML template
3. Create `scripts/policy-check.sh` — audit mode (advisory, not blocking)
4. Update `lesson-check.sh` to read positive alternatives and include in violation messages
5. Tests for policy-check.sh

**Evidence:** Positive instructions outperform negative for LLMs (NeQA benchmark, Pink Elephant Problem).

#### Quality Gate
- `make ci` passes
- Research gate blocks on a test file with blocking issues
- Roadmap skill produces valid artifact
- Policy check runs without errors on toolkit itself

---

### Phase 7: Agent Suite

**Goal:** Ship the 6 new agents and 8 existing agent improvements.
**Effort:** 1-2 sessions
**Prerequisites:** Phase 1 (bugs), Phase 2 (lesson-scanner scan groups reference updated lessons)

Per the design in `2026-02-23-agent-suite-design.md`:

#### Batch 7A: New Agents (6)

All placed in `~/.claude/agents/` (global) AND `agents/` (toolkit repo):

1. `bash-expert.md` — review/write/debug bash scripts
2. `shell-expert.md` — diagnose systemd/PATH/permissions issues
3. `python-expert.md` — async discipline, resource lifecycle, type safety
4. `integration-tester.md` — verify cross-service data flows
5. `dependency-auditor.md` — CVE/outdated/license scanning (read-only)
6. `service-monitor.md` — service/timer health auditing

#### Batch 7B: Existing Agent Improvements

P0 (correctness): security-reviewer tools/categories, infra-auditor freshness, lesson-scanner count
P1 (quality): model/maxTurns on all agents, doc-updater git diff
P2 (capability): lesson-scanner scan groups, notion fallbacks
P3 (polish): doc-updater output, counter-daily scope rule

#### Quality Gate
- All 14 agents have valid frontmatter (name, model, tools, maxTurns)
- `make ci` passes
- No agent references nonexistent tools

---

## Dependency Graph

```
Phase 1: Stabilize (bug fixes)
    │
    ├──► Phase 2: Pre-Execution Quality
    │        │
    │        ├──► Phase 4: MAB System ◄── Phase 3: Cost Infrastructure
    │        │        │
    │        │        ├──► Phase 5: Adoption & Polish
    │        │        │
    │        │        └──► Phase 6: Pipeline Extensions
    │        │
    │        └──► Phase 6: Pipeline Extensions
    │
    └──► Phase 7: Agent Suite (independent, can run in parallel with 2-6)
```

**Critical path:** 1 → 2 → 3 → 4 → 5
**Parallel track:** 7 can run anytime after Phase 1

---

## Effort Summary

| Phase | Batches | Estimated Sessions | Key Deliverable |
|-------|---------|-------------------|-----------------|
| 1: Stabilize | 2 | 1-2 | 20 bugs fixed, CI green |
| 2: Pre-Execution Quality | 3 | 1-2 | Plan scorecard, echo-back gate, context restructuring |
| 3: Cost Infrastructure | 3 | 1 | Cost tracking, prompt caching, structured progress |
| 4: MAB System | 4 | 2-3 | Competing agents, judge, Thompson Sampling, lesson promotion |
| 5: Adoption & Polish | 3 | 1-2 | Scope metadata, fast lane, 6 clusters |
| 6: Pipeline Extensions | 3 | 2-3 | Research phase, roadmap stage, positive policies |
| 7: Agent Suite | 2 | 1-2 | 6 new agents, 8 improvements |
| **Total** | **20** | **9-15** | **v1.0** |

---

## What "v1.0" Means

The toolkit reaches v1.0 when:

1. **Core pipeline works end-to-end** for headless, ralph loop, and MAB modes ✓ (mostly done)
2. **Quality gates catch real bugs** with < 20% false positive rate (needs scope metadata)
3. **Cost is tracked and optimized** (prompt caching, per-batch cost data)
4. **A new user can start in < 5 minutes** (fast lane onboarding)
5. **MAB produces measurable learning** (strategy-perf.json with 10+ data points, human-calibrated judge)
6. **Research phase produces durable artifacts** (not ephemeral conversation)
7. **Zero known bugs in core pipeline** (all 20 issues closed)
8. **Documentation is complete** — ARCHITECTURE.md, README, CONTRIBUTING, examples

### What's NOT in v1.0

- Multi-language support beyond Python/bash (deferred — no evidence of demand)
- CI/CD integration (GitHub Actions workflow exists but not tested across repos)
- Web dashboard (pipeline-status.sh is CLI-only)
- Pinecone-backed lesson dedup (only needed at 100+ lessons)
- Agent chains (post-commit audit, service triage, pre-release)
- Property-based testing integration (guidance only, no automation)

---

## Lean Gate

**Hypothesis:** A structured autonomous coding pipeline with quality gates and competing agents produces higher-quality code with fewer debugging cycles than manual Claude Code usage.

**MVP:** Phases 1-4 (stabilize + pre-execution quality + cost + MAB). Everything after is optimization.

**First 5 users:** Justin (primary), then 4 Claude Code power users from GitHub/Discord who have expressed interest in autonomous execution.

**Success metric:** Measured reduction in debugging batches per feature (target: < 1 retry per 5-batch feature, vs current ~2-3).

**Pivot trigger:** If MAB shows no win-rate differentiation after 20 features (10 per strategy), downgrade to single-strategy with the lessons system only.

---

## Next Action

Start with **Phase 1, Batch 1A** — fix the 7 medium-severity bugs. These affect core functionality (state management, batch execution, sampling) and must be fixed before any new features are built on top.
