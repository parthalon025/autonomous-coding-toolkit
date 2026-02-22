# A/B Run System Design

**Date:** 2026-02-22
**Status:** Approved
**Goal:** Competing autonomous agents (superpowers vs ralph-wiggum) execute the same brief using different methodologies, judged by an LLM that extracts lessons and updates strategy performance data. The toolkit gets smarter with every run, and community contributions compound learning for everyone.

## Problem

The toolkit has two execution strategies — structured (superpowers skill chain) and autonomous (ralph-wiggum iteration loop) — but no empirical data on which works better for which types of work. Users pick one and hope. The toolkit learns nothing from execution outcomes.

## Design Principles

1. **Thin infrastructure, rich data, LLM intelligence.** Bash scripts create worktrees, run quality gates, merge branches. LLM agents make all decisions (routing, judging, lesson extraction). Data files are the interface between runs.

2. **Both agents are full toolkit citizens.** They inherit all skills, lessons, hooks, quality gates, and CLAUDE.md conventions. The competition is about orchestration strategy, not available tools.

3. **Human input ends at PRD approval.** Brainstorm → design → PRD is human-in-the-loop. Everything after is machine-driven.

4. **Every run produces learning.** A/B lessons, strategy performance data, and failure mode classifications feed back into future runs. Community contributions propagate via git.

## Architecture

```
PHASE 1 — HUMAN + SINGLE AGENT (shared)
  1. Brainstorm → approved design doc
  2. PRD → machine-verifiable acceptance criteria
  3. Architecture map generated

PHASE 2 — PLANNER AGENT (LLM)
  Reads: design doc, PRD, architecture map, strategy-perf.json
  Decides per work unit: A/B or single? Which strategy? Unit size?

PHASE 3 — A/B EXECUTION (parallel worktrees)
  Agent A (superpowers): writes own plan, TDD, batch-by-batch
  Agent B (ralph): iterates until PRD criteria pass

PHASE 4 — JUDGE AGENT (LLM)
  Reads: both diffs, design doc, PRD, architecture map, lesson history
  Outputs: winner, bidirectional lessons, strategy update, failure mode

PHASE 5 — MERGE + LEARN
  Merge winner, log lessons, update strategy data, promote patterns
```

## Shared Inputs (Human-Approved)

All created before A/B execution begins. Human approves design and PRD.

| Artifact | Source | Purpose |
|----------|--------|---------|
| Design doc | Brainstorming skill | What to build and why |
| `tasks/prd.json` | `/create-prd` | Machine-verifiable acceptance criteria |
| `docs/ARCHITECTURE-MAP.json` | `architecture-map.sh` (auto-generated) | Module graph, imports/exports, dependencies |

## Agent Configuration

Both agents receive identical toolkit context. The only difference is the lead instruction.

### What both agents always get

```
1. CLAUDE.md chain
   ~/.claude/CLAUDE.md            (global)
   ~/Documents/CLAUDE.md          (workspace)
   <project>/CLAUDE.md            (project)

2. Toolkit enforcement
   hooks/hooks.json               (hookify rules)
   quality-gate.sh                (lesson-check + tests + memory)
   docs/lessons/*.md              (all lessons)

3. Shared brief
   Design doc
   tasks/prd.json
   docs/ARCHITECTURE-MAP.json
   logs/ab-lessons.json           (previous A/B learnings)

4. All skills available via Skill tool
```

### Agent A (superpowers-led)

```
Lead instruction:
  "Execute this using the superpowers skill chain.
   Write your own implementation plan first.
   Follow TDD: write test → verify fail → implement → verify pass → commit.
   Run quality gates between logical batches."

Natural behavior:
  → writing-plans (creates its own plan from the design doc)
  → executing-plans (batch-by-batch)
  → test-driven-development (per task)
  → verification-before-completion (at end)
```

### Agent B (ralph-led)

```
Lead instruction:
  "Execute this using the ralph-loop approach.
   All PRD acceptance criteria in tasks/prd.json must pass (exit 0).
   Iterate until done. Use any toolkit skills as needed."

Natural behavior:
  → Reads PRD criteria
  → Starts coding toward acceptance criteria
  → Uses TDD, debugging, etc. as needed (not mandated order)
  → Stop-hook checks criteria each cycle
  → Done when all criteria pass
```

## Worktree Isolation

Each A/B run creates two git worktrees branched from HEAD.

```bash
# Create worktrees
git worktree add .claude/worktrees/ab-a-batch-N -b ab-a-batch-N HEAD
git worktree add .claude/worktrees/ab-b-batch-N -b ab-b-batch-N HEAD

# After judge picks winner (say A):
git merge ab-a-batch-N

# Cleanup
git worktree remove .claude/worktrees/ab-a-batch-N
git worktree remove .claude/worktrees/ab-b-batch-N
git branch -d ab-a-batch-N ab-b-batch-N
```

Both agents run in parallel. Neither can see the other's work.

## Planner Agent

An LLM agent that decides routing before execution begins. Not a bash script — reads data files and produces a JSON routing plan.

### Inputs

- Design doc (scope and complexity)
- PRD task graph (dependencies, count)
- `docs/ARCHITECTURE-MAP.json` (cross-module touches)
- `logs/strategy-perf.json` (historical win rates per strategy x batch type)

### Decision Logic

```
For each work unit:
  1. Classify type: new-file, refactoring, integration, test-only
  2. Check strategy-perf.json for this type
  3. If clear winner (>70% win rate, 10+ data points): route to winner
  4. If uncertain or insufficient data: A/B run
  5. If error-prone type (historically high retry rate): A/B run
```

### Output

```json
{
  "routing": [
    {
      "unit": 1,
      "description": "Create test helpers and validators",
      "type": "new-file",
      "decision": "single",
      "strategy": "ralph",
      "reasoning": "new-file: ralph wins 70%, 15 data points"
    },
    {
      "unit": 2,
      "description": "Integration wiring and CI",
      "type": "integration",
      "decision": "ab_run",
      "reasoning": "integration: superpowers 55%, only 8 data points — need more data"
    }
  ]
}
```

### Work Unit Sizing

| Project size | Strategy |
|-------------|----------|
| Small (< 5 PRD tasks) | A/B the whole project |
| Medium (5-15 PRD tasks) | Chunk by PRD dependency groups, route per chunk |
| Large (15+ PRD tasks) | Phase 1: A/B (explore), Phase 2+: route to winners (exploit) |

## Judge Agent

An LLM agent that evaluates both candidates after execution.

### Inputs

```
1. Full plan context: design doc, PRD, architecture map
2. Both diffs: git diff main...ab-a, git diff main...ab-b
3. Quality gate results for both
4. All previous A/B lessons: logs/ab-lessons.json
5. Score from automated scoring (test count, diff size, gate pass)
```

### Evaluation Criteria

```
1. WINNER SELECTION
   Which implementation better serves the overall architecture?

2. BIDIRECTIONAL LESSONS
   What did the winner do well that the loser should learn from?
   What did the loser do well that the winner should learn from?

3. FAILURE MODE CLASSIFICATION
   How did the weaker submission fall short?
   Categories: over-engineering, under-testing, code-duplication,
   integration-gap, convention-violation, wrong-abstraction-level

4. TOOLKIT COMPLIANCE
   Did both agents follow CLAUDE.md conventions?
   Did both use TDD (regardless of strategy)?
   Did either trigger hookify blocks?
   Did either skip verification?

5. STRATEGY RECOMMENDATION
   For this work unit type, which strategy should be preferred?
   Confidence level (low/medium/high)?

6. LESSON EXTRACTION
   {
     "pattern": "description of what was learned",
     "context": "when this applies (batch type, project type)",
     "recommendation": "what to do differently",
     "source_strategy": "which agent's behavior this came from",
     "lesson_type": "syntactic|semantic"
   }
```

### Output

```json
{
  "winner": "agent_a",
  "confidence": "high",
  "reasoning": "Agent A's implementation separated validation logic into composable functions. Agent B duplicated validation across 3 files.",
  "failure_mode": "code-duplication-under-time-pressure",
  "toolkit_compliance": {
    "agent_a": {"tdd": true, "conventions": true, "hookify_blocks": 0},
    "agent_b": {"tdd": false, "conventions": true, "hookify_blocks": 0}
  },
  "lessons": [
    {
      "pattern": "Extract shared validation patterns before writing per-type validators",
      "context": "new-file batches with 3+ similar validators",
      "recommendation": "Create a shared contract function first, then implement per-type",
      "source_strategy": "agent_a",
      "lesson_type": "semantic"
    }
  ],
  "strategy_update": {
    "batch_type": "new-file",
    "winner": "superpowers",
    "confidence": "medium"
  }
}
```

## Data Files

### `logs/ab-lessons.json` — Accumulated A/B Lessons

```json
[
  {
    "timestamp": "2026-02-22T15:30:00Z",
    "project": "autonomous-coding-toolkit",
    "work_unit": "validator-suite",
    "batch_type": "new-file",
    "winner": "agent_a",
    "pattern": "Extract shared validation patterns before per-type validators",
    "context": "new-file batches with 3+ similar validators",
    "recommendation": "Create shared contract function first",
    "failure_mode": "code-duplication-under-time-pressure",
    "occurrences": 1
  }
]
```

### `logs/strategy-perf.json` — Strategy Win Rates

```json
{
  "new-file": {
    "superpowers": {"wins": 12, "losses": 8, "total": 20},
    "ralph": {"wins": 8, "losses": 12, "total": 20}
  },
  "refactoring": {
    "superpowers": {"wins": 3, "losses": 11, "total": 14},
    "ralph": {"wins": 11, "losses": 3, "total": 14}
  },
  "integration": {
    "superpowers": {"wins": 9, "losses": 2, "total": 11},
    "ralph": {"wins": 2, "losses": 9, "total": 11}
  },
  "test-only": {
    "superpowers": {"wins": 5, "losses": 7, "total": 12},
    "ralph": {"wins": 7, "losses": 5, "total": 12}
  }
}
```

### `docs/ARCHITECTURE-MAP.json` — Auto-Generated Module Graph

```json
{
  "generated_at": "2026-02-22T15:00:00Z",
  "modules": [
    {
      "name": "run-plan",
      "files": ["scripts/run-plan.sh", "scripts/lib/run-plan-*.sh"],
      "exports": ["run_mode_headless", "run_mode_team"],
      "depends_on": ["quality-gate", "lesson-check", "telegram"]
    }
  ]
}
```

## Lesson Lifecycle

```
A/B judge extracts lesson
  → logs/ab-lessons.json (immediate, local)

Pattern recurs 3+ times (same pattern across runs)
  → Auto-promoted to docs/lessons/NNNN-*.md
  → lesson-check.sh enforces syntactic lessons
  → lesson-scanner agent enforces semantic lessons

Promoted lesson causes quality gate failure
  → Tagged "disputed" in ab-lessons.json
  → Excluded from injection until human review

User runs /submit-lesson
  → PR to upstream autonomous-coding-toolkit repo
  → Maintainer reviews and merges
  → Community users pull via scripts/pull-community-lessons.sh
```

## Community Propagation

### Contributing Lessons

```bash
# Existing command — already in the toolkit
/submit-lesson

# Creates PR with:
#   docs/lessons/NNNN-<slug>.md (the lesson)
#   Commit message references the A/B run that produced it
```

### Consuming Community Lessons

```bash
# New script
scripts/pull-community-lessons.sh

# Behavior:
#   git fetch upstream
#   Copy new docs/lessons/*.md files
#   Copy updated logs/strategy-perf.json (community aggregate)
#   lesson-check.sh picks up new lessons automatically
```

### Community Strategy Data

Aggregated `strategy-perf.json` from all contributors. When merged upstream, includes anonymous win/loss data across all users' projects. New users start with community baseline instead of zero data.

### Semantic Search (Pinecone)

For large lesson corpus (100+ lessons):

```
Before judge extracts a lesson:
  Query Pinecone: "has this pattern been learned before?"
  If match: refine existing lesson instead of creating duplicate
  If no match: create new lesson
```

Uses the existing Pinecone MCP integration.

## Infrastructure Scripts

### `scripts/ab-run.sh` — Orchestrator

Thin bash script that:
1. Creates worktrees
2. Launches both agents in parallel (`claude -p` per worktree)
3. Runs quality gate on both
4. Launches judge agent
5. Merges winner
6. Cleans up worktrees
7. Updates data files

### `scripts/architecture-map.sh` — Module Graph Generator

Scans project source files:
- Python: `import` / `from X import` statements
- JavaScript/TypeScript: `import` / `require` statements
- Shell: `source` statements
- Produces `docs/ARCHITECTURE-MAP.json`

### `scripts/pull-community-lessons.sh` — Community Sync

Fetches latest lessons and strategy data from upstream repo.

### Agent Prompts

- `scripts/prompts/planner-agent.md` — routing decision prompt
- `scripts/prompts/judge-agent.md` — evaluation prompt
- `scripts/prompts/agent-a-superpowers.md` — superpowers lead instruction
- `scripts/prompts/agent-b-ralph.md` — ralph lead instruction

## File Summary

New files:
- `scripts/ab-run.sh` — A/B execution orchestrator
- `scripts/architecture-map.sh` — module graph generator
- `scripts/pull-community-lessons.sh` — community lesson sync
- `scripts/prompts/planner-agent.md` — planner prompt
- `scripts/prompts/judge-agent.md` — judge prompt
- `scripts/prompts/agent-a-superpowers.md` — Agent A instructions
- `scripts/prompts/agent-b-ralph.md` — Agent B instructions
- `scripts/tests/test-ab-run.sh` — A/B orchestrator tests
- `scripts/tests/test-architecture-map.sh` — map generator tests
- `docs/plans/2026-02-22-ab-run-design.md` — this document

Modified files:
- `scripts/run-plan.sh` — add `--ab` flag that routes through `ab-run.sh`
- `scripts/lib/run-plan-context.sh` — inject A/B lessons into batch context
- `docs/ARCHITECTURE.md` — document A/B system

Data files (created at runtime):
- `logs/ab-lessons.json`
- `logs/strategy-perf.json`
- `logs/ab-run-<timestamp>.json`
- `docs/ARCHITECTURE-MAP.json`
