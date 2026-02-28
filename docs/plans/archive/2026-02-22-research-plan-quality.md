# Research: Plan Quality for AI Coding Agents

> **Date:** 2026-02-22
> **Status:** Research complete
> **Method:** Web research + codebase analysis + SWE-bench literature review

## Executive Summary

1. **The 2-5 minute heuristic is directionally correct but too rigid.** Task granularity should vary by task type: single-file changes can be coarser (5-15 min), multi-file coordination tasks need finer decomposition (2-5 min), and verification-only batches need no decomposition at all. The strongest predictor of failure is lines-of-code-per-task, not wall-clock time. (Confidence: **high**)

2. **Over-specification hurts more than under-specification — but both lose to "structured intent."** The optimal spec provides: exact file paths, the goal and constraints for each task, one code example showing style — but does NOT dictate implementation line-by-line. Research on the "curse of instructions" shows LLM adherence to individual instructions drops as instruction count grows. (Confidence: **high**)

3. **Batch boundaries should follow dependency graphs, not arbitrary size limits.** Batches should group tasks that share test infrastructure or modify the same module, bounded by a quality gate. The toolkit's current 3-task batch default is reasonable but should be tunable per plan. (Confidence: **medium**)

4. **Plan quality is the single strongest lever on execution success.** SWE-bench Pro found that removing requirements and interface specifications from task descriptions degraded GPT-5 performance from 25.9% to 8.4% — a 3x drop. The plan IS the product; execution is mechanical. (Confidence: **high**)

5. **Adaptive decomposition outperforms fixed decomposition.** ADaPT (Allen AI, NAACL 2024) showed 28-33% higher success rates by decomposing tasks only when the executor fails, rather than pre-decomposing everything. This maps directly to the toolkit's retry escalation pattern. (Confidence: **medium**)

---

## 1. Task Granularity: What Size Produces the Best Outcomes?

### Findings

The "2-5 minute task" heuristic in the current `writing-plans` skill conflates two distinct dimensions: **scope** (how much code changes) and **complexity** (how many files, how much coordination). Research consistently shows that **lines of code changed** is the strongest predictor of AI agent success, not time.

**SWE-bench Verified difficulty analysis** (Ganhotra, 2025):

| Difficulty | Avg Files | Avg Hunks | Avg Lines Changed | Agent Success (top) |
|-----------|-----------|-----------|-------------------|---------------------|
| Easy (≤15 min) | 1.03 | 1.37 | 5.04 | ~80% |
| Medium (15-60 min) | 1.28 | 2.48 | 14.1 | 56-62% |
| Hard (≥1 hr) | 2.0 | 6.82 | 55.78 | 20-25% |

The 11x increase in lines changed from easy to hard dwarfs the 2x increase in file count. This means: **a single-file task that changes 60 lines is harder than a two-file task that changes 10 lines total.**

**SWE-bench Pro** (Scale AI, 2025) found that frontier models (Claude Opus 4.1, GPT-5) maintained reasonable success on single-file tasks but showed "sharp declines as file count increases," approaching near-zero on 10+ file tasks.

**Devin's recommendation** (Cognition, agents101): Target 1-6 hours of work per task for maximum ROI, with explicit checkpoint pauses between phases. This is much coarser than the toolkit's 2-5 minutes, but Devin operates in a persistent session — not fresh `claude -p` per batch.

**Anthropic's own guidance** (Effective Harnesses for Long-Running Agents): Work on one feature at a time. Agents that "try to do too much at once" exhaust context windows mid-implementation. The solution: a comprehensive feature list where each feature is independently testable.

### Evidence from the Toolkit's Own Execution Data

The `progress.txt` log reveals clear patterns across 14 batches of real headless execution:

| Batch Type | Tasks/Batch | Test Delta | Notes |
|-----------|-------------|------------|-------|
| Foundation (new files) | 3-5 | +22 | Clean execution, high test yield |
| Refactoring (modify existing) | 5 | +35 | Highest test yield per batch |
| Accuracy fixes (surgical) | 3 | +13 | Small scope, high precision |
| New capabilities | 2 | +7 | Lower test yield — integration complexity |
| Verification-only | 5 | 0 | No-ops and confirmation, no code |
| Bugfix | 2 | 0 | Rework, no new tests |

Key observations:
- **Batches with 3-5 tasks of new-file creation had the highest success rate** — clean scope, no coordination.
- **Batch 4 had a no-op task** (Task 12: lint already implemented in Batch 2) — the plan over-specified work that was already done. This wastes a `claude -p` invocation (~$0.10-0.50 per batch).
- **Batch 5 had lower test yield despite only 2 tasks** — both tasks involved cross-cutting integration (failure digest wiring, context_refs injection across parser + prompt modules). Multi-file coordination, not task count, drove complexity.
- **Batch 7 (verification-only) was efficient** — 5 tasks, zero code changes, pure confirmation. Could have been a single task.

### Implications for the Toolkit

**Replace "2-5 minutes" with a task-type-aware guideline:**

| Task Type | Recommended Granularity | Rationale |
|-----------|------------------------|-----------|
| New file creation | 1 file + its tests per task | Self-contained, high parallelism potential |
| Refactoring existing code | 1 module per task, ≤30 lines changed | Keep diff small to stay in "easy" zone |
| Cross-module integration | 1 integration point per task | Multi-file = high failure risk; isolate |
| Bug fixes | 1 bug per task, always | Never batch bugs together |
| Verification / wiring | Group freely (3-5 per batch) | Low risk, low complexity |

**Add a lines-changed heuristic:** If a task's expected diff exceeds ~30 lines, decompose further. The SWE-bench data shows the cliff between "easy" (5 lines avg) and "medium" (14 lines avg) is steep.

---

## 2. Specification Level: Over-Specification vs. Under-Specification

### Findings

The research reveals a clear "Goldilocks zone" for specification detail, with distinct failure modes on each side.

**Over-specification failure mode — "Curse of Instructions":**
Addy Osmani (referencing GitHub's analysis of 2,500+ agent configuration files) found that as instructions accumulate, LLM adherence to each individual instruction drops. Even GPT-4 struggles to satisfy many simultaneous requirements. The most effective specs cover six areas (commands, testing, structure, style, git workflow, boundaries) without prescribing implementation details.

**Under-specification failure mode — "Vague Specs = Vague Code":**
SWE-bench Pro demonstrated this quantitatively: removing requirements and interface specifications from task descriptions degraded GPT-5 from 25.9% to 8.4% resolve rate. The task description IS the primary input; without it, even frontier models flounder.

**The Goldilocks zone — "Structured Intent":**
Multiple sources converge on the same pattern:
- **Osmani:** "One real code snippet showing style beats three paragraphs of description."
- **Devin agents101:** "Clearly outline your preferred approach from the outset. Providing the agent with the overall architecture and logic upfront reduces review time."
- **Technical Design Spec pattern** (Harper Reed): Include full file paths, function signatures, API contracts — but NOT line-by-line implementation. "Prompting the agent to implement only one step at a time prevents it biting off more than it can chew."

**What the toolkit currently does well:**
The `writing-plans` skill already mandates exact file paths, complete test code, and exact commands with expected output. This is well-aligned with the research.

**What the toolkit currently over-specifies:**
The skill says "Complete code in plan (not 'add validation')." While the intent is correct (be specific, not vague), providing **complete implementation code** for every task removes the LLM's ability to adapt to discovered context. When the plan says "write this exact code" but the codebase has evolved since plan creation, the agent either follows the stale plan (wrong) or deviates (violating the plan contract).

### Evidence

| Specification Level | Example | Observed Outcome |
|--------------------|---------|-----------------|
| Under-specified | "Add validation" | Agent guesses scope, often wrong |
| Structured intent | "Add input validation to `parse_config()` in `src/config.py:45-60`. Reject empty strings and non-dict inputs. Write test first." | Agent knows scope, chooses implementation |
| Over-specified | "Replace line 47 with `if not isinstance(config, dict): raise ValueError('...')`" | Brittle — breaks if line numbers shift |

### Implications for the Toolkit

**Shift from "complete code in plan" to "complete contract in plan":**
- Keep: exact file paths, test assertions, expected behavior, command to verify
- Change: provide function signatures and contracts instead of full implementation code
- Add: explicit "constraints" section per task (what NOT to do)

**Proposed task template revision:**

```markdown
### Task N: [Name]

**Files:** Create: `path/to/file.py` | Test: `tests/path/test_file.py`

**Contract:**
- Function: `parse_config(raw: str) -> dict`
- Must reject: empty strings, non-dict JSON, missing required keys
- Must return: validated config dict with defaults applied

**Test (write first):**
```python
def test_parse_config_rejects_empty():
    with pytest.raises(ValueError):
        parse_config("")
```

**Verify:** `pytest tests/path/test_file.py::test_parse_config_rejects_empty -v`

**Constraints:**
- Do not modify `src/loader.py` (that's Task N+1)
- Use stdlib only — no new dependencies
```

This preserves specificity (file paths, test code, verification command) while leaving implementation to the agent's judgment.

---

## 3. Batch Boundaries: How Should Batches Be Drawn?

### Findings

The toolkit currently uses implicit batching (plan authors create `## Batch N` headers manually). Research suggests three viable strategies:

**Strategy A: Module-boundary batches.**
Group tasks that modify the same module or file cluster. Anthropic's long-running agent guidance recommends "one feature at a time" where each feature is independently testable. This maps to module-boundary batching.

**Strategy B: Dependency-graph batches.**
The toolkit's own `run-plan-routing.sh` already builds dependency graphs and computes parallelism scores. Tasks with shared dependencies belong in the same batch; independent tasks can be parallelized across batches.

**Strategy C: Test-group batches.**
Group tasks by the test suite that validates them. Each batch ends with a meaningful test gate. This is implicitly what the toolkit does (quality gate runs after each batch), but making it explicit forces plan authors to think about testability boundaries.

**What the research says:**
- **ADaPT** (Allen AI): Don't pre-decompose everything. Decompose only when the executor fails. This suggests batches should be coarser initially, with finer decomposition on retry.
- **SWE-EVO** (2025): Uses "Fix Rate" as a partial-progress metric — what fraction of failing tests does the agent fix? This supports test-group batching where progress is measurable per batch.
- **Anthropic's harness guidance:** The initializer + coding agent pattern treats each session as one feature increment. The feature list, not a batch structure, drives execution order.

### Evidence from Toolkit Execution Data

The progress.txt reveals natural batch boundary patterns:

| Batch | Boundary Type | Outcome |
|-------|--------------|---------|
| 1 (Foundation) | Module: shared libraries | Clean — independent files |
| 2 (Refactoring) | Dependency: all depend on Batch 1 libs | Clean — but 5 scripts modified |
| 3 (Accuracy) | Feature cluster: test parsing + context + duration | Clean — tight scope |
| 4 (Quality gates) | Mixed: new scripts + wiring | 1 no-op task (over-planned) |
| 5 (New capabilities) | Feature: failure digest + context refs | Low yield — cross-cutting |
| 6 (License + flags) | Feature: license check | 1 no-op task |
| 7 (Verification) | Test group: verify everything | 5 tasks, 0 code — batch was too large for its type |

**Pattern:** The cleanest batches (1, 2, 3) grouped by module or tight feature cluster. The messiest (4, 5, 6) mixed unrelated features or included tasks that were already done.

### Implications for the Toolkit

**Batch boundary guidelines for the `writing-plans` skill:**

1. **Primary rule: each batch has one testable outcome.** If you can't describe the batch's quality gate in one sentence, it's too broad.
2. **Group by dependency, not by count.** A batch of 2 cross-cutting tasks is harder than a batch of 5 independent file creations.
3. **Never mix new-file and integration tasks.** Create files in one batch, wire them together in the next. This prevents the "implement and integrate in one shot" failure mode.
4. **Verification batches should be a single task** — there's no benefit to splitting "run all tests and confirm" across 5 tasks within one `claude -p` invocation.
5. **Plan for no-ops.** If an earlier batch might complete a later task's work (common with refactoring), add a conditional: "Skip if already implemented in Batch N."

---

## 4. Plan Quality and Downstream Execution Success

### Findings

The evidence is unambiguous: **plan quality is the dominant variable in execution success.**

**SWE-bench Pro (Scale AI, 2025):**
"Human augmentation significantly improves resolvability." When requirements and interface specifications were provided alongside the issue description:
- GPT-5: 25.9% → 8.4% without specs (3x degradation)
- Claude Opus 4.1: Similar pattern

This means the spec/plan is worth roughly **3x the execution capability** of the model itself. A mediocre model with a great plan outperforms a great model with a bad plan.

**GitHub's analysis of 2,500+ agent config files:**
"Most agent files fail due to being too vague." The most effective configurations shared six properties: specific commands, testing instructions, project structure paths, style guidance, git workflow, and explicit boundaries.

**Anthropic's harness research:**
The most important design decision was having each agent session start by reading progress logs and selecting the next highest-priority incomplete feature. The plan structure (feature list with pass/fail tracking) determined success more than the agent's capability.

**Devin agents101:**
"80% time savings, not complete automation." The 20% manual intervention is almost entirely plan-level: clarifying intent, reordering steps, fixing spec ambiguities. The execution itself is largely mechanical when the plan is clear.

### Mapping to the Toolkit

The toolkit's architecture already reflects this insight: `progress.txt`, `prd.json`, and `.run-plan-state.json` give each fresh `claude -p` invocation the plan context it needs. But the plan file itself — the markdown document — is the primary input, and its quality determines everything downstream.

**Current plan quality strengths:**
- Exact file paths (strongly supported by research)
- TDD structure (test-first forces specificity)
- Batch structure with quality gates (machine-verifiable progress)
- Cross-batch context injection (prevents blind starts)

**Current plan quality gaps:**
- No plan validation beyond `validate-plans.sh` structural checks (sequential batch numbers, task presence)
- No measurement of plan quality before execution
- No detection of stale plans (codebase changed since plan creation)
- No conditional tasks ("skip if already done")
- Complete code provision instead of contracts (over-specification)

---

## 5. What SWE-bench, Devin, OpenHands, and Academic Literature Say

### SWE-bench Ecosystem

**SWE-bench Verified** (OpenAI, 2024): Established the standard task format — issue description + repository snapshot. No plan structure at all; agents must navigate repositories and write patches from a natural-language issue description. Top agents reach ~55% on Verified.

**SWE-bench Pro** (Scale AI, 2025): 1,865 enterprise-grade problems averaging 107 lines across 4.1 files. Found that "wrong solutions account for 35.9% of failures" — agents understand the task but implement incorrectly. This is a plan quality problem: better specs reduce solution space.

**SWE-EVO** (2025): 48 tasks averaging 21 files modified and 874 tests per instance. Introduced "Fix Rate" as a partial-progress metric. Relevant for batch execution: measure how many tests a batch fixes, not just pass/fail.

**SWE-rebench** (NeurIPS 2025): Automated task collection pipeline. Emphasizes decontamination — agents shouldn't have seen the solutions in training data. This is irrelevant to the toolkit's use case (novel codebases), but the task format research is applicable.

### Devin (Cognition)

Devin uses a two-agent architecture: **Planner** (high-level analysis, task breakdown) and **Executor** (implementation, tests, iteration). Key design decisions:
- Interactive planning phase before execution — user can edit, reorder, approve steps
- Checkpoint approach: Plan -> Implement chunk -> Test -> Fix -> Review -> Next chunk
- "Defensive prompting" — anticipate confusion points an intern would face

### OpenHands / CodeAct

OpenHands takes a minimal-structure approach: point the agent at a repo and an issue, let it plan and execute autonomously using bash and Python. CodeAct 2.1 is a single agent that interleaves planning and execution — no separate plan document.

This works for issue-resolution (SWE-bench) but not for multi-batch feature implementation (the toolkit's use case). The key difference: OpenHands agents have persistent context within a session; the toolkit uses fresh `claude -p` per batch.

### Aider

Aider's contribution is primarily about **edit format**, not plan structure:
- "Whole file" format: simple but expensive (return entire file for any edit)
- "Diff" format: efficient but error-prone with less capable models
- "Architect mode": separate planning model (generates instructions) + editing model (applies changes)

Aider's architect mode is conceptually similar to the toolkit's plan -> execute separation. The planning model operates with more context (can see the full codebase); the editing model operates with focused context (one file at a time).

### ADaPT (Allen AI, NAACL 2024)

**As-Needed Decomposition and Planning.** The core insight: don't pre-decompose tasks into subtasks. Instead, attempt the task at the current granularity and decompose only on failure. Results:
- 28.3% higher success in ALFWorld
- 27% higher in WebShop
- 33% higher in TextCraft

This directly maps to the toolkit's retry escalation: Attempt 1 gets the task as-is. Attempt 2 gets the task + failure context. The implication: the initial plan could be coarser, with finer decomposition reserved for retries.

### Self-Organized Agents (SoA, 2024)

Multi-agent framework where a "Mother agent" generates a code skeleton and delegates subtasks to "Child agents." The number of subtasks is automatically determined by the LLM based on problem complexity. This supports adaptive granularity over fixed granularity.

---

## 6. Frameworks for Measuring Plan Quality Before Execution

### Findings

No established framework exists for measuring AI-consumable plan quality pre-execution. This is a gap in the literature. However, combining software requirements quality research with AI agent evaluation metrics yields a viable framework.

### Proposed Plan Quality Scorecard

Drawing from IEEE 830 (SRS quality attributes), SWE-bench task analysis, and the toolkit's own execution data:

| Dimension | Metric | How to Measure | Weight |
|-----------|--------|---------------|--------|
| **Specificity** | File paths present per task | Automated: count tasks with `Files:` section | 0.20 |
| **Testability** | Verification command per task | Automated: count tasks with runnable test command | 0.20 |
| **Scope** | Estimated lines changed per task | Heuristic: count code blocks in plan, estimate diff size | 0.15 |
| **Independence** | Cross-task dependencies per batch | Parse: count references to other tasks within same batch | 0.15 |
| **Freshness** | Plan age vs. last codebase commit | Automated: compare plan file mtime to HEAD commit time | 0.10 |
| **Completeness** | Tasks cover all PRD acceptance criteria | Cross-reference: plan task IDs vs. prd.json task IDs | 0.10 |
| **Conditionality** | Skip conditions for potentially redundant tasks | Count: tasks with "Skip if..." clauses | 0.05 |
| **Batch coherence** | Tasks within batch share module/test scope | Heuristic: analyze file path overlap within batch | 0.05 |

**Scoring:**
- 0.8+ = Ready for headless execution
- 0.6-0.8 = Review recommended before headless; safe for interactive execution
- <0.6 = Rewrite recommended

### Implementation Path

This scorecard could be implemented as `scripts/validate-plan-quality.sh`:

```bash
# Run before execution
validate-plan-quality.sh docs/plans/my-feature.md

# Output:
# Specificity:    0.95  (19/20 tasks have file paths)
# Testability:    0.90  (18/20 tasks have verify commands)
# Scope:          0.75  (3 tasks estimated >30 lines)
# Independence:   0.85  (2 cross-task deps in same batch)
# Freshness:      1.00  (plan created today)
# Completeness:   0.80  (8/10 PRD criteria mapped)
# Conditionality: 0.40  (0 skip conditions, 2 potential no-ops detected)
# Batch coherence:0.70  (Batch 4 mixes unrelated modules)
#
# OVERALL: 0.82 — Ready for headless execution
# WARNINGS:
#   - Task 7 estimates ~45 lines changed — consider decomposing
#   - Batch 4 tasks touch 3 unrelated modules — consider splitting
```

---

## Recommendations

### R1: Replace fixed "2-5 minute" heuristic with task-type-aware granularity

**Change to `writing-plans/SKILL.md`:**

Replace the "Bite-Sized Task Granularity" section with a task-type matrix:

| Task Type | Target Scope | Max Lines Changed |
|-----------|-------------|-------------------|
| New file | 1 file + tests | ~50 |
| Refactor | 1 module | ~30 |
| Integration | 1 connection point | ~20 |
| Bug fix | 1 bug | ~30 |
| Verification | Group freely | 0 (no code changes) |

Confidence: **high** — directly supported by SWE-bench difficulty data showing lines-changed as strongest predictor.

### R2: Shift from "complete code" to "contract + one example"

**Change to `writing-plans/SKILL.md`:**

Replace "Complete code in plan (not 'add validation')" with: "Complete contract in plan: function signature, behavior specification, one test showing expected usage. Implementation code is optional — provide it only for non-obvious algorithms or domain-specific logic."

Confidence: **high** — supported by both the "curse of instructions" research and SWE-bench Pro's finding that requirements + interface specs are the critical inputs.

### R3: Add batch boundary guidelines

**Add to `writing-plans/SKILL.md`:**

"Each batch has exactly one testable outcome. Group by dependency, never by arbitrary count. Never mix file-creation and integration tasks in the same batch. Add skip conditions for tasks that earlier batches might complete."

Confidence: **medium** — supported by toolkit execution data and Anthropic's harness guidance, but no controlled experiments on batch boundary strategies exist.

### R4: Implement plan quality scorecard

**New script:** `scripts/validate-plan-quality.sh`

Pre-execution quality check that scores plans on 8 dimensions (see Section 6). Wire into `run-plan.sh` as an optional pre-flight check.

Confidence: **medium** — the individual dimensions are well-supported, but the specific weights are heuristic and would benefit from calibration against execution outcomes.

### R5: Support adaptive decomposition on retry

**Change to `run-plan-headless.sh`:**

On retry, if the failure digest indicates scope-related issues (context overflow, multi-file coordination failure), automatically request finer decomposition in the retry prompt: "The previous attempt failed. Break this batch into smaller steps, implementing one file at a time."

Confidence: **medium** — supported by ADaPT research (28-33% improvement from as-needed decomposition) but untested in the toolkit's specific architecture.

### R6: Add conditional task support to plan format

**Change to plan parser:**

Support a `skip_if:` field per task that specifies a shell command. If the command exits 0, the task is skipped. Example: `skip_if: test -f src/lib/telegram.sh` (skip if file already exists from a prior batch).

Confidence: **high** — directly addresses the no-op task problem observed in Batches 4 and 6 of the toolkit's own execution data.

---

## Sources

### SWE-bench Ecosystem
- [SWE-bench Pro: Can AI Agents Solve Long-Horizon Software Engineering Tasks?](https://arxiv.org/abs/2509.16941) — Scale AI, 2025
- [Cracking the Code: How Difficult Are SWE-Bench-Verified Tasks Really?](https://jatinganhotra.dev/blog/swe-agents/2025/04/15/swe-bench-verified-easy-medium-hard.html) — Ganhotra, 2025
- [SWE-bench Verified](https://openai.com/index/introducing-swe-bench-verified/) — OpenAI, 2024
- [SWE-EVO: Benchmarking Coding Agents](https://www.arxiv.org/pdf/2512.18470v1) — 2025
- [SWE-rebench](https://arxiv.org/abs/2505.20411) — NeurIPS 2025
- [SWE-bench Pro Leaderboard](https://scale.com/leaderboard/swe_bench_pro_public) — Scale AI

### Agent Architecture & Planning
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Anthropic Engineering
- [Coding Agents 101](https://devin.ai/agents101) — Cognition (Devin)
- [ADaPT: As-Needed Decomposition and Planning](https://arxiv.org/abs/2311.05772) — Allen AI, NAACL 2024
- [Self-Organized Agents: A LLM Multi-Agent Framework](https://arxiv.org/abs/2404.02183) — 2024
- [A Survey on Code Generation with LLM-based Agents](https://arxiv.org/abs/2508.00083) — 2025
- [A Survey of Task Planning with Large Language Models](https://spj.science.org/doi/10.34133/icomputing.0124) — Intelligent Computing

### Specification & Plan Structure
- [How to Write a Good Spec for AI Agents](https://addyosmani.com/blog/good-spec/) — Addy Osmani (cites GitHub analysis of 2,500+ agent configs)
- [How to Keep Your AI Coding Agent from Going Rogue](https://www.arguingwithalgorithms.com/posts/technical-design-spec-pattern.html) — Technical Design Spec Pattern
- [How to Use a Spec-Driven Approach for Coding with AI](https://blog.jetbrains.com/junie/2025/10/how-to-use-a-spec-driven-approach-for-coding-with-ai/) — JetBrains Junie
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices) — Anthropic

### Edit Formats & Code Generation
- [Aider Edit Formats](https://aider.chat/docs/more/edit-formats.html) — Aider
- [Unified Diffs Make GPT-4 Turbo 3X Less Lazy](https://aider.chat/docs/unified-diffs.html) — Aider
- [OpenHands CodeAct 2.1](https://openhands.dev/blog/openhands-codeact-21-an-open-state-of-the-art-software-development-agent) — OpenHands

### Evaluation Frameworks
- [Beyond Task Completion: An Assessment Framework for Evaluating Agentic AI Systems](https://arxiv.org/html/2512.12791v1) — 2025
- [TaskBench: Benchmarking Large Language Models for Task Automation](https://proceedings.neurips.cc/paper_files/paper/2024/file/085185ea97db31ae6dcac7497616fd3e-Paper-Datasets_and_Benchmarks_Track.pdf) — NeurIPS 2024
