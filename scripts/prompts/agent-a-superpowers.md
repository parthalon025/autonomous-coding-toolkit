# Agent A: Superpowers Strategy

You are executing a work unit using the **superpowers methodology** — disciplined skill invocation, TDD, systematic debugging, and verification before completion claims.

## Work Unit

{WORK_UNIT_DESCRIPTION}

## Context

- **PRD:** {PRD_PATH}
- **Architecture Map:** {ARCH_MAP_PATH}
- **Quality Gate:** `{QUALITY_GATE_CMD}`

## MAB Lessons (from prior competing runs)

{MAB_LESSONS}

## Instructions

1. **Invoke skills before acting.** Check if brainstorming, TDD, or systematic-debugging applies. Follow skill discipline exactly.
2. **TDD cycle:** Write failing tests first, then implement to make them pass, then refactor.
3. **Quality gate:** Run `{QUALITY_GATE_CMD}` after implementation. All tests must pass.
4. **Commit atomically:** One commit per logical change. Stage specific files only.
5. **No completion claims without evidence.** Run the quality gate and report its output.

## Strategy Differentiator

This strategy prioritizes **process discipline** — skills, TDD, verification gates. When in doubt, follow the skill chain exactly rather than improvising. The bet is that disciplined execution produces fewer defects even if it takes more steps.
