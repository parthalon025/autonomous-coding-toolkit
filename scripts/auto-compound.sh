#!/usr/bin/env bash
# auto-compound.sh — Automated Code Factory pipeline
#
# Usage: auto-compound.sh <project-dir> [--report <file>] [--dry-run] [--max-iterations N]
#
# Pipeline:
#   1. Analyze report → pick #1 priority (analyze-report.sh)
#   2. Generate PRD → create prd.json with acceptance criteria (claude /create-prd)
#   3. Create branch → compound/<feature-slug>
#   4. Run Ralph loop → iterate until all tasks pass
#   5. Push branch → open PR for review
#
# Requires: claude CLI, jq, gh, ollama

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/ollama.sh"
PROJECT_DIR="${1:-}"
REPORT_FILE=""
DRY_RUN=false
MAX_ITERATIONS=25
MODEL="deepseek-r1:8b"

# Parse args
shift || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --report) REPORT_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
auto-compound.sh — Automated Code Factory pipeline

USAGE:
  auto-compound.sh <project-dir> [OPTIONS]

OPTIONS:
  --report <file>        Path to report file (default: latest in reports/)
  --dry-run              Show what would happen without executing
  --max-iterations <n>   Max Ralph loop iterations (default: 25)
  --model <name>         Ollama model for analysis (default: deepseek-r1:8b)

PIPELINE:
  1. Analyze report → pick #1 priority
  2. Generate PRD with machine-verifiable acceptance criteria
  3. Create feature branch (compound/<slug>)
  4. Run Ralph loop with quality gates
  5. Push and open PR for review

REPORT FORMAT:
  Any markdown file in reports/ with issues, metrics, feedback.
  See scripts/analyze-report.sh for details.
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PROJECT_DIR" ]] || [[ ! -d "$PROJECT_DIR" ]]; then
  echo "Error: Project directory required" >&2
  echo "Usage: auto-compound.sh <project-dir> [--report <file>]" >&2
  exit 1
fi

cd "$PROJECT_DIR"

# Find report file
if [[ -z "$REPORT_FILE" ]]; then
  if [[ -d "reports" ]]; then
    REPORT_FILE=$(find reports/ -name '*.md' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  fi
fi

if [[ -z "$REPORT_FILE" ]] || [[ ! -f "$REPORT_FILE" ]]; then
  echo "Error: No report file found" >&2
  echo "Provide --report <file> or place reports in reports/*.md" >&2
  exit 1
fi

echo "═══════════════════════════════════════════════"
echo "  Code Factory Pipeline"
echo "═══════════════════════════════════════════════"
echo "Project:    $PROJECT_DIR"
echo "Report:     $REPORT_FILE"
echo "Model:      $MODEL"
echo "Max iters:  $MAX_ITERATIONS"
echo "═══════════════════════════════════════════════"
echo ""

# Step 1: Analyze report
echo "📊 Step 1: Analyzing report..."
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] Would analyze $REPORT_FILE with $MODEL"
  PRIORITY="example-feature"
  FEATURE_SLUG="example-feature"
else
  "$SCRIPT_DIR/analyze-report.sh" "$REPORT_FILE" --model "$MODEL" --output-dir .
  PRIORITY=$(jq -r '.priority' analysis.json)
  # Create slug from priority
  FEATURE_SLUG=$(echo "$PRIORITY" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-40)
fi
echo "  Priority: $PRIORITY"
echo "  Branch:   compound/$FEATURE_SLUG"
echo ""

# Step 2: Create branch
echo "🌿 Step 2: Creating branch..."
BRANCH_NAME="compound/$FEATURE_SLUG"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] Would create branch: $BRANCH_NAME"
else
  git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"
fi
echo ""

# Step 2.5: Prior art search
echo "🔎 Step 2.5: Searching for prior art..."
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] Would search: $PRIORITY"
else
  PRIOR_ART=$("$SCRIPT_DIR/prior-art-search.sh" "$PRIORITY" 2>&1 || true)
  echo "$PRIOR_ART" | head -20
  # Save for PRD context
  echo "$PRIOR_ART" > prior-art-results.txt
  echo "  Saved to prior-art-results.txt"

  # Append to progress.txt
  echo "## Prior Art Search: $PRIORITY" >> progress.txt
  echo "$PRIOR_ART" | head -10 >> progress.txt
  echo "" >> progress.txt
fi
echo ""

# Step 3: Generate PRD
echo "📋 Step 3: Generating PRD..."
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] Would run: claude '/create-prd $PRIORITY'"
  echo "  [dry-run] Would create tasks/prd.json"
else
  mkdir -p tasks
  # Include prior art if available
  prior_art_context=""
  if [[ -f "prior-art-results.txt" ]]; then
      prior_art_context=" Prior art found: $(head -20 prior-art-results.txt)"
  fi
  # Use Claude to generate the PRD
  prd_output=$(claude --print "/create-prd $PRIORITY. Context from analysis: $(cat analysis.json).$prior_art_context" 2>&1) || {
      echo "WARNING: PRD generation failed:" >&2
      echo "$prd_output" | tail -10 >&2
  }

  if [[ ! -f "tasks/prd.json" ]]; then
    echo "Warning: PRD generation didn't create tasks/prd.json" >&2
    echo "You may need to run /create-prd manually" >&2
  fi
fi
echo ""

# Step 4: Configure quality checks
echo "🔍 Step 4: Configuring quality checks..."
QUALITY_GATE="$SCRIPT_DIR/quality-gate.sh"
if [[ -x "$QUALITY_GATE" ]]; then
  QUALITY_CHECKS="$QUALITY_GATE --project-root $PROJECT_DIR"
  echo "  Using composite quality gate: $QUALITY_GATE"
else
  # Fallback: use detect_project_type if quality-gate.sh not available
  project_type=$(detect_project_type "$PROJECT_DIR")
  case "$project_type" in
    python)  QUALITY_CHECKS="pytest --timeout=120 -x -q" ;;
    node)
      QUALITY_CHECKS=""
      grep -q '"test"' package.json 2>/dev/null && QUALITY_CHECKS+="npm test"
      grep -q '"lint"' package.json 2>/dev/null && { [[ -n "$QUALITY_CHECKS" ]] && QUALITY_CHECKS+=";"; QUALITY_CHECKS+="npm run lint"; }
      ;;
    make)    QUALITY_CHECKS="make test" ;;
    *)       QUALITY_CHECKS="" ;;
  esac
  echo "  Fallback mode — quality-gate.sh not found"
fi

echo "  Quality checks: ${QUALITY_CHECKS:-none detected}"
echo ""

# Step 5: Run Ralph loop
echo "🔄 Step 5: Starting Ralph loop..."
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] Would run Ralph loop with:"
  echo "    --max-iterations $MAX_ITERATIONS"
  echo "    --quality-checks '$QUALITY_CHECKS'"
  echo "    --prd tasks/prd.json"
  echo "    --completion-promise 'ALL TASKS COMPLETE'"
else
  RALPH_ARGS="Implement the features in tasks/prd.json. Read prd.json, pick the next task where passes is false, implement it, verify acceptance criteria pass, update prd.json, commit, and move to the next task."
  RALPH_ARGS+=" --max-iterations $MAX_ITERATIONS"
  RALPH_ARGS+=" --completion-promise 'ALL TASKS COMPLETE'"

  if [[ -n "$QUALITY_CHECKS" ]]; then
    RALPH_ARGS+=" --quality-checks '$QUALITY_CHECKS'"
  fi

  if [[ -f "tasks/prd.json" ]]; then
    RALPH_ARGS+=" --prd tasks/prd.json"
  fi

  echo "  Running: /ralph-loop $RALPH_ARGS"
  echo ""
  echo "  Monitor progress:"
  echo "    head -15 .claude/ralph-loop.local.md"
  echo "    cat progress.txt"
  echo "    jq '.[].passes' tasks/prd.json"
  echo ""

  # Launch Claude with Ralph loop
  claude "/ralph-loop $RALPH_ARGS"
fi
echo ""

# Step 6: Push and create PR
echo "📤 Step 6: Pushing and creating PR..."
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] Would push $BRANCH_NAME and create PR"
else
  git push -u origin "$BRANCH_NAME" 2>/dev/null || true

  # Create PR
  PR_BODY="## Summary
Auto-generated by Code Factory pipeline.

**Priority:** $PRIORITY
**Analysis:** See analysis.json
**Tasks:** See tasks/prd.json

## Quality Checks
$QUALITY_CHECKS

## Generated by
\`auto-compound.sh\` → \`analyze-report.sh\` → \`/create-prd\` → \`/ralph-loop\`"

  gh pr create --title "compound: $PRIORITY" --body "$PR_BODY" 2>/dev/null || echo "PR creation skipped (may already exist)"
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "  Pipeline complete!"
echo "═══════════════════════════════════════════════"
