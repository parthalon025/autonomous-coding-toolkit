# Research: Codebase Auditing and Refactoring with Autonomous AI Agents

> **Date:** 2026-02-22
> **Status:** Research complete
> **Method:** Web research + academic literature + tool analysis + existing toolkit review
> **Confidence:** High on audit pipeline design, medium on migration patterns, high on metrics

## Executive Summary

The autonomous-coding-toolkit is optimized for greenfield development: brainstorm, plan, execute new features. But the overwhelming majority of professional software work is improving existing code — auditing for issues, refactoring legacy systems, improving test coverage, paying down tech debt, and migrating frameworks. This research makes the case that **"improve existing code" is as important a use case as "build new features"** and proposes a concrete pipeline for it.

**Key findings:**

1. **AI agents are already effective at localized refactoring** — extract method, dead code removal, naming improvements, magic number elimination — but struggle with cross-module architectural changes (confidence: high, ICSE 2025 IDE workshop evidence).
2. **Hotspot analysis (CodeScene's approach) is the highest-leverage prioritization strategy** — intersecting code complexity with change frequency identifies the 5-10% of files responsible for most defects and delivery slowdowns (confidence: high, behavioral code analysis research).
3. **Characterization testing is the safety net** — before any AI refactoring, capture current behavior as tests. Michael Feathers' principle: "legacy code is code without tests" (confidence: high, established practice).
4. **The strangler fig pattern maps naturally to AI agent work** — incremental replacement with a routing layer is safer than wholesale rewrite, and AI agents can execute the incremental steps autonomously (confidence: high).
5. **An audit-first pipeline is the missing stage** — the toolkit needs a `discover → assess → prioritize → plan → execute → measure` pipeline that precedes the existing brainstorm → plan → execute chain (confidence: high).
6. **Continuous improvement via scheduled agents is production-ready** — Continuous Claude and similar approaches demonstrate overnight autonomous PR generation for incremental code improvement (confidence: medium, early but proven pattern).

**Proposed new stages for the toolkit:**

```
[NEW] /audit → discover → assess → prioritize
[EXISTING] brainstorm → plan → execute → verify → finish
[NEW] /measure → track improvement over time
```

---

## 1. Audit-First Workflow: How AI Agents Should Approach Existing Code

### Findings

AI agents exploring unfamiliar codebases follow a consistent high-to-low resolution pattern, supported by both SWE-bench agent analysis and the ArchAgent framework (arXiv 2601.13007):

**Optimal exploration sequence:**

1. **Structural survey** (seconds) — file tree, directory layout, language detection, build system identification
2. **Documentation scan** (seconds) — README, CLAUDE.md, ARCHITECTURE.md, CONTRIBUTING.md, inline doc comments
3. **Dependency graph** (seconds-minutes) — `package.json`, `requirements.txt`, `pyproject.toml`, import analysis
4. **Test suite assessment** (seconds) — test framework detection, test count, coverage report if available, run baseline
5. **Git history analysis** (minutes) — recent commits, change frequency per file, contributor patterns, hotspot identification
6. **Architecture recovery** (minutes) — call graph extraction, module boundaries, entry points, data flow paths
7. **Tech debt inventory** (minutes) — code smells, complexity metrics, dead code, naming violations, pattern inconsistencies

SWE-Agent's approach deliberately shows only small amounts of code at a time during search, which works for targeted bug fixing but is insufficient for holistic codebase understanding. The OpenHands project discussion (issue #2363) proposes an "OmniscientAgent" — a head agent with a broader codebase view — suggesting the community recognizes this gap.

**Key insight from SWE-EVO benchmark:** Long-horizon software evolution tasks (averaging 21 files modified per task, 874 tests per instance) show dramatic performance drops — from 75% on SWE-bench Verified to 23% on SWE-bench Pro. This means current AI agents can fix isolated bugs but struggle with systemic improvements. A structured audit pipeline that breaks systemic improvement into targeted, isolated tasks is essential.

### Evidence

- SWE-bench Pro: Best models (GPT-5, Claude Opus 4.1) score only ~23% on multi-file evolution tasks vs. 75% on isolated fixes ([SWE-bench Pro, Scale AI](https://scale.com/leaderboard/swe_bench_pro_public))
- ArchAgent combines static analysis + adaptive code segmentation + LLM synthesis for architecture recovery ([arXiv 2601.13007](https://arxiv.org/html/2601.13007))
- OpenHands exploration relies on shell commands, file reading, and web browsing — no structured audit methodology ([OpenHands](https://github.com/OpenHands/OpenHands))

### Implications for the Toolkit

The toolkit needs a `/audit` command that executes the 7-step exploration sequence above, producing a structured audit report. This report then feeds into the existing brainstorm → plan → execute pipeline. The audit replaces brainstorming's "explore project context" step with a rigorous, repeatable methodology.

---

## 2. Codebase Comprehension: Building Mental Models

### Findings

AI agents build codebase understanding through several complementary techniques:

**Static analysis techniques:**
- **AST parsing** — extract function signatures, class hierarchies, import relationships. Fast, deterministic, language-specific.
- **Call graph extraction** — map which functions call which. Critical for understanding impact radius of changes.
- **Dependency mapping** — external dependencies (packages) and internal dependencies (module imports). Reveals coupling.
- **Architecture recovery** — ArchAgent's approach: File Summarizer → Repo Manager (chunking) → Readme Generator → Architect (Mermaid diagrams). Combines static analysis with LLM-powered synthesis.

**LLM-specific techniques:**
- **Hierarchical summarization** — summarize files → summarize modules → summarize system. Fits large codebases into context windows.
- **Intent-aware interaction** — CodeMap system provides "dynamic information extraction and representation aligned with human cognitive flow" ([arXiv 2504.04553](https://arxiv.org/html/2504.04553))
- **Cross-file relationship indexing** — ArchAgent's File Summarizer performs code search and reference indexing to establish cross-file relationships before summarization.

**Practical approach for the toolkit:**

```
Phase 1: Deterministic (fast, no LLM cost)
  - File tree + language detection
  - Dependency parsing (package.json, requirements.txt, etc.)
  - Import graph (grep/AST-based)
  - Test framework detection + baseline run
  - Git log analysis (hotspots, churn, contributors)

Phase 2: LLM-assisted (slower, higher quality)
  - Hierarchical file summarization
  - Architecture diagram generation (Mermaid)
  - Business logic identification
  - Pattern and convention extraction
  - Anti-pattern detection
```

### Evidence

- ArchAgent ablation study confirms dependency context improves architecture accuracy ([arXiv 2601.13007](https://arxiv.org/abs/2601.13007))
- LoCoBench-Agent benchmark evaluates LLM agents on interactive code comprehension tasks ([arXiv 2511.13998](https://arxiv.org/pdf/2511.13998))
- Hybrid reverse engineering combining static/behavioral views with LLM-guided interaction ([arXiv 2511.05165](https://arxiv.org/html/2511.05165v1))

### Implications for the Toolkit

Create a `codebase-profile.sh` script that runs Phase 1 deterministically and produces a JSON profile. This profile becomes the context input for Phase 2 LLM analysis and for all subsequent audit stages. The profile is cached and invalidated on significant git changes.

---

## 3. Refactoring Strategies: What Works with AI Agents

### Findings

Research from ICSE 2025 (IDE workshop) and practical experience establish a clear taxonomy of AI refactoring effectiveness:

**AI excels at (safe, high confidence):**
- Extract method / extract function
- Magic number elimination (replace with named constants)
- Long statement splitting
- Dead code removal
- Naming improvements (variable, function, class)
- Import cleanup and organization
- Automated idiomatization (e.g., Python list comprehensions)
- Simplify conditional logic (flatten nested if/else)
- Remove code duplication (within single file)

**AI is mediocre at (requires guardrails):**
- Move to module (cross-file refactoring)
- Replace inheritance with composition
- Interface extraction
- Dependency injection introduction
- Cross-file duplication removal

**AI struggles with (high risk, needs human review):**
- Architectural refactoring (e.g., monolith to modules)
- Multi-module refactoring requiring domain knowledge
- Performance optimization requiring profiling data
- Concurrency pattern changes
- Database schema migrations

**McKinsey estimates:** Generative AI can reduce refactoring time by 20-30% and code writing time by up to 45%. Static checks filter LLM hallucinations, and iterative re-prompting on compile/test errors raises functional correctness by 40-65 percentage points over naive LLM output.

### Evidence

- ICSE 2025 IDE workshop: "LLMs consistently outperform or match developers on systematic, localized refactorings... they underperform on context-dependent, architectural, or multi-module refactorings" ([ICSE 2025](https://conf.researchr.org/details/icse-2025/ide-2025-papers/12/LLM-Driven-Code-Refactoring-Opportunities-and-Limitations))
- Augment Code practical guide: "Begin on a low-risk module, prompt an LLM to map dependencies and suggest refactors, then run new code through test-suite and code-review gates" ([Augment Code](https://www.augmentcode.com/learn/ai-powered-legacy-code-refactoring))
- IBM: AI refactoring uses "intelligent risk assessment to predict failure cascades before they happen" ([IBM](https://www.ibm.com/think/topics/ai-code-refactoring))

### Implications for the Toolkit

The toolkit should classify refactoring tasks by risk level and route them accordingly:

| Risk Level | Examples | Execution Mode | Human Review |
|-----------|----------|----------------|-------------|
| Low | Naming, dead code, imports | Headless (Mode C) | Post-merge |
| Medium | Extract method, simplify conditionals | Ralph loop with quality gates | PR review |
| High | Architecture, cross-module | Competitive dual-track (Mode B) | Before merge |

The batch-type classification system (`classify_batch_type()`) already exists in `run-plan.sh` — extend it with a refactoring risk classifier.

---

## 4. Tech Debt Prioritization: What to Fix First

### Findings

The most effective prioritization strategy is **hotspot analysis** — intersecting code complexity with change frequency — pioneered by CodeScene and validated by behavioral code analysis research.

**CodeScene's approach:**
- **Code Health metric:** Aggregated score from 25+ factors, scaled 1 (severe issues) to 10 (healthy). Research shows unhealthy code has **15x more defects**, **2x slower development**, and **10x more delivery uncertainty**.
- **Hotspot = complexity + churn:** Files that are both complex AND frequently changed are the highest-priority targets. A complex file that nobody touches is low priority. A simple file that changes often is already fine.
- **Behavioral analysis:** Combines code quality with team patterns — knowledge silos, developer fragmentation, coordination problems.

**Prioritization framework for AI agents:**

```
Priority = Impact × Frequency × Feasibility

Impact:     How much does this issue slow down development?
            (defect rate, review time, build failures)

Frequency:  How often does this code change?
            (git log --oneline --since="6 months" -- <file> | wc -l)

Feasibility: Can an AI agent safely fix this?
             (Low risk refactoring? Tests exist? Clear scope?)
```

**Concrete prioritization order:**
1. **Hotspots with tests** — complex, frequently-changed files that already have test coverage. Safest to refactor.
2. **Hotspots without tests** — same files but need characterization tests first. Higher effort, same priority.
3. **Dead code** — unused imports, unreachable functions, commented-out blocks. Zero-risk removal.
4. **Naming violations** — convention drift that impairs readability. Low risk, high readability impact.
5. **Code duplication** — within-file first, then within-module, then cross-module.
6. **Dependency cleanup** — unused dependencies, outdated versions with security patches.
7. **Documentation drift** — stale references, outdated examples, missing docs for public APIs.

### Evidence

- CodeScene research: "unhealthy code has 15 times more defects, 2x slower development, and 10 times more delivery uncertainty" ([CodeScene](https://codescene.com/product/behavioral-code-analysis))
- CodeScene's Code Health metric is built on 25+ research-backed factors ([CodeScene Docs](https://docs.enterprise.codescene.io/versions/7.2.0/guides/technical/hotspots.html))
- NASA Software Assurance: "most effective evaluation is a combination of size and cyclomatic complexity" ([Wikipedia - Cyclomatic Complexity](https://en.wikipedia.org/wiki/Cyclomatic_complexity))

### Implications for the Toolkit

Create a `hotspot-analysis.sh` script that:
1. Runs `git log --format='%H' --since='6 months' -- <file> | wc -l` for change frequency
2. Runs complexity analysis (radon for Python, eslint-plugin-complexity for JS)
3. Cross-references with test coverage data
4. Produces a ranked list of files to improve

This replaces the current entropy-audit's flat check approach with a prioritized, evidence-based ranking.

---

## 5. Migration Patterns: Framework and API Upgrades

### Findings

The **strangler fig pattern** is the dominant strategy for incremental migration, and it maps naturally to AI agent capabilities:

**Strangler fig applied to AI agents:**
1. **Identify boundary** — find the interface between old and new (API layer, routing layer, module boundary)
2. **Build routing facade** — create a proxy that dispatches to old or new implementation
3. **Migrate one endpoint/module at a time** — each migration is an isolated, testable unit of work
4. **Verify parity** — run both old and new in parallel, compare outputs
5. **Retire old code** — once all traffic routes to new, remove legacy

**Why this works for AI agents:**
- Each migration step is small enough for a single context window
- Each step is independently verifiable (tests, output comparison)
- Rollback is trivial (change routing)
- No "big bang" rewrite risk

**Codemod tools:**
- **jscodeshift** (JavaScript) — AST-based transform scripts
- **ast-grep** (multi-language) — structural search and replace
- **libcst** (Python) — concrete syntax tree transforms
- **Rector** (PHP) — automated refactoring and upgrades

**AI + codemods:** AI agents can generate codemods from examples. Given "before" and "after" code for a few cases, an LLM can generate the transformation rule. This is more reliable than having the AI transform each file individually.

### Evidence

- Microsoft Azure Architecture Center: strangler fig is the recommended pattern for incremental modernization ([Azure Docs](https://learn.microsoft.com/en-us/azure/architecture/patterns/strangler-fig))
- AWS Prescriptive Guidance endorses the same pattern ([AWS Docs](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/strangler-fig.html))
- vFunction's automated AI platform integrates with strangler fig for Java monolith decomposition ([vFunction](https://vfunction.com/blog/strangler-architecture-pattern-for-modernization/))

### Implications for the Toolkit

Add a `migration` batch type to the batch-type classifier. Migration batches get:
- Parity verification gates (old output == new output)
- Rollback verification (can we switch back?)
- Higher retry budget (migrations are flaky)
- Parallel comparison mode (run old and new, diff outputs)

---

## 6. Test Coverage Improvement: Strategy for Untested Code

### Findings

The debate between "outside-in" (integration first) and "inside-out" (unit first) has a nuanced answer for AI agents working on legacy code:

**Michael Feathers' recommendation (Working Effectively with Legacy Code):**
> Start with characterization tests that capture current behavior, then use those as a safety net for refactoring. Don't try to achieve the standard test pyramid first — that requires too many unsafe refactorings.

**Recommended sequence for AI agents:**

1. **Characterization tests first** (golden master) — capture current behavior of critical paths. These are NOT correctness assertions — they're behavior preservation assertions. "Given input X, the system currently produces output Y. If that changes, we want to know."

2. **Integration tests for boundaries** — test the interfaces between modules. These catch the most bugs per line of test code because defects cluster at integration points.

3. **Unit tests for hotspots** — once characterization tests provide a safety net, add unit tests to the files identified by hotspot analysis. Focus on the 5-10% of code that changes most.

4. **Coverage-guided expansion** — use coverage reports to identify untested branches in high-churn files. AI can generate tests for specific uncovered branches efficiently.

**AI-specific considerations:**
- AI-generated tests need human review for relevance — AI may generate tests that pass but don't test meaningful behavior
- AI excels at generating tests from function signatures and docstrings
- AI is poor at generating tests that require complex setup or domain knowledge
- Coverage tools (coverage.py, Istanbul.js, Jest) should feed back into the prioritization loop

### Evidence

- Michael Feathers defines legacy code as "code without tests" — the solution is characterization tests before refactoring ([Working Effectively with Legacy Code](https://bssw.io/items/working-effectively-with-legacy-code))
- Golden master testing is "the fastest way to cover Legacy Code with meaningful, useful tests" ([The Code Whisperer](https://blog.thecodewhisperer.com/permalink/surviving-legacy-code-with-golden-master-and-sampling))
- Qodo: "In legacy codebases with poorly structured or untestable code, attempting to retrofit unit tests may be impractical" — focus on making code testable first ([Qodo](https://www.qodo.ai/blog/unit-testing-vs-integration-testing-ais-role-in-redefining-software-quality/))

### Implications for the Toolkit

Add a `/improve-coverage` command that:
1. Runs coverage analysis to identify gaps
2. Cross-references with hotspot data (cover hot files first)
3. Generates characterization tests for uncovered critical paths
4. Generates unit tests for uncovered branches in hotspot files
5. Uses quality gates to verify tests actually test meaningful behavior (not just asserting `True`)

---

## 7. Safe Refactoring Guardrails: Preventing Regressions

### Findings

The safety stack for AI refactoring has four layers:

**Layer 1: Characterization tests (pre-refactoring)**
- Capture current behavior before changes
- Golden master / approval tests for complex outputs
- Snapshot testing for serializable state

**Layer 2: Static analysis gates (during refactoring)**
- Type checking (mypy, TypeScript strict mode)
- AST-based pattern enforcement (ast-grep, Semgrep rules)
- Import validation (no new circular dependencies)
- The toolkit's existing lesson-check.sh fits here

**Layer 3: Test suite execution (after each change)**
- Full test suite must pass after every refactoring step
- Test count monotonicity (toolkit's existing enforcement)
- Coverage must not decrease
- Performance benchmarks must not regress

**Layer 4: Behavioral verification (before merge)**
- End-to-end smoke tests
- Output comparison (old vs. new for same inputs)
- Review by a separate AI agent (toolkit's existing code review skill)
- Horizontal + vertical pipeline testing (toolkit's existing /verify)

**Critical insight:** Iterative re-prompting on compile/test errors raises functional correctness by 40-65 percentage points. The toolkit's retry-with-escalating-context mechanism already implements this pattern. The existing quality gate pipeline (lesson-check → test suite → memory → test count regression → git clean) provides Layers 2-3. Layer 1 (characterization tests) is the gap.

### Evidence

- ICSE 2025: "iterative re-prompting on compile/test errors raises functional correctness over naive LLM output by 40–65 percentage points" ([ICSE 2025 IDE](https://seal-queensu.github.io/publications/pdf/IDE-Jonathan-2025.pdf))
- Characterization tests are the "fastest way to cover Legacy Code" ([Golden Master Testing](https://www.fabrizioduroni.it/blog/post/2018/03/20/golden-master-test-characterization-test-legacy-code))
- The toolkit's quality gate pipeline already implements Layers 2-3

### Implications for the Toolkit

Add a `characterize` pre-step before any refactoring batch. The characterize step:
1. Identifies functions/classes being modified
2. Generates characterization tests capturing current behavior
3. Runs them to establish baseline
4. Adds them to the test suite
5. Only then proceeds with refactoring

This can be implemented as a new `--pre-step characterize` flag on `run-plan.sh`.

---

## 8. Existing Tools and Approaches

### Findings

The landscape of AI-assisted codebase improvement tools as of early 2026:

| Tool | Focus | Approach | Strengths | Limitations |
|------|-------|----------|-----------|------------|
| **SWE-agent** | Bug fixing | Agent framework for SWE-bench tasks | Structured tool use, file navigation | Isolated fixes, not systemic improvement |
| **OpenHands** | General development | Open-source autonomous agent | Shell + browser + file manipulation | No structured audit methodology |
| **CodeScene** | Tech debt analysis | Behavioral code analysis | Hotspot analysis, Code Health metric, 25+ factors | Commercial, not agent-integrated |
| **SonarQube** | Code quality | Static analysis, 30+ languages | Quality gates, dashboards, CI/CD integration | Rule-based, not AI-powered analysis |
| **Semgrep** | Security + patterns | AST-based pattern matching, 20K-100K loc/sec | Custom rules look like source code, blazing fast | Pattern-only, no behavioral analysis |
| **Sourcery** | Python refactoring | Automated transforms | Pythonic idioms, real-time suggestions | Python only, single-file scope |
| **DCE-LLM** | Dead code elimination | CodeBERT + attribution-based line selection | 94% F1 on dead code detection, beats GPT-4o by 30% | Research prototype, not production tool |
| **Continuous Claude** | Automated PRs | Continuous loop + GitHub Actions | Overnight autonomous improvement, self-learning | Requires CI/CD setup, nascent tooling |
| **Knip** | Dead code (TS/JS) | Mark-and-sweep algorithm | Finds unused deps, exports, types | TypeScript/JavaScript only |
| **Meta's SCARF** | Dead code at scale | Dependency graph + auto-delete PRs | Production-proven at Meta scale | Internal tool, not publicly available |

**Key gap:** No tool combines hotspot-based prioritization with AI agent execution for autonomous codebase improvement. CodeScene identifies what to fix; AI agents can execute the fixes; but no pipeline connects the two. This is the toolkit's opportunity.

### Evidence

- CodeScene's MCP server creates "a continuous feedback loop for AI agents, with deterministic, real-time quality checks" ([CodeScene](https://codescene.com/))
- DCE-LLM achieves 94% F1 scores, surpassing GPT-4o by 30% on dead code detection ([ACL 2025](https://aclanthology.org/2025.naacl-long.501/))
- Semgrep scans at 20K-100K loc/sec per rule vs. SonarQube's 0.4K loc/sec ([Semgrep Docs](https://semgrep.dev/docs/faq/comparisons/sonarqube))
- Continuous Claude enables overnight autonomous PR generation ([Anand Chowdhary](https://anandchowdhary.com/open-source/2025/continuous-claude))

### Implications for the Toolkit

Integrate with existing tools rather than rebuilding:
- Use Semgrep rules for pattern enforcement (extend lesson-check.sh or add as optional gate)
- Use radon/eslint for complexity metrics (input to hotspot analysis)
- Use coverage.py/Istanbul.js for coverage data (input to test prioritization)
- Generate CodeScene-compatible output format for teams already using it

---

## 9. Incremental Improvement vs. Rewrite

### Findings

Joel Spolsky's 2000 assertion that "you should never rewrite" remains largely valid, but with important nuances:

**When incremental refactoring wins (most cases):**
- Preserves embedded domain knowledge ("old code is not ugly because it's old — it has bug fixes encoded in it")
- Maintains production capability during improvement
- Each step is individually verifiable
- Risk is bounded per change

**When rewrite might be justified:**
- Architecture or schema are severely misaligned with requirements AND no clear migration path exists
- Tech stack is limiting contributors (e.g., nobody writes that language anymore)
- Security architecture is fundamentally broken (can't be patched)
- The codebase is small enough that rewrite risk is bounded

**How AI changes the calculus:**
- AI dramatically reduces the cost of incremental refactoring (the main argument against it was "too slow")
- AI also reduces the cost of rewrites (but doesn't reduce the RISK)
- The strongest argument against rewrites — losing embedded knowledge — is NOT addressed by AI
- AI agents working on incremental refactoring benefit from existing tests; rewrites start from zero

**Recommendation:** AI makes the "never rewrite" heuristic STRONGER, not weaker. Incremental refactoring was always the safer choice; AI makes it faster, removing the main practical objection. The toolkit should optimize for incremental improvement by default.

### Evidence

- Joel Spolsky: "the single worst strategic mistake that any software company can make" — rewriting from scratch ([Joel on Software](https://bssw.io/items/things-you-should-never-do-part-i))
- Counter-argument: rewrites justified when "architecture is severely out of alignment and incrementally updating would be exceedingly difficult" ([Remesh Blog](https://remesh.blog/refactor-vs-rewrite-7b260e80277a))
- Ben Morris: "Refactoring code is almost always better than rewriting it" — preserves institutional knowledge ([Ben Morris](https://www.ben-morris.com/why-refactoring-code-is-almost-always-better-than-rewriting-it/))

### Implications for the Toolkit

Default to incremental improvement. The audit report should never recommend "rewrite from scratch" — instead, it should identify the highest-impact incremental improvements. If the assessment reveals a codebase so broken that incremental improvement is infeasible, flag it explicitly with the evidence and let a human decide.

---

## 10. Audit Report Format

### Findings

An effective AI-generated audit report must serve two audiences: the human reviewer (who decides priorities) and the AI agent (who executes fixes). This demands both readable prose AND machine-parseable structure.

**Recommended format:**

```json
{
  "audit_metadata": {
    "project": "project-name",
    "date": "2026-02-22",
    "commit": "abc123",
    "agent_version": "autonomous-coding-toolkit v1.x"
  },
  "summary": {
    "health_score": 7.2,
    "total_findings": 42,
    "critical": 3,
    "high": 8,
    "medium": 15,
    "low": 16,
    "top_3_actions": ["..."]
  },
  "findings": [
    {
      "id": "F001",
      "category": "dead-code|complexity|naming|duplication|coverage|dependency|security|documentation",
      "severity": "critical|high|medium|low",
      "file": "src/parser.py",
      "line_range": [45, 89],
      "title": "Cyclomatic complexity 23 in parse_config()",
      "description": "...",
      "evidence": "radon cc output: ...",
      "remediation": "Extract 3 helper functions for condition branches",
      "estimated_effort": "15 minutes",
      "risk_level": "low|medium|high",
      "auto_fixable": true,
      "acceptance_criteria": ["pytest tests/test_parser.py -x"]
    }
  ],
  "metrics": {
    "cyclomatic_complexity": {"mean": 5.2, "max": 23, "p90": 12},
    "test_coverage": {"line": 0.67, "branch": 0.45},
    "dependency_count": {"direct": 12, "transitive": 89},
    "file_count": {"total": 156, "over_300_lines": 4},
    "dead_code_estimate": {"files": 3, "functions": 15, "imports": 42}
  },
  "hotspots": [
    {"file": "src/parser.py", "churn": 47, "complexity": 23, "coverage": 0.34, "priority_score": 0.92}
  ]
}
```

**Key design decisions:**
- Every finding has `acceptance_criteria` — shell commands that exit 0 when fixed. This feeds directly into the PRD system.
- Every finding has `auto_fixable` — determines whether it can be assigned to an AI agent without human review.
- `hotspots` section provides the prioritized hit list.
- `metrics` section provides the baseline for measuring improvement.

### Evidence

- Solo Sentinel guide: "Define checklist with prioritized categories: Primary (business logic), Non-negotiable (security), Secondary (code health)" ([Mad Devs](https://maddevs.io/writeups/practical-guide-to-lightweight-audits-in-the-age-of-ai/))
- DocsBot: "AI presents findings in well-structured format, categorizing by severity with specific remediation steps" ([DocsBot](https://docsbot.ai/prompts/technical/code-audit-analysis))
- CodeAnt: structured audit output with severity scoring and automated remediation ([CodeAnt](https://www.codeant.ai/blogs/10-best-code-audit-tools-to-improve-code-quality-security-in-2025))

### Implications for the Toolkit

Create `audit-report.json` as a first-class artifact alongside `prd.json`. The audit command produces this report; the plan generator reads it; the quality gate validates against it; the measure step compares pre/post metrics.

---

## 11. The Audit-Plan-Execute Pipeline

### Findings

The existing pipeline needs a new front-end for improvement work:

**Current pipeline (greenfield):**
```
/autocode "Add feature X"
  → brainstorm → PRD → plan → execute → verify → finish
```

**Proposed pipeline (improvement):**
```
/audit [project-dir]
  → discover → assess → prioritize → report (audit-report.json)

/improve [audit-report.json]
  → select top-N findings → generate PRD → plan → execute → verify → measure → finish
```

**How the PRD system works for refactoring:**

Acceptance criteria for "code is better" are measurable:
- `radon cc src/parser.py -nc | grep -c ' [C-F] '` exits 0 (no functions above grade C)
- `pytest --cov=src --cov-fail-under=80` exits 0
- `grep -rc 'import unused_module' src/ | grep -v ':0$'` exits non-zero (no more imports)
- `wc -l < src/big_file.py` output is < 300

Each finding in the audit report already has `acceptance_criteria` — the PRD generator just needs to collect them.

**Batch organization for improvement work:**

Unlike feature development (which follows a dependency order), improvement work can be organized by risk and independence:
- **Batch 1:** Dead code removal (zero risk, builds confidence)
- **Batch 2:** Naming and import cleanup (near-zero risk)
- **Batch 3:** Characterization tests for hotspot files (preparation)
- **Batch 4:** Refactor hotspot #1 (medium risk, has tests now)
- **Batch 5:** Refactor hotspot #2
- **Final batch:** Measure improvement, update documentation

### Implications for the Toolkit

Two new commands:
1. `/audit` — runs discover → assess → prioritize → produces `audit-report.json`
2. `/improve` — reads audit report, generates improvement PRD and plan, executes

The `/improve` command reuses the existing execution pipeline entirely. The only new code is the audit pipeline and the audit-to-PRD translator.

---

## 12. Measuring Improvement: The Scorecard

### Findings

Measuring codebase improvement requires a composite approach — no single metric captures "better."

**Metrics that matter (ranked by evidence strength):**

| Metric | What It Measures | Evidence Strength | Tool |
|--------|-----------------|-------------------|------|
| **Defect rate** | Bugs per time period post-change | High — direct outcome | Git + issue tracker |
| **Code Health** | Composite quality (CodeScene's 25+ factors) | High — research-backed | CodeScene / radon + custom |
| **Test coverage (branch)** | % of branches exercised | Medium-High — necessary but not sufficient | coverage.py, Istanbul |
| **Cyclomatic complexity** | Decision point count | Medium — correlated with defects, not causal | radon, eslint |
| **Change frequency** | Churn rate post-refactoring | Medium — should decrease if refactoring worked | Git log |
| **Coupling (afferent/efferent)** | Module interdependence | Medium — high coupling → hard changes | Custom import analysis |
| **Dead code count** | Unreachable / unused code | Medium — direct measure of waste | DCE-LLM, Knip, custom |
| **File size distribution** | Lines per file | Low-Medium — proxy for decomposition | wc -l |
| **Build time** | CI/CD pipeline duration | Low — secondary indicator | CI system |
| **Dependency count** | Direct + transitive deps | Low — more ≠ worse, but worth tracking | pip-audit, npm ls |

**Important caveat from DX research:** "Traditional structural analysis misses the real sources of complexity that impact delivery speed and developer satisfaction." Cyclomatic complexity alone is misleading — it must be combined with behavioral data (change frequency, defect rate) to be meaningful.

**Composite health score formula (proposed):**

```
health_score = (
  0.25 * normalize(test_coverage_branch) +
  0.20 * normalize(1 / mean_cyclomatic_complexity) +
  0.20 * normalize(1 / hotspot_count) +
  0.15 * normalize(1 / dead_code_ratio) +
  0.10 * normalize(1 / max_file_size_ratio) +
  0.10 * normalize(1 / coupling_score)
) * 10  # Scale to 1-10
```

### Evidence

- CodeScene: "unhealthy code has 15x more defects, 2x slower development, 10x more delivery uncertainty" ([CodeScene](https://codescene.com/product/behavioral-code-analysis))
- DX: "Traditional structural analysis misses the real sources of complexity" ([GetDX](https://getdx.com/blog/cyclomatic-complexity/))
- NASA: "most effective evaluation is a combination of size and cyclomatic complexity" ([Wikipedia](https://en.wikipedia.org/wiki/Cyclomatic_complexity))
- LinearB: "Cyclomatic complexity alone is misleading" — needs behavioral context ([LinearB](https://linearb.io/blog/cyclomatic-complexity))

### Implications for the Toolkit

Create `measure-improvement.sh` that:
1. Reads baseline metrics from `audit-report.json`
2. Runs the same measurements on current code
3. Produces a delta report showing improvement/regression per metric
4. Calculates composite health score

This runs as the final step of `/improve` and feeds into the continuous improvement loop.

---

## 13. Continuous Improvement: Autonomous Ongoing Quality

### Findings

The most promising pattern for continuous codebase improvement is **scheduled autonomous agents** that generate small, focused PRs:

**Continuous Claude pattern:**
1. GitHub Actions workflow triggers on schedule (daily/weekly)
2. Claude Code runs in headless mode with specific improvement goals
3. Each run produces one focused PR (e.g., "Remove 3 dead functions in parser module")
4. CI validates the PR
5. Human reviews and merges (or auto-merges for low-risk changes)

**Key innovations from Continuous Claude:**
- Context persists between iterations via progress files
- Self-improving: "increase coverage" becomes "run coverage, find files with low coverage, do one at a time"
- Can tackle large refactoring as a series of 20 PRs over a weekend

**Tech debt budget approach:**
- Allocate 15-20% of each sprint to tech debt (industry standard)
- Use the audit report to fill this budget with highest-priority items
- AI agent handles the "boring" items (dead code, naming, imports) automatically
- Humans review the "interesting" items (architecture, design patterns)

**Integration with existing toolkit:**
- `auto-compound.sh` already implements the report → analyze → PRD → execute → PR pipeline
- `entropy-audit.sh` already runs on a weekly timer
- The missing piece is connecting audit findings to automated improvement execution

### Evidence

- Continuous Claude: "multi-step projects complete while you sleep" via automated PR loops ([Anand Chowdhary](https://anandchowdhary.com/open-source/2025/continuous-claude))
- Organizations report "60-80% reduction in technical debt accumulation" with AI-driven refactoring ([GetDX](https://getdx.com/blog/enterprise-ai-refactoring-best-practices/))
- Coder Tasks: "From GitHub Issue to Pull Request" with Claude Code coding agent ([Coder](https://coder.com/blog/launch-dec-2025-coder-tasks))

### Implications for the Toolkit

Create `auto-improve.sh` that chains:
1. `audit.sh` → produces `audit-report.json`
2. Filter to auto-fixable findings below risk threshold
3. For each finding: create branch → fix → test → PR
4. Notify via Telegram with summary

Run as a systemd timer (weekly) alongside the existing entropy-audit timer. Low-risk fixes get auto-merged; medium-risk get PRs for review.

---

## 14. Working with Unfamiliar Codebases: The Onboarding Phase

### Findings

When an AI agent encounters a project it has never seen, it needs a structured onboarding phase before it can safely modify code. This is distinct from the audit — the onboarding produces a reusable **codebase profile** that speeds up all subsequent interactions.

**Onboarding sequence:**

1. **Environment setup** (seconds)
   - Detect language, build system, package manager
   - Install dependencies
   - Verify build succeeds

2. **Convention detection** (seconds-minutes)
   - Naming conventions (snake_case vs. camelCase)
   - File organization patterns
   - Import style (absolute vs. relative)
   - Test file naming and location
   - Commit message format (from git log)

3. **Architecture map** (minutes)
   - Entry points (main files, CLI commands, API routes)
   - Module boundaries and dependencies
   - Data models and database schema
   - Configuration system
   - External service integrations

4. **Safety assessment** (minutes)
   - Test suite health (does it run? does it pass? how long?)
   - CI/CD configuration
   - Code review requirements
   - Protected branches
   - Pre-commit hooks

5. **Profile generation** (seconds)
   - Write `codebase-profile.json` with all discovered information
   - Generate abbreviated `CONTEXT.md` for injection into agent prompts
   - Cache for reuse across sessions

**Confucius Code Agent approach (arXiv 2512.10398):** Uses scalable scaffolding for real-world codebases — a composable framework that adapts to different project structures. The key insight is that the scaffolding (project understanding framework) is reusable across sessions while the specific task changes.

### Evidence

- Confucius Code Agent: scalable scaffolding for production codebases ([arXiv 2512.10398](https://arxiv.org/html/2512.10398v4))
- OpenHands SDK: composable and extensible foundation with reusable workspace packages ([arXiv 2511.03690](https://arxiv.org/html/2511.03690v1))
- AGENTLESS: achieves competitive results by de-composing the problem into localization and repair without complex agent frameworks ([arXiv 2407.01489](https://arxiv.org/pdf/2407.01489))

### Implications for the Toolkit

Create `/onboard` command that:
1. Runs environment setup + convention detection + architecture map + safety assessment
2. Produces `codebase-profile.json` (cached, invalidated on major changes)
3. Generates `CONTEXT.md` for prompt injection
4. All subsequent commands (`/audit`, `/improve`, `/autocode`) read the profile first

The onboard step is idempotent — running it again updates the profile rather than starting from scratch.

---

## Proposed Audit Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                    AUDIT PIPELINE                            │
│                                                              │
│  /onboard (first time only — produces codebase-profile.json) │
│      │                                                       │
│      ▼                                                       │
│  /audit                                                      │
│      │                                                       │
│      ├── Phase 1: Discover (deterministic, fast)             │
│      │   ├── File tree + language detection                  │
│      │   ├── Dependency graph (imports, packages)            │
│      │   ├── Test suite baseline (detect + run)              │
│      │   ├── Git history analysis (hotspots, churn)          │
│      │   └── Existing metrics (complexity, coverage)         │
│      │                                                       │
│      ├── Phase 2: Assess (LLM-assisted)                     │
│      │   ├── Architecture recovery (module map)              │
│      │   ├── Code smell detection (per-file analysis)        │
│      │   ├── Pattern consistency check                       │
│      │   ├── Dead code identification                        │
│      │   └── Documentation completeness                     │
│      │                                                       │
│      ├── Phase 3: Prioritize                                 │
│      │   ├── Hotspot ranking (complexity × churn × coverage) │
│      │   ├── Risk classification (low/medium/high)           │
│      │   ├── Auto-fixable vs. human-required                 │
│      │   └── Effort estimation                               │
│      │                                                       │
│      └── Output: audit-report.json                           │
│                                                              │
│  /improve (reads audit-report.json)                          │
│      │                                                       │
│      ├── Select top-N findings by priority                   │
│      ├── Generate improvement PRD (tasks/prd.json)           │
│      ├── Generate improvement plan                           │
│      │   ├── Batch 1: Zero-risk fixes (dead code, imports)   │
│      │   ├── Batch 2: Characterization tests for hotspots    │
│      │   ├── Batch 3-N: Refactor hotspots (one per batch)    │
│      │   └── Final: Measure improvement                      │
│      │                                                       │
│      └── Execute via existing pipeline                       │
│          (run-plan.sh / ralph-loop / subagent-dev)           │
│                                                              │
│  /measure (runs after /improve)                              │
│      ├── Compare pre/post metrics                            │
│      ├── Calculate health score delta                        │
│      └── Output: improvement-report.json                     │
│                                                              │
│  auto-improve.sh (scheduled, continuous)                     │
│      ├── Run /audit                                          │
│      ├── Filter to auto-fixable low-risk findings            │
│      ├── For each: branch → fix → test → PR                 │
│      └── Notify via Telegram                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Toolkit Integration

### New Scripts

| Script | Purpose | Inputs | Outputs |
|--------|---------|--------|---------|
| `audit.sh` | Full audit pipeline (discover + assess + prioritize) | project dir, codebase-profile.json | audit-report.json |
| `onboard.sh` | Generate codebase profile for unfamiliar projects | project dir | codebase-profile.json, CONTEXT.md |
| `hotspot-analysis.sh` | Git + complexity + coverage cross-reference | project dir | hotspots.json |
| `measure-improvement.sh` | Pre/post metric comparison | audit-report.json (baseline), project dir | improvement-report.json |
| `auto-improve.sh` | Scheduled autonomous improvement (audit → fix → PR) | project dir | PRs on GitHub |
| `characterize.sh` | Generate characterization tests for specified files | file list | test files |

### New Commands

| Command | Purpose |
|---------|---------|
| `/audit` | Run full audit, produce report |
| `/improve` | Read audit report, execute improvement plan |
| `/onboard` | Generate codebase profile for new project |
| `/measure` | Compare pre/post metrics |

### New Skills

| Skill | Purpose |
|-------|---------|
| `codebase-audit/SKILL.md` | How to explore, assess, and prioritize an existing codebase |
| `improvement-planning/SKILL.md` | How to plan improvement work (batch ordering, risk management) |
| `characterization-testing/SKILL.md` | How to write golden master / characterization tests |

### Extensions to Existing Components

| Component | Extension |
|-----------|-----------|
| `run-plan.sh` | Add `--pre-step characterize` flag for auto-characterization before refactoring batches |
| `quality-gate.sh` | Add coverage-no-decrease gate (test coverage must not drop) |
| `entropy-audit.sh` | Replace with or augment by `audit.sh` for full hotspot-based analysis |
| `batch-audit.sh` | Use `audit.sh` per project instead of raw `claude -p` |
| `auto-compound.sh` | Add `--mode improve` that reads audit report instead of analyzing a report file |
| `classify_batch_type()` | Add `refactoring-risk` classification (low/medium/high) |

### Integration with Existing Pipeline

```
EXISTING:  /autocode "Add feature X" → brainstorm → PRD → plan → execute → verify → finish
NEW:       /audit → discover → assess → prioritize → audit-report.json
BRIDGE:    /improve audit-report.json → PRD → plan → execute → verify → measure → finish
CONTINUOUS: auto-improve.sh (timer) → audit → filter → fix → PR → notify
```

The key insight is that `/improve` reuses 80% of the existing pipeline. The audit is the new work; the improvement execution is the existing work with a different input source.

---

## Improvement Metrics Scorecard

### Pre-Audit Baseline (captured by `/audit`)

| Metric | Tool | Command |
|--------|------|---------|
| Test coverage (branch) | coverage.py / Istanbul | `pytest --cov --cov-branch --cov-report=json` |
| Cyclomatic complexity (mean, max, p90) | radon / eslint | `radon cc src/ -j` |
| Dead code count | custom grep / knip | `grep -rc 'import' src/ \| ...` |
| File count over 300 lines | wc -l | `find src/ -name '*.py' -exec wc -l {} + \| awk '$1>300'` |
| Hotspot count (complexity > 10 AND churn > 10) | custom | `hotspot-analysis.sh` |
| Dependency count | pip-audit / npm ls | `pip list --format=json \| jq length` |
| Naming violations | custom grep | `grep -rnE '^def [a-z]+[A-Z]' src/` |
| Documentation coverage | custom | `% of public functions with docstrings` |

### Post-Improvement Delta (captured by `/measure`)

| Metric | Target | Red Flag |
|--------|--------|----------|
| Test coverage (branch) | +10% or more | Any decrease |
| Cyclomatic complexity (mean) | -20% or more | Any increase |
| Dead code count | -50% or more | No change |
| Files over 300 lines | Zero | Any increase |
| Hotspot count | -30% or more | No change |
| Naming violations | Zero | Any increase |
| Health score | +1.0 or more | Any decrease |

### Composite Health Score

```
health_score = (
  0.25 * normalize(test_coverage_branch) +
  0.20 * normalize(1 / mean_cyclomatic_complexity) +
  0.20 * normalize(1 / hotspot_count) +
  0.15 * normalize(1 / dead_code_ratio) +
  0.10 * normalize(1 / max_file_size_ratio) +
  0.10 * normalize(1 / coupling_score)
) * 10
```

Scale: 1 (critical issues) to 10 (excellent health). Mirrors CodeScene's Code Health for familiarity.

---

## Sources

### Academic Papers and Benchmarks
- [ArchAgent: Scalable Legacy Software Architecture Recovery with LLMs](https://arxiv.org/html/2601.13007) — arXiv 2025
- [SWE-bench Pro: Can AI Agents Solve Long-Horizon Software Engineering Tasks?](https://arxiv.org/pdf/2509.16941) — Scale AI 2025
- [SWE-EVO: Benchmarking Coding Agents in Software Evolution](https://www.arxiv.org/pdf/2512.18470v1) — arXiv 2025
- [LLM-Driven Code Refactoring: Opportunities and Limitations](https://seal-queensu.github.io/publications/pdf/IDE-Jonathan-2025.pdf) — ICSE 2025 IDE Workshop
- [Understanding Codebase like a Professional: Human-AI Collaboration](https://arxiv.org/html/2504.04553) — arXiv 2025
- [DCE-LLM: Dead Code Elimination with Large Language Models](https://aclanthology.org/2025.naacl-long.501/) — NAACL 2025
- [Confucius Code Agent: Scalable Agent Scaffolding for Real-World Codebases](https://arxiv.org/html/2512.10398v4) — arXiv 2025
- [AGENTLESS: Demystifying LLM-based Software Engineering Agents](https://arxiv.org/pdf/2407.01489) — arXiv 2024
- [OpenHands SDK: Composable and Extensible Foundation for Production Agents](https://arxiv.org/html/2511.03690v1) — arXiv 2025
- [LoCoBench-Agent: Interactive Benchmark for LLM Agents](https://arxiv.org/pdf/2511.13998) — arXiv 2025

### Industry Tools and Documentation
- [CodeScene: Behavioral Code Analysis](https://codescene.com/product/behavioral-code-analysis)
- [CodeScene: Technical Debt Prioritization](https://codescene.com/blog/prioritize-technical-debt-by-impact/)
- [Semgrep vs. SonarQube Comparison](https://semgrep.dev/docs/faq/comparisons/sonarqube)
- [SWE-bench Overview](https://www.swebench.com/SWE-bench/)
- [OpenHands: AI-Driven Development](https://github.com/OpenHands/OpenHands)
- [Continuous Claude](https://anandchowdhary.com/open-source/2025/continuous-claude)
- [Meta Engineering: Automating Dead Code Cleanup](https://engineering.fb.com/2023/10/24/data-infrastructure/automating-dead-code-cleanup/)

### Books and Foundational References
- Michael Feathers, *Working Effectively with Legacy Code* (2004) — characterization tests, legacy code definition
- Joel Spolsky, ["Things You Should Never Do, Part I"](https://bssw.io/items/things-you-should-never-do-part-i) — the rewrite anti-pattern
- Thomas J. McCabe, "A Complexity Measure" (1976) — cyclomatic complexity

### Practical Guides
- [Augment Code: AI-Powered Legacy Code Refactoring](https://www.augmentcode.com/learn/ai-powered-legacy-code-refactoring)
- [IBM: What Is AI Code Refactoring?](https://www.ibm.com/think/topics/ai-code-refactoring)
- [Solo Sentinel: AI-Powered Lightweight Code Audits](https://maddevs.io/writeups/practical-guide-to-lightweight-audits-in-the-age-of-ai/)
- [Golden Master Testing for Legacy Code](https://blog.thecodewhisperer.com/permalink/surviving-legacy-code-with-golden-master-and-sampling)
- [Strangler Fig Pattern — Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/patterns/strangler-fig)
- [Strangler Fig Pattern — AWS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/strangler-fig.html)
- [GetDX: Why Cyclomatic Complexity Misleads](https://getdx.com/blog/cyclomatic-complexity/)
- [Enterprise AI Refactoring Best Practices](https://getdx.com/blog/enterprise-ai-refactoring-best-practices/)
- [Qodo: Unit Testing vs Integration Testing with AI](https://www.qodo.ai/blog/unit-testing-vs-integration-testing-ais-role-in-redefining-software-quality/)
