#!/usr/bin/env bash
# agents-md-drift.sh — compare a canon instructions file against a hand-adapted mirror
# (e.g. two agent-runtime config files) and report which top-level sections exist in
# one but not the other.
#
# A mirror file that is hand-adapted from a canon (rather than generated) silently
# drifts: the canon gains a new section, the mirror is never updated, and nothing
# notices. This script diffs section headings between the two files so drift is
# visible instead of assumed away.
#
# Usage:
#   agents-md-drift.sh <canon.md> <mirror.md>
#
# Exit codes: 0 = in sync (no section-heading drift), 1 = drift found, 2 = usage/file error.
set -uo pipefail

usage() { echo "usage: agents-md-drift.sh <canon.md> <mirror.md>" >&2; exit 2; }

CANON="${1:-}"; MIRROR="${2:-}"
[ -n "$CANON" ] && [ -n "$MIRROR" ] || usage
[ -f "$CANON" ] || { echo "agents-md-drift: canon file not found: $CANON" >&2; exit 2; }
[ -f "$MIRROR" ] || { echo "agents-md-drift: mirror file not found: $MIRROR" >&2; exit 2; }

# extract_sections FILE — one heading (## or #) per line, normalized (trimmed, lowercased).
extract_sections() {
  grep -E '^#{1,3} ' "$1" | sed -E 's/^#{1,3} +//; s/ +$//' | tr '[:upper:]' '[:lower:]'
}

canon_sections="$(extract_sections "$CANON")"
mirror_sections="$(extract_sections "$MIRROR")"

only_in_canon="$(comm -23 <(echo "$canon_sections" | sort -u) <(echo "$mirror_sections" | sort -u))"
only_in_mirror="$(comm -13 <(echo "$canon_sections" | sort -u) <(echo "$mirror_sections" | sort -u))"

live_hash=$(shasum -a 256 "$CANON" | awk '{print $1}')
echo "agents-md-drift: canon=$CANON mirror=$MIRROR canon-sha256=$live_hash"

status=0
if [ -n "$only_in_canon" ]; then
  status=1
  echo
  echo "  sections in canon, missing from mirror:"
  echo "$only_in_canon" | sed 's/^/    - /'
fi
if [ -n "$only_in_mirror" ]; then
  status=1
  echo
  echo "  sections in mirror, not in canon:"
  echo "$only_in_mirror" | sed 's/^/    - /'
fi

echo
if [ "$status" -eq 0 ]; then
  echo "agents-md-drift: status=IN-SYNC (no section-heading drift)"
else
  echo "agents-md-drift: status=DRIFTED"
fi
exit "$status"
