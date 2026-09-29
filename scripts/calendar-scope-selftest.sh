#!/bin/zsh
# Casberi calendar-scope self-test — the Calendar room's tiles and month grid
# (prd §994):
#
#   Casberi/Casberi/Model/CalendarScope.swift
#   Casberi/Casberi/Model/ScheduleIngest.swift
#   Casberi/Casberi/Screens/FeedScreen.swift
#
# What it proves:
#
#   · the spans roll from today — Week is seven days, Month reaches the same
#     date next month, Today is one day — and nothing before today stands
#   · the grid is six weeks from the start of this one, today in the first
#     row, and every day of Month's span inside it
#   · the lit runs split at a week's edge, one run per row
#   · the busy days cover a multi-day event and not the midnight an all-day
#     event ends on
#   · the ingest fetches far enough for Month to be true (§83: a grid over a
#     week of data draws three empty weeks that are not empty)
#   · the room filters its list by the span and lights the grid from it
#
# `CalendarScope.swift` is Foundation-only by design and is compiled WHOLE AND
# UNMODIFIED below. Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SCOPE="Casberi/Casberi/Model/CalendarScope.swift"
INGEST="Casberi/Casberi/Model/ScheduleIngest.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
for f in "$SCOPE" "$INGEST" "$FEED"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards ------------------------------------------------------------
# The window: Month's longest span is 31 days from the start of today, and the
# fetch runs from `now`, so it must reach at least 32 days.
days=$(sed -nE 's/^ *static let forwardWindow: TimeInterval = ([0-9]+) \* 86_400.*/\1/p' "$INGEST")
[[ -n "$days" ]] || { echo "✗ ScheduleIngest.forwardWindow is no longer spelled 'N * 86_400' — this guard cannot read it"; exit 1; }
(( days >= 32 )) || { echo "✗ forwardWindow is $days days — Month (31 days) would draw days the ingest never fetched (prd §994)"; exit 1; }
grep -q 'recordBusyDays(events, window: start..<end)' "$INGEST" \
  || { echo "✗ the ingest no longer records every occurrence's day — the grid's dots would mark one day per series"; exit 1; }
grep -q 'span?.contains($0.capturedAt)' "$FEED" \
  || { echo "✗ the Calendar room no longer narrows its list to the picked span"; exit 1; }
grep -q 'CalendarMonthLead(scope: scope' "$FEED" \
  || { echo "✗ the Calendar room no longer draws the grid from the picked scope"; exit 1; }
grep -q 'let canOpen = !DS.isMac' "$FEED" \
  || { echo "✗ the New tile's gate moved — on the Mac nothing answers calshow: (Verbs' 2026-08-14 gate)"; exit 1; }
grep -qE 'case +all\b' "$SCOPE" \
  && { echo "✗ CalendarScope grew an All — Month is everything the room holds (user, prd §994)"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("✓ \(what)") } else { print("✗ \(what)"); failures += 1 }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
cal.firstWeekday = 1
func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

// Tuesday 29 September 2026, mid-afternoon.
let now = date(2026, 9, 29, 15)
let today = date(2026, 9, 29)

// Spans.
let t = CalendarScope.today.span(now: now, calendar: cal)!
check(t.lowerBound == today && t.upperBound == date(2026, 9, 30), "Today is the one day")
let w = CalendarScope.week.span(now: now, calendar: cal)!
check(w.lowerBound == today && w.upperBound == date(2026, 10, 6), "Week is today and the six days after (rolls, not Sun–Sat)")
let m = CalendarScope.month.span(now: now, calendar: cal)!
check(m.upperBound == date(2026, 10, 29), "Month reaches the same date next month")
check(CalendarScope.new.span(now: now, calendar: cal) == nil, "New is a verb and spans nothing")
check(!CalendarScope.week.allows(date(2026, 9, 28, 9), now: now, calendar: cal), "Yesterday stands under no scope")
check(CalendarScope.today.allows(date(2026, 9, 29, 23), now: now, calendar: cal), "Tonight is today")
check(!CalendarScope.today.allows(date(2026, 9, 30, 0), now: now, calendar: cal), "Midnight is tomorrow")
check(CalendarScope.allCases.filter { !$0.isVerb }.count == 3, "Three spans and one verb")

// 31 January → 28 February: the longest month span from a month end stays
// inside the grid.
let jan31 = date(2027, 1, 31, 10)
let janDays = CalendarGrid.days(now: jan31, calendar: cal)
let janSpan = CalendarScope.month.span(now: jan31, calendar: cal)!
check(janDays.count == 42, "The grid is six weeks")
check(janDays.filter { janSpan.contains($0.date) }.count
      == cal.dateComponents([.day], from: janSpan.lowerBound, to: janSpan.upperBound).day!,
      "Every day of Month's span is on the grid, from a month's last day")

// Grid.
let days = CalendarGrid.days(now: now, calendar: cal)
check(days.first?.date == date(2026, 9, 27), "The grid starts on the week's first day (Sunday 27th)")
check(days.firstIndex { $0.isToday } == 2, "Today sits in the first row")
check(!days[0].reachable && !days[1].reachable, "The days before today are out of reach")
check(days.filter(\.reachable).count == 30, "Reachable is exactly Month's span (29 Sep – 28 Oct)")
check(CalendarGrid.title(days, calendar: cal).contains("–"), "A grid crossing a month names both")
let symbols = CalendarGrid.weekdaySymbols(calendar: cal)
check(symbols.count == 7 && symbols.first == "S", "Weekday letters start on the first weekday")
var monday = cal; monday.firstWeekday = 2
check(CalendarGrid.days(now: now, calendar: monday).first?.date == date(2026, 9, 28),
      "A Monday-first locale starts the grid on Monday")

// Runs.
let weekRuns = CalendarGrid.runs(days, span: w)
check(weekRuns[0] == 2...6 && weekRuns[1] == 0...1 && weekRuns.count == 2,
      "Week lights the rest of this row and the start of the next")
let todayRuns = CalendarGrid.runs(days, span: t)
check(todayRuns == [0: 2...2], "Today lights one cell")
check(CalendarGrid.runs(days, span: nil).isEmpty, "The verb lights nothing")

// Busy days.
let window = today..<date(2026, 11, 3)
let busy = CalendarBusyDays.days(of: [
    (start: date(2026, 10, 2), end: date(2026, 10, 3)),        // all-day, ends at midnight
    (start: date(2026, 10, 9, 18), end: date(2026, 10, 11, 10)), // a weekend away
    (start: date(2026, 9, 20), end: date(2026, 9, 21)),        // before the window
], within: window, calendar: cal)
check(busy.contains("2026-10-02") && !busy.contains("2026-10-03"),
      "An all-day event marks its day, not the midnight it ends on")
check(busy.isSuperset(of: ["2026-10-09", "2026-10-10", "2026-10-11"]), "A multi-day event marks every day it covers")
check(!busy.contains("2026-09-20"), "An event before the window marks nothing")
check(CalendarBusyDays.decode(CalendarBusyDays.encode(busy)) == busy, "The days survive the store")

if failures > 0 { print("\(failures) failed"); exit(1) }
print("calendar-scope self-test: all passed")
SWIFT

xcrun swiftc -O -o "$TMP/calscope" "$SCOPE" "$TMP/main.swift" 2>&1 | grep -v '^ *$' || true
[[ -x "$TMP/calscope" ]] || { echo "✗ the harness did not compile"; exit 1; }
"$TMP/calscope"
