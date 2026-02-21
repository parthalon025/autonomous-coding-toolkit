# Autonomous Coding Toolkit

Scripts and frameworks for running AI coding agents autonomously — headless batch execution, quality gates, competitive dual-track, and a lessons-learned feedback loop.

Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) but the patterns are model-agnostic.

## What This Does

You write a plan. The toolkit executes it batch-by-batch without you at the keyboard:

```
Plan file (markdown) --> run-plan.sh --> claude -p per batch --> quality gates --> done
```

Each batch gets a fresh context window. Quality gates run between batches. Failed batches retry or stop. Progress is saved to a state file so you can resume.

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

## Architecture

```
run-plan.sh                     # Main entry point — 3 execution modes
├── lib/run-plan-parser.sh      # Parse ## Batch N / ### Task M from markdown
├── lib/run-plan-state.sh       # JSON state file — resume, test counts
├── lib/run-plan-quality-gate.sh # Test regression detection + git clean check
├── lib/run-plan-notify.sh      # Telegram notifications (optional)
├── lib/run-plan-prompt.sh      # Build self-contained prompts for claude -p

quality-gate.sh                 # Composite gate: lesson check + tests + memory
lesson-check.sh                 # Syntactic anti-pattern detector (grep-based, <2s)
auto-compound.sh                # Full pipeline: report → analyze → PRD → execute → PR
analyze-report.sh               # LLM-powered report triage (picks #1 priority)
entropy-audit.sh                # Detect doc drift, naming violations, dead refs
batch-audit.sh                  # Run audits across multiple project repos
batch-test.sh                   # Memory-aware cross-project test runner
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

## Claude Commands

The `.claude/commands/` directory contains commands for use inside Claude Code sessions:

- **`/code-factory`** — Full pipeline: brainstorm → PRD → plan → execute → verify
- **`/create-prd`** — Generate a PRD with machine-verifiable acceptance criteria (every criterion is a shell command)

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
