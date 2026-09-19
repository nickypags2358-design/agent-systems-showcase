# Client case brief: what we designed for a consumer brand in a regulated-claims category

Anonymized. The client, its product name, its primary marketplace and every
third-party brand named in the original deliverable are removed. Counts in this page
are self-reported in the deliverable; none was externally verified. No figure here is a
business result.

## The ask

A consumer brand in a regulated-claims category wanted to reduce its dependence on a
single marketplace. We designed
a software-based growth-marketing team: fifteen specialist systems, each owning one job
a human marketing team would handle, every one supervised by the business owners rather
than running loose.

## What "designed" means here

The deliverable says this up front, and this page keeps it:

- Where a system is marked **designed**, the plan exists and the build does not. Where
  a system is marked **built**, the thing itself exists.
- Most of it has not been built. None of it has ever been switched on.
- A global gate file defaults to a "nothing runs" state. Each system is switched on
  individually, with a specific yes from the owner, and only after the system it
  depends on is working. Turning on all fifteen at once would be the fastest way to
  produce confident nonsense at scale.

Per the deliverable: eleven of the fifteen systems are designed, not built; nothing has
run; no credentials are held; four client asks were never counted in projections; eight
contradictions between sourced figures remain unresolved.

## Architecture

One supervisor sits above the fifteen. It decides the day's priorities, the order of
work, and what must halt for a human. It does no marketing itself. It runs the room.

Six specialist operating documents are written in full:

| Specialist | Owns | Deciding question, where the deliverable states one |
|---|---|---|
| Top brain (supervisor) | Daily priorities, ordering, and what must halt for a human | |
| Outreach | Writes, checks and queues social posts; tags every link so attribution is possible | A real person moving from a feed to a site page. Not likes. Not reach. A person who moved |
| AI discoverability | Keeps product information consistent everywhere; asks AI assistants a standing question set on a schedule, records what they say, tracks change after interventions | Is this brand described accurately by an assistant, and can we prove the answer changed? |
| Marketplace digest | Reads marketplace reports and reduces them to a short list of what needs a human hand this week | |
| Claims | Checks every sentence before publication against what may legally be said about the product | |
| Measurement | Pulls every channel onto one board; refuses to guess at any number it cannot see | |

The remaining systems are specified, not written in full. Among them: product data held in
one structured place and pushed outward instead of hand-maintained across six surfaces;
a website system that changes one thing at a time so the result is readable; a
separate email lifecycle system (welcome, education, post-purchase, replenishment,
win-back); a channel-allocation loop where every post is assigned to a test arm, results
are read back twice weekly and effort moves toward what measurably works while
exploration stays mandatory; and a community system whose deciding question is
deliberately narrow (did a member come back, buy or bring someone) so that "engagement"
cannot be reported as a result on its own.

## The refusal layer

Guardrails are written as rules the system checks, not advice it is supposed to
remember. Five lists:

1. **Banned phrases.** Certain words can never appear in anything published.
2. **Competitor names.** Competitors are studied and never named in public output.
3. **Credential patterns.** Anything resembling a password or an API key in the wrong
   place halts the system.
4. **Stop conditions.** Written situations where the correct behaviour is to halt and
   ask a person rather than proceed.
5. **Never-do list.** Permanent refusals. Among them: never log into or automate the
   client's account on that marketplace, because no marketing gain is worth risking it.

Stopping is a designed feature, not a bug. A system that halts and asks is worth more
than one that guesses confidently.

### The claims gate

Nothing on any channel is published without passing it, and it works from a whitelist:
only sentences that have been explicitly approved can go out; everything else is
blocked by default. The whitelist ships empty on purpose, so the system cannot publish
any product claim until a compliance person or lawyer populates it. In the deliverable's
words: we built the lock before we built the door.

## Measurement contract

- Every reporting cell is exactly one of three things: a real number traceable to a
  named screen, an explicit zero, or UNAVAILABLE. There is no fourth option, and
  estimates are not permitted.
- Deciding metrics are named in advance. Followers, impressions and reach are listed as
  things never reported as a result.
- Three append-only ledgers (channels, posts, results). Rows are never edited or
  deleted; a wrong row is marked superseded and the original stays visible, so what was
  believed at any point in time can be reconstructed.
- One contradiction between this contract and a later view-based target is disclosed in
  the deliverable rather than hidden.

## Operating runbook

A written runbook with six named session types, five of which are summarized here:

| Session | Cadence | Purpose |
|---|---|---|
| Daily build | daily, about 20 minutes | Move one system forward |
| Readback | twice weekly | Read results into the ledgers |
| Weekly review | weekly, one page, six blocks | Decide what changes |
| Monthly roll-up | monthly | Aggregate |
| Cycle close | day 31 | Continue, change or stop |

## Pain point, and what answers it

| Pain point the client raised | What was designed to answer it |
|---|---|
| Heavy dependence on one marketplace | Fifteen owned channels and systems, each with its own deciding question; the marketplace account itself is on the never-automate list |
| Marketplace reports nobody has time to read | Marketplace digest: a short weekly list of what needs a human hand |
| Product facts inconsistent across surfaces | Structured product data in one place, pushed outward |
| Unknown what AI assistants say about the brand | Scheduled standing questions, answers recorded, change tracked |
| Claims language in a regulated category | Whitelist-only claims gate, shipped empty until counsel fills it |
| Reports that mix guesses with numbers | Three-value rule: number with a named screen, explicit zero, or UNAVAILABLE |
| Social activity with no evidence it sells | Outreach measured on a person moving to a site page; test arms on every post; read back twice weekly |
| "Engagement" reported as a result | Community deciding question narrowed to came back, bought or brought someone |
| One further ask | Answered "no system currently owns this". The deliverable declines to invent a component to make the row look complete |

## Access and safety policy

Read-only scoped access through an invitation under the client's own account, never a
shared password. Stated as non-negotiable. No credentials are held.

## Honesty ledger

- The written record is roughly 250 documents, per the deliverable: the diagnosis, the
  analysis behind each recommendation, specs for all fifteen systems, the runbook, and a
  self-audit naming the team's own mistakes and their direction.
- Three separate documents open by correcting an earlier document from the same team.
  The record argues with itself.
- Self-reported error: the team's own forecasts never counted any improvement from the
  test-and-learn loop. That was flagged as their error rather than left in their
  favour.
- Positioning, per the deliverable: the refusal layer is presented as the hardest part
  to buy.

---
Excerpt of a private system · numbers as measured on the stated date · portions intentionally omitted
