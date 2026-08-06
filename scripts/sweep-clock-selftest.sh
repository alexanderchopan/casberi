#!/bin/zsh
# Casberi sweep-clock self-test — the SHIPPED foreground-sweep instrument
# (2026-08-06):
#
#   Casberi/Casberi/Shell/SweepClock.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
#
# WHY A HARNESS. This file exists to measure a regression class nothing else in
# the tree can see (a foreground sweep holding the main actor; `perf.sh` times
# launch, RSS and answer latency and none of them move). An instrument that
# reports the WRONG number is worse than no instrument at all: it sends whoever
# reads it to optimize the wrong sweep, and it certifies a fix that did nothing.
# Every failure here is silent and renders as a perfectly plausible report.
#
# The first cut of this file shipped exactly such a bug, which is the reason
# the harness exists in this shape: `Duration.components.attoseconds` holds
# only the SUB-SECOND remainder, so a 1.4s sweep reported 400ms and a 2.0s one
# reported ZERO — and the sweeps worth finding are precisely the ones that
# cross the boundary. `ms()` is asserted across it below, and mutation-proven.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

CLOCK="Casberi/Casberi/Shell/SweepClock.swift"
[[ -f "$CLOCK" ]] || { echo "✗ $CLOCK not found"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- drift guards -----------------------------------------------------------
# Wiring the compiled type cannot prove about itself. A flawless SweepClock is
# worthless if nothing calls it, and this is the whole reason it was written.
fail=0
guard() {  # guard <description> <file> <pattern>
  if grep -qE "$3" "$2"; then
    print -r -- "  ✓ $1"
  else
    print -r -- "  ✗ $1 — no match for /$3/ in $2"
    fail=1
  fi
}
print -r -- "drift guards:"
guard "the foreground sweep opens a pass" \
  "Casberi/Casberi/Model/BridgeRefresh.swift" 'SweepClock\.beginPass\(force: force\)'
# The heavy post-271 sweeps, each named. A slot that quietly loses its timer
# does not fail a build and does not fail any other check — it just stops
# appearing in the report, which reads as "that one is fine now".
for label in photos.topics x.topics x.healRoom feeds.articleText youtube.shorts; do
  guard "slot instrumented: $label" \
    "Casberi/Casberi/Model/BridgeRefresh.swift" "sweepTimed\\(\"$label\"\\)"
done
# The tagging hop is the fix the report exists to certify. If `terms(in:)` ever
# goes back on the main actor the numbers stay green and the app stutters again.
guard "topic extraction hops off the main actor" \
  "Casberi/Casberi/Model/ScreenshotTopics.swift" 'Task\.detached\(priority: \.utility\)'
guard "the topics sweep uses it" \
  "Casberi/Casberi/Model/ScreenshotTopics.swift" 'await extract\(rows\.map\(\\\.content\)'
guard "the restamp repair uses it" \
  "Casberi/Casberi/Model/ScreenshotTopics.swift" 'await extract\(texts, includeDomains:'
# The SECOND off-main hop (2026-08-06): `VerbDetection`'s three scans, which a
# device profile put at ~21% of busy main-thread time in the render path and
# which then ran 150 rows deep on every foreground. Same silent-regression
# shape as the tagger — put back on main and every number here stays green.
guard "verb detection hops off the main actor" \
  "Casberi/Casberi/Model/Verbs.swift" 'nonisolated static func detect\(_ inputs: \[Input\]\) async'
guard "the detect hop is detached" \
  "Casberi/Casberi/Model/Verbs.swift" 'Task\.detached\(priority: \.utility\)'
# …and that the three scans take PLAIN VALUES. A scan that takes a `Thing`
# again cannot leave the main actor, and the hop above would go back to being
# a hop that carries nothing.
for fn in 'placeURL\(in input: Input\)' 'telURL\(in input: Input\)' 'mailtoURL\(in input: Input\)'; do
  guard "scan is value-typed: $fn" \
    "Casberi/Casberi/Model/Verbs.swift" "nonisolated static func $fn"
done
guard "the sweep uses the hop" \
  "Casberi/Casberi/Model/VerbDetection.swift" 'await VerbDerivation\.detect\('
guard "the sweep re-checks liveness after the hop (corollary 6)" \
  "Casberi/Casberi/Model/VerbDetection.swift" 'zip\(pending, detected\) where thing\.isLive'
# The PACING fix, which is the other half of the report's subject. The
# automatic sweep must hold past the first-scroll moment and space its slots;
# a pull-to-refresh must not (its contract is immediacy). A revert to one pace
# for both is invisible in every other check.
guard "the automatic sweep holds a lead-in, the pull does not" \
  "Casberi/Casberi/Model/BridgeRefresh.swift" 'let leadInMs = force \? 0 : [0-9]{4}'
guard "the automatic sweep spaces slots wider than the pull" \
  "Casberi/Casberi/Model/BridgeRefresh.swift" 'let slotSpacingMs = force \? 40 : 1[0-9]{2}'
# The pace must be baked in at DISPATCH, not read per slot — otherwise a
# pull-to-refresh mid-sweep re-paces the automatic sweep's remaining slots to
# its own 0/40 and collapses them into the burst the lead-in exists to prevent.
guard "a slot carries its own precomputed delay" \
  "Casberi/Casberi/Model/BridgeRefresh.swift" 'return leadInMs \+ nextSlot \* slotSpacingMs'
guard "stagger sleeps a delay, not an index" \
  "Casberi/Casberi/Model/BridgeRefresh.swift" 'func stagger\(_ delayMs: Int\) async'
# The clock has to be told about that window or it reports half a sweep.
guard "the pass is held open across the dispatch window" \
  "Casberi/Casberi/Model/BridgeRefresh.swift" 'SweepClock\.holdPass\(for: \.milliseconds\(leadInMs \+ nextSlot \* slotSpacingMs\)\)'
# The foreground work OUTSIDE the bridge sweep — deferred on every activation
# (it used to run inline on a return, which was the "lags when I come back"
# half) and on the clock, since it costs about what a bridge slot does.
guard "foreground work is deferred on a return too" \
  "Casberi/Casberi/Shell/RootShell.swift" 'firstActivation \? 800 : [0-9]+'
for label in insight.recompute verbs.detect; do
  guard "slot instrumented: $label" \
    "Casberi/Casberi/Shell/RootShell.swift" "SweepClock\\.measure\\(\"$label\"\\)"
done
# The probe is the only door to the report on a device.
guard "the probe hook exists" \
  "Casberi/Casberi/Shell/ProbeHooks.swift" 'Hook\(key: "sweepTimerProbe"\)'

# --- harness ----------------------------------------------------------------
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
/// Blocks the MAIN ACTOR — not `Task.sleep`, which suspends and would leave the
/// actor free, measuring nothing. The heartbeat's whole claim is that it can
/// detect exactly this, so the test has to actually do it.
func stallMain(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

func value(_ line: String, _ key: String) -> Double? {
    guard let r = line.range(of: key + "=") else { return nil }
    let rest = line[r.upperBound...].prefix { "0123456789.".contains($0) }
    return Double(rest)
}
func line(_ lines: [String], _ needle: String) -> String? {
    lines.first { $0.contains(needle) }
}

// Top-level code runs on the main actor, so these calls need no hop.
SweepClock.enable()

// 1. Wall time across the one-second boundary — the bug this harness exists
//    for. A 1.2s sweep must read ~1200ms, never ~200ms and never 0.
await SweepClock.measure("slow") { try? await Task.sleep(for: .milliseconds(1200)) }
var lines = SweepClock.summary()
let slow = line(lines, "slow").flatMap { value($0, "wall") } ?? -1
check(slow > 1100 && slow < 1500, "wall time crosses the 1s boundary (read \(Int(slow))ms)")

// 2. A sweep that BLOCKS the main actor is charged a hitch; the pass total
//    sees it too. This is the jank signal — the number the whole instrument
//    exists to produce.
await SweepClock.measure("blocker") {
    stallMain(0.35)
    try? await Task.sleep(for: .milliseconds(60))
}
lines = SweepClock.summary()
let blockerHitches = line(lines, "blocker").flatMap { value($0, "hitches") } ?? 0
let blockerStalled = line(lines, "blocker").flatMap { value($0, "stalled") } ?? 0
check(blockerHitches >= 1, "a main-actor stall is charged to the sweep in flight")
check(blockerStalled > 200, "the stall is measured near its real length (read \(Int(blockerStalled))ms)")
let pass = line(lines, "sweepPass|")
check((pass.flatMap { value($0, "hitches") } ?? 0) >= 1, "the pass total counts the hitch")
check((pass.flatMap { value($0, "worst") } ?? 0) > 200, "the pass reports the worst stall")

// 3. A sweep that only AWAITS is not called janky. A network read that takes
//    two seconds costs nobody a frame, and an instrument that flags it sends
//    the next person to optimize the wrong thing.
await SweepClock.measure("waiter") { try? await Task.sleep(for: .milliseconds(400)) }
lines = SweepClock.summary()
check((line(lines, "waiter").flatMap { value($0, "hitches") } ?? 99) == 0,
      "an awaiting sweep is charged no hitch")

// 4. Rank is by time STALLED, not wall time — `waiter` is slower than
//    `blocker` by the clock and must still sort below it.
let slots = lines.filter { $0.contains("sweepSlot|") }
let firstLabel = slots.first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
check(firstLabel == "blocker", "the report ranks by stall, not by wall time (led with \(firstLabel))")

// 5. Every label that ran appears. A report that silently drops one reads as
//    a sweep that cost nothing.
for label in ["slow", "blocker", "waiter"] {
    check(line(lines, label) != nil, "the report names \(label)")
}

// 6. The instrument returns the work's own value and runs it exactly once.
var runs = 0
let returned = await SweepClock.measure("passthrough") { () -> Int in runs += 1; return 41 + 1 }
check(returned == 42 && runs == 1, "measure is transparent: returns the value, runs once")

// 7. `holdPass` keeps ONE sweep in one report across a dispatch gap wider than
//    any settle. This is what the 2026-08-06 pacing change needs: slots are
//    spread over seconds now, so an early slot and a late one are separated by
//    a silence that would otherwise close the pass — and the split reads as
//    two small sweeps, i.e. as the jank having gone away.
SweepClock.report()          // close and clear whatever is open
SweepClock.beginPass()
SweepClock.holdPass(for: .milliseconds(3500))
await SweepClock.measure("early") { try? await Task.sleep(for: .milliseconds(50)) }
// Longer than `settle`, so an unheld pass has certainly reported by now.
try? await Task.sleep(for: .milliseconds(3000))
await SweepClock.measure("late") { try? await Task.sleep(for: .milliseconds(50)) }
lines = SweepClock.summary()
check(line(lines, "early") != nil && line(lines, "late") != nil,
      "a held pass keeps both sides of a dispatch gap in one report")

print(failures == 0 ? "sweep-clock-selftest: OK" : "sweep-clock-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

compile() {  # compile <clock-source> <out>
  # NOT `-parse-as-library`: the harness is top-level code in main.swift, and
  # under that flag every line of it is "expressions are not allowed at the top
  # level" — which the mutation loop below then scores as the MUTATION being
  # caught. Every mutation "passed" that way on the first run while testing
  # nothing at all (the x-selftest stale-fixture lesson, one layer meaner: the
  # harness was green because it was broken).
  swiftc -O -o "$2" "$1" "$WORK/main.swift" -module-name selftest 2>&1 \
    | grep -E 'error:' && return 1
  return 0
}

print ""; print -r -- "assertions:"
cp "$CLOCK" "$WORK/clock.swift"
compile "$WORK/clock.swift" "$WORK/run" || { echo "✗ harness did not compile"; exit 1; }
"$WORK/run" || fail=1

# --- mutations --------------------------------------------------------------
# Each is a silent wrong answer this harness must catch. A check that cannot
# fail proves nothing (the liveness audit's `--self-test` reasoning).
print ""; print -r -- "mutations (each MUST fail the harness):"
mutate() {  # mutate <name> <sed-expression>
  cp "$CLOCK" "$WORK/mut.swift"
  sed -i '' "$2" "$WORK/mut.swift"
  if ! cmp -s "$CLOCK" "$WORK/mut.swift"; then
    if compile "$WORK/mut.swift" "$WORK/mutrun" && "$WORK/mutrun" >/dev/null 2>&1; then
      print -r -- "  ✗ NOT CAUGHT: $1"
      fail=1
    else
      print -r -- "  ✓ caught: $1"
    fi
  else
    print -r -- "  ✗ STALE MUTATION (matched nothing): $1"
    fail=1
  fi
}
# The shipped bug: seconds dropped, so anything over 1s reports its remainder.
mutate "ms() reads attoseconds only (the 2026-08-06 bug)" \
  's|return Double(c.seconds) \* 1000 + Double(c.attoseconds) / 1e15|return Double(c.attoseconds) / 1e15|'
# A floor high enough to never fire reports a perfectly smooth app.
mutate "hitch floor raised past any real stall" \
  's|private static let hitchFloorMs: Double = 100|private static let hitchFloorMs: Double = 100000|'
# Charging the stall to nobody keeps the pass total honest and makes the
# per-slot ranking useless — the half of the report that names what to fix.
mutate "hitches no longer charged to the sweep in flight" \
  's|let charge = inFlight.isEmpty ? \["(none)"\] : Array(inFlight.keys)|let charge: [String] = []|'
# Ranking by wall time puts the slowest network read at the top of a report
# about jank.
mutate "report ranks by wall time instead of stall" \
  's|for label in order.sorted(by: { (entries\[\$0\]?.hitchMs ?? 0, entries\[\$0\]?.wallMs ?? 0)|for label in order.sorted(by: { (entries[$0]?.wallMs ?? 0, entries[$0]?.wallMs ?? 0)|'
# A `holdPass` that returns before the dispatch window is over lets the pass
# close in the gap the 2026-08-06 pacing opened, splitting one sweep into two
# reports that each look small. Nothing else here would notice — the numbers in
# both halves are correct, there are just two of them.
mutate "holdPass returns before the dispatch window is over" \
  's|try? await Task.sleep(for: window)|try? await Task.sleep(for: .zero)|'

print -r -- ""
if [[ $fail -eq 0 ]]; then
  print -r -- "sweep-clock-selftest: OK"
else
  print -r -- "sweep-clock-selftest: FAILED"
  exit 1
fi
