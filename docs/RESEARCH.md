# Research

Evidence base for the Autonomous Coding Toolkit's design decisions. Each report synthesizes peer-reviewed papers, benchmarks, and field observations into actionable findings.

## Core Design Research

These directly shaped the toolkit's architecture:

| Topic | Key Finding | Report |
|-------|-------------|--------|
| Plan quality | Plan quality dominates execution quality ~3:1 (SWE-bench Pro) | [Plan Quality](plans/2026-02-22-research-plan-quality.md) |
| Context degradation | 11/12 models < 50% accuracy at 32K tokens; mid-context loss up to 20pp | [Context Utilization](plans/2026-02-22-research-context-utilization.md) |
| Agent failures | Spec misunderstanding is the dominant failure mode (~60%), not code quality | [Agent Failure Taxonomy](plans/2026-02-22-research-agent-failure-taxonomy.md) |
| Verification | Property-based testing finds ~50x more mutations per test than unit tests | [Verification Effectiveness](plans/2026-02-22-research-verification-effectiveness.md) |
| Prompt engineering | Positive instructions outperform negative; context placement matters | [Prompt Engineering](plans/2026-02-22-research-prompt-engineering.md) |
| Lesson transferability | Anti-pattern lessons generalize across projects with scope metadata | [Lesson Transferability](plans/2026-02-22-research-lesson-transferability.md) |

## Competitive & Adoption Research

| Topic | Report |
|-------|--------|
| Competitive landscape (Aider, Cursor, SWE-agent, etc.) | [Competitive Landscape](plans/2026-02-22-research-competitive-landscape.md) |
| User adoption friction and onboarding | [User Adoption](plans/2026-02-22-research-user-adoption.md) |
| Cost/quality tradeoff modeling | [Cost-Quality Tradeoff](plans/2026-02-22-research-cost-quality-tradeoff.md) |

## Implementation Research

| Topic | Report |
|-------|--------|
| Testing strategies for large full-stack projects | [Comprehensive Testing](plans/2026-02-22-research-comprehensive-testing.md) |
| Multi-agent coordination patterns | [Multi-Agent Coordination](plans/2026-02-22-research-multi-agent-coordination.md) |
| Codebase auditing and refactoring with AI | [Codebase Audit](plans/2026-02-22-research-codebase-audit-refactoring.md) |
| Code guideline policies for AI agents | [Code Guidelines](plans/2026-02-22-research-code-guideline-policies.md) |
| Coding standards and AI agent performance | [Coding Standards](plans/2026-02-22-research-coding-standards-documentation.md) |
| Research phase integration into pipelines | [Phase Integration](plans/2026-02-22-research-phase-integration.md) |

## Advanced Topics

| Topic | Report |
|-------|--------|
| Multi-Armed Bandit strategy selection | [MAB Report](plans/2026-02-21-mab-research-report.md), [Round 2](plans/2026-02-22-mab-research-round2.md) |
| Operations design methodology (18 cross-domain frameworks) | [Operations Design](plans/2026-02-22-operations-design-methodology-research.md) |
| Unconventional perspectives on autonomous coding | [Unconventional Perspectives](plans/2026-02-22-research-unconventional-perspectives.md) |

## Key Papers Referenced

The most-cited papers across the research corpus:

1. **SWE-bench Pro** (Xia et al., 2025) — 1,865 programming problems; spec removal = 3x degradation
2. **Chroma** (Hong et al., 2025) — Long-context coding benchmark; 11/12 models < 50% at 32K
3. **Lost in the Middle** (Liu et al., Stanford TACL 2024) — Up to 20pp accuracy loss for mid-context information
4. **OOPSLA 2025** — Property-based testing mutation analysis
5. **Cooper Stage-Gate** — Projects with stable definitions are 3x more likely to succeed

Full citation details are in each individual report.
