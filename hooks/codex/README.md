# Codex hooks

The same policy family ported to a second agent runtime, to show the design isn't
tied to one harness: a PostToolUse prompt-injection scanner and two Stop-hook output
guards (anti-sycophancy phrase match, claim-evidence check). All three share the
`hook_log`/`json_get` shim in `../claude-code/lib/common.sh`.

| hook | event | trigger | effect |
|---|---|---|---|
| `injection-scan.sh` | PostToolUse (any) | prompt-injection markers in tool output | warn only, never blocks |
| `sycophancy-scan.sh` | Stop | banned validation openers / empty-encouragement closers | `{"decision":"block"}` forces one redo |
| `claim-evidence-guard.sh` | Stop | live-state claim with 0 reads this turn and no evidence marker | `{"decision":"block"}` forces one redo |

## Exit-code contract

- `injection-scan.sh`: always exits `0`; a hit is a stderr advisory only.
- `sycophancy-scan.sh` / `claim-evidence-guard.sh`: always exit `0`; a violation prints
  `{"decision":"block","reason":...}` on stdout to force one redo (loop-guarded via
  `stop_hook_active` in the stdin payload). Set `SYCOPHANCY_WARN=1` to downgrade the
  sycophancy check to warn-only.
- Both Stop hooks support a standalone test mode: `bash <hook>.sh --test "some text"`
  prints `VERDICT: clean` or `VERDICT: BLOCK (...)` with no stdin required.

## Wiring

Point your Codex hook configuration's PostToolUse and Stop (or nearest equivalent
end-of-turn) entries at these scripts, e.g.:

```toml
[hooks.post_tool_use]
command = "/path/to/hooks/codex/injection-scan.sh"

[hooks.stop]
commands = [
  "/path/to/hooks/codex/sycophancy-scan.sh",
  "/path/to/hooks/codex/claim-evidence-guard.sh",
]
```

Adjust the table/array shape to whatever your Codex build's hook config schema expects —
the scripts themselves only depend on the stdin JSON contract described above.

## Running the selftests

```bash
bash hooks/codex/injection-scan.selftest.sh
bash hooks/codex/sycophancy-scan.selftest.sh
bash hooks/codex/claim-evidence-guard.selftest.sh
```

Each is hermetic and can also be run from a fully clean environment:
`env -i HOME=/tmp/x PATH=$PATH bash hooks/codex/<selftest>.sh`.
