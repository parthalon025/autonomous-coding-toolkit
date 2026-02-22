# Multi-Armed Bandit System: Research Report

**Date:** 2026-02-21
**Status:** Research complete
**Scope:** Codebase gap analysis, academic literature review, Notion workspace cross-reference, internet survey of competing approaches
**Builds on:** `docs/plans/2026-02-22-mab-run-design.md` (approved design), `docs/plans/2026-02-22-mab-run-plan.md` (implementation plan)

---

## Executive Summary

The approved MAB design is sound in goal but overbuilt for first deployment. Research across six sources — the existing codebase, academic literature on MAB+LLM systems, LLM-as-Judge best practices, self-evolving workflow research, SWE-bench competitive approaches, and the Notion knowledge base — reveals that:

1. **80% of the orchestration infrastructure already exists** in `run-plan.sh` and its 8 lib files
2. **The judge is the highest-value component** — academic literature provides concrete design improvements
3. **The planner agent, architecture map, and community sync are premature** — they need data that doesn't exist yet
4. **Academic research suggests three techniques the current design misses:** Thompson Sampling, prompt evolution from judge reasoning, and position-bias mitigation

**Recommendation:** Rewrite the implementation plan as a 2-batch Phase 1 that builds on existing infrastructure, defer 4 of 6 original batches to Phases 2-3 after accumulating run data.

---

## 1. Codebase Gap Analysis

### What Run-Plan Already Provides

The current `run-plan.sh` system (main script + 8 lib modules + 35 test files) implements most of the orchestration the MAB design requires:

| MAB Requirement | Existing Capability | File | Gap |
|----------------|---------------------|------|-----|
| Parallel agent execution | Team mode runs parallel `claude -p` processes | `lib/run-plan-team.sh` | Uses same worktree; MAB needs separate worktrees |
| Automated scoring | `score_candidate()` scores gate pass, test count, diff size, lint, lessons, ast violations | `lib/run-plan-scoring.sh:8-29` | Already sufficient for MAB |
| Batch type classification | `classify_batch_type()` returns new-file/refactoring/integration/test-only | `lib/run-plan-scoring.sh:50-93` | Identical to MAB planner's classification |
| Prompt variant selection | `get_prompt_variants()` with explore/exploit from learned outcomes | `lib/run-plan-scoring.sh:99-146` | Needs extension for strategy-level variants |
| Quality gates between batches | Full pipeline: lesson-check → lint → ast-grep → tests → memory → regression → git clean | `lib/run-plan-quality-gate.sh`, `quality-gate.sh` | Already sufficient |
| Per-batch context injection | `generate_batch_context()` with 6000-char budget, failure patterns, state, git log | `lib/run-plan-context.sh` | Needs MAB lessons section added |
| State persistence + resume | `.run-plan-state.json` tracks batches, test counts, durations, quality gates | `lib/run-plan-state.sh` | Needs MAB-specific fields |
| Failure pattern learning | `record_failure_pattern()` tracks failure types and winning fixes per batch title | `lib/run-plan-context.sh:118-151` | Feed to judge as context |
| Retry with escalation | Attempt 1 → plain, Attempt 2 → "previous failed", Attempt 3 → failure digest | `lib/run-plan-headless.sh:214-234` | Already sufficient |
| Sampling with parallel candidates | `--sample N` spawns N candidates, scores, picks winner, logs outcome | `lib/run-plan-headless.sh:119-210` | Extend for strategy variants |
| Telegram notifications | Success/failure notifications with test counts and batch summaries | `lib/run-plan-notify.sh` | Already sufficient |
| Competitive mode | Stub that prints launch command | `run-plan.sh:267-272` | Replace with real `run_mode_mab()` |

### What the MAB Plan Duplicates

The `mab-run.sh` script in the implementation plan (1,134 lines) reimplements:
- Argument parsing and validation (already in `run-plan.sh:111-247`)
- Worktree creation and cleanup (partially in `run-plan-team.sh`)
- Agent launching via `claude -p` (already in `run-plan-headless.sh` and `run-plan-team.sh`)
- Quality gate execution (already in `run-plan-quality-gate.sh`)
- State tracking (already in `run-plan-state.sh`)
- Prompt assembly with placeholder substitution (already in `run-plan-prompt.sh`)

**Conclusion:** Build `lib/run-plan-mab.sh` (~200-300 lines) as a peer to `run-plan-headless.sh` and `run-plan-team.sh`, not a standalone script.

### What's Genuinely New

Only these components have no existing equivalent:
1. **Judge agent prompt** — evaluates two diffs and picks a winner
2. **Strategy prompt templates** — Agent A (superpowers) and Agent B (ralph) lead instructions
3. **Worktree-per-agent isolation** — team mode uses same worktree; MAB needs two
4. **Strategy performance data** — `logs/strategy-perf.json` (new data file)
5. **MAB lesson accumulation** — `logs/mab-lessons.json` (new data file)
6. **Winner merge logic** — `git merge <winner-branch>` after judge decision

---

## 2. Academic Literature Review

### 2.1 Multi-Armed Bandits Meet LLMs

**Source:** [Multi-Armed Bandits Meet Large Language Models — IBM Research, AAAI 2026](https://research.ibm.com/publications/multi-armed-bandits-meet-large-language-models)

Key findings directly applicable to the MAB system:

- **Prompt/strategy selection as MAB:** "Different prompt variants represent different arms, and the LLM's response quality serves as the reward signal." Bandit algorithms "continuously explore new formulations while exploiting the most successful ones."
- **Thompson Sampling recommended:** For strategy selection with binary outcomes (win/loss), Thompson Sampling naturally balances explore/exploit by sampling from the posterior distribution Beta(wins+1, losses+1) of each arm's win rate.
- **LLMs enhance bandits:** LLMs can "analyze historical data to dynamically suggest exploration rates" and convert "qualitative feedback into structured rewards." This means the judge's reasoning (qualitative) can be converted into structured strategy-perf updates (quantitative).
- **Contextual bandits:** For richer routing, use batch type + project characteristics as context features. The existing `classify_batch_type()` already provides the primary context dimension.

**Implication for design:** Replace the LLM planner agent with Thompson Sampling in bash (~15 lines). The planner becomes valuable only at 50+ data points when contextual features matter.

### 2.2 LLM-as-Judge Best Practices

**Sources:**
- [Using LLM-as-a-Judge (Hamel Husain)](https://hamel.dev/blog/posts/llm-judge/)
- [LLM-as-a-Judge Complete Guide (Langfuse)](https://langfuse.com/docs/evaluation/evaluation-methods/llm-as-a-judge)
- [LLM-As-Judge: 7 Best Practices (Monte Carlo Data)](https://www.montecarlodata.com/blog-llm-as-judge/)
- [Multi-Agent Debate for LLM Judges](https://arxiv.org/html/2510.12697v1)

Critical design guidance:

1. **Start binary, not multi-dimensional.** "A binary decision forces everyone to consider what truly matters." The current design asks the judge for 6 dimensions simultaneously — winner, bidirectional lessons, failure mode classification, toolkit compliance, strategy recommendation, lesson extraction. Research says this produces worse results than binary + reasoning.

2. **Position bias is real and measurable.** In pairwise LLM comparisons, the item presented first has a measurable advantage. The current judge prompt always shows Agent A (superpowers) first. Fix: randomize presentation order and include the order in the output for analysis.

3. **Pairwise comparison > direct scoring.** "Pairwise comparisons lead to more stable results and smaller differences between LLM judgments and human annotations relative to direct scoring." The MAB design already uses pairwise comparison — this validates the approach over scoring each agent independently.

4. **Validate against expert judgment.** "Start with ~30 examples covering different scenarios. Calculate precision and recall separately. Iterate until >90% agreement." For the MAB system: manually review the first 10 judge decisions before trusting automated routing.

5. **Detailed critiques prevent shallow evaluation.** "Provide detailed reasoning in training examples so the judge learns to explain its logic, not just score." The judge prompt should include worked examples of good evaluations.

**Implication for design:** Restructure the judge in phases:
- Phase 1: Binary winner + 2-3 sentence reasoning (one JSON field each)
- Phase 2: Add failure_mode and strategy_update
- Phase 3: Add bidirectional lessons and lesson extraction

### 2.3 Self-Evolving Workflows (SEW)

**Source:** [SEW: Self-Evolving Agentic Workflows (2025)](https://arxiv.org/abs/2505.18646)

SEW demonstrates that **evolving both workflow topology and agent prompts** via mutation and heuristic-driven operators yields up to 33% improvement on LiveCodeBench compared to static hand-crafted baselines.

Key insight for the MAB system: The current design treats strategies as static ("superpowers-v1" and "ralph-v1" forever). SEW shows that the *strategies themselves should evolve* based on outcomes.

**Concrete mechanism:** After the judge picks a winner and explains why, extract the winning behavior as a new prompt variant. The variant pool grows organically:

```json
{
  "variant": "Extract shared validation patterns before writing per-type validators",
  "source_run": "mab-run-1708607400",
  "batch_type": "new-file",
  "win_rate": 0.75,
  "uses": 4
}
```

This is a minimal version of SEW's mutation operators — but instead of random mutation, the judge's reasoning is the mutation source. The existing `get_prompt_variants()` and `logs/sampling-outcomes.json` infrastructure already supports this pattern.

**Implication for design:** Phase 2 feature. After 10+ runs, evolve prompt variants from judge reasoning rather than using hardcoded variant strings.

### 2.4 Automated Design of Agentic Systems (ADAS)

**Source:** [ADAS — ICLR 2025](https://github.com/ShengranHu/ADAS)

ADAS uses a "Meta Agent Search" algorithm where a meta agent iteratively programs new agents from an ever-growing archive of previous discoveries. Agents discovered by Meta Agent Search outperform state-of-the-art hand-designed agents and transfer across domains and models.

Key insight: The MAB system's two strategies are both hand-designed. ADAS shows that **the archive of discovered strategies is more valuable than any individual strategy.** Over time, the system should discover strategies that neither superpowers nor ralph represent.

**Concrete mechanism for Phase 3:**

```json
// logs/strategy-archive.json
[
  {"name": "superpowers-v1", "prompt_hash": "abc123", "win_rate": 0.6, "runs": 20},
  {"name": "ralph-v1", "prompt_hash": "def456", "win_rate": 0.55, "runs": 20},
  {"name": "hybrid-v1", "prompt_hash": "ghi789", "win_rate": 0.7, "runs": 8,
   "discovered_from": "mab-run-12: judge noted Agent B skipped tests on new files",
   "description": "Ralph iteration loop with mandatory test-first on new files"}
]
```

**Implication for design:** Phase 3 feature. Requires 50+ runs and a mechanism for the judge to propose new strategy descriptions, not just pick between existing ones.

### 2.5 SWE-bench Tournament Patterns

**Sources:**
- [SWE-bench Leaderboard Analysis](https://arxiv.org/html/2506.17208v2)
- [SWE-bench Verified Leaderboard](https://llm-stats.com/benchmarks/swe-bench-verified-(agentic-coding))

TRAE achieved 70.4% on SWE-bench Verified (May 2025) by using **o1 to select among patches generated by three different models** (Claude 3.7 Sonnet, Gemini 2.5 Pro, o4-mini). IBM's approach used inference scaling — running the same model multiple times on the same issue.

Both patterns validate the MAB approach. But they also reveal an underexplored dimension: **model variation matters as much as strategy variation.**

The current MAB design holds the model constant (both agents use the same model) and varies only the lead instruction. SWE-bench results suggest that varying the model may produce more diverse candidates:

| Variation dimension | Current MAB | SWE-bench winners | Expected diversity |
|--------------------|-------------|-------------------|-------------------|
| Strategy (prompt) only | ✅ superpowers vs ralph | — | Low (same model interprets both similarly) |
| Model only | — | ✅ TRAE: 3 models + selector | High (different training → different patterns) |
| Strategy + model | — | — | Highest |

**Implication for design:** Phase 2 feature. Extend the existing `--sample` flag to support heterogeneous model candidates:
```bash
--sample-models "sonnet,opus,haiku"  # one candidate per model
```
The scoring infrastructure (`score_candidate()`) is model-agnostic — it scores outputs, not inputs.

---

## 3. Notion Workspace Cross-Reference

### 3.1 Algorithms to Live By — Explore/Exploit Framework

**Source:** Notion Knowledge Hub page (693de656)

Justin's notes on "Algorithms to Live By" (Brian Christian, Tom Griffiths) contain directly relevant decision frameworks:

- **Gittins Index:** The mathematically optimal MAB solution that assigns an "exploration bonus" to unknowns. More principled than the current plan's 70% threshold but computationally expensive. Thompson Sampling is the practical approximation.
- **Time horizon matters:** "Young people should explore more; older people should exploit favorites (declining time horizon)." Applied to the toolkit: early runs should heavily explore (MAB everything), later runs should exploit (route to known winners). The current plan doesn't model this — it uses a fixed 70% threshold regardless of how many runs remain in a project.
- **37% Rule for optimal stopping:** For one-shot decisions (like "which strategy to use on a critical batch with no historical data"), spend 37% of budget on exploration and the rest exploiting the best-so-far. This suggests: for a 6-batch plan with no data, MAB the first 2 batches (33%), then route the rest.
- **Satisficing vs optimizing:** "The 37% rule still fails 63% of the time. Satisficing ('good enough') may produce better life outcomes." Applied: don't over-optimize strategy selection. A 60% win-rate strategy that ships reliably beats an 80% strategy that takes 3x longer to select.

### 3.2 Ryan Carson's Code Factory Pattern

**Source:** Notion page (73a97e21)

Carson's production code-review pipeline provides a complementary pattern: **SHA-pinned review state.** His key lesson: "If you skip current-head SHA matching, you can merge a PR using stale 'clean' evidence."

Applied to MAB: When the judge evaluates two diffs, those diffs must be pinned to specific commit SHAs. If either agent pushes additional commits after the judge starts evaluating, the judgment is stale.

**Concrete fields to add to judge output:**
```json
{
  "sha_a": "abc1234",
  "sha_b": "def5678",
  "evaluated_at": "2026-02-22T15:30:00Z"
}
```

This enables:
1. Re-running the judge on historical runs (reproducibility)
2. Detecting if an agent continued working after evaluation (staleness)
3. Cherry-picking the exact winning state via `git checkout <sha>`

### 3.3 Code Factory V2 Design

**Source:** Local plan at `docs/plans/2026-02-21-code-factory-v2-design.md` (referenced in Notion researcher results)

The Code Factory V2 design already contemplates three execution modes (headless, team, competitive) and establishes `sampling-outcomes.json` for learning which prompt variants win per batch type. The MAB system is the "competitive" mode made real.

V2's key data insight: **batch-type-aware routing** already tracks outcomes per (batch_type × prompt_variant). The MAB system adds a new axis: (batch_type × strategy × prompt_variant). The existing `sampling-outcomes.json` schema needs one additional field (`strategy`) to accommodate this.

---

## 4. Component-Level Recommendations

### 4.1 Components to Keep (validated by research)

| Component | Research validation | Priority |
|-----------|-------------------|----------|
| **Judge agent** | LLM-as-Judge literature confirms pairwise comparison is best approach | P0 — highest value |
| **Two strategy prompts** | SWE-bench shows diverse candidates improve outcomes | P0 — required for judge |
| **Worktree isolation** | Standard practice; Carson's SHA-pinning adds rigor | P0 — required for parallel execution |
| **strategy-perf.json** | Thompson Sampling needs win/loss counts per arm | P0 — required for learning |
| **mab-lessons.json** | Captures judge reasoning for prompt evolution (SEW pattern) | P1 — enables Phase 2 |

### 4.2 Components to Cut (invalidated or premature)

| Component | Original plan | Research finding | Recommendation |
|-----------|--------------|-------------------|----------------|
| **Standalone `mab-run.sh`** | 1,134 lines, separate script | 80% duplicates existing infrastructure | **Cut.** Build `lib/run-plan-mab.sh` (~200-300 lines) |
| **LLM planner agent** | Full LLM call to decide routing | Thompson Sampling does this in 15 lines of bash; LLM planner needs data that doesn't exist | **Defer to Phase 3** (50+ runs) |
| **`architecture-map.sh`** | Scans imports to produce module graph | Claude reads files natively; static analysis misses dynamic imports; maintenance burden exceeds value | **Cut entirely** |
| **`pull-community-lessons.sh`** | Fetches lessons from upstream remote | `git pull` already propagates lesson files; only `strategy-perf.json` merge needs custom handling | **Cut.** Document git-based workflow instead |
| **`promote-mab-lessons.sh`** | Auto-promotes patterns with 3+ occurrences | String-matching dedup fails (same lesson, different phrasing); Pinecone semantic dedup is better but premature | **Defer to Phase 3** |
| **Planner agent prompt** | `scripts/prompts/planner-agent.md` | No data to route on; Thompson Sampling replaces for Phase 1 | **Defer to Phase 3** |

### 4.3 Components to Improve (research-informed changes)

| Component | Original design | Research improvement |
|-----------|----------------|---------------------|
| **Judge prompt** | 6 simultaneous evaluation dimensions | Start binary (winner + reasoning), add dimensions in phases |
| **Judge presentation** | Agent A always shown first | Randomize order; record which was shown first for bias analysis |
| **Strategy selection** | Fixed threshold (>70%, 10+ data points) | Thompson Sampling from Beta distribution; natural explore/exploit balance |
| **Strategy evolution** | Static strategies forever | Phase 2: extract winning behaviors from judge reasoning as new prompt variants (SEW pattern) |
| **Model variation** | Same model for both agents | Phase 2: extend `--sample` for heterogeneous models (SWE-bench TRAE pattern) |
| **Judge context** | No failure history | Inject `failure-patterns.json` data for this batch type into judge prompt |
| **Evaluation reproducibility** | No SHA tracking | Pin judge evaluation to commit SHAs (Carson's SHA discipline) |
| **Validation** | Trust judge from run 1 | Manually review first 10 decisions; compute agreement rate before automated routing |

---

## 5. Revised Implementation Phases

### Phase 1: Judge + Orchestration (build now)

**Goal:** Produce the first MAB run data. Everything else depends on having real data.

**Files:**
- Create: `scripts/lib/run-plan-mab.sh` (~250 lines)
- Create: `scripts/prompts/judge-agent.md`
- Create: `scripts/prompts/agent-a-superpowers.md`
- Create: `scripts/prompts/agent-b-ralph.md`
- Modify: `scripts/run-plan.sh` (replace competitive stub with `--mode mab`)
- Modify: `scripts/lib/run-plan-context.sh` (inject MAB lessons)
- Runtime data: `logs/strategy-perf.json`, `logs/mab-lessons.json`, `logs/mab-run-<ts>.json`

**Judge design (Phase 1 — binary):**
```
Input: Two diffs (randomized order), design doc, PRD, automated scores, failure history
Output: {"winner": "agent_a|agent_b", "confidence": "low|medium|high",
         "reasoning": "2-3 sentences", "sha_a": "...", "sha_b": "...",
         "presentation_order": "a_first|b_first"}
```

**Routing design (Phase 1 — Thompson Sampling):**
```bash
# 15 lines of bash, not an LLM call
wins_a=$(jq ".[\"$batch_type\"].superpowers.wins" strategy-perf.json)
losses_a=$(jq ".[\"$batch_type\"].superpowers.losses" strategy-perf.json)
wins_b=$(jq ".[\"$batch_type\"].ralph.wins" strategy-perf.json)
losses_b=$(jq ".[\"$batch_type\"].ralph.losses" strategy-perf.json)
sample_a=$(python3 -c "import random; print(random.betavariate($wins_a+1,$losses_a+1))")
sample_b=$(python3 -c "import random; print(random.betavariate($wins_b+1,$losses_b+1))")
# If samples within 0.1 of each other, MAB run (explore)
# Otherwise, route to higher sample (exploit)
```

**Estimated effort:** 2 batches (down from 6)

### Phase 2: Learning Loop (after 10+ runs)

**Goal:** The system gets smarter from its own data.

**New capabilities:**
- Thompson Sampling routing replaces MAB-everything default
- Prompt evolution: extract winning behaviors from judge reasoning → `logs/evolved-prompts.json`
- Heterogeneous model sampling: `--sample-models "sonnet,opus,haiku"`
- MAB lesson injection into batch context (enriched `generate_batch_context()`)
- Judge enrichment: add failure_mode and strategy_update fields

**Prerequisite:** 10+ completed MAB runs with manually validated judge decisions.

**Estimated effort:** 1 batch

### Phase 3: Strategy Discovery (after 50+ runs, maybe never)

**Goal:** The system discovers strategies humans didn't design.

**New capabilities:**
- Strategy archive (ADAS pattern): judge proposes new strategy descriptions
- LLM planner agent for complex multi-factor routing
- Pinecone semantic dedup for lesson accumulation
- Community strategy data aggregation (merge `strategy-perf.json` across users)
- Auto-promotion of recurring lessons with semantic matching

**Prerequisite:** 50+ runs, validated learning loop, clear signal that current strategies plateau.

**Estimated effort:** 2 batches

---

## 6. Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Judge produces inconsistent evaluations | High (first 10 runs) | Medium — bad data poisons routing | Manually validate first 10 decisions; don't enable automated routing until >80% agreement |
| Both agents produce similar output (low diversity) | Medium | High — MAB provides no value if candidates are identical | Phase 2: add model variation; monitor diff similarity between agents |
| Cost: 2x compute per MAB batch | Certain | Medium — doubles API spend | Thompson Sampling quickly converges, reducing MAB frequency; budget-aware routing |
| Position bias in judge | High (measured in literature) | Medium — systematically favors first-presented agent | Randomize order; log order in output; monitor win rates by presentation position |
| Strategy-perf.json data is sparse per batch type | High (early runs) | Low — Thompson Sampling handles sparse data gracefully via prior | Start with uniform prior Beta(1,1); don't route based on < 5 data points |
| Worktree merge conflicts | Low | Medium — winner branch may conflict with main | Judge should flag "both agents modified same files" as a risk signal |

---

## 7. Success Metrics

| Metric | Phase 1 target | Phase 2 target | Measurement |
|--------|---------------|---------------|-------------|
| MAB runs completed | 10 | 50 | Count of `logs/mab-run-*.json` files |
| Judge agreement with human review | >80% | >90% | Manual validation of first 10, spot-check after |
| Strategy differentiation | Agents produce measurably different diffs | Win rates diverge by batch type | Compare diff overlap between agents |
| Quality gate pass rate (winner) | >80% | >90% | `strategy-perf.json` aggregate |
| Routing accuracy (Phase 2+) | — | Thompson Sampling converges within 15 runs | Track cumulative regret vs oracle |
| Prompt evolution yield (Phase 2+) | — | 1 evolved variant per 5 runs | Count of `logs/evolved-prompts.json` entries |

---

## 8. Sources

### Academic Literature
- [Multi-Armed Bandits Meet Large Language Models — IBM Research, AAAI 2026](https://research.ibm.com/publications/multi-armed-bandits-meet-large-language-models)
- [When AIs Judge AIs: Agent-as-a-Judge Evaluation for LLMs](https://arxiv.org/html/2508.02994v1)
- [Multi-Agent Debate for LLM Judges with Adaptive Stability Detection](https://arxiv.org/html/2510.12697v1)
- [In-Context Dueling Bandits with LLM Agents](https://aclanthology.org/2025.findings-acl.519.pdf)
- [Evaluation and Benchmarking of LLM Agents: A Survey](https://arxiv.org/html/2507.21504v1)
- [SEW: Self-Evolving Agentic Workflows for Automated Code Generation](https://arxiv.org/abs/2505.18646)
- [EvoAgentX: An Automated Framework for Evolving Agentic Workflows](https://github.com/EvoAgentX/EvoAgentX)
- [ADAS: Automated Design of Agentic Systems — ICLR 2025](https://github.com/ShengranHu/ADAS)
- [SWE-bench Leaderboard: Profiling Architectures of Agent-Based Repair Systems](https://arxiv.org/html/2506.17208v2)
- [SWE-EVO: Benchmarking Coding Agents in Long-Horizon Software Evolution](https://arxiv.org/html/2512.18470v1)
- [Multi-Agent Evolution Framework for Code Generation](https://medium.com/@tkadeethum/multi-agent-evolution-framework-a-self-improving-system-for-code-generation-02f8ddbf2ec9)

### Practitioner Guides
- [Using LLM-as-a-Judge for Evaluation (Hamel Husain)](https://hamel.dev/blog/posts/llm-judge/)
- [LLM-as-a-Judge Evaluation: Complete Guide (Langfuse)](https://langfuse.com/docs/evaluation/evaluation-methods/llm-as-a-judge)
- [LLM-As-Judge: 7 Best Practices (Monte Carlo Data)](https://www.montecarlodata.com/blog-llm-as-judge/)
- [LLM-as-a-Judge Simply Explained (Confident AI)](https://www.confident-ai.com/blog/why-llm-as-a-judge-is-the-best-llm-evaluation-method)
- [Using LLM-as-a-Judge for Agent Outputs (Patronus AI)](https://www.patronus.ai/llm-testing/llm-as-a-judge)
- [Evaluating the Effectiveness of LLM-Evaluators (Eugene Yan)](https://eugeneyan.com/writing/llm-evaluators/)

### Industry Reports
- [2026 Agentic Coding Trends Report (Anthropic)](https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf)
- [The Rise of AI Teammates in Software Engineering 3.0](https://arxiv.org/html/2507.15003v1)
- [Coding for the Agentic World (O'Reilly)](https://www.oreilly.com/AgenticWorld/)
- [Top Open-Source Autonomous Agents & Frameworks](https://cline.bot/blog/top-11-open-source-autonomous-agents-frameworks-in-2025)
- [Best AI Coding Agents for 2026 (Faros AI)](https://www.faros.ai/blog/best-ai-coding-agents-2026)

### Notion Workspace
- Algorithms to Live By — Knowledge Hub (Gittins Index, explore/exploit, optimal stopping)
- Code Factory — Repo Setup for Agent-Driven Code Review (Ryan Carson's SHA-pinning pattern)
- Code Factory V2 Design (batch-type-aware routing, sampling-outcomes.json)

### Codebase (autonomous-coding-toolkit)
- `scripts/run-plan.sh` — main runner (293 lines, 3 modes)
- `scripts/lib/run-plan-headless.sh` — serial batch execution with retry/sampling (344 lines)
- `scripts/lib/run-plan-team.sh` — parallel batch groups (191 lines)
- `scripts/lib/run-plan-scoring.sh` — candidate scoring, batch classification, prompt variants (147 lines)
- `scripts/lib/run-plan-context.sh` — per-batch context assembly within token budget (151 lines)
- `scripts/lib/run-plan-quality-gate.sh` — quality gate with test regression detection (129 lines)
- `scripts/lib/run-plan-state.sh` — JSON state persistence (99 lines)
- `scripts/lib/run-plan-prompt.sh` — batch prompt builder with cross-context (139 lines)
- `scripts/quality-gate.sh` — composite gate: validation + lessons + lint + ast-grep + tests + memory (231 lines)
- `docs/plans/2026-02-22-mab-run-design.md` — approved MAB design (445 lines)
- `docs/plans/2026-02-22-mab-run-plan.md` — original implementation plan (2042 lines, 6 batches, 26 tasks)
