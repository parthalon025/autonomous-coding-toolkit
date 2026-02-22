# Research: Context Window Utilization and Degradation in AI Coding Agents

**Date:** 2026-02-22
**Domain:** AI Agent Architecture
**Relevance:** autonomous-coding-toolkit Design Principle #1 ("fresh context per batch")
**Status:** Complete

---

## Executive Summary

The toolkit's "fresh context per batch" architecture is **strongly validated** by current research. Context degradation is real, measurable, and non-linear — but the mechanism is more nuanced than simple "context fills up, quality drops." The primary threats are (1) the Lost-in-the-Middle effect causing positional retrieval failures, (2) attention budget exhaustion from irrelevant context, and (3) noise-to-signal ratio degradation as accumulated context grows. The current 6000-char (~1500 token) context injection budget is conservative but defensible — it sits well within the "high-recall zone" where models maintain near-baseline performance. Fresh context per batch is empirically superior to accumulated context for autonomous coding, but the toolkit should adopt **structured context injection** (placing critical information at document edges, using XML tags) and consider **observation masking** as a lightweight alternative to full context reset for retry scenarios.

**Confidence: HIGH** — Multiple peer-reviewed papers, Anthropic's own engineering documentation, and empirical benchmarks from competing agent frameworks all converge on the same conclusions.

---

## 1. The Degradation Curve: When Does Quality Drop?

### Findings

**The degradation is real but task-dependent.** Research converges on several key patterns:

- **U-shaped positional recall:** Information at document edges (0-20% and 80-100% of context depth) achieves high recall. Middle-positioned information suffers dramatic drops. This is the "Lost in the Middle" effect (Liu et al., 2023).

- **Non-linear latency degradation:** The "Context Discipline" paper (Abubakar et al., 2026) measured Llama-3.1-70B at 150% latency degradation at 4K words scaling to 720% at 15K words, following a linear-quadratic trajectory driven by KV cache growth and memory bandwidth constraints.

- **Accuracy remains surprisingly stable under clean conditions:** Llama-70B dropped only 0.5% accuracy (98.5% to 98%) at 15K words. Qwen-14B dropped 1.5% (99% to 97.5%). Mixtral-8x7B dropped 1% (99.5% to 98.5%). These are clean-room conditions — single-needle retrieval tasks with minimal distraction.

- **Real-world degradation is much worse:** The Chroma "Context Rot" study (Hong et al., 2025) found that with distractors present, degradation accelerates dramatically. At 32K tokens, 11 of 12 tested models dropped below 50% of their short-context performance. A model claiming 200K tokens typically becomes unreliable around 130K (~65% utilization).

- **The cliff is not gradual:** Performance drops are often sudden rather than progressive. Models maintain near-baseline performance until hitting a threshold, then quality collapses.

### Evidence Quality

| Source | Type | Confidence |
|--------|------|------------|
| Liu et al. (2023) "Lost in the Middle" | Peer-reviewed (TACL 2024) | HIGH |
| Abubakar et al. (2026) "Context Discipline" | arXiv preprint | MEDIUM-HIGH |
| Chroma "Context Rot" (2025) | Industry research | MEDIUM-HIGH |
| Epoch AI context window analysis (2025) | Data analysis | MEDIUM |

### Implications for the Toolkit

The current architecture's fresh-context approach avoids the degradation curve entirely. Each `claude -p` call starts at the leftmost point of the curve — maximum performance. The 6000-char context injection means each batch operates at roughly 1500 tokens of injected context on top of the batch task text, well below any measured degradation threshold.

**Recommendation:** No change needed to the core architecture. The fresh-context approach is the most robust strategy available. Document the specific degradation thresholds (50% performance at ~32K tokens with distractors, unreliable at ~65% of claimed window) in ARCHITECTURE.md as empirical backing for Design Principle #1.

---

## 2. Is the 6000-Character Context Budget Optimal?

### Findings

The current budget (6000 chars / ~1500 tokens) is **conservative and safe, but could be expanded without risk.**

Key data points:

- **Anthropic's own guidance:** Place long documents (20K+ tokens) near the top of prompts. Queries at the end improve response quality by up to 30%. This suggests Claude handles substantial context volumes well when properly structured.

- **ACON framework thresholds:** Research on optimal compression triggers suggests 4096 tokens for history compression and 1024 tokens for observation compression as effective thresholds. The toolkit's 1500-token budget sits between these.

- **Factory.ai's approach:** Treats context as a "finite, budgeted resource" with a layered stack: repository overviews, semantic search results, targeted file operations, and hierarchical memory. Their per-layer budgets are not published but the architecture implies 2K-5K tokens per layer.

- **Sub-agent patterns from Anthropic:** Sub-agents return condensed summaries of 1000-2000 tokens to coordinating agents. This suggests Anthropic considers this range effective for conveying substantial task context.

- **The diminishing-returns zone:** Below ~500 tokens, agents lack sufficient context for non-trivial tasks. Above ~8K tokens of injected context (on top of the task itself), noise-to-signal ratio starts climbing. The sweet spot for injected auxiliary context appears to be **1000-4000 tokens** (~4000-16000 chars).

### Evidence Quality

| Source | Type | Confidence |
|--------|------|------------|
| Anthropic long-context tips | Official documentation | HIGH |
| ACON framework (Kang et al., 2025) | Peer-reviewed | HIGH |
| Factory.ai architecture | Industry practice | MEDIUM |
| Anthropic sub-agent patterns | Engineering blog | MEDIUM-HIGH |

### Implications for the Toolkit

The 6000-char budget is defensible but could be raised to **8000-12000 chars (~2000-3000 tokens)** to allow richer context injection without approaching any degradation threshold. The priority ordering in `run-plan-context.sh` (directives > failure patterns > referenced files > git log > progress notes) is correct — highest-signal information first.

**Recommendation:** Raise `TOKEN_BUDGET_CHARS` to 10000 (from 6000). This gives ~2500 tokens of auxiliary context — still well within safe bounds, but allows referenced files and progress notes to be included more reliably. The priority ordering should remain as-is.

---

## 3. The "Lost in the Middle" Effect

### Findings

The landmark paper by Liu et al. (2023) from Stanford, UC Berkeley, and Samaya AI demonstrated that:

- **Performance is highest when relevant information is at the beginning or end of context.** This holds across all tested models (GPT-3.5-Turbo, Claude-1.3, MPT-30B, LongChat-13B).

- **Middle-positioned information suffers dramatic retrieval failures.** On multi-document QA, accuracy dropped from ~75% (information at position 1) to ~45% (information at position 10 of 20) for several models — a 30+ percentage point degradation from position alone.

- **The effect persists even in models explicitly designed for long contexts.** LongChat-13B, trained specifically for 16K contexts, still exhibited the U-shaped performance curve.

- **More documents amplify the effect.** Going from 10 to 20 documents increased the performance gap between edge-positioned and middle-positioned information.

- **2025 follow-up research confirms persistence:** The "Lost in the Haystack" paper (2025) found that smaller gold contexts (shorter needles) further degrade performance and amplify positional sensitivity. The effect is not an artifact of early models — it persists in current architectures.

### Evidence Quality

| Source | Type | Confidence |
|--------|------|------------|
| Liu et al. (2023) arXiv 2307.03172 | Peer-reviewed (TACL 2024) | HIGH |
| "Lost in the Haystack" (2025) | Peer-reviewed (NAACL 2025) | HIGH |

### Implications for the Toolkit

The toolkit's `run-plan-prompt.sh` places batch task text in the middle of the prompt, with metadata above and requirements below. This is suboptimal per Lost-in-the-Middle findings.

Current prompt structure:
```
1. Header (batch number, working directory, branch)   <- TOP
2. Tasks in this batch                                 <- MIDDLE
3. Recent commits                                      <- MIDDLE
4. Previous progress                                   <- MIDDLE
5. Referenced files                                     <- MIDDLE
6. Requirements (TDD, quality gate, test count)        <- BOTTOM
```

Optimal structure per research:
```
1. Tasks in this batch (THE CRITICAL CONTENT)          <- TOP (primacy)
2. Referenced files                                    <- NEAR TOP
3. Header metadata                                     <- MIDDLE (low importance, OK here)
4. Recent commits                                      <- MIDDLE
5. Previous progress                                   <- MIDDLE
6. Requirements and directives                         <- BOTTOM (recency)
```

**Recommendation:** Restructure `build_batch_prompt()` to place the batch task text at the very top and the requirements/directives at the very bottom. Metadata and auxiliary context go in the middle where recall is lowest but impact of missing it is also lowest. This is a zero-cost change that could improve batch execution quality by up to 30% (per Anthropic's own testing of query placement).

---

## 4. Model-Specific Degradation

### Findings

Degradation varies significantly by model family and tier:

**Claude models:**
- Most conservative behavior — tend to abstain when uncertain rather than hallucinate (Chroma Context Rot study)
- Opus 4.6 "actually uses full context effectively" unlike previous generations (Anthropic marketing, take with grain of salt)
- Haiku "loses track fast in longer sessions, forgetting variable names and changing class names randomly" — suited for short tasks only
- Sonnet handles multi-file logic and state management well, "remembered context better" than Haiku in real projects

**GPT models:**
- "Highest rates of hallucination, often generating confident but incorrect responses" under context pressure (Chroma)
- GPT-4 fails to retrieve needles toward the start of documents as context length increases

**General patterns:**
- Larger models degrade more gracefully than smaller ones
- MoE architectures (Mixtral) show anomalous behavior — routing overhead at intermediate context lengths can paradoxically slow performance before the expected degradation point
- All models show the positional U-shaped curve, but severity varies

**By task type:**
- Retrieval tasks (find specific information): Most sensitive to context length and position
- Reasoning tasks (analyze and synthesize): More robust to context length, but quality degrades with irrelevant noise
- Code generation: Highly sensitive to having the right context, relatively robust to context volume if signal-to-noise ratio is maintained

### Evidence Quality

| Source | Type | Confidence |
|--------|------|------------|
| Chroma Context Rot (2025) | Industry research, 18 models | MEDIUM-HIGH |
| Real-world model comparisons | Practitioner reports | MEDIUM |
| Abubakar et al. (2026) | arXiv, 3 architectures | MEDIUM-HIGH |

### Implications for the Toolkit

The toolkit's model-agnostic approach (same context budget regardless of model) is reasonable given that all models share the same fundamental degradation patterns. However, the `run-plan.sh` script's `--model` flag could benefit from model-aware context budgets:

- **Haiku:** Reduce context injection budget (shorter attention span). Best for simple, well-specified tasks only.
- **Sonnet:** Current budget is well-suited. Good balance of context utilization and cost.
- **Opus:** Could tolerate larger context budgets, but the marginal benefit is small given the fresh-context architecture already keeps context minimal.

**Recommendation:** Add a model-tier multiplier to `TOKEN_BUDGET_CHARS`: Haiku 0.7x (4200 chars), Sonnet 1.0x (current), Opus 1.3x (7800 chars). LOW priority — the fresh-context architecture already mitigates most model-specific degradation.

---

## 5. The Sweet Spot: Too Little vs. Too Much Context

### Findings

Research and practice converge on a clear framework:

**Too little context (under ~500 tokens injected):**
- Agent doesn't know what happened in previous batches
- Repeats work already done
- Makes decisions inconsistent with prior implementation choices
- Fails to maintain architectural coherence across batches

**Sweet spot (~1000-4000 tokens injected on top of task text):**
- Agent has sufficient memory of prior work (progress notes, recent commits)
- Knows relevant failure patterns to avoid
- Can reference key files without drowning in irrelevant content
- Factory.ai's research shows this range preserves "structural relationships between components"

**Too much context (over ~8K tokens of auxiliary context):**
- Noise drowns signal — irrelevant context actively harms reasoning (Factory.ai)
- "Indiscriminate context stuffing becomes financially unsustainable" at scale
- Lost-in-the-Middle effect places critical information in the low-recall zone
- Latency increases non-linearly (720% at 15K words per Abubakar et al.)

**The critical insight from Factory.ai:** "Compression ratio optimization is counterproductive." OpenAI's aggressive 99.3% compression sacrificed quality. For coding tasks, **total tokens consumed per completed task** matters more than tokens saved per request, because missing details force expensive re-fetching and error cycles.

### Evidence Quality

| Source | Type | Confidence |
|--------|------|------------|
| Factory.ai compression evaluation | Industry benchmark | MEDIUM-HIGH |
| Factory.ai context window problem analysis | Industry research | MEDIUM |
| ACON framework benchmarks | Peer-reviewed | HIGH |

### Implications for the Toolkit

The toolkit's context assembler (`run-plan-context.sh`) already implements the correct priority ordering. The 6000-char budget lands in the sweet spot. The key improvement opportunity is not the budget size but the **information density** of what's injected.

**Recommendation:** Focus on improving context quality over quantity. Specifically:
1. Replace raw `git log --oneline -5` with structured commit summaries (what changed, not just commit messages)
2. Increase `progress.txt` tail from 10 to 15-20 lines (this is the highest-value context for cross-batch continuity)
3. Add XML tags around each context section per Anthropic's guidance: `<prior_batches>`, `<failure_patterns>`, `<referenced_files>`, `<recent_changes>`

---

## 6. Context Compression and Selection Strategies

### Findings

Six major strategies exist, ordered by complexity:

**1. Fresh Context (Context Reset)**
- What the toolkit does: start clean each batch
- Strongest guarantee against degradation
- Trade-off: loses all accumulated knowledge; requires explicit context injection
- Used by: autonomous-coding-toolkit (run-plan.sh Mode C)

**2. Observation Masking (Sliding Window)**
- Replace older environmental outputs with placeholders while preserving agent reasoning
- JetBrains research (2025): matched or exceeded LLM summarization in 4 of 5 configurations
- With Qwen3-Coder 480B: 2.6% solve rate improvement + 52% cost reduction vs. unmanaged context
- Used by: SWE-agent

**3. LLM Summarization (Compaction)**
- Use a separate model call to compress conversation history
- Anthropic's Claude Code uses this ("compaction") when approaching context limits
- Drawback: 13-15% trajectory elongation — agents run longer, increasing cost
- Drawback: "masks failure signals" — summaries may obscure indicators that the agent should stop
- Used by: OpenHands, Claude Code

**4. Structured Summarization (Anchored Iterative)**
- Maintain structured sections (files modified, decisions made, goals remaining) rather than free-form summaries
- Factory.ai's approach: outscored OpenAI and Anthropic on quality (3.70 vs 3.35 and 3.44)
- Preserves technical details like file paths and error codes (accuracy 4.04 vs 3.43)
- All methods struggle with "artifact trail preservation" (2.19-2.45 out of 5.0)

**5. Code-Specific Compression (LongCodeZip)**
- Dual-stage: coarse-grained (AST-based structural compression) + fine-grained (token-level)
- Achieves 5.6x compression without degrading task performance
- Purpose-built for code LLMs
- Published: October 2025

**6. RAG/Semantic Retrieval**
- Use embeddings to retrieve only the most relevant context chunks
- LLMLingua: 20x compression with minimal performance loss when integrated with LangChain/LlamaIndex
- Risk for code: destroys structural relationships between components when chunking naively
- Best used as a complement to, not replacement for, structured context injection

### Evidence Quality

| Source | Type | Confidence |
|--------|------|------------|
| JetBrains context management (2025) | Industry research | HIGH |
| Factory.ai compression evaluation | Industry benchmark | MEDIUM-HIGH |
| ACON framework (ICLR 2025) | Peer-reviewed | HIGH |
| LongCodeZip (2025) | arXiv | MEDIUM-HIGH |
| LLMLingua | Peer-reviewed + deployed | HIGH |

### Implications for the Toolkit

The toolkit's fresh-context approach (Strategy 1) is the most robust but also the most expensive in terms of information loss. The `progress.txt` mechanism and context assembler partially compensate, but there's room to adopt elements of Strategy 4 (structured summarization).

**Recommendation:** Enhance `progress.txt` with structured sections rather than free-form append-only text:
```
## Batch N Summary
### Files Modified
- path/to/file.py (added function X, modified class Y)
### Decisions Made
- Chose approach A over B because...
### Issues Encountered
- Test Z failed due to...
### State
- 45 tests passing, 2 pending
```

This makes the last-N-lines tail read by subsequent batches far more information-dense. The structured format also makes it possible to selectively inject specific sections (e.g., only "Decisions Made" for architecture-sensitive batches).

---

## 7. Anthropic's Official Guidance

### Findings

Anthropic's engineering blog posts and documentation provide clear guidance:

**Context as a finite resource:**
> "LLMs have an attention budget that they draw on when parsing large volumes of context." Context rot emerges across all models — as token count increases, recall accuracy decreases. Even larger context windows remain subject to attention constraints due to transformer architecture limitations (n-squared pairwise token relationships).

**Four key techniques (from Anthropic's "Effective Context Engineering" blog):**

1. **Compaction:** Summarize conversation history when approaching limits. Preserve architectural decisions and unresolved bugs. Discard redundant tool outputs.

2. **Just-in-Time Context:** Maintain lightweight identifiers, dynamically load data at runtime using tools. "Mirrors human cognition — we retrieve information on demand."

3. **Sub-Agent Architecture:** Specialized sub-agents with clean context windows return condensed summaries (1000-2000 tokens) to a coordinating agent. "Fresh start — the main agent context is not carried to subagents."

4. **Progress Documentation:** Maintain `claude-progress.txt` alongside git history. This is explicitly preferred over compaction alone because "compaction doesn't always pass perfectly clear instructions to the next agent."

**Document placement (from Anthropic's long-context tips):**
- Place long documents at the TOP of prompts, above queries and instructions
- Queries at the end improve response quality by up to 30%
- Use XML tags (`<document>`, `<document_content>`, `<source>`) for structure
- Ask Claude to quote relevant parts before answering — cuts through noise

**Multi-window architecture (from Anthropic's "Effective Harnesses" blog):**
- Use an initializer agent for first-window setup, then a coding agent for incremental work
- Each subsequent session: read progress logs and git history, review requirements, run tests, work incrementally
- Prevent agents from "one-shotting" projects — enforce incremental progress

### Evidence Quality

| Source | Type | Confidence |
|--------|------|------------|
| Anthropic "Effective Context Engineering" | Official engineering blog | HIGH |
| Anthropic "Effective Harnesses" | Official engineering blog | HIGH |
| Anthropic long-context tips | Official documentation | HIGH |
| Anthropic context windows docs | Official documentation | HIGH |

### Implications for the Toolkit

The toolkit already implements Anthropic's recommended patterns:
- Fresh sub-processes (≈ sub-agent architecture)
- `progress.txt` (≈ progress documentation)
- Context assembler with budget (≈ just-in-time context)

The gap is in **document placement** — the toolkit doesn't follow the "long content at top, queries at bottom" guidance, and doesn't use XML structuring for context sections.

**Recommendation:** Adopt Anthropic's XML tag structure in the prompt template. Wrap injected context in semantic tags. Place the batch task specification at the top and requirements/directives at the bottom.

---

## 8. Fresh Context vs. Accumulated Context with Good Management

### Findings

This is the core architectural question. The evidence strongly favors fresh context for autonomous coding:

**Arguments for fresh context (the toolkit's approach):**
- Eliminates degradation curve entirely — every batch starts at peak performance
- No risk of Lost-in-the-Middle effects on critical task instructions
- No compaction artifacts or information loss from summarization
- Deterministic context composition — same task always gets the same context structure
- JetBrains research: even best-managed accumulated context (observation masking) only matches fresh context performance while adding complexity
- Anthropic's own recommendation: "When the context window is cleared, consider restarting rather than compressing"

**Arguments for accumulated context:**
- Agents discover things during execution that aren't in the plan (edge cases, API quirks, naming conventions)
- Cross-task dependencies are naturally preserved in conversation history
- No need for explicit context serialization (progress.txt, state files)
- Compaction + context editing can extend effective session length significantly

**Arguments for hybrid (fresh context + rich injection):**
- Gets the reliability of fresh context with the continuity of accumulated knowledge
- `progress.txt` + structured context injection bridges the gap
- Factory.ai's structured summarization shows this approach preserves 95%+ of relevant context across resets
- ACON: 26-54% peak token reduction while maintaining task performance — the savings come from discarding irrelevant accumulated context, not useful context

**The decisive evidence:** JetBrains' 2025 study found that LLM summarization (the best way to manage accumulated context) caused agents to run 13-15% longer and masked failure signals. Observation masking (a partial-reset strategy) matched fresh context performance. This suggests that accumulated context management adds cost and complexity without improving outcomes for well-structured tasks.

**The exception:** For exploratory/debugging tasks (Ralph Loop Mode D), accumulated context has value. The stop-hook approach that re-injects prompts while preserving file-system state is a reasonable hybrid — the agent sees prior work through git history and progress.txt rather than conversation history.

### Evidence Quality

| Source | Type | Confidence |
|--------|------|------------|
| JetBrains context management study (2025) | Industry research, controlled | HIGH |
| Anthropic engineering blogs (2025) | Official guidance | HIGH |
| ACON framework (ICLR 2025) | Peer-reviewed | HIGH |
| Factory.ai structured summarization | Industry benchmark | MEDIUM-HIGH |

### Implications for the Toolkit

Fresh context per batch is validated as the superior strategy for structured plan execution. The toolkit should continue this approach and invest in improving the quality of context injection rather than switching to accumulated context.

**Recommendation:** Maintain fresh context as the default. For Ralph Loop (Mode D), consider implementing observation masking as a lightweight alternative to full context reset — mask old tool outputs while preserving the agent's reasoning chain. This would give Ralph loops better continuity without the full cost of accumulated context.

---

## Consolidated Recommendations

### Priority 1 (High Impact, Low Effort)

1. **Restructure prompt placement in `build_batch_prompt()`:** Move batch task text to the top, requirements to the bottom. Zero-cost change, up to 30% quality improvement per Anthropic's own testing. **Confidence: HIGH.**

2. **Add XML tags to context sections:** Wrap each injected context section in semantic tags (`<batch_tasks>`, `<prior_progress>`, `<failure_patterns>`, `<referenced_files>`, `<requirements>`). Aligns with Anthropic's explicit guidance. **Confidence: HIGH.**

3. **Document empirical basis in ARCHITECTURE.md:** Replace the unsourced claim "context degradation is the #1 quality killer" with specific citations: Lost-in-the-Middle (Liu et al., 2023), Context Rot (Chroma, 2025), and Anthropic's own "attention budget" framing. **Confidence: HIGH.**

### Priority 2 (Medium Impact, Medium Effort)

4. **Raise `TOKEN_BUDGET_CHARS` to 10000:** Current 6000 is safe but conservative. 10000 (~2500 tokens) remains well within the sweet spot while allowing richer context injection. **Confidence: MEDIUM-HIGH.**

5. **Structure `progress.txt` format:** Define sections (Files Modified, Decisions Made, Issues Encountered, State) instead of free-form text. Makes tail reads by subsequent batches far more information-dense. **Confidence: MEDIUM-HIGH.**

6. **Increase `progress.txt` tail read from 10 to 20 lines:** This is the highest-value context for cross-batch continuity, and the current 10-line limit may truncate critical information. **Confidence: MEDIUM.**

### Priority 3 (Lower Priority, Higher Effort)

7. **Model-aware context budgets:** Haiku 0.7x, Sonnet 1.0x, Opus 1.3x multiplier on `TOKEN_BUDGET_CHARS`. Useful but low-urgency given fresh-context architecture already mitigates model-specific degradation. **Confidence: MEDIUM.**

8. **Observation masking for Ralph Loop retries:** When a Ralph iteration fails, mask old tool outputs in the re-injected context rather than providing raw conversation history. JetBrains research shows this matches summarization quality at lower cost. **Confidence: MEDIUM.**

9. **Structured commit summaries:** Replace raw `git log --oneline` with `git log --format="- %s (%h): [files changed]"` or a custom summary that includes which files were modified, not just commit messages. **Confidence: MEDIUM.**

---

## Sources

### Peer-Reviewed Papers

- Liu, N.F. et al. (2023). "Lost in the Middle: How Language Models Use Long Contexts." [arXiv 2307.03172](https://arxiv.org/abs/2307.03172). Published in TACL 2024.
- Kang, M. et al. (2025). "ACON: Optimizing Context Compression for Long-Horizon LLM Agents." [arXiv 2510.00615](https://arxiv.org/abs/2510.00615). ICLR 2025.
- Abubakar et al. (2026). "Context Discipline and Performance Correlation: Analyzing LLM Performance and Quality Degradation Under Varying Context Lengths." [arXiv 2601.11564](https://arxiv.org/abs/2601.11564).
- Wang et al. (2025). "Lost in the Haystack: Smaller Needles are More Difficult for LLMs to Find." [arXiv 2505.18148](https://arxiv.org/abs/2505.18148). NAACL 2025.
- Li et al. (2025). "LongCodeZip: Compress Long Context for Code Language Models." [arXiv 2510.00446](https://arxiv.org/abs/2510.00446).

### Industry Research

- Hong et al. (2025). "Context Rot: How Increasing Input Tokens Impacts LLM Performance." [Chroma Research](https://research.trychroma.com/context-rot).
- JetBrains Research (2025). "Cutting Through the Noise: Smarter Context Management for LLM-Powered Agents." [JetBrains Research Blog](https://blog.jetbrains.com/research/2025/12/efficient-context-management/).
- Factory.ai (2025). "The Context Window Problem: Scaling Agents Beyond Token Limits." [Factory.ai](https://factory.ai/news/context-window-problem).
- Factory.ai (2025). "Evaluating Context Compression for AI Agents." [Factory.ai](https://factory.ai/news/evaluating-compression).
- Epoch AI (2025). "LLMs now accept longer inputs, and the best models can use them more effectively." [Epoch AI](https://epoch.ai/data-insights/context-windows).

### Anthropic Documentation

- Anthropic (2025). "Effective Context Engineering for AI Agents." [Engineering Blog](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents).
- Anthropic (2025). "Effective Harnesses for Long-Running Agents." [Engineering Blog](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).
- Anthropic (2025). "Long Context Prompting Tips." [Claude API Docs](https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/long-context-tips).
- Anthropic (2025). "Context Windows." [Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/context-windows).
- Anthropic (2025). "Prompt Engineering for Claude's Long Context Window." [Anthropic News](https://www.anthropic.com/news/prompting-long-context).

### Agent Framework References

- OpenHands (2025). "The OpenHands Software Agent SDK." [arXiv 2511.03690](https://arxiv.org/abs/2511.03690).
- OpenHands (2025). "CodeAct 2.1: An Open, State-of-the-Art Software Development Agent." [OpenHands Blog](https://openhands.dev/blog/openhands-codeact-21-an-open-state-of-the-art-software-development-agent).
- LLMLingua. "Effectively Deliver Information to LLMs via Prompt Compression." [LLMLingua](https://llmlingua.com/).
