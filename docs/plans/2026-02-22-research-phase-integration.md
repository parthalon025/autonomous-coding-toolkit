# Research Phase Integration: Formalizing Research in the Autonomous Coding Pipeline

**Date:** 2026-02-22
**Status:** Research complete
**Scope:** How to integrate a structured research phase into the toolkit's workflow pipeline, plus code factory consolidation and roadmap stage
**Method:** 3 parallel research agents (external frameworks, codebase analysis, cross-domain analogies) + manual codebase exploration

---

## Executive Summary

The autonomous coding toolkit's pipeline (brainstorm → PRD → plan → execute → verify → finish) has no formalized research phase. Research happens informally during brainstorming (codebase reconnaissance) and is partially automated via `prior-art-search.sh` in the headless pipeline — but neither produces a structured, reusable artifact.

Evidence from six domains (medicine, military intelligence, design thinking, competitive intelligence, deep research agents, SWE-bench) converges on the same pattern: **structured research before action, producing a durable artifact that downstream phases consume.**

The MAB research we conducted in this session is the proof case — Round 1 alone halved the batch count, identified 80% code reuse, surfaced 3 academic techniques the design missed, and found 8 latent bugs. All before a single line of implementation code was written.

**Three additions proposed:**
1. **Research phase** — new Stage 1.5 between brainstorming and PRD, producing structured `tasks/research-<slug>.md` + `.json`
2. **Roadmap stage** — new Stage 0.5 before brainstorming, for multi-feature sequencing
3. **Code factory consolidation** — bring all Code Factory scripts and skills into the toolkit as first-class pipeline components

---

## 1. The Case for Formalized Research

### 1.1 What Top-Performing Agents Do

Evidence from SWE-bench, Cognition (Devin), and academic literature:

| Finding | Source | Implication |
|---------|--------|-------------|
| Agents spend >60% of first-turn time retrieving context | Cognition SWE-bench report | Context retrieval is the bottleneck, not code generation |
| SWE-grep (specialized retrieval sub-agent) reduced context retrieval from 20+ turns to 4 turns | Cognition SWE-grep blog | Separate the retrieval agent from the coding agent |
| Performance degrades >30% when relevant info is in the middle of context vs beginning/end | Stanford "Lost in the Middle" (arXiv 2307.03172) | Compress and select before injecting — don't dump everything |
| RAG from diverse, high-quality sources produces significant gains even on top of GPT-4 | CodeRAG-Bench (arXiv 2406.14497) | Multi-source research (codebase + docs + web + papers) compounds |
| 72% of SWE-bench successes take >10 minutes | SWE-bench Pro (Scale AI) | Exploration time is not waste — it's the work |
| "Most agent failures are not model failures — they are context failures" | Anthropic context engineering guide | The research phase IS context engineering |

### 1.2 What the Current Pipeline Does (and Doesn't)

| Research-like Activity | Where | Artifact Produced | Consumed By | Gap |
|----------------------|-------|-------------------|-------------|-----|
| Codebase reconnaissance | brainstorming Step 1 | None — ephemeral | Clarifying questions only | No artifact, no record |
| Prior-art search | `auto-compound.sh` Step 2.5 | `prior-art-results.txt` (unstructured) | PRD prompt injection | Not in interactive path; unstructured; no schema |
| Report analysis | `analyze-report.sh` | `analysis.json` | `auto-compound.sh` only | Triage, not research |
| PRD investigation tasks | `create-prd.md` Step 4 | None — findings disappear | `progress.txt` at best | No template, no format, no enforcement |
| Competitive pre-flight | `competitive-mode.md` | Context brief (ephemeral) | Competitor prompts | Only in competitive mode; not a durable artifact |
| Manual research reports | MAB session (this session) | `docs/plans/*.md` (structured) | Design doc, plan | No automated analog |

**The structural gap:** Research findings have no path back into the pipeline. There is no stage that reads research output and uses it to modify the design, scope the PRD, or annotate the plan.

### 1.3 What the MAB Research Session Proved

| Activity | Impact | Pipeline Could Have Done This? |
|----------|--------|-------------------------------|
| Codebase gap analysis | Identified 80% infrastructure reuse — halved batch count | No — brainstorming doesn't audit existing code against plan assumptions |
| Academic literature review | Added Thompson Sampling, position bias mitigation, prompt evolution | No — no external search mechanism |
| Cross-domain analogies | 7 analogies produced 3 universal patterns (locked criteria, diversity as signal, discriminating conditions) | No — nothing searches outside the domain |
| Cost modeling | $1.88 vs $10.58/batch with cache priming — changed architecture | No — no cost analysis mechanism |
| Latent bug identification | 8 bugs found before implementation (including state schema mismatch affecting all headless runs) | Partial — lesson-check is post-hoc, not pre-implementation |
| Research → plan reshape | Round 1 halved batches; Round 2 added cache-prime step | No — no feedback path from research to plan |

---

## 2. Cross-Domain Research Frameworks

### 2.1 Evidence-Based Medicine (PICO + Cochrane)

The strongest anti-bias framework. Five mandatory phases before analysis:

1. **Protocol registration** — pre-specify question, inclusion/exclusion criteria, synthesis method *before seeing data*
2. **Question decomposition (PICO):** Population, Intervention, Comparison, Outcome
3. **Search strategy** — explicit queries across explicit sources, documented for reproducibility
4. **Screening** — two-stage: title/abstract first, then full-text, with pre-defined inclusion rules
5. **Data extraction → synthesis** — structured form per source, then aggregation with confidence grades (GRADE: high/moderate/low/very low)

**Key artifacts:** `review_protocol.md` (frozen before search), `search_log.json`, `screening_matrix.csv`, `evidence_table.md`

**Transferable insight:** The protocol is frozen before data collection. You cannot adjust inclusion criteria after seeing results. Applied to coding: define what "relevant prior art" means *before* searching.

**Automated analog:** otto-SR reproduced 12 Cochrane reviews in 2 days using a multi-agent LLM pipeline (abstract screen → full-text screen → extraction → synthesis). Sensitivity: 96.7%, specificity: 97.9%.

### 2.2 Military Intelligence (IPB + ACH + OODA)

**Intelligence Preparation of the Battlefield (IPB)** — four mandatory steps:

1. Define operational environment (scope)
2. Describe environmental effects on operations (constraints)
3. Evaluate the threat (adversary capabilities)
4. Determine threat courses of action (all plausible, not just most likely)

**What's distinctive:** IPB explicitly maps *what you don't know* alongside what you do. The artifact isn't just findings — it's a **structured-ignorance document** that defines what information would change the assessment.

**Analysis of Competing Hypotheses (ACH):** Build an evidence matrix where rows are evidence items and columns are competing hypotheses. Score each cell. The hypothesis with the least disconfirming evidence wins — not the one with the most confirming evidence.

**Transferable insights:**
- Map unknowns explicitly, not just knowns
- Evaluate competing approaches by disconfirmation, not confirmation
- The ASCOPE matrix (Areas, Structures, Capabilities, Organizations, People, Events) translates to: Files, Modules, APIs, Dependencies, Users, Workflows

### 2.3 Design Thinking (Double Diamond)

Two explicit diverge/converge cycles with a hard gate between them:

```
Diamond 1: Problem Space         Diamond 2: Solution Space
[Discover] → [Define]    GATE   [Develop] → [Deliver]
 (diverge)   (converge)          (diverge)   (converge)
```

**Gate rule:** You *cannot* enter solution space without a frozen problem definition.

**Discovery phase artifacts:** Empathy maps, competitive landscape matrix, "How Might We" question bank, insight statements

**Transferable insight:** Discovery is explicitly divergent — collect more than you need, then cull. The cull produces a Point of View (POV) statement that's frozen before solution work begins.

### 2.4 Competitive Intelligence

The intelligence cycle: **Requirements → Collection → Analysis → Dissemination**

**What's distinctive:** Dissemination is tailored by consumer role. The same research produces different artifacts for different downstream consumers (executive summary for decision-makers, detailed analysis for implementers, raw data for further analysis).

**Applied to the pipeline:** A single research phase produces:
- `research-<slug>.md` — human-readable report for design review
- `research-<slug>.json` — machine-readable for PRD scoping and context injection
- GitHub issues — for deferred items discovered during research

### 2.5 Deep Research Agent Architecture

The canonical pipeline (from GPT Researcher, OpenAI Deep Research, DeepResearchAgent):

```
Phase 1: PLAN       — decompose query into sub-questions (strategic LLM)
Phase 2: EXECUTE    — parallel retrieval per sub-question (crawler agents)
Phase 3: CURATE     — embedding similarity filter + credibility ranking
Phase 4: SYNTHESIZE — aggregate into structured output (smart LLM)
Phase 5: PUBLISH    — format with citations
```

**Key insight:** These pipelines treat research output as a *durable artifact* (a report), not ephemeral context. Coding agents typically treat retrieved context as ephemeral — this is the architectural gap.

### 2.6 Agile Technical Spikes

**Definition:** A time-boxed investigation task with a single question and a concrete deliverable (decision, estimate, or prototype).

**Best practices:**
- Single clear question — not "understand the codebase" but "what dependency injection pattern does the auth module use?"
- Time-boxed to 1-3 days (for agents: token/turn budgets)
- Deliverable is a decision, not code
- Two types: Technical (how to build) vs Functional (what to build)

**The anti-pattern AI agents make:** They conflate spike and implementation into a single trajectory. The agent starts searching and starts writing before search is complete.

---

## 3. Proposed Pipeline Changes

### 3.1 Current Pipeline

```
Stage 0:   Initialize      — detect project, load context
Stage 1:   Brainstorm      — design doc + user approval
Stage 2:   PRD             — tasks/prd.json with shell-verifiable criteria
Stage 3:   Plan            — TDD implementation plan
Stage 3.5: Isolate         — git worktree
Stage 4:   Execute         — one of 4 modes
Stage 5:   Verify          — all PRD criteria pass
Stage 6:   Finish          — merge/PR/keep/discard
```

### 3.2 Proposed Pipeline (3 additions)

```
Stage 0:   Initialize        — detect project, load context
Stage 0.5: ROADMAP [NEW]     — multi-feature sequencing, priority ordering
Stage 1:   Brainstorm        — design doc + user approval
Stage 1.5: RESEARCH [NEW]    — structured investigation, produces durable artifact
Stage 2:   PRD               — tasks/prd.json (scoped by research findings)
Stage 3:   Plan              — TDD implementation plan (informed by research)
Stage 3.5: Isolate           — git worktree
Stage 4:   Execute           — one of 4+ modes (including MAB)
Stage 5:   Verify            — all PRD criteria pass
Stage 6:   Finish            — merge/PR/keep/discard
```

### 3.3 Stage 0.5: Roadmap (New)

**Purpose:** Before brainstorming a single feature, assess whether the work fits into a larger picture. A roadmap answers: *What order should features be built in? What blocks what? What's the minimum viable sequence?*

**When to invoke:**
- When the user describes multiple features or a large system
- When `auto-compound.sh` processes a report with multiple priorities
- When multiple GitHub issues exist and need sequencing
- Skip for single, isolated features

**Artifact:** `docs/roadmap-<project-or-theme>.md`

```markdown
# Roadmap: <theme>
**Date:** YYYY-MM-DD
**Scope:** <what this roadmap covers>

## Features (priority order)
| # | Feature | Depends On | Effort | Value Signal |
|---|---------|-----------|--------|-------------|
| 1 | <name> | — | S/M/L | <why this first> |
| 2 | <name> | #1 | S/M/L | <why this order> |

## Dependency Graph
<text-based or mermaid graph>

## Decision Log
- <decision>: <rationale>

## Out of Scope
- <item>: <why deferred>
```

**Gate:** User approves roadmap before brainstorming the first feature. Each feature in the roadmap gets its own brainstorm → research → PRD → plan → execute cycle.

**Integration with pipeline:**
- `autocode` skill checks for existing roadmap; if none exists and scope seems multi-feature, prompts user
- `auto-compound.sh` can generate roadmap from multi-priority `analysis.json`
- Roadmap is a living document — updated after each feature completes

### 3.4 Stage 1.5: Research (New)

**Purpose:** After the design is approved, before PRD generation, conduct structured investigation to validate assumptions, find reusable components, surface latent issues, and mine external knowledge.

**Activities (parallel where possible):**

| Activity | Agent Type | Sources | Output |
|----------|-----------|---------|--------|
| Codebase gap analysis | Explore | Local files, AST, imports | Reuse table |
| Prior-art search | general-purpose | GitHub, web, Context7 | Library recommendations, patterns |
| Academic/external lit | general-purpose | Web search, papers | Techniques, measured impact |
| Cross-domain analogies | general-purpose | Web search (lateral) | Transferable patterns |
| Cost/feasibility | general-purpose | API pricing, benchmarks | Cost model |
| Latent issue scan | Explore + Bash | Existing code, tests, lint | Bug list with file:line |

**Research protocol (adapted from Cochrane):**
1. **Scope** — what questions does this research answer? (derived from design doc)
2. **Search** — explicit queries, documented in the artifact
3. **Screen** — relevance filter on results
4. **Extract** — structured findings per source
5. **Synthesize** — implications for design, PRD scope, and plan

**Artifacts produced:**

**`tasks/research-<feature-slug>.md`** — human-readable report:
```markdown
# Research: <feature>
**Date:** YYYY-MM-DD
**Design doc:** docs/plans/YYYY-MM-DD-<topic>-design.md

## Research Questions
1. <question derived from design>
2. <question>

## Codebase Gap Analysis
| Requirement | Existing File | Reusable? | Gap |
|-------------|--------------|-----------|-----|

## External Findings
### <Source Title>
- **Source:** <URL or citation>
- **Key finding:** <1-2 sentences>
- **Implication:** <how this affects our design>

## Latent Issues
| File:Line | Description | Severity | Blocking? |
|-----------|-------------|----------|-----------|

## Cross-Domain Insights
| Domain | Pattern | Application |
|--------|---------|-------------|

## Design Changes Recommended
1. [BLOCKING] <change> — <rationale>
2. <change> — <rationale>

## Cost Model
<if applicable>

## Deferred Items
- <item> → GitHub issue created: #<number>
```

**`tasks/research-<feature-slug>.json`** — machine-readable:
```json
{
  "feature": "string",
  "date": "YYYY-MM-DD",
  "design_doc": "path",
  "reuse_components": [
    {"requirement": "string", "file": "string", "lines": "string", "gap": "none|partial|full"}
  ],
  "latent_issues": [
    {"file": "string", "line": 0, "description": "string", "severity": "critical|high|medium|low", "blocking": true}
  ],
  "design_changes": [
    {"change": "string", "rationale": "string", "blocking": true}
  ],
  "prd_scope_delta": {
    "tasks_removable": ["string"],
    "tasks_added": ["string"],
    "estimated_task_reduction": 0
  },
  "external_findings_count": 0,
  "search_queries": ["string"]
}
```

**Consumption by downstream stages:**

| Stage | How It Uses Research |
|-------|---------------------|
| PRD generation | Reads `prd_scope_delta` — removes tasks covered by reuse, adds tasks for latent issues |
| Writing plans | References research report under `## Research Findings`; adds fix tasks for latent issues |
| run-plan-context.sh | Injects critical/high latent issues as `### Research Warnings` in per-batch context |
| auto-compound.sh | Replaces Step 2.5 (prior-art-results.txt) with structured research JSON |
| Quality gate | `research-gate.sh` blocks PRD generation if blocking design changes unresolved |

### 3.5 Code Factory Consolidation

**Current state:** Code Factory scripts and concepts are split between the toolkit repo and the Documents workspace:

| Component | Location | Should Be In Toolkit? |
|-----------|----------|----------------------|
| `auto-compound.sh` | toolkit `scripts/` | Yes (already there) |
| `quality-gate.sh` | toolkit `scripts/` | Yes (already there) |
| `run-plan.sh` + libs | toolkit `scripts/` | Yes (already there) |
| `analyze-report.sh` | toolkit `scripts/` | Yes (already there) |
| `prior-art-search.sh` | toolkit `scripts/` | Yes (already there) |
| `/create-prd` command | toolkit `commands/` | Yes (already there) |
| `/code-factory` command | toolkit `commands/` | Yes (already there) |
| `autocode` skill | toolkit `skills/` | Yes (already there) |
| `competitive-mode.md` | toolkit `skills/autocode/` | Yes (already there) |
| Code Factory design doc | workspace `docs/plans/` | Move to toolkit `docs/` |
| Code Factory V2 design | workspace `docs/plans/` | Move to toolkit `docs/` |
| `claude-md-validate.sh` | workspace `scripts/` | Keep in workspace (workspace-specific) |
| `lessons-review.sh` | workspace `scripts/` | Keep in workspace (workspace-specific) |
| PRD template/examples | toolkit `examples/` | Yes (already there) |

**The consolidation is mostly done.** The remaining gap is documentation — the Code Factory design docs and V2 design are in the workspace, not the toolkit. The pipeline integration points documented in `~/Documents/CLAUDE.md` under "Code Factory (Agent-Driven Development)" should be extracted into a toolkit-native `docs/CODE-FACTORY.md`.

**What "Code Factory in the toolkit" means concretely:**
1. Move Code Factory V2 design insights into `docs/ARCHITECTURE.md` (the authoritative architecture doc)
2. Ensure `autocode` skill references all pipeline scripts by their toolkit paths
3. The `competitive-mode.md` becomes the template for MAB's dual-agent execution
4. Prior-art search evolves into the research phase (this proposal)

---

## 4. Implementation Architecture

### 4.1 Research Skill

New file: `skills/research/SKILL.md`

```markdown
# Research Phase

## Overview
Conduct structured investigation after design approval and before PRD generation.
Produces a durable artifact that scopes the PRD and informs the plan.

## Checklist
1. Define research questions (from approved design doc)
2. Codebase gap analysis (Explore agent)
3. Prior-art search (call existing prior-art-search.sh + web search)
4. External literature (web search agents, parallel)
5. Cross-domain analogies (optional, for complex designs)
6. Latent issue scan (grep + lint on files the plan will touch)
7. Cost/feasibility model (optional, for compute-intensive features)
8. Synthesize into tasks/research-<slug>.md + .json
9. Present findings, get user approval
10. Apply blocking design changes before proceeding
```

### 4.2 Roadmap Skill

New file: `skills/roadmap/SKILL.md`

Invoked when scope is multi-feature. Produces `docs/roadmap-<theme>.md`. Gates brainstorming — each feature in the roadmap gets its own brainstorm cycle.

### 4.3 Pipeline Updates

**`skills/autocode/SKILL.md`** — add Stage 0.5 (roadmap, conditional) and Stage 1.5 (research, always):

```
Stage 0:   Initialize
Stage 0.5: Roadmap (if multi-feature scope)
Stage 1:   Brainstorm → design doc
Stage 1.5: Research → tasks/research-<slug>.md + .json
Stage 2:   PRD (scoped by research)
Stage 3:   Plan (informed by research)
...
```

**`commands/code-factory.md`** — add research stage between brainstorming and PRD

**`scripts/auto-compound.sh`** — replace Step 2.5 (prior-art search) with full research phase:
```bash
# Step 2.5: Research phase (replaces prior-art search)
log_step "Running research phase..."
# Call claude -p with research skill prompt
# Produces tasks/research-<slug>.json
# Check for blocking design changes
if jq -e '.design_changes[] | select(.blocking == true)' "tasks/research-${slug}.json" >/dev/null 2>&1; then
    log_error "Blocking design changes found — review before proceeding"
    exit 1
fi
```

**`scripts/lib/run-plan-context.sh`** — add research warnings to per-batch context:
```bash
# After failure patterns, before context_refs:
local research_file
research_file=$(find "$worktree/tasks/" -name "research-*.json" -print -quit 2>/dev/null)
if [[ -f "$research_file" ]]; then
    local warnings
    warnings=$(jq -r '.latent_issues[] | select(.severity == "critical" or .severity == "high") | "⚠ \(.file):\(.line) — \(.description)"' "$research_file" 2>/dev/null || true)
    if [[ -n "$warnings" ]]; then
        context+="### Research Warnings (fix before touching these files)"$'\n'
        context+="$warnings"$'\n\n'
    fi
fi
```

### 4.4 Research Gate

New file: `scripts/research-gate.sh`

Runs before PRD generation. Checks `tasks/research-<slug>.json` for blocking items:
- Blocking design changes → exit 1 (blocks PRD generation)
- Critical latent issues → exit 1 (must be acknowledged)
- Non-blocking items → exit 0 (warnings only)

Same enforcement pattern as quality gates — machine-verifiable, exit-code-driven.

---

## 5. The "Always Make a File" Principle

**Rule:** Every research activity produces a file. No ephemeral research.

This principle applies across the pipeline:

| Activity | File Produced | Format |
|----------|--------------|--------|
| Brainstorming exploration | `docs/plans/YYYY-MM-DD-<topic>-design.md` | Already exists |
| Research phase | `tasks/research-<slug>.md` + `.json` | New |
| PRD generation | `tasks/prd.json` + `tasks/prd-<feature>.md` | Already exists |
| Plan writing | `docs/plans/YYYY-MM-DD-<feature>.md` | Already exists |
| Per-batch execution | `.run-plan-state.json` + `progress.txt` | Already exists |
| MAB judge verdicts | `logs/mab-run-<ts>.json` | Already exists |
| Verification | Inline (PRD criteria results) | Could produce `tasks/verification-<slug>.md` |

**Why files, not memory:** Files survive context resets. A research finding discovered in one session and written to a file is available to every future session. A finding that lives only in conversation context dies when the session ends.

**Implementation:** The research skill's checklist Step 8 ("Synthesize into tasks/research-<slug>.md + .json") makes file creation mandatory, not optional. The research gate (Section 4.4) makes the file's existence a prerequisite for PRD generation.

---

## 6. Revised Full Pipeline

```
USER INPUT (feature description, report, or issue)
    │
    ▼
Stage 0: INITIALIZE
    │   Detect project, load CLAUDE.md, check Telegram, init progress.txt
    │   If input is report: analyze-report.sh → analysis.json
    │
    ├── Multi-feature scope detected?
    │   │
    │   ▼ Yes
    │   Stage 0.5: ROADMAP
    │       Invoke skills/roadmap
    │       Produce: docs/roadmap-<theme>.md
    │       Gate: user approves roadmap
    │       Loop: for each feature in roadmap order ─────┐
    │                                                     │
    ▼                                                     │
Stage 1: BRAINSTORM                                       │
    │   Invoke brainstorming skill                        │
    │   Produce: docs/plans/YYYY-MM-DD-<topic>-design.md  │
    │   Gate: user approves design                        │
    │                                                     │
    ▼                                                     │
Stage 1.5: RESEARCH [NEW]                                 │
    │   Invoke research skill (parallel agents)           │
    │   Produce: tasks/research-<slug>.md + .json         │
    │   Gate: research-gate.sh (no blocking items)        │
    │   Feedback: blocking changes → revise design        │
    │                                                     │
    ▼                                                     │
Stage 2: PRD                                              │
    │   /create-prd (reads research JSON for scoping)     │
    │   Produce: tasks/prd.json + tasks/prd-<feature>.md  │
    │   Gate: user approves                               │
    │                                                     │
    ▼                                                     │
Stage 3: PLAN                                             │
    │   writing-plans (references research report)        │
    │   Produce: docs/plans/YYYY-MM-DD-<feature>.md       │
    │   Gate: user chooses execution mode                  │
    │                                                     │
    ▼                                                     │
Stage 3.5: ISOLATE                                        │
    │   using-git-worktrees                               │
    │   Produce: .worktrees/<branch>/                     │
    │   Gate: baseline tests pass                         │
    │                                                     │
    ▼                                                     │
Stage 4: EXECUTE                                          │
    │   One of: subagent / executing-plans / headless /   │
    │           ralph-loop / MAB                          │
    │   Per-batch: quality gate + research warnings       │
    │   Produce: committed code, progress.txt updates     │
    │                                                     │
    ▼                                                     │
Stage 5: VERIFY                                           │
    │   verification-before-completion                    │
    │   ALL PRD criteria pass (shell commands)             │
    │   Lesson scanner on changed files                   │
    │                                                     │
    ▼                                                     │
Stage 6: FINISH                                           │
    │   finishing-a-development-branch                    │
    │   Merge / PR / Keep / Discard                       │
    │   ───────────────────────── Loop back for next ─────┘
    │                              feature in roadmap
    ▼
DONE
```

---

## 7. Effort Estimate

| Component | Files | New/Modify | Effort |
|-----------|-------|-----------|--------|
| Research skill | `skills/research/SKILL.md` | New | 1 task |
| Roadmap skill | `skills/roadmap/SKILL.md` | New | 1 task |
| Research gate | `scripts/research-gate.sh` | New | 1 task |
| Autocode skill update | `skills/autocode/SKILL.md` | Modify | 1 task |
| Code factory command update | `commands/code-factory.md` | Modify | 1 task |
| create-prd command update | `commands/create-prd.md` | Modify | 1 task |
| Context injection update | `scripts/lib/run-plan-context.sh` | Modify | 1 task |
| auto-compound.sh update | `scripts/auto-compound.sh` | Modify | 1 task |
| Code Factory docs | `docs/CODE-FACTORY.md` | New | 1 task |
| ARCHITECTURE.md update | `docs/ARCHITECTURE.md` | Modify | 1 task |
| Tests | `scripts/tests/test_research_gate.sh` | New | 1 task |
| **Total** | **11 files** | **5 new, 6 modify** | **~2 batches** |

---

## 8. Sources

### AI Agent Architecture
- [SWE-bench Technical Report — Cognition](https://cognition.ai/blog/swe-bench-technical-report)
- [SWE-grep: RL for Fast Context Retrieval — Cognition](https://cognition.ai/blog/swe-grep)
- [Devin 2.0 Planning Mode — Cognition](https://cognition.ai/blog/devin-2)
- [Lost in the Middle — Stanford, arXiv 2307.03172](https://arxiv.org/abs/2307.03172)
- [Effective Context Engineering — Anthropic Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Context Engineering for Agents — LangChain Blog](https://blog.langchain.com/context-engineering-for-agents/)
- [RAG Review 2025 — RAGFlow](https://ragflow.io/blog/rag-review-2025-from-rag-to-context)
- [CodeRAG-Bench — arXiv 2406.14497](https://arxiv.org/html/2406.14497v1)
- [RACG Survey — arXiv 2510.04905](https://arxiv.org/abs/2510.04905)
- [A-RAG Hierarchical Retrieval — arXiv 2602.03442](https://arxiv.org/html/2602.03442v1)
- [Building Effective AI Agents — Anthropic](https://www.anthropic.com/research/building-effective-agents)
- [Code Generation with LLM Agents Survey — arXiv 2508.00083](https://arxiv.org/html/2508.00083v1)

### Deep Research Agent Pipelines
- [GPT Researcher — GitHub](https://github.com/assafelovic/gpt-researcher)
- [GPT Researcher Architecture — DeepWiki](https://deepwiki.com/assafelovic/gpt-researcher)
- [DeepResearchAgent — SkyworkAI](https://github.com/SkyworkAI/DeepResearchAgent)
- [Deep Research API — OpenAI Cookbook](https://cookbook.openai.com/examples/deep_research_api/introduction_to_deep_research_api_agents)
- [Deep Research Agents Examination — arXiv 2506.18096](https://arxiv.org/html/2506.18096v2)

### Cross-Domain Frameworks
- [Cochrane PICO](https://www.cochranelibrary.com/about-pico)
- [otto-SR: Automated Systematic Reviews](https://ottosr.com/manuscript.pdf)
- [ASReview — Nature Machine Intelligence](https://www.nature.com/articles/s42256-020-00287-7)
- [Double Diamond — British Design Council / Maze](https://maze.co/blog/double-diamond-design-process/)
- [Intelligence Preparation of the Battlefield — Army ADP 2-01.3](https://armypubs.army.mil/epubs/DR_pubs/DR_a/ARN36709-ATP_2-01.3-001-WEB-2.pdf)
- [Analysis of Competing Hypotheses — CIA](https://www.cia.gov/static/955180a45afe3f5013772c313b16face/Tradecraft-Primer-apr09.pdf)
- [Technical Spikes in Agile — Talent500](https://talent500.com/blog/spike-in-agile-purpose-process-best-practices/)

### Codebase (Internal)
- `skills/autocode/competitive-mode.md` — pre-flight exploration pattern (codebase + external agents)
- `scripts/prior-art-search.sh` — existing prior-art search (GitHub + local + ast-grep)
- `scripts/auto-compound.sh` — automated pipeline with Step 2.5 prior-art search
- `docs/plans/2026-02-21-code-factory-v2-design.md` — V2 design with prior-art search as Task 3.2
- `docs/plans/2026-02-21-code-factory-v2-phase4-design.md` — ast-grep discovery mode
- `docs/plans/2026-02-13-ha-intelligence-research-findings.md` — example of structured research (4 parallel agents, 100+ papers)
- `docs/plans/2026-02-21-infrastructure-deep-research.md` — example of structured research (5 parallel agents)
- `docs/plans/2026-02-21-mab-research-report.md` — MAB Round 1 research (this session)
- `docs/plans/2026-02-22-mab-research-round2.md` — MAB Round 2 research (this session)
