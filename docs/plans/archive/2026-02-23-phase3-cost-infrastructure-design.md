# Phase 3: Cost Infrastructure — Design

**Date:** 2026-02-23
**Status:** Approved
**Prerequisites:** Phase 1 (complete), Phase 2 (complete)
**Effort:** 1 session (3 batches)

---

## Problem

The toolkit has no cost visibility. Every optimization decision (prompt caching, MAB economics, batch sizing) is guesswork without measured token usage and dollar costs per batch. The `--max-budget-usd` flag in `run-plan.sh` exists but is a no-op. Progress tracking is freeform text that loses structure across context resets.

## Approach

### Batch 3A: Per-Batch Cost Tracking

**Key design decision:** Claude CLI (`claude -p --output-format json`) returns a `session_id` but does not include token usage in the response. Token data lives in JSONL session files at `~/.claude/projects/<project>/<session-id>.jsonl`. We parse these post-hoc.

**New file:** `scripts/lib/cost-tracking.sh`

Functions:
- `find_session_jsonl(session_id)` — locates the JSONL file for a given session ID across project directories
- `extract_session_cost(session_id)` — parses JSONL, returns input tokens, output tokens, cache read tokens, and estimated USD cost
- `record_batch_cost(worktree, batch_num, session_id)` — calls extract, writes to `.run-plan-state.json`
- `check_budget(worktree, max_budget_usd)` — sums all batch costs, returns 1 if exceeded

**State schema addition** (`.run-plan-state.json`):
```json
{
  "costs": {
    "1": {"input_tokens": 12000, "output_tokens": 3400, "cache_read_tokens": 0, "estimated_cost_usd": 0.42, "session_id": "abc-123"},
    "2": {"input_tokens": 11200, "output_tokens": 2800, "cache_read_tokens": 8000, "estimated_cost_usd": 0.31, "session_id": "def-456"}
  },
  "total_cost_usd": 0.73
}
```

**Pricing model:** Hardcoded lookup table by model name (sonnet/opus/haiku) with input/output/cache rates per 1M tokens. Updated manually when pricing changes. No API call needed.

**Integration points:**
1. `run-plan-headless.sh` — after each `claude -p` call, capture session_id from JSON output, call `record_batch_cost()`
2. `run-plan.sh` — wire `--max-budget-usd` to call `check_budget()` before each batch. Abort with clear message if exceeded.
3. `pipeline-status.sh` — add "Cost" section showing per-batch and total costs
4. `run-plan-notify.sh` — include cost in Telegram notification

**Tests:** `tests/test-cost-tracking.sh`
- Mock JSONL file with known token counts, verify extraction
- Verify state schema updates correctly
- Verify budget check returns 1 when exceeded, 0 when within

### Batch 3B: Prompt Caching Structure

**Key design decision:** Anthropic's API automatically caches identical prompt prefixes. We don't need explicit cache control — we need to ensure the stable portion of our prompts is identical across batches so the API cache kicks in.

**Changes to `run-plan-prompt.sh`:**
1. Split `build_batch_prompt()` into two functions:
   - `build_stable_prefix()` — CLAUDE.md chain content, lesson text, project conventions, tool permissions. These don't change between batches.
   - `build_variable_suffix()` — batch tasks, prior progress, quality gate results, referenced files, research warnings. These change every batch.
2. Write stable prefix to `$WORKTREE/.run-plan-prefix.txt` on first batch. Reuse verbatim for subsequent batches (byte-identical enables cache hits).
3. Final prompt = prefix + suffix, assembled at call time.

**Cache observability:**
- After Batch 3A is wired, compare `input_tokens` across batches. If caching works, batches 2+ should show lower input token counts than batch 1 (cache_read_tokens > 0).
- Add `cache_hit_ratio` to state: `cache_read_tokens / (input_tokens + cache_read_tokens)` per batch.
- Display in `pipeline-status.sh` cost section.

**Tests:** `tests/test-run-plan-prompt.sh` (update existing)
- Verify `build_stable_prefix()` output is identical across two calls with different batch numbers
- Verify `build_variable_suffix()` output changes with different batch numbers
- Verify assembled prompt contains both sections in correct order

### Batch 3C: Structured progress.txt

**Replace freeform append with defined schema:**

```markdown
## Batch N: <title>
### Files Modified
- path/to/file (created|modified|deleted)

### Decisions
- <decision>: <rationale>

### Issues Encountered
- <issue> → <resolution>

### State
- Tests: N passing
- Duration: Ns
- Cost: $N.NN
```

**New file:** `scripts/lib/progress-writer.sh`

Functions:
- `write_batch_progress(worktree, batch_num, title)` — writes the batch header
- `append_progress_section(worktree, section, content)` — appends to current batch's section
- `read_batch_progress(worktree, batch_num)` — extracts a single batch's progress (for context injection)

**Integration:**
- `run-plan-headless.sh` — replace raw `echo >>` with `write_batch_progress()` / `append_progress_section()` calls
- `run-plan-context.sh` — use `read_batch_progress()` for the last N batches instead of `tail -20`
- `pipeline-status.sh` — show structured last-batch summary instead of raw tail

**Tests:** `tests/test-progress-writer.sh`
- Write, append, read round-trip
- Verify structured sections parse correctly
- Verify `read_batch_progress` returns only the requested batch

---

## Files Created/Modified

| File | Action | Batch |
|------|--------|-------|
| `scripts/lib/cost-tracking.sh` | Create | 3A |
| `scripts/lib/run-plan-headless.sh` | Modify — capture session_id, call record_batch_cost | 3A |
| `scripts/run-plan.sh` | Modify — wire --max-budget-usd enforcement | 3A |
| `scripts/pipeline-status.sh` | Modify — add cost section | 3A |
| `scripts/run-plan-notify.sh` | Modify — include cost in notification | 3A |
| `tests/test-cost-tracking.sh` | Create | 3A |
| `scripts/lib/run-plan-prompt.sh` | Modify — split into prefix/suffix | 3B |
| `tests/test-run-plan-prompt.sh` | Modify — add prefix/suffix tests | 3B |
| `scripts/lib/progress-writer.sh` | Create | 3C |
| `scripts/lib/run-plan-headless.sh` | Modify — use progress-writer | 3C |
| `scripts/lib/run-plan-context.sh` | Modify — use read_batch_progress | 3C |
| `scripts/pipeline-status.sh` | Modify — structured progress display | 3C |
| `tests/test-progress-writer.sh` | Create | 3C |

---

## Quality Gate

- `make ci` passes (all existing + new tests)
- Cost tracking produces data on a mock JSONL file
- Structured progress.txt parses correctly via `read_batch_progress()`
- Prompt prefix is byte-identical across batches (verified by test)
- Budget enforcement aborts when limit exceeded (verified by test)

---

## What's NOT Included

- Real-time cost streaming (would require stream-json parsing — over-engineered for batch mode)
- Agent SDK migration (JSONL parsing is sufficient; SDK would change the execution layer)
- Historical cost aggregation across runs (single-run tracking is the MVP)
- Pricing API calls (hardcoded lookup table, manually updated)
