#!/usr/bin/env bash
# claim-evidence-guard.sh — Codex-runtime Stop hook. Makes one recurring failure class
# mechanically harder instead of merely discouraged: asserting LIVE STATE from memory
# instead of reading it (e.g. "the credential is dead", "the feature is enabled", "N jobs
# were deployed") when the turn ran no state-reading tool call and the reply shows no receipt.
#
# HONEST SCOPE: catches the pure-memory class cleanly. Does not catch a wrong verification
# method (a command that ran but checked the wrong thing) — no text hook can. Deterministic
# phrase matching only. Fail-open everywhere. One redo max (loop-guarded).
#
#   Test:  bash claim-evidence-guard.sh --test "the key is dead"          -> BLOCK
#          bash claim-evidence-guard.sh --test "the key is dead \`\`\`x\`\`\`"  -> clean (evidence)
#
# WIRING: point your Codex hook config's Stop (or equivalent end-of-turn) entry at this script.
set -uo pipefail
[ "${CODEX_HEADLESS:-0}" = "1" ] && exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/../claude-code/lib/common.sh" 2>/dev/null || { hook_log() { :; }; }

# HIGH-RISK assertions: claims about live state that must be read, never remembered.
CLAIMS='(key|credential|token|api)s?[[:space:]]+(is|are|was|were)[[:space:]]+(dead|invalid|expired|revoked|down|broken)'
CLAIMS="$CLAIMS|(is|are|was|were)[[:space:]]+(now[[:space:]]+)?(enabled|disabled|loaded|unloaded)"
CLAIMS="$CLAIMS|(never[[:space:]]+(ran|fired|started)|has[[:space:]]+never[[:space:]]+run|did[[:space:]]+not[[:space:]]+run)"
CLAIMS="$CLAIMS|(needs|requires)[[:space:]]+(your|the (owner|team)'?s)[[:space:]]+(approval|amendment|authorization|sign-?off)"
CLAIMS="$CLAIMS|(is|are)[[:space:]]+(proven|verified|confirmed)[[:space:]]+(working|live|correct|clean)"
CLAIMS="$CLAIMS|[0-9]+[[:space:]]+(jobs?|requests?)[[:space:]]+(were[[:space:]]+)?(submitted|deployed|running|passing)"

# EVIDENCE markers: the reply itself shows a receipt.
EVIDENCE='```|[A-Za-z0-9_./-]+\.(py|sh|json|jsonl|md|yml|toml):[0-9]+'
EVIDENCE="$EVIDENCE|(verified|computed|recomputed|counted|checked|measured)[[:space:]]+(this[[:space:]]+run|live|just[[:space:]]+now|above)"
EVIDENCE="$EVIDENCE|(system|ledger|config|log|git)[[:space:]]+(shows?|says?|reports?|confirms?)"

META='claim-evidence-guard|verify-before-assert|this hook|the guard (exists|blocks)|failure class'

detect() { # $1 = reply text ; echoes "risk" or ""
  local t="${1:-}"
  [ -z "$t" ] && { printf ''; return 0; }
  printf '%s' "$t" | grep -qiE "$META" && { printf ''; return 0; }
  printf '%s' "$t" | grep -qiE "$CLAIMS" || { printf ''; return 0; }
  printf '%s' "$t" | grep -qiE "$EVIDENCE" && { printf ''; return 0; }
  printf 'risk'
}

if [ "${1:-}" = "--test" ]; then
  [ -z "$(detect "${2:-}")" ] && echo "VERDICT: clean" || echo "VERDICT: BLOCK"
  exit 0
fi

INPUT="$(head -c 400000)"
ACTIVE="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("stop_hook_active",False))' 2>/dev/null || echo False)"
[ "$ACTIVE" = "True" ] && exit 0
TRANSCRIPT="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;print((json.load(sys.stdin) or {}).get("transcript_path",""))' 2>/dev/null || true)"
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

TEXT="$(jq -rc 'select(.type=="assistant") | .message.content' "$TRANSCRIPT" 2>/dev/null | tail -1 \
        | jq -r 'if type=="array" then ([.[]|select(.type=="text")|.text]|join(" ")) elif type=="string" then . else "" end' 2>/dev/null || true)"
[ -n "$TEXT" ] || exit 0
[ -z "$(detect "$TEXT")" ] && exit 0

READS="$(python3 - "$TRANSCRIPT" <<'PY' 2>/dev/null || echo 0
import json, sys
rows = []
for ln in open(sys.argv[1], encoding="utf-8", errors="ignore"):
    try: rows.append(json.loads(ln))
    except Exception: pass
start = 0
for i, r in enumerate(rows):
    if r.get("type") == "user" and isinstance(r.get("message", {}).get("content"), str):
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
[ "$READS" -gt 0 ] && exit 0

hook_log BLOCK "pure-memory state assertion, 0 reads this turn"
printf '{"decision":"block","reason":"claim-evidence-guard: the reply asserts LIVE STATE (dead/enabled/proven/needs-approval/N-deployed) but this turn ran ZERO state-reading tool calls and the prose shows no receipt. Do ONE of: (a) run the check now and cite it; or (b) rewrite the claim as explicitly unverified. Do not restate it from memory."}\n'
exit 0
