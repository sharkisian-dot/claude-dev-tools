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
