# Lessons Learned Framework

Synthesized from three methodologies adapted for personal infrastructure and AI system development.

## Source Frameworks

| Framework | Contribution | Reference |
|-----------|-------------|-----------|
| **Army CALL OIL** | Maturity taxonomy (Observation → Insight → Lesson → Lesson Learned) | CALL Handbook 11-33 |
| **PMI PMBOK** | Structured register (category, root cause, corrective action, keywords) | PMI Lessons Learned Register |
| **Lean Six Sigma** | Analysis tools (5 Whys, Fishbone 6M, A3 format, DMAIC phases) | LSS Green Belt (Notion: Tri-County LEAN Six Sigma Made EZ) |

## OIL Maturity Taxonomy

Not every finding is a "lesson learned." The Army's OIL taxonomy provides a promotion path:

### Tier 1: Observation
**"What happened."** Raw conditions, symptoms, and facts from an incident.
- Requires: Date, system, files involved, factual description
- Example: "Intraday snapshots showed entities.total: 0 despite 14,392 logbook events"
- Status: `observed`

### Tier 2: Insight
**"What it means."** Analysis connecting observation to root cause. Uses 5 Whys or Fishbone to dig below symptoms.
- Requires: Root cause identified, impact assessed, "why" chain documented
- Example: "Decorator-based collector registry was never imported, so CollectorRegistry.all() returned empty dict"
- Status: `analyzed`

### Tier 3: Lesson
**"What to do about it."** Proposed corrective action — specific, implementable, testable.
- Requires: Corrective action described, preventive measure proposed, owner identified
- Example: "Add integration test verifying collector count >= 15; add import comment pattern to all decorator registries"
- Status: `proposed`

### Tier 4: Lesson Learned
**"Validated behavioral change."** The corrective action has been implemented, tested, AND confirmed to prevent recurrence. This is the highest tier — most entries won't reach it immediately.
- Requires: Implementation proof (commit, test, config change), validation evidence, sustain plan
- Example: "Test added (commit abc123), collector count assertion catches this class of bug. No recurrence in 30 days."
- Status: `validated`

**Key distinction:** A lesson is *proposed*. A lesson learned is *proven*. Most entries start as Tier 1-2 and promote over time.

## Lesson Structure (A3-Inspired)

Each lesson follows a compressed A3 format — the same one-page problem-solution structure from the Green Belt coursework, adapted for technical lessons:

```
# Lesson: [Title]

**Date:** YYYY-MM-DD
**System:** [Project name]
**Tier:** observation | insight | lesson | lesson_learned
**Category:** [See categories below]
**Keywords:** [comma-separated for retrieval]
**Files:** [affected files]

## Observation (What Happened)
[Factual description of the incident/discovery. Include data contradictions.]

## Analysis (Root Cause — 5 Whys)
Why #1: [surface cause]
Why #2: [deeper cause]
Why #3: [root cause — stop at the deepest controllable cause]

## Corrective Actions
| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | [specific action] | proposed/implemented/validated | [who] | [commit/test/config] |

## Ripple Effects
[What other systems/services/pipelines does this touch?]

## Sustain Plan
- [ ] 7-day check: [what to verify]
- [ ] 30-day check: [confirm no recurrence]
- [ ] Contingency: [if corrective action doesn't hold]

## Key Takeaway
[One sentence. The thing you'd tell someone in 10 seconds.]
```

## Categories

Aligned to the system hierarchy — when searching for patterns, filter by category:

| Category | Scope | Examples |
|----------|-------|---------|
| `data-model` | Schema, inheritance, data flow assumptions | HA entity→device→area chain |
| `registration` | Module loading, decorator patterns, import side effects | Collector registry empty |
| `cold-start` | First-run behavior, missing baselines, graceful degradation | Predictions 0 for missing weekday |
| `integration` | Cross-service dependencies, shared state, API contracts | Engine↔Hub JSON schema coupling |
| `deployment` | Service config, systemd, env vars, restart behavior | ~/.env export syntax |
| `monitoring` | Alert logic, noise suppression, false positives, staleness | Stuck sensor alerts |
| `ui` | Frontend assumptions, data display, user-facing bugs | Area counts showing 0 |
| `testing` | Coverage gaps, mock masking, smoke tests | Mocked collectors hiding registration bug |
| `performance` | Resource contention, memory, Ollama scheduling | Timer deconfliction |
| `security` | Auth, secrets, permissions | Credential exposure |

## Analysis Tools

### 5 Whys (Primary)
Use for most lessons. Stop at the deepest **controllable** root cause.

### Fishbone / 6M (Complex Issues)
When 5 Whys branches into multiple causes, use the 6M categories adapted for infrastructure:
- **Method:** Process/workflow gap (no smoke test after refactor)
- **Machine:** System/service failure (Ollama contention, OOM)
- **Material:** Data quality (stale cache, missing baselines)
- **Manpower:** Knowledge gap (didn't know HA inheritance model)
- **Management:** Process gap (no review step, no sustain plan)
- **Mother Nature:** External factor (upstream API change, network)

### Pareto Principle
When reviewing lessons over time: **most frequent category ≠ most impactful category.** Track both. Optimize for impact, not frequency.

## Lifecycle & Promotion

```
observed → analyzed → proposed → validated
   ↑          ↑          ↑          ↑
 Incident   5 Whys    Action     Proof +
  logged    done      defined    30-day
                                 sustain
```

**Promotion criteria:**
- `observed → analyzed`: Root cause identified via 5 Whys or Fishbone
- `analyzed → proposed`: Corrective action defined with owner and timeline
- `proposed → validated`: Action implemented + evidence of behavioral change (test passing, config applied, no recurrence for 30 days)

**Review cadence:** Check `proposed` items monthly. If no action in 60 days, either implement or archive with reason.

## Connecting to MEMORY.md

MEMORY.md carries **one-line summaries** pointing to full lesson files:

```markdown
## Lessons Learned
- `docs/lessons/2026-02-14-area-entity-resolution.md` — HA entity→device→area chain [lesson_learned]
- `docs/lessons/2026-02-14-collector-registration.md` — Decorator registries need explicit imports [lesson]
```

The `[tier]` tag shows maturity at a glance. Update when tier changes.

## Cross-Framework Mapping

For career transition context — how these frameworks translate:

| Military | LSS | PMI | This System |
|----------|-----|-----|-------------|
| AAR (After Action Review) | Kaizen session | Retrospective | Lesson file creation |
| MDMP (Military Decision Making) | DMAIC | Planning process | Plan docs in docs/plans/ |
| OPORD | A3 Report | Project charter | CLAUDE.md + plan doc |
| IPB | VSM + SIPOC | Stakeholder analysis | System audit (/ha-audit, /status) |
| F3EAD cycle | PDCA cycle | Monitor & Control | Counter system (/counter, /check, /reflect) |

## File Naming

`docs/lessons/YYYY-MM-DD-short-description.md`

One lesson per file. If an incident produces multiple independent lessons, split them.
