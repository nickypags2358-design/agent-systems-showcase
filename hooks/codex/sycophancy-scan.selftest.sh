#!/usr/bin/env bash
# sycophancy-scan.selftest.sh — drives sycophancy-scan.sh --test mode.
# Run with: bash sycophancy-scan.selftest.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/sycophancy-scan.sh"
[ -f "$GUARD" ] || { echo "FATAL: $GUARD not found"; exit 1; }
PASS=0; FAIL=0

expect() { # $1 = text  $2 = expected substring of VERDICT
  local out; out="$(bash "$GUARD" --test "$1")"
  if printf '%s' "$out" | grep -qF "$2"; then echo "PASS ($2): $1"; PASS=$((PASS+1)); else echo "FAIL (expected '$2', got '$out'): $1"; FAIL=$((FAIL+1)); fi
}

expect "You're absolutely right, let's fix it." "BLOCK"
expect "That is a really good point about the schema." "BLOCK"
expect "The fix changes the retry limit from 3 to 5." "clean"
expect "You've got this, keep going!" "BLOCK"

echo "----------------------------------------"
echo "sycophancy-scan selftest: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ]
