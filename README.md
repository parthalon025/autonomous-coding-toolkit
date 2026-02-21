# Autonomous Coding Toolkit

A complete system for running AI coding agents autonomously with quality gates, fresh-context execution, and machine-verifiable completion.

Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Includes skills, agents, scripts, and plugins that implement an end-to-end autonomous coding pipeline.

## What This Does

You write a plan. The toolkit executes it batch-by-batch without you at the keyboard:

```
Idea → Brainstorm → Plan → Worktree → Execute (4 modes) → Verify → Finish
```

Each unit of work gets a fresh context window. Quality gates run between batches. Skills enforce discipline at every stage. Lessons from past bugs become automated checks that prevent regressions.

## Quick Start

```bash
# 1. Write a plan (see examples/example-plan.md for format)

# 2. Run it headless
scripts/run-plan.sh docs/plans/my-feature.md

# 3. Resume if interrupted
scripts/run-plan.sh --resume

# 4. Run with retries and Telegram notifications
scripts/run-plan.sh docs/plans/my-feature.md --on-failure retry --max-retries 3 --notify
```

## The Skill Chain

Skills are Claude Code prompt templates that teach the agent HOW to execute each stage. They are rigid — follow exactly, don't adapt away discipline.

```
brainstorming → writing-plans → using-git-worktrees → [execution mode] → verification-before-completion → finishing-a-development-branch
```

| Stage | Skill | Purpose |
|-------|-------|---------|
| 1. Design | `brainstorming` | Explore intent → design → approval before code |
| 2. Plan | `writing-plans` | TDD-structured tasks at 2-5 minute granularity |
| 3. Isolate | `using-git-worktrees` | Isolated workspace with safety verification |
| 4a. Execute (same session) | `subagent-driven-development` | Fresh subagent per task + two-stage review |
| 4b. Execute (separate session) | `executing-plans` | Batch execution with human review checkpoints |
| 4c. Execute (headless) | `scripts/run-plan.sh` | `claude -p` per batch, fully autonomous |
| 4d. Execute (loop) | `plugins/ralph-loop` | Stop-hook iteration until completion promise |
| 5. Verify | `verification-before-completion` | Evidence-based gate: run commands, read output |
| 6. Finish | `finishing-a-development-branch` | Merge / PR / Keep / Discard + worktree cleanup |

### Supporting Skills

| Skill | Purpose |
|-------|---------|
| `test-driven-development` | Red-Green-Refactor cycle for all implementation |
| `systematic-debugging` | Root cause before fix, always |
| `dispatching-parallel-agents` | 2+ independent tasks in parallel |
| `requesting-code-review` | Dispatch reviewer subagent with template |
| `receiving-code-review` | Technical evaluation, not performative agreement |
| `writing-skills` | TDD applied to process documentation |
| `using-superpowers` | Meta-skill: invoke skills before any action |
| `verify` | Self-verification checklist before completion claims |

## Architecture

```
skills/                          # Claude Code skills (loaded via Skill tool)
├── brainstorming/SKILL.md
├── writing-plans/SKILL.md
├── executing-plans/SKILL.md
├── using-git-worktrees/SKILL.md
├── subagent-driven-development/
│   ├── SKILL.md
│   ├── implementer-prompt.md
│   ├── spec-reviewer-prompt.md
│   └── code-quality-reviewer-prompt.md
├── verification-before-completion/SKILL.md
├── finishing-a-development-branch/SKILL.md
├── test-driven-development/SKILL.md
├── systematic-debugging/
│   ├── SKILL.md
│   ├── root-cause-tracing.md
│   ├── defense-in-depth.md
│   └── condition-based-waiting.md
├── dispatching-parallel-agents/SKILL.md
├── requesting-code-review/
│   ├── SKILL.md
│   └── code-reviewer.md
├── receiving-code-review/SKILL.md
├── writing-skills/SKILL.md
├── using-superpowers/SKILL.md
└── verify/SKILL.md

agents/                          # Agent definitions (dispatched via Task tool)
└── lesson-scanner.md            # Scans for anti-patterns from 53 lessons learned

plugins/                         # Claude Code plugins (hooks + commands)
└── ralph-loop/                  # Autonomous iteration via stop hook
    ├── .claude-plugin/plugin.json
    ├── scripts/setup-ralph-loop.sh
    ├── hooks/stop-hook.sh
    ├── hooks/hooks.json
    └── commands/ralph-loop.md

scripts/                         # Bash scripts for headless execution
├── run-plan.sh                  # Main runner (3 modes: headless/team/competitive)
├── lib/                         # run-plan.sh modules
├── quality-gate.sh              # Composite gate: lesson-check + tests + memory
├── lesson-check.sh              # Syntactic anti-pattern detector (<2s, grep-based)
├── auto-compound.sh             # Full pipeline: report → PRD → execute → PR
├── entropy-audit.sh             # Detect doc drift, naming violations
├── batch-audit.sh               # Cross-project audit runner
└── batch-test.sh                # Memory-aware cross-project test runner

.claude/commands/                # Claude Code slash commands
├── code-factory.md              # /code-factory — full pipeline
├── create-prd.md                # /create-prd — machine-verifiable PRD
└── run-plan.md                  # /run-plan — in-session batch execution
```

## Execution Modes

### Mode C: Headless (default, fully autonomous)

Pure bash loop. Calls `claude -p` per batch with fresh context each time. No human interaction needed.

```bash
scripts/run-plan.sh docs/plans/feature.md
```

- Each batch = fresh `claude -p` process (solves context degradation)
- Quality gates between every batch
- Test count regression detection (new count must be >= previous)
- Retry with escalating context (previous attempt logs fed to next attempt)
- Resume from saved state after interruption

### Mode A: Team-Per-Batch

Uses Claude Code agent teams. A leader spawns implementer + reviewer teammates per batch.

```bash
scripts/run-plan.sh docs/plans/feature.md --mode team
```

- Implementer writes code (TDD cycle)
- Reviewer checks against spec
- Leader runs quality gate
- Two-stage review per batch

### Mode B: Competitive Dual-Track

Two agents implement the same batch in separate git worktrees. A judge picks the winner.

```bash
scripts/run-plan.sh docs/plans/feature.md --mode competitive --competitive-batches 5,8
```

- Teammate-A and Teammate-B work in parallel on isolated worktrees
- Judge compares: tests passing, spec compliance, code quality
- Winner's commits cherry-picked into main worktree
- Only activates for critical batches (others fall back to Mode A)

## Plan File Format

Standard markdown. No special syntax beyond heading conventions:

```markdown
## Batch 1: Setup and scaffolding

### Task 1: Create project structure

Create the directory layout and install dependencies.
- `src/` for source code
- `tests/` for test files
- Add pytest to dev dependencies

### Task 2: Add configuration module

Create `src/config.py` with environment variable loading.

## Batch 2: Core implementation

### Task 3: Implement the parser
...
```

See `examples/example-plan.md` for a complete example.

## Quality Gates

Quality gates run automatically between batches. The default gate (`quality-gate.sh`) runs three checks:

1. **Lesson check** — scans changed files for known anti-patterns (bare exceptions, async without await, fire-and-forget tasks)
2. **Test suite** — auto-detects pytest/npm test/make test and runs it
3. **Memory check** — warns if available memory < 4GB (advisory, never fails)

Customize with `--quality-gate`:

```bash
scripts/run-plan.sh plan.md --quality-gate "pytest -x && npm run lint"
```

## Lesson Check (Anti-Pattern Detector)

`lesson-check.sh` is a fast (<2s) syntactic checker that catches patterns known to cause real bugs:

| Check | What It Catches |
|-------|----------------|
| `[lesson-7]` | Bare `except:` without logging — silent data loss |
| `[lesson-25]` | `async def` without `await` — returns truthy coroutine instead of result |
| `[lesson-43]` | `create_task()` without `add_done_callback` — "task exception never retrieved" |
| `[lesson-12]` | Direct `hub.cache.*` access — use accessor methods |
| `[lesson-51]` | `.venv/bin/pip` instead of `.venv/bin/python -m pip` — wrong site-packages |

```bash
# Check specific files
scripts/lesson-check.sh src/main.py src/utils.py

# Check git-changed files (default)
scripts/lesson-check.sh

# Pipe file list
git diff --name-only | scripts/lesson-check.sh
```

The lesson framework at `docs/lessons/` provides the structure for adding your own checks.

## Code Factory (Full Pipeline)

`auto-compound.sh` runs the complete autonomous pipeline:

```
Report → Analyze (#1 priority) → PRD → Branch → Execute → Push → PR
```

```bash
scripts/auto-compound.sh ~/projects/my-app --report reports/daily.md
```

Requires: Claude CLI, jq, gh (GitHub CLI), Ollama (for report analysis).

## Installation

### As a Claude Code Plugin

```bash
# Clone into your plugins directory
git clone https://github.com/parthalon025/autonomous-coding-toolkit.git ~/.claude/plugins/autonomous-coding-toolkit

# Or symlink the skills into your skills directory
ln -s path/to/autonomous-coding-toolkit/skills/* ~/.claude/skills/
```

### As Standalone Scripts

```bash
# Clone anywhere
git clone https://github.com/parthalon025/autonomous-coding-toolkit.git

# Run headless execution directly
./autonomous-coding-toolkit/scripts/run-plan.sh your-plan.md
```

## Claude Commands

The `.claude/commands/` directory contains commands for use inside Claude Code sessions:

- **`/code-factory`** — Full pipeline: brainstorm → PRD → plan → execute → verify
- **`/create-prd`** — Generate a PRD with machine-verifiable acceptance criteria (every criterion is a shell command)
- **`/run-plan`** — In-session batch execution with quality gates

## Ralph Loop (Autonomous Iteration)

The `plugins/ralph-loop/` directory is a Claude Code plugin that enables autonomous iteration via a stop hook. Claude works on a task, tries to exit, the hook re-injects the prompt, and Claude continues — looping until a completion promise string appears.

```bash
# Start a Ralph loop in a Claude Code session
/ralph-loop "Implement everything in prd.json. Output <promise>COMPLETE</promise> when done."
```

The stop hook intercepts Claude's exit attempt, checks the transcript for the completion promise, and either lets it exit or re-injects the original prompt with quality checks.

## Lesson Scanner Agent

The `agents/lesson-scanner.md` defines a specialized agent that scans codebases for anti-patterns derived from real production failures. It covers 6 scan groups:

1. **Async Traps** — forgotten awaits, concurrent-modification risks
2. **Resource Lifecycle** — subscribe without unsubscribe, lazy-init traps
3. **Silent Failures** — bare except, untracked tasks, lost stack traces
4. **Integration Boundaries** — duplicate function names, path double-nesting, hardcoded localhost
5. **Test Anti-Patterns** — hardcoded count assertions, mocking the module under test
6. **Performance/Filter** — event handlers without domain filters

Reports findings as BLOCKER / SHOULD-FIX / NICE-TO-HAVE with file:line references.

## Lessons Framework

The `docs/lessons/` directory contains a structured framework for capturing and promoting engineering lessons:

- **FRAMEWORK.md** — Methodology (Army CALL OIL taxonomy + PMI + Lean Six Sigma)
- **TEMPLATE.md** — Template for new lessons

Lessons progress through tiers: Observation → Insight → Lesson → Lesson Learned (validated behavioral change).

## State Management

`run-plan.sh` saves state to `.run-plan-state.json` in the working directory:

```json
{
  "plan_file": "docs/plans/feature.md",
  "mode": "headless",
  "current_batch": 5,
  "completed_batches": [1, 2, 3, 4],
  "test_counts": {"1": 10, "2": 25, "3": 42, "4": 58},
  "started_at": "2025-01-15T10:00:00Z",
  "last_quality_gate": {"batch": 4, "passed": true, "test_count": 58}
}
```

Resume with `--resume` — picks up from `current_batch`.

## Requirements

- **Claude Code** (`claude` CLI) — for headless execution
- **bash** 4+ — for arrays and associative features
- **jq** — for state file management
- **git** — for worktree isolation and change detection
- **gh** (optional) — for PR creation in auto-compound pipeline
- **Ollama** (optional) — for report analysis in auto-compound pipeline
- **curl** (optional) — for Telegram notifications

## Configuration

### Telegram Notifications

Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in `~/.env`, then use `--notify`:

```bash
scripts/run-plan.sh plan.md --notify
```

### Custom Quality Gates

```bash
# Use project-specific checks
scripts/run-plan.sh plan.md --quality-gate "make lint && make test"

# Skip quality gates (not recommended)
scripts/run-plan.sh plan.md --quality-gate "true"
```

### Failure Handling

```bash
--on-failure stop    # Default — stop and save state for --resume
--on-failure skip    # Skip failed batch, continue to next
--on-failure retry   # Retry with escalating context (--max-retries N)
```

## Design Principles

1. **Fresh context per batch** — each `claude -p` call starts clean, preventing context degradation
2. **Quality gates are mandatory** — every batch must pass before the next starts
3. **Test count monotonicity** — test count must never decrease between batches
4. **Resumability** — state is saved after every batch; any interruption is recoverable
5. **Orthogonal verification** — bottom-up (anti-patterns) + top-down (integration) catches non-overlapping bug classes

## License

MIT
