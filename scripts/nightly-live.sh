#!/bin/zsh
# Nightly live-integrations pass — what launchd runs (see
# com.casberi.nightly-live.plist). Thin on purpose, like nightly-mac.sh:
# live-integrations.sh holds every row; this wraps it in the two things an
# unattended run needs and an interactive one doesn't.
#
#   1. A durable one-line-per-night LEDGER (scripts/output/nightly-live.log),
#      read back and REPORTED by verify.sh at the start of every pass — never
#      gated on, because it describes a third party on a different day.
#   2. The full table kept per night (scripts/output/live-<ts>.log), pruned.
#
# WHY THIS EXISTS (2026-09-08, prd §654). live-integrations.sh grew drift rows
# for all four devnet seats — Hegotá's frame-shape baseline and "what did the
# chain add" census, vibenet's contracts-config diff, Frames' genesis and
# envelope names, and now Privacy's — and NOTHING RAN IT. The Mac nightly's
# live block is three in-app probes (RSS, LinkTitle, oEmbed); verify.sh keeps
# this script out by contract. So every devnet drift detector printed to a
# terminal nobody opened, i.e. did not exist. The question that surfaced it:
# "how will we know if and when we need to update data models for our
# devnets?" — the honest answer was "we won't".
#
# Install (once):
#   cp scripts/com.casberi.nightly-live.plist ~/Library/LaunchAgents/
#   launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.casberi.nightly-live.plist
# Run it by hand any time:
#   launchctl kickstart -p gui/$UID/com.casberi.nightly-live
# Uninstall:
#   launchctl bootout gui/$UID/com.casberi.nightly-live
#
# A LaunchAgent for symmetry with nightly-mac, not necessity — this is curl and
# python3 only, no window server needed. It follows the same rule: a closed lid
# means the night is SKIPPED, not queued, and the ledger has no row for it,
# which verify.sh reports as staleness.
set -uo pipefail
# A LaunchAgent inherits NO locale (LANG unset, LC_COLLATE=C), and under a C
# locale `grep` matches a multibyte glyph BY BYTE — `[✗⚠]` then matches every
# ✓ row and every ─── rule, since they share a lead byte. Found on the first
# by-hand run (2026-09-08): the ledger's "flagged rows" were the whole table.
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/scripts/output"
LEDGER="$OUT/nightly-live.log"
KEEP=30          # nights of full tables to retain

mkdir -p "$OUT"
TS=$(date +%Y-%m-%dT%H:%M:%S)
SHA=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
TABLE="$OUT/live-$TS.log"

"$ROOT/scripts/live-integrations.sh" > "$TABLE" 2>&1
STATUS=$?   # always 0 by that script's contract; recorded in case that changes

# Strip ANSI once; every read below is off the plain copy.
PLAIN=$(sed $'s/\033\\[[0-9;]*m//g' "$TABLE")

# The script's own counters, from its closing line — never recounted from the
# glyphs (nightly-mac's 2026-08-01 lesson: counting "⚠" scored a clean night
# as warned). Three closing shapes, each carrying the numbers differently.
RED=0; AMBER=0
last=$(print -r -- "$PLAIN" | grep -E 'All live-integration hosts healthy|soft flag\(s\)|host issue\(s\)' | tail -1)
case "$last" in
  *"All live-integration hosts healthy"*) ;;
  *"soft flag(s), 0 failures"*) AMBER=$(print -r -- "$last" | grep -oE '^[0-9]+' ) ;;
  *"host issue(s)"*)
    RED=$(print -r -- "$last" | grep -oE '^[0-9]+')
    AMBER=$(print -r -- "$last" | grep -oE '\+[0-9]+ soft' | grep -oE '[0-9]+') ;;
  *) RED="?"; AMBER="?" ;;   # no closing line at all: the script died mid-table
esac
[[ -z "$RED" ]] && RED=0; [[ -z "$AMBER" ]] && AMBER=0

# The flagged rows themselves, so the ledger says WHAT moved without opening
# the table: "✗ Frames — THE DEVNET RESTARTED" is a different night from
# "⚠ Jupiter — 503", and a bare count makes them the same. Failures first.
FLAGGED=$(print -r -- "$PLAIN" | grep -E '^ *(✗|⚠)' | sed -E 's/^ *//' \
          | awk '/^✗/{print; next} {a[NR]=$0} END{for(i=1;i<=NR;i++) if(i in a) print a[i]}')
COUNT=$(print -r -- "$FLAGGED" | grep -c .)
if (( COUNT == 0 )); then
  VERDICT="CLEAN"
else
  VERDICT="red=$RED amber=$AMBER"
fi

print -r -- "$TS  $SHA  $VERDICT  $TABLE" >> "$LEDGER"
# The flagged rows ride UNDER the row, indented, so `tail -1` still yields one
# parseable line and a person reading the file sees what each night said.
if (( COUNT > 0 )); then
  print -r -- "$FLAGGED" | head -12 | sed 's/^/    /' >> "$LEDGER"
  (( COUNT > 12 )) && print -r -- "    … $((COUNT - 12)) more in $TABLE" >> "$LEDGER"
fi

# Prune: keep the most recent $KEEP tables.
print -l -- "$OUT"/live-*.log(.om) 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -f "$old"
done

exit $STATUS
