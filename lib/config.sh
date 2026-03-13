#!/usr/bin/env bash
# lib/config.sh — Load .devtools.yaml configuration with grep-based YAML parsing
#
# Provides config_get() to read YAML values without requiring yq.
# Sources this once at the top of any script that needs project config.
#
# Usage:
#   source "$(dirname "$0")/../lib/config.sh"
#   echo "$PROJECT_NAME"           # pre-loaded config vars
#   config_get "lane.image"        # dynamic lookups

set -eo pipefail

# ── Path detection ─────────────────────────────────────────────────────────────

# DEVTOOLS_ROOT: where the tooling repo lives
if [[ -z "${DEVTOOLS_ROOT:-}" ]]; then
  DEVTOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export DEVTOOLS_ROOT

# REPO_ROOT: the project repo that uses devtools
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
export REPO_ROOT

# ── YAML config file ──────────────────────────────────────────────────────────

DEVTOOLS_CONFIG="${REPO_ROOT}/.devtools.yaml"

# ── Grep-based YAML parser ────────────────────────────────────────────────────
#
# Supports simple scalar values in flat or one-level-nested YAML:
#   project:
#     name: "Family Narrative"
#     test_command: "npx vitest run"
#
# config_get "project.name" → "Family Narrative"
# config_get "lane.image"   → "family-narrative-dev"
#
# Does NOT support:
#   - Arrays (use config_get_list for those)
#   - Multi-level nesting beyond 2 levels
#   - YAML anchors or aliases

config_get() {
  local key="$1"
  local default="${2:-}"

  if [[ ! -f "$DEVTOOLS_CONFIG" ]]; then
    echo "$default"
    return
  fi

  local section field
  if [[ "$key" == *.* ]]; then
    section="${key%%.*}"
    field="${key#*.}"
  else
    section=""
    field="$key"
  fi

  local value=""

  if [[ -z "$section" ]]; then
    # Top-level key
    value=$(grep -E "^${field}:" "$DEVTOOLS_CONFIG" 2>/dev/null \
      | head -1 \
      | sed 's/^[^:]*:[[:space:]]*//' \
      | sed 's/^["'"'"']//' | sed 's/["'"'"']$//' \
      | sed 's/[[:space:]]*#.*//' \
      | sed 's/[[:space:]]*$//')
  else
    # Nested key: find section, then find field within it
    value=$(awk -v section="$section" -v field="$field" '
      BEGIN { in_section = 0 }
      /^[a-zA-Z_]/ {
        if ($0 ~ "^" section ":") { in_section = 1; next }
        else if (in_section) { exit }
      }
      in_section && /^[[:space:]]/ {
        gsub(/^[[:space:]]+/, "")
        if ($0 ~ "^" field ":") {
          sub(/^[^:]*:[[:space:]]*/, "")
          gsub(/^["'"'"']|["'"'"']$/, "")
          sub(/[[:space:]]*#.*/, "")
          sub(/[[:space:]]*$/, "")
          print
          exit
        }
      }
    ' "$DEVTOOLS_CONFIG" 2>/dev/null)
  fi

  if [[ -n "$value" ]]; then
    echo "$value"
  else
    echo "$default"
  fi
}

# config_get_list "browser_tests.required_env" → one item per line
config_get_list() {
  local key="$1"
  local section="${key%%.*}"
  local field="${key#*.}"

  [[ ! -f "$DEVTOOLS_CONFIG" ]] && return

  awk -v section="$section" -v field="$field" '
    BEGIN { in_section = 0; in_list = 0 }
    /^[a-zA-Z_]/ {
      if ($0 ~ "^" section ":") { in_section = 1; next }
      else if (in_section) { exit }
    }
    in_section && /^[[:space:]]/ {
      line = $0
      gsub(/^[[:space:]]+/, "", line)
      if (line ~ "^" field ":") { in_list = 1; next }
      else if (in_list && line ~ /^- /) {
        sub(/^- [[:space:]]*/, "", line)
        gsub(/^["'"'"']|["'"'"']$/, "", line)
        print line
      }
      else if (in_list && line !~ /^-/) { in_list = 0 }
    }
  ' "$DEVTOOLS_CONFIG" 2>/dev/null
}

# ── Pre-load common config vars ───────────────────────────────────────────────

PROJECT_NAME=$(config_get "project.name" "$(basename "$REPO_ROOT")")
TEST_COMMAND=$(config_get "project.test_command" "npm test")
BUILD_COMMAND=$(config_get "project.build_command" "npm run build")
DEV_COMMAND=$(config_get "project.dev_command" "npm run dev")
DEV_PORT=$(config_get "project.dev_port" "3000")

LANE_IMAGE=$(config_get "lane.image" "devtools-dev")
LANE_WORKTREES_DIR=$(config_get "lane.worktrees_dir" "../$(basename "$REPO_ROOT")-lanes")
LANE_DOCKERFILE=$(config_get "lane.dockerfile" "Dockerfile.dev")

REVIEW_RULES_FILE=$(config_get "review.rules_file" "CLAUDE.md")
REVIEW_RULES_MAX_LINES=$(config_get "review.rules_max_lines" "200")
REVIEW_SUPPRESSIONS_FILE=$(config_get "review.suppressions_file" ".devtools/review-suppressions.md")

RELAY_TASKS_FILE=$(config_get "relay.tasks_file" "TASKS.md")
RELAY_LOCK_DIR=$(config_get "relay.lock_dir" ".relay-locks")

BROWSER_TESTS_MANIFEST=$(config_get "browser_tests.manifest" "browser-tests/test-manifest.json")
BROWSER_TESTS_DIR=$(config_get "browser_tests.dir" "browser-tests")

HYGIENE_MAX_RULES_LINES=$(config_get "hygiene.max_rules_lines" "400")

# Static analysis gate configuration (pure bash, no LLM)
STATIC_ANALYSIS_TYPECHECK=$(config_get "static_analysis.typecheck_command" "")
STATIC_ANALYSIS_LINT=$(config_get "static_analysis.lint_command" "")
STATIC_ANALYSIS_LINT_FIX=$(config_get "static_analysis.lint_fix_command" "")
STATIC_ANALYSIS_FORMAT=$(config_get "static_analysis.format_command" "")

export PROJECT_NAME TEST_COMMAND BUILD_COMMAND DEV_COMMAND DEV_PORT
export LANE_IMAGE LANE_WORKTREES_DIR LANE_DOCKERFILE
export REVIEW_RULES_FILE REVIEW_RULES_MAX_LINES REVIEW_SUPPRESSIONS_FILE
export RELAY_TASKS_FILE RELAY_LOCK_DIR
export BROWSER_TESTS_MANIFEST BROWSER_TESTS_DIR
export HYGIENE_MAX_RULES_LINES
export STATIC_ANALYSIS_TYPECHECK STATIC_ANALYSIS_LINT STATIC_ANALYSIS_LINT_FIX STATIC_ANALYSIS_FORMAT
