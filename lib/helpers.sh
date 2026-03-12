#!/usr/bin/env bash
# lib/helpers.sh — Shared utility functions for devtools scripts
#
# Usage:
#   source "$(dirname "$0")/../lib/helpers.sh"

# ── Logging ────────────────────────────────────────────────────────────────────

log()  { echo "  $*"; }
info() { echo "→ $*"; }
err()  { echo "✗ $*" >&2; }
warn() { echo "⚠  $*" >&2; }
die()  { echo "❌ $*" >&2; exit 1; }

# ── Dependency checks ─────────────────────────────────────────────────────────

check_deps() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    exit 1
  fi
}

# ── Environment guards ────────────────────────────────────────────────────────

# Fail if running inside a Claude Code session (prevents nested session issues)
require_terminal() {
  if [[ -n "${CLAUDECODE_SESSION:-}" || -n "${CLAUDE_SESSION:-}" || -n "${CLAUDECODE:-}" ]]; then
    err "Cannot run from within Claude Code session."
    err "Run from a separate terminal instead."
    exit 1
  fi
}

# ── JSON parsing ──────────────────────────────────────────────────────────────

# Parse Claude's JSON response — handles bare JSON, markdown-fenced, or wrapped text
parse_review_json() {
  local raw="$1"
  local result

  # Try 1: direct jq parse (bare JSON)
  result=$(printf '%s' "$raw" | jq '.' 2>/dev/null) && { printf '%s' "$result"; return 0; }

  # Try 2: strip markdown fences then parse
  result=$(printf '%s' "$raw" | sed 's/^```json$//' | sed 's/^```$//' | jq '.' 2>/dev/null) && { printf '%s' "$result"; return 0; }

  # Try 3: extract first JSON object with jq --raw-input
  result=$(printf '%s' "$raw" | grep -v '^\s*$' | jq -R -s '
    capture("(?<json>\\{[\\s\\S]*\\})") | .json
  ' 2>/dev/null | jq -r '.' | jq '.' 2>/dev/null) && { printf '%s' "$result"; return 0; }

  return 1
}

# ── Temp file management ──────────────────────────────────────────────────────

TEMP_FILES=()

cleanup_temp() {
  rm -f "${TEMP_FILES[@]}" 2>/dev/null
}

# Call this in scripts that use TEMP_FILES:
#   trap cleanup_temp EXIT

# ── Cost tracking ────────────────────────────────────────────────────────────

# Logs model usage (timing + model) to a JSON-lines file for cost analysis.
# Usage: cost_log_start; ... run claude ...; cost_log_end "label" "model"
COST_LOG_FILE=""
_cost_start_time=""

cost_log_init() {
  COST_LOG_FILE="${1:-/tmp/devtools-cost-$(date +%s).jsonl}"
}

cost_log_start() {
  _cost_start_time=$(date +%s)
}

cost_log_end() {
  local label="$1" model="$2"
  local end_time; end_time=$(date +%s)
  local duration=$(( end_time - _cost_start_time ))
  if [[ -n "$COST_LOG_FILE" ]]; then
    printf '{"label":"%s","model":"%s","duration_s":%d,"timestamp":"%s"}\n' \
      "$label" "$model" "$duration" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$COST_LOG_FILE"
  fi
}

cost_log_summary() {
  [[ -z "$COST_LOG_FILE" || ! -f "$COST_LOG_FILE" ]] && return
  local total_duration=0 entry_count=0
  while IFS= read -r line; do
    local dur; dur=$(printf '%s' "$line" | jq -r '.duration_s // 0' 2>/dev/null) || continue
    total_duration=$(( total_duration + dur ))
    (( entry_count++ )) || true
  done < "$COST_LOG_FILE"
  echo "Cost log: $entry_count invocations, ${total_duration}s total wall time"
  echo "Details: $COST_LOG_FILE"
}

# ── Issue logging (cross-run pattern detection foundation) ────────────────────

# Appends review issues to a persistent JSON-lines log for future pattern analysis.
# Usage: log_review_issues "review-pr" "PR#18" "/path/to/review.json"
log_review_issues() {
  local source="$1" context="$2" json_file="$3"
  local log_dir="${REPO_ROOT:-.}/.devtools-logs"
  mkdir -p "$log_dir"
  local issues_log="$log_dir/review-issues.jsonl"

  local issue_count
  issue_count=$(jq '.issues | length' < "$json_file" 2>/dev/null) || return 0
  [[ "$issue_count" -eq 0 ]] && return 0

  local timestamp; timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -c --arg src "$source" --arg ctx "$context" --arg ts "$timestamp" \
    '.issues[] | {source: $src, context: $ctx, timestamp: $ts, file: .file, line: .line, severity: .severity, message: .message}' \
    < "$json_file" >> "$issues_log" 2>/dev/null || true
}
