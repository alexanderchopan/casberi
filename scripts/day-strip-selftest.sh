#!/bin/zsh
# Casberi day-strip self-test — today's shape under Day's next thing (prd §1087):
#
#   Casberi/Casberi/Model/DayStrip.swift   (compiled whole)
#
# WHY A HARNESS. Every failure draws a calm strip. An overlap left in one lane
# hides a conflict behind a block; a free stretch that starts before now, or
# that ignores a meeting in progress, tells you to book time you don't have;
# an all-day event on the axis paints the whole day busy. Only a case-by-case
# statement says the strip is right.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

STRIP="Casberi/Casberi/Model/DayStrip.swift"
CARD="Casberi/Casberi/Screens/DayAheadCard.swift"
for f in "$STRIP" "$CARD"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
grep -q 'DayStrip.make(' Casberi/Casberi/Screens/FeedScreen+MergedRoom.swift \
  || { echo "✗ the Day room no longer builds its strip"; exit 1; }
grep -q 'predicateForEvents' "$CARD" \
  || { echo "✗ the strip no longer reads the calendar itself — the store keeps no ended event, so the morning would vanish"; exit 1; }
grep -q 'minHeight: DSRoomChassis.leadBox' "$CARD" \
  || { echo "✗ Box B no longer holds the lead's one height (prd §904)"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$STRIP" "$TMP/"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 5))!
func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3_600) }
func ev(_ id: String, _ s: Double, _ e: Double?, allDay: Bool = false) -> DayStrip.Event {
    .init(id: id, title: id, start: at(s), end: e.map(at), allDay: allDay)
}

// ── The axis ─────────────────────────────────────────────────────────
let quiet = DayStrip.make([ev("Standup", 9, 9.5)], now: at(8.5), calendar: cal)
check(quiet.from == at(8) && quiet.to == at(20), "8 to 8 by default")
let early = DayStrip.make([ev("Gym", 6.5, 7.5), ev("Late", 21.25, 22)], now: at(6), calendar: cal)
check(early.from == at(6), "an early event widens the axis to its whole hour")
check(early.to == at(22), "a late event widens it to the hour it ends in")
check(quiet.position(at(14)) == 0.5, "two o'clock is the middle of 8 to 8")

// ── Today only, and what takes no time ───────────────────────────────
let mixed = DayStrip.make([ev("Yesterday", -10, -9), ev("Tomorrow", 30, 31),
                           ev("Holiday", 0, 24, allDay: true), ev("Review", 14, 15)],
                          now: at(10), calendar: cal)
check(mixed.blocks.map(\.id) == ["Review"], "only today's timed events are blocks")
check(mixed.allDay == ["Holiday"], "an all-day event is named, never drawn across the day")
let booking = DayStrip.make([ev("Intro call", 15, nil)], now: at(10), calendar: cal)
check(booking.blocks.first?.end == at(15.5), "a booking with no end is drawn at half an hour")

// ── Lanes and overlaps ───────────────────────────────────────────────
let busy = DayStrip.make([ev("Lunch", 12.5, 13.5), ev("Review", 13, 13.75), ev("1:1", 16, 17)],
                         now: at(11), calendar: cal)
check(busy.blocks.first { $0.id == "Lunch" }?.lane == 0, "the first block takes the first lane")
check(busy.blocks.first { $0.id == "Review" }?.lane == 1, "an overlap takes the second lane")
check(busy.blocks.first { $0.id == "1:1" }?.lane == 0, "a later block returns to the first lane")
check(busy.blocks.filter(\.overlaps).map(\.id) == ["Lunch", "Review"], "both sides of an overlap are marked")
check(busy.overlap?.first == "Lunch" && busy.overlap?.second == "Review", "the sentence names the overlap")
let over = DayStrip.make([ev("Lunch", 12.5, 13.5), ev("Review", 13, 13.75)], now: at(14), calendar: cal)
check(over.overlap == nil, "an overlap that is over is not named")

// ── Free time ────────────────────────────────────────────────────────
check(busy.free?.from == at(11) && busy.free?.until == at(12.5), "free from now until the next event")
let inMeeting = DayStrip.make([ev("Workshop", 10, 12), ev("Call", 12.25, 13)], now: at(11), calendar: cal)
check(inMeeting.free?.from == at(13) && inMeeting.free?.until == nil, "a meeting in progress and a gap under half an hour are not free")
let tight = DayStrip.make([ev("A", 9, 10), ev("B", 10.25, 19.9)], now: at(9.5), calendar: cal)
check(tight.free == nil, "no free stretch when nothing of half an hour is left")
let evening = DayStrip.make([ev("A", 9, 10)], now: at(21), calendar: cal)
check(evening.free == nil, "nothing is free once the axis has ended")
let morning = DayStrip.make([ev("A", 9, 10)], now: at(6), calendar: cal)
check(morning.free?.from == at(8), "free time starts at the axis, not before it")

check(DayStrip.make([], now: at(10), calendar: cal).isEmpty, "a day with nothing is empty")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
print("✓ day strip: the axis, today only, lanes, overlaps, free time")
SWIFT
swiftc -O -o "$TMP/run" "$TMP/DayStrip.swift" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
"$TMP/run"
