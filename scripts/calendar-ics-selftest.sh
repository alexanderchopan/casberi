#!/bin/zsh
# Subscribed calendars (prd §1137), the parser compiled AS SHIPPED.
#
# `Model/CalendarICS.swift` is Foundation-only and compiles WHOLE. A wrong
# parse is a wrong date in Coming up, and a wrong date looks exactly like a
# right one:
#
#   • a folded line (RFC 5545 §3.1) read as two, so a long title is cut
#   • a day-long event (VALUE=DATE) read as midnight UTC, a day early west of it
#   • a TZID ignored, so a 19:00 kick-off in London shows at 19:00 here
#   • a cancelled event listed
#   • a yearly holiday from 2015 never reaching this year, or spinning
#   • a weekly BYDAY rule yielding one day a week instead of each named day
#   • a rule it cannot read guessed at, instead of its first occurrence only
#   • an EXDATE ignored
#   • an escaped comma or newline left as `\,` / `\n`
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/CalendarICS.swift"
[[ -f "$SRC" ]] || { print -u2 "✗ $SRC not found"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("  FAIL \(what)") }
}
NSTimeZone.default = TimeZone(identifier: "America/New_York")!
var ny = Calendar(identifier: .gregorian)
ny.timeZone = TimeZone(identifier: "America/New_York")!
func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, zone: String = "America/New_York") -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
}
let from = at(2026, 10, 6)
let until = at(2027, 1, 6)

let text = """
BEGIN:VCALENDAR\r
VERSION:2.0\r
X-WR-CALNAME:Arsenal fixtures\r
BEGIN:VEVENT\r
UID:match-1\r
DTSTART;TZID=Europe/London:20261010T190000\r
DTEND;TZID=Europe/London:20261010T210000\r
SUMMARY:Arsenal v Chelsea\\, Premier\r
  League\r
LOCATION:Emirates Stadium\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:day-1\r
DTSTART;VALUE=DATE:20261012\r
DTEND;VALUE=DATE:20261013\r
SUMMARY:Columbus Day\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:gone\r
DTSTART:20261011T120000Z\r
STATUS:CANCELLED\r
SUMMARY:Called off\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:xmas\r
DTSTART;VALUE=DATE:20151225\r
RRULE:FREQ=YEARLY\r
SUMMARY:Christmas\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:standup\r
DTSTART;TZID=America/New_York:20261005T093000\r
DTEND;TZID=America/New_York:20261005T094500\r
RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6\r
EXDATE;TZID=America/New_York:20261007T093000\r
SUMMARY:Stand-up\\nteam\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:odd\r
DTSTART:20261020T150000Z\r
RRULE:FREQ=MONTHLY;BYMONTHDAY=20,21\r
SUMMARY:Odd rule\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:old\r
DTSTART:20250101T120000Z\r
SUMMARY:Last year\r
END:VEVENT\r
END:VCALENDAR\r
"""

let cal = CalendarICS.parse(text, from: from, until: until)
let byTitle = Dictionary(grouping: cal.events, by: \.title)
check(cal.name == "Arsenal fixtures", "the calendar's name is X-WR-CALNAME")
check(byTitle["Arsenal v Chelsea, Premier League"] != nil, "a folded line joins and an escaped comma unescapes")
check(byTitle["Arsenal v Chelsea, Premier League"]?.first?.start == at(2026, 10, 10, 19, zone: "Europe/London"),
      "a TZID start is that zone's time")
check(byTitle["Arsenal v Chelsea, Premier League"]?.first?.location == "Emirates Stadium", "the location is kept")
let day = byTitle["Columbus Day"]?.first
check(day?.allDay == true && day?.start == at(2026, 10, 12), "a VALUE=DATE event is a local day, all day")
check(byTitle["Called off"] == nil, "a cancelled event is dropped")
check(byTitle["Last year"] == nil, "an event before the window is dropped")
check(byTitle["Christmas"]?.map(\.start) == [at(2026, 12, 25)], "a yearly rule from 2015 reaches this year, once")
let stand = (byTitle["Stand-up\nteam"] ?? []).map(\.start)
check(stand == [at(2026, 10, 12, 9, 30), at(2026, 10, 14, 9, 30), at(2026, 10, 19, 9, 30), at(2026, 10, 21, 9, 30)],
      "a weekly BYDAY rule names each day, honours COUNT and EXDATE, and drops what ended before the window")
check(byTitle["Odd rule"]?.map(\.start) == [at(2026, 10, 20, 15, zone: "UTC")], "a rule it cannot read yields the first occurrence only")
check(Set(cal.events.map(\.id)).count == cal.events.count, "every occurrence has its own id")
check(cal.events.map(\.start) == cal.events.map(\.start).sorted(), "soonest first")
check(CalendarICS.parse(text, from: from, until: until, limit: 2).events.count == 2, "the limit holds")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   names, folding, zones, all-day, cancelled, repeats, EXDATE, unknown rules")
SWIFT

build() { swiftc -Onone -o "$work/run" "$1" "$work/main.swift" 2>"$work/err" || return 1 }

cp "$SRC" "$work/CalendarICS.swift"
build "$work/CalendarICS.swift" || { cat "$work/err"; fail "the shipped source does not compile"; }
TZ=America/New_York "$work/run" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  build "$work/m.swift" || { cat "$work/err"; fail "mutation does not compile: $why"; }
  if TZ=America/New_York "$work/run" >/dev/null 2>&1; then
    fail "mutation SURVIVED — $why"
  fi
  echo "  ok   catches  $why"
}

mutate "folded lines read as their own" 's/out\[out\.count - 1\] \+= String\(line\.dropFirst\(\)\)/out.append(String(line.dropFirst()))/'
mutate "a TZID ignored" 's/cal\.timeZone = zone/_ = zone/'
mutate "a cancelled event kept" 's/== "CANCELLED" \{ return \[\] \}/== "CANCELLED-NEVER" { return [] }/'
mutate "EXDATE ignored" 's/guard !excluded\.contains\(s\) else \{ return nil \}//'
mutate "BYDAY reduced to the start's weekday" 's/candidates = days\.compactMap/_ = days.compactMap/'
mutate "an unknown rule expanded as if understood" 's/Set\(parts\.keys\)\.isSubset\(of: understood\),/true,/'
mutate "an escaped comma left escaped" 's/escaping = true/out.append(c)/'
echo "✓ calendar ICS self-test"
