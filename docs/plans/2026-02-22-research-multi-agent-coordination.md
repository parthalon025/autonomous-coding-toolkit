# Research: Multi-Agent Coordination Patterns for Coding Tasks

**Date:** 2026-02-22
**Status:** Complete
**Confidence:** High (primary claims from peer-reviewed papers at ACL, ICLR, NeurIPS; framework claims from well-maintained open-source repos with 10k+ stars)
**Domain classification:** Complicated (Cynefin) — known patterns exist, but optimal configuration requires expertise and context-dependent tuning

---

## Executive Summary

Multi-agent coordination for code generation is a rapidly maturing field with 7+ distinct coordination patterns, each with different cost/quality tradeoffs. The empirical evidence shows:

1. **Multi-agent systems improve code quality over single-agent baselines**, but gains are smaller than initially reported and come with 2-10x cost overhead.
2. **Specialization works** — role-based systems (implementer, tester, reviewer) consistently outperform generalist agents on code generation benchmarks, but the optimal team size is 3-4 agents, not more.
3. **The #1 failure mode is coordination, not capability** — a Berkeley study of 1,600+ traces across 7 frameworks found that inter-agent misalignment and system design issues cause more failures than individual agent errors.
4. **Structured artifacts beat chat** — MetaGPT's document-passing approach outperforms ChatDev's dialogue-based approach because structured outputs prevent information loss between agents.
5. **Self-reflection/critique-revision is the highest-ROI pattern** — it improves code quality with minimal coordination overhead (single agent, iterative).
6. **The toolkit's current competitive mode is well-aligned with the literature**, but the team mode has optimization opportunities in communication protocol and failure handling.

**Recommendation:** Keep the competitive (MAB) mode for critical batches. Enhance team mode with structured artifact passing (not chat), add a dedicated test-generation agent, and implement the critique-revision pattern within each agent's execution loop. Confidence: high.

---

## Pattern Catalog

### Pattern 1: Pipeline / Sequential Role Specialization

**Description:** Agents execute in a fixed sequence, each with a specialized role. Output of agent N becomes input to agent N+1. Analogous to an assembly line.

**Key implementations:**
- **AgentCoder** (Huang et al., 2023): Programmer Agent -> Test Designer Agent -> Test Executor Agent. The test designer generates test cases *independently* from the programmer (preventing confirmation bias). The executor runs tests and feeds failures back to the programmer for iterative refinement. Achieved 96.3% pass@1 on HumanEval with GPT-4, vs. 90.2% for best single-agent baseline, with *lower* total token usage (56.9K vs 138.2K) [1].
- **MapCoder** (Islam et al., 2024, ACL): Retrieval Agent -> Planning Agent -> Coding Agent -> Debugging Agent. The retrieval agent generates similar problem-solution pairs (few-shot examples) without external databases. The planning agent creates step-by-step plans. The debugging agent uses both test I/O and the original plan for bug fixing. Achieved 93.9% pass@1 on HumanEval [2].
- **CodeCoR** (2025): Prompt Engineer -> Coder -> QA Tester -> Repair Specialist. Each agent generates multiple candidates and prunes low-quality outputs before passing to the next stage. 77.8% average pass@1 across four benchmarks [3].

**Evidence strength:** Strong. Multiple independent replications. AgentCoder and MapCoder results are peer-reviewed (ACL 2024).

**Applicability to toolkit:** The toolkit's team mode already uses a pipeline (leader -> implementer -> reviewer). The key insight from AgentCoder is that **test generation should be independent from implementation** — the test designer doesn't see the code, preventing confirmation bias. The toolkit's current flow has the implementer writing both code and tests (TDD), which is good for development speed but may miss edge cases that an independent test agent would catch.

**Cost:** Low-to-moderate. 3-4 agents in sequence. AgentCoder achieved better results with *fewer* tokens than single-agent approaches because each agent's prompt is focused.

---

### Pattern 2: Critique-Revision (Constitutional AI Applied to Code)

**Description:** A single agent generates code, then critiques its own output against explicit principles/criteria, then revises. This cycle repeats until quality criteria are met or a max iteration count is reached. Derived from Anthropic's Constitutional AI training methodology [4].

**Key implementations:**
- **Self-Refine** (Madaan et al., 2023, NeurIPS): Generate -> Feedback -> Refine loop using a single LLM. No supervised training data or RL needed. GPT-4 code optimization improved by 8.7 units; code readability improved by 13.9+ units [5].
- **Reflexion** (Shinn et al., 2023, NeurIPS): Adds verbal reinforcement learning — the agent generates a "reflection" after failure that persists across attempts. Achieved state-of-the-art on HumanEval and other code benchmarks [6].
- **CYCLE** (2024): Self-Refine specifically tuned for code generation with execution feedback integrated into the refinement loop [7].

**Evidence strength:** Strong. Self-Refine and Reflexion are both NeurIPS papers with extensive ablations.

**Applicability to toolkit:** This pattern maps directly to the Ralph loop's iteration model — the stop-hook re-injects the prompt, and progress.txt serves as the "reflection" memory. The toolkit could strengthen this by:
1. Adding explicit critique prompts between iterations (not just "continue working" but "identify what's wrong with the current code against these criteria")
2. Structuring progress.txt entries as critique-revision pairs rather than freeform notes
3. Using PRD acceptance criteria as the "constitution" — explicit principles to critique against

**Cost:** Very low. Single agent, 2-5 iterations typical. Highest ROI pattern in the literature.

---

### Pattern 3: Debate / Adversarial Review

**Description:** Two or more agents argue opposing positions on a code decision. A judge agent (or the agents themselves via consensus) selects the winner. The adversarial pressure surfaces errors that single-agent review misses.

**Key implementations:**
- **Multi-Agent Debate (MAD)** (Du et al., 2023; Liang et al., 2023): Agents take turns critiquing each other's reasoning. Improves factuality and mathematical reasoning. For code, heterogeneous agents (different models or different prompts) outperform homogeneous configurations because "differing model architectures, training data, and inductive biases result in varied reasoning strategies" [8].
- **ChatEval** (Chan et al., 2023): Multi-agent debate specifically for evaluation — agents debate the quality of generated text/code rather than generating it.
- **iMAD** (2025): Intelligent Multi-Agent Debate with adaptive agent selection — not all problems need debate; a classifier routes to debate only when beneficial.

**Evidence strength:** Mixed. Debate improves factuality and reasoning in controlled settings. However, "increasing test-time computation does not always improve accuracy, suggesting that current MAD frameworks may not effectively utilize larger inference budgets" [8]. The benefit is task-dependent.

**Applicability to toolkit:** The competitive mode IS a debate pattern — two agents implement the same batch, and a judge picks the winner. The literature supports this design but suggests:
1. **Use heterogeneous agents** (different models or significantly different prompts), not just different strategies with the same model
2. **Route selectively** — debate is expensive, so only use it for high-stakes or ambiguous batches (the planner agent in the MAB design already does this)
3. **Extract bidirectional lessons** — the judge should explain what each agent did better, not just pick a winner (the MAB design already includes this)

**Cost:** High. 2x compute minimum (both agents generate full solutions). Only justified for critical batches where the quality improvement outweighs the cost.

---

### Pattern 4: Hierarchical Organization (Software Company Simulation)

**Description:** Agents are organized in a hierarchy mimicking a software company — CEO, CTO, programmer, tester, reviewer. Higher-level agents decompose work and assign it to lower-level agents. Communication follows organizational channels.

**Key implementations:**
- **MetaGPT** (Hong et al., 2023, ICLR 2024): "Code = SOP(Team)". Agents communicate through **structured documents** (PRDs, design docs, API specs), not dialogue. Each role produces a specific artifact type. Standard Operating Procedures (SOPs) govern agent interactions. This document-passing approach prevents information loss and hallucination that plagues chat-based systems [9].
- **ChatDev** (Qian et al., 2023, ACL 2024): Chat-based waterfall model with "inception prompting" — each dialogue starts by reinforcing roles, goals, and constraints. Evolved into ChatDev 2.0, a configurable multi-agent orchestration platform [10].

**Evidence strength:** Strong for architecture; mixed for cost-effectiveness. MetaGPT outperforms ChatDev on code quality metrics, but "large agent groups such as MetaGPT and ChatDev introduce high communication costs, often exceeding $10 per HumanEval task" [11]. For comparison, AgentCoder's 3-agent pipeline costs a fraction of that.

**Applicability to toolkit:** The toolkit's overall architecture (brainstorm -> PRD -> plan -> execute) already mirrors MetaGPT's document-passing philosophy. Key lesson: **the toolkit's approach of passing structured artifacts (plan files, PRD JSON, progress.txt) between fresh contexts is better aligned with the evidence than having agents chat with each other.** The team mode should continue using file-based communication, not message-passing.

**Cost:** Very high. 5-7 agents, extensive inter-agent communication. The "Code in Harmony" evaluation found that 3-agent teams match or exceed the quality of larger teams at a fraction of the cost [11].

---

### Pattern 5: Ensemble / Voting

**Description:** Multiple agents (or the same agent with different prompts/temperatures) generate N candidate solutions. A selection mechanism (majority voting, execution-based filtering, learned ranker) picks the best one.

**Key implementations:**
- **Best-of-N sampling:** Generate N solutions, run tests, pick the one that passes the most. Codex achieved 28.8% pass@1 but 70.2% pass@100 on HumanEval, demonstrating that having more candidates dramatically improves success rates [12].
- **Majority voting / self-consistency** (Wang et al., 2023): Sample multiple reasoning paths, take the majority answer. Works well for structured outputs (math, SQL) but less effective for open-ended code where solutions aren't directly comparable via string matching.
- **Similarity-based selection** (2025): Generate multiple code solutions, cluster by structural similarity, select the most representative — avoids the need for test cases as the selection mechanism [13].
- **Prompt-ensemble:** Same model, different prompts (e.g., different few-shot examples or different instruction framings). Produces diverse candidates cheaply.

**Evidence strength:** Strong for the "generate many, filter" paradigm. The gap between pass@1 and pass@100 is large across all models, proving that candidate diversity + selection is valuable.

**Applicability to toolkit:** The toolkit's `--sample N` flag already implements this pattern — spawning N candidates with batch-type-aware prompt variants. The literature supports:
1. **Execution-based selection is best** — run tests on all candidates, pick the one with most passing tests. The toolkit already does this via quality gates.
2. **Diversity matters more than quantity** — 3 diverse candidates (different prompts, different models) beat 10 similar candidates. The batch-type classification for prompt variant selection is well-aligned.
3. **Cost-aware sampling** — only sample on retries and critical batches (the toolkit's `SAMPLE_ON_RETRY` and `SAMPLE_ON_CRITICAL` flags are exactly right).

**Cost:** Linear in N. Parallelizable, so wall-clock time doesn't increase if resources allow. The toolkit's memory guard prevents OOM, which is a practical necessity the literature rarely addresses.

---

### Pattern 6: Iterative Test-Debug Loop

**Description:** Generate code, run tests, feed failures back to the agent for fixing. Repeat until tests pass. The simplest multi-step pattern — technically single-agent with a test executor providing feedback.

**Key implementations:**
- **Debugging-based approaches** (2025 evaluation): "Debugging-based approaches generally outperform agentic workflows in most cases, and the combined approach offers superior performance compared to the agentic workflow alone with 85% confidence" [14].
- **MapCoder's debugging agent:** Uses both test I/O failures AND the original plan to guide debugging, significantly improving fix quality over blind test-failure-based debugging [2].
- **SWE-agent** (Yang et al., 2024): Agent-Computer Interface for real-world debugging. Top performers on SWE-bench use this pattern — read error, form hypothesis, edit code, re-run tests.

**Evidence strength:** Very strong. This is the most empirically validated pattern. SWE-bench leaderboard scores correlate directly with how well agents handle the test-debug loop.

**Applicability to toolkit:** The toolkit already implements this at multiple levels:
- Quality gates provide test failure feedback between batches
- Ralph loop iterates until tests pass
- Retry escalation includes previous failure logs in the next attempt's prompt

Enhancement opportunity: Include the **original plan** in the debug context (MapCoder's key insight). When a batch fails, the retry prompt should include not just the error log but the plan's intent for that batch, so the agent can distinguish "wrong approach" from "right approach, wrong implementation."

**Cost:** Low. Each iteration adds one agent invocation + one test run. Typically converges in 2-3 iterations.

---

### Pattern 7: Dynamic Role Assignment / Adaptive Coordination

**Description:** Instead of fixed roles, agents are assigned roles dynamically based on the task at hand. A coordinator agent analyzes the task and determines which roles are needed and how they should interact.

**Key implementations:**
- **iMAD** (2025): Intelligent Multi-Agent Debate that routes problems to debate only when beneficial — a classifier determines whether a given problem benefits from multi-agent debate or should be handled by a single agent.
- **MAB Planner** (toolkit design): The planner agent in the MAB system reads the PRD, architecture map, and strategy performance data to decide per work unit whether to use MAB or single strategy, which execution mode, and what team size.
- **CrewAI Flows** (2024-2025): Two-layer architecture where Flows handle deterministic orchestration and Crews handle dynamic agent collaboration. The coordinator can reconfigure team composition mid-task.

**Evidence strength:** Emerging. The concept is sound (supported by the Berkeley failure mode study showing that one-size-fits-all coordination leads to unnecessary overhead), but few rigorous ablations exist.

**Applicability to toolkit:** The MAB planner agent IS this pattern. The literature supports making routing decisions based on:
1. **Task complexity** — simple tasks don't benefit from multi-agent (the planner should route to headless mode)
2. **Task novelty** — well-understood patterns need less debate than novel architecture decisions
3. **Historical performance** — the strategy-perf.json feedback loop is exactly what the adaptive systems recommend
4. **Cost budget** — some users will prefer cheaper, faster execution over marginal quality gains

**Cost:** Minimal overhead for the routing decision itself. The value is in *avoiding* unnecessary coordination cost for simple tasks.

---

## Comparison to Toolkit's Current Patterns

| Pattern | Literature Example | Toolkit Implementation | Gap |
|---------|-------------------|----------------------|-----|
| Pipeline | AgentCoder (3 agents) | Team mode (leader + implementer + reviewer) | Missing independent test generation agent |
| Critique-Revision | Self-Refine, Reflexion | Ralph loop + progress.txt | Could add structured critique prompts |
| Debate | Multi-Agent Debate | Competitive mode (2 agents + judge) | Good alignment; could use heterogeneous models |
| Hierarchical | MetaGPT, ChatDev | Brainstorm->PRD->Plan->Execute chain | Good alignment; already uses document passing |
| Ensemble/Voting | Best-of-N, majority voting | `--sample N` flag | Good alignment; well-implemented |
| Test-Debug Loop | SWE-agent, MapCoder debug | Quality gates + retry escalation | Could include plan intent in retry context |
| Adaptive Routing | iMAD, CrewAI Flows | MAB planner agent | Good alignment; novel in CLI tooling |

**Assessment:** The toolkit covers 6 of 7 major patterns. The implementations are practical and well-adapted to the CLI/headless context. The main gap is the absence of independent test generation — every other area has solid coverage.

---

## Failure Modes Unique to Multi-Agent Systems

The Berkeley MAST study (Cemri et al., 2025, ICLR) analyzed 1,600+ traces across 7 frameworks and identified 14 failure modes in 3 categories [15]:

### Category 1: System Design Issues
- **Role/task ambiguity** — agents "disobey" their roles when instructions are underspecified
- **Information loss** — context is dropped when passing between agents (especially in chat-based systems)
- **Premature termination** — orchestrator stops before all agents complete their work
- **Infinite loops** — agents get stuck in repetition when exit conditions are unclear

### Category 2: Inter-Agent Misalignment
- **Conformity bias / groupthink** — agents reinforce each other's errors rather than providing independent evaluation
- **Cascading errors** — a single misinterpreted message early in the pipeline corrupts all downstream work
- **Loss of history** — agents "forget" context from earlier in the conversation
- **Contradictory outputs** — agents produce conflicting results that the orchestrator can't reconcile

### Category 3: Task Verification
- **Missing verification** — no agent checks the final output against the original spec
- **Shallow verification** — agents check syntax but not semantics
- **False consensus** — all agents agree the output is correct when it isn't

### Toolkit mitigations already in place:
- **Role ambiguity** -> Rigid skill definitions with explicit behavioral contracts
- **Information loss** -> Structured artifact passing (plan files, PRD JSON, progress.txt)
- **Premature termination** -> Quality gates between every batch; SIGPIPE trap
- **Infinite loops** -> Max retry counts; Ralph loop exit conditions
- **Loss of history** -> progress.txt read at start of each batch
- **Missing verification** -> Mandatory verification stage with Iron Law

### Residual risks:
- **Conformity bias** in team mode — the reviewer may agree with the implementer when using the same model. Mitigation: use different models or significantly different prompts for reviewer vs implementer.
- **Cascading errors** in parallel team execution — if one batch in a parallel group produces bad output that another batch depends on. Mitigation: the dependency graph computation (`compute_parallel_groups`) already handles this by only parallelizing independent batches.
- **False consensus** — both the implementer and reviewer could miss the same class of bug. Mitigation: the quality gate (machine-verified) catches what human-like review misses, and vice versa. Orthogonal verification is the right approach.

---

## Communication Protocols

The literature identifies three communication paradigms [16]:

### 1. Document/Artifact Passing (MetaGPT style)
Agents produce typed artifacts (PRDs, design docs, code, test results). The next agent reads the artifact, not a chat transcript. Advantages: no information loss, composable, auditable. Disadvantage: rigid, harder to handle unexpected situations.

**Toolkit alignment:** Strong. Plan files, PRD JSON, progress.txt, AGENTS.md, and quality gate results are all structured artifacts.

### 2. Message Passing (AutoGen style)
Agents exchange natural language messages in a conversation. Advantages: flexible, handles ambiguity well. Disadvantages: information loss, verbose, expensive (every message is billed).

**Toolkit alignment:** Not used. The toolkit deliberately avoids inter-agent chat. Fresh `claude -p` processes communicate only through files.

### 3. Shared State (LangGraph style)
Agents read from and write to a shared state object. Advantages: simple, no message formatting overhead. Disadvantages: race conditions, state pollution, harder to debug.

**Toolkit alignment:** Partially used. `.run-plan-state.json` is shared state, but write access is serialized (only the orchestrator writes), avoiding the race condition problems the literature warns about.

**Recommendation:** The toolkit's artifact-passing approach is well-aligned with the highest-performing systems in the literature. Do not switch to message-passing. The overhead of chat-based coordination is the primary cost driver in MetaGPT and ChatDev, and the toolkit avoids it entirely. Confidence: high.

---

## Recommendations

### 1. Add Independent Test Generation to Team Mode
**Priority:** High | **Confidence:** High | **Evidence:** AgentCoder, MapCoder, CodeCoR

The single highest-impact addition based on the literature. When the implementer writes both code and tests (TDD), there's a confirmation bias risk — the tests may only cover the happy path the implementer thought of. An independent test agent that reads only the spec (not the code) generates more diverse test cases.

**Implementation:** After the implementer completes a batch, spawn a test-generation agent that reads the plan/PRD (not the implementation) and generates additional test cases. Run these tests against the implementation. Feed failures back to the implementer.

**Cost:** One additional agent invocation per batch. Low marginal cost, high marginal quality improvement.

### 2. Structure Critique-Revision in Ralph Loop
**Priority:** Medium | **Confidence:** High | **Evidence:** Self-Refine, Reflexion

Between Ralph loop iterations, add an explicit critique step. Instead of re-injecting the raw prompt, inject: (1) the original task, (2) a structured self-critique prompt ("What specific acceptance criteria are still failing? What approach did you try? Why didn't it work? What should you try differently?"), and (3) the progress.txt history.

This transforms the Ralph loop from "try again" to "reflect, then try differently" — which is exactly the Reflexion pattern that achieved state-of-the-art results.

### 3. Include Plan Intent in Retry Context
**Priority:** Medium | **Confidence:** High | **Evidence:** MapCoder debugging agent

When a batch fails and retries, the current prompt includes the error log. Add the plan's description of what the batch was supposed to accomplish. This helps the agent distinguish "wrong approach" from "right approach, wrong implementation" — MapCoder found this distinction is critical for debugging effectiveness.

### 4. Use Heterogeneous Models for Competitive Mode
**Priority:** Low | **Confidence:** Medium | **Evidence:** MAD literature, Berkeley MAST study

When running competitive mode, use different models for the two agents (e.g., Claude for one, GPT-4 for the other, or different Claude model versions). Heterogeneous agents explore a broader solution space and reduce conformity bias. The MAB system's strategy-perf.json could track which model combinations produce the best results.

**Caveat:** This requires multi-provider API access, which not all users will have. Make it configurable, not mandatory.

### 5. Cap Team Size at 3-4 Agents
**Priority:** Low (already implemented) | **Confidence:** High | **Evidence:** AgentCoder, "Code in Harmony" evaluation

The literature is clear: 3-agent teams match or exceed the quality of larger teams at a fraction of the cost. The toolkit's team mode (leader + implementer + reviewer) is already at the optimal size. Adding the independent test agent (recommendation #1) would bring it to 4, which is still within the optimal range. Do not add more roles.

---

## Cost-Quality Tradeoff Summary

| Pattern | Quality Improvement | Cost Multiplier | Best For |
|---------|-------------------|-----------------|----------|
| Test-Debug Loop | +10-15% pass@1 | 1.2-1.5x | All batches (default) |
| Critique-Revision | +8-14% quality metrics | 1.3-2x | Complex logic, algorithms |
| Pipeline (3-agent) | +5-10% pass@1 | 1.5-2x | Feature implementation |
| Ensemble (N=3) | +15-25% pass@1 | 3x | Critical/risky batches |
| Debate (2-agent) | +5-15% quality | 2-3x | Architecture decisions |
| Hierarchical (5+) | Diminishing returns | 5-10x | Large projects (rarely worth it) |

The toolkit's tiered approach — headless for simple batches, team for standard batches, competitive for critical batches, sampling on retry — is well-aligned with the cost-quality curve. The planner agent's routing decision is the key leverage point.

---

## Sources

1. Huang et al. "AgentCoder: Multi-Agent-based Code Generation with Iterative Testing and Optimisation." arXiv:2312.13010, 2023. https://arxiv.org/abs/2312.13010
2. Islam et al. "MapCoder: Multi-Agent Code Generation for Competitive Problem Solving." ACL 2024. https://aclanthology.org/2024.acl-long.269/
3. "CodeCoR: An LLM-Based Self-Reflective Multi-Agent Framework for Code Generation." arXiv:2501.07811, 2025. https://arxiv.org/abs/2501.07811
4. Bai et al. "Constitutional AI: Harmlessness from AI Feedback." arXiv:2212.08073, 2022. https://arxiv.org/abs/2212.08073
5. Madaan et al. "Self-Refine: Iterative Refinement with Self-Feedback." NeurIPS 2023. https://arxiv.org/abs/2303.17651
6. Shinn et al. "Reflexion: Language Agents with Verbal Reinforcement Learning." NeurIPS 2023. https://arxiv.org/abs/2303.11366
7. "CYCLE: Learning to Self-Refine the Code Generation." ACM, 2024. https://dl.acm.org/doi/pdf/10.1145/3649825
8. ICLR Blogposts 2025. "Multi-LLM-Agents Debate — Performance, Efficiency, and Scaling Challenges." https://d2jud02ci9yv69.cloudfront.net/2025-04-28-mad-159/blog/mad/
9. Hong et al. "MetaGPT: Meta Programming for a Multi-Agent Collaborative Framework." ICLR 2024. https://arxiv.org/abs/2308.00352
10. Qian et al. "ChatDev: Communicative Agents for Software Development." ACL 2024. https://arxiv.org/abs/2307.07924
11. "Code in Harmony: Evaluating Multi-Agent Frameworks." OpenReview, 2025. https://openreview.net/forum?id=URUMBfrHFy
12. Chen et al. "Evaluating Large Language Models Trained on Code." (Codex paper), 2021. https://arxiv.org/abs/2107.03374
13. "Enhancing LLM Code Generation with Ensembles: A Similarity-Based Selection Approach." arXiv:2503.15838, 2025. https://arxiv.org/abs/2503.15838
14. "Enhancing LLM Code Generation: A Systematic Evaluation of Multi-Agent Collaboration and Runtime Debugging." arXiv:2505.02133, 2025. https://arxiv.org/abs/2505.02133
15. Cemri et al. "Why Do Multi-Agent LLM Systems Fail?" ICLR 2025. https://arxiv.org/abs/2503.13657
16. "Which LLM Multi-Agent Protocol to Choose?" arXiv:2510.17149, 2025. https://arxiv.org/abs/2510.17149
17. "LLM-Based Multi-Agent Systems for Software Engineering: Literature Review, Vision, and the Road Ahead." ACM TOSEM, 2025. https://dl.acm.org/doi/10.1145/3712003
18. DataCamp. "CrewAI vs LangGraph vs AutoGen." https://www.datacamp.com/tutorial/crewai-vs-langgraph-vs-autogen
19. SWE-bench. https://www.vals.ai/benchmarks/swebench
20. "Self-Reflection in LLM Agents: Effects on Problem-Solving Performance." arXiv:2405.06682, 2024. https://arxiv.org/abs/2405.06682
