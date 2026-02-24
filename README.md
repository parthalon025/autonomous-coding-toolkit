# Autonomous Coding Toolkit

A complete system for running AI coding agents autonomously with quality gates, fresh-context execution, and machine-verifiable completion.

Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Includes skills, agents, scripts, and plugins that implement an end-to-end autonomous coding pipeline.

## Why This Exists

AI coding agents degrade as context grows. By batch 5, they're hallucinating imports, forgetting requirements, and generating slop. This toolkit solves the problem at the architecture level:

- **Fresh context per batch** — each unit of work starts with a clean 200k context window
- **Quality gates between every batch** — tests, anti-pattern scans, and test-count regression checks prevent cascading errors
- **Learned prompt selection** — multi-armed bandit picks the best prompt strategy per batch type from past outcomes
- **Machine-verifiable completion** — every acceptance criterion is a shell command (exit 0 = pass)
- **Lessons compound** — every production bug becomes an automated check that prevents regressions

## Quick Start

```bash
# Install the plugin
/plugin install autonomous-coding-toolkit@autonomous-coding-toolkit

# Full pipeline — brainstorm → PRD → plan → execute → verify → finish
/autocode "Add user authentication with JWT"

# Or run a plan headless (fully autonomous, fresh context per batch)
scripts/run-plan.sh docs/plans/my-feature.md --on-failure retry --notify
```

See `examples/quickstart-plan.md` for a minimal plan that reaches first quality-gated execution in 3 commands.

## The Pipeline

```
Idea → [Roadmap] → Brainstorm → [Research] → PRD → Plan → Execute → Verify → Finish
```

Each stage exists because a specific failure mode demanded it. Evidence from a 25-paper synthesis:

| Stage | Why It Exists | Evidence |
|-------|--------------|----------|
| **Roadmap** | Multi-feature work without dependency ordering causes rework when Feature B needs Feature A's output | All 18 frameworks reviewed (JP 5-0, McKinsey, IDEO, Toyota A3, Stage-Gate) enforce a formal gate between problem understanding and solution design |
| **Brainstorm** | Agents build the wrong thing correctly — spec misunderstanding is 60%+ of failures for strong models on novel tasks | SWE-EVO (2025), 48 tasks; SWE-bench Pro (Scale AI, 2025), 1,865 enterprise problems — removing specs degraded GPT-5 from 25.9% to 8.4% |
| **Research** | Building on assumptions wastes hours; every framework examined requires a durable research artifact before detailed design | 18-framework systematic review (military, consulting, design, manufacturing); Cooper Stage-Gate: projects with stable definitions are 3x more likely to succeed |
| **PRD** | Vague criteria ("works correctly") can't be machine-verified — every criterion must be a shell command (exit 0 = pass) | AI code has distinct bug distribution; quality gates miss 33-67% of AI-specific patterns without explicit criteria (Tambon et al., 2024, 333 bugs analyzed) |
| **Plan** | Plan quality dominates execution quality at ~3:1 — investing in plan structure pays more than optimizing execution | SWE-bench Pro (Scale AI, 2025): spec removal = 3x degradation; OpenAI GPT-4.1 guide: +4% from structured planning prompts alone |
| **Execute** | Context degradation is the #1 quality killer — 11 of 12 models drop below 50% performance at 32K tokens with distractors | Chroma "Context Rot" (Hong et al., 2025), 12 models; Liu et al. "Lost in the Middle" (Stanford, TACL 2024, 1000+ citations): up to 20pp accuracy loss mid-context |
| **Verify** | One live integration test catches more behavioral bugs than six static reviewers — never claim done without running commands | OOPSLA 2025 (40 Python projects): property-based testing finds ~50x more mutations per test; combining PBT + example-based improves bug detection from 68.75% to 81.25% |
| **Finish** | Unfinished branches accumulate — explicit merge/PR/keep/discard forces a decision | Process discipline; every successful quality system at scale enforces explicit lifecycle completion |

Hard gates between stages — you cannot proceed until exit criteria are met.

## Execution Modes

| Mode | Command | Best For |
|------|---------|----------|
| In-session | `/autocode` or `/run-plan` | Plans with 1-3 batches, human review between batches |
| Subagent | `subagent-driven-development` skill | 5-15 independent tasks, fresh agent per task + two-stage review |
| Headless | `scripts/run-plan.sh plan.md` | 4+ batches, fully autonomous, `claude -p` per batch |
| Ralph Loop | `/ralph-loop "task"` | Iterate until done, stop-hook re-injects prompt |
| MAB | `scripts/run-plan.sh --mab` | Thompson Sampling routes to best strategy per batch type |

## Quality Gates

Mandatory between every batch: lesson check (<2s, grep-based) → ast-grep patterns → test suite → memory check → test count regression → git clean. Customize with `--quality-gate "your command"`.

## Community Lessons

Adding a lesson file to `docs/lessons/` automatically adds a check — no code changes needed. Syntactic lessons run in <2s via `lesson-check.sh`. Semantic lessons are picked up by the `lesson-scanner` agent at verification time. Submit via `/submit-lesson`.

## Installation

```bash
# Marketplace (recommended)
/plugin install autonomous-coding-toolkit@autonomous-coding-toolkit

# Or clone as plugin
git clone https://github.com/parthalon025/autonomous-coding-toolkit.git ~/.claude/plugins/autonomous-coding-toolkit

# Or standalone scripts
git clone https://github.com/parthalon025/autonomous-coding-toolkit.git
./autonomous-coding-toolkit/scripts/run-plan.sh your-plan.md
```

## Requirements

- **Claude Code** (`claude` CLI) — for headless execution
- **bash** 4+, **jq**, **git** — core dependencies
- **gh**, **Ollama**, **curl** — optional (PR creation, report analysis, Telegram notifications)

## Learn More

| Topic | Doc |
|-------|-----|
| Architecture & internals | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Contributing lessons | [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) |
| Plan file format | [`examples/example-plan.md`](examples/example-plan.md) |
| Design principles | [`docs/ARCHITECTURE.md#design-principles`](docs/ARCHITECTURE.md#design-principles) |

## Attribution

Core skill chain forked from [superpowers](https://github.com/obra/superpowers) by Jesse Vincent / Anthropic. Extended with quality gate pipeline, headless execution engine, Ralph loop, dynamic lesson system, lesson-scanner agent, MAB routing, and machine-verifiable PRD system.

## License

MIT
