[![CI](https://github.com/parthalon025/autonomous-coding-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/parthalon025/autonomous-coding-toolkit/actions)
[![npm](https://img.shields.io/npm/v/autonomous-coding-toolkit)](https://www.npmjs.com/package/autonomous-coding-toolkit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# Autonomous Coding Toolkit

**Requires [Claude Code](https://docs.anthropic.com/en/docs/claude-code).** Built specifically for the Claude Code + Claude API ecosystem.

A collection of scripts, skills, and infrastructure for agent-driven software development. It implements a structured pipeline — from brainstorming through verified delivery — with quality gates between every batch, fresh AI context per execution unit, and a compounding lesson system that turns production bugs into automated checks.

Works as a Claude Code plugin (interactive sessions) or as standalone Bash scripts for headless, unattended CI/CD execution. The standalone scripts (`scripts/`) have no Claude Code dependency and integrate directly with any CI system that respects exit codes.

## Who This Is For

- **Claude Code users who want structured, quality-gated autonomous coding workflows** — the full Code Factory pipeline (brainstorm → PRD → plan → execute → verify) without building the scaffolding from scratch
- **Teams using AI-assisted development who find agents going off-track or producing inconsistent output** — quality gates, fresh-context execution, and machine-verifiable acceptance criteria address the root causes
- **Developers who want CI/CD integration without Claude Code** — the standalone Bash scripts (`quality-gate.sh`, `lesson-check.sh`, `run-plan.sh`) work independently and exit 0/1 for any CI system

> **Core insight:** Plan quality dominates execution quality at roughly a 3:1 ratio. The pipeline enforces rigor at the stages where agent failures actually originate — not just at code review.

---

## The Code Factory Pipeline

```
Brainstorm → Research → PRD → Plan → Worktree → Execute → Verify → AAR → Finish
```

Each stage exists because a specific failure mode demanded it:

| Stage          | What It Does                                                 | Problem It Prevents                                |
| -------------- | ------------------------------------------------------------ | -------------------------------------------------- |
| **Brainstorm** | Explore intent, surface edge cases, get approval before code | Agents building the wrong thing correctly          |
| **Research**   | Structured investigation producing durable artifacts         | Decisions made on stale assumptions                |
| **PRD**        | Machine-verifiable acceptance criteria (`tasks/prd.json`)    | "Done" meaning different things to agent and human |
| **Plan**       | TDD-structured tasks at 2–5 minute granularity               | Plans too coarse for quality gate insertion        |
| **Worktree**   | Isolated Git worktree with safety pre-checks                 | Concurrent agents corrupting shared staging area   |
| **Execute**    | Fresh Claude context per batch, quality gate between each    | Context degradation degrading output quality       |
| **Verify**     | Evidence-based gate: run commands, read output               | Completion claims without verification             |
| **AAR**        | After-action review, lesson capture                          | Repeating the same class of bug                    |
| **Finish**     | PR creation, worktree cleanup                                | Lingering branches and broken editable installs    |

Research basis: SWE-bench Pro (spec removal → 3x degradation), Context Rot (11/12 models below 50% at 32K tokens). Full citations in [`docs/RESEARCH.md`](docs/RESEARCH.md).

---

## Install

### npm (recommended)

```bash
npm install -g autonomous-coding-toolkit
```

Puts `act` on your PATH.

### Claude Code Plugin

```bash
/plugin marketplace add parthalon025/autonomous-coding-toolkit
/plugin install autonomous-coding-toolkit@autonomous-coding-toolkit
```

### From Source

```bash
git clone https://github.com/parthalon025/autonomous-coding-toolkit.git
cd autonomous-coding-toolkit
npm link
```

### Platform Requirements

| Platform    | Status    | Notes                                                                    |
| ----------- | --------- | ------------------------------------------------------------------------ |
| **Linux**   | Supported | bash 4+, jq, git required                                                |
| **macOS**   | Supported | Install bash 4+ via `brew install bash coreutils` — macOS ships bash 3.2 |
| **Windows** | WSL only  | `wsl --install`, then use from inside WSL                                |

---

## Quick Start

```bash
# Bootstrap a project
act init --quickstart

# Full pipeline — interactive, with brainstorming gate
/autocode "Add paginated list endpoint with cursor-based navigation"

# Execute a plan headless — fresh context per batch, quality gates throughout
act plan docs/plans/my-feature.md --on-failure retry --notify

# Run the quality gate standalone
act gate --project-root .

# See all commands
act help
```

See [`examples/quickstart-plan.md`](examples/quickstart-plan.md) for a minimal two-batch plan you can run in three commands.

---

## Scripts Reference

All scripts live in `scripts/`. They can be invoked directly (standalone) or through the `act` CLI.

### `run-plan.sh` — Headless batch executor

Parses a markdown plan file and executes each batch via `claude -p`, with a quality gate between batches and persistent state across context resets.

```bash
# Execute a plan from the beginning
scripts/run-plan.sh docs/plans/2026-02-20-feature.md

# Resume after an interruption
scripts/run-plan.sh --resume --worktree /path/to/worktree

# Retry failures, start from batch 3, send Telegram notifications
scripts/run-plan.sh docs/plans/feature.md --start-batch 3 --on-failure retry --notify

# Multi-Armed Bandit mode: two competing strategies, LLM judge picks winner
scripts/run-plan.sh docs/plans/feature.md --mab

# Parallel patch sampling: generate N candidates per batch, score, take winner
scripts/run-plan.sh docs/plans/feature.md --sample 3
```

**Key options:**

| Flag                                 | Description                                                  |
| ------------------------------------ | ------------------------------------------------------------ |
| `--mode headless\|team\|competitive` | Execution strategy (default: headless)                       |
| `--on-failure stop\|skip\|retry`     | Batch failure handling                                       |
| `--max-retries N`                    | Retry limit per batch (default: 2)                           |
| `--start-batch N` / `--end-batch N`  | Execute a range of batches                                   |
| `--resume`                           | Continue from saved `.run-plan-state.json`                   |
| `--mab`                              | Thompson Sampling routing between competing agent strategies |
| `--sample N`                         | Spawn N candidate patches per batch, score and pick winner   |
| `--max-budget <dollars>`             | Abort if cumulative cost exceeds limit                       |
| `--verify`                           | Run verification pass after all batches complete             |
| `--notify`                           | Send Telegram notifications on completion/failure            |

State survives interruption via `.run-plan-state.json`. Execution context is assembled per-batch into a 6,000-character budget injected into CLAUDE.md before each Claude invocation.

---

### `quality-gate.sh` — Composite quality gate

Runs all checks in sequence, fails fast on the first failure. Designed to run between every batch in the Ralph loop or as a standalone pre-commit gate.

```bash
# Full gate (lesson check + lint + tests + memory warning)
scripts/quality-gate.sh --project-root .

# Fast inner-loop mode (skip lint and license audit)
scripts/quality-gate.sh --project-root . --quick

# Include dependency license audit
scripts/quality-gate.sh --project-root . --with-license
```

**Checks in order:**

| Step                | What It Does                                                                                            | Fails Gate?  |
| ------------------- | ------------------------------------------------------------------------------------------------------- | ------------ |
| Toolkit validation  | Runs `validate-all.sh` if present (toolkit self-check)                                                  | Yes          |
| Lesson check        | Scans changed files for known anti-patterns                                                             | Yes          |
| Lint                | `ruff` (Python) or `eslint` (Node), if configured                                                       | Yes          |
| Structural analysis | `ast-grep` patterns for bare-except, empty-catch, async-no-await, retry-no-backoff, hardcoded-localhost | Advisory     |
| Module size         | Flags files over 300 lines                                                                              | Advisory     |
| Test suite          | Auto-detects pytest / npm test / make test / bash test runner                                           | Yes          |
| License audit       | Flags GPL/AGPL dependencies (`--with-license` only)                                                     | Yes          |
| Memory check        | Warns if available RAM < 4 GB                                                                           | Warning only |

Exit 0 if all blocking checks pass. Telemetry is recorded automatically when called from `run-plan.sh` context.

---

### `lesson-check.sh` — Anti-pattern detector

Scans files for syntactic patterns extracted from the lessons database. Dynamic: adding a lesson automatically adds its check, no code changes needed.

```bash
# Check git-changed files in current directory (default)
scripts/lesson-check.sh

# Check specific files
scripts/lesson-check.sh src/api.py src/db.py

# Show detected project scope (scope-aware filtering)
scripts/lesson-check.sh --show-scope

# Override scope manually
scripts/lesson-check.sh --scope "language:python,domain:myproject" src/

# Bypass scope filtering — run all lessons
scripts/lesson-check.sh --all-scopes
```

Output format: `file:line: [lesson-N] title` — same as compiler errors, composable with other tools.

When `lessons-db` is installed (recommended), checks are sourced from the canonical SQLite database. Falls back to reading detection patterns directly from `docs/lessons/*.md` if the database is unavailable.

---

### `auto-compound.sh` — Automated Code Factory pipeline

Fully automated end-to-end pipeline: reads a report, uses an LLM to identify the top priority, generates a PRD, creates a branch, runs the Ralph loop to completion, and opens a PR.

```bash
# Analyze latest report and execute the full pipeline
scripts/auto-compound.sh /path/to/project

# Point at a specific report
scripts/auto-compound.sh /path/to/project --report reports/2026-03-08-audit.md

# Preview what would happen without executing
scripts/auto-compound.sh /path/to/project --dry-run

# Limit iterations in case of runaway loop
scripts/auto-compound.sh /path/to/project --max-iterations 15
```

Pipeline stages: `analyze-report.sh` → `/create-prd` → `git checkout -b compound/<slug>` → Ralph loop with quality gates → `gh pr create`.

---

### `analyze-report.sh` — LLM-powered priority extraction

Reads any markdown report (test failures, error logs, user feedback, metrics) and uses a local LLM to identify the single highest-impact fix. Outputs structured JSON consumed by `auto-compound.sh`.

```bash
# Analyze a report, output analysis.json
scripts/analyze-report.sh reports/weekly-audit.md

# Use a specific model
scripts/analyze-report.sh reports/weekly-audit.md --model qwen2.5-coder:14b

# Preview prompt and model selection without submitting
scripts/analyze-report.sh reports/weekly-audit.md --dry-run
```

Output (`analysis.json`):

```json
{
  "priority": "Fix N+1 query in entity list endpoint",
  "reasoning": "Causes 10s+ page loads for large datasets. Affects all users. Two-line fix.",
  "prd_outline": ["...", "..."]
}
```

Ranking order: revenue impact > user-facing bugs > developer experience > tech debt. Submits through the local Ollama queue for serialized execution. Default model: `deepseek-r1:8b`.

---

### `entropy-audit.sh` — Codebase entropy detector

Detects documentation drift, naming violations, dead references, and uncommitted work. Designed to run on a schedule (e.g., weekly systemd timer) to prevent codebase entropy from accumulating silently.

```bash
# Audit a single project
scripts/entropy-audit.sh --project my-project

# Audit all projects in the projects directory
scripts/entropy-audit.sh --all

# Auto-fix dead references in CLAUDE.md (reserved, coming soon)
scripts/entropy-audit.sh --project my-project --fix
```

**Checks:**

| Check                   | What It Detects                                     |
| ----------------------- | --------------------------------------------------- |
| Dead references         | Files mentioned in `CLAUDE.md` that no longer exist |
| File size violations    | Source files over 300 lines                         |
| Naming convention drift | camelCase Python functions (should be snake_case)   |
| Import hygiene          | Likely unused imports in Python files               |
| Uncommitted work        | Untracked or modified files in the working tree     |

Outputs per-project markdown reports to `/tmp/entropy-audit-<timestamp>/`.

---

### `batch-audit.sh` — Cross-project audit runner

Dispatches a Claude agent to run `/audit` against every project repo and collects the results.

```bash
# Run stale-refs audit across all projects (default focus)
scripts/batch-audit.sh ~/Documents/projects

# Focus on a specific audit type
scripts/batch-audit.sh ~/Documents/projects security
scripts/batch-audit.sh ~/Documents/projects test-coverage
scripts/batch-audit.sh ~/Documents/projects lessons

# Available focus options: stale-refs | security | test-coverage | naming | lessons | full
```

Results saved to `/tmp/batch-audit-<timestamp>/<project>.txt`. View all: `cat /tmp/batch-audit-*/*.txt`.

---

### `batch-test.sh` — Memory-aware cross-project test runner

Runs the test suite for every project in a directory. Auto-detects the test runner per project (pytest, npm test, make test). Checks available memory before each suite and reduces parallelism if below 4 GB.

```bash
# Run tests for all projects
scripts/batch-test.sh ~/Documents/projects

# Run tests for one specific project
scripts/batch-test.sh ~/Documents/projects my-project
```

Reports a pass/fail/skip summary across all projects. Exits non-zero if any project fails.

---

## Quality Gates — How They Integrate

Quality gates run between every batch in headless execution. They are machine-verifiable: every check exits 0 (pass) or non-zero (fail). No subjective judgment.

```
Batch N completes
      ↓
quality-gate.sh --project-root .
  ├─ lesson-check.sh (changed files)        ← blocks on violation
  ├─ ruff / eslint                          ← blocks on error
  ├─ ast-grep structural patterns           ← advisory
  ├─ pytest / npm test / make test          ← blocks on failure
  ├─ license-check.sh (--with-license)      ← blocks on GPL/AGPL
  └─ memory check                           ← advisory
      ↓
Batch N+1 executes
```

**Test count monotonicity:** The runner tracks the test count after each batch. If it goes down, execution stops. Tests only go up.

**Git cleanliness:** All changes must be committed before the next batch executes. Prevents context bleed across batch boundaries.

**CI integration:** `quality-gate.sh` exits 0/1 and is composable with any CI system. Add it as a step in your GitHub Actions workflow:

```yaml
- name: Quality gate
  run: scripts/quality-gate.sh --project-root .
```

---

## Lesson System

The lesson system converts production bugs into automated checks. Each lesson describes a failure pattern with a grep-detectable regex. Adding a lesson file adds a check — no code changes required.

Lessons are organized across six failure clusters:

| Cluster                     | Description                                |
| --------------------------- | ------------------------------------------ |
| A — Silent Failures         | Errors swallowed without logging           |
| B — Integration Boundaries  | Bugs hiding at layer seams                 |
| C — Cold Start              | Works steady-state, fails on restart       |
| D — Specification Drift     | Agent builds the wrong thing correctly     |
| E — Context & Retrieval     | Information available but not surfaced     |
| F — Planning & Control Flow | Wrong decomposition contaminates execution |

**Syntactic lessons** (grep-detectable) are run by `lesson-check.sh` in under 2 seconds as part of every quality gate.

**Semantic lessons** (requiring AI interpretation) are picked up by the `lesson-scanner` agent at verification time.

Submit a lesson: `/submit-lesson` or open a [PR](https://github.com/parthalon025/autonomous-coding-toolkit/issues/new?template=lesson_submission.md). See [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).

---

## Skills and Commands

Skills define how to execute each pipeline stage. They are loaded by Claude Code and invoked before any work begins.

| Skill                            | Stage         | Purpose                                        |
| -------------------------------- | ------------- | ---------------------------------------------- |
| `autocode`                       | Full pipeline | Orchestrates all 9 stages                      |
| `brainstorming`                  | Design        | Intent exploration and approval gate           |
| `research`                       | Research      | Structured investigation to durable artifacts  |
| `writing-plans`                  | Plan          | TDD-structured tasks at 2–5 min granularity    |
| `using-git-worktrees`            | Isolate       | Safe workspace creation with pre-checks        |
| `subagent-driven-development`    | Execute       | Fresh subagent per task, two-stage review      |
| `executing-plans`                | Execute       | Batch execution with human review checkpoints  |
| `verification-before-completion` | Verify        | Evidence-based gate: run commands, read output |
| `finishing-a-development-branch` | Finish        | PR + worktree cleanup                          |
| `systematic-debugging`           | Debug         | Root cause before fix, always                  |
| `dispatching-parallel-agents`    | Parallel      | 2+ independent tasks in parallel               |
| `test-driven-development`        | All           | Red-Green-Refactor cycle                       |

**Slash commands:** `/autocode`, `/run-plan`, `/create-prd`, `/ralph-loop`, `/cancel-ralph`, `/submit-lesson`

---

## State and Persistence

The toolkit is designed to survive interruption at any point:

| File                          | Purpose                                                                    |
| ----------------------------- | -------------------------------------------------------------------------- |
| `.run-plan-state.json`        | Completed batches, test counts, cost. Enables `--resume`.                  |
| `progress.txt`                | Append-only discovery log. Read at start of each batch.                    |
| `tasks/prd.json`              | Machine-verifiable acceptance criteria. Each criterion is a shell command. |
| `logs/failure-patterns.json`  | Cross-run failure learning per batch title.                                |
| `logs/sampling-outcomes.json` | Prompt variant win rates per batch type (MAB learning).                    |
| `logs/strategy-perf.json`     | Thompson Sampling win/loss counters per strategy.                          |

---

## Tech Stack

| Layer               | Technology                                          |
| ------------------- | --------------------------------------------------- |
| Scripts             | Bash 4+ (modular lib/ structure)                    |
| LLM execution       | Claude Code (`claude -p` headless)                  |
| Local LLM analysis  | Ollama + ollama-queue (serialized, port 7683)       |
| Structural analysis | ast-grep (optional)                                 |
| Lesson database     | SQLite via `lessons-db` CLI (optional, recommended) |
| Notifications       | Telegram Bot API (optional)                         |
| CI integration      | Any system that respects exit codes                 |

---

## Requirements

- **Claude Code** v1.0.33+ (`claude` CLI)
- **Node.js** 18+ (for the `act` CLI)
- **bash** 4+, **jq**, **git**
- Optional: **gh** (PR creation), **ast-grep** (structural checks), **lessons-db** (lesson database), **Ollama** (local LLM analysis)

---

## Directory Layout

```
scripts/          Bash scripts for headless execution and quality gates
├── run-plan.sh           Main headless executor
├── quality-gate.sh       Composite quality gate
├── lesson-check.sh       Anti-pattern detector
├── auto-compound.sh      Automated full-pipeline runner
├── analyze-report.sh     LLM priority extraction from reports
├── entropy-audit.sh      Codebase entropy detector
├── batch-audit.sh        Cross-project audit runner
├── batch-test.sh         Memory-aware cross-project test runner
└── lib/                  Modular library functions

skills/           Claude Code skills (loaded via Skill tool)
commands/         Claude Code slash commands
agents/           Agent definitions (dispatched via Task tool)
hooks/            Claude Code event hooks
policies/         Positive pattern definitions (policy-check.sh)
docs/             Architecture, research, contributing guides
examples/         Sample plan, PRD, roadmap, and quickstart files
```

---

## Learn More

| Topic                                   | Doc                                                          |
| --------------------------------------- | ------------------------------------------------------------ |
| Architecture and internals              | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)               |
| Research basis (25+ papers, 16 reports) | [`docs/RESEARCH.md`](docs/RESEARCH.md)                       |
| Contributing lessons                    | [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md)               |
| Plan file format                        | [`examples/example-plan.md`](examples/example-plan.md)       |
| PRD format                              | [`examples/example-prd.json`](examples/example-prd.json)     |
| Quickstart plan                         | [`examples/quickstart-plan.md`](examples/quickstart-plan.md) |

---

## Attribution

Core skill chain forked from [superpowers](https://github.com/obra/superpowers) by Jesse Vincent / Anthropic. Extended with quality gate pipeline, headless execution, lesson system, MAB routing, and research and roadmap stages.

## License

MIT
