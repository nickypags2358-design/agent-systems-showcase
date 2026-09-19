#!/usr/bin/env bash
# action-gate.sh — PreToolUse gate that reads a small action registry (actions.example.yaml)
# and enforces reversibility x blast_radius tiers on every tool call:
#   HARD-ASK rows -> deny  (external publish, money movement, security/system config, mass deletion)
#   ASK rows      -> ask   (git push/commit, install_dependency, external API writes)
#   everything else -> exit 0, no output
#
# CONTRACT: PreToolUse hook, stdin JSON {"tool_name":..,"tool_input":{...}}.
#   exit 2 + JSON {"decision":"block",...}        = deny
#   exit 0 + JSON {"decision":"ask",...}           = ask the human
#   exit 0, no output                              = not this gate's row; other hooks still apply
# It never returns an explicit "allow" for a row it does not recognize — silence means
# "not my row", so it never weakens another hook's verdict.
#
# WIRING (Claude Code, .claude/settings.json):
#   "hooks": {"PreToolUse": [{"matcher": "*",
#     "hooks": [{"type": "command", "command": "$SELF_DIR/action-gate.sh"}]}]}
#
# Registry path: ACTION_GATE_REGISTRY env override, default "$SELF_DIR/actions.example.yaml".
# Fail direction: a missing/broken jq degrades to a raw-payload scan that still denies the
# HARD-ASK signatures and lets ASK rows through with a logged warning — severe classes stay
# closed, the convenience tier fails open rather than wedging every tool call.
#
# ACTION_GATE_REPORT=1 or ACTION_GATE_HEADLESS=1 downgrades ASK rows to a logged line only
# (a headless job has no human to answer a prompt). HARD-ASK never downgrades.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/lib/common.sh" 2>/dev/null || { hook_log() { :; }; }
REGISTRY="${ACTION_GATE_REGISTRY:-$SELF_DIR/actions.example.yaml}"

IN="$(cat 2>/dev/null || true)"

# ── fast path ────────────────────────────────────────────────────────────────
case "$IN" in
  *'"Bash"'*|*mcp__*) : ;;
  *) exit 0 ;;
esac

REG="registry: $REGISTRY"

emit() { # $1 decision(block|ask)  $2 permissionDecision(deny|ask)  $3 reason
  local rj
  rj="$(printf '%s' "$3" | jq -Rs . 2>/dev/null)" || rj='"action-gate: registry row requires a human"'
  printf '{"decision":"%s","reason":%s,"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":%s}}\n' \
    "$1" "$rj" "$2" "$rj"
}

block() { # $1 class  $2 registry line  $3 tool
  hook_log BLOCK "tool=$3 class=$1"
  emit block deny "HARD-ASK (action registry): $1. $2 [$REG]. This row has no override — a human must run it."
  exit 2
}

ask() { # $1 class  $2 registry line  $3 tool
  if [ "${ACTION_GATE_REPORT:-}" = "1" ] || [ "${ACTION_GATE_HEADLESS:-}" = "1" ]; then
    hook_log ASK-REPORTED "tool=$3 class=$1"
    exit 0
  fi
  hook_log ASK "tool=$3 class=$1"
  emit ask ask "ASK (action registry): $1. $2 [$REG]. An explicit go-ahead from the human this turn flips it to ACT."
  exit 0
}

# ── registry lines (kept in sync with actions.example.yaml) ─────────────────
L_PUBLISH='publish_external {reversibility: LOW, blast_radius: BROAD} — "Public/irreversible; may be cached or indexed. Can not unsend."'
L_MONEY='financial_transaction {reversibility: LOW, blast_radius: BROAD} — "Money movement is never the agent'"'"'s call."'
L_SECCFG='modify_security_config {reversibility: LOW, blast_radius: BROAD} — "OS/security posture."'
L_MASSDEL='mass_delete {reversibility: LOW, blast_radius: BROAD} — "Hard to undo, wide blast."'
L_FORCE='git_force_push {reversibility: LOW, blast_radius: BROAD} — "Rewrites shared history."'
L_GITPUSH='git_push {reversibility: MED, blast_radius: BROAD} — "Publishes to a shared remote."'
L_GITCOMMIT='git_commit — named override: commit/push only when explicitly asked.'
L_INSTALL='install_dependency {reversibility: MED, blast_radius: SCOPED} — "Supply-chain + lockfile impact; confirm source."'
L_APIWRITE='call_external_api_write {reversibility: LOW, blast_radius: BROAD} — "Mutates remote state."'

# ── degraded mode: no jq ─────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  if printf '%s' "$IN" | grep -qE '(publish_post|create_post|send_dm|send_message|forward|reply)' \
     || printf '%s' "$IN" | grep -qE '(csrutil|fdesetup|spctl|authorized_keys)' \
     || printf '%s' "$IN" | grep -qE 'rm[^"]*-[A-Za-z]*[rR][A-Za-z]*[^"]*(\$\{?HOME\}?|~/|/Users/|/home/)'; then
    hook_log BLOCK-DEGRADED "jq-missing"
    printf '{"decision":"block","reason":"HARD-ASK (action registry, degraded scan): jq is unavailable, and the raw tool payload carries an external-publish / security-config / mass-delete signature. [%s]"}\n' "$REG"
    exit 2
  fi
  hook_log WARN "jq-missing-open"
  exit 0
fi

TOOL="$(printf '%s' "$IN" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ -n "$TOOL" ] || exit 0

# ── MCP surface ──────────────────────────────────────────────────────────────
case "$TOOL" in
  mcp__*)
    SUF="${TOOL##*__}"
    if printf '%s' "$SUF" | grep -qE '^(publish_post|create_post|send_dm|(private_)?reply(_to_[a-z_]+)?|send_message|forward|reply)$'; then
      block "external publish / outbound send via '$TOOL'" "$L_PUBLISH" "$TOOL"
    fi
    if printf '%s' "$SUF" | grep -qE '^([a-z_]*_)?(send_money|transfer_funds|create_payout|create_transfer|create_charge|withdraw|deposit|place_order|submit_order)([a-z_]*)$'; then
      block "money movement via '$TOOL'" "$L_MONEY" "$TOOL"
    fi
    if [ "$SUF" = "git_push" ]; then ask "git push via '$TOOL'" "$L_GITPUSH" "$TOOL"; fi
    if [ "$SUF" = "git_commit" ]; then ask "git commit via '$TOOL'" "$L_GITCOMMIT" "$TOOL"; fi
    if printf '%s' "$SUF" | grep -qE '^(share_file|share_[a-z_]+|create_webhook|update_webhook|delete_webhook)$'; then
      ask "external share / webhook via '$TOOL'" "$L_APIWRITE" "$TOOL"
    fi
    exit 0
    ;;
  Bash) : ;;
  *) exit 0 ;;
esac

# ── Bash surface ─────────────────────────────────────────────────────────────
CMD="$(printf '%s' "$IN" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

NORM="$(printf '%s' "$CMD" | sed -E 's|\$\{HOME\}|~|g; s|\$HOME|~|g; s|/Users/[^/ "'"'"']+|~|g; s|/home/[^/ "'"'"']+|~|g')"
SEGS="$(printf '%s' "$NORM" | tr ';&|\n' '\n\n\n\n')"

RM_RE='(^|[[:space:]])(sudo[[:space:]]+)?rm([[:space:]]+-[A-Za-z]*[rR][A-Za-z]*|[[:space:]]+--recursive)'
TGT_RE='(^|[[:space:]])"?'"'"'?(/|~|~/|/\*|~/\*|~/[^/[:space:]"*]+/?|/(usr|etc|var|bin|sbin|opt|System|Library|Applications|Volumes|private|Users)/?)'"'"'?"?([[:space:]]|$)'
SEC_RE='(^|[[:space:]])(sudo[[:space:]]+)?(spctl|csrutil|fdesetup)([[:space:]]|$)'
LCTL_BLOCK_RE='(^|[[:space:]])(sudo[[:space:]]+)?launchctl[[:space:]]+(load|bootstrap|enable|submit)([[:space:]]|$)'
LCTL_ASK_RE='(^|[[:space:]])(sudo[[:space:]]+)?launchctl[[:space:]]+(unload|bootout|disable|remove)([[:space:]]|$)'
AK_WRITE_RE='(>>?|tee|[[:space:]]cp[[:space:]]|[[:space:]]mv[[:space:]]|install[[:space:]]|ssh-copy-id|sed[[:space:]]+-i|chmod|chown)'
MONEY_RE='(^|[[:space:]])(sudo[[:space:]]+)?(stripe|paypal|venmo|coinbase|binance|plaid)[[:space:]]+([a-z_]+[[:space:]]+)?(create|charge|pay|payout|payouts|transfer|transfers|withdraw|deposit|send|buy|sell|order)([[:space:]]|$)'
MONEY2_RE='(send[-_]money|wire[-_]transfer|--transfer-funds)'
PUSH_RE='(^|[[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'
FORCE_RE='(^|[[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+(--force|--force-with-lease|-f)([[:space:]]|$)'
COMMIT_RE='(^|[[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'
INSTALL_RE='(^|[[:space:]])(sudo[[:space:]]+)?((npm|pnpm|yarn|bun)[[:space:]]+(i|install|add|ci)|(pip|pip3)[[:space:]]+install|python3?[[:space:]]+-m[[:space:]]+pip[[:space:]]+install|brew[[:space:]]+install|gem[[:space:]]+install|cargo[[:space:]]+install|go[[:space:]]+install)([[:space:]]|$)'

while IFS= read -r SEG; do
  [ -n "$SEG" ] || continue
  if printf '%s' "$SEG" | grep -qE "$RM_RE" && printf '%s' "$SEG" | grep -qE "$TGT_RE"; then
    block "mass deletion (recursive rm targeting /, \$HOME, a top-level child of \$HOME, or an OS root dir)" "$L_MASSDEL" "Bash"
  fi
  if printf '%s' "$SEG" | grep -qE "$SEC_RE" || printf '%s' "$SEG" | grep -qE "$LCTL_BLOCK_RE"; then
    block "security/system config change (gatekeeper, SIP, FileVault, or loading a new launchd agent)" "$L_SECCFG" "Bash"
  fi
  if printf '%s' "$SEG" | grep -qF 'authorized_keys' && printf '%s' "$SEG" | grep -qE "$AK_WRITE_RE"; then
    block "remote-access vector (write-shaped command targeting authorized_keys)" "$L_SECCFG" "Bash"
  fi
  if printf '%s' "$SEG" | grep -qE "$MONEY_RE" || printf '%s' "$SEG" | grep -qE "$MONEY2_RE"; then
    block "money movement" "$L_MONEY" "Bash"
  fi
  if printf '%s' "$SEG" | grep -qE "$FORCE_RE"; then
    block "force push (rewrites shared history)" "$L_FORCE" "Bash"
  fi
done <<EOF
$SEGS
EOF

while IFS= read -r SEG; do
  [ -n "$SEG" ] || continue
  if printf '%s' "$SEG" | grep -qE "$PUSH_RE"; then ask "git push" "$L_GITPUSH" "Bash"; fi
  if printf '%s' "$SEG" | grep -qE "$COMMIT_RE"; then ask "git commit" "$L_GITCOMMIT" "Bash"; fi
  if printf '%s' "$SEG" | grep -qE "$INSTALL_RE"; then ask "install_dependency" "$L_INSTALL" "Bash"; fi
  if printf '%s' "$SEG" | grep -qE "$LCTL_ASK_RE"; then ask "disabling a scheduled job" "$L_APIWRITE" "Bash"; fi
done <<EOF
$SEGS
EOF

exit 0
