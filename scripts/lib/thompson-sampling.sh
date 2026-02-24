#!/usr/bin/env bash
# thompson-sampling.sh — Thompson Sampling for MAB strategy routing
#
# Functions:
#   thompson_sample <wins> <losses>          — Beta approximation, returns float [0,1]
#   thompson_route <batch_type> <perf_file>  — Returns "superpowers"|"ralph"|"mab"
#   init_strategy_perf <file>                — Creates JSON with 4 batch types + calibration
#   update_strategy_perf <file> <batch_type> <winner_strategy>  — Increments counters
#
# Routing logic:
#   - Missing file or < 5 points per strategy → "mab" (compete)
#   - integration batch type → always "mab" (most variable)
#   - Win rate spread < 15% → "mab" (too close to call)
#   - Clear winner (≥70%, 10+ points) → return strategy name
#   - Otherwise → Thompson sample both, return higher sample

# Thompson sample from Beta(alpha, beta) using Box-Muller approximation.
# For Beta(a,b) with a,b > 1, a good approximation is:
#   mean = a/(a+b), variance = ab/((a+b)^2*(a+b+1))
#   sample ≈ mean + sqrt(variance) * normal_noise
# Clamped to [0.01, 0.99] to avoid degenerate values.
#
# Args: <wins> <losses>
# Output: float in [0,1]
thompson_sample() {
    local wins="${1:-0}" losses="${2:-0}"
    local alpha=$((wins + 1))
    local beta=$((losses + 1))

    # Use central limit theorem for a pseudo-normal: sum 12 uniform [0,1), subtract 6 → approx N(0,1).
    # Seed with bash $RANDOM + PID — PROCINFO["pid"] is gawk-only, mawk silently ignores it,
    # producing identical samples within the same second (kills Thompson Sampling).
    local noise
    noise=$(awk -v seed="$((RANDOM + $$))" 'BEGIN {
        srand(systime() * 1000 + seed);
        s = 0;
        for (i = 0; i < 12; i++) s += rand();
        printf "%.6f", s - 6;
    }' 2>/dev/null || echo "0")

    # Compute Beta sample approximation
    bc -l <<EOF
scale=6
a = $alpha
b = $beta
mean = a / (a + b)
var = (a * b) / ((a + b) * (a + b) * (a + b + 1))
sd = sqrt(var)
sample = mean + sd * $noise
if (sample < 0.01) sample = 0.01
if (sample > 0.99) sample = 0.99
sample
EOF
}

# Route a batch type to a strategy or "mab" (compete).
#
# Args: <batch_type> <perf_file>
# Output: "superpowers" | "ralph" | "mab"
thompson_route() {
    local batch_type="$1"
    local perf_file="$2"

    # Missing file → compete
    if [[ ! -f "$perf_file" ]]; then
        echo "mab"
        return
    fi

    # Integration → always compete (most variable)
    if [[ "$batch_type" == "integration" ]]; then
        echo "mab"
        return
    fi

    # Read strategy data
    local sp_wins sp_losses ralph_wins ralph_losses
    sp_wins=$(jq -r --arg bt "$batch_type" '.[$bt].superpowers.wins // 0' "$perf_file" 2>/dev/null || echo "0")
    sp_losses=$(jq -r --arg bt "$batch_type" '.[$bt].superpowers.losses // 0' "$perf_file" 2>/dev/null || echo "0")
    ralph_wins=$(jq -r --arg bt "$batch_type" '.[$bt].ralph.wins // 0' "$perf_file" 2>/dev/null || echo "0")
    ralph_losses=$(jq -r --arg bt "$batch_type" '.[$bt].ralph.losses // 0' "$perf_file" 2>/dev/null || echo "0")

    local sp_total=$((sp_wins + sp_losses))
    local ralph_total=$((ralph_wins + ralph_losses))

    # < 5 data points per strategy → compete
    if [[ "$sp_total" -lt 5 || "$ralph_total" -lt 5 ]]; then
        echo "mab"
        return
    fi

    # Compute win rates
    local sp_rate ralph_rate spread
    sp_rate=$(echo "scale=2; $sp_wins * 100 / $sp_total" | bc -l)
    ralph_rate=$(echo "scale=2; $ralph_wins * 100 / $ralph_total" | bc -l)

    # Spread check (< 15% → too close)
    spread=$(echo "scale=2; x=$sp_rate - $ralph_rate; if (x < 0) -x else x" | bc -l)
    local spread_too_close
    spread_too_close=$(echo "$spread < 15" | bc -l)
    if [[ "$spread_too_close" == "1" ]]; then
        echo "mab"
        return
    fi

    # Clear winner check (≥70%, 10+ points)
    local sp_clear ralph_clear
    sp_clear=$(echo "$sp_rate >= 70" | bc -l)
    ralph_clear=$(echo "$ralph_rate >= 70" | bc -l)

    if [[ "$sp_clear" == "1" && "$sp_total" -ge 10 ]]; then
        echo "superpowers"
        return
    fi
    if [[ "$ralph_clear" == "1" && "$ralph_total" -ge 10 ]]; then
        echo "ralph"
        return
    fi

    # Thompson sample both — higher sample wins
    local sp_sample ralph_sample
    sp_sample=$(thompson_sample "$sp_wins" "$sp_losses")
    ralph_sample=$(thompson_sample "$ralph_wins" "$ralph_losses")

    local sp_higher
    sp_higher=$(echo "$sp_sample > $ralph_sample" | bc -l)
    if [[ "$sp_higher" == "1" ]]; then
        echo "superpowers"
    else
        echo "ralph"
    fi
}

# Initialize strategy performance file with zero counters.
#
# Args: <file>
init_strategy_perf() {
    local file="$1"
    mkdir -p "$(dirname "$file")"
    cat > "$file" <<'JSON'
{
  "new-file": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "refactoring": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "integration": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "test-only": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "calibration_count": 0,
  "calibration_complete": false
}
JSON
}

# Update strategy performance after a MAB run.
# Winner gets +1 win, loser gets +1 loss.
#
# Args: <file> <batch_type> <winner_strategy>
update_strategy_perf() {
    local file="$1" batch_type="$2" winner="$3"

    if [[ ! -f "$file" ]]; then
        init_strategy_perf "$file"
    fi

    local loser
    if [[ "$winner" == "superpowers" ]]; then
        loser="ralph"
    else
        loser="superpowers"
    fi

    local tmp
    tmp=$(mktemp)
    jq --arg bt "$batch_type" --arg w "$winner" --arg l "$loser" '
        .[$bt][$w].wins += 1 |
        .[$bt][$l].losses += 1
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}
