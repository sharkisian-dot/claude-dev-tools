#!/usr/bin/env bash
# lib/agents.sh — Load agent definitions from markdown files
#
# Agent files are markdown with YAML frontmatter. They live in:
#   1. ${REPO_ROOT}/.devtools/agents/  (project overrides — highest priority)
#   2. ${DEVTOOLS_ROOT}/agents/        (built-in defaults)
#
# Usage:
#   source "$(dirname "$0")/../lib/agents.sh"
#   prompt=$(load_agent "review-correctness")

# Ensure config.sh is loaded (for DEVTOOLS_ROOT, REPO_ROOT, config vars)
if [[ -z "${DEVTOOLS_ROOT:-}" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
fi

# load_agent <agent-id>
#
# Reads the agent markdown file, strips YAML frontmatter, and substitutes
# {{VARIABLE}} placeholders with values from .devtools.yaml config.
#
# Returns the processed prompt body on stdout.
load_agent() {
  local agent_id="$1"
  local project_override="${REPO_ROOT}/.devtools/agents/${agent_id}.md"
  local builtin="${DEVTOOLS_ROOT}/agents/${agent_id}.md"

  local agent_file=""
  if [[ -f "$project_override" ]]; then
    agent_file="$project_override"
  elif [[ -f "$builtin" ]]; then
    agent_file="$builtin"
  else
    echo "ERROR: Agent definition not found: ${agent_id}" >&2
    echo "  Searched: $project_override" >&2
    echo "  Searched: $builtin" >&2
    return 1
  fi

  # Extract body (everything after the second ---)
  local body
  body=$(awk '
    BEGIN { fence_count = 0 }
    /^---[[:space:]]*$/ { fence_count++; next }
    fence_count >= 2 { print }
  ' "$agent_file")

  # Substitute {{VARIABLE}} placeholders with config values
  body="${body//\{\{PROJECT_NAME\}\}/${PROJECT_NAME}}"
  body="${body//\{\{TEST_COMMAND\}\}/${TEST_COMMAND}}"
  body="${body//\{\{BUILD_COMMAND\}\}/${BUILD_COMMAND}}"
  body="${body//\{\{DEV_COMMAND\}\}/${DEV_COMMAND}}"
  body="${body//\{\{DEV_PORT\}\}/${DEV_PORT}}"
  body="${body//\{\{RULES_FILE\}\}/${REVIEW_RULES_FILE}}"
  body="${body//\{\{RULES_MAX_LINES\}\}/${REVIEW_RULES_MAX_LINES}}"
  body="${body//\{\{TASKS_FILE\}\}/${RELAY_TASKS_FILE}}"
  body="${body//\{\{LOCK_DIR\}\}/${RELAY_LOCK_DIR}}"
  body="${body//\{\{BROWSER_TESTS_MANIFEST\}\}/${BROWSER_TESTS_MANIFEST}}"
  body="${body//\{\{BROWSER_TESTS_DIR\}\}/${BROWSER_TESTS_DIR}}"
  body="${body//\{\{LANE_IMAGE\}\}/${LANE_IMAGE}}"
  body="${body//\{\{LANE_WORKTREES_DIR\}\}/${LANE_WORKTREES_DIR}}"
  body="${body//\{\{HYGIENE_MAX_RULES_LINES\}\}/${HYGIENE_MAX_RULES_LINES}}"

  printf '%s' "$body"
}

# load_agent_model <agent-id>
#
# Returns the model specified in the agent's YAML frontmatter.
load_agent_model() {
  local agent_id="$1"
  local project_override="${REPO_ROOT}/.devtools/agents/${agent_id}.md"
  local builtin="${DEVTOOLS_ROOT}/agents/${agent_id}.md"

  local agent_file=""
  if [[ -f "$project_override" ]]; then
    agent_file="$project_override"
  elif [[ -f "$builtin" ]]; then
    agent_file="$builtin"
  else
    return 1
  fi

  # Extract model from frontmatter
  awk '
    BEGIN { in_front = 0 }
    /^---[[:space:]]*$/ { in_front++; next }
    in_front == 1 && /^model:/ {
      sub(/^model:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      print
      exit
    }
    in_front >= 2 { exit }
  ' "$agent_file"
}
