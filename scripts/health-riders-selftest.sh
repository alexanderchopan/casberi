#!/bin/zsh
# Casberi health-riders self-test — the SHIPPED rules behind the Apple Health
# seats and the activity dedupe (2026-09-06):
#
#   Casberi/Casberi/Model/HealthRiders.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic". The
# half that touches HealthKit and `Thing` lives in `HealthIngest.swift`, which
# no harness here can compile and which carries no judgement of its own: it
# maps `HKWorkout` onto `ActivityRecord` and does what this file decides.
#
# WHY A HARNESS AND NOT A LIVE CHECK. Nothing on this machine can produce the
# input. HealthKit ships no data on the simulator, a Garmin- or Strava-written
# workout cannot be seeded there, and the failure that matters most needs TWO
# apps to have written the same ride — a state that only exists on a real
# phone belonging to somebody who owns a Garmin watch. Every failure mode here
# is a SILENT WRONG ANSWER that renders perfectly:
#
#   · the same ride listed twice, once per seat, doubling the training year
#   · two activities somebody really did collapsed into one and one deleted
#   · Strava's COPY of a ride surviving over the watch record it came from
#   · a connected seat's ride dropped entirely because the record that won
#     was one that seat is not allowed to land
#   · a winner that changes between passes, so a row moves rooms on a sweep
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

RIDERS="Casberi/Casberi/Model/HealthRiders.swift"
INGEST="Casberi/Casberi/Model/HealthIngest.swift"
CONNECT="Casberi/Casberi/Model/BridgeConnect.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
for f in "$RIDERS" "$INGEST" "$CONNECT" "$REFRESH" "$CATALOG"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled functions cannot prove about themselves. A perfect
# `winner` is worthless if the ingest never calls it.
grep -q 'HealthRiders.activityGroups' "$INGEST" \
  || { echo "✗ HealthIngest no longer groups by activity — the same ride would land once per seat again"; exit 1; }
grep -q 'HealthRiders.winner' "$INGEST" \
  || { echo "✗ HealthIngest no longer picks a winner per activity"; exit 1; }
grep -q 'HealthRiders.source(forWriter:' "$INGEST" \
  || { echo "✗ HealthIngest no longer attributes through the shipped rule"; exit 1; }
# The claim is one-directional. Without this guard a DISCONNECTED rider's rows
# would be rewritten back to Apple Health, silently editing landed history.
grep -q 'landed.source == "Apple Health"' "$INGEST" \
  || { echo "✗ the rider claim is no longer one-directional — disconnecting a seat could rewrite its landed rows"; exit 1; }
# Corollaries 4 and 5 of the SwiftData liveness class: the fetched rows are
# filtered at the boundary and re-checked before every stored-property read.
grep -q ')) ?? \[\]).live' "$INGEST" \
  || { echo "✗ the landed-rows fetch no longer filters .live at the boundary (liveness corollary 4)"; exit 1; }
grep -q 'landed.isLive' "$INGEST" \
  || { echo "✗ a claimed row is read without an isLive guard (liveness corollary 5)"; exit 1; }
grep -q 'loser.isLive' "$INGEST" \
  || { echo "✗ a collapsed row is read without an isLive guard (liveness corollary 5)"; exit 1; }
# The claim only runs on a CONNECT. If a sweep started passing it, every
# foreground would pay for a full Health fetch it can never use.
grep -q 'claimExisting: true' "$CONNECT" \
  || { echo "✗ a rider's connect no longer claims the rows Apple Health already landed — the second seat is dead on arrival"; exit 1; }
grep -q 'claimExisting' "$REFRESH" \
  && { echo "✗ the foreground sweep now passes claimExisting — it would fetch the whole Health corpus every activation"; exit 1; }
grep -q 'Offer(name: "Garmin"' "$CATALOG" \
  || { echo "✗ the Garmin offer is gone from the catalog, but its rider row is still here"; exit 1; }
# Both rider seats are HealthKit-backed, so neither can exist on Mac Catalyst.
grep -A2 'Offer(name: "Garmin"' "$CATALOG" | grep -q 'unavailableOnMac: true' \
  || { echo "✗ the Garmin offer no longer declares unavailableOnMac — a Mac would show a Connect that can only fail"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

let t0 = Date(timeIntervalSince1970: 1_780_000_000)

struct Rec: ActivityRecord {
    var activityStart: Date
    var activityDuration: TimeInterval
    var writerName: String
    var activityID: String
}
func rec(_ id: String, _ writer: String, start: TimeInterval = 0,
         minutes: Double = 60) -> Rec {
    Rec(activityStart: t0.addingTimeInterval(start),
        activityDuration: minutes * 60, writerName: writer, activityID: id)
}

let garmin = "Garmin Connect"
let strava = "Strava"
let watch  = "Apple Watch"

print("Who measured it")
// The ranking is a fact about the APPS, so it never reads the connected set.
check("Garmin Connect outranks the Apple Watch bucket",
      HealthRiders.writerRank(garmin) > HealthRiders.writerRank(watch))
// The half that was said aloud in the wrong order once. Strava's row is a copy
// of the recording it displaced, so it can never outrank a recorder.
check("the Apple Watch bucket outranks Strava",
      HealthRiders.writerRank(watch) > HealthRiders.writerRank(strava))
check("Garmin Connect outranks Strava",
      HealthRiders.writerRank(garmin) > HealthRiders.writerRank(strava))
check("an app nobody has an opinion about ranks as a recorder",
      HealthRiders.writerRank("Nike Run Club") == HealthRiders.recorderRank)
check("the writer match is case-insensitive",
      HealthRiders.writerRank("GARMIN CONNECT") == HealthRiders.writerRank(garmin))

print("")
print("Which seat it lands under")
check("a connected rider claims its own writer",
      HealthRiders.source(forWriter: garmin, connected: ["Garmin"]) == "Garmin")
check("an unconnected rider's writer falls to Apple Health",
      HealthRiders.source(forWriter: garmin, connected: []) == "Apple Health")
check("one rider does not claim another's writer",
      HealthRiders.source(forWriter: garmin, connected: ["Strava"]) == "Apple Health")
check("an unknown writer is Apple Health's",
      HealthRiders.source(forWriter: watch, connected: ["Garmin", "Strava"]) == "Apple Health")

print("")
print("One activity, one group")
// The case this whole file exists for: a Garmin watch's ride reaches HealthKit
// twice, because Garmin Connect auto-uploads to Strava and Strava writes its
// own copy minutes later under a fresh UUID.
check("one ride written by two apps is one group",
      HealthRiders.activityGroups([rec("a", garmin), rec("b", strava, start: 45)]).count == 1)
check("clock skew inside the window still groups",
      HealthRiders.activityGroups([rec("a", garmin),
                                   rec("b", strava, start: 110, minutes: 60.5)]).count == 1)
// The safety rail. Two records from the SAME app are two activities somebody
// really did — never two copies of one — so they must never collapse.
check("the same app's two records never group",
      HealthRiders.activityGroups([rec("a", garmin), rec("b", garmin)]).count == 2)
check("starts further apart than the window do not group",
      HealthRiders.activityGroups([rec("a", garmin), rec("b", strava, start: 180)]).count == 2)
check("same start but different lengths do not group",
      HealthRiders.activityGroups([rec("a", garmin), rec("b", strava, minutes: 90)]).count == 2)
check("three apps' copies of one ride are one group",
      HealthRiders.activityGroups([rec("a", garmin), rec("b", strava, start: 30),
                                   rec("c", watch, start: 60)]).count == 1)
// The query returns newest-first; a grouping that depended on arrival order
// would put a row in a different room depending on when the sweep ran.
check("grouping does not depend on input order",
      HealthRiders.activityGroups([rec("b", strava, start: 45), rec("a", garmin)]).count == 1)
check("nothing in, nothing out", HealthRiders.activityGroups([Rec]()).isEmpty)

print("")
print("Which record survives")
let bothSeats: Set<String> = ["Garmin", "Strava"]
func win(_ group: [Rec], _ connected: Set<String>, healthOn: Bool = true) -> String? {
    HealthRiders.winner(of: group, connected: connected, healthOn: healthOn)?.activityID
}
check("the watch's own record beats the copy Strava made",
      win([rec("g", garmin), rec("s", strava)], bothSeats) == "g")
check("an Apple Watch ride is not handed to Strava",
      win([rec("w", watch), rec("s", strava)], ["Strava"]) == "w")
// With Health off, an Apple-Health-attributed record may not land at all — so
// letting it win would drop the ride the connected seat is entitled to.
check("with Health off, the record that CAN land wins",
      win([rec("w", watch), rec("s", strava)], ["Strava"], healthOn: false) == "s")
check("with Health off and no rider connected, nothing wins",
      win([rec("w", watch), rec("s", strava)], [], healthOn: false) == nil)
check("with Health on, a ride still lands when no rider is connected",
      win([rec("g", garmin), rec("s", strava)], []) == "g")
// Rank is about the apps, so an unconnected Garmin still beats Strava — the
// ride lands under Apple Health rather than as Strava's copy.
check("an unconnected recorder still outranks a connected mirror",
      win([rec("g", garmin), rec("s", strava)], ["Strava"]) == "g")
check("an empty group has no winner", win([], bothSeats) == nil)
// Two recorders with no ranking between them: the tiebreak exists so the same
// group resolves the same way on every pass, in any arrival order.
check("a tie between recorders is deterministic",
      win([rec("aaa", watch), rec("bbb", "Nike Run Club")], []) == "aaa")
check("…and does not depend on input order",
      win([rec("bbb", "Nike Run Club"), rec("aaa", watch)], []) == "aaa")

print("")
if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("all assertions pass")
SWIFT

build() { swiftc -Onone -o "$TMP/hr-selftest" "$1" "$TMP/main.swift" 2>"$TMP/build.log"; }

if ! build "$RIDERS"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/hr-selftest"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation below is a plausible
# "simplification" of the shipped logic, and each must break at least one
# assertion above.
echo ""
echo "Mutations (each must break something)"

mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut-riders.swift"
  cp "$RIDERS" "$target"
  # Literal, via argv — NOT interpolated into a regex (the room-heads lesson).
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$target" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# The half that was got wrong once out loud: Strava promoted over the recorders.
mutate "Strava is ranked as a recorder" \
  '("Strava", "strava", 0),' \
  '("Strava", "strava", 2),'
# The safety rail. Without it, one app's fumbled start/stop collapses into one
# row and the other is deleted.
mutate "the different-writers rail is dropped" \
  '               !groups[i].contains(where: { $0.writerName == record.writerName }) {' \
  '               true {'
# A window wide enough to swallow two genuinely different activities.
mutate "the window widens to ten minutes" \
  'static let sameActivityWindow: TimeInterval = 120' \
  'static let sameActivityWindow: TimeInterval = 600'
# Duration ignored: two different rides that merely started together collapse.
mutate "duration stops being compared" \
  '               abs(record.activityDuration - head.activityDuration) <= sameActivityWindow,' \
  '               true,'
# The whole reason `winner` takes healthOn: a record that cannot land must not
# be allowed to win, or the connected seat's ride is dropped silently.
mutate "a record that cannot land is allowed to win" \
  '            .filter { healthOn || rider(forWriter: $0.writerName, connected: connected) != nil }' \
  '            .filter { _ in true }'
# A winner that flips between passes moves a row from one room to another.
mutate "the tie-break runs the other way" \
  'return ra == rb ? a.activityID < b.activityID : ra > rb' \
  'return ra == rb ? a.activityID > b.activityID : ra > rb'
# Ranking read off the connected set instead of the apps: two phones with the
# same data would resolve the same ride differently.
mutate "an unknown writer ranks below everything" \
  '            ?? recorderRank' \
  '            ?? 0'

echo ""
echo "health-riders-selftest: OK — assertions pass and every mutation is caught."
