# Research: Code Guideline Policies for AI Coding Agents

> **Date:** 2026-02-22
> **Status:** Research complete
> **Method:** Web research + competitive analysis + academic literature
> **Confidence:** High on landscape/format findings, Medium on optimal instruction counts, Low on long-term measurability

## Executive Summary

The autonomous-coding-toolkit has strong negative enforcement (lessons, hookify, quality gates) but no positive policy system. This research examines how to add one.

**Key findings:**

1. **Positive instructions outperform negative ones.** LLMs follow "always do X" significantly better than "never do Y" due to how token generation works. The toolkit's anti-pattern system (negative) should be complemented by a positive policy system, not replaced.

2. **There is an emerging cross-tool standard.** AGENTS.md (Linux Foundation/Agentic AI Foundation) is the closest thing to a universal policy file, supported by 20+ tools. CLAUDE.md remains Claude Code's native format. The toolkit should support both.

3. **Instruction saturation is real and quantifiable.** Frontier LLMs can follow ~150-200 instructions with reasonable consistency. Claude Code's system prompt consumes ~50, leaving ~100-150 for user instructions. Policy files must be ruthlessly pruned to stay within this budget.

4. **Scoped, file-triggered policies beat monolithic rule files.** Cursor's `.mdc` format (glob-triggered rules) and GitHub Copilot's path-specific instructions demonstrate that policies attached to relevant files outperform global rule dumps. The signal-to-noise ratio matters more than rule count.

5. **The enforcement spectrum has three tiers.** Hard (gate/block) for safety and correctness, soft (prompt injection) for style and conventions, and post-hoc (review/audit) for subjective quality. The toolkit already covers hard enforcement; the gap is in soft and post-hoc.

6. **Policies and lessons are complementary, not overlapping.** Lessons capture "what went wrong" (reactive, negative). Policies capture "how we work" (proactive, positive). They serve different functions and should remain separate systems with cross-references.

---

## 1. Policy File Landscape

### Findings

The AI coding agent ecosystem has converged on markdown-based instruction files placed in the repository, with tool-specific naming conventions:

| Tool | File(s) | Format | Scoping | Injection Point |
|------|---------|--------|---------|-----------------|
| **Claude Code** | `CLAUDE.md` (root, parents, children, `~/.claude/`) | Markdown, freeform | Directory hierarchy | Every session start |
| **Cursor** | `.cursor/rules/*.mdc` (replaces legacy `.cursorrules`) | Markdown with YAML frontmatter (globs, alwaysApply, description) | Glob patterns, always, agent-requested, manual | Per-file or always, based on type |
| **GitHub Copilot** | `.github/copilot-instructions.md` + `.github/instructions/**/*.instructions.md` | Markdown with `applyTo` glob frontmatter | Repository-wide + path-specific | Attached to every chat/inline request |
| **Windsurf** | `.windsurf/rules/*.md` (replaces legacy `.windsurfrules`) | Markdown, topic-organized | Global (user) + project | Per-session |
| **Amazon Q** | `.amazonq/rules/*.md` | Markdown | Project-level | Scanned on first interaction, evaluated per request |
| **Aider** | `CONVENTIONS.md` (or any markdown via `--read`) | Markdown | Project-level | Loaded as read-only context |
| **JetBrains Junie** | `.junie/guidelines.md` | Markdown | Project-level | Per-task |
| **AGENTS.md** | `AGENTS.md` (root + subdirectories) | Markdown, freeform | Directory hierarchy (closest wins) | Cross-tool standard, 20+ agents |
| **ESLint** | `eslint.config.js` | JavaScript/JSON | Rule-level with overrides | Build-time enforcement |
| **Ruff/Black** | `pyproject.toml [tool.ruff]` | TOML | File/directory patterns | Build-time enforcement |
| **EditorConfig** | `.editorconfig` | INI with globs | File patterns | Editor-level |
| **Prettier** | `.prettierrc` | JSON/YAML/JS | File patterns | Build-time |

### Evidence

Every major AI coding tool has independently arrived at the same pattern: **a markdown file in the repository that gets injected into the agent's context**. The format is always natural language markdown, not structured config. This is because:

1. LLMs consume natural language natively -- no parsing overhead.
2. Markdown is human-readable and version-controllable.
3. The instruction set is inherently fuzzy (style, conventions, preferences) and resists formalization into structured schemas.

Traditional tools (ESLint, Ruff, Prettier, EditorConfig) use structured config because they perform deterministic enforcement. AI agent tools use natural language because the enforcement is probabilistic.

**AGENTS.md** is emerging as the cross-tool standard, stewarded by the Agentic AI Foundation under the Linux Foundation. It is supported by OpenAI Codex, Google Jules/Gemini CLI, GitHub Copilot, Cursor, Windsurf, Factory, Aider, and 15+ others. Its key design principle: "The closest AGENTS.md to the edited file wins; explicit user chat prompts override everything."

### Implications for the Toolkit

The toolkit should:
- **Support AGENTS.md** as the cross-tool policy format (broadest compatibility).
- **Continue using CLAUDE.md** for Claude Code-specific instructions (deepest integration).
- **Adopt scoped policies** (directory-level or glob-triggered) rather than a single monolithic file.
- **Use markdown** as the policy format -- not YAML, not JSON, not structured config. Natural language is the native format for LLM consumption.

**Confidence: High.** The convergence across 10+ independent tools is strong evidence that markdown-in-repo is the right format.

---

## 2. Positive vs. Negative Enforcement

### Findings

Research and practitioner evidence consistently show that LLMs respond better to positive instructions ("do X") than negative constraints ("don't do Y"):

1. **Token generation is inherently positive-selective.** LLMs predict the next most likely token -- they boost probabilities of desired outputs rather than suppressing undesired ones. Negative prompts only slightly reduce probabilities of unwanted tokens, while positive prompts actively boost desired outcomes.

2. **InstructGPT performance degrades with negative prompts at scale.** Research on the NeQA benchmark shows that negation understanding does not reliably improve as models get larger. Models like GPT-3, GPT-Neo, and InstructGPT "consistently struggle with negation across multiple benchmarks."

3. **Practitioner evidence is consistent.** Users report that LLMs "seem to produce worse output" the more "DO NOTs" appear in prompts. Specific example: Claude Code continued creating duplicate files despite explicit rules stating "NEVER create duplicate files."

4. **The "Pink Elephant Problem."** Analogous to Ironic Process Theory in psychology -- trying to suppress a specific thought makes it more likely to surface. When you tell an LLM "don't use mock data," the tokens "mock" and "data" get activated in the attention mechanism, potentially increasing their probability.

**Reframing examples that work:**

| Negative (less effective) | Positive (more effective) |
|--------------------------|--------------------------|
| "Don't use mock data" | "Only use real-world data" |
| "Don't uppercase names" | "Always lowercase names" |
| "Avoid creating new files" | "Apply all fixes to existing files" |
| "Don't include fields with no value" | "Only include fields that have a value" |
| "Never use bare except" | "Always catch specific exception types and log them" |
| "Don't hardcode test counts" | "Assert test discovery dynamically using `len(collected)`" |

### Evidence

- Research papers: NeQA benchmark studies on InstructGPT negation performance.
- Practitioner reports: Multiple Reddit threads and blog posts documenting negative instruction failures in Cursor, Claude Code, and GPT-4.
- Theoretical basis: Token generation mechanics (positive selection), Ironic Process Theory applied to neural networks.

### Implications for the Toolkit

The toolkit's existing lesson system is primarily negative ("don't do X" -- bare exceptions, async without await, create_task without callback). This is **correct for the enforcement layer** (quality gates should block known-bad patterns) but **incomplete for the guidance layer** (agents need to know what TO do, not just what NOT to do).

**Recommendation:** Create a policy system that complements lessons:

| System | Framing | Function | Enforcement |
|--------|---------|----------|-------------|
| Lessons | Negative ("don't do X") | Catch known bugs | Hard gate (lesson-check.sh) |
| Policies | Positive ("always do Y") | Guide correct patterns | Soft injection (prompt context) |

Every lesson should have an optional `positive_alternative` field that gets injected into agent prompts as a policy. Example: Lesson 0001 (bare except) maps to policy "Always catch specific exception types (ValueError, KeyError, etc.) and log the exception before any fallback behavior."

**Confidence: High** on the principle. **Medium** on the magnitude of improvement -- the research is qualitative, not quantified with compliance percentages.

---

## 3. Policy Injection Mechanics

### Findings

#### Where in the prompt should policies go?

Claude Code's CLAUDE.md content is injected as a system-level context block that Claude reads at the start of every conversation. Based on Anthropic's best practices documentation:

- CLAUDE.md goes into **every single session**, so contents must be universally applicable.
- Claude Code's system prompt contains ~50 individual instructions.
- Frontier thinking LLMs can follow **~150-200 instructions** with reasonable consistency.
- This leaves a budget of **~100-150 instructions** for user-defined policies.

Position matters: research shows models retrieve best from the **beginning or end** of long context, and degrade for information buried in the middle (the "lost in the middle" phenomenon).

#### How much policy text can an LLM absorb?

- **Optimal operating range:** 70-80% of context window capacity. Beyond this, accuracy drops regardless of remaining token capacity.
- **Smaller models show exponential decay** in instruction-following as count increases. Frontier models show **linear decay** -- more graceful but still real.
- Long system prompts increase prefill latency (time to first token) and bloat the KV cache for the entire turn.

#### What format works best?

Based on cross-tool convergence and Anthropic's official guidance:

| Format | LLM Effectiveness | Human Readability | Tooling Support |
|--------|-------------------|-------------------|-----------------|
| Prose paragraphs | Low -- buried signal | Medium | Universal |
| Bullet lists | High -- scannable | High | Universal |
| Numbered rules | High -- ordered, referenceable | High | Universal |
| Code examples | Highest -- concrete, unambiguous | Medium | Universal |
| YAML/JSON | Medium -- parseable but noisy | Low | Requires parser |
| Tables | High for comparisons | High | Markdown renderers |

**Best practice from Anthropic's documentation:**

```markdown
# Code style
- Use ES modules (import/export) syntax, not CommonJS (require)
- Destructure imports when possible (eg. import { foo } from 'bar')

# Workflow
- Be sure to typecheck when you're done making a series of code changes
- Prefer running single tests, not the whole test suite, for performance
```

Short, imperative bullet points. No prose. No explanation unless the rule is non-obvious. Code examples when the pattern is complex.

**Emphasis markers improve adherence:** Adding "IMPORTANT" or "YOU MUST" to critical rules measurably improves compliance, per Anthropic's documentation.

### Implications for the Toolkit

Policy injection should:
1. **Use bullet-list format** -- one rule per line, imperative voice, positive framing.
2. **Include code examples** for non-obvious patterns (the single highest-fidelity format for LLMs).
3. **Stay under 100 rules total** across all injected policy sources for a given session.
4. **Position critical rules first and last** in the policy block (primacy and recency effects).
5. **Inject scoped policies only when relevant** (glob-triggered, like Cursor's `.mdc`) to avoid wasting the instruction budget on irrelevant rules.
6. **Never duplicate what linters enforce.** Anthropic's own guidance: "Never send an LLM to do a linter's job."

**Confidence: High** on format and positioning. **Medium** on the 150-200 instruction limit (single source, no independent replication found).

---

## 4. Policy Scoping

### Findings

Policies naturally fall into four scopes, each with different update frequency and blast radius:

| Scope | Examples | Update Frequency | Applies To |
|-------|----------|------------------|------------|
| **Universal** | "Always handle errors explicitly," "Include type hints" | Rarely | All projects |
| **Language** | "Use pathlib over os.path," "Prefer f-strings over .format()" | Occasionally | All Python projects |
| **Framework** | "Use Pydantic models for API schemas," "Use pytest fixtures over setUp/tearDown" | Per-project | Projects using that framework |
| **Project** | "State management is in src/stores/," "Use the `ApiClient` class for all HTTP calls" | Frequently | Single project |

#### How to prevent policy bloat

The Cursor `.mdc` format provides the best model for scoped policies:

- **Always rules** (`alwaysApply: true`): Injected into every context. Reserve for universal and language-level policies. Budget: 20-30 rules max.
- **Auto-attached rules** (glob-triggered): Injected only when working with matching files. Example: `*.test.py` triggers testing conventions. Budget: 10-15 rules per scope.
- **Agent-requested rules** (description-based): The agent reads descriptions and pulls in rules it deems relevant. Lowest injection overhead.
- **Manual rules**: Never auto-injected. Reference material only.

GitHub Copilot's approach is similar but simpler: `.github/copilot-instructions.md` for global, `.github/instructions/**/*.instructions.md` with `applyTo` globs for scoped.

AGENTS.md uses directory hierarchy: place `AGENTS.md` in each subdirectory, and the closest one to the file being edited wins. This is identical to how CLAUDE.md works in Claude Code.

#### Evidence for scoping effectiveness

Cursor users report that migrating from a single `.cursorrules` file (often 500+ lines) to scoped `.mdc` files dramatically improved compliance: "Isn't 20 mdc files too much information for Cursor? No. This is what .mdc files solve." The key insight: the agent sees only the rules relevant to its current task, keeping the effective instruction count low even as the total policy library grows.

### Implications for the Toolkit

The toolkit should implement a **three-tier scoping model**:

```
policies/
  universal.md          # Always injected (20-30 rules max)
  python.md             # Auto-attached for *.py files
  javascript.md         # Auto-attached for *.js/*.ts files
  testing.md            # Auto-attached for test files
  project.md            # Project-specific conventions
```

Each policy file includes frontmatter specifying scope:

```markdown
---
scope: auto-attach
globs: ["*.py", "*.pyi"]
---
# Python Conventions
- Use pathlib for all file path operations
- Type-hint all function signatures (parameters and return)
- Use dataclasses or Pydantic for structured data, not plain dicts
```

The injection mechanism assembles the relevant policy set per batch/task/session:
1. Always include `universal.md`.
2. Auto-attach policies matching the files in the current batch.
3. Count total rules. If >100, warn and suggest pruning.

**Confidence: High.** Multiple tools have converged on scoped policies independently.

---

## 5. Enforcement Spectrum

### Findings

Policies exist on an enforcement spectrum from advisory to blocking. The appropriate level depends on two axes: **cost of violation** and **detectability**.

| Enforcement Level | Mechanism | When to Use | Examples |
|-------------------|-----------|-------------|---------|
| **Hard gate (block)** | Quality gate, hookify rule, linter | Violation causes bugs, data loss, or security issues. Pattern is syntactically detectable with near-zero false positives. | Bare exceptions, secrets in code, force-push |
| **Soft injection (advisory)** | Prompt context via CLAUDE.md / AGENTS.md / policy files | Violation degrades quality but isn't catastrophic. Pattern is stylistic or contextual. | Naming conventions, import organization, docstring format, preferred libraries |
| **Post-hoc review (audit)** | Code review agent, entropy audit, manual review | Violation is subjective or requires broad context to evaluate. | Architecture decisions, API design quality, test coverage adequacy |

#### Criteria for choosing enforcement level

Adapted from the Open Policy Agent (OPA) model of separating policy logic from enforcement:

1. **Is it syntactically detectable with >95% precision?** Hard gate.
2. **Is it a clear positive convention that an LLM can follow?** Soft injection.
3. **Does it require understanding the full codebase context?** Post-hoc review.
4. **Is the cost of a false positive higher than the cost of a missed violation?** Lower the enforcement level.

#### What the toolkit already covers

| Tier | Current Coverage | Gap |
|------|-----------------|-----|
| Hard gate | lesson-check.sh (6 syntactic patterns), hookify (5 rules), ast-grep (5 patterns), test suite, test count monotonicity | Well-covered for anti-patterns |
| Soft injection | CLAUDE.md instructions, skill prompts, AGENTS.md per worktree | **No structured positive policy system** |
| Post-hoc review | lesson-scanner agent, entropy-audit.sh, code review skill | Partially covered |

### Implications for the Toolkit

The gap is entirely in the **soft injection** tier. The toolkit has excellent hard gates and reasonable post-hoc review, but no systematic way to inject positive coding conventions into agent context.

The proposed policy system fills exactly this gap:
- Policies are **soft-injected** into agent prompts (CLAUDE.md, AGENTS.md, or dedicated policy files).
- They complement hard gates (lessons) rather than replacing them.
- They can optionally **graduate to hard enforcement** if a policy violation causes enough bugs (policy -> lesson -> hookify rule).

**Confidence: High.** The three-tier model maps cleanly to the toolkit's existing architecture.

---

## 6. Existing Implementations: Competitive Analysis

### Claude Code (CLAUDE.md)

**Strengths:**
- Directory hierarchy (root, parent, child) enables natural scoping.
- `@import` syntax lets CLAUDE.md reference other files without duplicating content.
- `/init` command auto-generates starter CLAUDE.md from project analysis.
- Skills (`.claude/skills/`) provide on-demand policy loading without bloating every session.
- Hooks provide deterministic enforcement for must-happen rules.

**Weaknesses:**
- No glob-based auto-attachment (unlike Cursor's `.mdc`).
- No structured frontmatter -- all freeform markdown.
- No built-in mechanism to measure instruction compliance.
- Official guidance says to "ruthlessly prune" but provides no tools to identify stale rules.

**Key quote from Anthropic:** "If your CLAUDE.md is too long, Claude ignores half of it because important rules get lost in the noise."

### Cursor (.mdc rules)

**Strengths:**
- Four rule types (Always, Auto-Attach, Agent-Requested, Manual) provide fine-grained injection control.
- Glob-based attachment means agents see only relevant rules.
- YAML frontmatter enables machine-parseable metadata.
- `.cursor/rules/` directory keeps rules organized by topic.

**Weaknesses:**
- Proprietary format (`.mdc`) not supported by other tools.
- Legacy `.cursorrules` migration path is confusing.
- No enforcement mechanism -- purely advisory.
- Rule effectiveness is not measurable.

### GitHub Copilot

**Strengths:**
- Path-specific instructions (`.github/instructions/**/*.instructions.md` with `applyTo` globs) is an elegant scoping model.
- Committed to repo, shared with team via git.
- Instructions attached to both chat and inline suggestions.

**Weaknesses:**
- Limited to Copilot ecosystem.
- No enforcement -- purely advisory.
- Relatively new feature, limited community examples.

### Amazon Q Developer

**Strengths:**
- Rules explicitly designed for coding standards enforcement.
- Scans `.amazonq/rules/` on first interaction, evaluates per request.
- Supports language-specific style guidelines with concrete examples.

**Weaknesses:**
- AWS ecosystem lock-in.
- No scoping beyond project-level.
- Limited community sharing.

### Aider (CONVENTIONS.md)

**Strengths:**
- Simplest model: one markdown file, loaded as read-only context.
- Community conventions repository for sharing.
- Integrates with post-edit linting (errors sent back to LLM for fixing).

**Weaknesses:**
- No scoping -- entire file loaded every time.
- No frontmatter or metadata.
- Relies on the LLM to decide relevance.

### JetBrains Junie

**Strengths:**
- `.junie/guidelines.md` can be auto-generated by prompting Junie to explore the project.
- Community guidelines catalog (GitHub: JetBrains/junie-guidelines).

**Weaknesses:**
- Single file, no scoping.
- JetBrains ecosystem only.

### AGENTS.md (Cross-Tool Standard)

**Strengths:**
- Supported by 20+ tools (broadest compatibility).
- Directory hierarchy scoping (closest file wins).
- No required fields -- flexible structure.
- Linux Foundation stewardship ensures longevity.

**Weaknesses:**
- No frontmatter standard for glob patterns or rule types.
- No enforcement mechanism.
- Still early -- limited community policy libraries.

### ESLint Shareable Configs

**Strengths:**
- Best example of **policy distribution at scale**: npm packages with versioned configs.
- `eslint-config-airbnb` has 3M+ weekly downloads -- proof that shared conventions work.
- Extends/overrides model for layered policies.

**Weaknesses:**
- Deterministic enforcement only (no fuzzy style guidance).
- JavaScript/TypeScript ecosystem only.
- Not consumed by LLMs.

### Implications for the Toolkit

The toolkit should:
1. **Generate AGENTS.md** in worktrees (already done for plan metadata -- extend with policies).
2. **Support a `policies/` directory** with scoped markdown files.
3. **Inject policies into the prompt assembly pipeline** (`scripts/lib/prompt.sh` or equivalent) during headless execution.
4. **Adopt Cursor's glob-trigger model** for auto-attachment, implemented in the toolkit's own prompt assembly rather than relying on Cursor.
5. **Build a policy distribution model** inspired by ESLint shareable configs -- community policy packs as git repos or directories.

**Confidence: High.** Analysis based on official documentation from all listed tools.

---

## 7. Interaction with Existing Systems

### Findings

The toolkit currently has three enforcement layers:

| Layer | System | Timing | Nature |
|-------|--------|--------|--------|
| Pre-write | Hookify rules | Before file write | Behavioral enforcement (block/warn) |
| Post-batch | lesson-check.sh + quality-gate.sh | Between batches | Anti-pattern detection (block) |
| Post-implementation | lesson-scanner agent, entropy-audit.sh | At verification | Semantic analysis (advisory) |

Policies would add a fourth layer:

| Layer | System | Timing | Nature |
|-------|--------|--------|--------|
| **Pre-execution** | Policy injection | Before agent starts each batch | **Positive guidance (advisory)** |

### How policies interact with each system

**Policies and Lessons:**
- Complementary, not overlapping. Lessons are reactive (capture past failures). Policies are proactive (define desired behavior).
- Cross-reference: Each lesson's `positive_alternative` field generates a corresponding policy entry.
- Example: Lesson 0001 ("bare except swallowing") cross-references policy "Always catch specific exception types and log them."

**Policies and Hookify:**
- Non-overlapping enforcement targets. Hookify enforces behavioral rules (no force-push, no secrets). Policies guide stylistic conventions (naming, patterns, preferred libraries).
- Exception: If a policy is consistently violated despite soft injection, it may indicate the need for escalation to hookify (policy graduation).

**Policies and Quality Gates:**
- Quality gates verify after the fact. Policies guide before the fact.
- Quality gates can optionally check policy compliance by running a lightweight audit of generated code against active policies (post-hoc tier).
- New gate step: `policy-check.sh` -- a grep-based scanner for positive pattern presence (e.g., "all new Python functions have type hints").

**Policies and Skills:**
- Skills define HOW to execute stages. Policies define WHAT conventions to follow during execution.
- Skills reference policies: "Follow the policies in `policies/python.md` for all Python code in this task."
- Skills are rigid process templates. Policies are flexible convention sets.

**Policies and AGENTS.md:**
- AGENTS.md is already generated per worktree with plan metadata.
- Extend it to include relevant policies assembled from the `policies/` directory.
- This makes policies visible to non-Claude agents that read AGENTS.md.

### Implications for the Toolkit

The policy system slots cleanly into the existing architecture without duplicating any existing system:

```
Policy injection (pre-execution, positive, advisory)
     ↓
Agent executes batch
     ↓
Hookify (pre-write, behavioral, block/warn)
     ↓
lesson-check.sh (post-batch, anti-pattern, block)
     ↓
quality-gate.sh (post-batch, composite, block)
     ↓
policy-check.sh (post-batch, convention, advisory) [NEW]
     ↓
lesson-scanner (post-implementation, semantic, advisory)
```

**Confidence: High.** The mapping is clean and non-overlapping.

---

## 8. Policy Lifecycle

### Findings

Policies, like code, need a lifecycle: creation, testing, versioning, and retirement. Without this, stale or contradictory policies accumulate and degrade agent performance.

#### Creation

Based on patterns from ESLint shareable configs and the toolkit's lesson system:

1. **Discovery:** A team member identifies a recurring pattern that should be standardized (not a bug -- that's a lesson).
2. **Drafting:** Write the policy as a positive instruction with an optional code example.
3. **Testing:** Run the policy through at least one batch execution and verify the agent follows it.
4. **Review:** Peer review (or `/counter` adversarial review) to check for ambiguity, conflicts with existing policies, and enforceability.
5. **Merge:** Add to `policies/` directory.

#### Testing

Policies are harder to test than lessons (which have grep-detectable patterns). Testing approaches:

- **Behavioral test:** Run a controlled batch with and without the policy. Diff the output. Does the policy produce measurably different code?
- **Compliance audit:** After a batch, grep for evidence of policy compliance (e.g., all new functions have type hints).
- **Contradiction check:** Automated scan for policies that conflict with each other or with existing lessons.

#### Versioning

- Policies live in git alongside code. Changes are tracked via commits.
- Each policy file has a `last_reviewed` date in frontmatter.
- Policies not reviewed in 90 days get flagged by `entropy-audit.sh`.

#### Retirement

A policy should be retired when:
1. It has been superseded by a linter rule (deterministic enforcement > probabilistic).
2. The convention it enforces has become default LLM behavior (Claude already does it without being told).
3. It consistently produces false positives or conflicts with other policies.
4. The technology it targets is no longer used in the project.

**Retirement process:** Move to `policies/archived/` with a note explaining why. Never delete -- stale policies may become relevant again.

### Implications for the Toolkit

Add to `entropy-audit.sh`:
- Check for policies with `last_reviewed` > 90 days ago.
- Check for policies that reference files or patterns no longer in the codebase.
- Check for policy-lesson contradictions (negative lesson says "don't X" but no positive policy says "do Y instead").

Policy template:

```markdown
---
scope: auto-attach
globs: ["*.py"]
last_reviewed: 2026-02-22
source: team-convention  # or: lesson-derived, community, framework-default
---
# Python Error Handling

- Always catch specific exception types (ValueError, KeyError, ConnectionError), never bare `except:`
- Log the exception with `logger.exception()` before any fallback behavior
- Use `contextlib.suppress()` only when the suppression is intentional and documented with a comment

## Example
```python
# Correct
try:
    result = parse_config(path)
except (FileNotFoundError, json.JSONDecodeError) as e:
    logger.exception("Config parse failed for %s", path)
    result = DEFAULT_CONFIG
```
```

**Confidence: High** on the lifecycle model. **Medium** on the 90-day review cadence (arbitrary, needs calibration).

---

## 9. Measurability

### Findings

Measuring policy effectiveness is the weakest area across all tools studied. No tool provides built-in policy compliance metrics. The industry relies on:

1. **Task compliance rate:** How often the agent produces code that follows the policy. Measured via post-hoc audit of generated code. Industry recommendation: 80% automated evaluation + 20% expert review.

2. **Policy violation rate over time:** Track how often `policy-check.sh` flags violations. A declining trend indicates the policy is working. A flat trend indicates the agent is ignoring it.

3. **Policy-triggered lesson rate:** If a policy's subject area keeps generating new lessons, the policy isn't effective enough. The policy-to-lesson ratio should trend toward zero new lessons in covered areas.

4. **Before/after code quality metrics:** Run the same batch with and without policies. Measure: test pass rate, lint violations, code review findings, time to completion. This is the gold standard but expensive to run.

5. **Agent self-report:** Ask the agent to report which policies it consulted during execution. Low-cost signal, but unreliable (agents may hallucinate compliance).

#### What metrics matter most

From the DX Research "Measuring AI Code Assistants and Agents" framework:

| Metric | What It Measures | Cost to Collect |
|--------|-----------------|-----------------|
| Utilization | Is the policy being injected? | Low (log injection events) |
| Compliance | Does the output follow the policy? | Medium (grep/audit post-batch) |
| Impact | Does the policy improve quality outcomes? | High (A/B testing, longitudinal tracking) |

#### Practical approach for the toolkit

Given the toolkit's existing infrastructure:

1. **Log policy injection.** When `run-plan.sh` assembles a prompt, log which policies were injected. Stored in `logs/policy-injection.log`.
2. **Grep-audit compliance.** Add optional `compliance_check` field to policy frontmatter: a grep pattern that should appear in compliant code. `policy-check.sh` runs these after each batch.
3. **Track violations in failure-patterns.json.** Extend the existing failure pattern learning to include policy violations. If a policy-related issue recurs, escalate to lesson.
4. **Monthly review.** During `/reflect`, review policy compliance logs. Retire ineffective policies.

### Implications for the Toolkit

Build measurability into the policy system from day one, but keep it lightweight:

```
Policy injection → log which policies applied
     ↓
Batch execution
     ↓
policy-check.sh → grep for compliance patterns
     ↓
Log results to logs/policy-compliance.json
     ↓
Monthly: /reflect reviews compliance trends
     ↓
Decision: keep / revise / retire / escalate to lesson
```

**Confidence: Medium.** No tool has solved this well. The proposed approach is practical but unvalidated.

---

## 10. Community Policies

### Findings

The lesson system already supports community contribution (`/submit-lesson` -> PR). Can policies be shared similarly?

#### Transferability comparison

| Characteristic | Anti-Pattern Lessons | Positive Policies |
|---------------|---------------------|-------------------|
| Transferability | High -- bugs are universal | Medium -- conventions are context-dependent |
| Example | "Bare except swallows errors" (true everywhere) | "Use Pydantic for API schemas" (only if you use Pydantic) |
| Specificity | Narrow (one pattern per lesson) | Broad (multiple conventions per policy) |
| Overlap risk | Low (bugs are distinct) | High (my "clean code" != your "clean code") |
| Distribution model | Single files, additive | Sets/packs, composable |

#### Community policy distribution models

1. **ESLint model (npm packages):** Versioned, named configs. `eslint-config-airbnb` sets a standard that millions use. Proven at scale. Requires a package manager.

2. **Cursor community model (awesome-cursorrules):** Git repos with categorized rule files. Users copy what they need. No versioning, no dependency management. Simple but fragile.

3. **Junie model (guidelines catalog):** Official repo with technology-specific guideline files. Community contributes via PR. Curated but slow to update.

4. **Aider model (conventions repo):** `github.com/Aider-AI/conventions` -- shared conventions files. Simple directory of markdown files.

#### Proposed model for the toolkit

**Policy packs** -- curated sets of policies for specific technology stacks, distributed as directories:

```
community-policies/
  python-standard/
    error-handling.md
    type-hints.md
    testing.md
    imports.md
  typescript-standard/
    error-handling.md
    types.md
    testing.md
  fastapi/
    api-conventions.md
    pydantic-models.md
  react/
    component-patterns.md
    state-management.md
```

Users install a pack:

```bash
# Copy a policy pack into your project
cp -r community-policies/python-standard/ policies/

# Or symlink for auto-updates
ln -s path/to/community-policies/python-standard/ policies/python
```

Each pack has a `manifest.md` describing what it covers, dependencies, and compatibility.

### Implications for the Toolkit

Community policies are viable but require more curation than lessons:
- **Lessons are additive** (each lesson catches one specific bug -- no conflicts).
- **Policies can conflict** ("use dataclasses" vs. "use Pydantic" vs. "use TypedDict").
- **Solution:** Policy packs declare what they cover. Users choose one pack per domain. Conflict detection in `entropy-audit.sh`.

**Confidence: Medium.** The ESLint model proves community standards work at scale. Whether this translates to LLM-consumed natural language policies is unproven.

---

## Policy System Design Recommendation

### Architecture

```
policies/                           # Policy directory (per-project)
  universal.md                      # Always injected (cross-language)
  python.md                         # Auto-attached for *.py
  javascript.md                     # Auto-attached for *.js/*.ts
  testing.md                        # Auto-attached for test files
  project.md                        # Project-specific conventions
  archived/                         # Retired policies (never delete)

scripts/
  policy-check.sh                   # Post-batch compliance audit [NEW]
  lib/policy-inject.sh              # Policy assembly for prompt injection [NEW]
```

### Policy File Format

```markdown
---
scope: auto-attach          # always | auto-attach | on-demand
globs: ["*.py", "*.pyi"]   # file patterns (for auto-attach scope)
last_reviewed: 2026-02-22
source: team-convention     # team-convention | lesson-derived | community | framework
related_lessons: [1, 7]    # cross-reference to lesson IDs
---
# Python Error Handling

- Always catch specific exception types, never bare `except:`
- Log exceptions with `logger.exception()` before any fallback
- Use `contextlib.suppress()` only with an explanatory comment

## Example

```python
try:
    result = parse_config(path)
except (FileNotFoundError, json.JSONDecodeError) as e:
    logger.exception("Config parse failed for %s", path)
    result = DEFAULT_CONFIG
```

## Compliance Check

```bash
# Verify no bare except in changed files
! grep -n 'except:' "$FILE" || echo "POLICY VIOLATION: Use specific exception types"
```
```

### Injection Pipeline

During headless execution (`run-plan.sh`), before each batch:

1. Read `policies/universal.md` (always).
2. Identify file types in the current batch.
3. Auto-attach matching policies based on globs.
4. Count total instruction lines across all injected policies.
5. If >100 instructions, warn and truncate least-relevant (on-demand scope first).
6. Append assembled policies to the batch prompt (after task description, before CLAUDE.md general instructions).
7. Log injected policies to `logs/policy-injection.log`.

For interactive sessions, policies are referenced via CLAUDE.md `@import`:

```markdown
# CLAUDE.md
@policies/universal.md
@policies/python.md
```

### Enforcement Tiers

| Tier | Mechanism | Timing | Action |
|------|-----------|--------|--------|
| **Guidance** | Prompt injection | Pre-execution | Advisory -- agent sees policies as instructions |
| **Audit** | policy-check.sh | Post-batch | Warning -- logs violations, does not block |
| **Escalation** | Manual review + lesson creation | On repeated violation | Policy becomes lesson, soft becomes hard |

### Integration Points

| Existing System | Integration |
|----------------|-------------|
| `run-plan.sh` | Call `lib/policy-inject.sh` to assemble policies per batch |
| `quality-gate.sh` | Add optional `policy-check.sh` step (advisory, non-blocking) |
| AGENTS.md generation | Include assembled policies in generated AGENTS.md |
| `entropy-audit.sh` | Add policy staleness check (last_reviewed > 90 days) |
| Lesson files | Add optional `positive_alternative` field -> auto-generates policy |
| `/submit-lesson` | Prompt for positive alternative when submitting a lesson |

### Policy Lifecycle

```
Convention identified
     ↓
Draft policy (positive framing, code example, compliance check)
     ↓
Test: run batch with policy, verify compliance
     ↓
Review: /counter or peer review for ambiguity/conflicts
     ↓
Merge to policies/ directory
     ↓
Monitor: policy-check.sh logs compliance rate
     ↓
Monthly /reflect: review compliance trends
     ↓
Decision: keep | revise | retire | escalate to lesson+hookify
```

### Implementation Plan (Suggested Batches)

| Batch | Scope | Deliverables |
|-------|-------|-------------|
| 1 | Foundation | `policies/` directory, policy file format, `universal.md` with 10-15 starter rules |
| 2 | Injection | `lib/policy-inject.sh`, integration with `run-plan.sh` prompt assembly |
| 3 | Audit | `policy-check.sh`, integration with `quality-gate.sh` (advisory mode) |
| 4 | Lesson bridge | `positive_alternative` field in lesson template, auto-generation of policy entries from lessons |
| 5 | AGENTS.md | Extend AGENTS.md generation to include assembled policies |
| 6 | Measurability | `logs/policy-compliance.json`, compliance trend reporting |
| 7 | Community | Policy pack format, `manifest.md`, conflict detection in `entropy-audit.sh` |

### Starter Policies (Batch 1)

Based on the toolkit's existing lessons and common cross-project conventions:

**universal.md:**
1. Handle errors explicitly -- catch specific exception types and log before fallback
2. Include type annotations on all function signatures
3. Write docstrings for public functions and classes
4. Use descriptive variable names -- no single-letter names except loop indices
5. Keep functions under 50 lines -- extract helpers when they grow
6. Return early for error conditions -- happy path last
7. Use constants for magic numbers and strings
8. Commit after each logical unit of work with a descriptive message
9. Write the test first, then the implementation
10. When importing, prefer explicit imports over wildcards

**python.md:**
1. Use pathlib for all file path operations
2. Use f-strings for string formatting
3. Use dataclasses or Pydantic for structured data, not plain dicts
4. Use `contextlib.suppress()` for intentional exception suppression, with a comment
5. Use `logging.exception()` in except blocks to capture tracebacks

**testing.md:**
1. Use pytest fixtures over setUp/tearDown methods
2. Name tests descriptively: `test_<function>_<scenario>_<expected_result>`
3. Assert specific values, not truthiness
4. Use `pytest.raises()` for expected exceptions, not try/except in tests
5. One logical assertion per test function

---

## Sources

### Official Documentation
- [Anthropic: Best Practices for Claude Code](https://code.claude.com/docs/en/best-practices)
- [Anthropic: Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
- [GitHub: Adding Repository Custom Instructions for Copilot](https://docs.github.com/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot)
- [Amazon Q Developer: Project Rules](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line-project-rules.html)
- [Amazon Q Developer: Creating Project Rules](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/context-project-rules.html)
- [Aider: Specifying Coding Conventions](https://aider.chat/docs/usage/conventions.html)
- [ESLint: Shareable Configs](https://eslint.org/docs/latest/extend/shareable-configs)
- [AGENTS.md Specification](https://agents.md/)
- [AGENTS.md GitHub Repository](https://github.com/agentsmd/agents.md)
- [OpenAI Codex: Custom Instructions with AGENTS.md](https://developers.openai.com/codex/guides/agents-md/)

### Research and Analysis
- [The Pink Elephant Problem: Why "Don't Do That" Fails with LLMs](https://eval.16x.engineer/blog/the-pink-elephant-negative-instructions-llms-effectiveness-analysis)
- [Why Positive Prompts Outperform Negative Ones with LLMs](https://gadlet.com/posts/negative-prompting/)
- [Understanding the Relationship Between LLMs and Negation (Swimm)](https://swimm.io/blog/understanding-llms-and-negation)
- [Prompt Length vs. Context Window: The Real Limits of LLM Performance (HackerNoon)](https://hackernoon.com/prompt-length-vs-context-window-the-real-limits-of-llm-performance)
- [Why Long System Prompts Hurt Context Windows](https://medium.com/data-science-collective/why-long-system-prompts-hurt-context-windows-and-how-to-fix-it-7a3696e1cdf9)
- [DX Research: Measuring AI Code Assistants and Agents](https://getdx.com/research/measuring-ai-code-assistants-and-agents/)
- [Three Metrics for Measuring the Impact of AI on Code Quality](https://getdx.com/blog/3-metrics-for-measuring-the-impact-of-ai-on-code-quality/)

### Practitioner Guides
- [Writing a Good CLAUDE.md (HumanLayer)](https://www.humanlayer.dev/blog/writing-a-good-claude-md)
- [Creating the Perfect CLAUDE.md (Dometrain)](https://dometrain.com/blog/creating-the-perfect-claudemd-for-claude-code/)
- [How to Write Great Cursor Rules (Trigger.dev)](https://trigger.dev/blog/cursor-rules)
- [Top Cursor Rules for Coding Agents (PromptHub)](https://www.prompthub.us/blog/top-cursor-rules-for-coding-agents)
- [Windsurf AI Rules Guide](https://uibakery.io/blog/windsurf-ai-rules)
- [Improve Your AI Code Output with AGENTS.md (Builder.io)](https://www.builder.io/blog/agents-md)
- [A Complete Guide to AGENTS.md (AI Hero)](https://www.aihero.dev/a-complete-guide-to-agents-md)
- [Coding Guidelines for Your AI Agents (JetBrains)](https://blog.jetbrains.com/idea/2025/05/coding-guidelines-for-your-ai-agents/)
- [JetBrains Junie Guidelines Catalog](https://github.com/JetBrains/junie-guidelines)
- [Mastering Amazon Q Developer with Rules (AWS Blog)](https://aws.amazon.com/blogs/devops/mastering-amazon-q-developer-with-rules/)

### Community Resources
- [awesome-cursorrules (GitHub)](https://github.com/PatrickJS/awesome-cursorrules)
- [awesome-cursor-rules-mdc (GitHub)](https://github.com/sanjeed5/awesome-cursor-rules-mdc)
- [Aider Conventions Repository](https://github.com/Aider-AI/conventions)
- [awesome-claude-code (GitHub)](https://github.com/hesreallyhim/awesome-claude-code)
- [dotcursorrules.com](https://dotcursorrules.com/)

### Policy as Code
- [Open Policy Agent (OPA) Documentation](https://www.openpolicyagent.org/docs/latest/)
- [Policy as Code: Introduction to Open Policy Agent (GitGuardian)](https://blog.gitguardian.com/what-is-policy-as-code-an-introduction-to-open-policy-agent/)

### Academic
- [LLMBar: Evaluating LLMs at Evaluating Instruction Following (ICLR 2024)](https://github.com/princeton-nlp/LLMBar)
- [Source Framing Triggers Systematic Bias in LLMs (Science Advances, 2025)](https://www.science.org/doi/10.1126/sciadv.adz2924)
