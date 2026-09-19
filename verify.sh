#!/usr/bin/env bash
# verify.sh — single entrypoint for local verification and CI.
# Runs: bash -n, shellcheck (if installed), py_compile, every *.selftest.sh,
# the eval runner on the sample golden set, the drift-checker demo, and a scan
# for absolute home paths (the tree must stay machine-independent).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
fail=0
step() { printf '\n== %s\n' "$*"; }

step "bash -n"
while IFS= read -r f; do bash -n "$f" || { echo "SYNTAX FAIL $f"; fail=1; }; done \
  < <(find . -name '*.sh' -not -path './.git/*' | sort)

step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck -S warning || fail=1
else
  echo "shellcheck not installed locally; skipped (CI runs it)"
fi

step "py_compile"
find . -name '*.py' -not -path './.git/*' -print0 | xargs -0 python3 -m py_compile || fail=1

step "selftests"
while IFS= read -r t; do
  if bash "$t" >/dev/null 2>&1; then echo "PASS $t"; else echo "FAIL $t"; bash "$t" 2>&1 | tail -20; fail=1; fi
done < <(find hooks -name '*.selftest.sh' | sort)

step "eval runner (sample golden set)"
bash evals/eval-run.sh || fail=1

step "drift checker demo (drift is expected on the fixtures)"
bash scripts/agents-md-drift.sh scripts/fixtures/a.md scripts/fixtures/b.md || true

step "no absolute home paths in tree"
if grep -rnE '/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/' . --exclude-dir=.git --exclude=verify.sh; then
  echo "FOUND machine paths"; fail=1
else
  echo "clean"
fi

if [ "$fail" -eq 0 ]; then printf '\nALL CHECKS PASSED\n'; else printf '\nCHECKS FAILED\n'; fi
exit "$fail"
