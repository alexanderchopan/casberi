#!/bin/zsh
# Journeys — how much a person has to DO to get a job done, measured with real
# taps (2026-10-14). Each journey in `CasberiUITests/JourneyTests.swift` walks
# one job from where a person starts, through the UI only (no hook skips a
# step), and counts taps, characters typed and seconds.
# `scripts/journeys-report.py` compares each with its last good run and appends
# to `scripts/output/journeys-history.csv`.
#
# Exits 0 when a report was written, like perf.sh: a journey that got longer is
# a product question for a person, not a red build. A journey that BROKE (a step
# not found) is reported ✗ with the step; read it before assuming the app broke,
# since a renamed label breaks a journey the same way.
#
# Usage: scripts/journeys.sh [journey ...]     e.g. scripts/journeys.sh find note
#   No names: every journey. A name is a test method without `test`, lowercased:
#   connect, note, find, spending, subscription.
# Output: scripts/output/journeys-<ts>/ — results.tsv, xcodebuild.log, and one
#   screenshot per step (<journey>-<n>-<step>.png), the before shots a proposal
#   is drawn against.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/scripts/output/journeys-$(date +%Y%m%d-%H%M%S)"
HIST="$ROOT/scripts/output/journeys-history.csv"
BUNDLE="com.casberi.app"
mkdir -p "$OUT"

DEVICE_ID="$(python3 "$ROOT/scripts/sim-device.py" "iPhone 17 Pro")" || {
  print -P "%F{red}✗ could not resolve a simulator — see above%f"; exit 1; }
SHA=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)

typeset -A METHOD=(connect testConnect note testNote find testFind
                   spending testSpending subscription testSubscription)
typeset -a ONLY
if (( $# == 0 )); then
  ONLY=(-only-testing:CasberiUITests/JourneyTests)
else
  for j in "$@"; do
    [[ -n "${METHOD[$j]-}" ]] || { print -P "%F{red}✗ no journey \"$j\" (${(k)METHOD})%f"; exit 2; }
    ONLY+=(-only-testing:CasberiUITests/JourneyTests/${METHOD[$j]})
  done
fi

# A clean install per run: a journey that tracks a subscription or writes a
# note leaves it behind, and the next run would walk a different path. The
# test target reinstalls the app; each journey launches with its own state.
xcrun simctl boot "$DEVICE_ID" 2>/dev/null
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null 2>&1
xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE" 2>/dev/null
# The demo pour asks for these on a fresh install, and an unanswered system
# sheet blocks every tap (CLAUDE.md, simulator gotchas). Granted up front; the
# walk also dismisses any alert that still shows, and does not count it.
# Calendar is RESET, never granted: `connect` walks iOS's calendar ask as
# its own step, and a grant would skip it.
for svc in photos reminders contacts; do
  xcrun simctl privacy "$DEVICE_ID" grant "$svc" "$BUNDLE" 2>/dev/null
done
xcrun simctl privacy "$DEVICE_ID" reset calendar "$BUNDLE" 2>/dev/null

print -P "%F{cyan}▶ journeys on $DEVICE_ID at $SHA → $OUT%f"
TEST_RUNNER_JOURNEYS_OUT="$OUT" "$ROOT/scripts/xcb.sh" \
  -project "$ROOT/Casberi/Casberi.xcodeproj" -scheme Casberi \
  -destination "id=$DEVICE_ID" -derivedDataPath "$HOME/Library/Developer/CasberiDD" \
  "${ONLY[@]}" test > "$OUT/xcodebuild.log" 2>&1
TEST_STATUS=$?
(( TEST_STATUS != 0 )) && print -P "%F{yellow}⚠ xcodebuild exited $TEST_STATUS — a broken journey does that; the report says which%f"

python3 "$ROOT/scripts/journeys-report.py" "$OUT/results.tsv" "$HIST" "$SHA" \
  "$ROOT/scripts/journeys-targets.json" | tee "$OUT/report.txt"
REPORT_STATUS=${pipestatus[1]}
if (( REPORT_STATUS != 0 )); then
  print -P "%F{red}✗ no journey reported — read $OUT/xcodebuild.log (a build failure lands there)%f"
  exit 1
fi
print -P "%F{green}✓ journeys report: $OUT/report.txt · history: ${HIST#$ROOT/}%f"
exit 0
