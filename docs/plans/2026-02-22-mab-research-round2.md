# Multi-Armed Bandit System: Research Report — Round 2

**Date:** 2026-02-22
**Status:** Research complete
**Scope:** Cost modeling, testing strategies, cross-domain analogies, coder toolkit workflow analysis, latent bugs
**Builds on:** `docs/plans/2026-02-21-mab-research-report.md` (Round 1)

---

## Executive Summary

Round 2 research expands beyond ML/AI literature into seven cross-domain analogies (chess tournaments, evolutionary biology, competitive programming, manufacturing dual-sourcing, adversarial collaboration, forecasting tournaments, ensemble methods), plus deep analysis of cost economics, testing methodology, and the full coder toolkit workflow. Key findings:

1. **Cost is manageable:** Two parallel agents cost ~$1.88-2.38 per task with prompt caching (83% reduction vs. uncached). Cache priming before parallel dispatch is the single biggest cost lever.
2. **Testing MAB requires synthetic bandits, not just integration tests.** Simulation with known ground truth, seeded randomness, and distribution-level assertions — not output equality.
3. **Three cross-domain patterns emerged independently across all seven analogies:** locked criteria before evaluation, diversity as signal, and discriminating starting conditions.
4. **The coder toolkit workflow has 8 latent issues** that should be fixed before or alongside MAB implementation, including a state schema mismatch that silently returns wrong test counts.
5. **The stop-hook/ralph-loop mechanism adapts naturally for MAB Agent B** — set up ralph-loop state in Agent B's worktree before `claude -p` launch.

**Action items for the revised implementation plan:** Fix Gap 6 (state schema bug), fix Gap 7 (JSON extraction fragility), wire planner into auto-compound.sh, and add cache-prime step before parallel agent dispatch.

---

## 1. Cost Economics

### 1.1 Concrete Pricing

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|-----------------------|------------------------|
| Claude Haiku 4.5 | $1.00 | $5.00 |
| Claude Sonnet 4.6 | $3.00 | $15.00 |
| Claude Opus 4.6 | $5.00 | $25.00 |
| Any model, >200K context | $6.00 input | $22.50 output |

**Real-world per-task costs (SWE-bench, from swe-rebench.com):**

| Agent/Model | Cost per Task | Tokens per Task | Resolved Rate |
|-------------|--------------|-----------------|---------------|
| Claude Sonnet 4.5 | $0.94 | ~1.9M | 47.1% |
| Claude Opus 4.6 | $0.93 | ~1.0M | 51.7% |
| Claude Code (product) | $3.50 | ~2.1M | 52.9% |

**Agent teams multiplier:** Anthropic's docs state teams use ~7x more tokens than single-agent sessions. Two parallel agents = ~2x per-agent cost with no automatic context sharing.

### 1.2 The Cache Priming Pattern

**Critical finding:** Claude Sonnet dropped from $5.29 to $0.91 per task with prompt caching — an 83% reduction. Cache reads cost 0.1x input price; cache writes cost 1.25x input price (one-time).

**Parallel agent gotcha:** When two agents fire simultaneously on uncached content, both create independent caches, doubling write costs and getting zero read savings.

**Fix:** Fire a single "prime the cache" call first with the shared context (system prompt + design doc + PRD + codebase summary), then launch both agents. Both agents get cache-read pricing on the shared prefix.

**Concrete cost model for MAB per batch:**

| Scenario | Cost per batch (2 agents) | 6-batch plan total |
|----------|--------------------------|-------------------|
| No caching | ~$5.29 × 2 = $10.58 | ~$63.48 |
| With cache priming | ~$0.94 × 2 = $1.88 | ~$11.28 |
| Single agent (no MAB) | ~$0.94 × 1 = $0.94 | ~$5.64 |

**Bottom line:** MAB doubles cost vs. single agent, but cache priming keeps it under $2/batch. The real cost concern is not per-batch — it's the judge call (~$0.50-1.00 additional per batch for evaluation).

### 1.3 Cost-Aware Thompson Sampling

Academic research formalizes "budgeted MAB" as a distinct problem class (UCB-B, Budget-UCB). Key techniques:

- **Cost-weighted priors:** Track `reward / cost` per arm, not just `reward`. Naturally deprioritizes expensive arms (Opus + extended thinking) unless they demonstrably outperform by more than the cost ratio.
- **Decaying violation budget:** Permit limited overspend early in learning, enforce strict compliance later. Maps directly to: early MAB runs explore freely, later runs exploit proven winners.
- **Pivot trigger:** A budget threshold at which all remaining pulls go to the current best arm regardless of uncertainty. Prevents runaway exploration.

**Recommendation for Phase 1:** Track cost per arm alongside win/loss. Don't optimize for it yet, but capture the data.

### 1.4 Agentic Plan Caching

A newer technique (arxiv 2506.14852) caches structured plan templates across semantically similar tasks. Result: 46.62% average cost reduction while maintaining 96.67% of optimal performance. Relevant if MAB runs similar task types repeatedly.

---

## 2. Testing Strategy for the MAB System

### 2.1 Testing the Bandit Algorithm

**Technique 1: Synthetic Bandits**

Build a synthetic environment with known ground truth. Define a matrix of true arm reward probabilities, generate simulated outcomes, run the algorithm, and verify convergence.

```bash
# Test: Thompson Sampling converges to the better arm
# Ground truth: arm_a wins 70%, arm_b wins 40%
test_thompson_convergence() {
    # Run 1000 simulated rounds with fixed seed
    result=$(python3 -c "
import random
random.seed(42)
wins_a, losses_a, wins_b, losses_b = 0, 0, 0, 0
choices = []
for i in range(1000):
    sample_a = random.betavariate(wins_a+1, losses_a+1)
    sample_b = random.betavariate(wins_b+1, losses_b+1)
    if sample_a >= sample_b:
        choices.append('a')
        if random.random() < 0.7: wins_a += 1
        else: losses_a += 1
    else:
        choices.append('b')
        if random.random() < 0.4: wins_b += 1
        else: losses_b += 1
# Assert: arm_a selected >70% of last 200 rounds
print(choices[-200:].count('a') / 200)
")
    # Should be >0.70 with high probability
    assertTrue "$(echo "$result > 0.70" | bc -l)" "Thompson Sampling should converge to better arm"
}
```

**Technique 2: Offline Replay Evaluation**

Log all MAB decisions and outcomes to `logs/mab-run-*.json`. Replay logged events against a candidate policy to validate that new routing logic would have performed at least as well as the historical policy.

**Key testing principles for stochastic systems (from CMU SEI):**
- Fix random seed for reproducibility
- Assert on distribution properties, not specific outputs ("arm A selected >70% of last N rounds" not "arm A selected at round 47")
- Run 10-20 replicates as baseline for estimating distribution properties
- Use KS test or chi-squared to compare output distribution to expected

### 2.2 Testing the LLM Judge

**Agreement rates from literature:**

| Context | Cohen's Kappa | Notes |
|---------|--------------|-------|
| Patch evaluation (clear cases) | 0.75 | High recall (0.94), precision (0.80) |
| Patch evaluation (full dataset) | 0.57 | Drops on ambiguous cases |
| Search query parsing | 0.807 → 0.639 | Position bias degrades by 0.17 |
| RAG evaluation (filtered) | 0.781-0.816 | "Substantial to almost perfect" |
| Human inter-rater (developers on patches) | Fleiss 0.31 | Humans themselves are inconsistent |

**Validation protocol (before trusting automated routing):**
1. Build rubric collaboratively (LLM drafts, expert refines)
2. Run judge on a clear benchmark where humans unanimously agree
3. Require kappa >= 0.70 on the clear subset before deploying
4. Track NPV separately — LLM judges are more reliable on INVALID (0.94-0.95) than VALID
5. Measure self-consistency: same input, different seeds → same output?
6. If >30% of cases have human disagreement, switch from categorical metrics to distributional (Jensen-Shannon Divergence)

**Judge test plan for Phase 1:**
- Prepare 10 synthetic evaluation pairs (known-better vs known-worse diffs)
- Run judge on each pair twice (once A-first, once B-first) = 20 evaluations
- Assert: >80% correct winner identification
- Assert: position bias < 15% (win rate difference between first/second position)
- Assert: self-consistency > 85% (same winner when re-run with same order)

### 2.3 Testing Nondeterministic Integration

The full MAB pipeline (agent dispatch → quality gate → judge → merge → learn) is inherently nondeterministic. Testing strategy:

- **Deterministic units:** Test each component in isolation with fixed inputs (e.g., test `run_judge()` with a fixed diff pair, test `thompson_sample()` with a fixed seed)
- **Stochastic integration:** Run the full pipeline N times on a trivial task (e.g., "add a docstring to this function") and assert statistical properties: winner is declared in >95% of runs, quality gate runs in 100%, state file is updated in 100%
- **Fault injection:** Test what happens when Agent A fails (exit non-zero), Agent B produces no diff, judge returns malformed JSON, merge conflicts occur

---

## 3. Cross-Domain Analogies

### 3.1 Computer Chess Tournaments (TCEC)

The closest structural analog. Two agents, identical hardware, identical problem, a judge picks the winner.

| TCEC Practice | MAB Application |
|---------------|-----------------|
| **Curated opening book** (bias toward decisive positions) | Pre-screen tasks for discriminating power. Trivially easy tasks (both ace) or impossible tasks (both fail) produce no signal. |
| **Adjudication rules** (auto-draw if engines agree ±0.08 for 10 plies) | Early termination: if both agents produce identical solutions (by diff similarity), declare a draw — don't burn judge tokens. If one passes all tests and the other passes none, skip detailed rubric — call it early. |
| **Same hardware, same time control** | Same model, same context budget, same token limit. Otherwise you're comparing resource allocation, not capability. |
| **Draw rate is a design problem** | If MAB produces too many ties, the task design is wrong. Fix the tasks, not the judge. Monitor tie rate as a health metric. |

### 3.2 Evolutionary Biology / Genetic Algorithms

| Biological Pattern | MAB Application |
|-------------------|-----------------|
| **Tournament selection pressure is a dial** (small tournament = diversity, large = convergence) | Number of tasks per MAB round controls signal-to-noise. More matches per round = more reliable signal but slower adaptation. |
| **Artificial selection drives local optima** (domesticated crops lose wild resilience) | If judge consistently favors one style, both agents converge to it. Diversity collapses. Monitor inter-agent diff similarity as a canary. |
| **Recombination > pure selection** | The real value isn't picking a winner — it's identifying *which parts* of each solution were stronger. Phase 2 judge should extract specific winning behaviors. |

### 3.3 Adversarial Collaboration (Kahneman)

| Scientific Practice | MAB Application |
|--------------------|-----------------|
| **Pre-registration of criteria** (both parties agree what evidence would change their mind before the experiment) | Judge rubric must be locked before agents see the task. If rubric is written after reviewing outputs, it unconsciously favors the impressive-looking answer. |
| **The joint design of the test is where value lies** | Defining what "better" means for each task class is harder and more valuable than the competition itself. |
| **Ask "on what dimension do these differ most?"** | Don't ask the judge "which is better overall?" — ask "on what dimension do these most differ, and which is better on that dimension?" Produces more actionable lessons. |

### 3.4 Manufacturing Dual Sourcing

| Procurement Pattern | MAB Application |
|--------------------|-----------------|
| **Credible threat of replacement drives improvement** | The mere existence of competition improves both agents. Keep both pipelines alive even when one is winning. |
| **Quality inconsistency between suppliers breaks integration** | If agents produce stylistically incompatible solutions (different abstractions, naming), the "winner" creates downstream debt. Judge needs a consistency criterion. |
| **Technology licensing outperforms pure competition** | Feed winning approach back to both agents before next round. Sharing knowledge produces better cumulative results than withholding it. Maps to injecting MAB lessons into both agents' context. |

### 3.5 Competitive Programming Judges (Codeforces/ICPC)

| Competition Practice | MAB Application |
|---------------------|-----------------|
| **Pre-test vs. system-test split** | Run agents against a visible "sanity check" suite first, then against a harder hidden suite for final judging. Prevents overfitting to visible rubric. |
| **Hacking** (competitors find inputs that break opponents' solutions) | After both agents submit, have each attempt to write a test case that breaks the other's solution. Valid breaking test = signal about code quality reasoning. (Phase 3 feature) |
| **Distinct verdict categories** (WA vs TLE vs RE) | Judge outputting only "Agent A wins" discards signal. "Agent A correct but 3x slower; Agent B had edge case bug at N=0" generates compounding knowledge. |

### 3.6 Forecasting Tournaments / Proper Scoring Rules

| Forecasting Pattern | MAB Application |
|--------------------|-----------------|
| **Proper scoring rules eliminate gaming** | Can an agent score well by optimizing for the judge rather than for correctness? If yes, the rubric isn't proper. Test by submitting impressive-looking-but-wrong solutions. |
| **Time-weighting for sequential competitions** | An agent that produces correct architecture early and refines is better than one that patches a wrong architecture — even if final outputs look identical. |
| **Panel of 2-3 judges beats single judge by 13-22%** | A single LLM judge is a single point of failure. Phase 2: use two judge calls with different temperatures and take majority vote. |

### 3.7 Ensemble Methods / Mixture of Experts

| ML Pattern | MAB Application |
|------------|-----------------|
| **Disagreement between agents IS the signal** | Two agents producing identical solutions = one agent. Track disagreement rate as a health metric. If it drops, tasks are too easy or agents have converged. |
| **Diversity must be actively promoted** | Same model + same context = correlated outputs. Structural diversity requires different prompting, tool access, context priming, or temperature. |
| **Gating network learns task-type trust** | A sophisticated judge learns "Agent A better on algorithmic; Agent B better on integration." Static rubrics lose this signal. |

### 3.8 Cross-Domain Synthesis

Three patterns appeared independently across all seven domains:

1. **Locked criteria before outputs are seen.** TCEC opening books, Kahneman's pre-registration, Codeforces hidden test suites, Brier score properness. The judge rubric must be defined and frozen before agents run.

2. **Homogeneous competition is waste.** Ensemble diversity, dual-sourcing, tournament selection pressure. If both agents converge to identical strategies, the competition produces zero information. Diversity is the asset; it must be actively maintained.

3. **Shared starting conditions must be pre-screened for discriminating power.** TCEC curated openings, speedrun set seeds, competitive programming difficulty calibration. Don't MAB trivially easy or impossibly hard tasks — they produce no signal.

---

## 4. Coder Toolkit Workflow Analysis

### 4.1 Full Skill Chain

```
USER INPUT
    │
    ▼
Phase 1: DESIGN ─────────── superpowers:brainstorming
    │                        Output: docs/plans/YYYY-MM-DD-<topic>-design.md
    │                        Gate: user approval
    ▼
Phase 2: PRD ────────────── /create-prd
    │                        Output: tasks/prd.json + tasks/prd-<feature>.md
    │                        Gate: user approval
    ▼
Phase 3: PLAN ───────────── superpowers:writing-plans
    │                        Output: docs/plans/YYYY-MM-DD-<feature>.md
    │                        Gate: user chooses execution mode
    ▼
Phase 3.5: ISOLATE ──────── superpowers:using-git-worktrees
    │                        Output: .worktrees/<branch>/, baseline test count
    │                        Gate: tests pass in clean worktree
    ▼
Phase 4: EXECUTE ────────── [4 modes, see below]
    │                        Gate: quality gate after every batch
    ▼
Phase 5: VERIFY ─────────── superpowers:verification-before-completion
    │                        Gate: ALL PRD criteria pass (shell commands)
    ▼
Phase 6: FINISH ─────────── superpowers:finishing-a-development-branch
                             Output: merge / PR / keep / discard
```

### 4.2 Four Execution Modes

| Mode | Entry Point | Context Model | Human Checkpoints | Best For |
|------|-------------|---------------|-------------------|----------|
| **4a: Subagent-Driven** | `superpowers:subagent-driven-development` | Fresh subagent per task | None after start | 1-10 tasks, interactive |
| **4b: Executing-Plans** | `superpowers:executing-plans` | Shared session (degrades) | Between batches | Medium plans, oversight needed |
| **4c: Headless** | `scripts/run-plan.sh` | Fresh `claude -p` per batch | None (autonomous) | 5+ batches, overnight |
| **4d: Ralph Loop** | `/ralph-loop` | Same session, iterates | None (until promise) | PRD-driven, open-ended |

Headless mode has 3 sub-modes: `headless` (serial), `team` (parallel groups), `competitive` (stub → becomes MAB).

### 4.3 Where MAB Fits

MAB replaces the competitive stub in headless mode. It sits at the Phase 4 execution layer:

```
Phase 3.5: ISOLATE
    │
    ├── MODE: headless ──── run_mode_headless() ──── serial batches
    ├── MODE: team ──────── run_mode_team() ──────── parallel groups
    ├── MODE: mab ──────── run_mode_mab() ──────── [NEW] two agents, judge picks winner
    │                       │
    │                       ├── Create worktree A (superpowers-led)
    │                       ├── Create worktree B (ralph-led)
    │                       ├── Cache-prime shared context
    │                       ├── Launch both agents in parallel
    │                       ├── Quality gate both
    │                       ├── Judge evaluates diffs (randomized order)
    │                       ├── Merge winner to main worktree
    │                       └── Update strategy-perf.json + mab-lessons.json
    │
    └── MODE: ralph ──────── /ralph-loop ──────── stop-hook iterations
```

### 4.4 State Files Across the Workflow

| File | Writer | Reader | Lifecycle |
|------|--------|--------|-----------|
| `docs/plans/*-design.md` | brainstorming | writing-plans, code-factory | Permanent |
| `tasks/prd.json` | /create-prd | verification, ralph-loop, run-plan.sh | Updated during execution |
| `docs/plans/*-<feature>.md` | writing-plans | all execution modes | Permanent |
| `.run-plan-state.json` | run-plan-state.sh | --resume, context injection | Per-execution |
| `progress.txt` | run-plan-prompt.sh | cross-batch context injection | Per-execution, append-only |
| `logs/failure-patterns.json` | run-plan-context.sh | batch context injection | Cross-run |
| `logs/sampling-outcomes.json` | run-plan-headless.sh | get_prompt_variants() | Cross-run |
| `logs/strategy-perf.json` | [NEW] run-plan-mab.sh | Thompson Sampling routing | Cross-run |
| `logs/mab-lessons.json` | [NEW] judge agent | batch context injection | Cross-run |
| `AGENTS.md` | run-plan-prompt.sh | agent teams | Per-execution |
| `.claude/ralph-loop.local.md` | setup-ralph-loop.sh | stop-hook.sh | Per-ralph-session |

### 4.5 Quality Gate Enforcement Points

1. **Worktree baseline** (Phase 3.5): Tests must pass before implementation begins
2. **Per-step** (Modes 4a/4b): Plan includes explicit "run test, verify it passes" steps
3. **Inter-batch** (Mode 4c): `run_quality_gate()` after every batch — lesson-check + tests + memory + regression + git clean
4. **Final verification** (Phase 5): ALL PRD criteria as shell commands, lesson-scanner agent
5. **Pre-merge** (Phase 6): Tests must pass before options are presented; re-tested after merge

### 4.6 Stop-Hook / Ralph Loop: MAB Adaptation

The stop-hook mechanism intercepts session exits and re-feeds the prompt. It's inherently single-session, while MAB needs two parallel sessions. However:

**Agent B (ralph-led) naturally fits ralph-loop.** In `run_mode_mab()`, before launching Agent B's `claude -p` call:
1. `cd "$worktree_b"`
2. Run `setup-ralph-loop.sh --completion-promise "ALL PRD CRITERIA PASS" --max-iterations 15`
3. Launch `claude -p` — the stop-hook will iterate Agent B until PRD criteria pass

Agent A (superpowers-led) terminates naturally after its last batch — no ralph-loop needed.

**Guard needed:** Both `.claude/ralph-loop.local.md` and the stop-hook are relative to `$PWD`. Since each MAB worktree has its own directory, state files are naturally isolated — but only if `cd "$worktree"` runs before `claude -p`. The current design doesn't explicitly `cd` — this must be added.

---

## 5. Latent Issues Found During Workflow Analysis

### Issue 1: State Schema Mismatch (Bug — affects all headless runs)

**File:** `scripts/lib/run-plan-context.sh:25`
**Problem:** `generate_batch_context()` reads `jq '[.batches[].test_count // 0] | max'` but `run-plan-state.sh` stores test counts at `.test_counts` (a flat key-value object), not `.batches[].test_count`.
**Impact:** The test count high-water-mark injected into batch context is always 0. All batches think they're starting from zero tests.
**Fix:** Change to `jq '[.test_counts // {} | to_entries[].value] | max // 0'`

### Issue 2: Judge JSON Extraction Is Fragile

**File:** `mab-run.sh` (planned) `run_judge()` function
**Problem:** `grep -o '{.*}' | head -1` fails on multi-line JSON, which LLM output frequently produces.
**Fix:** Use `python3 -c "import sys,json,re; m=re.search(r'\\{.*\\}', sys.stdin.read(), re.DOTALL); print(m.group(0) if m else '{}')"` or instruct judge prompt to output ONLY JSON and validate with `jq empty`.

### Issue 3: `--mab` Flag vs `--mode ab` Naming Inconsistency

**File:** MAB plan Batch 3, Tasks 9-10
**Problem:** The plan adds both a `--mab` boolean flag and a `--mode ab` enum value. These are parallel pathways that need reconciliation.
**Fix:** Use one canonical path: `run-plan.sh --mode mab`.

### Issue 4: Planner Agent Has No Caller

**File:** No file — gap in the plan
**Problem:** `scripts/prompts/planner-agent.md` is created in Batch 1 but never called by `auto-compound.sh` or any other script. The routing decision is purely manual.
**Fix:** Wire planner into `auto-compound.sh` between PRD generation and execution.

### Issue 5: `auto-compound.sh` Bypasses `writing-plans`

**File:** `scripts/auto-compound.sh`
**Problem:** Goes directly from PRD → Ralph loop, skipping plan writing entirely. This means MAB (which supports superpowers-led strategy that needs a plan) can't be exercised via `auto-compound.sh`.
**Fix:** Document this as intentional for the ralph-only pipeline. Add a `--plan-first` flag for when MAB or superpowers mode is desired.

### Issue 6: `sampling-outcomes.json` vs `strategy-perf.json` Confusion

**Problem:** Both files track win rates — one for prompt variants within a strategy (micro-MAB), one for strategies (macro-MAB). No documentation distinguishes them.
**Fix:** Add comment blocks to creation code and a section in ARCHITECTURE.md.

### Issue 7: MAB and Ralph Loop Compete for Session State

**Problem:** If a user activates `/ralph-loop` in a worktree that's also running inside `mab-run.sh`, both mechanisms are active simultaneously.
**Fix:** `run_mode_mab()` should write a `.mab-active` sentinel file in its worktrees. The ralph-loop setup should check for this and refuse to activate, or the MAB script should set up ralph-loop state itself (preferred — see Section 4.6).

### Issue 8: No Explicit `cd` Before Agent `claude -p` in MAB Worktrees

**Problem:** Each MAB agent's `claude -p` must run in its own worktree directory for proper isolation. The current design doesn't explicitly change directory.
**Fix:** Add `cd "$worktree_a" &&` before each `claude -p` invocation in `run_mode_mab()`.

---

## 6. Concrete Recommendations for Revised Plan

### Pre-MAB Fixes (do first)

| # | Fix | Effort | Impact |
|---|-----|--------|--------|
| 1 | Fix state schema mismatch (Issue 1) | 10 min | Fixes all headless runs |
| 2 | Canonical `--mode mab` naming (Issue 3) | 5 min | Prevents naming confusion |

### Phase 1 Architecture (replaces original Batches 1-3)

```
scripts/
├── lib/
│   └── run-plan-mab.sh          # ~250 lines, peer to headless/team
├── prompts/
│   ├── judge-agent.md            # Binary judge: winner + reasoning + SHAs
│   ├── agent-a-superpowers.md    # Superpowers-led batch execution prompt
│   └── agent-b-ralph.md          # Ralph-led iteration prompt
└── run-plan.sh                   # Add --mode mab dispatch
```

**`run-plan-mab.sh` responsibilities:**
1. Create two worktrees from current HEAD
2. Cache-prime shared context (design doc + PRD + codebase summary)
3. Launch both agents in parallel (`claude -p` with `cd "$worktree"`)
4. Wait for both to complete
5. Run quality gate on both
6. Call judge agent with randomized presentation order
7. Merge winner to main worktree
8. Update `logs/strategy-perf.json` and `logs/mab-lessons.json`
9. Clean up loser worktree

**Judge agent (Phase 1 — binary):**
```json
{
  "winner": "agent_a|agent_b|draw",
  "confidence": "low|medium|high",
  "reasoning": "2-3 sentences explaining the decision",
  "key_difference": "The specific dimension where agents most differed",
  "sha_a": "abc1234",
  "sha_b": "def5678",
  "presentation_order": "a_first|b_first"
}
```

**Routing (Phase 1 — Thompson Sampling, ~15 lines bash):**
```bash
sample_a=$(python3 -c "import random; random.seed(); print(random.betavariate($wins_a+1,$losses_a+1))")
sample_b=$(python3 -c "import random; random.seed(); print(random.betavariate($wins_b+1,$losses_b+1))")
delta=$(python3 -c "print(abs($sample_a - $sample_b))")
if (( $(echo "$delta < 0.10" | bc -l) )); then
    echo "mab"   # Uncertain — run both agents
else
    # Exploit — route to higher sample
    if (( $(echo "$sample_a > $sample_b" | bc -l) )); then
        echo "superpowers"
    else
        echo "ralph"
    fi
fi
```

**Early termination rules (from TCEC + Codeforces patterns):**
- If both agents produce identical diffs (>95% similarity): declare draw, skip judge
- If one agent passes all tests and other passes none: auto-declare winner, skip judge
- If both agents fail quality gate: declare no winner, retry batch in headless mode

### Phase 2 Additions (after 10+ runs)

- Judge enrichment: add `failure_mode`, `strategy_update`, `winning_behaviors` fields
- Prompt evolution from judge reasoning (SEW pattern) → `logs/evolved-prompts.json`
- Model variation: `--sample-models "sonnet,opus,haiku"` flag
- Panel judging: two judge calls, different temperatures, majority vote
- Wire planner agent into `auto-compound.sh` for automated routing

### Phase 3 Additions (after 50+ runs, maybe never)

- Strategy archive (ADAS pattern): judge proposes new strategy descriptions
- Hacking mechanism: each agent writes a test case to break the other (Codeforces pattern)
- Community strategy data aggregation
- Semantic lesson dedup via Pinecone

---

## 7. Updated Risk Matrix

| Risk | Likelihood | Impact | Mitigation | Source |
|------|-----------|--------|------------|--------|
| Judge inconsistency (first 10 runs) | High | Medium | Validate first 10 decisions manually; require kappa >= 0.70 | LLM-as-Judge literature |
| Low agent diversity (same outputs) | Medium | High | Monitor diff similarity; add model variation in Phase 2 | Ensemble methods, evolutionary biology |
| 2x compute cost | Certain | Low | Cache priming drops from $10.58 to $1.88/batch; Thompson Sampling reduces MAB frequency | SWE-bench cost data |
| Position bias in judge | High | Medium | Randomize order; log in output; monitor win rates by position | LLM-as-Judge research, Codeforces |
| Rubric gaming (agent optimizes for judge, not correctness) | Low (Phase 1) | High | Proper scoring rule design; hidden test suite for judge | Forecasting tournaments |
| State schema bug produces wrong test counts | Certain (existing) | Medium | Fix before MAB — affects all headless runs today | Workflow analysis |
| JSON extraction breaks on multiline judge output | High | Medium | Use multiline-aware extraction; validate with jq | Workflow analysis |
| Both mechanisms active (ralph-loop + MAB) | Low | Medium | MAB sets up ralph-loop state itself; sentinel file guard | Workflow analysis |
| Draw rate too high (no signal) | Medium | Medium | Pre-screen tasks for discriminating power; early termination rules | TCEC, comp programming |

---

## 8. Updated Success Metrics

| Metric | Phase 1 | Phase 2 | Measurement |
|--------|---------|---------|-------------|
| MAB runs completed | 10 | 50 | Count of `logs/mab-run-*.json` |
| Judge agreement with human | >80% | >90% | Manual review, Cohen's kappa |
| Judge self-consistency | >85% | >90% | Same input, different seed → same winner |
| Position bias | <15% | <10% | Win rate delta by presentation order |
| Agent diversity (diff similarity) | <80% overlap | <70% | Diff intersection / union |
| Cost per MAB batch | <$3.00 | <$2.50 | API billing, logged per run |
| Draw rate | <40% | <25% | Draws / total evaluations |
| Quality gate pass rate (winner) | >80% | >90% | strategy-perf.json aggregate |
| Thompson Sampling convergence | — | Within 15 runs | Cumulative regret vs oracle |
| Prompt evolution yield | — | 1 variant / 5 runs | evolved-prompts.json entries |

---

## 9. Sources

### Round 2 — New Sources

#### Cost & Economics
- [Manage costs effectively — Claude Code Docs](https://code.claude.com/docs/en/costs)
- [Claude API Pricing](https://platform.claude.com/docs/en/about-claude/pricing)
- [SWE-rebench Leaderboard](https://swe-rebench.com) (cost-per-task data)
- [Prompt Caching — Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- [Agentic Plan Caching — arxiv 2506.14852](https://arxiv.org/abs/2506.14852)
- [Budget-Constrained MAB — UCL/AAAI 2013](http://www0.cs.ucl.ac.uk/staff/w.zhang/rtb-papers/mab-adx.pdf)
- [Adaptive Budgeted UCB — arxiv 2505.02640](https://arxiv.org/pdf/2505.02640)

#### Testing & Validation
- [Validating LLM-as-a-Judge Under Rating Indeterminacy — CMU ML Blog](https://blog.ml.cmu.edu/2025/12/09/validating-llm-as-a-judge-systems-under-rating-indeterminacy/)
- [Judge's Verdict — arxiv 2510.09738](https://arxiv.org/pdf/2510.09738)
- [Seven Recommendations for Testing in a Non-Deterministic World — CMU SEI](https://www.sei.cmu.edu/blog/seven-recommendations-for-testing-in-a-non-deterministic-world/)
- [Statistical Testing of Stochastic Systems — U. Washington](https://homes.cs.washington.edu/~borning/papers/sevcikova-issta-2006.pdf)
- [Offline Bandit Evaluation — James LeDoux / Udemy](https://jamesrledoux.com/algorithms/offline-bandit-evaluation/)
- [Contextual R Package — Synthetic Bandit Simulation](https://nth-iteration-labs.github.io/contextual/)

#### Cross-Domain Analogies
- [TCEC Rules — Chessdom Wiki](https://wiki.chessdom.org/Rules)
- [Tournament Selection — Wikipedia](https://en.wikipedia.org/wiki/Tournament_selection)
- [Adversarial Collaboration — Kahneman / Edge.org](https://www.edge.org/adversarial-collaboration-daniel-kahneman)
- [Nature: Time for Adversarial Collaboration (2025)](https://www.nature.com/articles/d41586-025-01379-3)
- [Dual Sourcing — Management Science](https://pubsonline.informs.org/doi/10.1287/mnsc.41.8.1317)
- [Brier Score — Wikipedia](https://en.wikipedia.org/wiki/Brier_score)
- [Competitive Programming Judge Systems](https://en.wikipedia.org/wiki/Competitive_programming)
- [Codeforces Contest Rules](https://codeforces.com/blog/entry/4088)
- [Mixture of Experts — Wikipedia](https://en.wikipedia.org/wiki/Mixture_of_experts)
- [Ensemble Diversity — JMLR](https://jmlr.org/papers/volume24/23-0041/23-0041.pdf)
- [Speedrunning Verification](https://en.wikipedia.org/wiki/Speedrun)

### Round 1 Sources (from `2026-02-21-mab-research-report.md`)

See the original report for the full Round 1 source list covering academic MAB+LLM literature, LLM-as-Judge practitioner guides, SEW/ADAS research, SWE-bench analysis, and Notion workspace references.

### Codebase Files Analyzed

- Full skill chain: `skills/{brainstorming,writing-plans,using-git-worktrees,executing-plans,subagent-driven-development,verification-before-completion,finishing-a-development-branch}/SKILL.md`
- Commands: `commands/{code-factory,run-plan,ralph-loop}.md`
- Scripts: `scripts/run-plan.sh`, `scripts/auto-compound.sh`, all 8 `scripts/lib/run-plan-*.sh` modules
- Hooks: `hooks/stop-hook.sh`, `hooks/hooks.json`
- Architecture: `docs/ARCHITECTURE.md`
- MAB design + plan: `docs/plans/2026-02-22-mab-run-{design,plan}.md`
