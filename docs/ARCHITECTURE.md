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
│   BRAINSTORMING  │  Explore intent, ask questions, propose approaches
│   (mandatory)    │  Output: design doc (docs/plans/YYYY-MM-DD-*-design.md)
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

### Hookify (Real-Time Enforcement)

Hookify rules run on every file write and commit. They are the last line of defense:
- **bare-except:** Block writes containing `except:` without logging
- **test-counts:** Warn on hardcoded test count assertions
- **venv-pip:** Warn on `.venv/bin/pip` (use `.venv/bin/python -m pip`)
- **secrets:** Block writes containing values from `~/.env`
- **force-push:** Block `git push --force` and `-f`

Design rule: Syntactic patterns (near-zero false positives) → lesson files with `pattern.type: syntactic` → `lesson-check.sh`. Semantic patterns (needs context) → lesson files with `pattern.type: semantic` → `lesson-scanner` agent. Reserve hookify for behavioral/workflow enforcement (process violations, security boundaries).

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
