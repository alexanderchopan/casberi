#!/bin/zsh
# Casberi row-window self-test — the bound that keeps a long list from costing
# a sheet drag ten seconds of wall clock (prd §657, build 539's watchdog):
#
#   Casberi/Casberi/Model/RowWindow.swift
#   Casberi/Casberi/Screens/PersonRoomScreen.swift
#
# WHY A HARNESS AND NOT A LIVE CHECK. Nothing on this machine can produce the
# input. The failure needs a corpus with thousands of rows about ONE person (an
# X archive), a finger on a sheet, and a BACKGROUNDED app running at ~16% of a
# core — the six-fold throttle that turns a second and a half of render into a
# ten-second wall-clock kill. The build is clean, every static audit passed on
# the crashing binary, and no simulator backgrounds an app under a CPU quota.
# What can be proven here is the arithmetic and the wiring:
#
#   · the slice never hands out more than the budget
#   · the opener is drawn when and only when rows were held back (§83: a
#     control that reveals nothing is a dead control)
#   · a step opens exactly one more screenful, and the growth stays linear
#   · the person room draws THROUGH the window, not around it
#
# `RowWindow.swift` is Foundation-only by design and is compiled WHOLE AND
# UNMODIFIED below — the strongest form of "the harness ran the shipped logic".
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

WINDOW="Casberi/Casberi/Model/RowWindow.swift"
ROOM="Casberi/Casberi/Screens/PersonRoomScreen.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
ACCOUNT="Casberi/Casberi/Screens/AccountPage.swift"
for f in "$WINDOW" "$ROOM" "$FEED" "$ACCOUNT"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# The arithmetic below is worthless if the room draws around it. These read the
# WIRING, which no compiled function can prove about itself.
#
# A NEGATIVE sweep reads a COMMENT-STRIPPED copy, and that is not a nicety
# — this repo has paid for it twice (`category-fold-selftest.sh`'s "the
# Obsidian/Cursor lesson, third time"; `ondevice-selftest.sh` "earned again
# here on this guard's first run"). Both files below document §657 by NAMING
# the shape they must no longer have, so a guard grepping raw source fires on
# the prose explaining it. The positive greps read the raw file on purpose: a
# rule spelled only in a comment is not wiring.
STRIPPED=$(mktemp)
trap 'rm -f "$STRIPPED"' EXIT
sed -E 's://.*$::' "$ROOM" > "$STRIPPED"

grep -q 'RowWindow.slice(mergedRows.live, steps: windowSteps)' "$ROOM" \
  || { echo "✗ the person room no longer slices its rows through RowWindow — the list is unbounded again (prd §657)"; exit 1; }
grep -q 'ForEach(window.shown.keyed)' "$ROOM" \
  || { echo "✗ the person room's ForEach no longer draws the window's own rows"; exit 1; }
grep -q 'ForEach(merged' "$STRIPPED" \
  && { echo "✗ the person room draws the unwindowed array again — this is build 539's own line"; exit 1; }
# The merge is MEMOISED. Sorting is n log n stored-property reads on live
# models, and a sheet drag evaluates the body per offset change — so a body
# that calls `merged` itself leaves that term growing with the corpus on the
# very path the window was added to bound.
grep -q '@State private var mergedRows' "$ROOM" \
  || { echo "✗ the merged room is no longer memoised — the sort would run on every body pass, per drag frame"; exit 1; }
grep -qE '(let|var) window = RowWindow.slice\(merged,' "$STRIPPED" \
  && { echo "✗ the body merges and sorts for itself again — memoise into mergedRows"; exit 1; }
# The opener must be a TAP. `.onAppear` growth is a runaway (the feed's
# `olderRow` carries the measurement: 12% → 60% of main-thread samples).
grep -q 'windowSteps += 1' "$ROOM" \
  || { echo "✗ nothing opens the window — the rows past the first screenful are unreachable"; exit 1; }
grep -q 'onAppear.*windowSteps' "$STRIPPED" \
  && { echo "✗ the window grows on appearance — that feeds its own trigger and costs more than it saves"; exit 1; }
# The opener fires a haptic, and a sheet covers the shell's listener. The
# `.person` route mounts one; without it the tap is silent on the room's own
# primary door (`/code-review` finding, 2026-09-08).
grep -q 'DSHapticSink()' "$FEED" \
  || { echo "✗ the person-room sheet no longer mounts a haptic listener — Show older's tap would be silent"; exit 1; }

# --- the account-page chassis (prd §710) ------------------------------------
# The SECOND surface of build 539's class, and the one that reaches 55 screens
# at once: every account page is a `List` inside `MainSurface`'s one
# `.sheet(item: $route.connectForm)`, so a finger can drag it, and the roster
# was unbounded. RSS's roster is the one an OPML export fills in a single tap
# (hundreds of rows), which is how it was reported; the chassis's own doc
# already anticipated "a hundred and forty accounts".
#
# Read on a COMMENT-STRIPPED copy for the negative, same as the room above —
# this file now documents §710 by naming the shape it must not have.
ASTRIPPED=$(mktemp)
sed -E 's://.*$::' "$ACCOUNT" > "$ASTRIPPED"
trap 'rm -f "$STRIPPED" "$ASTRIPPED"' EXIT

grep -q 'RowWindow.slice(active + quiet, steps: windowSteps)' "$ACCOUNT" \
  || { echo "✗ the account page no longer slices its roster through RowWindow — all 55 pages are unbounded inside a draggable sheet again (prd §710)"; exit 1; }
grep -q 'ForEach(drawnActive)' "$ACCOUNT" \
  || { echo "✗ the account page's active half no longer draws the window's own rows"; exit 1; }
grep -q 'ForEach(drawnQuiet)' "$ACCOUNT" \
  || { echo "✗ the account page's quiet half no longer draws the window's own rows"; exit 1; }
grep -qE 'ForEach\((active|quiet|shown)\)' "$ASTRIPPED" \
  && { echo "✗ the account page draws an unwindowed roster half again — that is the line §710 removed"; exit 1; }
# The window is drawn in DRAW ORDER and split back, never sliced per half: two
# budgets draw two screenfuls, and slicing only the quiet half leaves a seat
# with 300 active rows (RSS after an OPML import) exactly as unbounded.
grep -qE 'RowWindow.slice\((active|quiet),' "$ASTRIPPED" \
  && { echo "✗ the account page slices a roster half against its own budget — window the draw order once, then split it back"; exit 1; }
grep -q 'windowSteps += 1' "$ACCOUNT" \
  || { echo "✗ nothing opens the account page's roster — the rows past the first screenful are unreachable"; exit 1; }
grep -q 'onAppear.*windowSteps' "$ASTRIPPED" \
  && { echo "✗ the account page's window grows on appearance — that feeds its own trigger (the feed's olderRow measurement)"; exit 1; }
# The header counts are TOTALS. A count that shrank to the window would hide
# what was held back, on the one row a person reads to learn how many they follow.
grep -qF 'AccountPageShape.watchingLabel(rows.filter(\.watched).count)' "$ACCOUNT" \
  || { echo "✗ Watching · N no longer counts the whole roster — a window's own count is not the fact that row states (§83)"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f "$STRIPPED" "$ASTRIPPED"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

let thousand = Array(0..<1000)

// 1. The bound holds, and it is the bound the doc claims.
let first = RowWindow.slice(thousand, steps: 0)
check("a fresh window draws one screenful of a 1,000-row list",
      first.shown.count == RowWindow.rowTarget)
check("and says there is more behind it", first.more)
check("the rows it draws are the NEWEST ones, in order",
      first.shown == Array(thousand.prefix(RowWindow.rowTarget)))

// 2. Growth is linear, one screenful per step — never geometric.
let budgets = (0..<5).map { RowWindow.budget(steps: $0) }
check("each step opens exactly one more screenful",
      budgets == [30, 60, 90, 120, 150])
check("a step really draws what its budget promises",
      RowWindow.slice(thousand, steps: 3).shown.count == 120)

// 3. The opener is drawn when and only when something was held back (§83).
check("a short list draws every row", RowWindow.slice([1, 2, 3], steps: 0).shown.count == 3)
check("…and offers no opener", !RowWindow.slice([1, 2, 3], steps: 0).more)
let exact = Array(0..<RowWindow.rowTarget)
check("a list that exactly fills the budget offers no opener — nothing is behind it",
      RowWindow.slice(exact, steps: 0).shown.count == RowWindow.rowTarget
        && !RowWindow.slice(exact, steps: 0).more)
check("one row past the budget does offer one",
      RowWindow.slice(Array(0..<(RowWindow.rowTarget + 1)), steps: 0).more)
check("an empty list draws nothing and offers nothing",
      RowWindow.slice([Int](), steps: 0).shown.isEmpty
        && !RowWindow.slice([Int](), steps: 0).more)

// 4. The window is a CAP, so a wide window over a narrow slice is still whole.
//    This is what makes it safe for `windowSteps` to stay monotonic across a
//    filter change in the person room.
let narrow = Array(0..<40)
check("a window opened wide still draws a short slice whole",
      RowWindow.slice(narrow, steps: 9).shown.count == 40)
check("…and says so", !RowWindow.slice(narrow, steps: 9).more)

// 5. A nonsense step cannot produce a nonsense budget.
check("a negative step floors at one screenful", RowWindow.budget(steps: -5) == RowWindow.rowTarget)

// 6. The cost this exists to bound. The shipped failure is O(rows × sections)
//    inside ONE synchronous list update; what the window guarantees is that the
//    row term is a constant no corpus can grow.
let huge = RowWindow.slice(Array(0..<250_000), steps: 0)
check("a quarter-million-row room still draws one screenful",
      huge.shown.count == RowWindow.rowTarget)

if failures > 0 { print("\n✗ \(failures) row-window check(s) failed"); exit(1) }
print("\n✓ row window: bound, growth, opener and wiring all hold")
SWIFT

xcrun swiftc -O -o "$TMP/rowwindow" "$WINDOW" "$TMP/main.swift" 2>&1 | grep -v '^ *$' || true
[[ -x "$TMP/rowwindow" ]] || { echo "✗ the harness did not compile — RowWindow.swift is no longer Foundation-only"; exit 1; }
"$TMP/rowwindow"
