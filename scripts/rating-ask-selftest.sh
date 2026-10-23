#!/bin/zsh
# The rating ask's rule (prd §1477): Apple's sheet is asked for only by
# someone using the app on their own things, on enough different days, once
# per version. A rule that counted the demo, asked a phone with nothing
# connected, or asked every launch would put Apple's sheet in front of
# exactly the people it should not, and nothing on screen would say so.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/RatingAsk.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias R = RatingAsk

// Recording a day.
check(R.recording("2026-10-20", to: [], connected: 1, demo: false) == ["2026-10-20"], "a day of real use is recorded")
check(R.recording("2026-10-20", to: [], connected: 1, demo: true).isEmpty, "a day in the demo is not")
check(R.recording("2026-10-20", to: [], connected: 0, demo: false).isEmpty, "a day with nothing connected is not")
check(R.recording("2026-10-20", to: ["2026-10-20"], connected: 1, demo: false) == ["2026-10-20"], "the same day counts once")
let many = (1...20).map { String(format: "2026-10-%02d", $0) }
check(R.recording("2026-10-21", to: many, connected: 1, demo: false).count == R.dayCap, "the days are capped, not a log")
check(R.recording("2026-10-21", to: many, connected: 1, demo: false).last == "2026-10-21", "the newest day is kept")

// The rule.
let four = ["2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23"]
check(R.shouldAsk(days: four, connected: 2, demo: false, askedVersion: nil, version: "3.0.8"), "four days of real use ask")
check(!R.shouldAsk(days: Array(four.prefix(3)), connected: 2, demo: false, askedVersion: nil, version: "3.0.8"), "three days do not")
check(!R.shouldAsk(days: four, connected: 2, demo: true, askedVersion: nil, version: "3.0.8"), "the demo never asks")
check(!R.shouldAsk(days: four, connected: 0, demo: false, askedVersion: nil, version: "3.0.8"), "nothing connected never asks")
check(!R.shouldAsk(days: four, connected: 2, demo: false, askedVersion: "3.0.8", version: "3.0.8"), "a version asks once")
check(R.shouldAsk(days: four, connected: 2, demo: false, askedVersion: "3.0.7", version: "3.0.8"), "a new version may ask again")
check(!R.shouldAsk(days: four, connected: 2, demo: false, askedVersion: nil, version: ""), "no version, no ask")

// The day key.
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
check(R.dayKey(Date(timeIntervalSince1970: 1_792_670_400), calendar: cal) == "2026-10-22", "the day key is the calendar day")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   real use only, enough days, once per version")
SWIFT

xcrun swiftc -O "$SRC" "$work/main.swift" -o "$work/t" 2>&1 | grep -v "^$" || true
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  xcrun swiftc -O "$work/m.swift" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "the demo records days"        's/guard !demo, connected > 0, !days\.contains\(day\)/guard connected > 0, !days.contains(day)/'
mutate "the demo asks"                's/guard !demo, connected > 0, !version\.isEmpty/guard connected > 0, !version.isEmpty/'
mutate "nothing connected asks"       's/guard !demo, connected > 0, !version\.isEmpty, askedVersion/guard !demo, !version.isEmpty, askedVersion/'
mutate "a version asks every launch"  's/, askedVersion != version else/ else/'
mutate "the first day asks"           's/static let daysNeeded = 4/static let daysNeeded = 1/'
