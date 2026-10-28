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
#   bluesky, connect, find, github, maillist, note, share, site, spending,
#   stoptracking, stripe, subscription, wallet, x. Two sweeps are opt-in:
#   `catalog` (every app's first step, prd §1306) and `sheets` (every sheet,
#   tray and cover opened and closed, prd §1308; JOURNEYS_SHEETS="id,id"
#   narrows it to those entries of scripts/sheet-sweep.json).
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
                   spending testSpending subscription testSubscription
                   maillist testMailList site testSite wallet testWallet
                   stripe testStripe bluesky testBluesky github testGitHub x testX
                   share testShare stoptracking testStopTracking catalog testCatalog)
typeset -a ONLY
if (( $# == 0 )); then
  # The catalogue sweep is opt-in (`journeys.sh catalog`, ~20 minutes, prd
  # §1306): every other journey runs by default.
  ONLY=(-only-testing:CasberiUITests/JourneyTests -skip-testing:CasberiUITests/JourneyTests/testCatalog)
else
  for j in "$@"; do
    # The sheet sweep is its own test class (`SheetSweepTests`).
    if [[ "$j" == sheets ]]; then
      # One test case per sheet (`SheetSweepTests.defaultTestSuite`), and a
      # failed case runs once more: an XCUITest hiccup is not a stuck sheet.
      ONLY+=(-only-testing:CasberiUITests/SheetSweepTests -retry-tests-on-failure -test-iterations 2)
      continue
    fi
    [[ -n "${METHOD[$j]-}" ]] || { print -P "%F{red}✗ no journey \"$j\" (${(k)METHOD} sheets)%f"; exit 2; }
    ONLY+=(-only-testing:CasberiUITests/JourneyTests/${METHOD[$j]})
  done
fi

# A clean install per run: a journey that tracks a subscription or writes a
# note leaves it behind, and the next run would walk a different path. The
# test target reinstalls the app; each journey launches with its own state.
xcrun simctl boot "$DEVICE_ID" 2>/dev/null
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null 2>&1
# The app group outlives an uninstall (its SwiftData store, the followed
# wallets and feeds), so a wallet or site followed last run would still be
# followed: removed with the app, so every run starts truly clean.
GROUP="$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE" group.com.casberi.app 2>/dev/null)"
xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE" 2>/dev/null
[[ -n "$GROUP" && "$GROUP" == */AppGroup/* ]] && rm -rf "$GROUP"
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
# The catalogue's names for the sweep, read off `BridgeCatalog.offers` (the
# one source of truth for the app list, CLAUDE.md), one per line.
CATALOG="$OUT/catalog-names.txt"
grep -oE 'Offer\(name: "[^"]+"' "$ROOT/Casberi/Casberi/Model/BridgeCatalog.swift" \
  | sed -E 's/Offer\(name: "//; s/"$//' | sort -u \
  | grep -vx 'Markets' | grep -vx 'Wallet' | grep -vx '…' > "$CATALOG"   # built in (prd §1234, §1316); a placeholder
# JOURNEYS_APPS="A,B" narrows the sweep to those apps (a re-check of what it flagged).
if [[ -n "${JOURNEYS_APPS:-}" ]]; then
  print -l -- ${(s:,:)JOURNEYS_APPS} > "$CATALOG"
fi

# TDLib (prd §1575) is linked from the Mac-wide cache, never committed, so a
# fresh worktree (nightly-mac.sh cuts one each night) has no framework until
# this runs; without it the test build fails and no journey reports at all.
"$ROOT/scripts/tdlib.sh" || { print -P "%F{red}✗ TDLib could not be linked (scripts/tdlib.sh)%f"; exit 1; }

TEST_RUNNER_JOURNEYS_OUT="$OUT" TEST_RUNNER_JOURNEYS_CATALOG="$CATALOG" \
TEST_RUNNER_JOURNEYS_SHEETS="$ROOT/scripts/sheet-sweep.json" TEST_RUNNER_JOURNEYS_SHEET_IDS="${JOURNEYS_SHEETS:-}" \
"$ROOT/scripts/xcb.sh" \
  -project "$ROOT/Casberi/Casberi.xcodeproj" -scheme Casberi \
  -destination "id=$DEVICE_ID" -derivedDataPath "$HOME/Library/Developer/CasberiDD" \
  "${ONLY[@]}" test > "$OUT/xcodebuild.log" 2>&1
TEST_STATUS=$?
(( TEST_STATUS != 0 )) && print -P "%F{yellow}⚠ xcodebuild exited $TEST_STATUS — a broken journey does that; the report says which%f"

# The sheet sweep reports apart: one row per sheet, ✗ for one that did not
# open or did not close (prd §1308).
if [[ -f "$OUT/sheets.tsv" ]]; then
  # A retried case writes twice; its last row is its result.
  python3 - "$OUT/sheets.tsv" <<'PY'
import sys
rows = {}
for line in open(sys.argv[1], encoding="utf-8"):
    if line.strip():
        rows[line.split("\t", 1)[0]] = line
open(sys.argv[1], "w", encoding="utf-8").writelines(rows.values())
PY
  python3 "$ROOT/scripts/sheet-sweep-report.py" "$OUT/sheets.tsv" "$ROOT/scripts/sheet-sweep.json" \
    "${JOURNEYS_SHEETS:-}" | tee "$OUT/sheets-report.txt"
  [[ -f "$OUT/results.tsv" || -f "$OUT/catalog.tsv" ]] || { print -P "%F{green}✓ sheet report: $OUT/sheets-report.txt%f"; exit 0; }
fi

# The sweep reports apart: one row per app, flagged over the target or with
# no first step found (prd §1306).
if [[ -f "$OUT/catalog.tsv" ]]; then
  python3 "$ROOT/scripts/journeys-report.py" --catalog "$OUT/catalog.tsv" \
    "$ROOT/scripts/journeys-targets.json" | tee "$OUT/catalog-report.txt"
  [[ -f "$OUT/results.tsv" ]] || { print -P "%F{green}✓ catalogue report: $OUT/catalog-report.txt%f"; exit 0; }
fi

python3 "$ROOT/scripts/journeys-report.py" "$OUT/results.tsv" "$HIST" "$SHA" \
  "$ROOT/scripts/journeys-targets.json" | tee "$OUT/report.txt"
REPORT_STATUS=${pipestatus[1]}
if (( REPORT_STATUS != 0 )); then
  print -P "%F{red}✗ no journey reported — read $OUT/xcodebuild.log (a build failure lands there)%f"
  exit 1
fi
print -P "%F{green}✓ journeys report: $OUT/report.txt · history: ${HIST#$ROOT/}%f"
exit 0
