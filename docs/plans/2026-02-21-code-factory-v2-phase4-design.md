# Code Factory v2 Phase 4 — Design Document

**Date:** 2026-02-21
**Status:** Approved
**Approach:** Fixes-First, Then Features (Batch 1 → 2 → 3 → 4 → 5, sequential)
**Prior work:** `docs/plans/2026-02-21-code-factory-v2-design.md` (Phases 1-3 complete, Phase 4 partial)

## Problem Statement

Phase 4 of Code Factory v2 has 4 remaining design tasks (4.2, 4.4, 4.5, 4.6) plus 2 quick fixes and 43 new lessons discovered during v2 execution. The existing 6 lesson files in the toolkit are a fraction of the 53 lessons accumulated across projects. This plan completes Phase 4 and brings all generalizable lessons into the public toolkit.

## What's Already Done (Phases 1-3 + partial Phase 4)

- Shared libraries: common.sh, ollama.sh, telegram.sh, run-plan-headless.sh
- Quality gates: lesson-check + lint (ruff/eslint) + tests + license-check + memory
- Prior-art search (text-based), pipeline-status, failure-digest, context_refs
- 19 test files, 224 assertions, all scripts under 300 lines

## Batch 1: Quick Fixes + All Lessons

### Fix 1: Empty Batch Detection

In `run-plan-headless.sh` line 37, the batch loop iterates `START_BATCH` to `END_BATCH` without checking if the batch has content. The parser found 9 batches for a 7-batch plan, burning 2 API calls on empty batches (~50s wasted).

**Fix:** After `get_batch_title`, call `get_batch_text` and skip if empty:

```bash
local batch_text
batch_text=$(get_batch_text "$PLAN_FILE" "$batch")
if [[ -z "$batch_text" ]]; then
    echo "  (empty batch -- skipping)"
    continue
fi
```

### Fix 2: Bash Test Suite Detection

`quality-gate.sh` detects pytest/npm/make but not bash test suites. For this repo, quality gates between batches reported "No test suite detected -- skipped" while 224 assertions existed.

**Fix:** Add `bash` case to `detect_project_type()` in `common.sh` when `scripts/tests/run-all-tests.sh` or a `test-*.sh` glob exists. Add corresponding `bash)` case in quality-gate.sh's test suite section.

### Lessons: 43 New Files (0007-0049)

Port all generalizable lessons from the Documents workspace (53 total - 6 already in toolkit - 11 too project-specific = 36 to port) plus 7 new lessons from v2 execution.

**Generalization rules:**
- No project names (no ARIA, HA, Telegram, etc.)
- No specific IPs, hostnames, or usernames
- No internal API references — use generic equivalents
- Focus on the universal anti-pattern, not the specific bug

**Lesson mapping (new ID → source → generalized title):**

| New ID | Source | Title | Type | Severity | Category |
|--------|--------|-------|------|----------|----------|
| 0007 | v2 | Runner state file rejected by own git-clean check | syntactic | should-fix | integration-boundaries |
| 0008 | v2 | Quality gate blind spot for non-standard test suites | semantic | should-fix | silent-failures |
| 0009 | v2 | Plan parser over-count burns empty API calls | semantic | should-fix | silent-failures |
| 0010 | v2 | `local` outside function silently misbehaves in bash | syntactic | blocker | silent-failures |
| 0011 | v2 | Batch execution writes tests for unimplemented code | semantic | should-fix | integration-boundaries |
| 0012 | v2 | API rejects markdown with unescaped special chars | semantic | nice-to-have | integration-boundaries |
| 0013 | v2 | `export` prefix in env files breaks naive parsing | syntactic | should-fix | silent-failures |
| 0014 | #2 | Decorator registries are import-time side effects | semantic | should-fix | silent-failures |
| 0015 | #4 | Frontend-backend schema drift invisible until e2e trace | semantic | should-fix | integration-boundaries |
| 0016 | #5 | Event-driven systems must seed current state on startup | semantic | should-fix | integration-boundaries |
| 0017 | #6 | Copy-pasted logic between modules diverges silently | semantic | should-fix | integration-boundaries |
| 0018 | #8 | Every layer passes its test while full pipeline is broken | semantic | should-fix | integration-boundaries |
| 0019 | #9 | systemd EnvironmentFile ignores `export` keyword | syntactic | should-fix | silent-failures |
| 0020 | #10 | Persist state incrementally before expensive work | semantic | should-fix | silent-failures |
| 0021 | #11 | Dual-axis testing: horizontal sweep + vertical trace | semantic | lesson-learned | integration-boundaries |
| 0022 | #13 | Build tool JSX factory shadowed by arrow params | syntactic | blocker | silent-failures |
| 0023 | #14 | Static analysis spiral -- chasing lint fixes creates more bugs | semantic | should-fix | test-anti-patterns |
| 0024 | #15 | Shared pipeline features must share implementation | semantic | should-fix | integration-boundaries |
| 0025 | #16 | Defense-in-depth: validate at all entry points | semantic | lesson-learned | integration-boundaries |
| 0026 | #17 | Linter with no rules enabled = false enforcement | semantic | should-fix | silent-failures |
| 0027 | #18 | JSX silently drops wrong prop names | syntactic | should-fix | silent-failures |
| 0028 | #20 | Never embed infrastructure details in client-side code | syntactic | blocker | silent-failures |
| 0029 | #21 | Never write secret values into committed files | syntactic | blocker | silent-failures |
| 0030 | #22 | Cache/registry updates must merge, never replace | semantic | should-fix | integration-boundaries |
| 0031 | #26 | Verify units at every boundary (0-1 vs 0-100) | semantic | should-fix | integration-boundaries |
| 0032 | #28 | Module lifecycle: subscribe after init gate, unsubscribe on shutdown | semantic | should-fix | resource-lifecycle |
| 0033 | #29 | Async iteration over mutable collections needs snapshot | syntactic | blocker | async-traps |
| 0034 | #30 | Caller-side missing await silently discards work | semantic | blocker | async-traps |
| 0035 | #31 | Duplicate registration IDs cause silent overwrite | semantic | should-fix | silent-failures |
| 0036 | #34 | WebSocket dirty disconnects raise RuntimeError, not close | semantic | should-fix | resource-lifecycle |
| 0037 | #36 | Parallel agents sharing worktree corrupt staging area | semantic | blocker | integration-boundaries |
| 0038 | #37 | Subscribe without stored ref = cannot unsubscribe | syntactic | should-fix | resource-lifecycle |
| 0039 | #38 | Fallback `or default()` hides initialization bugs | semantic | should-fix | silent-failures |
| 0040 | #39 | Process all events when 5% are relevant -- filter first | semantic | should-fix | performance |
| 0041 | #40 | Ambiguous base dir variable causes path double-nesting | semantic | should-fix | integration-boundaries |
| 0042 | #42 | Spec compliance without quality review misses defensive gaps | semantic | should-fix | integration-boundaries |
| 0043 | #44 | Exact count assertions on extensible collections break on addition | syntactic | should-fix | test-anti-patterns |
| 0044 | #46 | Relative `file:` deps break in git worktrees | semantic | should-fix | integration-boundaries |
| 0045 | #49 | Iterative "how would you improve" catches 35% more design gaps | semantic | lesson-learned | integration-boundaries |
| 0046 | #50 | Plan-specified test assertions can have math bugs | semantic | should-fix | test-anti-patterns |
| 0047 | #52 | pytest runs single-threaded by default -- add xdist | semantic | should-fix | performance |
| 0048 | #53 | Multi-batch plans need explicit integration wiring batch | semantic | lesson-learned | integration-boundaries |
| 0049 | #56 | A/B verification finds zero-overlap bug classes | semantic | lesson-learned | integration-boundaries |

**SUMMARY.md:** Generalized version of the Documents workspace summary with:
- Quick reference table (all 49 lessons)
- Three root cause clusters (Silent Failures, Integration Boundaries, Cold-Start)
- Six rules to build by
- Diagnostic shortcuts table
- No project-specific references

All lesson files follow the toolkit's YAML frontmatter schema (see `docs/lessons/TEMPLATE.md`).

## Batch 2: Per-Batch Context Assembler

**Goal:** Minimize the context gap between a fresh batch agent and an experienced one. Each agent gets exactly the context it needs within a token budget -- directives, not just facts.

### Architecture

A `generate_batch_context()` function in `scripts/lib/run-plan-context.sh` that:

1. **Reads all context sources:** state file, progress.txt, git log, context_refs, failure-patterns.json
2. **Scores by relevance:** recency (recent batches score higher) + direct dependency (context_refs from this batch score highest) + failure history (if this batch type failed before, that scores high)
3. **Assembles within token budget:** ~1500 tokens target. Priority order: directives > failure history > context_refs contents > git log > progress.txt
4. **Outputs directives:** "Don't repeat X", "Read Y before modifying", "Quality gate expects N+ tests"
5. **Writes to CLAUDE.md:** Appends `## Run-Plan: Batch N` section (overwritten per batch, not accumulated)

### Context Sources (priority order)

1. **Failure patterns** (highest) — from `logs/failure-patterns.json`, cross-run learning
2. **Context_refs file contents** — first 100 lines of files declared in batch header
3. **Prior batch quality gate results** — test count, pass/fail, duration
4. **Git log** — last 5 commits from prior batches
5. **Progress.txt** — last 20 lines of discoveries/decisions
6. **Directives** — synthesized from above: "tests must stay above 224", "these files were modified by batch 2"

### Cross-Run Failure Patterns

`logs/failure-patterns.json` persists across runs:

```json
[
  {
    "batch_title_pattern": "integration wiring",
    "failure_type": "missing import",
    "frequency": 3,
    "last_seen": "2026-02-21",
    "winning_fix": "check all imports before running tests"
  }
]
```

When a batch title fuzzy-matches a pattern, the relevant warning is injected into context.

### Token Budget

- Budget: ~1500 tokens (~6000 chars)
- If assembled context exceeds budget, trim lowest-priority items first
- Always include: directives (mandatory), failure patterns (if matched), quality gate expectations
- Trim first: progress.txt, git log, context_refs file contents (truncate to first 50 lines)

## Batch 3: ast-grep Integration

**Goal:** Help agents write code that fits the existing codebase and catch semantic anti-patterns that grep cannot detect. Two modes: discovery (before PRD) and enforcement (in quality gate).

### Discovery Mode (prior-art-search.sh)

Run `ast-grep` once at plan start to extract the dominant codebase patterns:

- Error handling style (try/except with logging vs bare except)
- Test patterns (assert helpers, fixture usage, naming conventions)
- Function size distribution
- Import patterns

Results feed into the context assembler (Batch 2) as "Codebase style: [patterns]" — every batch agent writes code that fits without being told to.

### Enforcement Mode (quality-gate.sh)

Optional quality gate step that runs ast-grep rules derived from lesson files:

- Read lesson YAML where `pattern.type: semantic` and language has ast-grep support
- Auto-generate ast-grep rule files from lesson descriptions
- Run against changed files in the batch
- Warn (not fail) by default — `--strict-ast` to make it a hard gate

### Auto-Generated Rules from Lessons

Lessons with `pattern.type: semantic` that describe structural patterns (e.g., "async def body has no await") can be converted to ast-grep YAML rules. A `scripts/generate-ast-rules.sh` script reads lesson files and produces `scripts/patterns/*.yml`.

Not all semantic lessons can be converted — some require true AI understanding. The script attempts conversion and logs which lessons it could/couldn't handle.

### Built-in Pattern Files

5-10 patterns in `scripts/patterns/` for common structural anti-patterns:

```
scripts/patterns/
  retry-loop.yml          — retry without backoff
  bare-except.yml         — except without specific exception
  async-no-await.yml      — async def with no await in body
  empty-catch.yml         — catch block with no logging
  unused-import.yml       — imported but never referenced
```

### Graceful Degradation

If `ast-grep` is not installed:
- Discovery mode: skip with note ("install ast-grep for structural analysis")
- Enforcement mode: skip silently (grep-based lesson-check.sh still runs)
- No hard dependency — ast-grep enhances but is not required

## Batch 4: Team Mode with Decision Gate

**Goal:** Reduce total wall-clock time for plan execution while maintaining quality. Automatically select the optimal execution mode based on plan analysis.

### Decision Gate

Before any execution starts, `run-plan.sh` analyzes the plan and selects a mode:

```
run-plan.sh <plan>
    |
    v
analyze_plan_for_mode()
    |-- Parse all batches: Files, context_refs, depends_on
    |-- Build file-level dependency graph
    |-- Compute parallelism score (0-100)
    |-- Check: AGENT_TEAMS flag available?
    |-- Check: available memory vs worker count
    |
    v
Decision:
    score < 20  --> HEADLESS (sequential is optimal)
    score 20-60 --> HEADLESS with advisory ("team mode would save ~Xmin")
    score > 60 + teams available + memory OK --> TEAM (parallel)
    score > 60 + teams unavailable --> HEADLESS with note
    any + --mode override --> use override
```

### Parallelism Score Factors

- % of batches with zero file overlap with neighbors (+)
- Number of batches in first parallel group (+)
- Total file overlap across all batch pairs (-)
- Shared runtime hints: "starts server", "modifies DB" (-)
- Explicit `parallel_safe: true` in plan header (+20 bonus)

### Routing Plan (always shown)

```
=== Execution Mode Analysis ===

Plan: implementation-plan.md
Batches: 7 | Files touched: 31 | Avg overlap: 12%

Dependency graph:
  B1 --> B2 --> B3
  B1 --> B4 --> B5 --> B7
             B6 -------> B7

Parallelism score: 72/100
  + 3 independent groups detected
  + Max parallel width: 3 (B3, B5, B6)
  + File overlap < 20% in parallel groups
  - B2->B3 share 2 files (conservative: sequential)

Recommendation: TEAM MODE
  Workers: 2 (21G available, 8G/worker threshold)
  Est. wall time: 14min (vs 28min sequential)
  Est. cost: $2.40 (vs $3.10 sequential)

Model routing:
  B1: sonnet  (implementation -- creates 4 files)
  B2: sonnet  (implementation -- modifies 3 files, adds tests)
  B3: haiku   (verification -- 0 creates, 5 run commands) [auto-escalate]
  B4: sonnet  (implementation -- creates 2 files)
  B5: sonnet  (implementation -- modifies + tests)
  B6: haiku   (wiring -- 0 new logic) [auto-escalate]
  B7: haiku   (verification -- pipeline trace only) [auto-escalate]

Speculative execution:
  B2 starts while B1 gate runs (overlap: 0%)
  B5 waits for B4 gate (overlap: 73%)
```

### Auto-Detect Parallelism

Build dependency graph from plan content — no `depends_on:` annotations required:

- `context_refs` in batch headers declare which files a batch reads from prior batches
- `Files:` sections declare which files a batch creates/modifies
- If batch B's context_refs don't include any of batch A's output files, they're independent
- Fall back to sequential when analysis is ambiguous

Existing plans work in team mode with zero changes.

### Team Execution Architecture

- **Team lead:** owns task list, quality gates, merge queue
- **N workers:** each gets isolated git worktree, claims batches, executes
- **Progressive merge queue:** each batch merges to main immediately after gate pass (keeps divergence small)
- **Speculative execution:** start next batch while gate runs when file overlap < threshold. Abort speculation if gate fails.
- **Model routing with auto-escalation:** haiku batches that fail retry on sonnet, sonnet failures escalate to opus

### Routing Configuration (`scripts/lib/run-plan-routing.sh`)

```bash
# Parallelism thresholds
PARALLEL_SCORE_THRESHOLD=60      # min score for team mode recommendation
SPECULATE_MAX_OVERLAP=20         # max file overlap % for speculative execution

# Model routing (batch classification --> model)
MODEL_IMPLEMENTATION="sonnet"    # creates/modifies code files
MODEL_VERIFICATION="haiku"       # only run/verify commands
MODEL_ARCHITECTURE="opus"        # "design" or "architecture" in title
MODEL_ESCALATE_ON_FAIL=true      # haiku-->sonnet-->opus on retry

# Resource limits
WORKER_MEM_THRESHOLD_GB=8        # min GB available per worker
MAX_WORKERS=3                    # hard cap regardless of memory
```

### Override Escape Hatches

- `--mode headless` — force sequential regardless of score
- `--mode team` — force team regardless of score
- `--workers N` — override worker count
- `--model-override B3=opus` — force specific model for a batch
- `--no-speculate` — disable speculative execution
- `--sequential-after B4` — parallel until B4, then sequential

### Decision Log (`logs/routing-decisions.log`)

Every decision logged with timestamp and reasoning:

```
[12:03:14] MODE: team (score=72, threshold=60)
[12:03:14] PARALLEL: B2,B4 -- overlap=0 files, both depend only on B1
[12:03:14] MODEL: B3-->haiku -- 0 create/modify, 5 run commands, confidence=85%
[12:05:22] SPECULATE: B3 starting while B2 gate runs -- overlap 0%
[12:05:45] GATE_PASS: B2 (224-->231 tests), merging worktree
[12:05:48] MERGE: B2 --> main, 3 files, 0 conflicts
[12:06:01] SPECULATE_OK: B3 confirmed
[12:08:30] ESCALATE: B6 failed on haiku, retrying on sonnet
```

### Where Team Mode Falls Back to Headless

- Parallelism score < 60 (tightly coupled batches)
- Shared runtime state detected (service ports, DB migrations)
- Plan is concern-batched (all impl then all tests)
- Available memory < 2 x worker threshold
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` flag not set

### Integration with pipeline-status.sh

After execution, pipeline-status.sh shows routing decisions alongside results:

```
Batch 3: haiku --> PASSED (22s, 8 tests added)
Batch 4: sonnet --> PASSED (180s, 15 tests added)
Batch 6: haiku-->sonnet (escalated) --> PASSED (45s, 3 tests added)
Total: 14min wall, $2.38 cost, 2 workers
```

### Writing-Plans Integration

The writing-plans skill should assess parallelism when creating plans:
- Add `parallel_safe: true/false` to plan header
- Add `depends_on: [batch-N]` hints to batch headers when dependencies exist
- Design batches for independence when possible (different files per batch)

## Batch 5: Parallel Patch Sampling

**Goal:** Maximize the probability that a batch succeeds, especially for hard batches. Improve success probability over time through outcome learning.

### When Sampling Triggers

Not every batch — only when:
- Batch marked `critical: true` in plan header
- Batch failed its first attempt (sampling replaces naive retry)
- User passes `--sample N` flag explicitly

### Tournament Architecture

```
Batch fails first attempt (or marked critical)
    |
    v
Round 1: N candidates in parallel (default: 3)
    |-- Candidate 1: vanilla prompt
    |-- Candidate 2: prompt + failure digest + "try a different approach"
    |-- Candidate 3: prompt + failure digest + "minimal change only"
    |
    Each in isolated worktree
    |
    v
Score each candidate:
    |-- Quality gate pass/fail (mandatory -- eliminates failures)
    |-- Test count (more = better)
    |-- Diff size (smaller = better among passers)
    |-- Lint warnings (fewer = better)
    |-- Lesson-check violations (penalty: -200 each)
    |-- ast-grep violations (penalty: -100 each)
    |
    v
Decision:
    Clear winner (1 passes, others don't) --> use it
    Multiple passers --> highest score wins
    No winner OR close scores --> Round 2: Synthesis
    |
    v
Round 2: Synthesis agent
    Reads: all N attempts + their gate results + their diffs
    Task: "Candidate 1 had best architecture but failed test X.
           Candidate 3 passed but duplicated 40 lines.
           Synthesize: use C1's approach, fix using C3's insight."
    |
    v
Score synthesis --> if passes, use it. If not, best Round 1 winner.
```

### Scoring Function

```bash
score_candidate() {
    local gate_passed="$1"     # 0 or 1
    local test_count="$2"      # integer
    local diff_lines="$3"      # integer
    local lint_warnings="$4"   # integer
    local lesson_violations="$5"  # integer
    local ast_violations="$6"     # integer

    # Gate pass is mandatory
    if [[ "$gate_passed" -ne 1 ]]; then
        echo 0; return
    fi

    # Weighted score: tests most important, quality penalties heavy
    local score=$(( (test_count * 10) + (10000 / (diff_lines + 1)) + (1000 / (lint_warnings + 1)) - (lesson_violations * 200) - (ast_violations * 100) ))
    echo "$score"
}
```

### Prompt Diversity: Batch-Type-Aware + Learned

**Batch type classification** from plan content:

| Batch type | Likely failure | Best prompt variants |
|------------|---------------|---------------------|
| New file creation | Missing imports, incomplete API | vanilla, "check all imports", "write tests first" |
| Refactoring | Breaking existing tests | vanilla, "minimal change", "run tests after each edit" |
| Integration wiring | Missing connections | vanilla, "trace end-to-end", "check every import/export" |
| Test-only | Flaky assertions, wrong mocks | vanilla, "use real objects not mocks", "edge cases only" |

**Learned from outcomes** (`logs/sampling-outcomes.json`):

```json
[
  {
    "batch_type": "refactoring",
    "prompt_variant": "minimal-change",
    "won": true,
    "score": 2450,
    "timestamp": "2026-02-21T12:05:00Z"
  }
]
```

Over 10+ runs, patterns emerge. Candidate slot allocation:
- 1 slot always vanilla (baseline)
- Remaining slots allocated to historically winning variants for this batch type
- 1 slot always experimental (random variant for exploration)

This is a simple multi-armed bandit: exploit what works, explore 1 slot.

### Integration with Team Mode

- In headless mode: candidates run sequentially (N claude -p calls)
- In team mode: candidates run as parallel workers on same batch (natural fit)
- Decision gate factors this in: worker count = sample count for sampled batches

### Resource Guards

- Memory: don't sample if available memory < N x 4G
- Cost: log estimated cost in routing plan ("Sampling B4: ~$1.20 for 3 candidates vs $0.40 single")
- Time: sampling adds ~50% wall time per batch (parallel) or Nx (sequential)

### Configuration

```bash
# In run-plan-routing.sh
SAMPLE_ON_RETRY=true             # auto-sample when batch fails first attempt
SAMPLE_ON_CRITICAL=true          # auto-sample for critical: true batches
SAMPLE_COUNT=3                   # default candidate count
SAMPLE_MAX_COUNT=5               # hard cap
SAMPLE_MIN_MEMORY_PER_GB=4       # per-candidate memory requirement
```

### Override Flags

- `--sample N` — force sampling for all batches with N candidates
- `--sample-batch B4=5` — sample only batch 4 with 5 candidates
- `--no-sample` — disable all sampling

## Dependencies

- **Batch 1** has no dependencies (fixes + lesson files)
- **Batch 2** depends on Batch 1 (failure patterns reference lesson IDs)
- **Batch 3** depends on Batch 2 (ast-grep feeds into context assembler) + optional install: `ast-grep`
- **Batch 4** depends on Batch 2 (context assembler) + Batch 3 (ast-grep scoring) + requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- **Batch 5** depends on Batch 4 (team mode for parallel candidates) + Batch 3 (ast-grep in scoring)

## Success Metrics

1. All 49 lessons in toolkit with YAML frontmatter, no project-specific references
2. Empty batches detected and skipped (0 wasted API calls)
3. Bash test suites detected by quality gate
4. Context assembler reduces agent "discovery" time (measurable via batch duration comparison)
5. ast-grep catches at least 3 anti-patterns that grep cannot
6. Team mode parallelism score correctly predicts speedup within 20%
7. Patch sampling improves retry success rate vs naive retry (track in sampling-outcomes.json)

## Risk Mitigations

- **Lesson volume:** 43 new files is mechanical work — each follows the template. Use subagents for parallel writing.
- **ast-grep availability:** All ast-grep features fail-open. The toolkit works without it installed.
- **Agent teams instability:** Team mode falls back to headless. Decision gate prevents team mode when conditions aren't right.
- **Sampling cost:** Resource guards prevent sampling when memory is low. Cost shown in routing plan before execution.
- **Prompt diversity convergence:** Multi-armed bandit prevents getting stuck on one variant. Always explores 1 slot.

## New Files (estimated)

| Category | Count | Location |
|----------|-------|----------|
| Lesson files | 43 | `docs/lessons/0007-*.md` through `0049-*.md` |
| Lesson summary | 1 | `docs/lessons/SUMMARY.md` (rewrite) |
| Lib scripts | 5 | `scripts/lib/run-plan-context.sh`, `run-plan-routing.sh`, `run-plan-team.sh`, `run-plan-scoring.sh`, `generate-ast-rules.sh` |
| Pattern files | 5-10 | `scripts/patterns/*.yml` |
| Config | 1 | Routing defaults in `run-plan-routing.sh` |
| Test files | 8-10 | `scripts/tests/test-*.sh` for each new lib |
| Logs | 3 | `logs/failure-patterns.json`, `logs/routing-decisions.log`, `logs/sampling-outcomes.json` |
