#!/bin/zsh
# Nightly Mac pass — what launchd actually runs (see com.casberi.nightly-mac
# below). Thin on purpose: verify-mac.sh holds every check; this only wraps it
# in the three things an unattended run needs and an interactive one doesn't.
#
#   1. A durable one-line-per-night ledger, so a slow drift is visible without
#      opening 30 output dirs.
#   2. Pruning, so nightly screenshots don't grow without bound.
#   3. A non-zero exit that is actually recorded somewhere a human will look.
#
# Install (once):
#   cp scripts/com.casberi.nightly-mac.plist ~/Library/LaunchAgents/
#   launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.casberi.nightly-mac.plist
# Run it by hand any time:
#   launchctl kickstart -p gui/$UID/com.casberi.nightly-mac
# Uninstall:
#   launchctl bootout gui/$UID/com.casberi.nightly-mac
#
# WHY LAUNCHD AND NOT CRON/A CLOUD RUNNER: this drives a real GUI app. It
# needs a logged-in user session with a window server — a LaunchAgent has one,
# a LaunchDaemon and a cloud runner do not. It follows that a nightly only
# fires while the Mac is awake and logged in; a closed lid means the run is
# skipped, not queued, and the ledger simply has no row for that night.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEDGER="$ROOT/scripts/output/nightly-mac.log"
KEEP=14          # nights of output dirs to retain

mkdir -p "$ROOT/scripts/output"
TS=$(date +%Y-%m-%dT%H:%M:%S)
SHA=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)

# The run. Full launch-survival cycles — the intermittent first-frame crash
# class is exactly what an unattended nightly is FOR, and nobody is waiting.
# VERIFY_NO_CACHE: an unattended green is the one nobody re-reads, so no
# scheduled pass may ever be served a CACHED verdict — `verify.sh`'s skip cache
# (2026-08-19) trades a re-run for "the harness and every file it names are
# byte-identical to a run that passed", which is the right trade at a keyboard
# and the wrong one at 03:20 with nobody looking. Exported rather than set on
# the command below, so it reaches anything this wrapper grows later.
#
# Today it is a BELT, not a fix, and that is worth saying plainly: this nightly
# drives `verify-mac.sh`, whose logic self-tests are its own DISCOVERED
# sequential loop with no cache of any kind, so nothing here reads the flag
# yet. It is set now so that the day that loop gains the cache — or this
# wrapper calls `verify.sh` — the nightly is already correct rather than
# quietly cached.
export VERIFY_NO_CACHE=1

LAUNCH_CYCLES=${LAUNCH_CYCLES:-10} "$ROOT/scripts/verify-mac.sh" > /tmp/nightly-mac-run.log 2>&1
STATUS=$?

# From the OUTPUT_DIR line verify-mac.sh prints before any check runs, so a
# FAILING night still records where to look.
RUN_DIR=$(grep -o 'OUTPUT_DIR /.*/mac-[0-9-]*' /tmp/nightly-mac-run.log | tail -1 | cut -d' ' -f2)
[[ -n "$RUN_DIR" ]] && cp /tmp/nightly-mac-run.log "$RUN_DIR/console.log" 2>/dev/null

# Pull the three perf numbers straight out of the run's own report rather than
# recomputing them — one source of truth per night.
PERF="n/a"
if [[ -n "$RUN_DIR" && -f "$RUN_DIR/perf.txt" ]]; then
  L=$(grep -o 'launch (init→ready): [0-9]*ms' "$RUN_DIR/perf.txt" | grep -o '[0-9]*' | head -1)
  M=$(grep -o 'memory (RSS): [0-9]*MB'        "$RUN_DIR/perf.txt" | grep -o '[0-9]*' | head -1)
  A=$(grep -o 'answer (compose): [0-9]*ms'    "$RUN_DIR/perf.txt" | grep -o '[0-9]*' | head -1)
  PERF="launch=${L:-?}ms rss=${M:-?}MB answer=${A:-?}ms"
fi

# The failing STEP, not just the exit code — "cold-launch cycle 7" and "find
# probe" are different nights, and a bare FAIL makes them look the same.
if (( STATUS == 0 )); then
  # Read the run's own SUMMARY line rather than counting "⚠" in the console:
  # the perf section prints that character for flags it raises BY DESIGN and
  # never gates on, so counting them scored a perfectly clean night as
  # "PASS(5warn)" (caught on the first wrapper run, 2026-08-01). Live
  # warnings mean a third party was unreachable; perf flags mean a number
  # moved. Only the first is a warning about US, so only it colours the
  # verdict — the flag count still rides along, unranked.
  # Matched as `SUMMARY .*` rather than by spelling every field: the line
  # gained `logic_skipped` on 2026-09-01, and an exact-field pattern silently
  # matches NOTHING the day a field is added — which reads as a night with no
  # summary at all, i.e. the exact silent gap this ledger exists to close.
  # Each field is then pulled out by name, so order and additions are free.
  SUMMARY=$(grep -o 'SUMMARY .*' /tmp/nightly-mac-run.log | tail -1)
  LIVE_W=$(echo "$SUMMARY" | grep -o 'live_warnings=[0-9]*' | cut -d= -f2)
  PERF_F=$(echo "$SUMMARY" | grep -o 'perf_flags=[0-9]*'    | cut -d= -f2)
  LIVE_S=$(echo "$SUMMARY" | grep -o 'live_skipped=[0-9]*'  | cut -d= -f2)
  LOGIC_S=$(echo "$SUMMARY" | grep -o 'logic_skipped=[0-9]*' | cut -d= -f2)
  VERDICT="PASS"
  (( ${LIVE_S:-0} == 1 )) && VERDICT="PASS(live skipped)"
  (( ${LIVE_W:-0} > 0 ))  && VERDICT="PASS(${LIVE_W} live-warn)"
  (( ${PERF_F:-0} > 0 ))  && VERDICT="$VERDICT[${PERF_F} perf-flag]"
  # The nightly never sets SKIP_LOGIC — it is the pass that must run all 86
  # uncached. Recorded anyway, because a row that reads exactly like a full
  # night while 86 checks never ran is the one thing this ledger must not say.
  (( ${LOGIC_S:-0} == 1 )) && VERDICT="$VERDICT[logic SKIPPED]"
else
  # Strip ANSI before trimming: `fail()` colours its output, so the escape
  # codes rode into the ledger and every FAIL row ended in a stray "[39m".
  VERDICT="FAIL: $(grep '✗' /tmp/nightly-mac-run.log | tail -1 \
    | sed $'s/\033\\[[0-9;]*m//g' | sed 's/^✗ *//' | cut -c1-90)"
fi

print -r -- "$TS  $SHA  $VERDICT  $PERF  ${RUN_DIR:-no-output-dir}" >> "$LEDGER"

# Prune: keep the most recent $KEEP mac-* dirs, drop the rest.
print -l -- "$ROOT"/scripts/output/mac-*(/om) 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -rf "$old"
done

exit $STATUS
