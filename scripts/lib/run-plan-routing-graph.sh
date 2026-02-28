#!/usr/bin/env bash
# run-plan-routing-graph.sh — Dependency graph building and parallelism scoring
#
# Functions:
#   _get_batch_files <plan_file> <batch_num>      -> "Action:file" lines
#   build_dependency_graph <plan_file>            -> JSON {batch: [deps]}
#   compute_parallelism_score <plan_file>         -> 0-100 score
#
# Requires: count_batches, get_batch_text, get_batch_context_refs from run-plan-parser.sh

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
            deps=$(echo "$graph" | timeout 30 jq -r ".\"$b\"[]" 2>/dev/null) || {
                [[ $? -eq 124 ]] && echo "[WARN] jq timeout on batch $b — treating as no deps" >&2
                deps=""
            }
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
