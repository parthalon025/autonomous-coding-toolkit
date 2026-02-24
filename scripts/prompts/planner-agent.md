# Planner Agent: Routing Reference

> **NOTE:** This file is reference documentation only. The actual routing logic is
> implemented in `scripts/lib/thompson-sampling.sh` using Thompson Sampling —
> not an LLM planner.

## How Routing Works

The MAB system uses **Thompson Sampling** (a Bayesian multi-armed bandit algorithm)
to decide whether each batch runs in competing mode (both strategies) or uses a
known winner (single strategy).

### Decision Flow

1. **Check data sufficiency:** If fewer than 5 data points per strategy for this
   batch type, always run competing (`"mab"`).
2. **Check batch type:** `integration` batches always run competing (too variable
   for confident routing).
3. **Check win rate spread:** If the gap between strategies is < 15%, run competing
   (too close to call).
4. **Check for clear winner:** If one strategy has ≥ 70% win rate with 10+ data
   points, route directly to that strategy.
5. **Thompson Sample:** Draw from Beta(wins+1, losses+1) for each strategy.
   Higher sample wins the route.

### Batch Types

| Type | Description | Routing Behavior |
|------|-------------|-----------------|
| `new-file` | Creating new files from scratch | Normal Thompson routing |
| `refactoring` | Modifying existing code | Normal Thompson routing |
| `integration` | Connecting components | Always competing (high variance) |
| `test-only` | Only running/adding tests | Normal Thompson routing |

### Data Storage

- `logs/strategy-perf.json` — Win/loss counters per strategy per batch type
- `logs/mab-lessons.json` — Patterns observed by the judge agent

### Human Calibration

The first 10 competing runs prompt for human override (if stdin is a tty).
This calibrates the system before it runs fully autonomously.
After `calibration_complete: true`, the system trusts its own routing.
