#!/usr/bin/env bash
# output-guard.selftest.sh — builds a fake transcript.jsonl per case and drives output-guard.sh
# through it. BLOCK cases must exit 0 but print {"decision":"block",...}; PASS cases must exit 0
# with empty stdout. Run with: bash output-guard.selftest.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/output-guard.sh"
[ -f "$GUARD" ] || { echo "FATAL: $GUARD not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required to build fixtures"; exit 1; }
TD="$(mktemp -d "${TMPDIR:-/tmp}/outguard-selftest.XXXXXX")"
trap 'rm -rf "$TD"' EXIT
PASS=0; FAIL=0

# write_transcript READ_TOOLS ASSISTANT_TEXT -> path to transcript.jsonl
# READ_TOOLS=1 adds one Bash tool_use row after the human turn; 0 adds none.
write_transcript() {
  local read_tools="$1" text="$2" path="$TD/transcript.jsonl"
  {
    jq -nc --arg t "hello" '{type:"user",message:{content:$t}}'
    if [ "$read_tools" = "1" ]; then
      jq -nc '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash",input:{command:"echo hi"}}]}}'
    fi
    jq -nc --arg t "$text" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}'
  } > "$path"
  printf '%s' "$path"
}

run() { # $1 transcript_path
  jq -n --arg tp "$1" '{stop_hook_active:false,transcript_path:$tp}' \
    | env HOME="$TD" HOOK_HOME="$TD/hh" CLAUDE_HEADLESS= bash "$GUARD" > "$TD/out.log" 2> "$TD/err.log"
  RC=$?
  OUT="$(cat "$TD/out.log" 2>/dev/null)"
}

expect_block() { local tp; tp="$(write_transcript "$2" "$3")"; run "$tp"; if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qE '"decision":[[:space:]]*"block"'; then echo "PASS (block): $1"; PASS=$((PASS+1)); else echo "FAIL (expected block, rc=$RC): $1 :: $OUT"; FAIL=$((FAIL+1)); fi; }
expect_pass() { local tp; tp="$(write_transcript "$2" "$3")"; run "$tp"; if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then echo "PASS (silent): $1"; PASS=$((PASS+1)); else echo "FAIL (expected silent, rc=$RC): $1 :: $OUT"; FAIL=$((FAIL+1)); fi; }

expect_block "sycophancy opener" 1 "You're absolutely right! Here is the fix."
expect_block "claim-evidence, 0 reads" 0 "The credential is dead and the cache is disabled."
expect_pass  "claim-evidence, has read + no risky claim" 1 "The credential is dead and the cache is disabled."
expect_pass  "ordinary reply" 1 "Here is the summary of the change: added a new function."

echo "----------------------------------------"
echo "output-guard selftest: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
