# Code Factory v2 — Design Document

**Date:** 2026-02-21
**Status:** Approved
**Approach:** Foundation-First (Phase 1 → 2 → 3 → 4, sequential)

## Problem Statement

The Code Factory pipeline (`auto-compound.sh` → `quality-gate.sh` → `run-plan.sh`) works but has accumulated technical debt: code duplication across scripts, hardcoded paths, missing quality gate steps, no cross-batch context for agents, and no prior-art search. Research across Notion, GitHub (10 repos), web best practices, and the codebase identified 24 concrete improvements.

## Research Findings

### Competitive Landscape (10 repos analyzed)
- **Unique strengths to preserve:** PRD with shell exit codes (no other repo does this), hookify pre-write guardrails, lesson-indexed anti-patterns
- **Gaps to close:** No prior-art search (only RepoMaster/NeurIPS 2025 does this), no lint step, no cross-batch context, no cost tracking
- **Patterns to adopt:** Aider's Architect/Editor split, structured `context_refs` from multi-agent-coding-system, 4-checkpoint quality gate pipeline

### Key Principles
- **Harness Engineering** (OpenAI): Design environments/feedback loops that govern agent behavior
- **Compound Product** (Ryan Carson): Self-improving agent loop where each iteration improves operating instructions
- **Agent specialization formula:** Model + Runtime + MCP + Skills = Specialized Agent (one agent + composable skills > many specialized agents)

### Module Health
| Script | Lines | Status |
|--------|-------|--------|
| `run-plan.sh` | 412 | VIOLATION (>300) — extract headless loop |
| `auto-compound.sh` | 230 | OK |
| `entropy-audit.sh` | 213 | OK |
| `lesson-check.sh` | 195 | OK |
| `analyze-report.sh` | 114 | OK |
| `quality-gate.sh` | 111 | OK |

### Code Duplications Found
1. Project type detection (auto-compound.sh lines 145-163, quality-gate.sh lines 30-50)
2. Arg parsing boilerplate (5 scripts repeat the same pattern)
3. Ollama API calls (analyze-report.sh, entropy-audit.sh)
4. Telegram credential loading (run-plan-notify.sh, lessons-review.sh)
5. JSON fence stripping (analyze-report.sh lines 104-110)

## Design

### Phase 1: Foundation (Shared Library + Module Compliance)

Extract duplicated code into a shared library and bring all scripts under the 300-line limit.

**Task 1.1: Create `scripts/lib/common.sh`**
Extract into shared functions:
- `detect_project_type()` — unified Python/Node/general detection
- `parse_common_args()` — `--help`, `--project-root`, `--verbose` boilerplate
- `strip_json_fences()` — remove ```json wrappers from LLM output
- `check_memory_available()` — memory guard (threshold parameterized)
- `require_command()` — check binary exists, print install hint

**Task 1.2: Create `scripts/lib/ollama.sh`**
Extract Ollama interaction:
- `ollama_query()` — submit prompt to ollama-queue or direct API
- `ollama_parse_json()` — query + strip fences + validate JSON

**Task 1.3: Refactor `auto-compound.sh` to use `common.sh`**
- Replace inline project detection with `detect_project_type()`
- Replace JSON stripping with `strip_json_fences()`
- Fix line 127: PRD output discarded to `/dev/null` with `|| true` (lesson-7 violation)

**Task 1.4: Refactor `quality-gate.sh` to use `common.sh`**
- Replace inline project detection with `detect_project_type()`
- Replace inline memory check with `check_memory_available()`

**Task 1.5: Refactor `entropy-audit.sh`**
- Replace hardcoded `PROJECTS_DIR="$HOME/Documents/projects"` (line 17) with `--project-root` arg or env var
- Use `ollama.sh` for LLM calls

**Task 1.6: Extract `scripts/lib/run-plan-headless.sh`**
- Move `run_mode_headless()` (lines 229-376, 148 lines) from `run-plan.sh` into dedicated lib module
- Target: `run-plan.sh` drops to ~260 lines

**Task 1.7: Refactor `analyze-report.sh` to use shared libs**
- Use `ollama.sh` for LLM calls
- Use `strip_json_fences()` from `common.sh`

### Phase 2: Accuracy (Fix Broken Pipeline Steps)

Fix the pipeline steps that silently fail or produce incomplete results.

**Task 2.1: Fix PRD invocation in `auto-compound.sh`**
- Line 127 discards `/create-prd` output — capture and validate
- Verify headless `claude --print` loads project-scoped commands from `~/Documents/.claude/commands/`
- If not, inline the PRD prompt or add `--commands-dir` flag

**Task 2.2: Fix test count parsing for non-pytest projects**
- `run-plan-quality-gate.sh` line 23: `grep -oP '\b(\d+) passed\b'` is pytest-only
- Add parsers for: `jest` (`Tests: N passed`), `go test` (`ok`/`FAIL`), `npm test` (TAP format)
- Return `-1` (skip regression check) when format is unrecognized, not `0` (which defeats detection)

**Task 2.3: Add cross-batch context to `run-plan-prompt.sh`**
- Include `git log --oneline -5` (recent commits from prior batches)
- Include last 20 lines of `progress.txt` (discoveries, decisions)
- Include previous quality gate result (pass/fail, test count)
- Keep prompt under 2000 tokens to leave room for batch instructions

**Task 2.4: Add cost/duration tracking to state**
- Track per-batch wall time (already computed but not saved)
- Track cumulative duration across batches
- Add `duration_seconds` field to batch entries in `.run-plan-state.json`

**Task 2.5: Wire Telegram credential loading through shared lib**
- Create `scripts/lib/telegram.sh` — single source for `_load_telegram_env()`
- Replace duplicate in `run-plan-notify.sh` and `lessons-review.sh`

### Phase 3: Quality Gates (Lint + Search + Status)

Add missing quality gate steps and a new prior-art search capability.

**Task 3.1: Add `ruff` lint step to `quality-gate.sh`**
- Run `ruff check --select E,W,F` for Python projects
- Run `eslint` for Node projects (if `.eslintrc*` exists)
- Gate: lint errors = fail, warnings = warn-only

**Task 3.2: Create `scripts/prior-art-search.sh`**
- Input: feature description or plan file
- Search GitHub via `gh search repos` and `gh search code`
- Search local codebase via `grep -r` for similar patterns
- Output: ranked list of relevant repos/files with relevance scores
- Integrate with `ast-grep` for structural code search (Phase 4)

**Task 3.3: Create `scripts/license-check.sh`**
- Check dependencies for license compatibility
- Python: parse `pip licenses` output
- Node: parse `license-checker` output
- Flag GPL/AGPL in MIT-licensed projects

**Task 3.4: Create `scripts/pipeline-status.sh`**
- Single-command view of all pipeline components
- Show: last run time, pass/fail, test count, batch progress
- Read from `.run-plan-state.json` and quality gate logs

**Task 3.5: Wire new gates into `quality-gate.sh`**
- Add lint step (Task 3.1) between lesson-check and tests
- Add license check (Task 3.3) as optional `--with-license` flag
- Preserve fast-path: skip slow checks when `--quick` flag is passed

**Task 3.6: Wire prior-art search into `auto-compound.sh`**
- Run before PRD generation
- Pass results as context to PRD prompt
- Log findings to `progress.txt`

### Phase 4: New Capabilities

Add advanced features based on research findings.

**Task 4.1: Create `scripts/failure-digest.sh`**
- Parse failed batch logs
- Extract: error messages, stack traces, failed test names
- Generate structured digest for retry prompts
- Replace the naive `tail -50` in `run-plan.sh` line 291

**Task 4.2: Add persistent `AGENTS.md` to worktrees**
- Auto-generated file listing agent capabilities used in the plan
- Include: tools allowed, model, permission mode, batch assignments
- Agents read this at start of each batch for team awareness

**Task 4.3: Add structured `context_refs` to plan format**
- Each batch can declare dependencies on prior batch outputs
- Format: `context_refs: [batch-2:src/auth.py, batch-3:tests/]`
- Parser extracts refs and includes referenced file contents in prompt

**Task 4.4: Add `ast-grep` integration to prior-art search**
- Structural code search (find patterns by AST shape, not text)
- Install: `cargo install ast-grep` or `npm i @ast-grep/cli`
- Use for: finding similar function signatures, API patterns, test structures

**Task 4.5: Implement team mode in `run-plan.sh`**
- Replace stub at lines 379-384
- Use Claude Code agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)
- Assign batches to parallel agents with shared state file
- Quality gate runs after each batch completion (any agent)

**Task 4.6: Add parallel patch sampling**
- For critical batches: generate N candidate implementations
- Run quality gate on each
- Keep the one with highest test count / cleanest lint
- Inspired by Agentless (NeurIPS 2024) approach

## Dependencies

- **Phase 1** has no external dependencies (pure refactoring)
- **Phase 2** depends on Phase 1 (shared libs)
- **Phase 3** depends on Phase 2 (accurate pipeline) + installs: `ruff`, `ast-grep`
- **Phase 4** depends on Phase 3 (quality gates) + requires agent teams feature

## Success Metrics

1. All scripts under 300 lines
2. Zero code duplication across scripts (shared lib extraction complete)
3. Quality gate catches lint errors, license issues, and test regressions
4. Prior-art search runs before every PRD generation
5. Cross-batch context reduces retry rate by providing agents with prior batch results
6. Pipeline status visible in single command

## Risk Mitigations

- **Breaking existing workflows:** Each phase is independently shippable. Phase 1 is pure refactoring with no behavior change.
- **Headless command loading:** Task 2.1 explicitly tests whether project-scoped commands work in headless mode. Fallback: inline the prompt.
- **Tool installation:** Install tools as needed per phase (ruff in Phase 3, ast-grep in Phase 4). No upfront bulk install.
- **Agent teams instability:** Phase 4 team mode depends on experimental feature flag. Headless mode remains the stable default.
