#!/usr/bin/env bash
# common.sh — tiny shared shim for the hooks in this showcase repo.
# Source it as:  source "$SELF_DIR/lib/common.sh"
# Fail-open by design: every helper degrades gracefully, never aborts the caller.

# HOOK_HOME: env override, defaults to a per-user scratch dir (never a repo-relative
# writable path, so the hooks work read-only-checked-out too).
HOOK_HOME="${HOOK_HOME:-${TMPDIR:-/tmp}/agent-hooks}"
LOG_DIR="${LOG_DIR:-$HOOK_HOME/logs}"
mkdir -p "$LOG_DIR" 2>/dev/null || true

# hook_log LEVEL MESSAGE — append one line to $LOG_DIR/hooks.log. Never fatal.
hook_log() {
  local level="${1:-INFO}" msg="${2:-}"
  printf '%s | %s | %s\n' "$(date '+%F %T' 2>/dev/null || echo now)" "$level" "$msg" \
    >> "$LOG_DIR/hooks.log" 2>/dev/null || true
}

# read_stdin_json — cat stdin into a variable and echo it (so callers can capture once).
read_stdin_json() {
  cat 2>/dev/null || true
}

# json_get JSON DOTTED.PATH — prefer jq, fall back to python3, else empty string.
json_get() {
  local json="$1" path="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r --arg p "$path" '
      . as $in | $p | split(".") as $keys |
      reduce $keys[] as $k ($in; if . == null then null else .[$k]? end)
      | if . == null then "" else . end' 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cur = data
for key in sys.argv[1].split("."):
    if isinstance(cur, dict):
        cur = cur.get(key)
    else:
        cur = None
        break
if cur is None:
    print("")
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur))
else:
    print(cur)
' "$path" 2>/dev/null && return 0
  fi
  printf ''
}
