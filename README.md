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
| 4d. Execute (loop) | `commands/ralph-loop` | Stop-hook iteration until completion promise |
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
.claude-plugin/                  # Plugin metadata for marketplace
├── plugin.json
└── marketplace.json

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

commands/                        # Claude Code slash commands
├── code-factory.md              # /code-factory — full pipeline
├── create-prd.md                # /create-prd — machine-verifiable PRD
├── run-plan.md                  # /run-plan — in-session batch execution
├── ralph-loop.md                # /ralph-loop — autonomous iteration loop
├── cancel-ralph.md              # /cancel-ralph — stop active loop
└── submit-lesson.md             # /submit-lesson — community lesson PR

agents/                          # Agent definitions (dispatched via Task tool)
└── lesson-scanner.md            # Dynamic anti-pattern scanner from lesson files

hooks/                           # Claude Code event hooks
├── hooks.json                   # Stop hook registration
└── stop-hook.sh                 # Ralph loop stop-hook interceptor

scripts/                         # Bash scripts for headless execution
├── run-plan.sh                  # Main runner (3 modes: headless/team/competitive)
├── lib/                         # run-plan.sh modules
├── setup-ralph-loop.sh          # Ralph loop state file initialization
├── quality-gate.sh              # Composite gate: lesson-check + tests + memory
├── lesson-check.sh              # Dynamic anti-pattern detector (reads lesson files)
├── auto-compound.sh             # Full pipeline: report → PRD → execute → PR
├── entropy-audit.sh             # Detect doc drift, naming violations
├── batch-audit.sh               # Cross-project audit runner
└── batch-test.sh                # Memory-aware cross-project test runner

docs/
├── ARCHITECTURE.md              # Full system architecture
├── CONTRIBUTING.md              # How to submit lessons
└── lessons/
    ├── FRAMEWORK.md             # Lesson capture methodology
    ├── TEMPLATE.md              # Template for new lessons (YAML schema)
    └── 0001-*.md ...            # Starter + community-contributed lessons
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

### From the Marketplace

```bash
# Add as a marketplace source
/plugin marketplace add parthalon025/autonomous-coding-toolkit

# Install the plugin
/plugin install autonomous-coding-toolkit@autonomous-coding-toolkit
```

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

The `commands/` directory contains slash commands for use inside Claude Code sessions:

- **`/code-factory`** — Full pipeline: brainstorm → PRD → plan → execute → verify
- **`/create-prd`** — Generate a PRD with machine-verifiable acceptance criteria
- **`/run-plan`** — In-session batch execution with quality gates
- **`/ralph-loop`** — Start autonomous iteration loop (stop-hook re-injects prompt until completion)
- **`/cancel-ralph`** — Stop an active Ralph loop
- **`/submit-lesson`** — Submit a lesson learned as a community contribution PR

## Ralph Loop (Autonomous Iteration)

The ralph-loop is a Claude Code stop hook that enables autonomous iteration. Claude works on a task, tries to exit, the hook re-injects the prompt, and Claude continues — looping until a completion promise string appears.

```bash
# Start a Ralph loop in a Claude Code session
/ralph-loop "Implement everything in prd.json. Output <promise>COMPLETE</promise> when done."
```

The stop hook (`hooks/stop-hook.sh`) intercepts Claude's exit attempt, checks the transcript for the completion promise, and either lets it exit or re-injects the original prompt with quality checks.

## Community Lessons

The toolkit improves with every user's production failures. Lessons are structured markdown files in `docs/lessons/` with machine-parseable YAML frontmatter. Adding a lesson file automatically adds a check — no code changes needed.

### Two-Tier Enforcement

| Tier | Type | Speed | Tool |
|------|------|-------|------|
| Fast | Syntactic (grep-detectable) | <2 seconds | `scripts/lesson-check.sh` |
| Deep | Semantic (needs context) | Minutes | `agents/lesson-scanner.md` |

### Submitting Lessons

```bash
# Inside a Claude Code session
/submit-lesson "bare except clauses hide failures in production"
```

The command captures your bug, generates a structured lesson file, and opens a PR. See `docs/CONTRIBUTING.md` for details.

### Starter Lessons

The toolkit ships with 6 lessons from real production failures:

| ID | Title | Type | Severity |
|----|-------|------|----------|
| 0001 | Bare exception swallowing | syntactic | blocker |
| 0002 | async def without await | semantic | blocker |
| 0003 | create_task without callback | semantic | should-fix |
| 0004 | Hardcoded test counts | syntactic | should-fix |
| 0005 | sqlite without closing | syntactic | should-fix |
| 0006 | .venv/bin/pip path | syntactic | should-fix |

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

## Attribution

Core skill chain forked from [superpowers](https://github.com/obra/superpowers) by Jesse Vincent / Anthropic. This toolkit extends it with:
- Quality gate pipeline (lesson-check.sh → quality-gate.sh → auto-compound.sh)
- Headless execution engine (run-plan.sh with 3 modes)
- Ralph loop autonomous iteration (stop-hook mechanism)
- Dynamic lesson system with community contribution pipeline
- Lesson-scanner agent for semantic anti-pattern detection
- Machine-verifiable PRD system (tasks/prd.json)

## License

MIT
