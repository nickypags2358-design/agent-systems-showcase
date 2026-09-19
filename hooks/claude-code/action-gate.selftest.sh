#!/usr/bin/env bash
# action-gate.selftest.sh — bidirectional proof for action-gate.sh.
#   BLOCK — HARD-ASK rows must deny (rc 2) and the reason must name the class.
#   ASK   — ASK rows must emit permissionDecision "ask" and exit 0.
#   PASS  — ordinary work must exit 0 with NO output (catches an over-matching guard).
# Run with: bash action-gate.selftest.sh
# Hermetic: run from a clean env, e.g. `env -i HOME=/tmp/x PATH=$PATH bash action-gate.selftest.sh`
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/action-gate.sh"
[ -f "$GUARD" ] || { echo "FATAL: $GUARD not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required to build fixtures"; exit 1; }

TD="$(mktemp -d "${TMPDIR:-/tmp}/actiongate-selftest.XXXXXX")"
trap 'rm -rf "$TD"' EXIT
PASS=0; FAIL=0

run() { # $1 tool_name   $2 command (empty => Read-shaped input)
  if [ -n "${2:-}" ]; then
    jq -n --arg t "$1" --arg c "$2" '{tool_name:$t,tool_input:{command:$c}}' > "$TD/payload.json"
  else
    jq -n --arg t "$1" '{tool_name:$t,tool_input:{file_path:"/tmp/notes.md"}}' > "$TD/payload.json"
  fi
  env HOME="$TD" HOOK_HOME="$TD/hh" ACTION_GATE_HEADLESS= ACTION_GATE_REPORT= bash "$GUARD" \
    > "$TD/out.log" 2> "$TD/err.log" < "$TD/payload.json"
  RC=$?
  OUT="$(cat "$TD/out.log" "$TD/err.log" 2>/dev/null)"
}

expect_block() { run "$1" "${2:-}"; if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -qF '"deny"' && printf '%s' "$OUT" | grep -qF "$3"; then echo "PASS (block/$3): $1 ${2:-}"; PASS=$((PASS+1)); else echo "FAIL (expected block+'$3', rc=$RC): $1 ${2:-} :: $OUT"; FAIL=$((FAIL+1)); fi; }
expect_ask() { run "$1" "${2:-}"; if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF '"permissionDecision":"ask"' && printf '%s' "$OUT" | grep -qF "$3"; then echo "PASS (ask/$3): $1 ${2:-}"; PASS=$((PASS+1)); else echo "FAIL (expected ask+'$3', rc=$RC): $1 ${2:-} :: $OUT"; FAIL=$((FAIL+1)); fi; }
expect_pass() { run "$1" "${2:-}"; if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then echo "PASS (silent): $1 ${2:-}"; PASS=$((PASS+1)); else echo "FAIL (expected silent exit 0, rc=$RC): $1 ${2:-} :: $OUT"; FAIL=$((FAIL+1)); fi; }

M='mcp__example_social__'

echo "-- HARD-ASK: external publish / outbound send --"
expect_block "${M}publish_post" ""      "external publish"
expect_block "${M}send_dm" ""           "external publish"

echo "-- HARD-ASK: security/system config, mass delete, money, force-push --"
expect_block Bash 'rm -rf ~/x'                          "mass deletion"
expect_block Bash 'sudo rm -rf /'                        "mass deletion"
expect_block Bash 'sudo csrutil disable'                 "security/system config"
expect_block Bash 'cat /tmp/k.pub >> ~/.ssh/authorized_keys' "remote-access vector"
expect_block Bash 'stripe payouts create --amount 100'   "money movement"
expect_block Bash 'git push --force origin main'         "force push"

echo "-- ASK rows --"
expect_ask Bash 'git push origin feat/x'   "git push"
expect_ask Bash 'git commit -m "wip"'      "git commit"
expect_ask Bash 'npm install left-pad'     "install_dependency"

echo "-- PASS: ordinary work must be silent --"
expect_pass Read ""
expect_pass Bash 'git log --oneline -5'
expect_pass Bash 'rm -rf /tmp/scratch/build'
expect_pass Bash 'npm run build'
expect_pass "${M}list_posts" ""

echo "----------------------------------------"
echo "action-gate selftest: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
