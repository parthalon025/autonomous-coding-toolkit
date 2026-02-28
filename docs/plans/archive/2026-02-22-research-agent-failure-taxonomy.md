# Research: Agent Failure Taxonomy — Why AI Coding Agents Fail

**Date:** 2026-02-22
**Researcher:** Claude Opus 4.6 (research agent)
**Confidence:** High (12 primary sources, 6 empirical studies with >35,000 data points)

---

## Executive Summary

Academic literature identifies **5-7 top-level failure categories** for AI coding agents, compared to the toolkit's 3 clusters. The toolkit's taxonomy (Silent Failures, Integration Boundaries, Cold-Start Assumptions) maps well to implementation-level failures but misses three major failure classes that dominate in empirical studies: **Specification Misunderstanding** (agents solve the wrong problem), **Planning Failures** (agents decompose tasks incorrectly), and **Context Degradation** (quality declines as context grows). These three categories account for an estimated 40-55% of all agent failures in the literature, yet the toolkit has zero lessons addressing them.

The toolkit's strengths are real — its integration boundary and silent failure coverage is more granular than any academic taxonomy. But its blind spots are systematic: it captures failures that happen *during* correct implementation but not failures that happen *before* implementation begins (wrong task, wrong plan, wrong context).

**Recommendation:** Add 3 new root cause clusters to the taxonomy. Keep the existing 3. The result is a 6-cluster model that covers the full agent failure surface.

---

## 1. What Does Academic Literature Say About Why Coding Agents Fail?

### 1.1 The Landscape of Empirical Studies

Six major empirical studies (2024-2026) provide quantitative failure analysis:

| Study | Scope | Key Finding |
|-------|-------|-------------|
| Jimenez et al. (2024) — SWE-Bench | 2,294 GitHub issues | Agents solve 3-65% depending on model/benchmark variant |
| SWE-EVO (2025) | Long-horizon evolution tasks | Best model (GPT-5) solves only 21% vs 65% on SWE-Bench Verified |
| Failed Agentic PRs (2026) | 33,596 agent-authored PRs | 71.5% merge rate overall; 38% of rejections are abandoned without review |
| Unmerged Fix PRs (2026) | 326 closed-unmerged PRs | 12 failure reasons; test failures (18%) and redundancy (22%) dominate |
| Autonomous Agent Failures (2025) | 204 runs, 3 frameworks | ~50% completion rate; planning errors dominate |
| MAST (2025) | 1,600+ traces, 7 frameworks | 14 failure modes in 3 categories; coordination failures = 37% |

### 1.2 Convergent Findings Across Studies

Despite different methodologies, all studies converge on a consistent set of root causes:

1. **Specification/instruction misunderstanding** — agents solve the wrong problem (strongest models fail here most)
2. **Implementation errors** — correct understanding but wrong code (weaker models fail here most)
3. **Tool/environment misuse** — incorrect invocation of editing tools, test runners, file paths
4. **Context/retrieval failures** — agents lose critical information or retrieve irrelevant context
5. **Planning failures** — incorrect task decomposition, unrealistic plans, failed self-refinement
6. **Verification gaps** — superficial or absent validation of generated code

**Confidence: High.** These categories appear independently in 4+ studies with different datasets and methodologies.

### 1.3 Distribution of Failure Causes

Synthesizing across studies, the approximate distribution:

| Failure Class | Estimated Share | Primary Sources |
|---------------|----------------|-----------------|
| Specification misunderstanding | 15-25% | SWE-EVO (60%+ for GPT-5), Failed PRs (4% unwanted features) |
| Incorrect implementation | 20-30% | SWE-EVO (70% for open-source models), Code gen study (functional bugs 13-69%) |
| Planning failures | 10-20% | Autonomous agent study (dominant failure mode), MAST |
| Context/retrieval failures | 10-15% | Context rot studies (13.9-85% degradation), consolidation gap research |
| Tool/environment misuse | 5-15% | SWE-EVO, autonomous agent study (tool exploitation failures) |
| Verification gaps | 10-20% | MAST (21.3%), unmerged PRs (test failures 18.1%) |
| Process/coordination issues | 5-15% | MAST (36.9% coordination), abandoned PRs (38%) |

**Note:** These ranges overlap because studies use different taxonomies and granularity. A single failure often has multiple contributing causes.

**Confidence: Medium.** Individual study numbers are solid; cross-study synthesis requires interpretation due to taxonomy differences.

---

## 2. Failure Modes Unique to Autonomous Agents vs Human-in-the-Loop

### 2.1 Autonomous-Only Failure Modes

These failure modes are absent or rare with human-in-the-loop but frequent in autonomous execution:

| Failure Mode | Why Autonomous-Only | Toolkit Coverage |
|-------------|---------------------|-----------------|
| **Stuck in loop** — agent repeats same actions without progress | Human would notice and redirect after 1-2 iterations | None |
| **Premature termination** — agent gives up with viable paths remaining | Human would suggest next steps | None |
| **Context window overflow** — quality degrades as context fills | Human sessions are shorter and reset naturally | Implicit (ARCHITECTURE.md design principle, but no lesson) |
| **Cascading retry failure** — each retry compounds errors from previous attempts | Human would reset approach rather than building on failures | None |
| **Overthinking/safety conflicts** — larger models refuse viable actions due to safety training | Human can override or rephrase | None |
| **Failed self-refinement** — agent identifies error but applies wrong fix in loop | Human would catch the meta-error | None |

### 2.2 Amplified Failure Modes

These exist in human-in-the-loop but are much worse in autonomous mode:

| Failure Mode | Human-in-Loop Severity | Autonomous Severity | Toolkit Coverage |
|-------------|------------------------|---------------------|-----------------|
| **Specification drift** — gradual deviation from intent | Low (human catches early) | High (compounds over batches) | None |
| **Integration blindness** — unit tests pass, integration fails | Medium | High (no human to spot it) | Strong (Cluster B) |
| **Silent failures** — errors produce no visible signal | Medium | Critical (no human watching) | Strong (Cluster A) |
| **Test adequacy illusion** — tests pass but don't cover the bug | Medium | High (agent trusts green tests) | Partial (lesson 0008) |

### 2.3 Key Insight

**The toolkit's taxonomy is biased toward implementation-phase failures because it was derived from a human-in-the-loop workflow** where Justin catches specification, planning, and context errors himself. In fully autonomous mode, these pre-implementation failures become the dominant failure class.

**Confidence: High.** This is a structural observation supported by the data — the toolkit's 61 lessons contain zero entries about the agent misunderstanding the task, decomposing it incorrectly, or losing context.

---

## 3. Failure Taxonomies Used by SWE-Bench, OpenHands, and SWE-Agent

### 3.1 SWE-EVO Taxonomy (7 categories)

The most granular benchmark-derived taxonomy, from SWE-EVO (2025):

| Category | Definition | Distribution (GPT-5) | Distribution (Open-Source) |
|----------|-----------|----------------------|---------------------------|
| Syntax Error | Patch breaks parsing/formatting | <5% | 5-10% |
| Incorrect Implementation | Right area, wrong behavior | 15-20% | ~70% |
| Instruction Following | Misreads or ignores requirements | 60%+ | 10-15% |
| Tool-Use | Failed invocation of agent tools | <5% | 10-15% |
| Stuck in Loop | Repeats actions without progress | <5% | 15-20% |
| Gave Up Prematurely | Terminates with viable paths remaining | <5% | 10-15% |
| Other | Rare/ambiguous failures | <5% | <5% |

**Key finding:** As models get stronger, **instruction following** (not implementation) becomes the dominant failure mode. This is counter-intuitive but robust across SWE-EVO and SWE-Bench Pro data.

### 3.2 OpenHands Agent Analysis

OpenHands provides a trajectory-level analysis framework:

- Agents correctly identify problematic files in **72-81% of cases even in failures**
- Success depends on **approximate rather than exact** code modifications
- Failed trajectories are **consistently longer and more variable** than successful ones
- **Consolidation gap:** agents "see" 100% of relevant code but only retain 50-70% in final context

### 3.3 Three-Tier Autonomous Agent Taxonomy

From the comprehensive autonomous agent failure study (2025):

**Phase 1 — Planning:** Improper task decomposition, failed self-refinement, unrealistic planning
**Phase 2 — Execution:** Tool exploitation failures, code generation defects, environmental setup issues
**Phase 3 — Response:** Context window constraints, formatting issues, interaction limits exceeded

### 3.4 MAST Framework (Multi-Agent Systems)

14 failure modes in 3 categories, from 1,600+ annotated traces:

**Category 1 — System Design:** Poor prompt design, missing role constraints, lack of termination criteria
**Category 2 — Inter-Agent Misalignment:** Communication breakdowns, state synchronization issues, conflicting objectives (36.9% of all failures)
**Category 3 — Task Verification:** Superficial checks, compilation-only validation, inconsistent comment verification (21.3%)

### 3.5 Code Generation Error Taxonomy

From the comprehensive LLM code generation study (2024):

**Type A — Syntax Bugs** (<10%): Incomplete syntax, indentation, import errors
**Type B — Runtime Bugs** (5-45%): API misuse, undefined references, boundary conditions, argument errors
**Type C — Functional Bugs** (13-69%): Logic errors, hallucinations, I/O format errors

**Critical distribution insight:** Functional bugs (logic errors, wrong algorithm) increase with problem complexity. Syntax bugs are nearly eliminated by modern LLMs. The remaining challenge is *semantic correctness*.

---

## 4. Failure Classes the Toolkit's Lesson System Cannot Catch

### 4.1 Structural Blind Spots

The toolkit's lesson system catches pattern-level anti-patterns in code. These failure classes operate at a different level of abstraction:

| Failure Class | Why Uncatchable | Estimated Prevalence | Example |
|---------------|----------------|---------------------|---------|
| **Requirement misunderstanding** | No code pattern to grep for; the code is correct for the wrong spec | 15-25% | Agent implements caching when spec asked for rate limiting |
| **Architectural mismatch** | Decision is sound locally but wrong for the system; needs global context | 5-10% | Agent adds polling when system uses event-driven architecture |
| **Plausible-but-wrong patches** | Tests pass but behavior is incorrect; needs semantic verification | 10-15% | Fix handles reported case but breaks unreported edge case |
| **Context consolidation failures** | Agent saw the relevant code but lost it by patch time | 10-15% | Agent reads file with constraint, edits another file without applying constraint |
| **Planning over-decomposition** | Too many steps create compounding error probability | 5-10% | 20-step plan where step 3 error cascades through steps 4-20 |
| **Hallucinated APIs/libraries** | Agent invents functions, parameters, or entire libraries that don't exist | 5-10% | `from sklearn.ensemble import AdaptiveGBM` (doesn't exist) |

### 4.2 What the Lesson System CAN Catch

For contrast, the toolkit excels at catching:

- Implementation-level anti-patterns (bare except, missing await, wrong pip path)
- Integration boundary violations (schema drift, unit mismatch, path confusion)
- Resource lifecycle errors (missing unsubscribe, connection leaks)
- Test anti-patterns (hardcoded counts, lint spirals, format mismatches)

### 4.3 The Gap in Numbers

**Toolkit's 61 lessons cover approximately 30-40% of the total failure surface** identified in academic literature. The missing 60-70% is concentrated in pre-implementation failures (specification, planning, context) and post-implementation verification gaps (plausible-but-wrong patches).

**Confidence: Medium-High.** The "30-40%" estimate is derived from mapping toolkit lessons against academic taxonomies. The exact number depends on task mix — for bug-fix-only tasks the toolkit covers more; for greenfield features it covers less.

---

## 5. Distribution of Failure Causes

### 5.1 Four-Way Split

Synthesizing across all studies, failures cluster into four macro-categories:

```
Specification Failures (20-25%)
├── Requirement misunderstanding
├── Instruction following errors
├── Unwanted/misaligned features
└── Wrong task description

Reasoning Failures (25-35%)
├── Incorrect implementation logic
├── Missing edge cases
├── Hallucinated APIs/behavior
└── Plausible-but-wrong patches

Tool/Environment Failures (10-20%)
├── Tool invocation errors
├── File path mistakes
├── Environmental setup issues
└── Context window overflow

Verification Failures (15-25%)
├── Insufficient test coverage
├── Superficial validation
├── Test adequacy illusion
└── Missing integration tests
```

### 5.2 The Counter-Intuitive Finding

**Better models fail differently, not less.** GPT-5 on SWE-EVO shows 60%+ of failures are instruction-following errors, not implementation bugs. As implementation capability improves, specification understanding becomes the bottleneck.

This has a direct implication for the toolkit: **quality gates that check code correctness (lesson-check, test suites) will catch a shrinking share of failures over time.** The growing failure mode — specification misunderstanding — requires a different kind of gate.

### 5.3 Context Degradation as a Force Multiplier

Context degradation is not a failure mode itself but a **force multiplier for all other failure modes**:

- Models experience **13.9-85% performance degradation** as input length increases, even within claimed context windows
- Performance degradation is **worse on complex tasks** than simple ones
- **Coherent context is harder to process** than shuffled text (counter-intuitive but empirically validated)
- The "consolidation gap" means agents lose 30-50% of relevant information between retrieval and patch generation

The toolkit's architecture (fresh context per batch) directly addresses this. But the lesson system doesn't capture *why* this matters or what happens when it fails.

**Confidence: High.** Context degradation is one of the most robustly measured phenomena, with 5+ independent studies and consistent results across models.

---

## 6. How Failure Modes Differ by Task Type

### 6.1 Merge Success Rates by Task Type

From the 33,596 PR analysis:

| Task Type | Merge Rate | Primary Failure Mode |
|-----------|-----------|---------------------|
| Documentation | 84% | Rarely fails |
| CI/Build | 74-79% | Configuration errors |
| Refactoring | ~75% | Behavioral regression |
| Feature addition | ~70% | Specification misunderstanding |
| Bug fix | 64% | Plausible-but-wrong patches |
| Performance | 55% | Incorrect optimization strategy |

### 6.2 Failure Mode Distribution by Task Type

| Failure Mode | Bug Fix | New Feature | Refactoring |
|-------------|---------|-------------|-------------|
| Specification error | Low | **High** | Medium |
| Implementation error | **High** | Medium | Low |
| Test adequacy gap | **High** | Medium | Low |
| Integration boundary | Medium | Medium | **High** |
| Architectural mismatch | Low | **High** | Medium |
| Context overflow | Low | **High** | Low |

### 6.3 Implications for the Toolkit

The toolkit's lesson system is best suited for **bug fix and refactoring tasks** where implementation-level patterns dominate. It is weakest for **new feature development** where specification understanding and architectural decisions are the primary failure modes.

This matches the toolkit's origin story — lessons derived from implementation experience, not from feature design sessions.

**Confidence: Medium.** Task-type distributions are from a single large study. The directional findings are consistent across studies but exact percentages may vary.

---

## 7. Failure Prevention Strategies with Empirical Support

### 7.1 Strategies with Strong Evidence

| Strategy | Evidence Source | Effect | Toolkit Implementation |
|----------|---------------|--------|----------------------|
| **Fresh context per unit of work** | Context rot studies (5+) | Prevents 13.9-85% degradation | Yes — core architecture |
| **Test-driven development** | SWE-Bench, code gen studies | Catches implementation errors at write time | Yes — quality gates |
| **Retry with escalation** | Autonomous agent study | Success improves through iteration 10, plateaus after | Yes — run-plan.sh retry logic |
| **Dual-track verification** | MAST, UTBoost | Catches plausible-but-wrong patches | Partial — A/B verification exists |
| **Monotonic test counts** | Toolkit's own data | Prevents test deletion/breakage | Yes — quality gates |

### 7.2 Strategies with Moderate Evidence

| Strategy | Evidence Source | Effect | Toolkit Implementation |
|----------|---------------|--------|----------------------|
| **RAG-based context injection** | Hallucination study (2024) | Reduces hallucinated APIs/libraries | Partial — per-batch context injection |
| **Specification validation before coding** | Failed PR study, MAST | Catches wrong-task errors early | Partial — brainstorming stage |
| **Multi-agent review** | MAST, multi-agent coding studies | Catches errors single agent misses | Yes — subagent-driven-development |
| **Fault localization first** | OpenHands analysis | 72-81% correct even in failures; build on this | No explicit strategy |
| **Meta-controller for error routing** | Autonomous agent study | Routes planning vs execution errors to different fix strategies | No |

### 7.3 Strategies with Emerging Evidence

| Strategy | Evidence Source | Effect | Toolkit Implementation |
|----------|---------------|--------|----------------------|
| **Specification diffing** — compare agent's understanding against human intent before coding | Addy Osmani (2025), spec writing guides | Catches requirement misunderstanding pre-implementation | No |
| **Behavioral regression testing** — test observable behavior, not just return values | UTBoost (ACL 2025) | Catches plausible-but-wrong patches that pass unit tests | No |
| **Trajectory length monitoring** — flag when agent trajectory exceeds 2x median | OpenHands trajectory analysis | Early warning for stuck/looping agents | No |
| **Confidence-gated commits** — agent declares confidence; low-confidence changes get extra review | Emerging practice | Routes uncertain code to human review | No |

**Confidence: High for 7.1, Medium for 7.2, Low-Medium for 7.3.** Strong-evidence strategies have multiple independent validations. Emerging strategies have theoretical support and early results but limited replication.

---

## 8. Gap Analysis: Toolkit's 3-Cluster Taxonomy vs Academic Taxonomies

### 8.1 Coverage Matrix

| Academic Failure Category | Toolkit Cluster | Coverage Level | Notes |
|--------------------------|----------------|---------------|-------|
| Syntax errors | Cluster A (Silent) | Partial | Lessons cover some (0022 JSX, 0010 bash), but not code gen syntax errors |
| Runtime errors / API misuse | Cluster A + B | Strong | Lessons 0002, 0005, 0006, 0033, etc. |
| Functional/logic errors | Cluster B (Integration) | Strong | Lessons 0015, 0018, 0031, etc. |
| Silent failures | Cluster A (Silent) | **Excellent** | 21 lessons — most granular coverage of any taxonomy |
| Integration boundary errors | Cluster B (Integration) | **Excellent** | 27 lessons — unmatched depth |
| Cold-start failures | Cluster C (Cold-Start) | Good | 4 lessons — small but well-defined |
| **Specification misunderstanding** | **None** | **Missing** | Zero lessons. Major gap. |
| **Planning/decomposition errors** | **None** | **Missing** | Zero lessons. Addressed architecturally but not in lesson system. |
| **Context degradation** | **None** | **Missing** | Addressed by architecture (fresh context) but no lessons capture what to do when it fails. |
| **Stuck in loop / premature termination** | **None** | **Missing** | No lessons. Ralph loop has stop conditions, but no diagnostic lessons. |
| **Hallucination (API/library)** | **None** | **Missing** | No lessons about fabricated APIs, wrong library versions, invented parameters. |
| **Verification gaps** | Partial | **Weak** | Lesson 0008 (quality gate blind spot) is the only entry. Academic literature identifies this as 15-25% of failures. |
| **Tool/environment misuse** | Cluster B | Partial | Lesson 0006 (pip path), 0044 (worktree deps), but missing broader tool invocation failures. |
| **Coordination failures (multi-agent)** | Cluster B | Partial | Lesson 0037 (parallel agents), but missing communication and state sync failures. |

### 8.2 Completeness Score

**Toolkit covers 4 of 9 major failure categories well, 2 partially, and 3 not at all.**

Mapping by estimated failure prevalence:

- **Well covered** (Clusters A, B, C): ~35-45% of failures
- **Partially covered**: ~10-15% of failures
- **Not covered** (specification, planning, context, hallucination, loops): ~40-55% of failures

### 8.3 What the Toolkit Does Better Than Academia

The academic taxonomies have their own gaps that the toolkit fills:

1. **Granularity of implementation-level patterns.** No academic taxonomy distinguishes "bare except swallowing" from "async def without await" from "cache replace vs merge." The toolkit's 61 lessons provide grep-detectable specificity that academic categories lack.

2. **Actionability.** Academic taxonomies describe *what* fails. The toolkit's lessons describe *what to do about it* — with corrective actions, 5-whys analysis, and sustain plans.

3. **Compounding enforcement.** Academic taxonomies are descriptive. The toolkit turns lessons into automated checks (lesson-check.sh, hookify rules, quality gates). No academic framework has this feedback loop.

4. **Integration boundary depth.** The toolkit's 27 integration boundary lessons constitute the most detailed treatment of this failure class in any source reviewed.

---

## 9. Recommendations: New Lesson Categories

### 9.1 Proposed 6-Cluster Taxonomy

Retain the existing 3 clusters. Add 3 new ones:

| Cluster | Name | Description | Priority |
|---------|------|-------------|----------|
| A | Silent Failures | (existing) Something fails with no error signal | — |
| B | Integration Boundaries | (existing) Bug hides at seam between components | — |
| C | Cold-Start Assumptions | (existing) Works steady-state, fails on restart | — |
| **D** | **Specification Drift** | **Agent solves the wrong problem or deviates from intent** | **High** |
| **E** | **Context & Retrieval** | **Agent loses, ignores, or hallucinates critical information** | **High** |
| **F** | **Planning & Control Flow** | **Agent decomposes incorrectly, loops, or terminates prematurely** | **Medium** |

### 9.2 Proposed Starter Lessons per New Cluster

#### Cluster D: Specification Drift

| ID | Title | Type | Source |
|----|-------|------|--------|
| D-1 | Agent implements feature the spec didn't ask for | semantic | SWE-EVO instruction following |
| D-2 | Specification ambiguity resolved incorrectly by agent | semantic | Failed PR study |
| D-3 | Agent addresses symptom instead of root cause in bug fix | semantic | APR plausible-but-wrong patches |
| D-4 | Refactoring changes observable behavior (semantic regression) | semantic | Task-type failure analysis |

#### Cluster E: Context & Retrieval

| ID | Title | Type | Source |
|----|-------|------|--------|
| E-1 | Agent reads constraint in file A but ignores it when editing file B | semantic | Consolidation gap research |
| E-2 | Agent hallucinates API that doesn't exist in the library version used | semantic | Library hallucination study |
| E-3 | Long context causes quality degradation mid-task | semantic | Context rot studies |
| E-4 | RAG retrieval includes irrelevant code that distracts agent | semantic | Long-context LLM + RAG study |

#### Cluster F: Planning & Control Flow

| ID | Title | Type | Source |
|----|-------|------|--------|
| F-1 | Agent loops on same failed approach without changing strategy | semantic | SWE-EVO (stuck in loop) |
| F-2 | Agent gives up with viable approaches remaining | semantic | SWE-EVO (premature termination) |
| F-3 | Over-decomposed plan creates compounding error across steps | semantic | Autonomous agent study |
| F-4 | Agent self-refinement applies wrong fix to correctly-identified error | semantic | Failed self-refinement research |

### 9.3 New Diagnostic Shortcuts

| Symptom | Check First |
|---------|-------------|
| Agent's output is correct code that solves the wrong problem | D-1, D-2 |
| Fix works for reported case but breaks other cases | D-3 |
| Agent ignores information it read 10 minutes ago | E-1, E-3 |
| Code references API/function that doesn't exist | E-2 |
| Agent retries the same approach 3+ times | F-1 |
| Agent declares "done" but obvious work remains | F-2 |
| Step 7 of 15 fails because step 3 was wrong | F-3 |

### 9.4 New Prevention Strategies to Implement

**High priority (strong evidence):**

1. **Specification echo-back gate.** Before coding, agent must restate the requirement in its own words. Human or automated check compares against original spec. Catches Cluster D failures. (Evidence: SWE-EVO, Addy Osmani spec guidance.)

2. **Trajectory length alarm.** If agent trajectory exceeds 2x the median for that task type, trigger a warning and force re-evaluation. Catches Cluster F failures. (Evidence: OpenHands trajectory analysis — failed runs are consistently longer.)

3. **Library/API existence check.** Before using any import or API call, verify it exists in the installed version. Catches Cluster E hallucination failures. (Evidence: Library hallucination study.)

**Medium priority (moderate evidence):**

4. **Constraint propagation check.** After reading a file with constraints, verify those constraints appear in subsequent edits. Catches consolidation gap (Cluster E).

5. **Behavioral regression tests.** Add tests for observable behavior (not just return values) to catch plausible-but-wrong patches. (Evidence: UTBoost.)

6. **Context budget monitoring.** Track context window utilization; trigger context pruning or fresh-start when approaching limits. (Evidence: Context rot studies.)

---

## 10. Sources

### Empirical Studies (Primary Sources)

1. Jimenez, C. E., et al. (2024). "SWE-Bench: Can Language Models Resolve Real-World GitHub Issues?" ICLR 2024. https://arxiv.org/pdf/2310.06770

2. SWE-EVO (2025). "Benchmarking Coding Agents in Long-Horizon Software Evolution Scenarios." https://arxiv.org/html/2512.18470

3. "Where Do AI Coding Agents Fail? An Empirical Study of Failed Agentic Pull Requests in GitHub." (2026). https://arxiv.org/html/2601.15195v1

4. "Why Are AI Agent-Involved Pull Requests (Fix-Related) Remain Unmerged? An Empirical Study." (2026). https://arxiv.org/html/2602.00164

5. "Exploring Autonomous Agents: A Closer Look at Why They Fail When Completing Tasks." (2025). https://arxiv.org/html/2508.13143v1

6. Cemri, M., Pan, M. Z., Yang, S., et al. (2025). "Why Do Multi-Agent LLM Systems Fail?" (MAST Framework). https://arxiv.org/abs/2503.13657

### Code Generation Error Analysis

7. "What's Wrong with Your Code Generated by Large Language Models? An Extensive Study." (2024). https://arxiv.org/html/2407.06153v1

8. "Understanding Code Agent Behaviour: An Empirical Study of Success and Failure Trajectories." (2025). https://arxiv.org/abs/2511.00197

9. "LLM Hallucinations in Practical Code Generation: Phenomena, Mechanism, and Mitigation." ISSTA 2025. https://arxiv.org/abs/2409.20550

10. "Library Hallucinations in LLMs." (2025). https://arxiv.org/pdf/2509.22202

### Context Degradation

11. "Context Length Alone Hurts LLM Performance Despite Perfect Retrieval." EMNLP 2025. https://arxiv.org/abs/2510.05381

12. "Context Rot: How Increasing Input Tokens Impacts LLM Performance." Chroma Research (2025). https://research.trychroma.com/context-rot

13. "Context Discipline and Performance Correlation." (2026). https://arxiv.org/html/2601.11564v1

### Evaluation & Verification

14. "UTBoost: Rigorous Evaluation of Coding Agents on SWE-Bench." ACL 2025. https://aclanthology.org/2025.acl-long.189/

### Agent Frameworks & Tools

15. OpenHands Agent Analysis. https://github.com/OpenHands/agent-analysis

16. "RepairAgent: An Autonomous, LLM-Based Agent for Program Repair." (2024). https://arxiv.org/abs/2403.17134

### Industry Reports

17. Answer.AI independent evaluation of Devin. Reported via IT Pro, The Register, Futurism (2025). 15% task completion rate on 20 tasks.

18. IEEE Spectrum. "AI Coding Degrades: Silent Failures Emerge." (2025). https://spectrum.ieee.org/ai-coding-degrades

---

## Appendix A: Full Mapping of Toolkit Lessons to Academic Categories

| Toolkit Lesson | Academic Category | SWE-EVO Equivalent | MAST Equivalent |
|---------------|-------------------|--------------------|-----------------|
| 0001 (bare except) | Silent failure | — | — |
| 0002 (async without await) | Runtime bug (API misuse) | Syntax Error | — |
| 0004 (hardcoded counts) | Test anti-pattern | — | Task Verification |
| 0015 (schema drift) | Integration boundary | Incorrect Implementation | Inter-Agent Misalignment |
| 0018 (unit pass, integration fail) | Verification gap | — | Task Verification |
| 0037 (parallel agent staging) | Coordination failure | — | Inter-Agent Misalignment |
| 0055 (garbled batch prompts) | Context/retrieval | Instruction Following | System Design |

## Appendix B: Academic Taxonomy Comparison Table

| Dimension | SWE-EVO | MAST | Autonomous Agent Study | Failed PR Study | Toolkit |
|-----------|---------|------|----------------------|-----------------|---------|
| # of top-level categories | 7 | 3 | 3 (phases) | 3 | 3 |
| # of leaf categories | 7 | 14 | 9 | 12 | 6* |
| Covers specification errors | Yes | Yes | Yes | Yes | **No** |
| Covers planning errors | No | Yes | Yes | No | **No** |
| Covers context degradation | No | No | Yes | No | **No** |
| Covers implementation errors | Yes | Yes | Yes | Yes | Yes |
| Covers integration errors | Implicit | Yes | No | Implicit | **Yes** |
| Covers silent failures | No | No | No | No | **Yes** |
| Actionable (corrective actions) | No | No | No | No | **Yes** |
| Automated enforcement | No | No | No | No | **Yes** |

*6 categories in existing taxonomy, with 61 individual lessons providing the leaf-level granularity.

---

## Appendix C: Counter-Arguments and Limitations

### Why the gap might be smaller than estimated

1. **The toolkit's architecture already prevents some missing failure classes.** Fresh context per batch prevents context degradation. Brainstorming prevents some specification errors. The quality gate prevents some verification gaps. These architectural mitigations are not lessons but they reduce exposure.

2. **The toolkit targets a specific workflow.** It's designed for plan-driven, batch-executed development — not open-ended "fix this issue" tasks like SWE-Bench. Some academic failure modes (stuck in loop, premature termination) may be less relevant in this constrained context.

3. **Some "missing" categories may be inherently non-lesson-able.** Specification misunderstanding may require better prompting, not a lesson file. The lesson system's strength is grep-detectable patterns; some failures resist that format.

### Why the gap might be larger than estimated

1. **The toolkit has been tested by one developer.** The lesson system reflects one person's failure distribution, which may under-represent failure classes they personally catch early.

2. **Hallucination frequency is increasing with library/API churn.** As ecosystems evolve faster, the gap between training data and current APIs grows, making hallucination a larger failure class over time.

3. **Multi-agent coordination failures are underrepresented.** The toolkit has 1 lesson (0037) on multi-agent issues. The MAST framework identifies 14 failure modes, with coordination accounting for 37% of all MAS failures.
