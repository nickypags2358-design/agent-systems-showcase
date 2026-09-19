# Proof of work

Excerpts of a running personal agent estate. Portions only, deliberately incomplete.

The rest of this repository is code you can run. This section is different: it is a
set of documents cut from the private system that code came from, so the counts in
the root README have something behind them. Nothing on these pages is verifiable from
this repository. What can be verified is `./verify.sh` at the root.

Each page states the date, or the month, its numbers were measured where the source
records one. Each was redacted to the same rule: keep the shape, the counts and the
honesty framing; drop the mechanism, the names and the paths.

## Pages

**[System atlas](system-atlas.md)** ([standalone HTML](system-atlas.html))
The estate at a glance. A component register of 2,692 components in 10 categories and
a generated system diagram of 63 nodes across 12 planes. Describes the three execution
lanes, the hook plane by lifecycle event, the fail-closed security plane, the scheduler
and its cadence bands, and how the parts gate each other. The HTML version is the same
content with an inline SVG plane diagram, no external assets, and a print stylesheet.

**[Client case brief](client-case-brief.md)**
What was designed for a consumer brand in a regulated-claims category that wanted to
depend less on a single marketplace: fifteen specialist systems under one supervisor, six of them
written in full, a five-list refusal layer, a whitelist-only claims gate, and a
measurement contract that forbids estimates. Presented as design work, not results:
per the deliverable, eleven of the fifteen systems are designed and not built, and
nothing has ever been switched on.

**[Automation evidence, 90 days](automation-evidence-90d.md)**
A short-term review of the estate over mid-June to mid-September 2026. Job liveness,
enforcement inventory, commit activity, 259 unattended social deliveries across five
platforms, per-platform outcomes with the small-base caveat stated, and the
unflattering half: an escalation backlog, config drift and red CI. Every figure was
read off a dashboard or a ledger or is marked UNMEASURED. Outcomes may change.

## What is deliberately left out

> **Paths.** No absolute or home-relative file paths. The source documents warn that
> paths carry private machine information; they were removed rather than trimmed.
>
> **Component names.** No hook, script, agent, job, plugin or scheduler-entry file
> names beyond the seven hooks already open-sourced in this repository. Mechanisms are described
> by what they do.
>
> **Schedules.** Cadence bands (fast, hourly, daily, weekly) are kept. Individual job
> names, clock times and per-row grace values are not.
>
> **Identities.** No client names, product names, marketplace names, account
> handles, vendor tool names beyond Claude Code, which the root README names, machine
> names, OS versions or disk figures.
>
> **Money.** No pricing, contract terms or revenue. Where the source says attributed
> revenue is UNMEASURED, that word is kept.

## How to read the numbers

- Counts differ between pages because they were measured on different days by
  different instruments (a register, a generated diagram, a 90-day review). Each table
  states its own date, or month, where the source records one. Nothing was reconciled
  by hand, and the root README carries yet another snapshot.
- Where a source labels something UNMEASURED, UNKNOWN, BLOCKED or NOT_SCORED, the label
  is reproduced. A blank was never converted into a pass.
- Self-reported figures from a client deliverable are marked "per the deliverable".

---
Excerpt of a private system · numbers as measured on the stated date · portions intentionally omitted
