#!/bin/zsh
# Feed-seam self-test (prd §866, 2026-09-21) — the day seam you feel:
#
#   Casberi/Casberi/Model/FeedSeam.swift   compiled WHOLE and unmodified
#
# WHY A HARNESS. Every failure mode here is SILENT on the screen and only ever
# felt, which is the one category a screenshot sweep, a census and a room probe
# are all blind to. The whole feature is four guards in one small state machine,
# and each of them reads like a line you could simplify away:
#
#   • THE FIRST-PLACEMENT GUARD (`was != 0`). Arriving on a side is not crossing
#     to it. Drop it and every divider the List MOUNTS ticks — so landing on the
#     feed, or any scroll that brings a new day into the window, buzzes for a
#     seam nothing crossed. This is the one that turns a texture into a rattle.
#   • THE HAND GATE. A fling crosses six days in half a second. Drop it and the
#     tick fires through the deceleration, when the finger is not on the glass.
#   • THE GAP. A fast drag is still a drag, so the hand gate alone does not bound
#     the rate. Two seams inside `minGap` were one motion; the second is DROPPED,
#     never queued — a queued one would arrive after the motion that earned it.
#   • THE DEAD BAND. A bare `minY < 0` flickers for a divider parked at the line:
#     sub-point jitter reads as a crossing every frame. Nothing inside ±`band`
#     is a side at all.
#
# Plus the drift guards no compiled assertion can see: that the divider still
# observes, that the hand flag is still written and still cleared, and that the
# feel is declared in BOTH grammars (`dsSensoryFeedback` and `SheetHaptics`) —
# a counter bumped with no mapping is a haptic that silently never fires.
#
# Pure, local, deterministic — no network, no simulator, no key.
set -euo pipefail
cd "$(dirname "$0")/.."

SEAM="Casberi/Casberi/Model/FeedSeam.swift"
DIVIDER="Casberi/Casberi/Screens/FeedDayDivider.swift"
CHROME="Casberi/Casberi/Shell/ShellChrome.swift"
HAPTICS="Casberi/Casberi/Design/Haptics.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
FLOOR="Casberi/Casberi/Screens/CorpusFloor.swift"
MARK="Casberi/Casberi/Design/CasberiMark.swift"
for f in "$SEAM" "$DIVIDER" "$CHROME" "$HAPTICS" "$FEED" "$FLOOR" "$MARK"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/feed-seam-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# `FeedSeam` calls `DSHaptic.seam()`, which lives in the SwiftUI design layer.
# Stubbed so the state machine compiles Foundation-only — and the stub COUNTS,
# so every assertion below is about ticks that actually reached the bus.
cat > "$TMP/stub.swift" <<'SWIFT'
import Foundation

enum DSHaptic {
    nonisolated(unsafe) static var ticks = 0
    static func seam() { ticks += 1 }
}
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

/// A fresh divider, and the tick count reset. Every case below starts here so
/// one case's debt can never pay for the next one's assertion.
func fresh() -> FeedSeam.Tracker {
    DSHaptic.ticks = 0
    FeedSeam.set(dragging: false)
    return FeedSeam.Tracker()
}

/// The gap is real time, so a case that means to clear it has to spend it.
func pastTheGap() {
    Thread.sleep(forTimeInterval: 0.35)
}

// --- the dead band -------------------------------------------------------------
check(FeedSeam.side(ofTop: -40) == -1, "a divider well above the line is on the top side")
check(FeedSeam.side(ofTop: 40) == 1, "a divider well below the line is on the bottom side")
check(FeedSeam.side(ofTop: 0) == 0, "exactly on the line is NO side")
check(FeedSeam.side(ofTop: 0.4) == 0 && FeedSeam.side(ofTop: -0.4) == 0,
      "sub-point jitter at the line is not a crossing")
check(FeedSeam.side(ofTop: FeedSeam.band) == 0 && FeedSeam.side(ofTop: -FeedSeam.band) == 0,
      "the band edge itself is still the band, not a side")
check(FeedSeam.band > 1,
      "the band is wider than a point — a band that narrow cannot swallow jitter")

// --- the hand gate -------------------------------------------------------------
do {
    let t = fresh()
    FeedSeam.observe(side: 1, in: t)
    FeedSeam.observe(side: -1, in: t)
    check(DSHaptic.ticks == 0, "a crossing with no finger on the glass is SILENT (a fling)")
    // The crossing still has to be RECORDED while silent, or the finger landing
    // mid-fling would tick for a seam that went by without it.
    check(t.side == -1, "a silent crossing still moves the tracker")
}

// --- the first-placement guard -------------------------------------------------
do {
    let t = fresh()
    FeedSeam.set(dragging: true)
    FeedSeam.observe(side: -1, in: t)
    check(DSHaptic.ticks == 0, "a divider's FIRST placement is not a crossing (it mounted there)")
    check(t.side == -1, "...but it is placed")
}
do {
    let t = fresh()
    FeedSeam.set(dragging: true)
    FeedSeam.observe(side: 0, in: t)
    FeedSeam.observe(side: 0, in: t)
    check(DSHaptic.ticks == 0, "a divider seen only inside the band has no side and says nothing")
    check(t.side == 0, "...and is still unplaced")
    FeedSeam.observe(side: 1, in: t)
    check(DSHaptic.ticks == 0, "leaving the band for the first time is placement, not a crossing")
}

// --- one tick per crossing -----------------------------------------------------
do {
    let t = fresh()
    FeedSeam.set(dragging: true)
    FeedSeam.observe(side: 1, in: t)          // placed below
    FeedSeam.observe(side: 0, in: t)          // into the band
    FeedSeam.observe(side: -1, in: t)         // out the top — one crossing
    check(DSHaptic.ticks == 1, "a full crossing through the band ticks exactly once — got \(DSHaptic.ticks)")
    FeedSeam.observe(side: -1, in: t)
    FeedSeam.observe(side: 0, in: t)
    FeedSeam.observe(side: -1, in: t)
    check(DSHaptic.ticks == 1, "re-reporting the same side, band dips included, is not a new crossing")
}
do {
    let t = fresh()
    FeedSeam.set(dragging: true)
    FeedSeam.observe(side: 1, in: t)
    FeedSeam.observe(side: -1, in: t)
    check(DSHaptic.ticks == 1, "a crossing that SKIPS the band still ticks (a fast sample)")
}

// --- the gap -------------------------------------------------------------------
do {
    let t = fresh()
    FeedSeam.set(dragging: true)
    FeedSeam.observe(side: 1, in: t)
    FeedSeam.observe(side: -1, in: t)
    FeedSeam.observe(side: 1, in: t)
    FeedSeam.observe(side: -1, in: t)
    check(DSHaptic.ticks == 1,
          "four seams inside the gap are ONE motion, not four ticks — got \(DSHaptic.ticks)")
    // Dropped, never queued: waiting out the gap must not release a backlog.
    pastTheGap()
    check(DSHaptic.ticks == 1, "the dropped ticks are gone, not queued behind the gap")
    FeedSeam.observe(side: 1, in: t)
    check(DSHaptic.ticks == 2, "a crossing after the gap ticks again")
}

// --- a new drag starts clean ---------------------------------------------------
do {
    let t = fresh()
    FeedSeam.set(dragging: true)
    FeedSeam.observe(side: 1, in: t)
    FeedSeam.observe(side: -1, in: t)
    check(DSHaptic.ticks == 1, "the first drag ticked")
    FeedSeam.set(dragging: false)
    FeedSeam.set(dragging: true)
    FeedSeam.observe(side: 1, in: t)
    check(DSHaptic.ticks == 2,
          "a NEW drag's first seam is never swallowed by the last drag's gap — got \(DSHaptic.ticks)")
}

// --- the flag itself -----------------------------------------------------------
do {
    _ = fresh()
    check(!FeedSeam.dragging, "the hand is off the glass by default")
    FeedSeam.set(dragging: true)
    check(FeedSeam.dragging, "the flag reads back")
    FeedSeam.set(dragging: false)
    check(!FeedSeam.dragging, "and clears")
}

if failures > 0 { print("✗ feed-seam-selftest: \(failures) failure(s)"); exit(1) }
SWIFT

swiftc -O -o "$TMP/run" "$SEAM" "$TMP/stub.swift" "$TMP/main.swift" 2>"$TMP/build.log" \
  || { cat "$TMP/build.log"; echo "✗ feed-seam-selftest did not compile"; exit 1; }
"$TMP/run"

# --- drift guard: the divider still observes ----------------------------------
# The whole feature is one `onGeometryChange` on one view. Nothing compiles
# differently if it goes, and nothing on screen changes.
grep -q 'FeedSeam.side(ofTop:' "$DIVIDER" \
  || { echo "✗ $DIVIDER no longer reads its own position — no seam is ever felt"; exit 1; }
grep -q 'FeedSeam.observe(side:' "$DIVIDER" \
  || { echo "✗ $DIVIDER no longer reports crossings — no seam is ever felt"; exit 1; }
grep -q 'frame(in: .scrollView)' "$DIVIDER" \
  || { echo "✗ the seam line is no longer the feed's own viewport — .global puts it under the status bar"; exit 1; }
# Held by `@State` so the identity survives a render; a fresh tracker per render
# is forever unplaced, so nothing ever crosses.
grep -q '@State private var tracker = FeedSeam.Tracker()' "$DIVIDER" \
  || { echo "✗ the tracker is not held across renders — every render re-places it and nothing crosses"; exit 1; }

# --- drift guard: the hand flag is written, and cleared ------------------------
grep -q 'FeedSeam.set(dragging: phase == .tracking || phase == .interacting)' "$CHROME" \
  || { echo "✗ the hand flag is not written from the scroll phase — every seam is silent"; exit 1; }
grep -q 'FeedSeam.set(dragging: false)' "$CHROME" \
  || { echo "✗ the hand flag is never cleared — a screen left mid-drag leaves it true"; exit 1; }

# --- drift guard: the feel is declared in BOTH grammars ------------------------
# `DSHaptic.seam()` bumps a counter; a counter with no `.sensoryFeedback`
# mapping is a call site that compiles, runs, and is never felt. The two
# grammars are the root shell's and a presentation's (see `SheetHaptics`).
grep -q 'var seam = 0' "$HAPTICS" \
  || { echo "✗ HapticBus has no seam counter"; exit 1; }
sink=$(awk '/func dsSensoryFeedback\(\)/,/^}/' "$HAPTICS")
echo "$sink" | grep -q 'HapticBus.shared.seam' \
  || { echo "✗ the seam has no mapping in dsSensoryFeedback — the counter bumps and nothing is felt"; exit 1; }
sheet=$(awk '/struct SheetHaptics/,/^}/' "$HAPTICS")
echo "$sheet" | grep -q 'HapticBus.shared.seam' \
  || { echo "✗ the seam has no mapping in SheetHaptics — silent under any presentation"; exit 1; }
# It is the lightest thing in the grammar, under the pour (which is at least an
# event). A seam louder than a deliberate act inverts what the feels mean.
intensity_of() {
  echo "$sink" | grep -B1 "trigger: HapticBus.shared.$1" \
    | grep -o 'intensity: 0\.[0-9]*' | head -1 | sed 's/intensity: //'
}
seam_i=$(intensity_of seam)
pour_i=$(intensity_of pour)
[[ -n "$seam_i" && -n "$pour_i" ]] \
  || { echo "✗ could not read the seam/pour intensities — the grammar's shape changed"; exit 1; }
awk -v s="$seam_i" -v p="$pour_i" 'BEGIN { exit !(s < p) }' \
  || { echo "✗ the seam ($seam_i) is not lighter than the pour ($pour_i) — a passive crossing may not outweigh an event"; exit 1; }

# --- drift guard: the floor's mark ---------------------------------------------
# `CasberiMarkShape` existed with ZERO callers for two months (prd §5's screen
# was cut and took its one call site with it). A guard here, because that is
# exactly how it went dead the first time.
grep -q 'CasberiMarkShape()' "$FLOOR" \
  || { echo "✗ the floor no longer draws the mark's outline — the draw-on is gone"; exit 1; }
grep -q 'struct CasberiMarkShape' "$MARK" \
  || { echo "✗ CasberiMarkShape is gone — the floor's draw-on cannot compile"; exit 1; }
grep -q 'CorpusFloor(oldest:' "$FEED" \
  || { echo "✗ the feed no longer draws the floor — prd §218's line went with it"; exit 1; }
# Both halves, or it is an outline octopus rather than the app's mark.
grep -q 'trim(from: 0, to: drawn ? 1 : 0)' "$FLOOR" \
  || { echo "✗ the outline no longer trims — it appears instead of drawing"; exit 1; }
grep -q 'CasberiMark(size:' "$FLOOR" \
  || { echo "✗ the drawing never settles into the real mark"; exit 1; }
# THE USE, NOT THE DECLARATION. Both of these first shipped as a grep for the
# identifier, and both survived a mutation that deleted the line doing the work
# while leaving the identifier sitting there (the `@Environment` property, the
# `.trim` modifier). A guard that a mutation walks through is not a guard.
arrive=$(awk '/private func arrive\(\)/,/^    }$/' "$FLOOR")
[[ -n "$arrive" ]] || { echo "✗ could not find CorpusFloor.arrive()"; exit 1; }
echo "$arrive" | grep -q 'guard !reduceMotion else { drawn = true; settled = true; return }' \
  || { echo "✗ the floor's draw-on ignores Reduce Motion — it performs where the person asked it not to"; exit 1; }
echo "$arrive" | grep -q 'withAnimation(.easeOut(duration: Self.draw)) { drawn = true }' \
  || { echo "✗ the outline is no longer ANIMATED on — the trim jumps to 1 and the mark appears"; exit 1; }
echo "$arrive" | grep -q 'withAnimation(.easeIn(duration: Self.settle)) { settled = true }' \
  || { echo "✗ the settle is no longer animated — the outline cuts to the solid mark"; exit 1; }

# THE OUTLINE MUST END AS THE MARK IT DRAWS (prd §866). `CasberiMarkShape` took
# the three-arm small cut for two months with no caller to notice; the floor
# draws at a rung where `CasberiMark` paints FIVE, so the settle grew two limbs.
# Derived from the two numbers rather than asserted as a string, so a change to
# either rung re-answers the question instead of going stale.
grep -q 'fileprivate static var silhouetteArms: \[Path\] { armsFull }' "$MARK" \
  || { echo "✗ the drawn-on outline is not the full-arm silhouette — it changes shape at the settle"; exit 1; }
cut_at=$(grep -o 'static let smallCutBelow: CGFloat = [0-9.]*' "$MARK" | grep -o '[0-9.]*$')
floor_rung=$(grep -o 'private static let size = DS.Mark.[a-z]*' "$FLOOR" | sed 's/.*DS.Mark.//')
floor_pt=$(grep -A1 "static let $floor_rung: CGFloat" Casberi/Casberi/Design/DesignTokens.swift \
  | grep -o "static let $floor_rung: CGFloat = [0-9.]*" | grep -o '[0-9.]*$')
[[ -n "$cut_at" && -n "$floor_pt" ]] \
  || { echo "✗ could not read smallCutBelow ($cut_at) or the floor's rung $floor_rung ($floor_pt)"; exit 1; }
awk -v f="$floor_pt" -v c="$cut_at" 'BEGIN { exit !(f >= c) }' \
  || { echo "✗ the floor draws at ${floor_pt}pt, under smallCutBelow (${cut_at}) — the solid mark takes the SMALL cut there, so the full-arm outline now loses two arms at the settle instead of gaining them"; exit 1; }
# §218's gate is what makes this honest at all: a floor on a young corpus reads
# as an empty-state apology, and now it would perform on the way.
floor=$(awk '/private func corpusFloorSection\(/,/^    }$/' "$FEED")
echo "$floor" | grep -q 'live.count >= 8' \
  || { echo "✗ the floor's row minimum is gone (prd §218) — it fires on a corpus with no history"; exit 1; }
echo "$floor" | grep -q '7 \* 86_400' \
  || { echo "✗ the floor's age minimum is gone (prd §218) — 'this is where it starts · today'"; exit 1; }
echo "$floor" | grep -q 'filter(\\.isLive)' \
  || { echo "✗ the floor reads capturedAt off a derived array without an isLive filter (the build-150 class)"; exit 1; }
# NOT OVER A `Show older` DOOR (prd §866a). The window draws 30 rows and a door
# to the rest, and this section renders below that door — so without the gate
# the feed claims a start date under a button holding the other 122 days, with
# the app's mark drawn over it. `olderRow`'s own doc already states the rule for
# `caughtUpFooter`; this is the same claim at the other end of the feed.
echo "$floor" | grep -q '!memo.windowHasMore' \
  || { echo "✗ the floor draws while 'Show older' is on screen — 'this is where it starts' over a door to the rest of the corpus (§83)"; exit 1; }

echo "✓ feed-seam-selftest passed"
