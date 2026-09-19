# Automation evidence: a 90-day review

**Short-term review. Outcomes may change.**

Window: mid-June to mid-September 2026. Every figure on this page was read directly
off a platform dashboard or an on-disk ledger, or is marked UNMEASURED. Nothing is
modelled or projected. Attributed revenue is UNMEASURED; there is none to report.

## Two clocks

Two different clocks are in play and are not to be conflated:

- The automation estate has run continuously since 2026-05-29, roughly three and a half months at
  the time of review. Version control began later, on 2026-06-27. That is when tracking
  started, not when the system started.
- The on-disk posting ledger on the current host spans only 13 days.

Estate figures below are on the first clock. Posting-output figures are on the second.

## Estate at a glance (mid-September 2026)

| Measure | Count |
|---|---|
| Scheduled jobs in the orchestrator manifest | 144 |
| Jobs that actually ran in the preceding 24 hours | 125 (about 87%) |
| Jobs stale by more than 7 days | 2 |
| OS scheduler entries installed | 32 |
| Enforcement hooks | 39 |
| Specialist subagents | 36 |
| Skills (codified procedures) | 58 |
| Oversight scripts | 102 |
| Commits to the system repository in 90 days | 435, of which 17 explicitly fix/repair |

Commit activity by month: June 29, July 8, August 219, September 179.

About 87% liveness is a fact about execution, not about usefulness. It says the jobs
ran. It does not say they were worth running.

## What runs unattended

Daily: briefing, self-test, integrity and pin guards, posting, outcome and repository
audits, cost reporting, consolidation, growth. Fast-interval: security and breach
monitoring. Weekly: security, supply-chain and patch audits.

## Guardrails recorded in the review

- Paid advertising is permanently off across all platforms by standing policy. All
  reach below is organic.
- A publish gate OCRs every outbound visual at multiple rotations to block vendor,
  tool and path leaks before posting.
- Hook integrity is checked against a blessed tamper manifest. Secret-shape vetoes
  block credential-looking output.

## Posting output (13-day ledger)

259 social deliveries across 5 platforms in 13 days, scheduled rather than hand-posted.

| Platform | Deliveries |
|---|---|
| X | 72 |
| Facebook | 64 |
| Threads | 58 |
| LinkedIn | 55 |
| Instagram | 10 |

Ledger status: 234 POSTED, 9 LINK-REPLY, 3 STAGED, 1 UNVERIFIED, 1 DELETED-BY-OWNER,
1 BLOCKED, 1 ANOMALY (250 of 259 deliveries carry one of these statuses; 9 rows carry no status in the source).

Cadence gaps, admitted: 4 of the 13 days produced zero posts, and 2 more produced under
5. The daily slot count is fixed per platform and was reduced mid-window.

Each slot is assigned an audience, an objective, an A/B arm and a UTM. Per-post readback
captured 138 rows, 511 impressions, 7 engagements, 0 link clicks and 0 follows. With zero
recorded clicks the optimiser correctly remains in EXPLORE with no A/B verdict. The
review calls the per-post attribution layer the weak link.

## 90-day platform outcomes

| Platform | Measure | Value | Change |
|---|---|---|---|
| X | Impressions | about 43K | up about 800% |
| X | Engagements | about 3.6K | engagement rate about 8% |
| Instagram | Views | about 11,000 | up about 400% |
| Instagram | Viewers | about 5,700 | up about 700%, 95% non-followers |
| Instagram | Interactions | about 1,400 | up about 1,500% |
| Instagram | Net followers | +45 | up about 1% |
| Facebook | 3-second views | about 13,000 | up about 600%, 99% from non-followers, 84% from Reels |
| YouTube | Views | about 650K | flat |
| YouTube | Watch time | | down about 9% |
| YouTube | Subscribers | +510 | |

The source shows two captures of the X dashboard for the same window; only one is
reproduced here, so the delta between them is not visible on this page.

The asymmetry, stated: several-hundred-percent gains on small bases are not the same
kind of evidence as movement on a 650K-view channel. YouTube, the only mature
high-volume channel, was flat on views and down on watch time.

## What is not claimed

- **Causation.** Posting ran throughout the window, so there is no control period to
  compare against.
- **Revenue.** UNMEASURED.
- **Cadence held.** It did not; see the gaps above.
- **System healthy.** See the next section.
- **A/B learning.** Zero recorded clicks; the optimiser has no verdict.

## The unflattering half

At review time: 1,050 open escalations in the inbox, 2,099 open work-queue rows,
measured config drift against canon, and red CI.

The review's own verdict: the monitoring layer works and the remediation layer does not
keep up. That produces observability, not control.

## What would make this evidence stronger

Three gaps this page draws from the review, in this page's order:

1. A working per-post attribution layer. With 0 link clicks recorded, no outcome can be
   tied to a post and the optimiser cannot leave EXPLORE.
2. A control period. Without one, no reach change can be attributed to the automation.
3. A remediation layer that drains the escalation inbox faster than it fills.

## Method note

Every number on this page was read from a dashboard or a ledger. None was estimated.
Where the source shows two captures, only one is reproduced here, so the delta between
them is not visible on this page. Where the source says UNMEASURED, so does this page.

---
Excerpt of a private system · numbers as measured on the stated date · portions intentionally omitted
