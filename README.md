[![CI](https://github.com/parthalon025/autonomous-coding-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/parthalon025/autonomous-coding-toolkit/actions)
[![npm](https://img.shields.io/npm/v/autonomous-coding-toolkit)](https://www.npmjs.com/package/autonomous-coding-toolkit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# Autonomous Coding Toolkit

> **Goal:** Code better than a human on large projects — not by being smarter on any single batch, but by compounding learning across thousands of batches across hundreds of users.

**A learning system for autonomous AI coding.** Fresh context per batch, quality gates between every step, 79 community lessons that prevent the same bug twice, and telemetry that makes the system smarter with every run.

Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (v1.0.33+). Works as a Claude Code plugin (interactive) and npm CLI (headless/CI).

## Install

### npm (recommended)

```bash
npm install -g autonomous-coding-toolkit
```

This puts `act` on your PATH.

### Claude Code Plugin

```bash
# Add the marketplace source
/plugin marketplace add parthalon025/autonomous-coding-toolkit

# Install the plugin
/plugin install autonomous-coding-toolkit@autonomous-coding-toolkit
```

### From Source

```bash
git clone https://github.com/parthalon025/autonomous-coding-toolkit.git
cd autonomous-coding-toolkit
npm link  # puts 'act' on PATH
```

### Platform Notes

| Platform | Status | Notes |
|----------|--------|-------|
| **Linux** | Works out of the box | bash 4+, jq, git required |
| **macOS** | Works with Homebrew bash | macOS ships bash 3.2 — install bash 4+ via `brew install bash`. Also install coreutils for GNU readlink: `brew install coreutils` |
| **Windows** | WSL only | Run `wsl --install`, then use the toolkit inside WSL. Native Windows is not supported |

<details>
<summary>macOS setup</summary>

macOS ships bash 3.2 (2007) due to licensing. The toolkit requires bash 4+ for associative arrays and other features.

```bash
# Install modern bash and GNU coreutils
brew install bash coreutils jq

# Verify
bash --version  # Should show 5.x
```

Homebrew bash installs to `/opt/homebrew/bin/bash` (Apple Silicon) or `/usr/local/bin/bash` (Intel). The `act` CLI invokes scripts via `bash` — as long as Homebrew's bin is on your PATH (which `brew` sets up automatically), scripts will use the correct version.

</details>

## Quick Start

```bash
# Bootstrap your project
act init --quickstart

# Full pipeline — brainstorm → plan → execute → verify → finish
/autocode "Add user authentication with JWT"

# Run a plan headless (fully autonomous, fresh context per batch)
act plan docs/plans/my-feature.md --on-failure retry --notify

# Quality check
act gate --project-root .

# See all commands
act help
```

See [`examples/quickstart-plan.md`](examples/quickstart-plan.md) for a minimal plan you can run in 3 commands.

## The Pipeline

```
Idea → [Roadmap] → Brainstorm → [Research] → PRD → Plan → Execute → Verify → Finish
```

Each stage exists because a specific failure mode demanded it:

| Stage | Problem It Solves | Evidence |
|-------|------------------|----------|
| **Brainstorm** | Agents build the wrong thing correctly | SWE-bench Pro: removing specs = 3x degradation |
| **Research** | Building on assumptions wastes hours | Stage-Gate: stable definitions = 3x success rate |
| **Plan** | Plan quality dominates execution quality ~3:1 | SWE-bench Pro: spec removal = 3x degradation |
| **Execute** | Context degradation is the #1 quality killer | 11/12 models < 50% at 32K tokens |
| **Verify** | Static review misses behavioral bugs | Property-based testing finds ~50x more mutations |

Full evidence with 25+ papers across 16 research reports: [`docs/RESEARCH.md`](docs/RESEARCH.md)

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
- **Node.js** 18+ (for the `act` CLI router)
- **bash** 4+, **jq**, **git**
- Optional: **gh** (PR creation), **curl** (Telegram notifications), **ast-grep** (structural checks)

## Learn More

| Topic | Doc |
|-------|-----|
| Architecture and internals | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Research (25+ papers, 16 reports) | [`docs/RESEARCH.md`](docs/RESEARCH.md) |
| Contributing lessons | [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) |
| Plan file format | [`examples/example-plan.md`](examples/example-plan.md) |
| Execution modes (5 options) | [`docs/ARCHITECTURE.md#system-overview`](docs/ARCHITECTURE.md#system-overview) |

## Attribution

Core skill chain forked from [superpowers](https://github.com/obra/superpowers) by Jesse Vincent / Anthropic. Extended with quality gate pipeline, headless execution, lesson system, MAB routing, and research/roadmap stages.

## Research Sources

The toolkit's design is grounded in peer-reviewed research. Key papers:

- **SWE-bench Pro** (Xia et al., 2025) — 1,865 programming problems; removing specifications degraded agent success from 25.9% to 8.4%
- **Chroma** (Hong et al., 2025) — Long-context coding benchmark; 11 of 12 models scored below 50% accuracy at 32K tokens
- **Lost in the Middle** (Liu et al., Stanford TACL 2024) — Information placed mid-context suffers up to 20 percentage point accuracy loss
- **OOPSLA 2025** — Property-based testing finds ~50x more mutations per test than traditional unit tests
- **Cooper Stage-Gate** — Projects with stable, upfront definitions are 3x more likely to succeed

16 research reports synthesizing 25+ papers: [`docs/RESEARCH.md`](docs/RESEARCH.md)

## License

MIT
