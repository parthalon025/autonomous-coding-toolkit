# Design: npm Packaging as a Learning System

> **Date:** 2026-02-24
> **Status:** Approved
> **Goal:** Package the autonomous-coding-toolkit as a publicly installable npm package that improves with every run, every user, and every failure — not just a tool, but a compounding learning system.

## The Thesis

The toolkit's differentiator isn't any single feature — it's that **the system gets better with every run**. Lessons compound, strategy routing learns, quality gates adapt, trust earns autonomy. The packaging must expose the learning loop as a first-class concept:

```
Every run → telemetry captured
Every failure → lesson candidate
Every lesson → community contribution candidate
Every community contribution → all users improve
Every improvement → measured by benchmarks
```

That's how you code better than a human on large projects: not by being smarter on any single batch, but by compounding learning across thousands of batches across hundreds of users.

---

## Research Foundation

This design is governed by findings from the 25-paper cross-cutting synthesis (`research/2026-02-22-cross-cutting-synthesis.md`). Key findings that drive decisions:

| # | Finding | Confidence | Design Impact |
|---|---------|------------|---------------|
| 1 | Plan quality worth ~3x execution capability | High | Plan scoring learns which dimensions predict success |
| 2 | Fresh context per batch is superior to accumulated | High | Core architecture preserved — this is the #1 differentiator |
| 3 | Prompt caching yields 83% cost reduction | High | Stable prefix structure in prompts |
| 4 | Lost in the Middle: 20pp accuracy degradation | High | Task top, requirements bottom in context assembly |
| 5 | Spec misunderstanding is 60%+ of failures for strong models | Medium | Two-tier echo-back gate |
| 6 | Lesson system covers 30-40% of failure surface | Medium-High | Expand to 6 clusters, add spec drift coverage |
| 7 | 34.7% abandon on difficult setup | Medium | Fast lane onboarding under 3 minutes |
| 8 | Positive instructions outperform negative for LLMs | Medium-High | Policy system promoted alongside lessons |
| 9 | Transferability depends on abstraction level | High | Scope metadata prevents false positive death spiral |
| 10 | Coordination is #1 multi-agent failure mode (37%) | High | Structured artifacts over chat for agent communication |
| 11 | Property-based testing finds 50x more mutations | High | Testing guidance in plan skill |
| 12 | Optimal multi-agent team size is 3-4 | High | Subagent-driven-dev stays within this bound |
| 13 | No benchmark suite = can't prove improvement | — | Benchmark suite ships with package |
| 14 | Single-user testing is not testing | — | Federated telemetry across users |

---

## Part 1: Package Structure

### Approach: npm + Claude Code Plugin (dual surface)

**npm:** `npm install -g autonomous-coding-toolkit` → `act` CLI on PATH
**Plugin:** `/install autonomous-coding-toolkit` → skills, commands, agents in Claude Code

Both install from the same repo. Nothing moves — we add `package.json` + `bin/act.js` on top of the existing structure.

### Directory Layout (additions in bold)

```
autonomous-coding-toolkit/
├── **package.json**          # npm: name, version, bin, files, engines
├── **bin/**
│   └── **act.js**            # Node.js CLI router (~150 lines)
├── scripts/                  # 32 bash scripts (UNCHANGED)
│   ├── lib/                  # 18 modules (UNCHANGED)
│   ├── prompts/              # 4 agent prompts (UNCHANGED)
│   ├── patterns/             # 5 ast-grep rules (UNCHANGED)
│   ├── tests/                # Script tests (UNCHANGED)
│   └── **init.sh**           # Project bootstrapper (~100 lines)
├── skills/                   # 20 skills (UNCHANGED)
├── commands/                 # 7 commands (UNCHANGED)
├── agents/                   # 7 agents (UNCHANGED)
├── hooks/                    # hooks.json + stop-hook.sh (UNCHANGED)
├── policies/                 # 4 positive pattern defs (UNCHANGED)
├── examples/                 # 4 samples (UNCHANGED)
├── **benchmarks/**           # 5 reproducible benchmark tasks
│   ├── **tasks/**            # Task definitions + reference implementations
│   ├── **rubrics/**          # Machine-scored evaluation rubrics
│   └── **runner.sh**         # Benchmark orchestrator
├── docs/
│   ├── ARCHITECTURE.md       # System design
│   ├── CONTRIBUTING.md       # Lesson submission guide
│   └── lessons/              # 79 lessons + framework (BUNDLED)
├── .claude-plugin/           # Plugin metadata (UNCHANGED)
├── .github/                  # CI (UNCHANGED)
├── Makefile                  # lint, test, validate, ci
├── SECURITY.md
├── README.md
└── .gitignore
```

### package.json

```json
{
  "name": "autonomous-coding-toolkit",
  "version": "1.0.0",
  "description": "Autonomous AI coding pipeline: quality gates, fresh-context execution, community lessons, and compounding learning",
  "license": "MIT",
  "author": "Justin McFarland <parthalon025@gmail.com>",
  "homepage": "https://github.com/parthalon025/autonomous-coding-toolkit",
  "repository": "https://github.com/parthalon025/autonomous-coding-toolkit",
  "bin": {
    "act": "./bin/act.js"
  },
  "files": [
    "bin/",
    "scripts/",
    "skills/",
    "commands/",
    "agents/",
    "hooks/",
    "policies/",
    "examples/",
    "benchmarks/",
    "docs/",
    ".claude-plugin/",
    "Makefile",
    "SECURITY.md"
  ],
  "engines": {
    "node": ">=18.0.0"
  },
  "os": ["linux", "darwin", "win32"],
  "keywords": [
    "autonomous-coding", "ai-agents", "quality-gates",
    "claude-code", "tdd", "lessons-learned", "headless",
    "multi-armed-bandit", "code-review", "pipeline"
  ]
}
```

**Note:** `files` field excludes runtime state (`logs/`, `.run-plan-state.json`, `progress.txt`, `.worktrees/`). These are project-local, not distributable.

### Windows Support

Scripts are bash. Windows users require WSL (Windows Subsystem for Linux). `bin/act.js` checks for bash availability at startup and prints a WSL installation hint if missing. Claude Code users on Windows already have WSL as a practical requirement.

---

## Part 2: CLI Surface

### bin/act.js — Node.js Router (~150 lines)

Responsibilities:
1. **Platform check** — verify `bash` available, WSL hint on Windows
2. **Subcommand routing** — dispatch to correct bash script
3. **Toolkit root resolution** — `path.resolve(__dirname, '..')` (works for npm global, npx, and local clone)
4. **Pass-through** — all args forwarded, exit codes preserved
5. **Version/help** — built-in, no bash needed

### Full Command Map

#### Execution

| Command | Script | Purpose |
|---------|--------|---------|
| `act plan <file> [flags]` | `run-plan.sh` | Headless/team/MAB batch execution |
| `act plan --resume` | `run-plan.sh --resume` | Resume interrupted execution |
| `act compound [dir] [flags]` | `auto-compound.sh` | Full pipeline: report→PRD→execute→PR |
| `act mab <flags>` | `mab-run.sh` | Multi-Armed Bandit competing agents |

#### Quality

| Command | Script | Purpose |
|---------|--------|---------|
| `act gate [flags]` | `quality-gate.sh` | Composite quality gate |
| `act check [files...]` | `lesson-check.sh` | Syntactic anti-pattern scan |
| `act policy [flags]` | `policy-check.sh` | Advisory positive-pattern check |
| `act research-gate <json>` | `research-gate.sh` | Validate research completeness |
| `act validate` | `validate-all.sh` | Toolkit self-validation |
| `act validate-plan <file>` | `validate-plan-quality.sh` | Score plan quality (8 dimensions) |
| `act validate-prd [file]` | `validate-prd.sh` | Validate PRD JSON structure |

#### Lessons

| Command | Script | Purpose |
|---------|--------|---------|
| `act lessons pull [--remote]` | `pull-community-lessons.sh` | Sync community lessons + strategy data |
| `act lessons check` | `lesson-check.sh --list` | List active lesson checks |
| `act lessons promote` | `promote-mab-lessons.sh` | Auto-promote MAB patterns |
| `act lessons infer [--apply]` | `scope-infer.sh` | Infer scope tags for lessons |

#### Analysis

| Command | Script | Purpose |
|---------|--------|---------|
| `act audit [flags]` | `entropy-audit.sh` | Doc drift & naming violations |
| `act batch-audit <dir>` | `batch-audit.sh` | Cross-project audit |
| `act batch-test <dir>` | `batch-test.sh` | Memory-aware cross-project tests |
| `act analyze <report>` | `analyze-report.sh` | Extract priority from report |
| `act digest <log>` | `failure-digest.sh` | Summarize failure patterns |
| `act status [dir]` | `pipeline-status.sh` | Pipeline health check |
| `act architecture [dir]` | `architecture-map.sh` | Generate architecture diagram |

#### Telemetry (NEW)

| Command | Script | Purpose |
|---------|--------|---------|
| `act telemetry show` | `telemetry.sh show` | Dashboard: success rate, cost, lesson hits |
| `act telemetry export` | `telemetry.sh export` | Export anonymized run data |
| `act telemetry import <file>` | `telemetry.sh import` | Import community aggregate data |
| `act telemetry reset` | `telemetry.sh reset` | Clear local telemetry |

#### Benchmarks (NEW)

| Command | Script | Purpose |
|---------|--------|---------|
| `act benchmark run` | `benchmarks/runner.sh` | Execute all 5 benchmark tasks |
| `act benchmark run <name>` | `benchmarks/runner.sh <name>` | Execute single benchmark |
| `act benchmark compare <a> <b>` | `benchmarks/runner.sh compare` | Compare two benchmark results |

#### Setup

| Command | Script | Purpose |
|---------|--------|---------|
| `act init` | `init.sh` | Bootstrap project for toolkit use |
| `act init --quickstart` | `init.sh --quickstart` | Fast lane: working example in <3 min |
| `act license-check` | `license-check.sh` | GPL/AGPL dependency audit |
| `act module-size` | `module-size-check.sh` | Detect oversized modules |

#### Meta

| Command | Purpose |
|---------|---------|
| `act version` | Print version (from package.json) |
| `act help [command]` | Show help for any command |

---

## Part 3: Two Install Paths

### Path A: npm (CLI scripts)

```bash
npm install -g autonomous-coding-toolkit
# Now: act plan, act gate, act check, act telemetry, etc. on PATH
```

Or zero-install:
```bash
npx autonomous-coding-toolkit gate --project-root .
```

### Path B: Claude Code Plugin (skills/commands/agents)

```bash
# From Claude Code:
/install autonomous-coding-toolkit
# Now: /autocode, /create-prd, /run-plan, /ralph-loop, etc. available
```

**Both paths install from the same repo/package.** Users who install both get the full experience:
- npm → CLI scripts for headless, CI, and standalone use
- Plugin → skills, commands, agents for interactive Claude Code sessions

### Entry Points

| User wants to... | Entry point |
|-------------------|-------------|
| Start a new feature from scratch | `/autocode <feature>` (Claude Code) |
| Start from an existing plan | `act plan <file>` (CLI) or `/run-plan` (Claude Code) |
| Jump into a roadmap mid-stream | `act plan <file> --start-batch N` or `act plan --resume` |
| Quick quality check | `act gate --project-root .` (CLI) |
| See how the system is performing | `act telemetry show` (CLI) |
| Validate before shipping | `act benchmark run` (CLI) |
| Bootstrap a new project | `act init --quickstart` (CLI) |

---

## Part 4: Seven Strategic Improvements

These improvements transform the toolkit from a tool into a learning system.

### Improvement 1: Telemetry — Measure Before Optimizing

**Principle:** You can't improve what you don't measure. The research says "the first measurement infrastructure should precede the first optimization."

**Data captured per batch (local, opt-in for sharing):**

```json
{
  "timestamp": "2026-02-24T14:30:00Z",
  "project_type": "python",
  "batch_type": "integration",
  "batch_number": 3,
  "attempt": 1,
  "passed_gate": true,
  "gate_failures": [],
  "lessons_triggered": ["0007", "0033"],
  "lessons_true_positive": ["0007"],
  "test_count_delta": 12,
  "duration_seconds": 180,
  "cost_usd": 0.42,
  "strategy": "superpowers",
  "plan_quality_score": 78,
  "echo_back_passed": true,
  "trust_score": 73
}
```

**Storage:** `logs/telemetry.jsonl` (append-only, one line per batch). Project-local, never committed.

**Dashboard (`act telemetry show`):**
```
Autonomous Coding Toolkit — Telemetry Dashboard
════════════════════════════════════════════════

Runs: 47 batches across 8 plans
Success rate: 89% (42/47 passed gate on first attempt)
Total cost: $19.83 ($0.42/batch average)
Total time: 2.4 hours

Strategy Performance:
  superpowers: 78% win rate (28 runs)
  ralph:       65% win rate (19 runs)

Top Lesson Hits:
  #0007 bare-except:     12 hits, 11 true positives (92%)
  #0033 sqlite-closing:   3 hits, 3 true positives (100%)
  #0045 hub-cache:        8 hits, 0 true positives (0%) ← retirement candidate

Batch Type Success:
  new-file:     95% (19/20)
  test-only:    100% (8/8)
  refactoring:  83% (10/12)
  integration:  71% (5/7)  ← lowest, consider MAB for this type
```

**Export/import for community learning:**
- `act telemetry export` → anonymized JSON (no file paths, no project names, no code)
- `act telemetry import community-aggregate.json` → merges into local strategy routing
- Community aggregate published periodically to toolkit repo (opt-in contributions)

### Improvement 2: Federated Learning for Strategy Routing

**Principle:** 100 users learning independently is 100x slower than learning together. Strategy performance should compound across the community.

**Current state:** `strategy-perf.json` is per-install. `pull-community-lessons.sh` already merges it with `max(local, remote)` per counter.

**Improvement:** Extend the pull mechanism to also merge:
- Anonymized strategy-perf data from community aggregate
- Lesson hit rate statistics (which lessons actually catch bugs)
- Batch-type success rates per strategy

**Merge strategy (already implemented, extend):**
- `max(local, remote)` per counter for win/loss data
- Weighted average for rates (weight = sample size)
- Never overwrite local data — additive merge only

**Effect on routing:** Thompson Sampling in `lib/thompson-sampling.sh` starts with community priors instead of uniform priors. A new user benefits from the collective experience of all previous users from their first run.

### Improvement 3: Adaptive Quality Gates

**Principle:** The immune system amplifies what works and retires what doesn't (biological analogy from research #B2-3). Quality gates should do the same.

**Current state:** Gate pipeline is static: lesson-check → ast-grep → tests → memory → test count → git clean.

**Improvement:** Track lesson effectiveness from telemetry:

| Metric | Threshold | Action |
|--------|-----------|--------|
| True positive rate > 80% | After 20+ triggers | Promote to "high-value" (always first in pipeline) |
| True positive rate 20-80% | After 20+ triggers | Normal (current behavior) |
| True positive rate < 20% | After 50+ triggers | Downgrade to advisory (warn, don't block) |
| Zero triggers | After 100+ scans | Flag as retirement candidate |

**Implementation:** `lesson-check.sh` reads `logs/telemetry.jsonl` to compute lesson effectiveness. Lessons flagged as retirement candidates appear in `act telemetry show` for manual review. No lesson is auto-deleted — only downgraded to advisory.

**Why not auto-delete:** A lesson with zero hits might be preventing bugs by its mere presence in the system (developers read lessons and avoid the pattern). Retirement requires human judgment.

### Improvement 4: Semantic Echo-Back

**Principle:** Spec misunderstanding is 60%+ of failures for strong models (#B1-5). Keyword matching catches omissions but not misinterpretation. A human reviewer asks "do you understand what I'm asking?" before "did you do it right?"

**Current state:** `run-plan-echo-back.sh` does keyword matching — checks whether key terms from batch text appear in agent output.

**Improvement:** Two-tier echo-back:

**Tier 1 (current, every batch):** Keyword match — fast (<1s), catches obvious omissions.

**Tier 2 (new, selective):** LLM verification — agent summarizes what it will build, separate `claude -p` call compares summary vs. spec, flags misalignment.

**When Tier 2 activates:**
- Always on Batch 1 of any plan (disproportionate risk — research #B2-3, #P9)
- Always on integration batches (highest failure rate from telemetry)
- When `--strict-echo-back` flag is set
- MAB can learn whether Tier 2 prevents enough rework to justify cost (~$0.10/batch)

**Tier 2 prompt structure:**
```
You are a specification compliance reviewer. Compare:

SPECIFICATION:
<batch task text from plan>

AGENT'S UNDERSTANDING:
<agent's summary of what it will build>

Does the agent's understanding match the specification? Flag any:
- Missing requirements
- Added requirements not in spec
- Misinterpreted requirements
- Ambiguous interpretations

Output: PASS or FAIL with specific misalignments.
```

### Improvement 5: Fast Lane Onboarding

**Principle:** 34.7% abandon on difficult setup (#B2-1). A dead user gets zero benefit from perfect process. Time to first value must be under 3 minutes.

**`act init` (standard):**
1. Detect project type (Python/Node/bash/Make/unknown)
2. Create `tasks/` directory
3. Create empty `progress.txt`
4. Append Code Factory section to CLAUDE.md (or create minimal CLAUDE.md)
5. Set quality gate command based on project type
6. Detect language → set `## Scope Tags`
7. Print next steps

**`act init --quickstart` (fast lane):**
All of the above, plus:
1. Copy `examples/quickstart-plan.md` → `docs/plans/quickstart.md`
2. Customize the plan for detected project type:
   - Python: "Add a conftest.py with common fixtures + test helper"
   - Node: "Add a build validation script + test helper"
   - Bash: "Add shellcheck CI + test runner"
3. Run `act gate --project-root .` to verify quality gate works
4. Print: "Ready. Run `act plan docs/plans/quickstart.md` for your first quality-gated execution."

**Time budget:** `act init` < 10 seconds, `act init --quickstart` < 30 seconds (gate run is the bottleneck).

### Improvement 6: Graduated Autonomy

**Principle:** Start supervised, earn trust, reduce friction. Humans don't give full autonomy to new team members on day one.

**Trust score per project, derived from telemetry:**

```
Trust Score = weighted average of:
  - Gate first-attempt pass rate (40%)
  - Echo-back pass rate (20%)
  - Test regression rate, inverted (20%)
  - Post-merge revert rate, inverted (20%)
```

**Trust levels and default behavior:**

| Trust | Score | Default Mode | Rationale |
|-------|-------|-------------|-----------|
| New | < 30 (or < 10 runs) | Mode B: human checkpoint every batch | Unknown project, build confidence |
| Growing | 30-70 | Headless with checkpoint every 3rd batch | Earning trust, spot-check |
| Trusted | 70-90 | Headless with notification on failures only | Proven track record |
| Autonomous | > 90 | Full headless, post-run summary only | Consistently excellent |

**Override:** Users can always set `--mode` explicitly. Trust score is advisory default, not a hard gate.

**Trust score in `act status`:**
```
Project: my-app (python)
Trust Score: 73/100 (28 runs)
  Gate pass rate:     89% ████████▉  (HIGH)
  Echo-back rate:     92% █████████▏ (HIGH)
  Test regression:     4% ▍          (GOOD)
  Post-merge revert:   0% ▏          (EXCELLENT)
Default mode: headless with checkpoint every 3rd batch
```

### Improvement 7: Benchmark Suite

**Principle:** "Single-user testing is not testing." Without benchmarks, you can't prove the toolkit works, you can't measure improvement between versions, and users can't validate their setup.

**5 benchmark tasks (varying complexity):**

| # | Task | Complexity | Measures |
|---|------|-----------|----------|
| 1 | Add a REST endpoint with tests | Simple (1 batch) | Basic execution, TDD compliance |
| 2 | Refactor a module into two | Medium (2 batches) | Refactoring quality, test preservation |
| 3 | Fix an integration bug | Medium (2 batches) | Debugging, root cause analysis |
| 4 | Add test coverage to untested module | Medium (2 batches) | Test quality, edge case discovery |
| 5 | Multi-file feature with API + DB + tests | Complex (4 batches) | Full pipeline, cross-file coordination |

**Each benchmark includes:**
- `task.md` — Problem description (what the agent receives)
- `scaffold/` — Starting codebase (reproducible initial state)
- `reference/` — Reference implementation (what "correct" looks like)
- `rubric.sh` — Machine-scored evaluation (exit 0 = pass per criterion)
- `rubric.json` — Criteria and weights for scoring

**`act benchmark run` behavior:**
1. Create temp directory, copy scaffold
2. Run `act plan` on the task
3. Execute `rubric.sh` to score the result
4. Compare against reference implementation
5. Output scorecard with per-criterion pass/fail

**`act benchmark compare <before.json> <after.json>`:**
```
Benchmark Comparison: v1.0.0 vs v1.1.0
═══════════════════════════════════════
                    v1.0.0    v1.1.0    Delta
Task 1 (endpoint):    85%       92%     +7%
Task 2 (refactor):    72%       78%     +6%
Task 3 (debug):       68%       81%     +13%  ← biggest improvement
Task 4 (coverage):    90%       91%     +1%
Task 5 (multi-file):  55%       67%     +12%
─────────────────────────────────────────
Overall:              74%       82%     +8%
```

---

## Part 5: Complete Concept Inventory

Everything from the existing toolkit is preserved. Nothing is removed or moved.

### Skills (20 — all preserved)

| Skill | Purpose | Pipeline Stage |
|-------|---------|---------------|
| autocode | Full 9-stage pipeline orchestrator | Entry point |
| brainstorming | Design exploration & approval | Stage 1 |
| research | Structured technical investigation | Stage 1.5 |
| roadmap | Multi-feature epic decomposition | Stage 0.5 |
| writing-plans | TDD-structured implementation plans | Stage 3 |
| using-git-worktrees | Isolated workspace creation | Stage 2 |
| subagent-driven-development | Fresh agent per task + 2-stage review | Stage 4a |
| executing-plans | Batch execution with human checkpoints | Stage 4b |
| verification-before-completion | Evidence-based gate | Stage 5 |
| finishing-a-development-branch | Merge/PR/keep/discard | Stage 6 |
| test-driven-development | Red-Green-Refactor cycle | Supporting |
| systematic-debugging | 4-phase root cause investigation | Supporting |
| dispatching-parallel-agents | 2+ independent task coordination | Supporting |
| requesting-code-review | Dispatch reviewer subagent | Supporting |
| receiving-code-review | Technical evaluation of feedback | Supporting |
| using-superpowers | Meta-skill: invoke skills before action | Meta |
| verify | Self-verification checklist | Supporting |
| writing-skills | TDD applied to skill documentation | Meta |
| capture-lesson | Incident → lesson workflow | Lesson system |
| check-lessons | Surface relevant lessons for current work | Lesson system |

### Commands (7 — all preserved)

| Command | Purpose |
|---------|---------|
| `/autocode <feature>` | Full pipeline entry point |
| `/code-factory <feature>` | Alias for autocode |
| `/create-prd <feature>` | Machine-verifiable acceptance criteria |
| `/run-plan <file>` | In-session batch execution |
| `/ralph-loop <prompt>` | Autonomous iteration with stop-hook |
| `/cancel-ralph` | Cancel active Ralph loop |
| `/submit-lesson` | Community lesson submission via PR |

### Agents (7 — all preserved)

| Agent | Model | Purpose |
|-------|-------|---------|
| lesson-scanner | sonnet | Dynamic anti-pattern scan from lesson files |
| bash-expert | sonnet | Shell script review & debugging |
| shell-expert | sonnet | systemd/service diagnosis |
| python-expert | sonnet | Async, lifecycle, type safety review |
| integration-tester | opus | Cross-service data flow verification |
| dependency-auditor | haiku | CVE scan, license compliance |
| service-monitor | sonnet | systemd service/timer health |

### Scripts (32 existing + 3 new = 35)

**Existing (all preserved, paths unchanged):**

Execution: run-plan.sh, auto-compound.sh, mab-run.sh, setup-ralph-loop.sh
Quality: quality-gate.sh, lesson-check.sh, policy-check.sh, research-gate.sh
Validation: validate-all.sh, validate-lessons.sh, validate-skills.sh, validate-commands.sh, validate-plugin.sh, validate-hooks.sh, validate-policies.sh, validate-prd.sh, validate-plan-quality.sh
Analysis: entropy-audit.sh, batch-audit.sh, batch-test.sh, analyze-report.sh, failure-digest.sh, pipeline-status.sh, architecture-map.sh
Lessons: pull-community-lessons.sh, promote-mab-lessons.sh, scope-infer.sh
Utilities: license-check.sh, module-size-check.sh, generate-ast-rules.sh, prior-art-search.sh

**New:**

| Script | Purpose | Lines (est.) |
|--------|---------|-------------|
| `scripts/init.sh` | Project bootstrapper (`act init`) | ~100 |
| `scripts/telemetry.sh` | Telemetry capture, dashboard, export/import | ~200 |
| `benchmarks/runner.sh` | Benchmark orchestrator | ~150 |

### Lib Modules (18 — all preserved)

common.sh, ollama.sh, telegram.sh, progress-writer.sh, cost-tracking.sh, thompson-sampling.sh, run-plan-parser.sh, run-plan-state.sh, run-plan-headless.sh, run-plan-team.sh, run-plan-routing.sh, run-plan-quality-gate.sh, run-plan-prompt.sh, run-plan-context.sh, run-plan-sampling.sh, run-plan-scoring.sh, run-plan-echo-back.sh, run-plan-notify.sh

### Execution Modes (5 — all preserved)

| Mode | Entry (Claude Code) | Entry (CLI) | Isolation |
|------|-------------------|------------|-----------|
| A: Subagent-dev | /autocode → Stage 4a | N/A (Claude-only) | Same session |
| B: Executing-plans | /autocode → Stage 4b | N/A (Claude-only) | Separate session |
| C: Headless | /run-plan | `act plan <file>` | Fresh context/batch |
| D: Ralph Loop | /ralph-loop | N/A (needs stop-hook) | Same session |
| E: MAB | /run-plan --mab | `act plan <file> --mab` | Parallel worktrees |

### State & Persistence (5 existing + 1 new = 6)

| State File | Location | Purpose |
|-----------|----------|---------|
| `.run-plan-state.json` | Project root | Execution checkpoint (batches, test counts, costs) |
| `progress.txt` | Project root | Append-only discovery log |
| `tasks/prd.json` | Project root | Machine-verifiable acceptance criteria |
| `logs/failure-patterns.json` | Project root | Cross-run failure learning |
| `.claude/ralph-loop.local.md` | Project root | Ralph loop state |
| **`logs/telemetry.jsonl`** | Project root | **Per-batch telemetry (NEW)** |

Additional learning state (existing, in `logs/`): routing-decisions.log, sampling-outcomes.json, strategy-perf.json, mab-lessons.json.

All state is project-local. The npm package is stateless. No state collision between projects.

### Lessons (79 + framework — all bundled)

**Three-tier architecture:**

```
Tier 1: Bundled (ships with npm, updated on npm update)
  Location: <npm-root>/docs/lessons/
  Count: 79 (grows with releases)

Tier 2: Community (git-synced between releases)
  Mechanism: act lessons pull --remote upstream
  Source: main branch of toolkit repo
  Merge: additive only, never overwrites local

Tier 3: Project-local (user's own lessons)
  Location: <project>/docs/lessons/
  Scope: project-specific anti-patterns
  Never overwritten by Tier 1 or 2
```

**Six root cause clusters:**
1. Silent Failures — operation appears to succeed but silently fails
2. Integration Boundaries — each component passes its test; bug hides at seam
3. Cold-Start Assumptions — works steady-state, fails on restart
4. Specification Drift — agent builds wrong thing correctly
5. Context & Retrieval — info available but buried/misscoped
6. Planning & Control Flow — wrong decomposition contaminates downstream

**Lesson schema:** YAML frontmatter with id, title, severity, languages, scope, category, pattern (type + regex/description), fix, positive_alternative, example (bad/good).

**Scope filtering:** `lesson-check.sh` reads `## Scope Tags` from CLAUDE.md, computes intersection with lesson scope tags. Prevents false positive death spiral at scale (research #B2-2).

### Policies (4 — all preserved)

| File | Scope | Patterns |
|------|-------|----------|
| universal.md | All projects | Error visibility, test before ship, fresh context, durable artifacts |
| python.md | Python | Async discipline, closing(), create_task callbacks |
| bash.md | Shell | Strict mode, quoting, subshell cd, atomic writes |
| testing.md | All tests | No hardcoded counts, boundary testing, live > static |

### Hooks (2 — all preserved)

| Hook | Trigger | Purpose |
|------|---------|---------|
| SessionStart | Session init | Symlink setup for skill discovery |
| Stop | Session exit | Ralph loop continuation gate |

### Quality Gate Pipeline (preserved + enhanced)

```
lesson-check.sh (syntactic, <2s)
  ↓ if clean
ast-grep patterns (5 structural checks)
  ↓ if clean
Test suite (auto-detected: pytest/npm/make)
  ↓ if pass
Memory check (warn if <4GB, never fail)
  ↓
Test count regression (new_count >= old_count)
  ↓ if no regression
Git clean (all changes committed)
  ↓ if clean
**Telemetry capture (NEW — write batch results to logs/telemetry.jsonl)**
  ↓
✅ PASS → next batch
```

### Examples (4 — all preserved)

example-plan.md, example-prd.json, example-roadmap.md, quickstart-plan.md

### Documentation (all preserved)

ARCHITECTURE.md, CONTRIBUTING.md, SECURITY.md, docs/lessons/FRAMEWORK.md, docs/lessons/TEMPLATE.md, docs/lessons/SUMMARY.md, docs/lessons/DIAGNOSTICS.md

### CI (preserved)

.github/workflows/ci.yml — ShellCheck + shfmt + shellharden + semgrep + tests

### Prompts & AST Patterns (all preserved)

Prompts: planner-agent.md, judge-agent.md, agent-a-superpowers.md, agent-b-ralph.md
Patterns: bare-except.yml, empty-catch.yml, async-no-await.yml, retry-loop-no-backoff.yml, hardcoded-localhost.yml

---

## Part 6: External Dependencies

### Required

| Dependency | Used By | Check |
|-----------|---------|-------|
| bash 4+ | All scripts | `act` checks at startup |
| git | Worktrees, state, PRs | `act` checks at startup |
| jq | State files, PRD, MAB, telemetry | `act` checks at startup |
| curl | Ollama, Telegram (optional features) | Checked at call site |
| claude CLI | Execution modes (plan, compound, mab) | Checked by run-plan.sh |
| Node.js 18+ | `bin/act.js` router only | npm enforces via engines |

### Optional (graceful degradation)

| Dependency | Used By | Behavior if Missing |
|-----------|---------|-------------------|
| ruff | quality-gate (Python lint) | Skipped with warning |
| eslint | quality-gate (JS lint) | Skipped with warning |
| ast-grep | quality-gate (structural) | Skipped (advisory anyway) |
| ollama | analyze-report, auto-compound | Fails with clear message |
| bc | Thompson Sampling | Falls back to random routing |
| gh | PRs, submit-lesson, benchmarks | Fails with install hint |
| pytest/npm/make | quality-gate (tests) | Auto-detected, skips if none |

### Hardcoded Paths to Fix (2 only)

| Current | Fix | Script |
|---------|-----|--------|
| `~/.env` for Telegram/Ollama creds | Add `ACT_ENV_FILE` env var | telegram.sh, ollama.sh |
| `$HOME/Documents/projects` default | Already has `--projects-dir` flag | entropy-audit.sh |

Everything else uses `SCRIPT_DIR` relative resolution via `readlink -f`.

---

## Part 7: Design Principles

These principles govern the toolkit's behavior and every future contribution. They are non-negotiable.

### From the Original Architecture

1. **Fresh context per unit of work** — Context degradation is the #1 quality killer. Every execution mode solves this differently.
2. **Machine-verifiable gates** — No human judgment for "did this work?" Every gate is a command that exits 0 or non-zero.
3. **Test count monotonicity** — Tests only go up. Decreased count = something broke.
4. **State survives interruption** — Every transition persisted to disk. Kill, reboot, come back later — `--resume` works.
5. **Orthogonal verification** — Bottom-up (syntactic) + top-down (integration) catch non-overlapping bug classes.
6. **Lessons compound** — Every bug becomes an automated check. The system gets harder to break over time.

### From the Research Foundation

7. **Plan quality over execution quality** — 3:1 ratio. Invest in plan scoring, spec echo-back, and research gates before execution optimization.
8. **Measure before optimizing** — Telemetry first. Every improvement must be measurable.
9. **Positive instructions alongside negative** — Policies ("do Y") complement lessons ("don't do X"). LLMs respond better to positive guidance.
10. **Scope to prevent noise** — Every lesson has scope metadata. Without it, false positives compound and users disable the system.
11. **Community learning compounds** — Federated telemetry and lesson sync mean every user makes every other user's system better.
12. **Graduated autonomy** — Start supervised, earn trust through measured success, reduce friction over time.
13. **Fast time to first value** — Under 3 minutes to first quality-gated execution. A dead user gets zero benefit from perfect process.

### From Operations Research (18 frameworks converged)

14. **Formal gate between understanding and building** — The brainstorm→research→PRD chain is not optional overhead; it's the highest-leverage investment.
15. **Adversarial review at every stage** — Spec reviewer, code quality reviewer, lesson scanner, quality gate — each catches a different failure class.
16. **Intent over method** — Plans specify what and why, not how. Agents choose implementation strategy.

---

## Part 8: What's New (Summary)

| Item | Type | Est. Lines | Priority |
|------|------|-----------|----------|
| `package.json` | New file | ~30 | P0 (required for npm) |
| `bin/act.js` | New file | ~150 | P0 (CLI router) |
| `scripts/init.sh` | New file | ~100 | P0 (project bootstrap) |
| `scripts/telemetry.sh` | New file | ~200 | P1 (measurement before optimization) |
| `benchmarks/` directory | New directory | ~300 | P1 (prove the system works) |
| Fix `~/.env` → `ACT_ENV_FILE` | Edit 2 files | ~10 | P0 (portability) |
| `LESSONS_DIR` project-local fallback | Edit lesson-check.sh | ~10 | P0 (lesson tiers) |
| Update README.md | Edit | ~200 | P0 (installation docs) |
| Telemetry capture in quality gate | Edit quality-gate.sh | ~20 | P1 (data collection) |
| Trust score in pipeline-status.sh | Edit | ~50 | P2 (graduated autonomy) |
| Tier 2 echo-back | Edit run-plan-echo-back.sh | ~80 | P2 (spec drift prevention) |
| **Total new code** | | **~1,150** | |

**P0:** Required for npm publish. Ship first.
**P1:** Required for the learning system thesis. Ship second.
**P2:** Enhances the learning system. Ship third.

---

## Part 9: What Does NOT Change

- All 20 skills — unchanged, same paths
- All 7 commands — unchanged
- All 7 agents — unchanged
- All 32 existing scripts — unchanged (except 3 small edits noted above)
- All 18 lib modules — unchanged
- All 79 lessons — bundled as-is
- All 4 policies — unchanged
- All 5 execution modes — unchanged
- All hooks — unchanged
- All state file formats — unchanged
- All prompts and AST patterns — unchanged
- CI workflow — unchanged
- Directory layout — preserved (additions only)
- Design principles 1-6 — preserved (7-16 are additions)

---

## Appendix A: Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `act` name collision (other npm packages) | Medium | Low | Check npm registry; fallback: `actk` |
| Windows without WSL | Medium | Medium | Clear error message + WSL install guide |
| Telemetry privacy concerns | Low | High | Local-only default, explicit opt-in for sharing, no PII ever |
| Claude Code API changes break hooks/skills | Medium | High | Abstract plugin interface; version pin in package.json |
| Lesson false positive spiral at scale | Medium | High | Adaptive gates (Improvement 3) + scope filtering |
| Community doesn't form | High | Medium | Toolkit works solo; community features are additive |

## Appendix B: Success Metrics

| Metric | Target (6 months) | How Measured |
|--------|-------------------|-------------|
| npm weekly downloads | 50+ | npm stats |
| Community lessons submitted | 10+ | GitHub PRs |
| Benchmark score improvement | +10% over v1.0 baseline | `act benchmark compare` |
| Gate first-attempt pass rate | >85% across community | Aggregated telemetry |
| Time to first value | <3 minutes | Manual testing + user reports |
| User retention (>5 runs) | >50% of installers | Telemetry (if opted in) |

## Appendix C: Research Document Index

Full research corpus governing this design: `research/2026-02-22-cross-cutting-synthesis.md` (25 papers, 409 lines). Key references by section:

- Telemetry: Cost/Quality (#B1-7), MAB R2 (#P7)
- Federated learning: Lesson Transferability (#B2-2), MAB R1 (#P6)
- Adaptive gates: Lesson Transferability (#B2-2), Unconventional Perspectives (#B2-3)
- Echo-back: Failure Taxonomy (#B1-5), Multi-Agent Coordination (#B1-8)
- Fast lane: User Adoption (#B2-1), Competitive Landscape (#B1-4)
- Graduated autonomy: User Adoption (#B2-1), Operations Design (#P9)
- Benchmarks: Verification Effectiveness (#B1-6), Comprehensive Testing (#B2-7)
