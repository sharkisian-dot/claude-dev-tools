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
# Accepts JSON via file path ($3) or stdin (pass "-" or "/dev/stdin" as $3).
log_review_issues() {
  local source="$1" pr_ref="$2" json_source="$3"
  local log_dir="${REPO_ROOT:-.}/.devtools-logs"
  mkdir -p "$log_dir"
  local log_file="$log_dir/review-issues.jsonl"

  # Read JSON from file or stdin
  local json_content
  if [[ "$json_source" == "-" || "$json_source" == "/dev/stdin" ]]; then
    json_content=$(cat)
  else
    json_content=$(cat "$json_source" 2>/dev/null) || { warn "log_review_issues: could not read $json_source"; return; }
  fi

  # Single jq call: extract verdict + issues array, construct the log line
  local log_line
  log_line=$(printf '%s' "$json_content" | jq -c \
    --arg src "$source" \
    --arg pr "$pr_ref" \
    --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{source:$src, pr:$pr, verdict:.verdict, issues:[(.issues // [])[] | {file, severity, message}], timestamp:$t}' \
    2>/dev/null) || { warn "log_review_issues: failed to parse JSON from $json_source"; return; }

  # Append — >> is atomic for lines under PIPE_BUF on POSIX systems
  printf '%s\n' "$log_line" >> "$log_file"
}

# ── PR size check ─────────────────────────────────────────────────────────────

# Shared PR size gating. Exits/continues based on FORCE mode.
# Usage: check_pr_size <pr_number> <max_diff_lines> <force_review> [exit_on_fail]
#   exit_on_fail: "die" to exit (fix-loop), "continue" to skip (review-pr). Default: "die"
check_pr_size() {
  local pr="$1" max_lines="$2" force="$3" on_fail="${4:-die}"
  local diff_lines
  diff_lines=$(gh pr diff "$pr" 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$diff_lines" -gt "$max_lines" ]]; then
    if [[ "$force" != "true" ]]; then
      warn "PR #${pr} has ${diff_lines} changed lines (limit: ${max_lines})."
      warn "AI review quality degrades on large diffs. Consider splitting the PR."
      if [[ "$on_fail" == "die" ]]; then
        die "Use --force to proceed anyway, or --max-diff-lines N to adjust the limit."
      else
        warn "Use --force to review anyway, or --max-diff-lines N to adjust the limit."
        return 1  # caller should 'continue'
      fi
    else
      warn "PR #${pr}: ${diff_lines} lines (above ${max_lines} limit) — proceeding with --force"
    fi
  fi
  return 0
}

# ── RAM-aware concurrency gate ────────────────────────────────────────────────
#
# available_ram_mb: free + inactive pages on macOS, free + available on Linux
# memory_pressure_level: 0=normal, 1=warning, 2=critical (macOS only, 0 on Linux)
memory_pressure_level() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sysctl -n vm.memory_pressure 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# available_ram_mb: truly-free pages only (not inactive, which macOS may not actually reclaim)
available_ram_mb() {
  if [[ "$(uname)" == "Darwin" ]]; then
    local page_size; page_size=$(sysctl -n hw.pagesize)
    vm_stat | awk -v ps="$page_size" '
      /Pages free/       { free=$3 }
      /Pages purgeable/  { purg=$3 }
      END { printf "%d", (free + purg) * ps / 1024 / 1024 }
    ' | tr -d '.'
  else
    awk '/MemAvailable/ { printf "%d", $2 / 1024; exit }' /proc/meminfo
  fi
}

# wait_for_ram <required_mb> [label]
# Blocks until memory pressure is normal AND at least <required_mb> MB is free.
wait_for_ram() {
  local required="${1:-2500}"
  local label="${2:-process}"
  local waited=false
  while (( $(memory_pressure_level) > 0 )) || (( $(available_ram_mb) < required )); do
    if [[ "$waited" == false ]]; then
      log "⏳ Waiting for RAM before launching ${label} (pressure=$(memory_pressure_level), free=$(available_ram_mb)MB, need ${required}MB)..."
      waited=true
    fi
    sleep 5
  done
  if [[ "$waited" == true ]]; then
    log "✅ RAM clear (pressure=$(memory_pressure_level), free=$(available_ram_mb)MB) — launching ${label}"
  fi
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
