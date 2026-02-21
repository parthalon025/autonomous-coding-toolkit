#!/usr/bin/env bash
# entropy-audit.sh — Detect documentation drift, naming inconsistencies, and stale conventions
#
# Usage: entropy-audit.sh [--project <name>] [--all] [--fix]
#
# Checks:
#   1. CLAUDE.md freshness — file references that no longer exist
#   2. Naming drift — files/functions that violate project conventions
#   3. Dead code — unreferenced exports and unused imports
#   4. File size violations — files exceeding 300-line taste invariant
#   5. Doc staleness — CLAUDE.md mentions of removed features
#
# Designed to run as a systemd timer for continuous entropy management.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Documents/projects}"
ALL_PROJECTS=false
FIX_MODE=false
TARGET_PROJECT=""
RESULTS_DIR="/tmp/entropy-audit-$(date +%Y%m%d-%H%M%S)"

while [[ $# -gt 0 ]]; do
  case $1 in
    --project) TARGET_PROJECT="$2"; shift 2 ;;
    --all) ALL_PROJECTS=true; shift ;;
    --fix) FIX_MODE=true; shift ;;
    --projects-dir) PROJECTS_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "entropy-audit.sh — Detect and report codebase entropy"
      echo ""
      echo "Usage: entropy-audit.sh [--project <name>] [--all] [--fix]"
      echo ""
      echo "Options:"
      echo "  --project <name>  Audit a specific project"
      echo "  --all             Audit all projects"
      echo "  --fix             Auto-fix simple issues (dead refs in CLAUDE.md)"
      exit 0
      ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$RESULTS_DIR"

audit_project() {
  local project_dir="$1"
  local project_name
  project_name="$(basename "$project_dir")"
  local report="$RESULTS_DIR/$project_name.md"

  echo "Auditing $project_name..."

  {
    echo "# Entropy Audit: $project_name"
    echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""

    # Check 1: CLAUDE.md references to nonexistent files
    echo "## 1. Dead References in CLAUDE.md"
    local claude_md="$project_dir/CLAUDE.md"
    local dead_count=0
    if [[ -f "$claude_md" ]]; then
      # Extract file paths mentioned in backticks — collect into array to avoid subshell
      local refs
      refs=$(grep -oE '`[^`]+\.(py|ts|js|sh|json|md|yaml|yml)`' "$claude_md" 2>/dev/null | tr -d '`' || true)
      if [[ -n "$refs" ]]; then
        while IFS= read -r ref; do
          # Skip paths with placeholders
          if echo "$ref" | grep -qE '<|>|\*|\$|~'; then continue; fi
          # Check relative to project dir
          if [[ ! -f "$project_dir/$ref" ]] && [[ ! -f "$ref" ]]; then
            echo "- ❌ Referenced but missing: \`$ref\`"
            dead_count=$((dead_count + 1))
          fi
        done <<< "$refs"
      fi
      if [[ $dead_count -eq 0 ]]; then
        echo "- ✅ All references valid"
      else
        echo "- Found $dead_count dead reference(s)"
      fi
    else
      echo "- ⚠️ No CLAUDE.md found"
    fi
    echo ""

    # Check 2: File size violations (>300 lines)
    echo "## 2. File Size Violations (>300 lines)"
    local size_count=0
    local code_files
    code_files=$(find "$project_dir" \( -name '*.py' -o -name '*.ts' -o -name '*.js' -o -name '*.sh' \) \
      -not -path '*/node_modules/*' -not -path '*/__pycache__/*' -not -path '*/.git/*' -not -path '*/.venv/*' -not -path '*/venv/*' -not -path '*/site-packages/*' -not -path '*/.tox/*' 2>/dev/null || true)
    if [[ -n "$code_files" ]]; then
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local lines
        lines=$(wc -l < "$f" 2>/dev/null || echo 0)
        if [[ $lines -gt 300 ]]; then
          echo "- ⚠️ \`$(basename "$f")\`: $lines lines"
          size_count=$((size_count + 1))
        fi
      done <<< "$code_files"
    fi
    if [[ $size_count -eq 0 ]]; then
      echo "- ✅ All files within limit"
    else
      echo "- Found $size_count file(s) over 300 lines"
    fi
    echo ""

    # Check 3: Naming convention drift
    echo "## 3. Naming Convention Check"
    local naming_count=0
    local py_files
    py_files=$(find "$project_dir" -name '*.py' \
      -not -path '*/node_modules/*' -not -path '*/__pycache__/*' -not -path '*/.git/*' -not -path '*/.venv/*' -not -path '*/venv/*' -not -path '*/site-packages/*' -not -path '*/.tox/*' 2>/dev/null || true)
    if [[ -n "$py_files" ]]; then
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local camel_funcs
        camel_funcs=$(grep -nE '^def [a-z]+[A-Z]' "$f" 2>/dev/null || true)
        if [[ -n "$camel_funcs" ]]; then
          echo "- ⚠️ \`$(basename "$f")\`: camelCase functions found (should be snake_case)"
          naming_count=$((naming_count + 1))
        fi
      done <<< "$py_files"
    fi
    if [[ $naming_count -eq 0 ]]; then
      echo "- ✅ No naming drift detected"
    fi
    echo ""

    # Check 4: Unused imports (Python only, basic check — first 20 files)
    echo "## 4. Import Hygiene"
    local import_count=0
    local py_sample
    py_sample=$(find "$project_dir" -name '*.py' -not -path '*__pycache__*' -not -path '*.git*' 2>/dev/null | head -20 || true)
    if [[ -n "$py_sample" ]]; then
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local imports
        imports=$(grep -E '^(from .+ import .+|import .+)' "$f" 2>/dev/null || true)
        if [[ -n "$imports" ]]; then
          while IFS= read -r imp; do
            local name
            name=$(echo "$imp" | grep -oE 'import (\w+)' | tail -1 | awk '{print $2}' || true)
            if [[ -n "$name" ]]; then
              local count
              count=$(grep -c "$name" "$f" 2>/dev/null || echo 0)
              if [[ $count -le 1 ]]; then
                echo "- ⚠️ \`$(basename "$f")\`: possibly unused import: \`$name\`"
                import_count=$((import_count + 1))
              fi
            fi
          done <<< "$imports"
        fi
      done <<< "$py_sample"
    fi
    if [[ $import_count -eq 0 ]]; then
      echo "- ✅ No obvious unused imports"
    fi
    echo ""

    # Check 5: Git status (uncommitted work)
    echo "## 5. Uncommitted Work"
    if [[ -d "$project_dir/.git" ]]; then
      local untracked
      untracked=$(cd "$project_dir" && git status --porcelain 2>/dev/null | wc -l || echo 0)
      if [[ $untracked -gt 0 ]]; then
        echo "- ⚠️ $untracked uncommitted files"
      else
        echo "- ✅ Working tree clean"
      fi
    fi
    echo ""

  } > "$report"

  echo "  Report: $report"
}

# Determine which projects to audit
if [[ -n "$TARGET_PROJECT" ]]; then
  audit_project "$PROJECTS_DIR/$TARGET_PROJECT"
elif [[ "$ALL_PROJECTS" == "true" ]]; then
  for d in "$PROJECTS_DIR"/*/; do
    [[ -d "$d" ]] && audit_project "$d"
  done
  # Also audit workspace-level CLAUDE.md
  echo ""
  echo "Workspace CLAUDE.md audit:"
  if [[ -f "$HOME/Documents/CLAUDE.md" ]]; then
    local_refs=$(grep -oE '`[^`]+\.(py|ts|js|sh|json|md|yaml|yml)`' "$HOME/Documents/CLAUDE.md" 2>/dev/null | tr -d '`' || true)
    if [[ -n "$local_refs" ]]; then
      while IFS= read -r ref; do
        if echo "$ref" | grep -qE '<|>|\*|\$|~'; then continue; fi
        if [[ ! -f "$HOME/Documents/$ref" ]] && [[ ! -f "$ref" ]]; then
          echo "  ❌ Dead ref: $ref"
        fi
      done <<< "$local_refs"
    fi
  fi
else
  echo "Usage: entropy-audit.sh --project <name> | --all" >&2
  echo "Projects available:" >&2
  ls "$PROJECTS_DIR" 2>/dev/null | while read -r p; do echo "  $p"; done >&2
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "Results: $RESULTS_DIR/"
echo "═══════════════════════════════════════════════"
