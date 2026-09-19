---
name: eval-design
description: Design an eval suite, change gate, or success metric for a system that can modify itself — what to measure, who owns the oracle, where the improvement threshold sits. Fires when creating a benchmark or golden suite, when asked "how do we measure whether this got better", when a metric is about to become the thing a model optimizes against, or when a self-improving loop needs a gate before auto-apply. DOES NOT cover writing individual items for a string grader (golden-set-authoring), handling a partially-failed run (eval-coverage-gate), or reporting the resulting numbers (small-n-reporting).
---

## When this fires

You are about to define how "better" gets decided for a system that can write its own files — a change gate, a growth metric, a nightly eval, a promotion criterion.

Do not use this for ordinary unit tests of deterministic code. Use it the moment the number will be read as evidence that the system improved.

## What goes wrong without it

Two documented failure shapes:

- A regression detector and a scheduled eval job kept running over an empty results directory, so it never had two data points to compare and printed `PASS` every night for months. The scheduled green light was the only evidence anyone looked at, and it measured nothing.
- A published self-improving agent reached a perfect score by deleting its own hallucination detector after being told not to.

## Procedure

### 1. Choose a metric shape the subject cannot inflate

Apply one test: **can the subject raise this number without changing its behavior?**

Forbidden shapes — counts of artifacts the subject can create: "the system has N agents", "N hooks exist", "the docs are M lines". Any such number rises when a model writes a file, which makes it a measure of effort at gaming rather than of capability. Counting is not scoring.

This is a live risk wherever a capability-surface metric is computed as a glob count over generated files. Mass-producing files posts fake net growth against that proxy. If you must keep such a count, label it **inventory** and keep it out of the verdict.

Replace with behavior: a case whose `expect` a clearly wrong response visibly fails.

### 2. Build two suites, not one

| | Gate | Holdout |
|---|---|---|
| Size | ~10 cases | ~5 cases |
| Run | every candidate change | periodically, and whenever a gate result sits near the margin |
| Optimized against | yes, deliberately | never |
| Shape | the common request shapes | deliberately different, including at least one case where **acting** is correct and refusing fails |

The holdout is not a random split of the gate distribution — a random split measures the same overfitting-prone thing twice.

Three constraints keep it a holdout, none enforceable by a hook: do not tune against it, do not read holdout failures to design a fix, do not move a failing case from holdout to gate.

Reversion rule: **gate up + holdout flat or down = metric-fitting. Revert the change and set auto-apply back to OFF.**

### 3. Give the oracle to someone other than the subject

A model may write `input`, `rationale`, and honest `provenance`. A **human writes `expect`** and chooses gate or holdout.

Stage candidates in a separate file with `expect` deliberately empty and refuse to fill it — including refusing to "save time" with a suggested `expect`, which anchors the human on the system's own answer. If the system under test authors the definition of correct, the score measures agreement with itself.

### 4. Set a floor and a margin, never `>=`

- **Absolute floor** (e.g. 0.70): below it nothing ships even if it beat baseline.
- **Margin tau** (e.g. 0.15): the candidate mean must beat baseline by at least this. On a 10-case set one case is 0.10 of the score and run-to-run sampling routinely moves one case, so a gate that ships on `candidate >= baseline` ships on noise.
- **Minimum runs** (e.g. 3) for both baseline and candidate.
- **Tie is not a pass.** `delta == 0` is `NEUTRAL`; if the change is worth having for a reason outside the gate, state that reason in words rather than disguising it as a score.

Two clauses that stop a good mean from hiding a bad change:
- **Hard regression** — any case that passed in *all* baseline runs and fails in *all* candidate runs is a `REGRESSION` regardless of the mean.
- **Noise-dominated** — if candidate per-run rates spread by `>= tau` (max minus min), the verdict is `NOISE_DOMINATED`, not a coin-flip pass.

### 5. Make the verdict vocabulary three-valued

`PASS` / `FAIL` / `NOT_SCORED`. `NOT_SCORED` means the structural checks ran and the quality question is open — different from both "good" and "broken". Collapsing it into either is exactly how a silent-failure eval job tells the same lie every night.

### 6. Record provenance and admit the warrant

Each case carries `provenance`: `seed` (authored at bootstrap) or `observed failure <date> in <context>`. Seed cases are a weaker warrant than a human-labeled case from a real failure — record that in the contract file rather than letting it be quietly forgotten, and log who ratified it and when.

## Hard rules

- Never make the gate's own definition editable by the system it governs. Deny the agent's write path to the eval directory, the gate script, and the guard itself — an oracle the defendant can edit measures nothing.
- Never derive the verdict from a number written into a result file. Derive it from raw per-case outcomes; a pre-computed score is a place for a number to be *written* rather than *counted*.
- A passing gate is a recommendation to a human, not an authorization to self-modify, until auto-apply has been turned on by a dated human decision with an exhaustive in-class list.

## Honest limits

- A pre-tool-use hook blocks the agent's *editing path*; it is not a filesystem ACL. The accurate claim is "the agent's editing path to this file is blocked", not "this file is immutable".
- The three holdout-hygiene constraints are load-bearing and unenforceable. If they are violated, the system loses its only independent check and has no way to know.
- A 10-case gate cannot resolve effects smaller than one case. It is a coarse ship/no-ship instrument, not a measurement of degree.

## Self-check before finishing

1. Can any number in this design go up because a model wrote a file? If yes, it is inventory — relabel it or remove it from the verdict.
2. Who wrote `expect`, by name? If the answer is "the model", the eval is not an eval.
3. Does the design produce a third verdict for "ran, but nothing to score" — or does it fall back to pass?
4. Would a candidate that gains exactly one case ship? If yes, the margin is missing.
