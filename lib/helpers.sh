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

# ── Duration tracking ────────────────────────────────────────────────────────

# Logs wall-clock duration per LLM invocation to a JSON-lines file.
# Usage: duration_log_start; ... run claude ...; duration_log_end "label" "model"
DURATION_LOG_FILE=""
_duration_start_time=""

duration_log_init() {
  DURATION_LOG_FILE="${1:-/tmp/devtools-duration-$(date +%s).jsonl}"
}

duration_log_start() {
  _duration_start_time=$(date +%s)
}

duration_log_end() {
  local label="$1" model="$2"
  [[ -z "$_duration_start_time" ]] && return
  local end_time; end_time=$(date +%s)
  local duration=$(( end_time - _duration_start_time ))
  if [[ -n "$DURATION_LOG_FILE" ]]; then
    if command -v jq >/dev/null 2>&1; then
      jq -nc --arg l "$label" --arg m "$model" --argjson d "$duration" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{label:$l, model:$m, duration_s:$d, timestamp:$t}' >> "$DURATION_LOG_FILE"
    else
      printf '{"label":"%s","model":"%s","duration_s":%d,"timestamp":"%s"}\n' \
        "$label" "$model" "$duration" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$DURATION_LOG_FILE"
    fi
  fi
  _duration_start_time=""
}

# ── Review metrics logging ────────────────────────────────────────────────────

# Append review results to .devtools-logs/review-issues.jsonl for cross-run analysis.
log_review_issues() {
  local source="$1" pr_ref="$2" json_file="$3"
  local log_dir="${REPO_ROOT:-.}/.devtools-logs"
  mkdir -p "$log_dir"
  local log_file="$log_dir/review-issues.jsonl"

  local issue_count verdict
  issue_count=$(jq '.issues | length' < "$json_file" 2>/dev/null) || return
  verdict=$(jq -r '.verdict' < "$json_file" 2>/dev/null) || return

  jq -nc \
    --arg src "$source" \
    --arg pr "$pr_ref" \
    --arg v "$verdict" \
    --argjson ic "$issue_count" \
    --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson issues "$(jq '[.issues[] | {file, severity, message}]' < "$json_file" 2>/dev/null || echo '[]')" \
    '{source:$src, pr:$pr, verdict:$v, issue_count:$ic, issues:$issues, timestamp:$t}' \
    >> "$log_file"
}

duration_log_summary() {
  [[ -z "$DURATION_LOG_FILE" || ! -f "$DURATION_LOG_FILE" ]] && return
  local total_duration=0 entry_count=0
  while IFS= read -r line; do
    local dur; dur=$(printf '%s' "$line" | jq -r '.duration_s // 0' 2>/dev/null) || continue
    total_duration=$(( total_duration + dur ))
    (( entry_count++ )) || true
  done < "$DURATION_LOG_FILE"
  echo "Duration: $entry_count invocations, ${total_duration}s total wall time"
  echo "Details: $DURATION_LOG_FILE"
}
