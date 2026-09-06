#!/bin/zsh
# Casberi perf-readings self-test (prd §623, 2026-09-05) — proves the logic
# behind the Diagnostics screen's "this device's own perf numbers" block, and
# pins the wiring that makes those numbers exist.
#
#   Casberi/Casberi/Model/PerfReadings.swift
#     — lines      (the digest a person screenshots: empty case, one reading,
#                   median/worst arithmetic, fixed span order, the note, and the
#                   two "measuring" hints)
#     — prune      (newest N per span, retention)
#     — measuring  (ONE switch writes BOTH gate keys — `launchTimer` and
#                   `sweepTimer` — the keys `LaunchClock.reports` and
#                   `SweepClock.isOn` already read; a switch that set one would
#                   record a launch with no stall count beside it, which is
#                   half a baseline reading as a whole one)
#
# WHY A HARNESS: the simulator can produce a reading, but a green run there
# says only that the write path executed. Every failure mode below is a
# SILENT WRONG NUMBER on a screen whose purpose is to be believed: a median
# that is really the minimum, "worst" that is really the newest, a cap that
# keeps the OLDEST twenty launches, a switch that flips one gate and not the
# other. `PerfReadings.swift` is compiled VERBATIM — Foundation-only for
# exactly this reason (the `AppMetricsDigest` shape).
#
# The drift guards pin the wiring the assertions cannot reach: that the four
# signpost spans and the sweep report actually hand their numbers over, that
# every save is counted, that the screen and the probe draw through the SAME
# digest, and that the source room's light-column projection stays behind its
# OS gate (docs/perf-spec.md P1 — a bare assignment reproduces §592's
# empty-room defect on iOS 18.6).
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/PerfReadings.swift"
SIGNPOSTS="Casberi/Casberi/Model/AppSignposts.swift"
SWEEP="Casberi/Casberi/Shell/SweepClock.swift"
SAVE="Casberi/Shared/SaveHonestly.swift"
SCREEN="Casberi/Casberi/Screens/DiagnosticsScreen.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
PERFSH="scripts/perf.sh"
for f in "$SRC" "$SIGNPOSTS" "$SWEEP" "$SAVE" "$SCREEN" "$PROBES" "$FEED" "$PERFSH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# Comment-stripped copies for every guard: these files DOCUMENT the rules
# they implement by naming the very calls being checked, so a guard on raw
# source can pass on prose (the Obsidian/Cursor lesson).
strip() { sed -E 's://.*$::' "$1"; }
need() { # need <file> <pattern> <message>
  # Substitution, not a pipe: `grep -q` closes the pipe on its first match,
  # sed dies of SIGPIPE on a file long enough to still be streaming, and
  # `pipefail` then reports a PRESENT line as missing (first run, ProbeHooks).
  grep -qF -- "$2" <<< "$(strip "$1")" || { echo "✗ $3"; echo "   (missing in $1: $2)"; exit 1; }
}

# --- drift guards -----------------------------------------------------------
for span in Launch ForegroundSweep AskFirstPaint AskSettled; do
  need "$SIGNPOSTS" "PerfReadings.record(\"$span\"" \
    "AppSignposts no longer hands the $span span to PerfReadings — the screen's number and MetricKit's histogram must come from ONE stopwatch"
done
need "$SWEEP" 'PerfReadings.record("SweepStalls"' \
  "SweepClock.report no longer records the pass — the stall reading is the P0 number the switch exists for"
need "$SWEEP" 'saves=%d' \
  "the sweepPass| line lost saves= — hitches and saves must sit on ONE line to answer whether each save re-emits the feed"
need "$SAVE" 'SaveCensus.count += 1' \
  "saveHonestly no longer counts saves — saves=N would read 0 forever and look like a fix"
need "$SCREEN" 'PerfReadings.lines(PerfReadings.load(), measuring: PerfReadings.measuring)' \
  "DiagnosticsScreen draws readings through something other than PerfReadings.lines"
need "$SCREEN" 'PerfReadings.measuring = on' \
  "the Measure stalls toggle no longer writes PerfReadings.measuring"
need "$PROBES" 'PerfReadings.lines(PerfReadings.load(), measuring: PerfReadings.measuring)' \
  "-perfReadingsProbe draws through a second digest — the probe must be evidence about the SCREEN"
for key in perfReadingsProbe perfMeasure perfForget; do
  need "$PROBES" "Hook(key: \"$key\")" "the -$key hook is gone"
done
# The gate. Both halves: the projection is INSIDE the gate, and the gate is
# an OS check — not a constant, not a defaults read in Release.
need "$FEED" 'if Self.sourceRoomLightColumns { d.propertiesToFetch = Self.lightColumns }' \
  "the source room's propertiesToFetch is no longer behind sourceRoomLightColumns — on iOS 18.6 a predicated partial fetch returns rows the predicate never selected (§592)"
need "$FEED" 'if #available(iOS 26.0, *) { return true }' \
  "sourceRoomLightColumns is no longer an iOS 26 availability gate"
python3 - "$FEED" <<'PY' || exit 1
import sys, re
src = re.sub(r'//.*', '', open(sys.argv[1]).read())
i = src.find('static var sourceRoomLightColumns: Bool {')
body = src[i:src.find('\n    }\n', i)]
# The DEBUG override must be inside #if DEBUG — a Release knob could turn
# the defect back on from a launch argument.
j = body.find('forKey: "sourceRoomLightColumns"')
if j < 0: sys.exit("✗ the -sourceRoomLightColumns override is gone (it is how the 18.6 arm is driven)")
if body.rfind('#if DEBUG', 0, j) < 0 or body.find('#endif', j) < 0:
    sys.exit("✗ the -sourceRoomLightColumns override is not inside #if DEBUG")
PY
need "$PERFSH" 'eventMessage CONTAINS "sweepPass|"' "perf.sh no longer streams the sweep report"
need "$PERFSH" '-sweepTimer YES' "perf.sh no longer turns the heartbeat on, so it has nothing to report"
echo "✓ perf-readings drift guards green"

# --- the digest, compiled verbatim ------------------------------------------
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
let suite = "casberi.perf-readings-selftest.\(ProcessInfo.processInfo.processIdentifier)"
let d = UserDefaults(suiteName: suite)!
d.removePersistentDomain(forName: suite)
PerfReadings.defaults = d
PerfReadings.buildLabel = { "1.0 (999)" }
var failures = 0
func check(_ ok: Bool, _ msg: String) { if !ok { print("✗ \(msg)"); failures += 1 } }
let now = Date(timeIntervalSince1970: 1_800_000_000)

let empty = PerfReadings.lines([], now: now, measuring: false)
check(empty.count == 2 && empty[0].hasPrefix("Performance: no readings yet"), "empty digest says so in words")
check(empty[1].contains("not being measured"), "empty digest names the switch")

PerfReadings.record("Launch", ms: 812, now: now)
var l = PerfReadings.lines(PerfReadings.load(), now: now, measuring: false)
check(l[0] == "Open → first screen: last 812ms · 1.0 (999)", "one reading has no median/worst: \(l[0])")

PerfReadings.record("Launch", ms: 1412, now: now.addingTimeInterval(60))
PerfReadings.record("Launch", ms: 790, now: now.addingTimeInterval(120))
l = PerfReadings.lines(PerfReadings.load(), now: now, measuring: false)
check(l[0] == "Open → first screen: last 790ms · median 812ms · worst 1412ms over 3 · 1.0 (999)",
      "last is the NEWEST, median is the middle, worst is the max: \(l[0])")

check(PerfReadings.fmt(2300) == "2.3s" && PerfReadings.fmt(1999) == "1999ms" && PerfReadings.fmt(0.4) == "0ms", "fmt switches to seconds at 2s")

PerfReadings.record("AskSettled", ms: 3000, now: now)
PerfReadings.record("AskFirstPaint", ms: 400, note: "early paint", now: now)
PerfReadings.record("SweepStalls", ms: 230, note: "2 stalls totalling 380ms, 7 saves, most in x.topics", now: now)
l = PerfReadings.lines(PerfReadings.load(), now: now, measuring: true)
check(l.map { String($0.split(separator: ":")[0]) } == ["Open → first screen", "Ask → first paint", "Ask → settled", "Worst stall during a sweep"],
      "spans read in the fixed order regardless of arrival: \(l)")
check(l[1].contains("· early paint ·"), "the note rides the newest reading")
check(l[3].contains("7 saves") && l[3].contains("most in x.topics"), "the sweep note carries saves and the worst slot")
check(!l.contains(where: { $0.contains("not being measured") || $0.hasPrefix("Measuring stalls") }),
      "no switch hint once a stall reading exists")

PerfReadings.forget()
PerfReadings.record("Launch", ms: 1, now: now)
l = PerfReadings.lines(PerfReadings.load(), now: now, measuring: true)
check(l.last!.hasPrefix("Measuring stalls"), "switch on but no stall reading yet says when one lands")

var rows: [PerfReadings.Reading] = []
for i in 0..<50 { rows.append(.init(span: "Launch", ms: Double(i), at: now.addingTimeInterval(Double(i)), build: "b", note: "")) }
rows.append(.init(span: "AskSettled", ms: 1, at: now.addingTimeInterval(-40 * 86_400), build: "b", note: ""))
rows.append(.init(span: "AskSettled", ms: 2, at: now, build: "b", note: ""))
let pruned = PerfReadings.prune(rows, now: now.addingTimeInterval(100))
check(pruned.filter { $0.span == "Launch" }.count == PerfReadings.keepPerSpan, "cap per span")
check(pruned.filter { $0.span == "Launch" }.map(\.ms).min() == 30, "the cap keeps the NEWEST, not the oldest")
check(pruned.filter { $0.span == "AskSettled" }.count == 1, "retention drops the 40-day-old row and keeps today's")

PerfReadings.measuring = true
check(d.bool(forKey: "launchTimer") && d.bool(forKey: "sweepTimer"), "the switch sets BOTH gate keys")
PerfReadings.measuring = false
check(!d.bool(forKey: "launchTimer") && !d.bool(forKey: "sweepTimer"), "the switch clears both")

PerfReadings.forget()
check(PerfReadings.load().isEmpty, "forget empties the store")
d.removePersistentDomain(forName: suite)
if failures > 0 { exit(1) }
print("ok")
SWIFT
build() { xcrun swiftc -O -o "$TMP/t" "$1" "$TMP/main.swift" 2>"$TMP/err" || { cat "$TMP/err"; return 1; } }
build "$SRC" && "$TMP/t" >/dev/null || { echo "✗ perf-readings digest failed"; exit 1; }
echo "✓ perf-readings digest verified"

# --- mutations: each must FAIL the assertions above ---------------------------
mutate() { # mutate <name> <perl-expr>
  local name=$1 expr=$2
  perl -0777 -pe "$expr" "$SRC" > "$TMP/m.swift"
  cmp -s "$SRC" "$TMP/m.swift" && { echo "✗ mutation '$name' did not change the source — the anchor drifted"; exit 1; }
  if build "$TMP/m.swift" 2>/dev/null && "$TMP/t" >/dev/null 2>&1; then
    echo "✗ mutation '$name' SURVIVED — the harness cannot see it"; exit 1
  fi
}
mutate "cap keeps the oldest"      's/\.suffix\(keepPerSpan\)/.prefix(keepPerSpan)/'
mutate "median is the minimum"     's/sorted\[sorted\.count \/ 2\]/sorted[0]/'
mutate "switch sets one key only"  's/for k in switchKeys \{ defaults\.set\(newValue, forKey: k\) \}/defaults.set(newValue, forKey: switchKeys[0])/'
mutate "retention never expires"   's/where r\.at > cutoff//'
echo "✓ perf-readings self-test: 4 mutations caught, drift guards green"
