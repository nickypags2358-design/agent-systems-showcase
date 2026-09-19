#!/usr/bin/env bash
# claim-evidence-guard.selftest.sh — drives claim-evidence-guard.sh --test mode.
# Run with: bash claim-evidence-guard.selftest.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/claim-evidence-guard.sh"
[ -f "$GUARD" ] || { echo "FATAL: $GUARD not found"; exit 1; }
PASS=0; FAIL=0

expect() { # $1 = text  $2 = expected substring of VERDICT
  local out; out="$(bash "$GUARD" --test "$1")"
  if printf '%s' "$out" | grep -qF "$2"; then echo "PASS ($2): $1"; PASS=$((PASS+1)); else echo "FAIL (expected '$2', got '$out'): $1"; FAIL=$((FAIL+1)); fi
}

expect "The API key is dead." "BLOCK"
expect 'The API key is dead. Verified this run: ```curl -I https://api.example.com``` -> 401' "clean"
expect "Here is the diff for the retry logic." "clean"
expect "3 jobs were deployed this morning." "BLOCK"

echo "----------------------------------------"
echo "claim-evidence-guard selftest: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
