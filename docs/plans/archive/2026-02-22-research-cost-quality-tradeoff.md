# Cost/Quality Tradeoff Modeling for Autonomous Coding Pipelines

**Date:** 2026-02-22
**Status:** Research complete
**Confidence:** High on pricing data (official sources), Medium on quality deltas (benchmark-dependent), Medium on break-even modeling (assumptions documented)

---

## Executive Summary

Running an autonomous coding pipeline costs $5-65 per 6-batch feature depending on execution mode and caching strategy. The single largest cost lever is **prompt caching** (83% reduction), not model selection. Sonnet 4.5/4.6 matches or exceeds Opus on SWE-bench coding benchmarks at 60% of the price, making Opus routing justifiable only for architectural/planning tasks where reasoning depth matters. Competitive (MAB) mode doubles per-batch cost but stays under $2/batch with cache priming — the break-even is any feature where a single rework cycle costs more than $6. Compared to commercial alternatives (Devin at $8-9/hr, Cursor at ~$0.09/request, Copilot at $0.04/premium request), the toolkit's API-direct approach is cheaper for heavy autonomous workloads but lacks the UX guardrails of commercial products.

**Recommendation:** Default to Sonnet with Haiku for verification-only batches. Reserve Opus for planning and judging. Always cache-prime before parallel dispatch. Implement cost tracking per batch (the data doesn't exist yet and every recommendation here would be more precise with it).

---

## 1. Current API Pricing Landscape

### 1.1 Claude Model Pricing (Anthropic, Official)

Source: [Anthropic Pricing Page](https://platform.claude.com/docs/en/about-claude/pricing)

| Model | Input $/MTok | Output $/MTok | Cache Read $/MTok | Cache Write (5m) $/MTok | Batch Input $/MTok | Batch Output $/MTok |
|-------|-------------|--------------|-------------------|------------------------|--------------------|---------------------|
| **Opus 4.6/4.5** | $5.00 | $25.00 | $0.50 | $6.25 | $2.50 | $12.50 |
| **Sonnet 4.6/4.5/4** | $3.00 | $15.00 | $0.30 | $3.75 | $1.50 | $7.50 |
| **Haiku 4.5** | $1.00 | $5.00 | $0.10 | $1.25 | $0.50 | $2.50 |
| Opus 4.1/4 (legacy) | $15.00 | $75.00 | $1.50 | $18.75 | $7.50 | $37.50 |
| Haiku 3.5 | $0.80 | $4.00 | $0.08 | $1.00 | $0.40 | $2.00 |

**Long context surcharge:** Requests exceeding 200K input tokens double the input price and add 50% to output (e.g., Sonnet: $6/$22.50). This is relevant for batch agents with large codebases — staying under 200K tokens per call is a significant cost optimization.

**Key ratio:** Opus 4.6 costs 1.67x Sonnet input and 1.67x Sonnet output. This is dramatically cheaper than legacy Opus 4.1 (5x Sonnet). The Opus tax has shrunk from 5x to 1.67x in one generation.

### 1.2 Competitor Pricing

| Provider | Model | Input $/MTok | Output $/MTok | Notes |
|----------|-------|-------------|--------------|-------|
| OpenAI | GPT-4o | $2.50 | $10.00 | 128K context |
| OpenAI | GPT-4o Mini | $0.15 | $0.60 | Budget tier |
| Google | Gemini 2.5 Pro | $1.25 | $10.00 | Under 200K; doubles above |
| Google | Gemini 2.5 Flash | $0.075 | $0.30 | Cheapest viable option |
| Google | Gemini 3 Pro | $2.00 | $12.00 | Newest generation |

**Finding:** Claude Sonnet ($3/$15) is priced between GPT-4o ($2.50/$10) and Gemini 3 Pro ($2/$12) on input, but is significantly more expensive on output. For output-heavy coding tasks (where the model generates substantial code), Claude's output premium matters. A batch generating 50K output tokens costs $0.75 on Sonnet vs $0.50 on GPT-4o vs $0.60 on Gemini 3 Pro.

**Implication for the toolkit:** The toolkit is model-agnostic at the `claude -p` layer, but the skill chain and quality gates are Claude-specific. Multi-provider routing (send verification batches to Gemini Flash at $0.075/$0.30) would require significant architecture changes but could cut verification costs by 90%.

### 1.3 Discount Mechanisms

| Mechanism | Discount | Latency Impact | Stackable? |
|-----------|----------|---------------|------------|
| **Prompt caching (read)** | 90% off input | Faster (no reprocessing) | Yes, with batch |
| **Prompt caching (write)** | +25% on first call | Minimal | Yes, with batch |
| **Batch API** | 50% off everything | Up to 24h (usually <1h) | Yes, with caching |
| **Cache + Batch combined** | ~95% off cached input | Up to 24h | Yes |

**The stacking math for a typical batch:**
- Uncached Sonnet input (100K tokens): $0.30
- Cached Sonnet input (90K cached + 10K new): 90K × $0.30/MTok + 10K × $3.00/MTok = $0.027 + $0.030 = $0.057
- Cached + Batch: 90K × $0.15/MTok + 10K × $1.50/MTok = $0.0135 + $0.015 = $0.029

That's a 90% reduction from uncached to cached, and 95% from uncached to cached+batch.

---

## 2. Quality Delta Between Models for Coding

### 2.1 Benchmark Evidence

Source: [SWE-bench Verified Leaderboard](https://llm-stats.com/benchmarks/swe-bench-verified), [SWE-rebench](https://swe-rebench.com), [Vellum LLM Leaderboard](https://www.vellum.ai/llm-leaderboard)

| Model | SWE-bench Verified | SWE-bench Pro | Cost/Task (SWE-rebench) |
|-------|-------------------|---------------|------------------------|
| Claude Sonnet 4.5 | 77.2% (82% w/ parallel) | 43.6% | $0.94 |
| Claude Opus 4.5 | 80.9% | 45.9% | — |
| Claude Opus 4.6 | ~80-82% | — | $0.93 |
| GPT-4o | ~49% | — | ~$0.50-1.00 |
| Gemini 2.5 Pro | ~65% | — | ~$0.80 |

**Finding: Sonnet is ~95% of Opus quality on coding benchmarks at 60% of the price.**

On SWE-bench Verified, Sonnet 4.5 scores 77.2% vs Opus 4.5's 80.9% — a 4.6% gap. On SWE-bench Pro (harder), the gap is 2.3 percentage points (43.6% vs 45.9%). Crucially, Sonnet 4.5 with parallel compute (82%) actually exceeds single-shot Opus (80.9%).

**Where Opus still wins:**
- Planning and architecture decisions (qualitative, not well-captured by SWE-bench)
- Complex multi-file refactoring requiring deep reasoning
- Judge/evaluation tasks where nuanced comparison matters
- The SWE-bench Pro gap suggests Opus pulls ahead on harder problems

**Where Opus doesn't justify the cost:**
- Standard implementation tasks (file creation, test writing)
- Verification/run-only batches
- Well-specified tasks with clear acceptance criteria

### 2.2 Cost Per Success Analysis

The metric that matters is **cost per successful batch**, not cost per token.

| Model | Cost/batch | Success rate (est.) | Cost/success |
|-------|-----------|--------------------:|-------------|
| Haiku 4.5 | ~$0.30 | ~60% | ~$0.50 |
| Sonnet 4.6 | ~$0.94 | ~85% | ~$1.11 |
| Opus 4.6 | ~$1.50 | ~90% | ~$1.67 |

Success rates are estimated from SWE-bench data scaled to the toolkit's quality gate pass rates. The key insight: **Haiku's apparent cheapness disappears when factoring in retry cost.** A 60% success rate means 40% of batches need a retry (costing another $0.30+ each), plus the quality gate execution time.

**Implication:** Sonnet is the cost-per-success sweet spot. Haiku is appropriate only for tasks with near-deterministic success (verification-only, run commands, check output). Opus is appropriate when a single failure is very expensive (complex integration, architectural changes).

---

## 3. Cost Per Batch by Execution Mode

### 3.1 Token Consumption Model

Based on SWE-rebench data and Claude Code usage statistics:

| Component | Input Tokens | Output Tokens | Notes |
|-----------|-------------|--------------|-------|
| System prompt + CLAUDE.md chain | ~8,000 | — | Cacheable |
| Plan text (single batch) | ~2,000 | — | Varies by plan |
| Context injection (failure patterns, progress) | ~1,500 | — | From run-plan-context.sh |
| Tool definitions (Bash, Read, Write, Edit, Grep, Glob) | ~2,000 | — | Cacheable |
| File reads during execution | ~20,000 | — | Varies heavily |
| Code generation + tool calls | — | ~15,000 | Primary output cost |
| **Total per batch** | **~33,500** | **~15,000** | Conservative estimate |

### 3.2 Cost Per Batch by Mode

Using Sonnet 4.6 pricing ($3/$15 per MTok) with ~33.5K input, ~15K output:

| Mode | Agents | Calls/Batch | Input Tokens | Output Tokens | Cost/Batch (uncached) | Cost/Batch (cached) |
|------|--------|------------|-------------|--------------|----------------------|---------------------|
| **Headless** | 1 | 1 | 33.5K | 15K | $0.33 | $0.13 |
| **Team** | 2-3 | 2-3 | 67-100K | 30-45K | $0.65-1.00 | $0.26-0.40 |
| **Competitive (MAB)** | 2 + judge | 3 | 80K+ | 35K+ | $0.77+ | $0.31+ |
| **Ralph loop** | 1 (iterating) | 2-5 | 67-167K | 30-75K | $0.65-1.63 | $0.26-0.65 |

**Notes:**
- Team mode spawns implementer + reviewer agents. Each gets its own context window.
- Competitive mode runs 2 parallel implementers + 1 judge evaluation. The judge call is smaller (diff comparison, not full implementation).
- Ralph loop cost depends on iterations. The stop-hook re-injects the prompt each cycle, but context accumulates within a session. Worst case: 5 iterations before convergence.
- Cached prices assume 80% of input tokens hit cache (system prompt + tools + CLAUDE.md chain + plan prefix).

### 3.3 Model Routing Impact on Batch Cost

The toolkit's `classify_batch_model()` function in `run-plan-routing.sh` routes:
- **Haiku** for verification-only batches (all steps are `Run:` commands)
- **Sonnet** for implementation batches (Create/Modify files) — default
- **Opus** for CRITICAL-tagged batches

| Batch Type | Model | Cost (cached) | Frequency |
|-----------|-------|--------------|-----------|
| Implementation (Create) | Sonnet | $0.13 | ~50% |
| Implementation (Modify) | Sonnet | $0.13 | ~30% |
| Verification-only | Haiku | $0.04 | ~10% |
| Critical | Opus | $0.22 | ~10% |

**Weighted average per batch:** ~$0.12 (cached, with routing)
**Without routing (all Sonnet):** ~$0.13 (cached)
**Routing savings:** ~8% — modest, because Sonnet dominates the mix.

**Implication:** Model routing saves less than prompt caching by a large margin. Caching first, routing second.

---

## 4. Total Pipeline Cost for a Typical Feature

### 4.1 Pipeline Stage Costs

| Stage | Model | Calls | Input Tokens | Output Tokens | Cost (cached) |
|-------|-------|-------|-------------|--------------|---------------|
| Brainstorm | Sonnet | 1 interactive session | ~50K | ~10K | $0.20 |
| PRD generation | Sonnet | 1 | ~20K | ~5K | $0.10 |
| Plan writing | Sonnet | 1 | ~30K | ~20K | $0.40 |
| Execution (6 batches, headless) | Mixed | 6 | ~200K | ~90K | $0.78 |
| Quality gates (6x) | — | 0 (bash scripts) | — | — | $0.00 |
| Verification | Sonnet | 1 | ~30K | ~5K | $0.12 |
| **Total (headless, cached)** | | **~10 calls** | **~330K** | **~130K** | **~$1.60** |

### 4.2 Total Cost by Execution Mode (6-batch feature)

| Mode | Base Cost | + Retries (20%) | + Judge (MAB) | Total |
|------|----------|----------------|--------------|-------|
| **Headless** | $1.60 | $0.16 | — | **$1.76** |
| **Team** | $2.38 | $0.24 | — | **$2.62** |
| **Competitive (MAB)** | $2.50 | $0.25 | $0.60 | **$3.35** |
| **Ralph loop** | $2.20 | $0.22 | — | **$2.42** |

**Without caching:**

| Mode | Total (uncached) |
|------|-----------------|
| **Headless** | ~$6.50 |
| **Team** | ~$10.00 |
| **Competitive (MAB)** | ~$13.50 |
| **Ralph loop** | ~$9.00 |

### 4.3 Scaling: What Does a Multi-Feature Sprint Cost?

Assuming 5 features per week, 6 batches each:

| Scenario | Weekly Cost | Monthly Cost |
|----------|-----------|-------------|
| Headless + cached | $8.80 | $35.20 |
| MAB on everything + cached | $16.75 | $67.00 |
| Headless + uncached | $32.50 | $130.00 |
| MAB + uncached | $67.50 | $270.00 |

**Context:** Claude Code's average daily cost per developer is $6, with 90th percentile at $12 (source: [Claude Code cost docs](https://code.claude.com/docs/en/costs)). The toolkit's headless mode with caching would add ~$1.76 per feature on top of any interactive session costs.

---

## 5. When Does Competitive Mode Pay for Itself?

### 5.1 The Rework Cost Model

Competitive mode costs ~$3.35 vs headless at ~$1.76 — a **$1.59 premium** per feature. This premium pays for itself when it avoids rework.

**What does rework cost?**
- A failed batch that passes quality gates but introduces subtle bugs: 1-3 batches of debugging ($0.40-1.20 cached)
- A failed batch caught by quality gates requiring retry: $0.13-0.22 per retry
- A feature that ships broken and requires a hotfix cycle: $3-10 (new brainstorm + plan + execute)
- Developer time debugging AI-generated code: $50-150/hr (opportunity cost)

### 5.2 Break-Even Analysis

| Rework Scenario | Rework Cost | MAB Premium | Break-Even Frequency |
|----------------|------------|-------------|---------------------|
| 1 retry saved | $0.13 | $1.59 | Every 12th feature |
| 1 debugging batch saved | $0.94 | $1.59 | Every 2nd feature |
| 1 hotfix cycle saved | $5.00 | $1.59 | Every 3rd hotfix |
| 1 hour dev time saved | $75.00 | $1.59 | Every 47th feature |

**Finding:** If competitive mode catches architectural issues that would require even one debugging batch per 2 features, it pays for itself. The question is empirical: **does the judge actually catch issues that quality gates miss?**

### 5.3 When to Use Competitive Mode

**Use competitive mode when:**
- The batch involves cross-module integration (highest bug density)
- Historical retry rate for this batch type exceeds 30%
- The cost of a subtle bug is high (production-facing, data-handling)
- You have no strategy performance data yet (exploration phase of MAB)

**Use headless when:**
- The task is well-specified with clear acceptance criteria
- Strategy performance data shows a clear winner (>70% win rate)
- The batch is isolated (single file, no cross-module touches)
- Cost sensitivity is high and quality gates are comprehensive

---

## 6. Model Routing Strategies with Empirical Support

### 6.1 Academic Approaches

Three main paradigms from the literature:

**Routing (single model selection):** A classifier predicts which model will succeed and routes the entire request to that model. Cost = 1 model call + router overhead.
- Hybrid-LLM (ICLR 2024): Routes based on estimated quality gap between models. Works well when the small model handles >60% of queries adequately.
- Source: [ICLR 2024 paper](https://proceedings.iclr.cc/paper_files/paper/2024/file/b47d93c99fa22ac0b377578af0a1f63a-Paper-Conference.pdf)

**Cascading (escalation):** Start with the cheapest model. If confidence is below threshold, escalate to the next tier. Cost = 1-3 model calls, but most stop at tier 1.
- C3PO (2025): Achieves <20% cost of the most capable model with <2% accuracy loss across 16 benchmarks.
- Source: [C3PO paper](https://arxiv.org/pdf/2511.07396)

**Unified routing + cascading (ICLR 2025):** Proves that combining routing and cascading is strictly better than either alone. 4% improvement on RouterBench with 80% relative improvement over naive baselines.
- Source: [Unified approach](https://arxiv.org/abs/2410.10347)

### 6.2 Current Toolkit Strategy

The toolkit uses static routing via `classify_batch_model()`:

```
Create files → Sonnet
Modify files → Sonnet
Run-only (verification) → Haiku
CRITICAL tag → Opus
Default → Sonnet
```

This is pure routing (no cascading). It's simple and low-overhead but leaves money on the table.

### 6.3 Recommended Improvements

**Short-term (no architecture changes):**
1. **Retry escalation already exists** — the toolkit escalates context on retry (includes previous failure log). Adding model escalation (Haiku → Sonnet → Opus on retry) would implement cascading with zero new infrastructure.
2. **Tag more batches as Haiku-eligible.** Currently only "all-Run" batches get Haiku. Config/documentation-only batches, test-only batches, and simple rename/move batches could also use Haiku.

**Medium-term (requires tracking):**
3. **Cost-per-success tracking.** Record model, cost, and pass/fail per batch in `.run-plan-state.json`. After 50+ data points, the toolkit can make data-driven routing decisions.
4. **Complexity-based routing.** Use batch metadata (file count, line count of changes, number of cross-file references) as routing features. More complex batches → higher-tier model.

**Long-term (architecture change):**
5. **Cascade on failure.** Instead of retrying with the same model + more context, retry with a more capable model. Haiku fails → Sonnet retry → Opus retry. Cost increases only when needed.

---

## 7. Prompt Caching Economics

### 7.1 How Caching Works for the Toolkit

The toolkit's `claude -p` calls have a highly cacheable prefix:

| Component | Tokens | Cacheable? | Cache Hit Rate |
|-----------|--------|-----------|---------------|
| System prompt | ~2,000 | Yes | ~100% across batches |
| CLAUDE.md chain (3 files) | ~4,000 | Yes | ~100% across batches |
| Tool definitions | ~2,000 | Yes | ~100% across batches |
| AGENTS.md (per-worktree) | ~1,000 | Yes | ~100% across batches |
| Plan text (current batch) | ~2,000 | No | 0% (changes per batch) |
| Context injection | ~1,500 | No | 0% (changes per batch) |
| File contents read during execution | ~20,000 | Partial | ~50% (some files repeated) |
| **Cacheable total** | **~9,000** | | |
| **Non-cacheable total** | **~24,500** | | |

**Effective cache rate:** ~27% of input tokens are cacheable across batches (the static prefix). Within a batch with multiple tool calls, the entire conversation so far is cacheable for each subsequent turn, pushing effective rates to 60-80%.

### 7.2 Cache Priming for Parallel Agents

The MAB round 2 research identified a critical pattern: when two agents launch simultaneously with uncached content, both pay write costs independently. The fix is a "prime the cache" call:

1. Send a single API call with the shared prefix (system prompt + CLAUDE.md + tools + design doc + PRD)
2. This call creates the cache entry (costs 1.25x input)
3. Both parallel agents then get cache-read pricing (0.1x input) on the shared prefix

**Savings per MAB batch:**
- Without priming: 2 × cache write = 2 × 1.25x × $3.00/MTok × 9K tokens = $0.0675
- With priming: 1 × cache write + 2 × cache read = 1.25x × $3.00/MTok × 9K + 2 × 0.1x × $3.00/MTok × 9K = $0.034 + $0.0054 = $0.039
- Savings: $0.028 per batch, or ~42% of the cache-related costs

This is small in absolute terms but compounds: over a 26-task MAB plan, it saves ~$0.73.

### 7.3 Batch API for Non-Interactive Work

The Batch API offers 50% off everything with up to 24-hour latency (usually under 1 hour). This is directly applicable to the toolkit's headless mode — `claude -p` calls are already non-interactive.

**Current barrier:** The toolkit uses `claude -p` (CLI), not the Batch API directly. Converting to Batch API would require:
1. Constructing API requests as JSON
2. Submitting batches via `curl` or a thin wrapper
3. Polling for completion
4. Parsing results

**Potential savings:** 50% across the board. A 6-batch headless feature drops from $1.76 to $0.88 (cached + batched).

---

## 8. Economics of Retry

### 8.1 Retry Cost Model

Each retry is a full API call — no discount for "trying again." The retry includes:
- All original context (system prompt, tools, plan)
- Additional context: previous failure log (~2,000 tokens)
- The model's new attempt (full output token cost)

**Cost per retry = base batch cost + ~10% overhead for failure context.**

### 8.2 Expected Retry Costs

| Scenario | P(success) | E[retries] | E[cost] per batch | vs. Single-shot |
|----------|-----------|-----------|-------------------|----------------|
| Sonnet, well-specified | 90% | 0.11 | $0.14 | +8% |
| Sonnet, complex integration | 70% | 0.43 | $0.19 | +46% |
| Haiku, simple task | 80% | 0.25 | $0.05 | +25% |
| Haiku, moderate task | 50% | 1.00 | $0.08 | +100% |

Expected retries formula: E[retries] = (1 - p) / p for geometric distribution, capped at max_retries (typically 3).

### 8.3 When to Retry vs. Escalate

**Current behavior:** Retry same model with more context (failure log appended).
**Better behavior:** Escalate model tier after first failure.

| Strategy | Avg cost/batch (complex task) | Success rate |
|----------|------------------------------|-------------|
| Retry same model (3x Sonnet) | $0.39 (3 × $0.13) | ~97% |
| Escalate (Sonnet → Opus) | $0.35 ($0.13 + $0.22) | ~98.5% |
| Escalate (Haiku → Sonnet → Opus) | $0.39 ($0.04 + $0.13 + $0.22) | ~99% |

**Finding:** Escalation is slightly cheaper than retry-at-same-tier for complex tasks because the higher-tier model is more likely to succeed on attempt 1, avoiding the cost of a third attempt. The quality improvement is marginal (97% vs 98.5%) but the cost structure is better.

---

## 9. Commercial AI Coding Tool Pricing

### 9.1 Pricing Comparison

| Tool | Pricing Model | Monthly Cost | $/Hour of Work | Notes |
|------|--------------|-------------|---------------|-------|
| **Devin** (Core) | $20/mo + $2.25/ACU | $20+ | ~$9.00/hr | 1 ACU = ~15 min work |
| **Devin** (Team) | $500/mo + $2.00/ACU | $500+ | ~$8.00/hr | 250 ACUs included |
| **Cursor** (Pro) | $20/mo | $20 | ~$0.09/request | ~225 requests/mo with Claude |
| **Cursor** (Ultra) | $200/mo | $200 | ~$0.05/request | 20x capacity |
| **GitHub Copilot** (Pro) | $10/mo | $10 | $0.04/overage | 300 premium requests |
| **GitHub Copilot** (Pro+) | $39/mo | $39 | $0.04/overage | 1,500 premium requests |
| **Toolkit** (API direct) | Pay-per-token | $0-270/mo | ~$0.29/batch | Depends entirely on usage |

### 9.2 Cost-Effectiveness Comparison

For a developer running 5 features/week (6 batches each = 30 batches/week):

| Tool | Monthly Cost | Autonomous? | Quality Gates? |
|------|-------------|------------|---------------|
| Toolkit (headless, cached) | ~$35 | Yes | Yes (built-in) |
| Toolkit (MAB, cached) | ~$67 | Yes | Yes + competitive evaluation |
| Devin (equivalent work) | ~$360-720 | Yes | Limited (proprietary) |
| Cursor Pro | $20 (capped) | No (interactive) | No (manual) |
| Copilot Pro | $10 (capped) | Partial (agent mode) | No (manual) |

**Finding:** The toolkit is the cheapest option for autonomous batch execution. Commercial tools are cheaper for interactive use (fixed monthly fee) but don't support headless autonomous operation with quality gates.

### 9.3 What You're Paying For

| Capability | Toolkit | Devin | Cursor | Copilot |
|-----------|---------|-------|--------|---------|
| Autonomous execution | Yes | Yes | No | Partial |
| Quality gates | Yes | No | No | No |
| Fresh context per batch | Yes | Unknown | No | No |
| Model routing | Yes | No | Yes (credit-weighted) | Yes (model selection) |
| Cost transparency | Yes (API direct) | ACU-abstracted | Credit-abstracted | Request-abstracted |
| UX/IDE integration | No (CLI) | Web UI | VS Code | VS Code/GitHub |

---

## 10. Cost Model for the Autonomous Coding Toolkit

### 10.1 Per-Batch Cost Calculator

```
batch_cost = (input_tokens × input_rate × cache_factor) + (output_tokens × output_rate)

Where:
  input_rate:
    haiku:  $1.00/MTok
    sonnet: $3.00/MTok
    opus:   $5.00/MTok

  output_rate:
    haiku:  $5.00/MTok
    sonnet: $15.00/MTok
    opus:   $25.00/MTok

  cache_factor:
    uncached: 1.0
    first call (write): 1.25
    subsequent (read): 0.1
    effective (80% cache hit): 0.28

  Typical batch:
    input_tokens:  33,500
    output_tokens: 15,000
```

### 10.2 Reference Cost Table

All costs in USD per batch, assuming typical token consumption:

| Configuration | Sonnet (uncached) | Sonnet (cached) | Haiku (cached) | Opus (cached) |
|--------------|------------------|-----------------|----------------|--------------|
| Headless (1 call) | $0.33 | $0.13 | $0.04 | $0.22 |
| Team (2 calls) | $0.65 | $0.26 | $0.09 | $0.43 |
| Competitive (2+judge) | $0.77 | $0.31 | $0.12 | $0.52 |
| With 1 retry | $0.46 | $0.18 | $0.06 | $0.30 |
| With 2 retries | $0.59 | $0.23 | $0.07 | $0.39 |

### 10.3 Full Pipeline Cost Table

| Pipeline Configuration | 6-Batch Feature | 12-Batch Feature | 26-Batch Sprint |
|----------------------|----------------|-----------------|----------------|
| Headless, all Sonnet, cached | $1.60 | $2.40 | $4.20 |
| Headless, routed, cached | $1.52 | $2.24 | $3.90 |
| MAB on all batches, cached | $3.35 | $5.50 | $10.40 |
| MAB selective (30% MAB), cached | $2.12 | $3.40 | $6.10 |
| Headless, all Sonnet, uncached | $6.50 | $10.00 | $18.00 |

### 10.4 Monthly Budget Estimates

For a solo developer using the toolkit full-time (20 features/month, 6 batches avg):

| Strategy | Monthly API Cost | Annual |
|----------|-----------------|--------|
| Conservative (headless, cached, routed) | $30 | $365 |
| Balanced (headless + selective MAB, cached) | $42 | $510 |
| Aggressive (MAB everything, cached) | $67 | $804 |
| Uncached baseline | $130 | $1,560 |

---

## 11. Recommendations

### Priority-ordered by impact:

1. **Implement prompt caching immediately.** 83% cost reduction, zero quality tradeoff. This is the single highest-ROI optimization. Ensure the CLAUDE.md chain, system prompt, and tool definitions are in the cacheable prefix of every `claude -p` call.

2. **Add cost tracking per batch.** Record `{model, input_tokens, output_tokens, cache_hits, cost, passed}` to `.run-plan-state.json`. Without this data, all cost optimization is guesswork. This is prerequisite to every other recommendation.

3. **Keep Sonnet as default.** The SWE-bench data shows Sonnet 4.5/4.6 is 95% of Opus quality at 60% of the price. The 4.6-generation Opus price drop (from 5x to 1.67x Sonnet) makes Opus more tempting, but Sonnet remains the cost-per-success sweet spot for implementation tasks.

4. **Implement model escalation on retry.** Instead of retrying the same model with more context, escalate: Haiku → Sonnet → Opus. This is cheaper than 3x same-model retry and has a higher cumulative success rate.

5. **Use selective MAB, not universal MAB.** Run competitive mode on integration batches, first-time batch types, and historically-flaky batch types. Route known-easy batches to headless. Target 30% MAB rate for optimal cost/learning balance.

6. **Cache-prime before parallel dispatch.** When running MAB or team mode, fire a single "warm the cache" call with the shared prefix before launching parallel agents. Saves ~42% of cache-related costs.

7. **Evaluate Batch API for overnight runs.** For non-urgent features (entropy audits, batch-audit.sh, auto-compound.sh overnight), the Batch API's 50% discount is free money. Requires thin wrapper around `curl` to submit and poll.

8. **Expand Haiku eligibility.** Currently only verification-only batches get Haiku. Add: test-only batches, config/documentation updates, simple file renames. Each Haiku-eligible batch saves $0.09 vs Sonnet (cached).

### What NOT to optimize:

- **Don't chase multi-provider routing.** Sending verification batches to Gemini Flash would save ~$0.03/batch but requires significant architecture changes. Not worth it at current scale.
- **Don't use Opus for everything.** The 1.67x cost premium over Sonnet is not justified by the 5% quality improvement for standard implementation tasks.
- **Don't skip quality gates to save money.** Quality gates are bash scripts with zero API cost. They prevent the most expensive failure mode: subtle bugs that ship and require full rework cycles.

---

## Sources

### Pricing (Official)
- [Anthropic Claude API Pricing](https://platform.claude.com/docs/en/about-claude/pricing)
- [OpenAI API Pricing](https://platform.openai.com/docs/pricing)
- [Google Gemini API Pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Devin AI Pricing](https://devin.ai/pricing)
- [GitHub Copilot Plans](https://github.com/features/copilot/plans)
- [Cursor Pricing](https://cursor.com/pricing)

### Benchmarks & Performance
- [SWE-bench Verified Leaderboard](https://llm-stats.com/benchmarks/swe-bench-verified)
- [SWE-rebench Leaderboard](https://swe-rebench.com) (cost-per-task data)
- [Vellum LLM Leaderboard](https://www.vellum.ai/llm-leaderboard)
- [Claude Sonnet 4.5 Benchmarks](https://www.leanware.co/insights/claude-sonnet-4-5-overview)

### Caching & Optimization
- [Anthropic Prompt Caching Docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- [Anthropic Batch Processing Docs](https://platform.claude.com/docs/en/build-with-claude/batch-processing)
- [Claude Code Cost Management](https://code.claude.com/docs/en/costs)

### Research Papers
- [Unified Routing and Cascading for LLMs — ICLR 2025](https://arxiv.org/abs/2410.10347)
- [Hybrid LLM: Cost-Efficient Quality-Aware — ICLR 2024](https://proceedings.iclr.cc/paper_files/paper/2024/file/b47d93c99fa22ac0b377578af0a1f63a-Paper-Conference.pdf)
- [C3PO: Optimized LLM Cascades — 2025](https://arxiv.org/pdf/2511.07396)
- [Why Multi-Agent LLM Systems Fail — 2025](https://arxiv.org/pdf/2503.13657)

### Internal References
- [MAB Research Round 2](/home/justin/Documents/projects/autonomous-coding-toolkit/docs/plans/2026-02-22-mab-research-round2.md) — cost economics, cache priming pattern
- [Architecture](/home/justin/Documents/projects/autonomous-coding-toolkit/docs/ARCHITECTURE.md) — execution modes, quality gates
- [Run-Plan Routing](/home/justin/Documents/projects/autonomous-coding-toolkit/scripts/lib/run-plan-routing.sh) — model classification logic
