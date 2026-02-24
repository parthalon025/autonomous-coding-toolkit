# Autonomous Coding Toolkit

A complete system for running AI coding agents autonomously with quality gates, fresh-context execution, and machine-verifiable completion.

## How It Works

This toolkit implements an **autonomous coding pipeline**: you write a plan in markdown, the system executes it batch-by-batch with a fresh AI context per batch, quality gates between batches, and machine-verifiable acceptance criteria.

### The Skill Chain

Skills are loaded by Claude Code and define HOW to execute each stage. The `autocode` skill orchestrates the full chain:

```
/autocode → brainstorming → PRD → writing-plans → using-git-worktrees → [execution mode] → verification-before-completion → finishing-a-development-branch
```

| Stage | Skill | Purpose |
|-------|-------|---------|
| 1. Design | `brainstorming` | Explore intent → design → approval before code |
| 2. Plan | `writing-plans` | TDD-structured tasks at 2-5 minute granularity |
| 3. Isolate | `using-git-worktrees` | Isolated workspace with safety verification |
| 4a. Execute (same session) | `subagent-driven-development` | Fresh subagent per task + two-stage review |
| 4b. Execute (separate session) | `executing-plans` | Batch execution with human review checkpoints |
| 4c. Execute (headless) | `scripts/run-plan.sh` | `claude -p` per batch, fully autonomous |
| 4c+. Execute (MAB) | `scripts/run-plan.sh --mab` | Competing agents via Thompson Sampling |
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

## Directory Layout

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
├── lib/                         # run-plan.sh modules (parser, state, prompt, context, routing, scoring)
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
    ├── 0001-*.md through 0006-*.md  # Starter lessons
    └── ...                      # Community-contributed lessons

examples/
├── example-plan.md              # Sample implementation plan
└── example-prd.json             # Sample PRD with shell-command criteria
```

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

## Quality Gates

Quality gates are mandatory between every batch. The default gate runs:

1. **Lesson check** — syntactic anti-pattern scan (grep-based, <2s)
2. **Test suite** — auto-detected (pytest / npm test / make test)
3. **Memory check** — warn if < 4GB available

Additionally enforced:
- **Test count regression** — tests only go up between batches
- **Git clean** — all changes committed before next batch

Advanced options:
- **`--sample N`** — parallel patch sampling: spawns N candidates with batch-type-aware prompt variants, scores them, and picks the winner. Uses multi-armed bandit learning from `logs/sampling-outcomes.json`.
- **Auto-sampling** — automatically enables on retry (`SAMPLE_ON_RETRY`) and critical batches (`SAMPLE_ON_CRITICAL`), with memory guard to prevent OOM.
- **Batch-type classification** — `classify_batch_type()` categorizes batches (new-file, refactoring, integration, test-only) for prompt variant selection.
- **AGENTS.md** — auto-generated per worktree with plan metadata, tool permissions, and batch table for agent awareness.
- **Per-batch context injection** — assembles targeted context (failure patterns, prior batch summaries, referenced files) within a 6000-char budget and injects into CLAUDE.md before each batch.
- **ast-grep patterns** — 5 patterns in `scripts/patterns/` (bare-except, empty-catch, async-no-await, retry-loop-no-backoff, hardcoded-localhost).
- **`--mab`** — Multi-Armed Bandit mode: runs two competing strategies (superpowers vs ralph) in parallel worktrees, LLM judge picks winner with quality gate override, Thompson Sampling routes future batches. Human calibration for first 10 runs.

## Community Lessons

The lesson system is dynamic — adding a lesson file automatically adds a check. No code changes needed.

- **Syntactic lessons** (grep-detectable) → `scripts/lesson-check.sh` runs them in <2s as a quality gate
- **Semantic lessons** (need AI context) → `agents/lesson-scanner.md` picks them up at verification time

Submit new lessons via `/submit-lesson` or open a PR. See `docs/CONTRIBUTING.md`.

## State & Persistence

Three mechanisms prevent data loss across context resets:

- **`.run-plan-state.json`** — execution state (completed batches, test counts). Enables `--resume`.
- **`progress.txt`** — append-only discovery log. Read at start of each batch for cross-context memory.
- **`tasks/prd.json`** — machine-verifiable acceptance criteria. Every criterion is a shell command (exit 0 = pass).
- **`logs/failure-patterns.json`** — cross-run failure learning (failure types, frequencies, winning fixes per batch title).
- **`logs/routing-decisions.log`** — execution traceability (mode selection, model routing, parallelism scores).
- **`logs/sampling-outcomes.json`** — prompt variant learning (which sampling strategy won per batch type).
- **`logs/strategy-perf.json`** — MAB win/loss counters per strategy per batch type (Thompson Sampling data).
- **`logs/mab-lessons.json`** — patterns observed by the MAB judge agent (auto-promoted at 3+ occurrences).

## Design Principles

1. **Fresh context per unit of work** — context degradation is the #1 quality killer
2. **Machine-verifiable gates** — every gate is a command that exits 0 or non-zero
3. **Test count monotonicity** — tests only go up
4. **State survives interruption** — every state transition persisted to disk
5. **Lessons compound** — every bug becomes an automated check over time

## Scope Tags
language:bash, project:autonomous-coding-toolkit

## Conventions

- Plans go in `docs/plans/` with format `YYYY-MM-DD-description.md`
- Skills are rigid — follow exactly, don't adapt away discipline
- Brainstorming is mandatory before any new feature — no exceptions
- No completion claims without fresh verification evidence

## Run-Plan: Batch 5


### Recent Commits
504dd75 feat: add validate-plugin, validate-hooks, validate-all with tests
aca7912 fix: add SIGPIPE trap — confirmed root cause of silent death (exit 141)
c91e272 fix: add signal handling and non-critical command guards to run-plan.sh
404ade0 feat: add validate-plans.sh and validate-prd.sh with tests
4bc8ca4 docs: add Telegram notification format spec

### Progress Notes
| validate-plugin.sh | 77 (new) |
| validate-hooks.sh | 68 (new) |
| validate-all.sh | 53 (new) |

### Decisions
- validate-all runs validators silently (>/dev/null 2>&1) and reports only PASS/FAIL — individual validators can be run standalone for details
- validate-all skips missing validators with SKIP instead of failing — forward-compatible with future validators
- validate-plugin extracts marketplace version from `.plugins[0].version` (first plugin entry)
- validate-hooks uses jq recursive descent (`.. | objects | select(.type == "command")`) to find all command hooks regardless of nesting depth
- Pre-existing validate-skills failures (code-factory missing SKILL.md, using-git-worktrees referencing CLAUDE.md) — validate-all test accounts for this by using --warn for the pass test and verifying FAIL reporting separately
