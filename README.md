# Agent Systems Showcase

Public, self-contained excerpts from a production operating layer for autonomous
coding agents, built on **Claude Code** and **OpenAI Codex CLI**. Everything here
runs on its own, is verified in CI, and carries no client data, no credentials and
no link to the private repositories it was extracted from.

If you arrived from an Upwork or LinkedIn profile: this is the evidence behind the
claims there. Clone it, run `./verify.sh`, read the hooks.

## What is in here

| Directory | What it shows | Try it |
|---|---|---|
| `hooks/claude-code/` | Mechanical enforcement of security and quality rules at tool-call time: blocks `curl \| sh`, credential-file reads, mass deletes, reverse shells; flags prompt injection; enforces an anti-sycophancy output policy. Each hook ships with a selftest. | `bash hooks/claude-code/security-rules-enforce.selftest.sh` |
| `hooks/codex/` | The same contracts on the second runtime (Codex CLI): injection scan, claim-evidence guard, sycophancy scan. | `bash hooks/codex/injection-scan.selftest.sh` |
| `evals/` | Golden-set evaluation: a JSONL set of incidents with expected verdicts and a runner that scores a classifier and fails on regression. Sample set is synthetic. | `bash evals/eval-run.sh --dry-run` |
| `skills/` | Procedural knowledge the agent loads on demand: task tracking, untrusted-data boundary, eval design, secret-leak response, tamper-evident publishing. | read `skills/README.md` |
| `mcp-servers/atelier/` | Three Model Context Protocol servers that emit HTML/CSS/SVG deterministically (stdlib Python, zero paid API calls) for design and layout work. | register via `mcp-servers/atelier/client-config.example.json` |
| `scripts/` | Drift checker that keeps the Claude Code and Codex instruction files in parity. | `bash scripts/agents-md-drift.sh scripts/fixtures/a.md scripts/fixtures/b.md` |
| `docs/ARCHITECTURE.md` | How the layers fit: hooks, policy, ledger, scheduled audits, evals, MCP tools. | |

## The system these come from

These excerpts are cut from a larger private system. Its scale as of September 2026,
stated here for context and not verifiable from this repository:

| Component | Count |
|---|---|
| Runtime hooks (Claude Code) | 48 |
| Runtime hooks (Codex CLI) | 24 |
| Skills | 57 |
| Subagent definitions | 37 |
| Scheduled audit and review jobs | 160 |
| Codex sessions run through the system | over 6,000 |

What can be verified is in this tree, under `./verify.sh`.

Not included, on purpose: domain-specific agents, the task and escalation ledgers, data
servers tied to a particular domain, and anything from a client engagement. The excerpts
were re-pathed, stripped of private references and re-tested before publication. History
starts at this repository's first commit.

## Proof of work

Excerpts of the private system these hooks came from, redacted to shape, counts and honesty framing:

| Page | What it shows |
|---|---|
| [System atlas](docs/proof-of-work/system-atlas.md) ([standalone HTML](docs/proof-of-work/system-atlas.html)) | 2,692 components in 10 categories; three execution lanes, one hook plane; 44 hooks by lifecycle event; a fail-closed security plane; the four-layer proof model where a blank is never a pass. |
| [Client case brief](docs/proof-of-work/client-case-brief.md) | An anonymized 15-system marketing design for a consumer brand in a regulated-claims category: a refusal layer, a whitelist-only claims gate, a three-value measurement rule. Per the deliverable, eleven of the fifteen are designed and not built; nothing switched on. |
| [Automation evidence, 90 days](docs/proof-of-work/automation-evidence-90d.md) | Measured review: 144 scheduled jobs, about 87% liveness, 259 unattended posts on 5 platforms, and the unflattering half. Short-term; outcomes may change. |

Nothing in that section is verifiable from this repository, and its counts differ from the table above because they were measured on different days. Paths, component names, schedules and client identities are left out on purpose; see [docs/proof-of-work/README.md](docs/proof-of-work/README.md).

## Design principles

1. **Enforce with hooks, guide with prompts.** If a rule matters it gets a hook, an
   exit code the runtime honours, and a selftest.
2. **Fail loudly.** Blocked is exit 2 with a reason on stderr. Undecidable becomes a
   structured escalation, never a silent guess.
3. **Evals before opinions.** Behaviour changes are scored against golden sets written
   before the change.
4. **Cheapest capable model per task.** Routine work goes to smaller models; judgment,
   security and irreversible actions stay on the strongest one.
5. **Provenance on external claims.** Source, verbatim quote, rewrite, confidence, or
   "no source found".
6. **Two runtimes, one contract.** Claude Code and Codex configurations are checked
   for drift so a rule cannot quietly diverge.

## Quick start

```bash
git clone https://github.com/nickypags2358-design/agent-systems-showcase.git
cd agent-systems-showcase
./verify.sh        # bash -n, shellcheck, py_compile, every selftest, eval run, path scan
```

Requirements: bash 3.2 or newer, python3, `jq` optional, `shellcheck` optional locally
(installed in CI).

## Wiring a hook into Claude Code

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash /path/to/hooks/claude-code/security-rules-enforce.sh" }
        ]
      }
    ]
  }
}
```

Each hook reads the tool call as JSON on stdin and answers with an exit code: `0`
allow, `2` block. See `hooks/claude-code/README.md` for the full contract and the
Codex equivalent.

## License

MIT. See `LICENSE`.
