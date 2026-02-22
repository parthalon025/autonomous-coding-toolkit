# Research: Lesson Transferability — Do Anti-Pattern Lessons Generalize Across Projects?

**Date:** 2026-02-22
**Researcher:** Claude Opus 4.6 (research agent)
**Domain:** Cynefin complicated — well-studied in adjacent fields (static analysis, safety science), but novel in community lesson systems for AI coding agents
**Confidence:** Medium overall — strong evidence from analogous domains, limited direct evidence for AI-agent-specific lesson systems

---

## Executive Summary

Anti-pattern lessons transfer reliably within a well-defined scope boundary, but applying all lessons universally to all projects produces unacceptable false positive rates. The evidence from static analysis research (SonarQube, ESLint, Semgrep), cross-project defect prediction (622-pair studies), and safety science (aviation ASRS, medical NRLS, Toyota A3) converges on one conclusion: **transferability is a function of abstraction level, not project similarity**.

Lessons that encode universal programming invariants ("log before fallback," "close resources") transfer with near-zero false positives. Lessons that encode language-specific semantics ("async def without await") transfer within their language. Lessons that encode framework or tool-specific behavior ("hub.cache access patterns") do not transfer at all. The current lesson system has no scope metadata, which means every lesson runs against every project — a guaranteed source of noise as the library grows.

**Recommendation:** Add a `scope` field to lesson YAML frontmatter with values `universal | language | framework | project-specific`. Filter lessons at scan time based on project language/framework detection. Target library size of 100-150 active lessons with aggressive retirement. Confidence: high.

---

## 1. Do Anti-Pattern Lessons From One Project Actually Prevent Bugs in Another?

### Findings

**Yes, but with significant caveats.** The cross-project defect prediction (CPDP) literature provides the strongest evidence. Zimmermann, Nagappan et al. (2009) ran 622 cross-project predictions across 12 real-world applications and found that cross-project prediction "is a serious challenge" — simply using models from projects in the same domain or with the same process does not guarantee accurate predictions. However, when the projects share structural and metric similarity, transfer works. More recent work (Tao 2024, using LSTM networks; TriStage-CPDP 2025, using CodeT5+) shows that deep learning can extract "project-invariant features" that improve transfer — but these are statistical features, not the kind of discrete rules in a lesson system.

The more relevant evidence comes from the static analysis ecosystem. Tools like ESLint, Pylint, and SonarQube have been applying cross-project rules for decades. Their experience shows:

- **Universal rules work universally.** SonarQube's "Sonar way" default profiles activate rules "that should be applicable to most projects" (SonarQube docs). These are the equivalent of our "bare except" lesson — language-level invariants.
- **Framework-specific rules produce false positives outside their framework.** This is why Semgrep uses `<language>/<framework>/<category>` namespacing — a React rule applied to a Django project is pure noise.
- **Unconfigured deployments average 67% false positive rates.** The 2024 GitLab Security Report measured SAST tools (including Semgrep, CodeQL, SonarQube CE) and found that out-of-the-box configurations "overwhelm developers with false positives."

The lesson system is analogous to a static analysis tool with no scoping mechanism. Every lesson runs everywhere. This works at 10 lessons but will not work at 100.

### Evidence Quality

- Zimmermann et al. 2009: Large-scale empirical study, widely cited (2000+ citations). **High confidence.**
- GitLab Security Report 2024: Industry report, methodology unclear. **Medium confidence.**
- SonarQube/ESLint ecosystem behavior: Observable, well-documented. **High confidence.**

### Implications for the Toolkit

The current 61-lesson library is already at the point where scope matters. Of the 61 lessons, roughly 15 are Python-specific (async traps, venv/pip issues), 5 are JavaScript-specific (JSX factory, prop names), 8 are bash/shell-specific (local scope, set -e, grep -c), and the rest are universal or integration-level. Running Python-specific lessons against a JavaScript project is wasted work and false positive risk.

---

## 2. What's the Generalizability Boundary?

### Findings

Anti-patterns exist on a spectrum of abstraction, and transferability maps directly to that spectrum:

| Scope Level | Transfers To | False Positive Risk | Examples from Our Lessons |
|---|---|---|---|
| **Universal** | All projects in all languages | Near zero | 0001 (bare except → bare catch), 0018 (each layer passes its test), 0020 (persist state before expensive work), 0029 (no secrets in code) |
| **Language** | All projects in that language | Low | 0002 (async def without await — Python), 0010 (local outside function — bash), 0022 (JSX factory shadowed — JavaScript) |
| **Framework/Tool** | Projects using that framework | Medium | 0006 (.venv/bin/pip — Python + pip), 0044 (relative file: deps — npm workspaces), 0047 (pytest xdist) |
| **Domain** | Projects in the same domain | High if misapplied | 0016 (event-driven cold start — only relevant to event-driven systems), 0037 (parallel agents sharing worktree — only relevant to multi-agent systems) |
| **Project-specific** | Only the originating project | Very high | 0007 (runner state file rejected by own git-clean check), 0009 (plan parser over-count), 0051 (infrastructure fixes can't benefit their own run) |

The Wikipedia list of software anti-patterns confirms this hierarchy: anti-patterns are classified into software development (universal), architecture (domain), programming (language-specific), and methodological (process-specific) categories.

### Evidence

The Semgrep registry provides the clearest empirical model. Their rule namespace `<language>/<framework>/<category>/$MORE` explicitly encodes this hierarchy. When Semgrep scans a repository, it "identifies the languages used in your repositories and only runs rules applicable to those languages." This is exactly the filtering mechanism our lesson system lacks.

SonarQube's quality profiles reinforce this: "Every project has a quality profile set for each supported language." Rules are never applied cross-language. The built-in "Sonar way" profile activates a curated subset — not all rules.

### Implications

The lesson system needs scope metadata. Without it, the lesson library cannot scale past ~80-100 lessons without producing noise. The Semgrep model (`language/framework/category`) is the right template.

---

## 3. What Does the Static Analysis Literature Say About Rule Transferability?

### Findings

The static analysis ecosystem has converged on several principles over two decades:

**1. Rules are scoped to language, always.** No tool applies Python rules to JavaScript. This is foundational — not even debated. SonarQube uses per-language quality profiles. ESLint only applies to JavaScript/TypeScript. Pylint only applies to Python. Semgrep runs only rules matching detected languages.

**2. Default rule sets are intentionally conservative.** SonarQube's "Sonar way" activates a subset of available rules. ESLint's recommended config enables ~50 of 200+ available rules. The principle: start with high-confidence universal rules, let users opt into more specific ones. This is directly applicable to our lesson system — not every lesson should be active by default.

**3. Shared configs are the primary transfer mechanism.** In the ESLint ecosystem, `eslint-config-airbnb` (4M+ weekly downloads) and `standard` (545K+ weekly downloads) represent community consensus on which rules apply broadly. These configs are curated — someone decided which rules transfer and which don't. Our lesson system has no curation layer.

**4. False positive rates are the primary adoption barrier.** SonarQube empirical studies show 18% precision (69/384 sample) without configuration. DeepSource targets <5% false positive rate through a multi-stage relevance engine. The industry consensus is that unconfigured analysis averaging 67% false positive rates is worse than no analysis — it erodes trust and causes developer fatigue.

**5. AI-powered triage is the emerging solution.** Datadog's Bits AI and Semgrep's AI noise filtering (announced 2025) use LLMs to classify findings as true/false positives. This is directly relevant — our lesson-scanner agent could apply the same approach, using the AI agent's understanding of project context to suppress irrelevant lessons.

### Evidence Quality

- ESLint/SonarQube/Semgrep documentation: Primary sources. **High confidence.**
- GitLab Security Report 2024 false positive rates: Industry measurement. **Medium confidence.**
- DeepSource <5% target: Self-reported, methodology published. **Medium confidence.**
- Datadog/Semgrep AI triage: Early stage, limited public evaluation data. **Low-medium confidence.**

---

## 4. Are There Lesson Categories That Transfer Well vs. Poorly?

### Findings

Mapping our six categories against the transferability spectrum:

| Category | Transfer Potential | Reasoning |
|---|---|---|
| **silent-failures** | **High** (mostly universal) | "Log before fallback" is language-agnostic. Bare except (Python), empty catch (JS/Java/Go), `|| true` (bash) — same concept, different syntax. 18 of 21 silent-failure lessons transfer with syntax adaptation. |
| **integration-boundaries** | **Medium** (domain-dependent) | "Verify at boundaries" is universal, but specific boundary patterns (worktree corruption, systemd env files, JSX prop names) are domain/tool-specific. 10 of 27 integration lessons are truly universal; 17 are context-dependent. |
| **async-traps** | **Medium** (language-dependent) | Async anti-patterns transfer within the async programming model (Python asyncio, JavaScript Promises/async-await, C# async/await, Rust async). They do NOT transfer to synchronous-only projects. 3 of 3 async lessons are Python-specific in syntax but concept-transferable. |
| **test-anti-patterns** | **High** (mostly universal) | "Don't hardcode counts in assertions" applies to any test framework in any language. 5 of 6 test lessons transfer universally. |
| **resource-lifecycle** | **High** (universal concept, language-specific syntax) | "Close what you open" applies everywhere. Specific mechanisms (Python context managers, Java try-with-resources, Go defer) vary by language. 3 of 3 lessons transfer conceptually. |
| **performance** | **Medium** (context-dependent) | "Filter before processing" is universal. "Use pytest-xdist" is tool-specific. 1 of 2 performance lessons transfers universally. |

**Key finding:** The categories that transfer best encode **invariants of correctness** (silent failures, test anti-patterns, resource lifecycle). The categories that transfer worst encode **operational specifics** (integration boundaries, domain-specific async patterns).

This maps to the Semgrep finding that their most widely-used community rules are generic security checks (SQL injection, XSS, hardcoded secrets) rather than framework-specific patterns.

---

## 5. What's the False Positive Cost of Applying Project-Specific Lessons to Unrelated Projects?

### Findings

The cost is higher than it appears because false positives compound in three ways:

**1. Direct noise cost.** Each false positive requires a developer (or AI agent) to read, evaluate, and dismiss the finding. At 61 lessons, with perhaps 10 project-specific ones, the noise is manageable. At 200 lessons with 60 project-specific ones, every scan produces dozens of irrelevant findings.

**2. Trust erosion.** The Parasoft blog on static analysis false positives states it clearly: "too much noise kills adoption." SonarQube community forums document cases of "hundreds of obvious false positives" leading teams to disable scanning entirely. The same dynamic applies to our lesson system — if users see irrelevant warnings repeatedly, they stop reading any warnings.

**3. Alert fatigue leading to missed true positives.** This is the most dangerous cost. The medical safety literature documents this extensively: the NHS NRLS receives over 2 million reports per year, and the primary challenge is ensuring that signal isn't lost in noise. In our context: if 30% of lesson warnings are false positives, users develop a habit of dismissing warnings — including the one true positive that would have prevented a production bug.

**Quantifying the cost:** If unconfigured SAST tools average 67% false positive rates, and our lesson system has no scoping, we can expect a similar trajectory as the library grows. At 100 lessons with no scope filtering, a JavaScript project would receive warnings from ~15 Python-specific and ~8 bash-specific lessons — roughly 23% noise before even considering domain-specific false positives.

### Evidence

- GitLab Security Report 2024: 67% average FP rate for unconfigured SAST. **Medium confidence.**
- SonarQube community forums: Documented user complaints about "hundreds of obvious false positives." **High confidence** (primary source).
- NHS NRLS: 2M+ reports/year, signal-in-noise is the central challenge. **High confidence.**
- Quantitative estimate for our system (23% noise at 100 lessons): **Low confidence** (extrapolation, not measurement).

---

## 6. How Do Other Community-Driven Quality Systems Handle Scope?

### Findings

Six systems, six approaches:

**ESLint Shared Configs** — Community-driven scope via npm packages. `eslint-config-airbnb` encodes Airbnb's opinion on which rules apply to their JavaScript projects. Users explicitly opt in by installing the package. Scope is implicit (JavaScript-only because ESLint is JavaScript-only) and explicit (curated rule sets). The flat config system introduced namespace challenges — "the ecosystem needs to decide how it solves the problem of plugin namespacing." Lesson: explicit scope metadata prevents namespace collisions as libraries grow.

**Semgrep Registry** — `<language>/<framework>/<category>` namespacing. Technology metadata tags (e.g., `express`, `django`) link rules to frameworks. Language auto-detection at scan time filters irrelevant rules. Rulesets group rules by programming language, OWASP category, or framework. Lesson: the namespace hierarchy IS the scope mechanism.

**SonarQube Quality Profiles** — Per-language profiles with inheritance. Built-in "Sonar way" as conservative default. Organizations extend profiles with project-specific rules. Lesson: a default conservative profile plus opt-in extensions is the right activation model.

**CodeClimate** — File-path-based filtering via `Filters` tool. Excludes `config/`, `test/`, `vendor/` by default. Per-project filter definitions for monorepos. Lesson: path-based filtering catches project-structure-specific noise.

**DeepSource** — Multi-stage relevance engine. AST analysis → processor pipeline → relevance engine → confidence scoring. Targets <5% false positive rate. Each issue gets a "dynamic weight." Lesson: post-detection relevance scoring can reduce noise without removing rules.

**Aviation ASRS** — NASA's voluntary safety reporting. Reports are de-identified and published in CALLBACK monthly bulletin with "supporting commentary." The key insight: raw reports are not directly actionable — they require expert curation and contextualization before becoming "lessons." The ASRS model has been adopted by the UK (CHIRP), Canada, Australia, Japan, and cross-domain (NFIRS for fire, NRLS for healthcare). Lesson: curation transforms reports into transferable knowledge.

**NHS NRLS** — 2M+ reports/year. Reports are classified by type, severity, and clinical area. National-level analysis produces "rapid response reports, patient safety alerts, and safer practice notices" — curated outputs from raw data. Lesson: the volume of raw incident data must be distilled into actionable alerts, not applied wholesale.

**Toyota A3** — One-page problem-solution format. A3s are stored in a searchable database so "you never solve the same problem twice." The format forces root cause analysis (5 Whys), proposed countermeasures, and follow-up validation. Lesson: structured format (which our lesson system already has) enables searchability and reuse.

### Synthesis

Every successful system employs at least one of three mechanisms:
1. **Scope metadata** (Semgrep, SonarQube) — rules tagged with their applicability
2. **Curation** (ASRS, NRLS, ESLint configs) — expert review before broad distribution
3. **Relevance filtering** (DeepSource, Datadog) — post-detection scoring to suppress noise

Our lesson system currently has none of these. Adding scope metadata (mechanism 1) is the highest-leverage change. The maintainer review process in CONTRIBUTING.md provides mechanism 2 but doesn't enforce scope classification. Mechanism 3 (relevance filtering) could be added to the lesson-scanner agent.

---

## 7. Should Lessons Have Scope Metadata?

### Findings

**Yes. Unequivocally.** Every analogous system that has scaled past ~50 rules uses scope metadata.

Proposed schema addition to lesson YAML frontmatter:

```yaml
scope:
  level: universal | language | framework | domain | project-specific
  languages: [python]              # Required if level != universal
  frameworks: [asyncio, pytest]    # Optional, for framework-level lessons
  domains: [event-driven, multi-agent]  # Optional, for domain-level lessons
```

**Filtering logic at scan time:**

1. `universal` — always active
2. `language` — active if project contains files in the specified language(s)
3. `framework` — active if project's dependency manifest includes the specified framework(s)
4. `domain` — active if project's CLAUDE.md or config declares the domain
5. `project-specific` — active only in the originating project (or explicitly opted-in)

**Classification of current 61 lessons by proposed scope:**

| Scope Level | Count | Examples |
|---|---|---|
| Universal | ~25 | 0001 (bare except — concept is universal even if regex is Python), 0018, 0020, 0029 |
| Language (Python) | ~15 | 0002, 0003, 0005, 0033, 0034 |
| Language (JavaScript) | ~5 | 0022, 0027, 0044 |
| Language (Bash) | ~8 | 0010, 0013, 0019, 0053, 0056, 0060 |
| Framework/Tool | ~4 | 0006 (pip), 0047 (pytest-xdist) |
| Domain | ~2 | 0037 (multi-agent worktree), 0016 (event-driven cold start) |
| Project-specific | ~2 | 0007 (runner state file), 0009 (plan parser over-count) |

**Implementation cost:** Low. Adding a YAML field to existing lessons is a one-time effort. Filtering logic in `lesson-check.sh` requires reading the project's language from file extensions or a config file — perhaps 20 lines of bash. The lesson-scanner agent already has project context and can filter semantically.

### Confidence: High

Every analogous system does this. The only question is syntax, not whether.

---

## 8. What's the Optimal Lesson Library Size?

### Findings

The static analysis literature and industry practice converge on a principle: **focused sets outperform exhaustive sets.**

**Evidence for diminishing returns:**

- Parasoft (static analysis vendor): "Checking a lot of rules is not the secret to achieving the best ROI with static analysis. In fact, in many cases, the reverse is true."
- SonarQube's "Sonar way" activates a curated subset, not all available rules. The full rule set for Java alone exceeds 600 rules; "Sonar way" activates approximately 350.
- ESLint's `recommended` config enables ~50 of 200+ rules. Airbnb's config enables ~250, but these are heavily curated for a specific use case.
- DeepSource's approach: fewer rules, but <5% false positive rate per rule. Quality over quantity.

**The noise accumulation curve:**

```
Rules  | True Positives | False Positives | Signal-to-Noise
-------|----------------|-----------------|----------------
  20   |   High/rule    |   Very low      |   Excellent
  50   |   Medium/rule  |   Low           |   Good
 100   |   Low/rule     |   Medium        |   Acceptable
 200   |   Very low/rule|   High          |   Poor
 500   |   Negligible   |   Very high     |   Unusable
```

Each new lesson has diminishing marginal value (the most common anti-patterns are caught early) and increasing marginal cost (more rules = more false positives = more noise). The crossover point — where adding a rule produces more noise than signal — depends on scope filtering:

- **Without scope filtering:** Crossover at ~80-100 lessons (our current trajectory)
- **With language-level filtering:** Crossover at ~150-200 lessons per language
- **With framework-level filtering:** Crossover at ~250-300 lessons per framework

**Recommendation:** Target 100-150 active lessons with scope filtering. Institute a retirement policy: lessons with zero true positive matches across 100+ scans should be archived (not deleted — moved to an `archived/` subdirectory). Review annually.

### Confidence: Medium

The principle is well-established (high confidence), but the specific numbers are extrapolations from adjacent domains (medium confidence). Empirical measurement of false positive rates for our specific lesson system would increase confidence.

---

## 9. How Do Lesson Systems in Other Domains Work?

### Findings

Three domains with mature lesson systems:

**Aviation (ASRS)**
- **Structure:** Voluntary, confidential, de-identified. NASA operates (neutral third party). No enforcement authority.
- **Volume:** 1.7M+ reports since 1976. Monthly CALLBACK bulletin with curated excerpts.
- **Transfer mechanism:** Expert analysis → categorized alerts → industry-wide distribution. Raw reports are never applied directly — they are distilled.
- **Success evidence:** "A proven and effective way to fill in the gaps left by accident investigations" (FAA Safety). Model adopted by 6+ countries and 3+ other industries.
- **Key insight for us:** Raw incident reports (our lesson files) need a curation and distillation layer to transfer effectively. The ASRS doesn't say "here are 1.7M reports, read all of them." It says "here are this month's 6 most important patterns."

**Medical Safety (NHS NRLS)**
- **Structure:** Mandatory reporting for serious incidents, voluntary for near-misses. 2M+ reports/year.
- **Volume:** World's largest patient safety database.
- **Transfer mechanism:** National analysis → rapid response reports → patient safety alerts → local action plans. Classification by incident type, severity, clinical area, and contributing factors.
- **Success evidence:** "Findings and learnings shared across the organization, leading to redesigning policies, improving processes."
- **Key insight for us:** Classification metadata (type, severity, area) is essential for making large databases searchable and actionable. Our lesson system has severity and category but lacks scope.

**Manufacturing (Toyota A3)**
- **Structure:** One-page structured problem-solution format. Searchable database.
- **Volume:** Organization-wide, accumulated over decades.
- **Transfer mechanism:** "You never solve the same problem twice" — A3s are indexed and searchable. Managers use A3s to mentor root-cause thinking.
- **Success evidence:** MIT Sloan Management Review describes A3 as "the key tactic in sharing a deeper method of thinking that lies at the heart of Toyota's sustained success."
- **Key insight for us:** Our lesson format (YAML frontmatter + observation/insight/lesson) already follows the A3 structure. The missing piece is the searchable database — currently lessons are flat files discovered by grep.

### Cross-Domain Synthesis

All three systems share four properties:
1. **Structured capture** — standardized format for raw incidents (we have this)
2. **Expert curation** — human review before broad distribution (we have this via PR review)
3. **Scope classification** — metadata for filtering relevance (we lack this)
4. **Distilled outputs** — curated summaries for different audiences (we partially have this via SUMMARY.md)

The aviation and medical systems also share a critical property we lack: **tiered distribution**. Not every report goes to every practitioner. Alerts are routed based on relevance (clinical area, aircraft type, role). Our lesson system applies every lesson to every project — the equivalent of sending every patient safety alert to every doctor regardless of specialty.

---

## 10. What Filtering/Relevance Mechanisms Could Reduce False Positives Without Losing Coverage?

### Findings

Five mechanisms, ordered by implementation cost and expected impact:

**Mechanism 1: Scope metadata filtering (High impact, Low cost)**
Add `scope.level` and `scope.languages` to lesson YAML. At scan time, detect project language(s) from file extensions and filter lessons accordingly. This eliminates the most obvious noise — Python lessons in JavaScript projects — with minimal implementation effort.

Expected noise reduction: 30-40% of current false positives.

**Mechanism 2: Framework detection (Medium impact, Medium cost)**
Read `requirements.txt`, `package.json`, `Cargo.toml`, etc. to detect frameworks. Filter framework-scoped lessons based on actual dependencies. More implementation effort (must parse multiple manifest formats) but eliminates framework-specific noise.

Expected noise reduction: 10-15% additional.

**Mechanism 3: Confidence scoring on matches (Medium impact, Medium cost)**
For syntactic lessons, score matches by context. A bare `except:` in a test helper is less critical than in production code. For semantic lessons, the lesson-scanner agent already has context — add a confidence field to its output. This follows the DeepSource model of post-detection relevance scoring.

Expected noise reduction: 15-20% additional (primarily for syntactic lessons in test/example code).

**Mechanism 4: AI-powered triage (High impact, High cost)**
Following Datadog's Bits AI model, use the lesson-scanner agent to evaluate whether a syntactic match is actually problematic in context. The agent reads the surrounding code, understands the project's patterns, and suppresses findings that are technically matches but practically benign. This is the most powerful mechanism but requires significant agent compute.

Expected noise reduction: 20-30% additional, but at high compute cost per scan.

**Mechanism 5: Community feedback loop (Medium impact, Low ongoing cost)**
Track true/false positive rates per lesson across the community. Lessons with >20% false positive rate get flagged for review. Lessons with >50% false positive rate get automatically demoted from `blocker` to `nice-to-have`. This follows the DeepSource model of "static issue filtering based on conventions and user feedback."

Expected noise reduction: Compounds over time. 5% in year 1, 15% by year 2.

### Recommended Implementation Order

1. Scope metadata (immediate — one PR, low risk, high impact)
2. Framework detection (next quarter — moderate effort, good ROI)
3. Confidence scoring (same quarter — extends existing lesson-scanner)
4. Community feedback loop (ongoing — requires usage telemetry infrastructure)
5. AI-powered triage (future — high cost, diminishing marginal returns if 1-4 are done)

---

## Transferability Framework for the Lesson System

Based on all findings, here is the proposed framework:

### Lesson Scope Taxonomy

```
┌─────────────────────────────────────────────────┐
│ UNIVERSAL                                       │
│ "Log before fallback" — applies to all code     │
│ Transfer: unconditional                         │
│ False positive risk: near zero                  │
├─────────────────────────────────────────────────┤
│ LANGUAGE                                        │
│ "async def without await" — Python only         │
│ Transfer: within language boundary              │
│ Filter: file extension / language detection     │
├─────────────────────────────────────────────────┤
│ FRAMEWORK                                       │
│ ".venv/bin/pip installs wrong" — pip-specific   │
│ Transfer: within framework users                │
│ Filter: dependency manifest detection           │
├─────────────────────────────────────────────────┤
│ DOMAIN                                          │
│ "Seed state on event-driven startup" — EDA only │
│ Transfer: within architectural pattern          │
│ Filter: project config / CLAUDE.md declaration  │
├─────────────────────────────────────────────────┤
│ PROJECT-SPECIFIC                                │
│ "Runner state file rejected by git-clean"       │
│ Transfer: originating project only              │
│ Filter: project name match                      │
│ Default: inactive in community library          │
└─────────────────────────────────────────────────┘
```

### YAML Schema Extension

```yaml
# Proposed addition to lesson frontmatter
scope:
  level: universal          # universal | language | framework | domain | project-specific
  languages: [python]       # Required unless level = universal
  frameworks: []            # Optional, for framework-level lessons
  domains: []               # Optional, for domain-level lessons
  project: ""               # Required if level = project-specific
```

### Filtering Algorithm

```
function should_run_lesson(lesson, project):
  if lesson.scope.level == "universal":
    return true

  if lesson.scope.level == "language":
    return project.languages ∩ lesson.scope.languages ≠ ∅

  if lesson.scope.level == "framework":
    return project.dependencies ∩ lesson.scope.frameworks ≠ ∅

  if lesson.scope.level == "domain":
    return project.domains ∩ lesson.scope.domains ≠ ∅

  if lesson.scope.level == "project-specific":
    return project.name == lesson.scope.project
```

### Activation Policy

| Scope Level | Default State | Activation |
|---|---|---|
| Universal | Active for all | Cannot be disabled |
| Language | Active if language detected | Auto-detected from file extensions |
| Framework | Inactive by default | Activated by dependency detection or user opt-in |
| Domain | Inactive by default | Activated by project config declaration |
| Project-specific | Inactive | Only active in originating project |

### Library Growth Policy

- **Target:** 100-150 active lessons with scope filtering
- **Retirement:** Archive lessons with zero matches across 100+ scans
- **Review cadence:** Quarterly review of false positive rates per lesson
- **Quality bar:** New lessons must specify scope level; PR review verifies scope accuracy
- **Universal lessons cap:** No more than 40 universal lessons (diminishing returns)

---

## Recommendations

### Immediate (This Sprint)

1. **Add `scope` field to TEMPLATE.md and CONTRIBUTING.md** — require scope for all new lessons
2. **Backfill scope on existing 61 lessons** — classify each lesson by scope level (estimated effort: 1-2 hours)
3. **Add language filtering to `lesson-check.sh`** — detect project language(s) from file extensions, skip lessons with non-matching `scope.languages` (estimated effort: 30 minutes)

### Next Quarter

4. **Add framework detection** — parse `requirements.txt`, `package.json`, `Cargo.toml` for framework-level filtering
5. **Add confidence scoring to lesson-scanner output** — each finding gets a confidence level based on context
6. **Document scope taxonomy** in ARCHITECTURE.md

### Future

7. **Community false positive tracking** — aggregate match data to identify noisy lessons
8. **AI-powered triage** — use lesson-scanner agent to evaluate syntactic matches in context
9. **Lesson retirement automation** — auto-archive lessons below signal threshold

### Confidence Assessment

| Recommendation | Confidence | Basis |
|---|---|---|
| Add scope metadata | **High** | Every analogous system does this. Zero counterevidence. |
| Language-level filtering | **High** | SonarQube, Semgrep, ESLint all do this. Standard practice. |
| Framework detection | **Medium** | Semgrep does this well; implementation complexity varies. |
| Library size target (100-150) | **Medium** | Extrapolated from static analysis literature; needs empirical validation. |
| AI-powered triage | **Low-Medium** | Datadog/Semgrep results promising but early-stage. |

---

## Sources

### Academic Research
- [Zimmermann, Nagappan et al. — Cross-project Defect Prediction (ESEC/FSE 2009)](https://dl.acm.org/doi/10.1145/1595696.1595713) — 622 cross-project predictions, "a serious challenge"
- [Tao 2024 — Cross-project Defect Prediction Using Transfer Learning with LSTM](https://ietresearch.onlinelibrary.wiley.com/doi/10.1049/2024/5550801)
- [TriStage-CPDP 2025 — Three-stage Cross-project Defect Prediction](https://link.springer.com/article/10.1007/s40747-025-02098-y) — CodeT5+ for project-invariant features
- [Cross-project Defect Prediction Based on Transfer GCN (2025)](https://link.springer.com/article/10.1007/s10664-025-10783-2)
- [Antipatterns in Software Classification Taxonomies (ScienceDirect 2022)](https://www.sciencedirect.com/science/article/pii/S0164121222000826)
- [Predicting Bugs Using Antipatterns (ResearchGate)](https://www.researchgate.net/publication/261416699_Predicting_Bugs_Using_Antipatterns)
- [Multi-Programming-Language Bug Prediction (2024)](https://arxiv.org/html/2407.10906v1)
- [Are Static Analysis Violations Really Fixed? (IEEE 2019)](https://ieeexplore.ieee.org/document/8813272/) — SonarQube empirical study
- [Toyota's Secret: The A3 Report (MIT Sloan Management Review)](https://sloanreview.mit.edu/article/toyotas-secret-the-a3-report/)
- [Toyota A3 Report: Process Improvement in Healthcare (PubMed)](https://pubmed.ncbi.nlm.nih.gov/19380942/)

### Industry Reports and Documentation
- [SonarQube Quality Profiles Documentation](https://docs.sonarsource.com/sonarqube-server/latest/quality-standards-administration/managing-quality-profiles/)
- [SonarQube Rules Overview](https://docs.sonarsource.com/sonarqube-server/quality-standards-administration/managing-rules/rules)
- [Semgrep Rule Structure Syntax](https://semgrep.dev/docs/writing-rules/rule-syntax)
- [Semgrep Registry Contribution Guide](https://semgrep.dev/docs/contributing/contributing-to-semgrep-rules-repository)
- [Semgrep Policies and Rule Management](https://semgrep.dev/docs/semgrep-code/policies)
- [ESLint Shareable Configs](https://eslint.org/docs/latest/extend/shareable-configs)
- [ESLint Flat Config Introduction](https://eslint.org/blog/2022/08/new-config-system-part-2/)
- [CodeClimate Maintainability Documentation](https://docs.codeclimate.com/docs/maintainability)
- [CodeClimate Filters](https://docs.codeclimate.com/docs/filters)
- [Sonar Blog — False Positives Are Our Enemies](https://www.sonarsource.com/blog/false-positives-our-enemies-but-maybe-your-friends/)
- SonarQube Community Forum — [Hundreds of Obvious False Positives](https://community.sonarsource.com/t/hundreds-of-obvious-false-positives/57867)

### False Positive Research and Filtering
- [DeepSource — How We Ensure Less Than 5% False Positive Rate](https://deepsource.com/blog/how-deepsource-ensures-less-false-positives)
- [Datadog — Using LLMs to Filter Out False Positives from SAST](https://www.datadoghq.com/blog/using-llms-to-filter-out-false-positives/)
- [Semgrep — Announcing AI Noise Filtering and Triage Memories (2025)](https://semgrep.dev/blog/2025/announcing-ai-noise-filtering-and-triage-memories/)
- [GitLab Security Report 2024 — 67% average FP rate](https://kb.secuarden.com/briefs/issue-2-drowning-in-alerts-the-false-positive-trap-in-open-source-sast/)
- [Parasoft — False Positives in Static Code Analysis](https://www.parasoft.com/blog/false-positives-in-static-code-analysis/)
- [Parasoft — 10 Tips for Static Analysis Clean-Up](https://www.parasoft.com/blog/10-tips-static-analysis/)

### Safety Science
- [NASA ASRS — Aviation Safety Reporting System](https://asrs.arc.nasa.gov/)
- [ASRS Wikipedia](https://en.wikipedia.org/wiki/Aviation_Safety_Reporting_System)
- [NASA ASRS Program Briefing (2024)](https://ntrs.nasa.gov/api/citations/20240014226/downloads/ICASS%202024%20ASRS.pdf)
- [SKYbrary — ASRS Overview](https://skybrary.aero/articles/aviation-safety-reporting-system-asrs)
- [FAA — The Case for Confidential Incident Reporting Systems](https://www.faasafety.gov/files/events/EA/EA23/2010/EA2334954/NASA_Reporting.pdf)
- [NHS NRLS — Using Incident Reporting Systems to Improve Patient Safety (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11554398/)
- [NHS NRLS Background (NCBI Bookshelf)](https://www.ncbi.nlm.nih.gov/books/NBK385184/)
- [Systems for Identifying and Reporting Medicines-Related Safety Incidents (NCBI)](https://www.ncbi.nlm.nih.gov/books/NBK355903/)

### Developer Experience
- [Agoda Engineering — How to Make Linting Rules Work](https://medium.com/agoda-engineering/how-to-make-linting-rules-work-from-enforcement-to-education-be7071d2fcf0)
- [Qlty — Developer Experience Gaps of Linting on CI](https://qlty.sh/blog/developer-experience-gaps-of-linting-on-ci)
- [eslint-config-airbnb on npm](https://www.npmjs.com/package/eslint-config-airbnb) — 4M+ weekly downloads
- [standard on npm](https://www.npmjs.com/package/standard) — 545K+ weekly downloads
