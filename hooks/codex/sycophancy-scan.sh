#!/usr/bin/env bash
# sycophancy-scan.sh — Codex-runtime Stop hook. Auto-catches the explicit banned
# openers/closers from an anti-sycophancy output policy, deterministically.
#
# DEFAULT = BLOCK: emits {"decision":"block"} so the agent redoes the reply.
#   Loop-guarded (stop_hook_active -> one redo max, never wedges the session).
#   Set SYCOPHANCY_WARN=1 to downgrade to warn-only (prints a visible flag, no redo).
# HONEST SCOPE: deterministic phrase match only — catches the blatant listed phrases,
#   not subtle softening/hedging/inflation that avoids the listed words.
# Skips meta-discussion of the policy. Fail-open.
#
#   Test:  bash sycophancy-scan.sh --test "You're absolutely right!"   (prints VERDICT)
#
# WIRING: point your Codex hook config's Stop (or equivalent end-of-turn) entry at this script.
set -uo pipefail
[ "${CODEX_HEADLESS:-0}" = "1" ] && exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/../claude-code/lib/common.sh" 2>/dev/null || { hook_log() { :; }; }

# Blatant validation OPENERS (matched at the START).
OPENERS="you'?re absolutely right|you are absolutely right|great question|i appreciate you sharing|that'?s a really good point|that is a really good point|i hear you|i feel you"
# Empty-encouragement CLOSERS (matched near the END).
CLOSERS="you'?ve got this|you can do it|things will get better|stay positive|believe in yourself|trust the process"

detect() { # $1 = reply text -> "opener"/"closer"/"opener+closer"/""
  local text="$1" first last hits=""
  [ -z "$text" ] && { printf ''; return 0; }
  if printf '%s' "$text" | grep -qiE 'anti-sycophancy|banned (opener|closer)|the policy|sycophancy-(scan|check)'; then
    printf ''; return 0
  fi
  first="$(printf '%s' "$text" | sed -n '1,3p' | tr '\n' ' ' | cut -c1-120)"
  last="$(printf '%s' "$text" | tr '\n' ' ' | rev | cut -c1-160 | rev)"
  printf '%s' "$first" | grep -qiE "^[[:space:]>*_\"'-]*($OPENERS)" && hits="opener"
  printf '%s' "$last"  | grep -qiE "($CLOSERS)" && hits="${hits:+$hits+}closer"
  printf '%s' "$hits"
}

emit_block() { # $1 = hits
  hook_log BLOCK "$1"
  printf '{"decision":"block","reason":"Anti-sycophancy backstop: banned %s detected. Redo WITHOUT it — lead with the conclusion, drop the validation/encouragement, cite evidence for any praise, bad news first."}\n' "$1"
}
emit_warn() { # $1 = hits
  hook_log WARN "$1"
  printf 'sycophancy-scan: banned %s in the last reply (warn-only; unset SYCOPHANCY_WARN to enforce redo).\n' "$1"
}

if [ "${1:-}" = "--test" ]; then
  h="$(detect "${2:-}")"
  if [ -z "$h" ]; then echo "VERDICT: clean"; else
    [ "${SYCOPHANCY_WARN:-0}" = "1" ] && echo "VERDICT: warn ($h)" || echo "VERDICT: BLOCK ($h)"
  fi
  exit 0
fi

INPUT="$(head -c 200000)"
ACTIVE="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("stop_hook_active",False))' 2>/dev/null || echo False)"
[ "$ACTIVE" = "True" ] && exit 0
TRANSCRIPT="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;print((json.load(sys.stdin) or {}).get("transcript_path",""))' 2>/dev/null || true)"
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0
TEXT="$(jq -rc 'select(.type=="assistant") | .message.content' "$TRANSCRIPT" 2>/dev/null | tail -1 \
        | jq -r 'if type=="array" then ([.[]|select(.type=="text")|.text]|join(" ")) elif type=="string" then . else "" end' 2>/dev/null || true)"
HITS="$(detect "$TEXT")"
[ -z "$HITS" ] && exit 0
if [ "${SYCOPHANCY_WARN:-0}" = "1" ]; then emit_warn "$HITS"; else emit_block "$HITS"; fi
exit 0
