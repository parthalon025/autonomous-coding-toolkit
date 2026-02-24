# Architecture: How Autonomous Coding Works

> From idea to shipped branch with no manual copy-paste, no context degradation, and machine-verifiable completion.

## The Core Problem

Claude Code has a context window. Long implementation tasks degrade quality as context fills. Manual workflows (copy-paste prompts, eyeball test results, hand-run quality checks) don't scale past 3-4 tasks. This system solves both problems:

1. **Fresh context per unit of work** — each batch/task/iteration starts clean
2. **Machine-verifiable gates** — no batch proceeds until tests pass and anti-patterns are absent
3. **Resumability** — every state transition is persisted; any interruption is recoverable

## System Overview

```
IDEA
  │
  ▼
┌─────────────────┐
│   ROADMAP        │  Decompose multi-feature epics (conditional)
│   (Stage 0.5)   │  Output: tasks/roadmap.md (dependency-ordered features)
└────────┬────────┘
         │ (loops per feature)
         ▼
┌─────────────────┐
│   BRAINSTORMING  │  Explore intent, ask questions, propose approaches
│   (Stage 1)     │  Output: design doc (docs/plans/YYYY-MM-DD-*-design.md)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   RESEARCH       │  Investigate unknowns, resolve blockers (conditional)
│   (Stage 1.5)   │  Output: tasks/research-<slug>.md + .json
│                  │  Gate: research-gate.sh (blocks if unresolved issues)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   GIT WORKTREE   │  Isolated branch, baseline tests, clean workspace
│   (isolation)    │  Output: worktree at .worktrees/<branch>
└────────┬────────┘
         │
    ┌────┴────┐
    │  PRD    │  Machine-verifiable acceptance criteria (tasks/prd.json)
    │(optional)│  Every criterion is a shell command: exit 0 = pass
    └────┬────┘
         │
         ▼
┌─────────────────┐
│  WRITING PLANS   │  TDD-structured tasks at 2-5 minute granularity
│                  │  Output: plan file (docs/plans/YYYY-MM-DD-*.md)
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────────┐
│              EXECUTION (choose one)              │
│                                                  │
│  A. Subagent-Driven    Fresh agent per task,     │
│     (same session)     two-stage review each     │
│                                                  │
│  B. Executing-Plans    Batch + human checkpoint   │
│     (separate session) every 3 tasks             │
│                                                  │
│  C. run-plan.sh        Headless bash loop,       │
│     (unattended)       claude -p per batch       │
│                                                  │
│  D. Ralph Loop         Stop-hook loop,           │
│     (autonomous)       iterates until done        │
│                                                  │
│  ┌──────────────────────────────────────────┐    │
│  │  QUALITY GATE (between every batch)      │    │
│  │  lesson-check → test suite → memory →    │    │
│  │  test count regression → git clean       │    │
│  └──────────────────────────────────────────┘    │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────┐
│  VERIFICATION    │  Evidence-based gate: run commands, read output,
│  (mandatory)     │  confirm claim BEFORE making it
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  FINISH BRANCH   │  Merge | PR | Keep | Discard
│                  │  Worktree cleanup
└─────────────────┘
```

## The Skill Chain

Each stage is a Claude Code skill — a prompt template that teaches Claude how to execute that stage. Skills are **rigid**: follow exactly, don't adapt away discipline.

### Stage 1: Brainstorming

**Trigger:** Mandatory before any new feature, component, or behavior change. No exceptions.

**What happens:**
1. Explore project context (files, docs, recent commits)
2. Ask clarifying questions — one at a time, multiple choice preferred
3. Propose 2-3 approaches with trade-offs and a recommendation
4. Present design section by section, get user approval after each
5. Write design doc to `docs/plans/YYYY-MM-DD-<topic>-design.md`

**Hard gate:** No code, no scaffold, no implementation skill until design is approved and written.

**Code Factory enhancement:** After design approval, generate `tasks/prd.json` — 8-15 granular tasks where every acceptance criterion is a shell command that exits 0 on pass. This creates the machine-verifiable contract that the quality gates enforce.

### Stage 2: Git Worktree Isolation

**Trigger:** Before executing any plan.

**What happens:**
1. Create worktree: `git worktree add .worktrees/<branch> -b <branch-name>`
2. Auto-detect and run project setup (npm install / pip install / etc.)
3. Run baseline test suite — if tests fail, stop and report before proceeding

**Why:** Isolation means the main branch stays clean. Failed experiments are discardable. Multiple agents can work in separate worktrees without staging area conflicts (lesson #36).

### Stage 3: Writing Plans

**Trigger:** After approved design, before touching code.

**What happens:**
1. Read the design doc
2. Produce a plan file with TDD-structured tasks at 2-5 minute granularity
3. Each task specifies: exact file paths, complete code, exact commands with expected output
4. Every task follows: write failing test → confirm fail → implement → confirm pass → commit

**Plan format:**
```markdown
## Batch 1: Title
### Task 1: Name
[full task description with exact files and commands]

### Task 2: Name
...

## Batch 2: Title
...
```

**Code Factory enhancement:** Plan must include a `## Quality Gates` section listing checks to run between batches, cross-references to `tasks/prd.json` task IDs, and `progress.txt` initialization as the first step.

### Stage 4: Execution

Four execution modes, each solving a different problem:

#### Mode A: Subagent-Driven Development (same session)

**Best for:** Plans with 5-15 independent tasks where you want to watch progress.

**How it works:**
```
For each task:
  1. Spawn implementer agent (Task tool, general-purpose)
     - Receives full task text (never reads plan file)
     - Implements using TDD, commits
     - Self-reviews before reporting

  2. Spawn spec compliance reviewer
     - Reads actual code (does NOT trust implementer's report)
     - Checks: nothing missing, nothing extra vs. spec
     - If gaps → implementer fixes → re-review

  3. Spawn code quality reviewer
     - Only runs AFTER spec compliance passes
     - Checks: naming, patterns, clean code
     - If issues → implementer fixes → re-review

After all tasks:
  4. Spawn final code reviewer for entire implementation
```

**Key constraint:** Never dispatch multiple implementer agents in parallel on the same worktree. Parallel commits corrupt the staging area (lesson #36).

#### Mode B: Executing Plans (separate session, batch + checkpoint)

**Best for:** Plans you want to execute in a fresh session with human review between batches.

**How it works:**
```
1. Load plan, create task list
2. Execute first 3 tasks as a batch
3. Report: what was implemented + verification output
4. Say "Ready for feedback" — wait for user
5. Apply feedback, execute next batch
6. Repeat until done
```

**Key constraint:** Stops immediately if blocked, plan has gaps, or verification fails. Asks rather than guesses.

#### Mode C: Headless Bash (`run-plan.sh`)

**Best for:** Long plans (10+ batches) where you want to walk away.

**How it works:**
```bash
for batch in (start..end):
    prompt = parse_plan(plan_file, batch)
    claude -p "$prompt" --allowedTools Bash,Read,Write,Edit,Grep,Glob
    run_quality_gate || handle_failure
    update_state_file
    [optional: telegram_notify]
done
```

Each `claude -p` is a fresh process with a fresh context window. No degradation over 13 batches because there's no accumulated context.

**Retry escalation:** On failure, the next attempt includes the previous attempt's log tail in its prompt. Attempt 1 gets the task. Attempt 2 gets the task + "previous attempt failed." Attempt 3 gets the task + the last 50 lines of attempt 2's log.

**State management:** `.run-plan-state.json` tracks completed batches, test counts, and quality gate results. `--resume` picks up where it left off.

**Sub-modes within headless:**

| Mode | Flag | Architecture |
|------|------|-------------|
| Headless | `--mode headless` (default) | Bash loop, `claude -p` per batch |
| Team | `--mode team` | Leader session spawns implementer + reviewer agents per batch |
| Competitive | `--mode competitive` | Two agents implement same batch in separate worktrees, judge picks winner |
| MAB | `--mab` | Thompson Sampling routes to best strategy; uncertain batches trigger competitive dual-track |

**Competitive dual-track** (for critical batches):
```
Leader
  ├── git worktree: competitor-a
  ├── git worktree: competitor-b
  ├── Agent A implements (subagent-dev style)
  ├── Agent B implements (ralph style)
  ├── Both finish in parallel (separate worktrees = safe)
  ├── Judge agent compares:
  │     Tests pass (binary gate)
  │     Spec compliance (0.4)
  │     Code quality (0.3)
  │     Test coverage (0.3)
  ├── Cherry-pick winner into main worktree
  └── Cleanup both competitor worktrees
```

#### Mode E: Multi-Armed Bandit (`--mab`)

**Best for:** Plans where you want the system to learn which execution strategy works best per batch type.

**How it works:** Thompson Sampling routes each batch to either "superpowers" (TDD-style subagent) or "ralph" (iterative loop) strategy. Uncertain batches trigger competitive dual-track execution where both strategies run in parallel worktrees and an LLM judge picks the winner.

```
Batch arrives
  │
  ├── strategy-perf.json has < 5 data points per strategy
  │     → "mab" — compete (both strategies, parallel worktrees)
  │
  ├── integration batch type
  │     → "mab" — always compete (most variable outcome)
  │
  ├── Clear winner (≥70% win rate, 10+ data points)
  │     → route directly to winning strategy
  │
  └── Otherwise
        → Thompson sample from Beta(wins+1, losses+1) for each strategy
        → route to highest sample
```

**Key components:**
- **`scripts/lib/thompson-sampling.sh`** — Beta approximation using Box-Muller, routing logic with calibration thresholds
- **`logs/strategy-perf.json`** — Win/loss counters per strategy per batch type (new-file, refactoring, integration, test-only)
- **`logs/mab-lessons.json`** — Patterns the LLM judge observes during competitive runs (auto-promoted at 3+ occurrences)
- **Human calibration** — First 10 decisions default to competitive mode to build a baseline before the sampling model takes over
- **Quality gate override** — If the judge's pick fails the quality gate but the loser passes, the loser wins regardless of judge score

Enable with `--mab` flag on `run-plan.sh`.

#### Mode D: Ralph Loop (autonomous iteration)

**Best for:** Tasks with clear boolean success criteria. "Make all tests pass." "Implement everything in prd.json."

**How it works:** Uses a **Stop hook** — a shell script that intercepts Claude's attempt to exit the session and re-injects the original prompt. Claude sees its own previous work in files and git history, iterates, and improves.

```
1. User: /ralph-loop "Build X. Output <promise>COMPLETE</promise> when done."
2. Claude works on the task
3. Claude tries to exit
4. Stop hook intercepts → re-injects prompt
5. Claude sees previous work, continues
6. Loop exits ONLY when completion promise string appears
```

**Quality gates in Ralph:** The `--quality-checks` flag runs shell commands between iterations. Combined with `--prd` flag, it checks `tasks/prd.json` acceptance criteria.

**`progress.txt`:** Auto-created by Ralph setup. Read at the start of each iteration (gives Claude memory across context resets). Appended at the end of each iteration.

### Stage 5: Verification

**Trigger:** Before claiming ANY work is complete. Applies to exact claims AND implications of success.

**The Iron Law:** No completion claim without fresh verification evidence. If you haven't run the command in this turn, you cannot claim it passes.

**Five mandatory steps:**
1. **IDENTIFY** — what command proves this claim?
2. **RUN** — execute the full command fresh (not from cache or memory)
3. **READ** — full output, check exit code, count failures
4. **VERIFY** — does output actually confirm the claim?
5. **ONLY THEN** — make the claim

**Code Factory extension:** Run ALL `tasks/prd.json` acceptance criteria. Every task must have `"passes": true`. Include quality gate results as evidence.

**Local extension (`/verify` skill):**
- Integration wiring check
- Lesson-scanner agent against changed files
- Horizontal sweep: every endpoint/CLI command
- Vertical trace: one real input through entire stack
- Checklist of specific lessons to verify (#11, #16, #34, #43, etc.)

### Stage 6: Finish Branch

**Trigger:** All tasks complete, all tests verified passing.

**What happens:**
1. Run test suite — if failing, STOP (do not present options)
2. Present exactly 4 options:
   - **Merge** locally (cleanup worktree)
   - **Push + PR** (keep worktree)
   - **Keep** branch as-is (keep worktree)
   - **Discard** (requires typed confirmation, cleanup worktree)
3. Execute chosen option
4. Clean up worktree for merge and discard only

## Quality Gate Pipeline

Quality gates run between every batch in every execution mode. They are the enforcement mechanism that prevents degradation.

```
┌─────────────────────────────┐
│   lesson-check.sh           │  Syntactic anti-pattern scan
│   (<2 seconds, grep-based)  │  6 checks from real bugs:
│                              │   - bare except without logging
│                              │   - async def without await
│                              │   - create_task without done_callback
│                              │   - hub.cache direct access
│                              │   - HA automation singular keys
│                              │   - .venv/bin/pip wrong path
└──────────┬──────────────────┘
           │ if clean
           ▼
┌─────────────────────────────┐
│   ast-grep patterns          │  5 structural code patterns:
│   (scripts/patterns/*.yml)   │   - bare-except, empty-catch
│                              │   - async-no-await
│                              │   - retry-loop-no-backoff
│                              │   - hardcoded-localhost
└──────────┬──────────────────┘
           │ if clean
           ▼
┌─────────────────────────────┐
│   Test suite                 │  Auto-detected:
│   (pytest / npm test / make) │  pytest / npm test / make test
└──────────┬──────────────────┘
           │ if pass
           ▼
┌─────────────────────────────┐
│   Memory check               │  Advisory: warn if < 4GB
│   (never fails)              │  available (OOM prevention)
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│   Test count regression      │  new_count >= previous_count
│   (monotonic enforcement)    │  Catches: deleted tests,
│                              │  broken test discovery
└──────────┬──────────────────┘
           │ if no regression
           ▼
┌─────────────────────────────┐
│   Git clean check            │  All changes committed
│                              │  No leftover unstaged work
└──────────┬──────────────────┘
           │ if clean
           ▼
┌─────────────────────────────┐
│   MAB lessons injection      │  Inject judge observations
│   (--mab mode only)          │  from logs/mab-lessons.json
│                              │  into next batch context
└──────────┬──────────────────┘
           │ if clean
           ▼
        ✅ PASS → next batch
```

## State & Persistence

Three persistence mechanisms prevent data loss across context resets:

### `.run-plan-state.json` (execution state)
```json
{
  "plan_file": "docs/plans/feature.md",
  "current_batch": 5,
  "completed_batches": [1, 2, 3, 4],
  "test_counts": {"1": 10, "2": 25, "3": 42, "4": 58},
  "last_quality_gate": {"batch": 4, "passed": true, "test_count": 58}
}
```
Written after every batch. Enables `--resume`.

### `progress.txt` (discovery log)
Append-only file written by the executing agent. Contains:
- Batch summaries (what was done, what was discovered)
- Decisions made during implementation
- Issues encountered and how they were resolved

Read at the start of each batch/iteration to give the agent memory across context resets. This is how a headless `claude -p` process (which has no memory of previous batches) knows what happened before.

### `tasks/prd.json` (acceptance criteria tracker)
```json
[
  {
    "id": 1,
    "title": "Implement parser",
    "acceptance_criteria": ["pytest tests/test_parser.py -x"],
    "passes": false
  }
]
```
Updated after each batch. `"passes": true` is set when all acceptance criteria exit 0. Verification stage requires every task to pass.

### `logs/failure-patterns.json` (cross-run failure learning)
Tracks failure types, frequencies, and winning fixes indexed by batch title pattern. Fed into the next run's context injection so agents don't repeat the same mistakes.

### `logs/routing-decisions.log` (execution traceability)
Append-only log of mode selection, model routing, and parallelism scores for each batch. Enables post-run analysis of why specific strategies were chosen.

### `logs/sampling-outcomes.json` (prompt variant learning)
Records which sampling strategy (prompt variant) won per batch type. Used by `--sample N` to weight future variant selection.

### `logs/strategy-perf.json` (MAB Thompson Sampling data)
Win/loss counters per strategy (superpowers, ralph) per batch type (new-file, refactoring, integration, test-only). The Thompson Sampling routing in `--mab` mode reads this to decide whether to compete or route directly.

### `logs/mab-lessons.json` (MAB judge observations)
Patterns observed by the LLM judge during competitive runs. When a pattern reaches 3+ occurrences, it is auto-promoted into the context injection for future batches.

## Feedback Loops

### Lessons → Checks → Gates → Enforcement

```
Bug happens
  │
  ▼
Lesson captured (docs/lessons/YYYY-MM-DD-*.md)
  │  Using Army OIL taxonomy: Observation → Insight → Lesson → Lesson Learned
  │
  ▼
Pattern identified
  │
  ├─ Syntactic pattern (grep-detectable, near-zero false positives)
  │    → Add to lesson-check.sh
  │    → Enforced by quality gate on every batch
  │
  ├─ Semantic pattern (needs context, AI-detectable)
  │    → Add to lesson-scanner agent
  │    → Run during verification stage
  │
  └─ Behavioral pattern (process/workflow)
      → Add hookify rule
      → Enforced at tool-call time (pre-write, pre-commit)
```

### Community Lesson Loop

Every user's production failures improve every other user's agent:

```
User encounters bug
  │
  ▼
/submit-lesson command
  │  Captures anti-pattern, generates structured YAML lesson file
  │
  ▼
PR opened against toolkit repo
  │  Maintainer reviews regex accuracy, severity, category
  │
  ▼
Lesson file merged to docs/lessons/
  │
  ├─ pattern.type: syntactic
  │    → lesson-check.sh reads regex from YAML, runs grep
  │    → Enforced by quality gate on every batch (<2s)
  │
  └─ pattern.type: semantic
       → lesson-scanner agent reads description + example
       → Run during verification stage (AI-assisted analysis)
  │
  ▼
Every user's next scan catches that anti-pattern
```

Adding a lesson file is all it takes — no code changes to the scanner or check script.

### Scope Metadata (Project-Level Filtering)

Not every lesson applies to every project. The `scope:` field on each lesson enables project-level filtering so lessons only fire where they're relevant.

**How it works:**

1. Each lesson has a `scope:` YAML field with tags like `[universal]`, `[language:python]`, `[project:ha-aria]`
2. Each project's `CLAUDE.md` declares `## Scope Tags` (e.g., `language:python, framework:pytest, project:ha-aria`)
3. `detect_project_scope()` reads `CLAUDE.md` from the working directory and extracts these tags
4. `scope_matches()` computes the intersection — a lesson applies if any of its scope tags match the project's tags (or if the lesson is `[universal]`)

**CLI flags on `lesson-check.sh`:**
- `--all-scopes` — Ignore scope filtering, scan everything (useful for cross-project audits)
- `--show-scope` — Display the scope tags for each matched lesson
- `--scope <tags>` — Override project scope detection with explicit tags

**Design rationale:** Without scope metadata, false positives compound — at ~100 lessons, research shows 67% of flagged violations are irrelevant to the current project. Scope filtering keeps the signal-to-noise ratio high as the lesson library grows.

### Hookify (Real-Time Enforcement)

Hookify rules run on every file write and commit. They are the last line of defense:
- **bare-except:** Block writes containing `except:` without logging
- **test-counts:** Warn on hardcoded test count assertions
- **venv-pip:** Warn on `.venv/bin/pip` (use `.venv/bin/python -m pip`)
- **secrets:** Block writes containing values from `~/.env`
- **force-push:** Block `git push --force` and `-f`

Design rule: Syntactic patterns (near-zero false positives) → lesson files with `pattern.type: syntactic` → `lesson-check.sh`. Semantic patterns (needs context) → lesson files with `pattern.type: semantic` → `lesson-scanner` agent. Reserve hookify for behavioral/workflow enforcement (process violations, security boundaries).

## Agent Suite

The toolkit ships with 7 agents in the `agents/` directory, dispatched via Claude Code's Task tool. Each serves a distinct role in the quality pipeline.

| Agent | Model | Purpose | When to Use |
|-------|-------|---------|-------------|
| `lesson-scanner` | sonnet | Dynamic anti-pattern scan from lesson files | Verification stage, post-commit audit |
| `bash-expert` | sonnet | Review, write, debug bash scripts | .sh files, CI steps, Makefile targets |
| `shell-expert` | sonnet | Diagnose systemd, PATH, permissions | Service failures, environment issues |
| `python-expert` | sonnet | Async discipline, resource lifecycle, type safety | Python code review, HA/Telegram ecosystem |
| `integration-tester` | opus | Verify data flows across service seams | After deployments, timer failures, pipeline validation |
| `dependency-auditor` | haiku | CVE scan, outdated packages, license compliance | Periodic audits, pre-release checks |
| `service-monitor` | sonnet | Deep systemd service + timer investigation | When infra-auditor flags issues |

**Agent chains** (manual, not yet automated):
1. **Post-commit:** security-reviewer → lesson-scanner → doc-updater
2. **Service triage:** infra-auditor (detect) → shell-expert (investigate) → service-monitor (verify)
3. **Pre-release:** dependency-auditor → integration-tester → lesson-scanner

## Research Phase (Stage 1.5)

After design approval and before PRD generation, the optional research phase investigates technical unknowns. This prevents the most expensive failure mode: building the wrong thing correctly.

**Artifacts produced:**
- `tasks/research-<slug>.md` — human-readable report (questions, findings, recommendations)
- `tasks/research-<slug>.json` — machine-readable output with `blocking_issues`, `warnings`, `dependencies`, `confidence_ratings`

**Gate:** `scripts/research-gate.sh` reads the JSON and blocks PRD generation if any `blocking_issues` have `resolved: false`. Use `--force` to override. The gate integrates with both the interactive pipeline (`skills/autocode/SKILL.md`) and the headless pipeline (`scripts/auto-compound.sh`).

**Context injection:** `scripts/lib/run-plan-context.sh` reads research warnings from all `tasks/research-*.json` files and injects them into batch context within the token budget. This ensures agents see relevant warnings even when research was done in a prior session.

## Roadmap Stage (Stage 0.5)

For multi-feature epics (3+ features or "roadmap" keyword), the roadmap stage decomposes the work before brainstorming begins. Each feature then runs the full Stage 1-6 pipeline independently.

**Artifact:** `tasks/roadmap.md` with dependency-ordered features, phase groupings, complexity estimates, and risk ratings.

**When it activates:** Automatically when autocode detects multi-feature input. Skipped for single-feature work.

## Positive Policy System

Policies are the complement to lessons — instead of "don't do X" (negative, lesson-based), policies say "always do Y" (positive, pattern-based). Research (#62) shows positive instructions outperform negative ones for LLMs.

**Policy files** in `policies/`:
| File | Scope | Patterns |
|------|-------|----------|
| `universal.md` | All projects | Error visibility, test before ship, fresh context, durable artifacts |
| `python.md` | Python projects | Async discipline, closing(), create_task callbacks, pip via module |
| `bash.md` | Shell scripts | Strict mode, quoting, subshell cd, temp cleanup, atomic writes |
| `testing.md` | All test files | No hardcoded counts, boundary testing, test the test, live > static |

**Checker:** `scripts/policy-check.sh` — advisory by default (always exits 0). Use `--strict` to exit non-zero on violations. Auto-detects project language and runs applicable checks.

## Entropy Management

Over time, codebases drift. The entropy audit catches it:

```bash
scripts/entropy-audit.sh --projects-dir ~/projects --all
```

**Checks:**
1. Dead references in CLAUDE.md (files that no longer exist)
2. File size violations (>300 lines)
3. Naming convention drift (camelCase in Python)
4. Unused imports
5. Uncommitted work

Designed to run as a systemd timer (weekly) for continuous entropy management.

## Cross-Project Operations

### Batch Audit
```bash
scripts/batch-audit.sh ~/projects lessons
```
Runs headless `claude -p` against every project repo in a directory. Each gets its own process with read-only tools.

### Batch Test
```bash
scripts/batch-test.sh ~/projects
```
Memory-aware test runner. Auto-detects test framework per project. Skips full suite if available memory < 4GB.

### Auto-Compound (Full Pipeline)
```bash
scripts/auto-compound.sh ~/projects/my-app --report reports/daily.md
```
End-to-end: analyze report → pick #1 priority → generate PRD → create branch → Ralph loop with quality gates → push → open PR.

## Design Principles

1. **Fresh context per unit of work.** Context degradation is the #1 quality killer. Every execution mode solves this differently: `claude -p` per batch (Mode C), fresh subagent per task (Mode A), stop-hook re-injection (Mode D).

2. **Machine-verifiable gates.** No human judgment in the loop for "did this work?" Every gate is a command that exits 0 or non-zero. Humans decide *what to build*; machines verify *that it was built correctly*.

3. **Test count monotonicity.** Tests only go up. If the count decreases between batches, something broke — the gate catches it before the next batch compounds the damage.

4. **State survives interruption.** Every state transition is persisted to disk (JSON state file, progress.txt, prd.json). Kill the process, reboot the machine, come back a week later — `--resume` picks up where it left off.

5. **Orthogonal verification.** Bottom-up (syntactic anti-patterns, file-level checks) and top-down (integration boundaries, data flow traces) catch non-overlapping bug classes. A/B verification found zero overlap in critical findings across 6 critical bugs.

6. **Lessons compound.** Every bug that costs real debugging time becomes a lesson. Lessons with syntactic signatures become automated checks. Checks run on every batch. The system gets harder to break over time.
