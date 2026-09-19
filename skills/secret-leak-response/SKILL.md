---
name: secret-leak-response
description: A credential, API key, token, webhook secret, or env file has been committed, pushed, logged, or otherwise exposed. Fires the moment a secret is found in git history, a tracked file, a build log, a backup, or a shared artifact — and enforces rotate-first ordering before any history rewrite or force-push. DOES NOT cover fixing a scanner that false-positives on legitimate identifiers (pattern-tighten-only) or a generic live outage (crisis-response).
---

## When this fires

Any of: a scanner flags a real key in a tracked file; a secret appears in `git log -p`, a backup, a
log, or a pasted transcript; an `.env` was committed; a key is suspected compromised. Private repo
still counts — the blast radius is collaborators, CI tokens, and every existing clone.

A broader incident-response process owns the incident frame (severity, comms, post-mortem). This
skill owns the one thing that frame does not encode: **the order**.

## The order. Do not reorder it.

### Step 1 — ROTATE (first, always; it is the only step that removes the exposure)

Until the key is rotated it stays valid in every clone, every history copy, every backup, and every
CI cache. History surgery before rotation spends destructive, coordination-heavy effort while the
exposure is unchanged.

- For each exposed credential, rotate at the vendor console.
- **Check whether one regeneration invalidates all prior keys for that account.** Where it does, a
  single regen covers *every* leaked generation at once, collapsing multiple incidents into one action.
- Rotate the sibling secrets too — webhook signing secrets, refresh tokens, and anything derived from
  the leaked value.
- Paste new values only into a **gitignored** file, never back into the tracked one, then
  `chmod 600` it.
- Confirm the system still works after rotation (run the job that consumes the key). A rotation that
  breaks production silently is a second incident.

Rotation needs vendor logins — that is needs-human-hands. Do not stall: escalate with the exact
console steps, and proceed to steps 2 and 3, which you can do yourself.

### Step 2 — UNTRACK

Remove the file from tracking and stop it coming back:

```bash
git rm --cached <path>
# then add BOTH the exact path and its class to .gitignore, e.g. *-keys.env and **/*-keys.env
```

### Step 3 — GUARD

Close the mechanism, not the instance. Match the **class** by suffix (`*.env`, `*-keys.env`) so the
next differently-named file is caught even if the ignore rule misses it. Add a local secret-scanning
pre-commit/pre-push hook in addition to any server-side scan — server-side alone means the secret is
already off your machine when it is caught.

If closing the hole means changing a scanner pattern, tighten it; never loosen a credential pattern
to make a false positive go away (see `pattern-tighten-only`).

### Step 4 — PURGE HISTORY (only after rotation; destructive; coordinated)

Once rotated, the blobs hold dead strings and this is hygiene — but it rewrites history and
force-pushes, which breaks every clone and every auto-sync job if uncoordinated. Sequence:

1. **Pause the auto-sync jobs first** so they cannot re-push the old refs mid-rewrite.
2. Tell every other session (cloud, phone, second machine) to stop pushing for the window.
3. `git filter-repo --path <blob> [--path <blob2>] --invert-paths --force`
4. `git push --force origin main`, plus any branch that carries the blobs.
5. Everyone with a clone **re-clones**. Old clones still contain the blobs — which is why rotation
   was step 1.
6. Re-enable the sync jobs and verify one full cycle.

This step is low-reversibility and broad-blast. Get explicit human approval, and write the
pause/resume commands into a handover note before starting.

### Step 5 — VERIFY THE PREVENTION

Prove the two mechanisms that caused it are closed: the file is untracked, and the class-level guard
actually denies. Test the guard by attempting the thing it must block, not by reading its source.

## Hard rules

1. **Never display, echo, log, quote, or commit the secret value** — not in a report, not in a
   commit message, not in an escalation. Refer to it by path and vendor.
2. **Never resolve a leak by deleting the file in a new commit.** The blob stays in history; you have
   only hidden it from `HEAD`.
3. **Never force-push before rotation is confirmed done.** Confirmed means the old key is rejected,
   not that someone said they would rotate it.
4. **A private repo is not containment.** Scope the blast radius explicitly: collaborators, CI, forks,
   clones, backups, and any archive repo that mirrors the history.

## Watch for the silent-guard second-order failure

A secret guard that aborts **quietly** is indistinguishable from "nothing to sync". One documented
case: a credential regex matched a legitimate domain identifier, so the guard aborted every
auto-commit for 42 hours — dead sync, exit 0, nothing paged. After adding or tightening any secret
guard, add a **staleness alarm** on the thing it gates. A clean exit code is not evidence the
pipeline ran.

## Failure mode without this

The instinct is to reach for history-rewrite tooling first, because rewriting history feels like
deleting the secret. It is not: it breaks every clone and every sync job, takes hours of
coordination, and at the end the key is *still live* in the clones you did not reach. Meanwhile the
window in which the key could be used never closed.

## Honest limits

- Rotation is vendor-side and human-gated. This skill cannot execute it; it can only order the work
  and produce the exact steps.
- You cannot prove a leaked key was never used. Where the vendor offers access logs, check them and
  state the finding; where it does not, say so rather than implying safety.
- History-rewrite tools rewrite only the repos you run them on. Mirrors, archive clones, forks, and
  backup bundles each need their own pass, and some backups are deliberately immutable.
- Step 5 proves the two known mechanisms are closed. It does not prove there is no third.
