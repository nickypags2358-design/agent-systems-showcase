# Claude Code hooks

Four hooks that harden a Claude Code agent session: a PreToolUse security gate, a
PreToolUse action-registry gate, a PostToolUse prompt-injection scanner, and a Stop
hook that enforces an anti-sycophancy / claim-evidence output policy.

| hook | event | trigger | effect |
|---|---|---|---|
| `security-rules-enforce.sh` | PreToolUse (Bash) | secret reads, curl\|sh, disabling OS security, reverse/bind shells, authorized_keys writes, mass delete, recursive chmod/chown at root, credential POST | exit 2 = block |
| `action-gate.sh` | PreToolUse (any) | reversibility x blast-radius registry (`actions.example.yaml`) | exit 2 = block (HARD-ASK), or `{"decision":"ask"}` (ASK) |
| `injection-scan.sh` | PostToolUse (any) | prompt-injection markers in tool output | warn only, never blocks |
| `output-guard.sh` | Stop | banned sycophancy phrases; live-state claims with no evidence | `{"decision":"block"}` forces one redo |

## Exit-code contract

- PreToolUse hooks: exit `2` + a reason on stderr = **block** the tool call. Exit `0` = allow.
  `action-gate.sh` additionally emits a JSON `{"decision":"ask",...}` on stdout for ASK-tier rows.
- PostToolUse (`injection-scan.sh`): always exits `0`; a hit is a stderr advisory only.
- Stop (`output-guard.sh`): always exits `0`; a violation prints `{"decision":"block","reason":...}`
  on stdout, which the harness uses to force one redo (loop-guarded via `stop_hook_active`).

## Wiring (`.claude/settings.json`)

```json
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "/path/to/hooks/claude-code/security-rules-enforce.sh"}]},
      {"matcher": "*",    "hooks": [{"type": "command", "command": "/path/to/hooks/claude-code/action-gate.sh"}]}
    ],
    "PostToolUse": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "/path/to/hooks/claude-code/injection-scan.sh"}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "/path/to/hooks/claude-code/output-guard.sh"}]}
    ]
  }
}
```

Every hook honors `HOOK_HOME` (default `${TMPDIR:-/tmp}/agent-hooks`) for its log dir, and
`action-gate.sh` honors `ACTION_GATE_REGISTRY` to point at your own registry file.

## Running the selftests

```bash
bash hooks/claude-code/security-rules-enforce.selftest.sh
bash hooks/claude-code/action-gate.selftest.sh
bash hooks/claude-code/injection-scan.selftest.sh
bash hooks/claude-code/output-guard.selftest.sh
```

Each is hermetic (temp `HOME`/`HOOK_HOME`) and can also be run from a fully clean
environment: `env -i HOME=/tmp/x PATH=$PATH bash hooks/claude-code/<selftest>.sh`.
