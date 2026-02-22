#!/usr/bin/env bash
# run-plan-routing.sh — Plan analysis, dependency graph, and execution mode routing
#
# Analyzes plan structure to determine optimal execution mode.
# Builds dependency graphs from Files/context_refs metadata.
#
# Functions:
#   build_dependency_graph <plan_file>              -> JSON {batch: [deps]}
#   compute_parallelism_score <plan_file>           -> 0-100 score
#   recommend_execution_mode <score> <teams_avail> <mem_gb> -> headless|team
#   classify_batch_model <plan_file> <batch_num>    -> sonnet|haiku|opus
#   generate_routing_plan <plan_file> <score> <teams_avail> <mem_gb> <mode> -> printed plan
#   log_routing_decision <worktree> <category> <message>

# --- Configuration ---
PARALLELISM_THRESHOLD_TEAM=40    # Score above this recommends team mode
MIN_MEMORY_TEAM_GB=8             # Minimum memory for team mode
# shellcheck disable=SC2034  # MIN_BATCHES_TEAM reserved for future use
MIN_BATCHES_TEAM=3               # Need at least 3 batches to justify team mode

# --- Sampling configuration ---
# shellcheck disable=SC2034  # consumed by run-plan-headless.sh
SAMPLE_ON_RETRY=true             # auto-sample when batch fails first attempt
# shellcheck disable=SC2034
SAMPLE_ON_CRITICAL=true          # auto-sample for CRITICAL batches
# shellcheck disable=SC2034
SAMPLE_DEFAULT_COUNT=3           # default candidate count
# shellcheck disable=SC2034
SAMPLE_MAX_COUNT=5               # hard cap
# shellcheck disable=SC2034
SAMPLE_MIN_MEMORY_PER_GB=4       # per-candidate memory requirement (GB)

# --- Extract files touched by a batch ---
# Returns lines like "Create:src/lib.sh" or "Modify:src/lib.sh"
_get_batch_files() {
    local plan_file="$1" batch_num="$2"
    local batch_text
    batch_text=$(get_batch_text "$plan_file" "$batch_num")
    echo "$batch_text" | grep -oE '(Create|Modify): `[^`]+`' | sed 's/`//g; s/: /:/g' || true
}

# --- Build dependency graph ---
# Returns JSON: {"1": [], "2": ["1"], "3": ["1"], "4": ["2","3"]}
build_dependency_graph() {
    local plan_file="$1"
    local total
    total=$(count_batches "$plan_file")

    # Phase 1: collect files each batch creates/modifies
    declare -A creates
    declare -A modifies

    for ((b = 1; b <= total; b++)); do
        local files
        files=$(_get_batch_files "$plan_file" "$b")
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local action="${line%%:*}"
            local file="${line#*:}"
            if [[ "$action" == "Create" ]]; then
                creates["$file"]="$b"
            fi
            # Track all batches that touch each file (Create or Modify)
            modifies["$file"]="${modifies[$file]:-} $b"
        done <<< "$files"
    done

    # Phase 2: find dependencies (Create→Modify, Modify→Modify, context_refs)
    local graph="{"
    for ((b = 1; b <= total; b++)); do
        local deps=()

        local files
        files=$(_get_batch_files "$plan_file" "$b")
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local action="${line%%:*}"
            local file="${line#*:}"
            if [[ "$action" == "Modify" ]]; then
                local creator="${creates[$file]:-}"
                if [[ -n "$creator" && "$creator" != "$b" ]]; then
                    deps+=("$creator")
                fi
                local touchers="${modifies[$file]:-}"
                for t in $touchers; do
                    if [[ "$t" -lt "$b" ]]; then
                        deps+=("$t")
                    fi
                done
            fi
        done <<< "$files"

        # Check context_refs
        local refs
        refs=$(get_batch_context_refs "$plan_file" "$b" 2>/dev/null || true)
        while IFS= read -r ref; do
            ref=$(echo "$ref" | xargs)
            [[ -z "$ref" ]] && continue
            local creator="${creates[$ref]:-}"
            if [[ -n "$creator" && "$creator" != "$b" ]]; then
                deps+=("$creator")
            fi
        done <<< "$refs"

        # Deduplicate deps
        local unique_deps=()
        local seen=""
        for d in "${deps[@]+"${deps[@]}"}"; do
            if [[ "$seen" != *"|$d|"* ]]; then
                unique_deps+=("$d")
                seen+="|$d|"
            fi
        done

        # Build JSON array
        local deps_json="[]"
        if [[ ${#unique_deps[@]} -gt 0 ]]; then
            deps_json="["
            for ((i = 0; i < ${#unique_deps[@]}; i++)); do
                [[ $i -gt 0 ]] && deps_json+=","
                deps_json+="\"${unique_deps[$i]}\""
            done
            deps_json+="]"
        fi

        [[ "$b" -gt 1 ]] && graph+=","
        graph+="\"$b\":$deps_json"
    done
    graph+="}"

    echo "$graph"
}

# --- Compute parallelism score (0-100) ---
# Higher = more batches can run in parallel
compute_parallelism_score() {
    local plan_file="$1"
    local total
    total=$(count_batches "$plan_file")

    if [[ "$total" -le 1 ]]; then
        echo "0"
        return
    fi

    local graph
    graph=$(build_dependency_graph "$plan_file")

    # Topological sort into parallel groups
    local completed=""
    local groups=0
    local max_group_size=0
    local remaining="$total"

    while [[ "$remaining" -gt 0 ]]; do
        groups=$((groups + 1))
        local group_size=0
        local new_completed=""

        for ((b = 1; b <= total; b++)); do
            # Skip already completed
            [[ "$completed" == *"|$b|"* ]] && continue

            local deps
            deps=$(echo "$graph" | jq -r ".\"$b\"[]" 2>/dev/null || true)
            local all_met=true
            while IFS= read -r dep; do
                [[ -z "$dep" ]] && continue
                if [[ "$completed" != *"|$dep|"* ]]; then
                    all_met=false
                    break
                fi
            done <<< "$deps"

            if [[ "$all_met" == true ]]; then
                new_completed+="|$b|"
                group_size=$((group_size + 1))
                remaining=$((remaining - 1))
            fi
        done

        completed+="$new_completed"

        if [[ "$group_size" -gt "$max_group_size" ]]; then
            max_group_size=$group_size
        fi

        if [[ "$group_size" -eq 0 ]]; then
            break
        fi
    done

    # Score: weighted parallel_ratio (70%) + group_savings (30%)
    local parallel_ratio=$(( (max_group_size * 100) / total ))
    local denom=$(( total - 1 ))
    [[ "$denom" -lt 1 ]] && denom=1
    local group_savings=$(( (total - groups) * 100 / denom ))
    local score=$(( (parallel_ratio * 7 + group_savings * 3) / 10 ))

    # Clamp to 0-100
    [[ "$score" -gt 100 ]] && score=100
    [[ "$score" -lt 0 ]] && score=0

    echo "$score"
}

# --- Recommend execution mode ---
recommend_execution_mode() {
    local score="$1"
    local teams_available="${2:-false}"
    local available_mem_gb="${3:-0}"

    if [[ "$score" -ge "$PARALLELISM_THRESHOLD_TEAM" && "$available_mem_gb" -ge "$MIN_MEMORY_TEAM_GB" ]]; then
        echo "team"
    else
        echo "headless"
    fi
}

# --- Classify batch model (sonnet/haiku/opus) ---
classify_batch_model() {
    local plan_file="$1" batch_num="$2"
    local batch_text
    batch_text=$(get_batch_text "$plan_file" "$batch_num")

    # Check for Create files — needs implementation skill = sonnet
    if echo "$batch_text" | grep -qE -- '^\*\*Files:\*\*' && echo "$batch_text" | grep -qE -- 'Create:'; then
        echo "sonnet"
        return
    fi

    # Check for Modify files — needs understanding + editing = sonnet
    if echo "$batch_text" | grep -qE -- 'Modify:'; then
        echo "sonnet"
        return
    fi

    # Check if batch is mostly Run commands (verification) = haiku
    local total_steps
    total_steps=$(echo "$batch_text" | grep -cE -- '^\*\*Step [0-9]+' 2>/dev/null || true)
    total_steps=${total_steps:-0}
    local run_steps
    run_steps=$(echo "$batch_text" | grep -cE -- '^Run: ' 2>/dev/null || true)
    run_steps=${run_steps:-0}
    if [[ "$total_steps" -gt 0 && "$run_steps" -ge "$total_steps" ]]; then
        echo "haiku"
        return
    fi

    # Check for CRITICAL tag = opus
    local title
    title=$(get_batch_title "$plan_file" "$batch_num")
    if [[ "$title" == *"CRITICAL"* ]]; then
        echo "opus"
        return
    fi

    # Default: sonnet
    echo "sonnet"
}

# --- Generate human-readable routing plan ---
generate_routing_plan() {
    local plan_file="$1" score="$2" teams_available="$3" mem_gb="$4" current_mode="$5"
    local total
    total=$(count_batches "$plan_file")

    echo ""
    echo "=== Routing Analysis ==="
    echo "  Batches: $total"
    echo "  Parallelism score: $score/100"
    echo "  Teams available: $teams_available"
    echo "  Memory: ${mem_gb}GB"
    echo ""

    # Show dependency graph
    local graph
    graph=$(build_dependency_graph "$plan_file")
    echo "  Dependency graph:"
    for ((b = 1; b <= total; b++)); do
        local deps
        deps=$(echo "$graph" | jq -r ".\"$b\" | join(\",\")" 2>/dev/null || echo "")
        local title
        title=$(get_batch_title "$plan_file" "$b")
        local model
        model=$(classify_batch_model "$plan_file" "$b")
        if [[ -z "$deps" ]]; then
            echo "    Batch $b: $title [$model] (no deps)"
        else
            echo "    Batch $b: $title [$model] (depends on: $deps)"
        fi
    done

    echo ""
    local recommended
    recommended=$(recommend_execution_mode "$score" "$teams_available" "$mem_gb")
    echo "  Recommended mode: $recommended"
    if [[ "$current_mode" != "auto" && "$current_mode" != "$recommended" ]]; then
        echo "  (overridden by --mode $current_mode)"
    fi
}

# --- Routing decision logger ---
log_routing_decision() {
    local worktree="$1" category="$2" message="$3"
    local log_file="$worktree/logs/routing-decisions.log"
    mkdir -p "$(dirname "$log_file")"
    echo "[$(date '+%H:%M:%S')] $category: $message" >> "$log_file"
}
