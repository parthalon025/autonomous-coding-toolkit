---
name: research
description: "Structured investigation between brainstorming and PRD. Produces durable research artifacts that inform implementation decisions."
version: 1.0.0
---

# Research — Structured Investigation Protocol

## Overview

Research fills the gap between design intent (brainstorming) and technical specification (PRD). It investigates existing code, external libraries, potential blockers, and implementation options before committing to an approach.

**When to invoke:** After brainstorming produces an approved design, before PRD generation.

## Inputs

- Approved design doc from brainstorming (e.g., `docs/plans/YYYY-MM-DD-<topic>-design.md`)
- Feature description or scope from the user

## Steps

### Step 1: Extract Research Questions

Read the design doc and identify:
- Technical unknowns ("does library X support feature Y?")
- Existing code dependencies ("what module handles auth today?")
- Integration points ("what interface does the consumer expect?")
- Performance constraints ("can we process N items in M seconds?")

List 3-8 concrete research questions.

### Step 2: Search Existing Code

For each question about the current codebase:
- Use Grep/Glob to find relevant files and patterns
- Read key files to understand current implementations
- Document: file paths, function signatures, data structures

### Step 3: Search Documentation

For each question about libraries or frameworks:
- Check project docs (README, ARCHITECTURE.md, CLAUDE.md)
- Search for existing patterns in the codebase
- Check docs/lessons/ for relevant lessons

### Step 4: External Research

For each question requiring external knowledge:
- Search for library documentation, API references
- Look for known issues, migration guides, compatibility notes
- Document version constraints and breaking changes

### Step 5: Identify Blockers

Categorize findings as:
- **Blocking:** Cannot proceed without resolving (missing dependency, incompatible API, no viable approach)
- **Warning:** Proceed with caution (deprecated API, performance concern, partial support)
- **Dependency:** Requires work in another module/project first

### Step 6: Synthesize Findings

Write a human-readable summary with:
- Answer to each research question
- Recommended approach (with confidence level: high/medium/low)
- Blocking issues and proposed resolutions
- Warnings that the PRD should account for

### Step 7: Produce Artifacts

Create two files:

**`tasks/research-<slug>.md`** — Human-readable research report:
```markdown
# Research: <Feature Name>

## Questions Investigated
1. <question> — <answer summary>
...

## Recommended Approach
<1-2 paragraphs with confidence level>

## Blocking Issues
- [ ] <issue> — <proposed resolution>

## Warnings
- <warning that PRD should account for>

## Dependencies
- <module/project that needs work first>

## Evidence
- <file:line references, documentation links>
```

**`tasks/research-<slug>.json`** — Machine-readable for pipeline consumption:
```json
{
  "feature": "<name>",
  "timestamp": "<ISO 8601>",
  "questions": ["<q1>", "<q2>"],
  "blocking_issues": [
    {"issue": "<description>", "resolved": false, "resolution": "<proposed>"}
  ],
  "warnings": ["<w1>", "<w2>"],
  "dependencies": ["<dep1>"],
  "confidence_ratings": {
    "approach": "high|medium|low",
    "effort_estimate": "high|medium|low"
  },
  "recommended_approach": "<summary>"
}
```

### Step 8: Gate Check

If any `blocking_issues` have `resolved: false`:
- Present them to the user
- Wait for resolution or override
- Do NOT proceed to PRD with unresolved blockers

### Step 9: Update Progress

Append research summary to `progress.txt`.

### Step 10: Handoff

Pass `tasks/research-<slug>.json` to PRD generation. The PRD should:
- Account for all warnings
- Include tasks that resolve blocking issues
- Reference research findings in acceptance criteria

## Exit Criteria

- `tasks/research-<slug>.md` exists with all sections
- `tasks/research-<slug>.json` is valid JSON with all required fields
- All blocking issues are resolved OR user has explicitly overridden
- `progress.txt` updated with research summary

## Rules

- **Always make a file.** Research that exists only in conversation is lost on context reset.
- **Cite evidence.** Every finding should reference a specific file:line, documentation URL, or command output.
- **Confidence levels are mandatory.** Express high/medium/low confidence on every recommendation.
- **Don't over-research.** 30-60 minutes maximum. If a question can't be answered in that time, flag it as a blocking issue for the user.
