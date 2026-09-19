#!/usr/bin/env bash
# security-rules-enforce.sh — PreToolUse guard for Bash tool calls.
#
# PURPOSE: mechanically block a short list of NEVER-do shell actions (secret-file
# reads, remote-code-into-shell pipes, disabling OS security controls, reverse/bind
# shells, authorized_keys/sshd_config writes, mass deletion at a filesystem root or
# home, recursive chmod/chown at a root, and credential POSTs to a non-allowlisted
# domain) instead of relying on prompt instructions alone.
#
# CONTRACT: PreToolUse hook. Reads one JSON payload on stdin:
#   {"tool_name": "...", "tool_input": {"command": "..."}}
# Exit 2 + a one-line reason on stderr = BLOCK the tool call.
# Exit 0 (silent, or with a stderr advisory) = ALLOW.
# Non-Bash tool calls and calls this hook cannot parse are always allowed (fail-open
# on "can I even see this call", fail-closed on "should this specific call run").
#
# WIRING (Claude Code, .claude/settings.json):
#   "hooks": {"PreToolUse": [{"matcher": "Bash",
#     "hooks": [{"type": "command", "command": "$SELF_DIR/security-rules-enforce.sh"}]}]}
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/lib/common.sh" 2>/dev/null || { hook_log() { :; }; }

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0   # no payload: nothing to check

if ! command -v jq >/dev/null 2>&1 || ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  hook_log WARN "security-rules-enforce: jq missing or payload unparseable — command NOT checked"
  exit 0
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL_NAME" ] || [ "$TOOL_NAME" = "Bash" ] || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$COMMAND" ] || exit 0

# ---------- wrapper-bypass normalization ----------
# env/sudo/nohup/setsid/nice/ionice/watch can prefix a dangerous command; strip a
# few levels of leading wrapper so the checks below see the real verb.
NORM="$COMMAND"
NORM="${NORM//\\$'\n'/ }"
NORM="${NORM//\\ / }"
for _ in 1 2 3; do
  NORM=$(sed -E 's/^[[:space:]]*(env([[:space:]]+[A-Z_]+=[^[:space:]]+)*|sudo|watch([[:space:]]+-[a-zA-Z0-9]+)*|ionice([[:space:]]+-[a-zA-Z0-9]+)*|setsid|nice([[:space:]]+-[a-zA-Z0-9]+)*|nohup)[[:space:]]+//' <<< "$NORM")
done
shopt -s nocasematch
NORM_LC="$NORM"

block() { # $1 rule number  $2 description
  hook_log BLOCK "rule=$1 desc=\"$2\""
  echo "security-rules-enforce: rule $1 triggered: $2" >&2
  exit 2
}
warn() { # $1 rule number  $2 description
  hook_log WARN "rule=$1 desc=\"$2\""
  echo "security-rules-enforce advisory (rule $1): $2" >&2
}

# ============================================================================
# RULE 1 (block) — reading secret material through Bash
# Text matching, not containment: an unlisted reader or a variable-built path
# still passes. .env.example/.sample/.template, *.pub, known_hosts and
# authorized_keys stay readable by design.
# ============================================================================
R1SCAN=$(printf '%s' "$NORM" | tr -d '\042\047')
R1READER='(^|[[:space:]/;&|(])((cat|bat|less|more|head|tail|nl|strings|xxd|od|hexdump|base64|cp|scp|rsync|tee|awk|sed|grep|rg|jq|python[0-9.]*|perl|ruby|node)([[:space:]]|$)|openssl[[:space:]]+enc([[:space:]]|$))'
R1TARGET='(^|[[:space:]/=])\.env(\.local|\.production|\.development|\.staging)?([[:space:];|&]|$)|[^[:space:]]*\.(pem|p12|pfx|keystore|jks)([[:space:];|&]|$)|(^|[[:space:]/])id_(rsa|dsa|ecdsa|ed25519)([[:space:];|&]|$)|/\.ssh/|/\.gnupg/|/\.aws/credentials|(^|[[:space:]/])\.netrc([[:space:];|&]|$)|(^|[[:space:]/])\.git-credentials|(^|[[:space:]/])\.pypirc'
R1ALLOW='\.env\.(example|sample|template)|\.pub([[:space:];|&]|$)|authorized_keys|known_hosts'
if [[ "$R1SCAN" =~ $R1READER ]] && [[ "$R1SCAN" =~ $R1TARGET ]] && ! [[ "$R1SCAN" =~ $R1ALLOW ]]; then
  block 1 "Reading secret material (.env / private keys / credential stores) via Bash — reference the variable NAME and let the environment supply the value"
fi

# ============================================================================
# RULE 2 — pipe remote code into a shell/interpreter (curl|wget -> sh/python/...)
# ============================================================================
R2WRAP='((sudo|env|nice|ionice|nohup|setsid|watch|xargs|command)[^|]*[[:space:]])?'
R2PATH='(/[^[:space:]|]*/)?'
if [[ "$NORM_LC" =~ (curl|wget|fetch)[^\|]*\|[[:space:]]*${R2WRAP}${R2PATH}(ba|z|k|d|t|c)?sh([[:space:]]|$) ]]; then
  block 2 "Pipe remote code into shell (curl|wget -> sh/bash/zsh)"
fi
if [[ "$NORM_LC" =~ (curl|wget|fetch)[^\|]*\|[[:space:]]*${R2WRAP}${R2PATH}(python[0-9]*|ruby|perl|node|osascript|deno)([[:space:]]|$) ]]; then
  block 2 "Pipe remote code into interpreter (curl|wget -> python/ruby/perl/node)"
fi
# Same intent without a pipe: process substitution `bash <(curl ...)` and command
# substitution `sh -c "$(curl ...)"` / `sh -c "`curl ...`"`. Quotes are stripped first
# so quoting style does not matter. `diff <(sort a) <(sort b)` is not an interpreter.
R2SCAN=$(printf '%s' "$NORM_LC" | tr -d '\042\047')
R2INTERP='(^|[[:space:]/;&|(])(bash|sh|zsh|ksh|dash|python3|python|perl|node)[[:space:]]+'
R2PSUB="${R2INTERP}"'([^|;&]*[[:space:]])?<\([[:space:]]*(curl|wget|fetch)([[:space:]]|$)'
R2CSUB="${R2INTERP}"'-c[[:space:]]+(\$\(|`)[[:space:]]*(curl|wget|fetch)([[:space:]]|$)'
if [[ "$R2SCAN" =~ $R2PSUB ]]; then
  block 2 "Remote code via process substitution into an interpreter (bash <(curl ...))"
fi
if [[ "$R2SCAN" =~ $R2CSUB ]]; then
  block 2 "Remote code via command substitution into an interpreter (sh -c \"\$(curl ...)\")"
fi
if [[ "$NORM_LC" =~ base64[[:space:]]+-[dD][^\|]*\|[[:space:]]*((ba|z)?sh|python) ]]; then
  block 2 "Base64-decode piped into a shell (common obfuscation pattern)"
fi

# ============================================================================
# RULE 3 — disable OS security controls (macOS example commands shown; adapt
# the pattern list for other platforms)
# ============================================================================
if [[ "$NORM_LC" =~ csrutil[[:space:]]+(disable|clear) ]]; then block 3 "Cannot disable System Integrity Protection"; fi
if [[ "$NORM_LC" =~ spctl[[:space:]]+--(master|global)-disable ]]; then block 3 "Cannot disable Gatekeeper"; fi
if [[ "$NORM_LC" =~ fdesetup[[:space:]]+(disable|remove) ]]; then block 3 "Cannot disable full-disk encryption"; fi
if [[ "$NORM_LC" =~ socketfilterfw[[:space:]]+[^\|]*--setglobalstate[[:space:]]+off ]]; then
  block 3 "Cannot disable the application firewall"
fi

# ============================================================================
# RULE 4 — reverse / bind shells, and dev servers that bind all interfaces
# ============================================================================
if [[ "$NORM_LC" =~ (^|[[:space:]/])(nc|ncat)[[:space:]]+([^\|]*[[:space:]])?(-[lL][[:space:]vp0-9]|--listen([[:space:]=]|$)) ]]; then
  block 4 "Bind shell / listening netcat detected (nc -l / --listen)"
fi
if [[ "$NORM_LC" =~ (^|[[:space:]/])(nc|ncat)[[:space:]]+[^\|]*(-e[[:space:]]+|--(exec|sh-exec)[[:space:]=]) ]]; then
  block 4 "Netcat with -e/--exec flag = reverse shell"
fi
if [[ "$NORM_LC" =~ (bash|zsh|sh)[[:space:]]+-i[[:space:]]+\>\&[[:space:]]*/dev/tcp/ ]] || [[ "$NORM_LC" =~ /dev/tcp/[^[:space:]]+/[0-9]+ ]]; then
  block 4 "Reverse shell to /dev/tcp/ detected"
fi
if [[ "$NORM_LC" =~ (^|[[:space:]/])socat[[:space:]]+[^\|]*(exec:) ]]; then
  block 4 "socat with EXEC pattern = reverse shell"
fi
if [[ "$NORM_LC" =~ (^|[[:space:]/])ssh[[:space:]]+[^\|]*-R[[:space:]]+[0-9] ]]; then
  block 4 "ssh -R remote port forward (bind-shell pattern)"
fi
_srv_loopback='(--bind|-b|-a|--host|--address)[[:space:]=]+(127\.0\.0\.1|::1|\[::1\]|localhost)'
if [[ "$NORM_LC" =~ (^|[[:space:]/\;\&])python[0-9.]*[[:space:]]+([^\|]*[[:space:]])?-m[[:space:]]+(http\.server|simplehttpserver)([[:space:]]|$) ]] && ! [[ "$NORM_LC" =~ $_srv_loopback ]]; then
  block 4 "python -m http.server binds all interfaces — add --bind 127.0.0.1"
fi

# ============================================================================
# RULE 5 — write to ~/.ssh/authorized_keys or /etc/ssh/sshd_config
# ============================================================================
if [[ "$NORM" =~ \>\>?[[:space:]]*[~/]*\.?ssh/authorized_keys ]] || [[ "$NORM" =~ tee[[:space:]]+[^[:space:]]*authorized_keys ]]; then
  block 5 "Cannot modify ~/.ssh/authorized_keys"
fi
if [[ "$NORM" =~ \>\>?[[:space:]]*/etc/ssh/sshd_config ]] || [[ "$NORM" =~ sed[[:space:]]+[^\|]*-i[^\|]*/etc/ssh/sshd_config ]]; then
  block 5 "Cannot modify /etc/ssh/sshd_config"
fi

# ============================================================================
# RULE 6 — mass-delete at a bare root/home (rm -rf /, ~, $HOME, /Users, etc; and
# find ... -delete / find ... -exec rm at the same roots). POSIX-equivalent root
# spellings (//, /., /./, /..) are normalized first so they can't bypass the check.
# ============================================================================
R6NORM="$NORM"
for _r6i in 1 2 3 4 5 6 7 8; do
  _r6prev="$R6NORM"
  R6NORM=$(sed -E \
    -e 's#/{2,}#/#g' \
    -e 's#(/\.)+/#/#g' \
    -e 's#(/\.)+([[:space:];|&]|$)#/\2#g' \
    -e 's#/[^/[:space:]]*[^/.[:space:]][^/[:space:]]*/\.\.(/|[[:space:];|&]|$)#/\1#g' \
    -e 's#(^|[[:space:]])/\.\.(/|[[:space:];|&]|$)#\1/\2#g' \
    <<< "$R6NORM" 2>/dev/null) || { R6NORM="$_r6prev"; break; }
  [ -z "$R6NORM" ] && { R6NORM="$_r6prev"; break; }
  [ "$R6NORM" = "$_r6prev" ] && break
done
R6HEAD='(^|[[:space:]\;&|(])rm[[:space:]]+'
R6FLAGS='((-[a-zA-Z]+|--[a-zA-Z-]+)[[:space:]]+)*(--[[:space:]]+)?'
R6Q="[\"']?"
R6ROOT='(/|~|\$\{?HOME\}?|/home/[A-Za-z0-9._-]+|/Users/[A-Za-z0-9._-]+|/Users|/System|/Library|/private)'
R6GLOB='(/+|/?\.?\*+)?'
R6END='[[:space:]]*(\;|\||\&|$)'
if [[ "$R6NORM" =~ ${R6HEAD}${R6FLAGS}${R6Q}${R6ROOT}${R6GLOB}${R6Q}${R6END} ]]; then
  block 6 "Mass-delete at a bare root/home/system path (rm -rf /, ~, \$HOME, /Users[/<home>] etc — glob and trailing-slash forms included)"
fi
if [[ "$R6NORM" =~ find[[:space:]]+${R6Q}${R6ROOT}/?${R6Q}[[:space:]]+[^\|]*-delete ]]; then
  block 6 "find with -delete at root/home — mass-deletion pattern"
fi
if [[ "$R6NORM" =~ find[[:space:]]+${R6Q}${R6ROOT}/?${R6Q}([[:space:]]|$)[^\|]*-(exec|execdir|ok|okdir)[[:space:]]+(/[^[:space:]]*/)?rm ]]; then
  block 6 "find -exec rm at root/home — mass deletion"
fi

# ============================================================================
# RULE 6b — chmod/chown/chgrp with ANY recursion flag aimed at a bare root/home,
# order-free (chmod -R 755 /, chmod 755 -R /, sudo chown -vR nobody $HOME, ...).
# Segment-scoped so `chmod -R 755 ./build && ls /` stays allowed.
# ============================================================================
R6BSEGS=$(printf '%s' "$R6NORM" | tr -d '\042\047' | tr ';&|' '\n\n\n' 2>/dev/null)
[ -n "$R6BSEGS" ] || R6BSEGS="$R6NORM"
R6BVERB='(^|[[:space:]/])(chmod|chown|chgrp)([[:space:]]|$)'
R6BREC='(^|[[:space:]])(-[a-zA-Z]*R[a-zA-Z]*|--recursive)([[:space:]]|$)'
R6BTARGET='(^|[[:space:](])'"${R6Q}${R6ROOT}"'/?'"${R6Q}"'([[:space:])]|$)'
shopt -u nocasematch
while IFS= read -r _r6bseg; do
  [ -n "$_r6bseg" ] || continue
  if [[ "$_r6bseg" =~ $R6BVERB ]] && [[ "$_r6bseg" =~ $R6BREC ]] && [[ "$_r6bseg" =~ $R6BTARGET ]]; then
    shopt -s nocasematch
    block 6 "Recursive chmod/chown/chgrp at a bare root or home — denied regardless of flag order or spelling"
  fi
done <<< "$R6BSEGS"
shopt -s nocasematch

# ============================================================================
# RULE 7 — POST credential env vars to a non-allowlisted external domain
# Allowlist is intentionally small/generic; extend it for your own environment.
# ============================================================================
HAS_HTTP_POST=0
HAS_CRED=0
if [[ "$NORM_LC" =~ (curl|wget|http)[[:space:]]+[^\|]*(-x[[:space:]]*(post|put|patch)|--data|--data-raw|--data-urlencode|--data-binary|-d[[:space:]]) ]]; then
  HAS_HTTP_POST=1
fi
if [[ "$NORM" =~ \$\{?(AWS_(ACCESS_KEY|SECRET_ACCESS_KEY|SESSION_TOKEN)|OPENAI_API_KEY|ANTHROPIC_API_KEY|STRIPE_(API_)?KEY|STRIPE_SECRET|GITHUB_TOKEN|GH_TOKEN|GOOGLE_API_KEY|SLACK_(BOT_)?TOKEN|DATABASE_URL|DB_PASSWORD|API_KEY|SECRET_KEY|ACCESS_TOKEN|PRIVATE_KEY) ]]; then
  HAS_CRED=1
fi
if [ "$HAS_HTTP_POST" = "1" ] && [ "$HAS_CRED" = "1" ]; then
  if [[ "$NORM_LC" =~ https?://[^/[:space:]\"\']*@ ]]; then
    block 7 "Credential POST to a userinfo@host URL (allowlist-bypass attempt)"
  fi
  if [[ "$NORM_LC" =~ https?://(api\.anthropic\.com|api\.openai\.com|api\.github\.com|github\.com/api)([/:?#[:space:]\"\']|$) ]]; then
    : # allowlisted destination
  else
    block 7 "Sending credential env vars via HTTP POST/PUT/PATCH to a non-allowlisted domain"
  fi
fi

# ============================================================================
# OBSERVE-ONLY — warn (never block) on raw secret-shaped patterns visible in
# the command, and on a literal hardcoded credential assignment.
# ============================================================================
shopt -u nocasematch
if [[ "$COMMAND" =~ sk-(proj-|ant-|live_|test_)?[A-Za-z0-9_-]{20,} ]]; then warn 1 "Raw API key pattern (sk-*) detected in command"; fi
if [[ "$COMMAND" =~ AKIA[A-Z0-9]{16} ]]; then warn 1 "AWS access key pattern (AKIA*) detected in command"; fi
if [[ "$COMMAND" =~ gh[posu]_[A-Za-z0-9_]{36,} ]]; then warn 1 "GitHub token pattern (ghp_/gho_/ghs_/ghu_) detected in command"; fi
if [[ "$COMMAND" =~ xox[bpsoa]-[A-Za-z0-9-]{10,} ]]; then warn 1 "Slack token pattern (xoxb-/xoxp-) detected in command"; fi
if [[ "$COMMAND" =~ (API_KEY|SECRET|PASSWORD|PRIVATE_KEY|ACCESS_TOKEN)=[\"\']?[A-Za-z0-9_-]{16,}[\"\']? ]]; then
  if ! [[ "$COMMAND" =~ (API_KEY|SECRET|PASSWORD|PRIVATE_KEY|ACCESS_TOKEN)=(\$|\"your|\"xxx|\"YOUR|\"test|\"example|\"placeholder|\"\"|\"\$\{) ]]; then
    warn 11 "Hardcoded credential literal in command — use an env var instead"
  fi
fi

exit 0
