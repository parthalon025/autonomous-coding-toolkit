---
description: "Run the full Code Factory pipeline — brainstorm → PRD → plan → execute → verify"
argument-hint: "<feature description or report path>"
---

# Code Factory

Run the full agent-driven development pipeline for: $ARGUMENTS

## Pipeline

This command orchestrates the superpowers skill chain with Code Factory enhancements integrated at each stage. Follow each step in order — do not skip stages.

### Stage 1: Brainstorming
Invoke `superpowers:brainstorming` to explore the idea, ask questions, propose approaches, and produce an approved design doc at `docs/plans/YYYY-MM-DD-<topic>-design.md`.

### Stage 2: PRD Generation
After the design is approved, generate `tasks/prd.json` using the `/create-prd` format:
- 8-15 granular tasks with machine-verifiable acceptance criteria (shell commands)
- Separate investigation tasks from implementation tasks
- Order by dependency
- Save both `tasks/prd.json` and `tasks/prd-<feature>.md`

### Stage 3: Writing Plans
Invoke `superpowers:writing-plans` to create the implementation plan. Enhance the plan with:
- A `## Quality Gates` section listing project checks (auto-detect: pytest, npm test, npm run lint, make test)
- Cross-references to `tasks/prd.json` task IDs
- `progress.txt` initialization as the first step

### Stage 4: Execution
Invoke `superpowers:executing-plans` to execute in batches. Between each batch:
- Run quality gate commands and report results
- Update `tasks/prd.json` — mark passing tasks
- Append batch summary to `progress.txt`
- Fix any failures before proceeding

### Stage 5: Verification
Invoke `superpowers:verification-before-completion`:
- Run ALL `tasks/prd.json` acceptance criteria
- Confirm every task has `"passes": true`
- Show quality gate evidence
- Only claim completion with full evidence

### Stage 6: Finish
Invoke `superpowers:finishing-a-development-branch` to handle commit, PR, or merge.

## Rules

- Never skip a stage. The design must be approved before PRD generation.
- Every acceptance criterion is a shell command. No vague criteria.
- Quality gates run between EVERY batch, not just at the end.
- Progress.txt is append-only during execution — never truncate it.
- If the input is a report file path, run `scripts/analyze-report.sh` first to identify the top priority, then use that as the feature description for brainstorming.
