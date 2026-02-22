# Research: Prompt Engineering for Code Generation Agents

> **Date:** 2026-02-22
> **Status:** Research complete
> **Method:** Web research + academic literature + open-source agent analysis
> **Confidence convention:** High = multiple corroborating sources + empirical data. Medium = consistent expert guidance but limited controlled studies. Low = anecdotal or single-source.

## Executive Summary

This research synthesizes evidence from academic papers, open-source agent codebases (SWE-agent, OpenHands, Aider), vendor documentation (Anthropic, OpenAI), and SWE-bench competition analysis to answer eight questions about prompt engineering for code generation agents. The findings directly inform improvements to the toolkit's `run-plan-prompt.sh` and `run-plan-context.sh`.

**Top-line findings:**

1. **Structured planning in prompts yields a measurable 4% SWE-bench improvement** (OpenAI, confirmed). Direct instruction with structured planning outperforms both raw chain-of-thought and unstructured prompts for code generation.
2. **File context ordering matters significantly.** The "Lost in the Middle" effect (Stanford, 2023) is real and confirmed across models: information at the start and end of context is recalled best. Place task instructions and critical files at boundaries; relegate supporting context to the middle.
3. **Simple role prompting ("You are an expert programmer") has no measurable effect.** Detailed, behavior-defining system prompts do help, but generic personas do not.
4. **Few-shot examples help for smaller models but have diminishing returns on frontier models.** Self-planning with examples shows up to 25.4% Pass@1 improvement, but the benefit comes from the planning structure, not the examples per se.
5. **Error context in retries should be a failure digest, not a raw log dump.** The current escalation strategy (attempt 2: signal, attempt 3: digest) aligns with best practice.
6. **The current prompt variants ("vanilla", "different-approach", "minimal-change") were chosen without evidence.** Research supports batch-type-aware variants but the specific suffixes need revision based on what top agents actually do.

---

## 1. Prompt Structure: What Produces the Best Code from LLMs?

### Findings

Three prompting paradigms have been benchmarked for code generation:

| Approach | Performance vs. Baseline | Source |
|----------|------------------------|--------|
| Direct instruction | Baseline | Multiple |
| Standard Chain-of-Thought (CoT) | +0.82 pts Pass@1 (marginal) | Li et al., SCoT (ACM TOSEM 2024) |
| Structured CoT (SCoT) | +13.79% HumanEval, +12.31% MBPP | Li et al., SCoT (ACM TOSEM 2024) |
| Self-Planning | +25.4% Pass@1 vs. direct, +11.9% vs. CoT | ACM TOSEM 2024 |
| Chain of Grounded Objectives (CGO) | Outperforms SCoT and self-planning | Yeo et al., ECOOP 2025 |
| Explicit planning in system prompt | +4% SWE-bench Verified | OpenAI GPT-4.1 Prompting Guide |

**Key insight:** Standard CoT is wasteful for code generation. It adds 35-600% latency for marginal gains. Structured approaches that decompose the task into functional objectives or implementation steps perform far better. The ECOOP 2025 CGO paper found that "machine-oriented reasoning" (functional objectives) outperforms "human-oriented reasoning" (step-by-step procedures) for code.

**What top agents actually do:**

- **SWE-agent:** Mandates a structured five-phase workflow in its system prompt: reproduce issue, localize cause, plan fix, implement, verify. The system prompt is ~800 words.
- **OpenHands:** Five-phase workflow: Exploration, Analysis, Testing, Implementation, Verification. Explicitly states "thoroughly examine relevant files first."
- **Aider:** Minimal system prompt focused on output format (SEARCH/REPLACE blocks), not reasoning strategy. Relies on the model's native capabilities.

**Confidence:** High. Multiple independent benchmarks converge on structured planning > raw CoT > direct instruction.

### Evidence

- Li et al., "Structured Chain-of-Thought Prompting for Code Generation," ACM TOSEM 2024 ([arXiv 2305.06599](https://arxiv.org/abs/2305.06599))
- Yeo et al., "Chain of Grounded Objectives: Concise Goal-Oriented Prompting for Code Generation," ECOOP 2025 ([arXiv 2501.13978](https://arxiv.org/abs/2501.13978))
- [OpenAI GPT-4.1 Prompting Guide](https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide) — "Inducing explicit planning increased the pass rate by 4%"
- [Anthropic Claude 4 Best Practices](https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)

### Implications for the Toolkit

The current `build_batch_prompt()` gives a task list and requirements but no explicit planning instruction. Adding a structured planning directive would likely improve first-attempt pass rates.

**Specific change:** Add a planning section to the prompt template:

```
Before implementing, plan your approach:
1. Read relevant files to understand current state
2. For each task, identify: what files to create/modify, what tests to write, what the expected behavior is
3. Implement one task at a time: write failing test, implement, verify pass, commit
4. After all tasks, run the quality gate
```

This aligns with the OpenAI finding (+4% SWE-bench) and OpenHands/SWE-agent's structured workflow approach.

---

## 2. File Context Ordering in Prompts

### Findings

The "Lost in the Middle" effect (Liu et al., 2023) establishes a U-shaped attention curve: LLMs attend most strongly to information at the **beginning** and **end** of the context, with significant degradation for information positioned in the middle. This has been confirmed across GPT-3.5, GPT-4, Claude, LLaMA, and Qwen model families.

**Practical ordering rules derived from research:**

1. **Task instructions and critical constraints go first** (primacy effect)
2. **Error context and test output go last** (recency effect)
3. **Supporting file contents go in the middle** (least critical position)
4. **If a file is the most important context, either lead with it or echo key parts at the end**

**What top agents do:**

- **Augment Code** explicitly states: "Models pay attention to beginning and end. Prioritize importance: user message content > prompt beginning > middle sections."
- **SWE-agent** places the issue statement last (after system prompt and demonstrations), leveraging recency bias.
- **OpenHands** places the task description at the end of system messages.
- **Anthropic** recommends: "If you control the prompt, bias it so key evidence is early or echoed late, and pre-summarize the most relevant spans."

**Truncation strategy also matters:** When truncating long outputs (command output, logs), Augment Code recommends **removing the middle, keeping the beginning and end**. Error messages typically appear at the end of output; file headers and structure appear at the beginning.

**Confidence:** High. The Lost in the Middle finding is one of the most replicated results in LLM research (Stanford 2023, published in TACL 2024, 1000+ citations).

### Evidence

- Liu et al., "Lost in the Middle: How Language Models Use Long Contexts," TACL 2024 ([arXiv 2307.03172](https://arxiv.org/abs/2307.03172))
- Raimondi, "Exploiting Primacy Effect to Improve Large Language Models," RANLP 2025 ([arXiv 2507.13949](https://arxiv.org/abs/2507.13949))
- [Augment Code: 11 Prompting Techniques](https://www.augmentcode.com/blog/how-to-build-your-agent-11-prompting-techniques-for-better-ai-agents)

### Implications for the Toolkit

The current `build_batch_prompt()` ordering is:

```
1. Role + working directory (top)      ← OK
2. Tasks in this batch                 ← GOOD (high priority, near top)
3. Recent commits                      ← OK (middle)
4. Previous progress                   ← OK (middle)
5. Previous quality gate               ← OK (middle)
6. Referenced files                    ← OK (middle)
7. Requirements (TDD, quality gate)    ← GOOD (at bottom, recency)
```

This ordering is already reasonable. The main improvements:

1. **Move Requirements block higher or duplicate key constraints.** The TDD and quality gate requirements are at the very bottom, which benefits from recency. But the task list is near the top, which benefits from primacy. This is a good structure.

2. **When injecting error context in retries, place the failure digest at the end** (already done in attempt 3 — this is correct).

3. **For `run-plan-context.sh`: the TOKEN_BUDGET_CHARS=6000 (~1500 tokens) is conservative.** The context budget should be high enough to include critical file content but aggressive about what gets included. Current priority order (directives > failure patterns > refs > git log > progress) is correct — highest value first.

4. **When including referenced files (`context_refs`), truncate by removing the middle** of long files rather than using `head -100` (which loses the end of the file where key functions may live).

---

## 3. "Lost in the Middle" for Code Context Injection

### Findings

The Stanford paper (arXiv 2307.03172) tested multi-document QA and key-value retrieval. When the relevant document was placed in the middle of 20 documents, accuracy dropped by up to 20 percentage points compared to placing it first or last. The effect was present even in models explicitly trained for long contexts.

**For code context specifically:**

- Code files have a natural structure: imports at top, main logic in middle, exports/entry points at bottom. When injecting multiple files, the agent needs to find the relevant function or class.
- **The mitigation is not to avoid middle placement, but to make middle content discoverable.** Techniques:
  - Add section headers/markers before each file: `--- path/to/file.py (relevant function: parse_config) ---`
  - Pre-summarize each file's purpose in a header line
  - If injecting more than 5 files, summarize all files first, then include full content of the 2-3 most relevant ones

**The "Found in the Middle" follow-up paper** (2024) proposes plug-and-play positional encoding to mitigate the effect but this requires model architecture changes, not prompt engineering.

**Confidence:** High for the phenomenon existing. Medium for the specific code-context mitigations (these are derived from general principles applied to code, not directly benchmarked).

### Evidence

- Liu et al., "Lost in the Middle," TACL 2024 ([arXiv 2307.03172](https://arxiv.org/abs/2307.03172))
- Zhu et al., "Found in the Middle," NeurIPS 2024 ([arXiv 2403.04797](https://arxiv.org/abs/2403.04797))

### Implications for the Toolkit

The current context injection in `run-plan-context.sh` and `build_batch_prompt()` includes referenced files with a simple header (`--- $ref ---`) and `head -100`. Improvements:

1. **Add purpose annotations to context_refs headers.** Instead of `--- path/to/file.py ---`, use `--- path/to/file.py (defines: ConfigParser class, parse_config function) ---`. This could be automated by extracting the first docstring or function/class names.

2. **Limit injected files to 3-5 maximum.** Beyond that, include only summaries. The current TOKEN_BUDGET_CHARS=6000 naturally limits this, which is good.

3. **For files truncated by `head -50` or `head -100`, also include `tail -20`** to capture the end of the file (exports, main logic, error handling).

---

## 4. Role Prompting for Code Generation

### Findings

Research on role prompting for code generation shows surprisingly mixed results:

| Study | Finding | Source |
|-------|---------|--------|
| "When 'A Helpful Assistant' Is Not Really Helpful" | Personas have "no or small negative effects" on performance across 4 LLM families | arXiv 2311.10054 |
| PromptHub analysis | Basic persona prompts don't improve results; Expert Prompting significantly outperformed other methods | PromptHub blog |
| Anaconda persona study | Different programming personas (Torvalds, Knuth) can influence code style but not correctness | Anaconda blog |

**The critical distinction:** Simple role assignment ("You are an expert Python developer") does not improve code quality. But **detailed behavioral specification** does. The difference:

- **Ineffective:** "You are a senior software engineer."
- **Effective:** "You are implementing Batch 3 of a plan. Follow TDD: write failing test, implement, verify pass, commit. Run the quality gate after all tasks. All 42+ tests must pass."

The effective version is not a "role" — it's a behavioral contract with specific constraints and success criteria.

**What top agents do:**

- **Aider:** No role prompt at all. Defines behavior through output format constraints.
- **SWE-agent:** "You are a helpful assistant" + detailed ACI tool documentation.
- **OpenHands:** "You are a helpful AI assistant" + 5-phase workflow specification.
- **Claude Code:** No generic role. Behavior defined by CLAUDE.md project instructions.

**Confidence:** High that generic roles don't help. Medium that detailed behavioral specs do (consistent across top agents but no controlled study isolating this variable).

### Evidence

- Zheng et al., "When 'A Helpful Assistant' Is Not Really Helpful" ([arXiv 2311.10054](https://arxiv.org/html/2311.10054v3))
- [PromptHub: Role-Prompting Analysis](https://www.prompthub.us/blog/role-prompting-does-adding-personas-to-your-prompts-really-make-a-difference)
- [Anaconda: Persona Programming](https://www.anaconda.com/blog/persona-programming-ai)

### Implications for the Toolkit

The current prompt opens with: `"You are implementing Batch ${batch_num}: ${title} from ${plan_file}."` This is already close to optimal — it's a behavioral specification, not a persona. No change needed here.

**Do NOT add:** "You are an expert software engineer" or similar generic role prompts. The research consistently shows this has zero or negative effect on frontier models.

---

## 5. SWE-bench Top Performer Prompt Strategies

### Findings

As of early 2026, top SWE-bench Verified performers score 75-79%:

| Agent | Score | Key Prompt Strategy |
|-------|-------|-------------------|
| Claude Opus 4.6 (Thinking) | 79.2% | Adaptive thinking, no explicit planning prompt needed |
| Live-SWE-agent + Claude | 79.2% | ACI design: custom file viewer, linting before edit, structured observation |
| Gemini 3 Flash | 76.2% | Extended thinking |
| GPT 5.2 | 75.4% | Explicit planning in system prompt |
| CodeStory Midwit Agent | 62% | Multi-agent with brute force search |

**Common strategies among top performers:**

1. **Explicit planning prompt** — OpenAI measured +4% from adding planning instructions. This is the single largest prompt-engineering intervention with controlled evidence.

2. **Structured tool usage** — API-parsed tool descriptions outperform manually injected schemas by +2% (OpenAI). SWE-agent's ACI is the canonical example: custom commands with documentation and demonstrations.

3. **Persistence instructions** — "Keep going until the task is fully resolved" prevents early termination. OpenAI, Augment, and Anthropic all recommend this.

4. **Minimal context, maximum relevance** — Top agents aggressively filter context. SWE-agent uses file localization before editing. OpenHands mandates "Exploration" phase before implementation.

5. **Multi-agent approaches** — CodeStory's Midwit Agent uses multiple agents (brute force). The competitive mode in this toolkit already implements this.

**The sample SWE-bench prompt from OpenAI's guide specifies an 8-step methodology:**
1. Understand the problem deeply
2. Investigate the codebase systematically
3. Develop clear, step-by-step plans
4. Implement incrementally with small, testable changes
5. Debug to identify root causes
6. Test frequently after each change
7. Verify comprehensively
8. Reflect on edge cases and hidden test scenarios

**Confidence:** High. These strategies are from the agents that actually top the benchmark, with controlled ablations from OpenAI.

### Evidence

- [OpenAI GPT-4.1 Prompting Guide](https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide)
- [SWE-bench Leaderboard](https://www.vals.ai/benchmarks/swebench)
- [SWE-rebench Leaderboard](https://swe-rebench.com)
- [SWE-agent paper](https://arxiv.org/abs/2405.15793)

### Implications for the Toolkit

The toolkit already implements several of these (fresh context per batch, quality gates, TDD workflow). Missing elements:

1. **Add persistence instruction:** "Complete all tasks in this batch before stopping. Do not end your turn early or ask for clarification — use your tools to investigate and resolve uncertainties."

2. **Add investigation-first instruction:** "Before implementing any task, read the relevant files to understand the current state. Do not assume file contents from the plan description."

3. **The 8-step methodology from OpenAI maps well to TDD.** The current prompt says "TDD: write test -> verify fail -> implement -> verify pass -> commit each task." This could be expanded to include investigation and verification steps.

---

## 6. How Devin, SWE-agent, OpenHands, and Aider Construct Their Prompts

### Findings

| Agent | System Prompt Length | Key Structure | Context Strategy |
|-------|---------------------|---------------|-----------------|
| **SWE-agent** | ~800 words | System prompt + demonstration + issue | Custom ACI commands with inline docs. Linter gates edits. File viewer replaces raw `cat`. |
| **OpenHands** | ~600 words (Jinja2 template) | Role + capabilities + workflow phases + error recovery | Structured 5-phase workflow. "Reflect on 5-7 possible causes" on repeated failure. |
| **Aider** | ~200 words (main) + format spec | Behavioral constraints + SEARCH/REPLACE format | Minimal context. Repo map (file tree + signatures) injected automatically. Referenced files in full. |
| **Devin** | Proprietary | Unknown (closed source) | Multi-agent with planning agent, execution agent, and verification agent. |

**Structural patterns across all agents:**

1. **Role + capabilities** — One sentence establishing what the agent can do.
2. **Behavioral constraints** — Explicit rules about when to ask vs. act, how to handle ambiguity.
3. **Output format** — Strict format for code changes (SEARCH/REPLACE in Aider, structured actions in SWE-agent).
4. **Error recovery protocol** — What to do when things fail (OpenHands: "reflect on 5-7 possible causes").
5. **Minimal prompting** — None of these agents use long, elaborate prompts. The system prompts are 200-800 words. The power comes from tool design and workflow structure, not prompt verbosity.

**Aider's approach is distinctive:** It barely prompts the model for reasoning. Instead, it constrains the output format (SEARCH/REPLACE blocks) and relies on the model's native intelligence. The "repo map" (file tree with function/class signatures) provides structural context without full file contents.

**OpenHands' error recovery is the most sophisticated:** On repeated failure, the prompt instructs the agent to "step back" and "reflect on 5-7 different possible sources of the problem" before continuing. This prevents the common failure mode of repeatedly trying the same approach.

**Confidence:** High. These are the actual source code of production agents, not documentation or blog posts.

### Evidence

- [Aider prompts.py](https://github.com/Aider-AI/aider/blob/main/aider/prompts.py)
- [Aider editblock_prompts.py](https://github.com/Aider-AI/aider/blob/main/aider/coders/editblock_prompts.py)
- [OpenHands system_prompt.j2](https://github.com/All-Hands-AI/OpenHands/blob/main/openhands/agenthub/codeact_agent/prompts/system_prompt.j2)
- [SWE-agent ACI documentation](https://github.com/SWE-agent/SWE-agent/blob/main/docs/background/aci.md)
- [SWE-agent paper](https://arxiv.org/abs/2405.15793)

### Implications for the Toolkit

The current `build_batch_prompt()` is ~30 lines of template. This is in the right range — the top agents use 200-800 words. The prompt should not get longer, but it should get more structured.

**Specific improvements:**

1. **Add an error recovery instruction** (from OpenHands): When the prompt includes failure context (retries), add: "Before attempting a fix, identify 3-5 possible root causes and assess the likelihood of each. Address the most likely cause first."

2. **Consider a repo map equivalent.** The current `context_refs` system injects full file content. A lighter-weight option: inject file tree + function signatures for the entire worktree, similar to Aider's repo map. This gives the agent structural awareness without consuming tokens on file content.

3. **The prompt variant system in `get_prompt_variants()` appends short suffixes like "check all imports before running tests."** Top agents don't use this pattern. Instead, they vary the workflow structure or the error recovery strategy. The variant system should be revised (see Recommendations).

---

## 7. Few-Shot Examples in Code Generation Prompts

### Findings

The evidence on few-shot examples for code generation is nuanced:

| Model Class | Few-Shot Impact | Source |
|-------------|----------------|--------|
| Small models (T5, CodeLlama-7B) | Significant improvement | CODEEXEMPLAR, arXiv 2412.02906 |
| Frontier models (GPT-4, Claude Opus) | Diminishing returns | General consensus, no single paper |
| All models with self-planning | +25.4% Pass@1 improvement | ACM TOSEM 2024 |

**Key findings:**

1. **The benefit of few-shot comes from the planning structure, not the examples themselves.** Self-planning prompting (show examples of planning, then coding) yields +25.4% improvement. The planning template transfers; the specific example code does not.

2. **More complex examples are more informative than simple ones.** The CODEEXEMPLAR-FREE method selects examples the LLM struggles to generate on its own. This is counterintuitive — you'd expect easy examples to be better demonstrations. But hard examples force the model to attend more carefully.

3. **For frontier models on code generation tasks, few-shot examples consume tokens without proportional benefit.** The models already know how to code. The value-add is in workflow and constraint specification, not in showing code examples.

4. **Anthropic's guidance for Claude 4.6:** "Be vigilant with examples & details. Claude pays close attention to details and examples. Ensure that your examples align with the behaviors you want to encourage." But also: "Avoid overfitting to specific examples" — test that examples don't degrade performance on novel cases.

**What top agents do:**

- **SWE-agent:** Optional demonstration (a worked example of solving a GitHub issue). This is the closest to few-shot and it is marked as optional.
- **Aider:** No few-shot examples. Pure instruction + format specification.
- **OpenHands:** No few-shot examples. Workflow specification only.

**Confidence:** Medium. The self-planning result is well-evidenced, but the claim about diminishing returns on frontier models is inferred from the absence of few-shot in top agents rather than a controlled ablation.

### Evidence

- Bairi et al., "Does Few-Shot Learning Help LLM Performance in Code Synthesis?" ([arXiv 2412.02906](https://arxiv.org/abs/2412.02906))
- Jiang et al., "Self-Planning Code Generation with Large Language Models," ACM TOSEM 2024
- [Anthropic Claude 4 Best Practices](https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)

### Implications for the Toolkit

The current prompt does not include few-shot examples. **This is correct for a system using frontier models.** Do not add few-shot code examples to the prompt.

However, the self-planning finding suggests value in including a brief **planning template** (not a code example):

```
Planning template:
Task: [task name]
Files to read: [list]
Files to create/modify: [list]
Test to write: [test file and test name]
Expected behavior: [what the test checks]
```

This is a structural template, not a few-shot example. It guides the planning process without showing code.

---

## 8. Error Context Framing in Retry Prompts

### Findings

The toolkit's current retry escalation is:

- **Attempt 1:** Raw task prompt
- **Attempt 2:** Task + "Previous attempt failed. Review the quality gate output and fix the issues."
- **Attempt 3+:** Task + failure digest (last 50 lines or `failure-digest.sh` output) + "Focus on fixing the root cause."

**Research-backed best practices for retry prompts:**

1. **Signal-then-detail escalation is correct.** Attempt 2 signals failure without overwhelming context. Attempt 3 provides detail. This matches the recommended pattern.

2. **Failure digests should be structured, not raw logs.** Raw log tails include noise (progress bars, timestamps, irrelevant warnings). A digest that extracts: (a) the specific failure message, (b) the file and line number, and (c) the expected vs. actual output is more effective.

3. **"Reflect before retrying" prevents loops.** OpenHands' pattern: "reflect on 5-7 different possible sources of the problem. Assess the likelihood of each possible cause. Methodically address the most likely causes." This is the most important addition for retries.

4. **Prompt framing matters for self-correction.** Research shows that "ask yourself what went wrong" prompts lead to better self-correction than "be aware that you failed" prompts. The former triggers diagnostic reasoning; the latter triggers defensive behavior.

5. **Maximum retry limits prevent infinite loops.** The toolkit's `MAX_RETRIES` already implements this.

6. **Dynamic prompt adaptation improves over iterations.** Error context should not just be appended — it should reshape the instruction. Example: if the failure is a test failure, the retry prompt should say "Run the failing test first to reproduce the issue before attempting any fix."

**Confidence:** Medium. The OpenHands reflection pattern is well-tested in production. The "ask yourself" vs. "be aware" framing difference is from a single medium article but is consistent with known LLM behavior.

### Evidence

- [OpenHands system prompt](https://github.com/All-Hands-AI/OpenHands/blob/main/openhands/agenthub/codeact_agent/prompts/system_prompt.j2) — reflection on failure pattern
- [Augment Code prompting guide](https://www.augmentcode.com/blog/how-to-build-your-agent-11-prompting-techniques-for-better-ai-agents) — truncation strategy
- [Anthropic context engineering guide](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — compaction and context management

### Implications for the Toolkit

The current retry escalation is structurally sound. Specific improvements:

1. **Attempt 2 prompt revision:**
```
Previous attempt failed quality gate. Before implementing again:
1. Read the quality gate output to understand what specifically failed
2. Identify 3 possible root causes
3. Address the most likely cause first
4. Run the failing test to verify your fix before proceeding to other tasks
```

2. **Attempt 3+ prompt revision:**
```
Previous attempts failed (${attempt_count} so far). Failure digest:
\`\`\`
${failure_digest}
\`\`\`

IMPORTANT: Do not repeat the same approach. Step back and consider:
- Is the test expectation wrong, or is the implementation wrong?
- Are there import errors, path errors, or dependency issues?
- Is there an assumption from the plan that doesn't match the actual codebase?

Fix the root cause. Run the specific failing test before running the full suite.
```

3. **The `failure-digest.sh` script should produce structured output** with sections: `FAILING_TEST`, `ERROR_MESSAGE`, `STACK_TRACE`, `EXPECTED_VS_ACTUAL`. Raw tail output is a fallback.

---

## Recommendations

Concrete changes to prompt assembly in `run-plan-prompt.sh`, ordered by expected impact:

### R1. Add Explicit Planning Instruction (High Impact, High Confidence)

**Evidence:** +4% SWE-bench (OpenAI), consistent with all top-performing agents.

Add after the task list in `build_batch_prompt()`:

```bash
cat <<'PLANNING'

Approach:
1. Read relevant files before modifying them — do not assume contents from the plan
2. For each task: write a failing test, confirm it fails, implement the fix, confirm it passes, commit
3. After all tasks: run the quality gate command
4. If the quality gate fails, fix issues before proceeding
PLANNING
```

### R2. Add Persistence Instruction (Medium Impact, High Confidence)

**Evidence:** OpenAI, Anthropic, and Augment all recommend this. Prevents early termination.

Add to the Requirements section:

```
- Complete ALL tasks in this batch. Do not stop early or report partial completion.
- If uncertain about implementation details, read the relevant files rather than guessing.
```

### R3. Add Reflection-on-Failure for Retries (Medium Impact, Medium Confidence)

**Evidence:** OpenHands production usage, consistent with self-correction research.

Modify the retry prompt escalation in `run_mode_headless()`:

```bash
if [[ $attempt -eq 2 ]]; then
    full_prompt="$prompt

Previous attempt failed quality gate. Before re-implementing:
1. Read the quality gate output to understand what failed
2. Identify 3 possible root causes and address the most likely first
3. Run the failing test to verify your fix before proceeding"
```

### R4. Improve Context Ordering (Low-Medium Impact, High Confidence)

**Evidence:** Lost in the Middle (Stanford 2023), confirmed by Augment Code's production experience.

Current ordering is already reasonable. Marginal improvements:

- In `run-plan-context.sh`, when truncating referenced files, use `head -50` AND `tail -20` instead of just `head -50`, joining them with `\n...(truncated)...\n`.
- Add one-line purpose annotations to context_refs headers (extract from first docstring or comment).

### R5. Revise Prompt Variant System (Low Impact, Medium Confidence)

**Evidence:** Top agents do not use short instruction suffixes. They vary workflow structure.

The current `get_prompt_variants()` appends suffixes like "check all imports before running tests." This is a weak signal. Replace with workflow-level variants:

```bash
type_variants[new-file]="Write all test files first, then implement all production files|Implement each task fully (test+code) before moving to the next"
type_variants[refactoring]="Read every file you plan to modify before making any changes|Run the full test suite after each individual modification"
type_variants[integration]="Trace one complete data path end-to-end before declaring done|Write an integration test first that exercises the full flow"
```

These are behavioral instructions, not reminders. They change the agent's workflow, not just its attention.

### R6. Remove Any Generic Role Prompt (No Impact, High Confidence)

**Evidence:** Multiple studies show generic personas have no or negative effect on frontier models.

The current prompt does not have a generic role prompt — it uses a behavioral specification ("You are implementing Batch N"). **Do not add one.** This is a non-action recommendation to prevent future regression.

### R7. Consider Repo Map for Structural Context (Speculative, Low Confidence)

**Evidence:** Aider's repo map approach. No controlled benchmark comparison.

For batches that modify many files, a lightweight file tree with function signatures (like Aider's repo map) could provide better structural awareness than injecting full file contents. This is a larger implementation effort and should be validated experimentally.

### R8. Align with Anthropic's Claude 4.6 Guidance (Medium Impact, High Confidence)

**Evidence:** Official Anthropic documentation for the model the toolkit actually uses.

Key Claude 4.6-specific adjustments:

1. **Remove any anti-laziness language.** Claude 4.6 is already proactive; "be thorough" or "do not be lazy" causes over-exploration. The current prompt does not have this, but the prompt variants should not add it.

2. **Do not add "think step by step."** Anthropic specifically says "Remove explicit think tool instructions" for Claude 4.6 — the model thinks effectively without being told to.

3. **Add context window awareness:** If context compaction is available, add: "Your context window will be compacted as it approaches its limit. Save progress to progress.txt before reaching the limit."

4. **Use the effort parameter** rather than prompt-based reasoning control when invoking `claude -p`.

---

## Sources

### Academic Papers
- Liu et al., "Lost in the Middle: How Language Models Use Long Contexts," TACL 2024 — [arXiv 2307.03172](https://arxiv.org/abs/2307.03172)
- Li et al., "Structured Chain-of-Thought Prompting for Code Generation," ACM TOSEM 2024 — [arXiv 2305.06599](https://arxiv.org/abs/2305.06599)
- Yeo et al., "Chain of Grounded Objectives: Concise Goal-Oriented Prompting for Code Generation," ECOOP 2025 — [arXiv 2501.13978](https://arxiv.org/abs/2501.13978)
- Bairi et al., "Does Few-Shot Learning Help LLM Performance in Code Synthesis?" 2024 — [arXiv 2412.02906](https://arxiv.org/abs/2412.02906)
- Yang et al., "SWE-agent: Agent-Computer Interfaces Enable Automated Software Engineering," 2024 — [arXiv 2405.15793](https://arxiv.org/abs/2405.15793)
- Wang et al., "OpenHands: An Open Platform for AI Software Developers as Generalist Agents," 2024 — [arXiv 2407.16741](https://arxiv.org/abs/2407.16741)
- Zheng et al., "When 'A Helpful Assistant' Is Not Really Helpful: Personas in System Prompts Do Not Improve Performances of Large Language Models" — [arXiv 2311.10054](https://arxiv.org/html/2311.10054v3)
- Zhu et al., "Found in the Middle: How Language Models Use Long Contexts Better via Plug-and-Play Positional Encoding," NeurIPS 2024 — [arXiv 2403.04797](https://arxiv.org/abs/2403.04797)
- Raimondi, "Exploiting Primacy Effect to Improve Large Language Models," RANLP 2025 — [arXiv 2507.13949](https://arxiv.org/abs/2507.13949)

### Vendor Documentation
- [Anthropic Claude 4 Best Practices](https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)
- [Anthropic: Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [OpenAI GPT-4.1 Prompting Guide](https://developers.openai.com/cookbook/examples/gpt4-1_prompting_guide)

### Open-Source Agent Codebases
- [Aider prompts.py](https://github.com/Aider-AI/aider/blob/main/aider/prompts.py)
- [Aider editblock_prompts.py](https://github.com/Aider-AI/aider/blob/main/aider/coders/editblock_prompts.py)
- [OpenHands system_prompt.j2](https://github.com/All-Hands-AI/OpenHands/blob/main/openhands/agenthub/codeact_agent/prompts/system_prompt.j2)
- [SWE-agent ACI documentation](https://github.com/SWE-agent/SWE-agent/blob/main/docs/background/aci.md)
- [SWE-agent templates documentation](https://swe-agent.com/latest/config/templates/)

### Industry Analysis
- [Augment Code: 11 Prompting Techniques for Better AI Agents](https://www.augmentcode.com/blog/how-to-build-your-agent-11-prompting-techniques-for-better-ai-agents)
- [SWE-bench Verified Leaderboard](https://www.vals.ai/benchmarks/swebench)
- [SWE-rebench Leaderboard](https://swe-rebench.com)
- [Verdent SWE-bench Technical Report](https://www.verdent.ai/blog/swe-bench-verified-technical-report)
- [Modal: Open-source AI Agents](https://modal.com/blog/open-ai-agents)
