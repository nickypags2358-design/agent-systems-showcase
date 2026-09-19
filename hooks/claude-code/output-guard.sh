#!/usr/bin/env bash
# output-guard.sh — Stop hook. Anti-sycophancy + claim-evidence output policy, run as one
# staged pass over the assistant's final reply for the turn:
#   stage 1 (sycophancy) — blocks banned validation openers / empty-encouragement closers.
#   stage 2 (claim-evidence) — blocks a reply that asserts LIVE STATE (a credential is dead,
#     a feature is enabled/proven, N jobs were deployed, etc.) when this turn read ZERO state
#     and the prose shows no evidence marker (a code fence, a file:line citation, "verified
#     just now", ...). Forces a verify-or-hedge redo instead of a memory-based claim.
# Any tripped stage aggregates into one {"decision":"block"} JSON so only one redo happens.
# Loop-guarded (stop_hook_active -> exit 0, never wedges the session). Skips when
# CLAUDE_HEADLESS=1 (no human-facing reply to police). Always exits 0 on internal error
# (fail-open). Deterministic phrase matching only — it will not catch subtle sycophancy or
# a wrong verification method, only the blatant listed shapes.
#
# CONTRACT: Stop hook, stdin JSON {"stop_hook_active":bool,"transcript_path":"..."}.
#   Trip -> stdout {"decision":"block","reason":"..."}; exit 0 either way.
#
# WIRING (Claude Code, .claude/settings.json):
#   "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "$SELF_DIR/output-guard.sh"}]}]}
set -uo pipefail
[ "${CLAUDE_HEADLESS:-0}" = "1" ] && exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/lib/common.sh" 2>/dev/null || { hook_log() { :; }; }

# Stage 1: sycophancy
OPENERS="you'?re absolutely right|you are absolutely right|great question|i appreciate you sharing|that'?s a really good point|that is a really good point|i hear you|i feel you"
CLOSERS="you'?ve got this|you can do it|things will get better|stay positive|believe in yourself|trust the process"

syco_detect() { # $1 = reply text -> "opener"/"closer"/"opener+closer"/""
  local text="$1" first last hits=""
  [ -z "$text" ] && { printf ''; return 0; }
  if printf '%s' "$text" | grep -qiE 'anti-sycophancy|banned (opener|closer)|output-guard|sycophancy-(scan|check)'; then
    printf ''; return 0
  fi
  first="$(printf '%s' "$text" | sed -n '1,3p' | tr '\n' ' ' | cut -c1-120)"
  last="$(printf '%s' "$text" | tr '\n' ' ' | rev | cut -c1-160 | rev)"
  printf '%s' "$first" | grep -qiE "^[[:space:]>*_\"'-]*($OPENERS)" && hits="opener"
  printf '%s' "$last"  | grep -qiE "($CLOSERS)" && hits="${hits:+$hits+}closer"
  printf '%s' "$hits"
}
SYCO_REASON_FMT='Anti-sycophancy backstop: banned %s detected. Redo WITHOUT it — lead with the conclusion, drop the validation/encouragement, cite evidence for any praise, bad news first.'

# Stage 2: claim-evidence
CLAIMS='(key|credential|token|api)s?[[:space:]]+(is|are|was|were)[[:space:]]+(dead|invalid|expired|revoked|down|broken)'
CLAIMS="$CLAIMS|(is|are|was|were)[[:space:]]+(now[[:space:]]+)?(enabled|disabled|loaded|unloaded)"
CLAIMS="$CLAIMS|(never[[:space:]]+(ran|fired|started)|has[[:space:]]+never[[:space:]]+run|did[[:space:]]+not[[:space:]]+run)"
CLAIMS="$CLAIMS|(is|are)[[:space:]]+(proven|verified|confirmed)[[:space:]]+(working|live|correct|clean)"
CLAIMS="$CLAIMS|[0-9]+[[:space:]]+(jobs?|requests?)[[:space:]]+(were[[:space:]]+)?(submitted|deployed|running|passing)"
EVIDENCE='```|[A-Za-z0-9_./-]+\.(py|sh|json|jsonl|md|yml|toml):[0-9]+'
EVIDENCE="$EVIDENCE|(verified|computed|recomputed|counted|checked|measured)[[:space:]]+(this[[:space:]]+run|live|just[[:space:]]+now|above)"
EVIDENCE="$EVIDENCE|(config|launchctl|git|log)[[:space:]]+(shows?|says?|reports?|confirms?)"
CLAIM_META='claim-evidence|verify-before-assert|this hook|the guard (exists|blocks)|failure class'

claim_detect() { # $1 = reply text -> "risk" or ""
  local t="${1:-}"
  [ -z "$t" ] && { printf ''; return 0; }
  printf '%s' "$t" | grep -qiE "$CLAIM_META" && { printf ''; return 0; }
  printf '%s' "$t" | grep -qiE "$CLAIMS" || { printf ''; return 0; }
  printf '%s' "$t" | grep -qiE "$EVIDENCE" && { printf ''; return 0; }
  printf 'risk'
}
CLAIM_REASON='claim-evidence-guard: the reply asserts LIVE STATE (dead/enabled/proven/N-deployed) but this turn ran ZERO state-reading tool calls and the prose shows no receipt. Do ONE of: (a) run the check now and cite it, or (b) rewrite the claim as explicitly unverified. Do not restate it from memory.'

INPUT="$(head -c 400000)"
ACTIVE="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("stop_hook_active",False))' 2>/dev/null || echo False)"
[ "$ACTIVE" = "True" ] && exit 0
TRANSCRIPT="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;print((json.load(sys.stdin) or {}).get("transcript_path",""))' 2>/dev/null || true)"
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

TEXT="$(jq -rc 'select(.type=="assistant") | .message.content' "$TRANSCRIPT" 2>/dev/null | tail -1 \
        | jq -r 'if type=="array" then ([.[]|select(.type=="text")|.text]|join(" ")) elif type=="string" then . else "" end' 2>/dev/null || true)"

set --
WARNS=""

S1="$(syco_detect "$TEXT")"
if [ -n "$S1" ]; then
  if [ "${SYCOPHANCY_WARN:-0}" = "1" ]; then
    hook_log WARN "sycophancy: $S1"
    WARNS="${WARNS}output-guard (warn): banned $S1 in the last reply.
"
  else
    hook_log BLOCK "sycophancy: $S1"
    set -- "$@" "$(printf "$SYCO_REASON_FMT" "$S1")"
  fi
fi

if [ -n "$(claim_detect "$TEXT")" ]; then
  READS="$(python3 - "$TRANSCRIPT" <<'PY' 2>/dev/null || echo 0
import json, sys
rows = []
for ln in open(sys.argv[1], encoding="utf-8", errors="ignore"):
    try: rows.append(json.loads(ln))
    except Exception: pass
def is_human_turn(r):
    if r.get("type") != "user":
        return False
    c = (r.get("message") or {}).get("content")
    if isinstance(c, str):
        return True
    if isinstance(c, list):
        types = [b.get("type") for b in c if isinstance(b, dict)]
        return "text" in types and "tool_result" not in types
    return False
start = 0
for i, r in enumerate(rows):
    if is_human_turn(r):
        start = i
n = 0
for r in rows[start:]:
    c = (r.get("message") or {}).get("content")
    if isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type") == "tool_use" \
               and b.get("name") in ("Bash", "Read", "Grep", "Glob", "Agent", "Workflow"):
                n += 1
print(n)
PY
)"
  case "$READS" in ''|*[!0-9]*) READS=0;; esac
  if [ "$READS" -eq 0 ]; then
    hook_log BLOCK "pure-memory state assertion, 0 reads this turn"
    set -- "$@" "$CLAIM_REASON"
  fi
fi

if [ $# -gt 0 ]; then
  python3 -c 'import json,sys;print(json.dumps({"decision":"block","reason":"\n\n".join(sys.argv[1:])}))' "$@" 2>/dev/null \
    || hook_log ERROR "block-emit failed ($# reason(s) dropped)"
elif [ -n "$WARNS" ]; then
  printf '%s' "$WARNS"
fi
exit 0
