#!/usr/bin/env bash
# eval-run.sh — deterministic golden-set runner (self-contained port; no shared lib).
#
# What it does, per golden file:
#   1. Structural integrity — every line must be valid JSON and carry the required keys
#      (id, date, source, title, resolution_excerpt, label). A malformed/short line is a
#      structural FAIL.
#   2. Field-presence summary — counts how many rows populate each required key.
#   3. Scoring oracle — the `label` field IS the oracle. Rows labeled FP/TP are the scored
#      set; UNLABELED rows are pending human triage and are EXCLUDED from the pass-rate
#      (reported separately so coverage is never silently inflated).
#   4. Optional --dry-run classifier stub — a deterministic, rule-based scorer that guesses
#      FP/TP from keyword heuristics in `title`, purely to demonstrate what a real scoring
#      step would compare against `label`. It never calls a model or a network service.
#
# Usage:
#   eval-run.sh                 # run the default sample golden set
#   eval-run.sh <file.jsonl>    # run one file
#   eval-run.sh --dry-run       # also run the rule-based classifier stub and score it
#
# Env overrides:
#   EVAL_GOLDEN   default golden file (default: $SELF_DIR/golden/escalation-golden.sample.jsonl)
#   EVAL_OUT      results directory   (default: ${TMPDIR:-/tmp}/evals)
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GOLDEN_DEFAULT="${EVAL_GOLDEN:-$SELF_DIR/golden/escalation-golden.sample.jsonl}"
OUT_DIR="${EVAL_OUT:-${TMPDIR:-/tmp}/evals}"
mkdir -p "$OUT_DIR" 2>/dev/null || true
RLOG="$OUT_DIR/eval-run.log"
REQUIRED_KEYS="id date source title resolution_excerpt label"
HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1

DRY_RUN=0
files=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    *) files+=("$a") ;;
  esac
done
[ "${#files[@]}" -eq 0 ] && files=("$GOLDEN_DEFAULT")

now() { date '+%Y-%m-%d %H:%M:%S'; }
note() { printf '%s | eval-run | %s\n' "$(now)" "$1" >> "$RLOG" 2>/dev/null || true; }

# validate_line JSON_LINE — echoes "ok" or "bad:<reason>". Uses jq when present, else a
# python3 stdlib fallback so the runner never goes dark just because jq is missing.
validate_line() {
  local line="$1"
  if [ "$HAVE_JQ" = 1 ]; then
    printf '%s' "$line" | jq -e 'type == "object"' >/dev/null 2>&1 || { echo "bad:not-a-json-object"; return; }
    local k miss=""
    for k in $REQUIRED_KEYS; do
      printf '%s' "$line" | jq -e --arg k "$k" 'has($k)' >/dev/null 2>&1 || miss="$miss $k"
    done
    [ -n "$miss" ] && { echo "bad:missing-keys:${miss# }"; return; }
    echo "ok"
  else
    printf '%s' "$line" | REQ="$REQUIRED_KEYS" python3 -c '
import sys, os, json
try:
    o = json.loads(sys.stdin.read())
except Exception:
    print("bad:invalid-json"); sys.exit(0)
if not isinstance(o, dict):
    print("bad:not-a-json-object"); sys.exit(0)
miss = [k for k in os.environ["REQ"].split() if k not in o]
print("bad:missing-keys:" + ",".join(miss) if miss else "ok")
' 2>/dev/null || echo "bad:checker-error"
  fi
}

label_of() {
  local line="$1"
  if [ "$HAVE_JQ" = 1 ]; then
    printf '%s' "$line" | jq -r '.label // "UNLABELED"' 2>/dev/null || echo UNLABELED
  else
    printf '%s' "$line" | python3 -c 'import sys,json
try: print(json.loads(sys.stdin.read()).get("label","UNLABELED") or "UNLABELED")
except Exception: print("UNLABELED")' 2>/dev/null || echo UNLABELED
  fi
}

# classify_dry_run TITLE — deterministic rule-based stub standing in for a real model call.
# Keyword heuristic only: never a network call, never an LLM. Demonstrates the scoring slot.
classify_dry_run() {
  local title_lc
  title_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$title_lc" in
    *duplicate*|*known*|*already*|*sentinel*|*self-test*|*test*) echo "FP" ;;
    *expired*|*full*|*flaky*|*credential*|*secret*|*leak*) echo "TP" ;;
    *) echo "UNLABELED" ;;
  esac
}

[ "$HAVE_JQ" = 1 ] || echo "eval-run: jq not found — using python3 stdlib fallback for validation"
echo "eval-run — golden eval runner"
echo "  oracle: .label  (FP/TP = scored; UNLABELED = excluded, pending human triage)"
[ "$DRY_RUN" = 1 ] && echo "  --dry-run: rule-based classifier stub active (no model, no network)"

tot_cases=0; tot_struct_fail=0; tot_fp=0; tot_tp=0; tot_un=0; tot_other=0; files_run=0
tot_dry_correct=0; tot_dry_scored=0

for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "  x $f — not a file (skipped)"; continue; }
  files_run=$((files_run+1))
  cases=0; sfail=0; fp=0; tp=0; un=0; other=0; firstbad=""
  dry_correct=0; dry_scored=0
  pres_id=0; pres_date=0; pres_source=0; pres_title=0; pres_excerpt=0; pres_label=0

  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "${line// /}" ] && continue
    cases=$((cases+1))
    res="$(validate_line "$line")"
    if [ "$res" != "ok" ]; then
      sfail=$((sfail+1))
      [ -z "$firstbad" ] && firstbad="line $cases: $res"
      continue
    fi
    if [ "$HAVE_JQ" = 1 ]; then
      printf '%s' "$line" | jq -e '.id                 | (. != null and . != "")' >/dev/null 2>&1 && pres_id=$((pres_id+1))
      printf '%s' "$line" | jq -e '.date               | (. != null and . != "")' >/dev/null 2>&1 && pres_date=$((pres_date+1))
      printf '%s' "$line" | jq -e '.source             | (. != null and . != "")' >/dev/null 2>&1 && pres_source=$((pres_source+1))
      printf '%s' "$line" | jq -e '.title              | (. != null and . != "")' >/dev/null 2>&1 && pres_title=$((pres_title+1))
      printf '%s' "$line" | jq -e '.resolution_excerpt | (. != null and . != "")' >/dev/null 2>&1 && pres_excerpt=$((pres_excerpt+1))
      printf '%s' "$line" | jq -e '.label              | (. != null and . != "")' >/dev/null 2>&1 && pres_label=$((pres_label+1))
    fi
    label="$(label_of "$line")"
    case "$label" in
      FP) fp=$((fp+1));;
      TP) tp=$((tp+1));;
      UNLABELED|"") un=$((un+1));;
      *) other=$((other+1));;
    esac
    if [ "$DRY_RUN" = 1 ] && { [ "$label" = "FP" ] || [ "$label" = "TP" ]; }; then
      title="$(printf '%s' "$line" | { [ "$HAVE_JQ" = 1 ] && jq -r '.title' || python3 -c 'import sys,json;print(json.loads(sys.stdin.read()).get("title",""))'; })"
      guess="$(classify_dry_run "$title")"
      dry_scored=$((dry_scored+1))
      [ "$guess" = "$label" ] && dry_correct=$((dry_correct+1))
    fi
  done < "$f"

  scored=$((fp+tp))
  decided=$((fp+tp+other))
  if [ "$cases" -gt 0 ]; then
    cov="$(printf '%s %s' "$decided" "$cases" | awk '{printf "%.0f", ($2>0)?($1*100/$2):0}')"
  else cov=0; fi

  echo
  echo "  file: $f"
  echo "    cases=$cases  struct_fail=$sfail  labels: FP=$fp TP=$tp UNLABELED=$un other=$other"
  if [ "$HAVE_JQ" = 1 ]; then
    echo "    field-presence (non-empty): id=$pres_id date=$pres_date source=$pres_source title=$pres_title resolution_excerpt=$pres_excerpt label=$pres_label / $cases"
  fi
  echo "    scored set (FP+TP)=$scored  label-coverage=${cov}% (decided=$decided of $cases)"
  if [ "$DRY_RUN" = 1 ]; then
    echo "    dry-run classifier: $dry_correct/$dry_scored correct against .label"
  fi
  if [ "$sfail" -gt 0 ]; then
    echo "    FAIL structural — first: $firstbad"
  else
    echo "    OK structural integrity (all $cases lines valid JSON with required keys)"
  fi

  tot_cases=$((tot_cases+cases)); tot_struct_fail=$((tot_struct_fail+sfail))
  tot_fp=$((tot_fp+fp)); tot_tp=$((tot_tp+tp)); tot_un=$((tot_un+un)); tot_other=$((tot_other+other))
  tot_dry_correct=$((tot_dry_correct+dry_correct)); tot_dry_scored=$((tot_dry_scored+dry_scored))
done

tot_scored=$((tot_fp+tot_tp)); tot_decided=$((tot_fp+tot_tp+tot_other))
if [ "$tot_cases" -gt 0 ]; then
  tot_cov="$(printf '%s %s' "$tot_decided" "$tot_cases" | awk '{printf "%.0f", ($2>0)?($1*100/$2):0}')"
else tot_cov=0; fi

verdict=PASS; [ "$tot_struct_fail" -gt 0 ] && verdict=FAIL
echo
note "files=$files_run cases=$tot_cases struct_fail=$tot_struct_fail FP=$tot_fp TP=$tot_tp UNLABELED=$tot_un dry_correct=$tot_dry_correct/$tot_dry_scored -> $verdict"
if [ "$DRY_RUN" = 1 ] && [ "$tot_dry_scored" -gt 0 ]; then
  echo "eval-run: SUMMARY files=$files_run cases=$tot_cases struct_fail=$tot_struct_fail scored=$tot_scored(FP=$tot_fp/TP=$tot_tp) unlabeled=$tot_un label-coverage=${tot_cov}% dry_run=${tot_dry_correct}/${tot_dry_scored} -> $verdict"
else
  echo "eval-run: SUMMARY files=$files_run cases=$tot_cases struct_fail=$tot_struct_fail scored=$tot_scored(FP=$tot_fp/TP=$tot_tp) unlabeled=$tot_un label-coverage=${tot_cov}% -> $verdict"
fi
[ "$tot_struct_fail" -eq 0 ] || exit 1
exit 0
