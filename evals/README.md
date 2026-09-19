# evals — golden-set eval runner

A **golden set** is a small JSONL file of past incidents that were manually reviewed and
labeled true-positive (`TP`, a real escalation) or false-positive (`FP`, noise that
shouldn't have paged anyone). It is the oracle a change-detection or alert-routing system
gets checked against, so drift in that system shows up as a scoring regression instead of
silence.

## Schema (one JSON object per line)

| key | meaning |
|---|---|
| `id` | stable identifier, `<source-file>:<line>` |
| `date` | ISO date the incident occurred |
| `source` | the system that raised it |
| `title` | one-line summary |
| `resolution_excerpt` | how it was actually resolved (the evidence behind the label) |
| `label` | `TP`, `FP`, or `UNLABELED` (pending human triage — excluded from the pass rate) |

`evals/golden/escalation-golden.sample.jsonl` ships 8 synthetic rows covering common
shapes: infra noise (disk full, flaky test, duplicate alert), real regressions (expired
cert, stuck canary), a secret-pattern false positive, a self-test false positive, and one
`UNLABELED` row to show triage coverage reporting.

## Run it

```bash
bash evals/eval-run.sh                    # runs the sample set
bash evals/eval-run.sh path/to/other.jsonl
EVAL_GOLDEN=/path/to/custom.jsonl bash evals/eval-run.sh
bash evals/eval-run.sh --dry-run          # also runs the rule-based classifier stub
```

Results/log land under `${EVAL_OUT:-${TMPDIR:-/tmp}/evals}`.

## What it scores

1. **Structural integrity** — every line is valid JSON with all six required keys.
2. **Field-presence** — how many rows populate each key (data-quality signal).
3. **Label coverage** — share of rows with a decided `TP`/`FP` label vs. `UNLABELED`.
4. **`--dry-run` only:** a deterministic, keyword-based classifier stub stands in for a
   real model call, scored against `.label`, so the runner demonstrates the slot a real
   scorer would fill without invoking any LLM or network service.

The runner never calls a model or the network. It is a data-side structural/coverage
check, not a judgment eval — see `skills/eval-design/SKILL.md` for how to design the
judgment layer on top of this (metric shape, gate vs. holdout, oracle ownership) and how
this golden set should grow over time.
