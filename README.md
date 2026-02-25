[![CI](https://github.com/parthalon025/autonomous-coding-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/parthalon025/autonomous-coding-toolkit/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/parthalon025/autonomous-coding-toolkit/releases/tag/v1.0.0)

# Autonomous Coding Toolkit

> **Goal:** Code better than a human on large projects — not by being smarter on any single batch, but by compounding learning across thousands of batches across hundreds of users.

**A learning system for autonomous AI coding.** Fresh context per batch, quality gates between every step, 79 community lessons that prevent the same bug twice, and telemetry that makes the system smarter with every run.

Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (v1.0.33+). Works as a Claude Code plugin (interactive) and npm CLI (headless/CI).

## What It Does

```
You write a plan → the toolkit executes it batch-by-batch with:
  - Fresh 200k context window per batch (no accumulated degradation)
  - Quality gates between every batch (tests + anti-pattern scan + memory check)
  - Machine-verifiable completion (every criterion is a shell command)
```

## Install (2 commands)

```bash
# 1. Add the marketplace source
/plugin marketplace add parthalon025/autonomous-coding-toolkit

# 2. Install the plugin
/plugin install autonomous-coding-toolkit@autonomous-coding-toolkit
```

<details>
<summary>Alternative: standalone scripts (no plugin system)</summary>

```bash
git clone https://github.com/parthalon025/autonomous-coding-toolkit.git
cd autonomous-coding-toolkit
scripts/run-plan.sh --help
```

</details>

## Quick Start

```bash
# Full pipeline — brainstorm → plan → execute → verify → finish
/autocode "Add user authentication with JWT"

# Or run a plan headless (fully autonomous, fresh context per batch)
scripts/run-plan.sh docs/plans/my-feature.md --on-failure retry --notify
```

See [`examples/quickstart-plan.md`](examples/quickstart-plan.md) for a minimal plan you can run in 3 commands.

## The Pipeline

```
Idea → [Roadmap] → Brainstorm → [Research] → PRD → Plan → Execute → Verify → Finish
```

Each stage exists because a specific failure mode demanded it:

| Stage | Problem It Solves | Evidence |
|-------|------------------|----------|
| **Brainstorm** | Agents build the wrong thing correctly — spec misunderstanding is the dominant failure mode | SWE-bench Pro (1,865 problems): removing specs degraded success from 25.9% to 8.4% |
| **Research** | Building on assumptions wastes hours | Cooper Stage-Gate: projects with stable definitions are 3x more likely to succeed |
| **Plan** | Plan quality dominates execution quality ~3:1 | SWE-bench Pro: spec removal = 3x degradation |
| **Execute** | Context degradation is the #1 quality killer | Chroma (Hong et al., 2025): 11/12 models < 50% at 32K tokens; Liu et al. (Stanford, TACL 2024): up to 20pp mid-context accuracy loss |
| **Verify** | Static review misses behavioral bugs | OOPSLA 2025: property-based testing finds ~50x more mutations per test |

Full evidence table with all 25 papers: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

## How It Compares

| Tool | Approach | This Toolkit's Difference |
|------|----------|--------------------------|
| Claude Code `/plan` | Built-in planning | No quality gates, no fresh context per batch, no lesson system |
| Aider | Interactive pair programming | Aider is conversational; this is batch-autonomous with gates |
| Cursor Agent | IDE-integrated agent | No headless mode, no batch isolation |
| SWE-agent | Autonomous GitHub issue solver | Single-issue scope; this handles multi-batch plans with state |

**Core differentiators:** (1) fresh context per batch, (2) machine-verifiable quality gates, (3) compounding lesson system, (4) headless unattended execution.

## Quality Gates

Mandatory between every batch:

1. Lesson check (<2s, grep-based anti-pattern scan)
2. ast-grep patterns (5 structural checks)
3. Test suite (auto-detected: pytest / npm test / make test)
4. Memory check (warns if < 4GB available)
5. Test count regression (tests only go up)
6. Git clean (all changes committed)

## Community Lessons

79 lessons across 6 failure clusters, learned from production bugs. Adding a lesson file to `docs/lessons/` automatically adds a check — no code changes needed.

Submit new lessons via `/submit-lesson` or [open an issue](https://github.com/parthalon025/autonomous-coding-toolkit/issues/new?template=lesson_submission.md).

## Requirements

- **Claude Code** v1.0.33+ (`claude` CLI)
- **bash** 4+, **jq**, **git**
- Optional: **gh** (PR creation), **curl** (Telegram notifications)

## Learn More

| Topic | Doc |
|-------|-----|
| Architecture, evidence, internals | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Contributing lessons | [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) |
| Plan file format | [`examples/example-plan.md`](examples/example-plan.md) |
| Execution modes (5 options) | [`docs/ARCHITECTURE.md#system-overview`](docs/ARCHITECTURE.md#system-overview) |

## Attribution

Core skill chain forked from [superpowers](https://github.com/obra/superpowers) by Jesse Vincent / Anthropic. Extended with quality gate pipeline, headless execution, lesson system, MAB routing, and research/roadmap stages.

## License

MIT
