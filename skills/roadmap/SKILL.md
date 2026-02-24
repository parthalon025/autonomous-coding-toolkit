---
name: roadmap
description: "Decompose a multi-feature epic into a dependency-ordered, phased roadmap with effort estimates."
version: 1.0.0
---

# Roadmap — Multi-Feature Decomposition

## Overview

When the input to `/autocode` is a multi-feature epic (3+ distinct features or the keyword "roadmap"), this skill decomposes it into an ordered sequence of features, each ready for brainstorming as a standalone unit.

<HARD-GATE>
Do NOT brainstorm individual features until the roadmap is approved. Feature ordering determines dependency flow — changing order mid-execution causes rework.
</HARD-GATE>

## When to Use

- Input contains 3+ distinct features
- Input uses "roadmap", "epic", or "multi-feature" keywords
- Input references a large body of work spanning multiple PRs

Skip this stage when:
- Input is a single feature (even a complex one — brainstorming handles that)
- Input is a bug fix or small enhancement

## Process

### Step 1: Extract Features

Read the input and identify distinct features. Each feature must be:
- **Independent enough** to be brainstormed, PRD'd, and implemented as a standalone unit
- **Ordered by dependency** — if Feature B needs Feature A's output, A comes first
- **Sized for 1-3 sessions** — if a feature takes more, it's an epic, not a feature; decompose further

### Step 2: Identify Dependencies

For each pair of features, determine:
- **Hard dependency** — B cannot start until A is merged (shared interfaces, schema changes)
- **Soft dependency** — B benefits from A being done first (shared patterns, learning)
- **Independent** — no relationship

### Step 3: Order and Phase

Group features into phases based on dependencies:

| Phase | Features | Why this order |
|-------|----------|---------------|
| 1 | Foundation features | No dependencies, enable later work |
| 2 | Dependent features | Require Phase 1 outputs |
| 3 | Polish features | Require Phase 1+2, add refinement |

### Step 4: Estimate Effort

For each feature, estimate:
- **Complexity** — simple (1 batch) / moderate (2-3 batches) / complex (4+ batches)
- **Risk** — low / medium / high (based on unknowns, integration surface, external deps)

### Step 5: Produce Artifact

Write `tasks/roadmap.md` with this structure:

```markdown
# Roadmap: <Epic Title>

Generated: YYYY-MM-DD

## Features (dependency order)

### Phase 1: <Phase Name>
| # | Feature | Complexity | Risk | Dependencies |
|---|---------|-----------|------|-------------|
| 1 | Feature A | moderate | low | none |
| 2 | Feature B | simple | low | none |

### Phase 2: <Phase Name>
| # | Feature | Complexity | Risk | Dependencies |
|---|---------|-----------|------|-------------|
| 3 | Feature C | complex | medium | #1 |

## Dependency Graph
1 → 3
2 (independent)

## Total Estimate
- Features: N
- Phases: M
- Estimated sessions: X-Y
```

### Step 6: Get Approval

Present the roadmap to the user. Ask:
- **"Does this feature ordering make sense?"**
- **"Should any features be cut, combined, or reordered?"**

Minimum 1 round of refinement before proceeding.

**Exit criteria:** `tasks/roadmap.md` exists, user approves feature ordering.

## After Approval

The autocode pipeline loops through features in roadmap order:
1. Pick next feature from roadmap
2. Run Stage 1 (Brainstorm) through Stage 6 (Finish) for that feature
3. Mark feature complete in roadmap
4. Repeat until all features done

Each feature gets its own branch, PRD, plan, and verification cycle.

## Integration

**Called by:** `autocode` skill (Stage 0.5, conditional)
**Produces:** `tasks/roadmap.md`
**Consumed by:** `autocode` pipeline (iterates features in order)
