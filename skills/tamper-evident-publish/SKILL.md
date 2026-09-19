---
name: tamper-evident-publish
description: Committing and pushing a generated file to a shared repo from automation, where the commit must contain exactly what was scanned and nothing a concurrent writer left behind. Fires when writing or reviewing a script/hook that commits and pushes, when `git add -A`, `git commit -am`, or `git push --force` is about to run unattended, when a secret scan must gate a commit, or when several processes publish through one checkout. DOES NOT cover human PR workflow, working-tree isolation (worktree-test), or leaked-secret cleanup (secret-leak-response).
---

## When this fires

Automation writes a file and pushes it: a telemetry event, a generated report, a state snapshot, an
audit record. Especially when the checkout is shared by other processes or sessions.

## What "tamper-evident" means here

The commit that lands must be provably the tree that passed the scan. Every step below exists to
close a gap between *what you checked* and *what you pushed*.

## Procedure

**1. Serialize on the checkout.** One `flock` on a lock file keyed by a hash of the resolved checkout
path, with a timeout, released in a `finally`. A shared checkout has one index and one HEAD; two
unsynchronised publishers corrupt each other's staging.

**2. Refuse a checkout that is dirty outside your output directory.** Parse
`git status --porcelain=v1 -z --untracked-files=all` and reject any path not under your own subtree.
Use `-z` and handle rename/copy records (they consume two NUL-separated fields) — a naive line split
mis-parses paths with spaces or quotes.

**3. Check idempotency before writing.** Derive the artifact id from its content, then look for it in
`HEAD` first (`git ls-tree -r --name-only -z HEAD -- <dir>`). If it is already committed, skip
straight to the push — a re-run must be a no-op, not a duplicate commit.

**4. Stage exactly one path — then verify that it is the only thing staged.**

```bash
git add -- "$path"
git diff --cached --name-status --no-renames -z   # must yield exactly one A|M record == "$path"
```

`git add -- <path>` does not guarantee the index holds only that path; something else may already
have been staged. This is the single highest-value check in the procedure. Never `git add -A` /
`git commit -am` in automation.

**5. Capture the tree, scan it, then confirm the tree did not move.**

```bash
tree_id=$(git write-tree)
gitleaks git --staged --redact --no-banner --log-level error   # must exit 0
[ "$(git write-tree)" = "$tree_id" ] || die "index changed during secret scanning"
```

Without the re-check, a concurrent writer can change the index between scan and commit, and you push
an unscanned tree. Scanning is **fail-closed**: a missing scanner is a refusal to publish, not a
warning.

**6. Commit the captured tree, not the current index.**

```bash
parent=$(git rev-parse HEAD)
commit=$(git commit-tree "$tree_id" -p "$parent" -m "<message>")
git update-ref "refs/heads/$branch" "$commit" "$parent"        # compare-and-swap on the old value
[ "$(git rev-parse "$commit^{tree}")" = "$tree_id" ] || die "committed tree differs from scanned tree"
```

`git commit` re-reads the live index; `commit-tree` binds the commit to the exact object you scanned.
Passing the old value to `update-ref` makes the branch move a compare-and-swap, so a concurrent
publisher cannot be silently overwritten.

**7. Push with bounded retry and a safe abort.** On non-fast-forward: fetch, rebase, retry, at most
three attempts. If the rebase conflicts: `git rebase --abort`, then **verify recovery** — HEAD is back
on the expected branch and no `rebase-merge` / `rebase-apply` state directory remains (resolve them
via `git rev-parse --git-path`). If either check fails, raise "unsafe git state" rather than
continuing. An automated publisher that leaves a half-rebased checkout breaks every later run and
every human who opens the repo.

**8. Clean up only your own path on failure.**

```bash
git reset -q HEAD -- "$path"   # unstage just yours
rm -f "$path"                  # only if it was not already committed
```

Never `git reset --hard`, never `git clean -fd` — in a shared checkout they delete another process's
in-flight work.

**9. Queue, do not lose.** If any step fails, write the sanitized artifact to a private outbox
(mode 0700 dir, 0600 file, atomic `mkstemp` → `fsync` → `os.replace`) so a later flush can retry.
Sanitize *before* queueing, so the queue cannot hold something the publisher will reject forever.

**10. Contain the write path if the filename is derived from input.** Walk the directory chain with
`O_DIRECTORY|O_NOFOLLOW` descriptors, reject `.`/`..`/embedded separators, and create with
`O_CREAT|O_EXCL` (or write-temp + `link`) so a symlink cannot redirect the write outside the tree.

## Failure mode without this

The default automation shape — `git add -A && git commit -m x && git push` — fails four ways at once
in a shared checkout: it commits another process's half-written file; it pushes a tree that was never
the tree you scanned; on conflict it either loses the push or leaves a broken rebase; and on failure
its cleanup wipes work it did not create. Each failure is silent and only shows up as a corrupt
history days later.

## Self-check before finishing

1. Is there exactly one staged path, verified by reading the index back?
2. Is the pushed commit's tree the same object id that the scanner saw?
3. Does a second run of the same input produce zero new commits?
4. After a forced failure mid-way, is the checkout on its branch with no leftover rebase state and no
   files removed that were not mine?

## Honest limits

- One commit per artifact is durable and auditable but inefficient at volume; batching is a different
  design and re-opens the "exactly what was scanned" question.
- `flock` serialises one host only. Two machines converge through bounded fetch/rebase/push retries,
  and a persistent conflict stays queued for a later flush rather than resolving itself.
- Secret scanning is pattern-based: fail-closed on scanner absence buys you strictness, not
  completeness.
- Commits are unsigned here. This detects accidental divergence between scan and push; it does not
  defend against an attacker who already has write access to the checkout.
