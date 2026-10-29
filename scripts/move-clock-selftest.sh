#!/bin/zsh
# Move's stage clock (prd §1602): where a send's time went, from the tap to
# landing. A clock that drops a stage, double-counts one, or counts from the
# wrong instant sends the next speed pass at the wrong stage, and every number
# on the receipt still looks plausible.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/MoveClock.swift"
MOVE="Casberi/Casberi/Screens/MoveSentence.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
let t0 = Date(timeIntervalSince1970: 1_000_000)
func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

var c = MoveClock(at: t0)
c.enter(.faceID, at: at(2))
c.enter(.signer, at: at(3.5))
c.enter(.sending, at: at(40))
c.enter(.landing, at: at(41))
let spans = c.spans(until: at(45))
check(spans.map(\.mark) == [.preparing, .faceID, .signer, .sending, .landing], "every stage, in order")
check(spans.map(\.seconds) == [2, 1.5, 36.5, 1, 4], "each stage until the next")
check(c.total(until: at(45)) == 45, "the total runs from the tap")
check(c.words(until: at(45)) == "45s: preparing 2.0s, Face ID 1.5s, your Signer 37s, sending 1.0s, landing 4.0s", "the words")

var d = MoveClock(at: t0)
d.enter(.faceID, at: at(1))
d.enter(.faceID, at: at(2))
check(d.entries.count == 2, "the same stage twice is one stage")
d.enter(.preparing, at: at(3))
d.enter(.faceID, at: at(4))
check(d.spans(until: at(5)).map(\.seconds) == [2, 3], "a stage entered again adds up")

check(MoveClock.seconds(9.94) == "9.9s" && MoveClock.seconds(10.4) == "10s", "tenths under ten seconds, then whole")

// prd §1605: each stage's requests are the ones that began in it.
let trips = [MoveClock.Trip(start: at(0.1), seconds: 0.9), MoveClock.Trip(start: at(0.5), seconds: 1.4),
             MoveClock.Trip(start: at(40.2), seconds: 0.6)]
let counted = c.words(until: at(45), trips: trips, retries: [at(1.0)])
check(counted == "45s: preparing 2.0s (2 requests, slowest 1.4s, 1 retried), Face ID 1.5s, your Signer 37s, sending 1.0s (1 requests), landing 4.0s",
      "requests and retries counted in the stage they began in: \(counted)")
check(c.stage(at: at(3.6)) == .signer && c.stage(at: at(-1)) == .preparing, "the stage at a moment")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   every stage from the tap, in order, added up, in words")
SWIFT

xcrun swiftc -O "$SRC" "$work/main.swift" -o "$work/t" 2>&1 | grep -v "^$" || true
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" || fail "assertions failed against the shipped source"

# The clock is wired: started at the tap, stepped by every stage, read on the
# receipt in a pre-release build only.
grep -qF 'clock = MoveClock()' "$MOVE" || fail "the clock does not start at the tap"
grep -qF 'clock?.enter(Self.clockMark(s))' "$MOVE" || fail "the clock does not follow the stages"
grep -qF 'if BuildChannel.isPreRelease, outcome != nil {' "$MOVE" || fail "the receipt's timing is not pre-release only"
grep -qF 'IngestSupport.$tripLog.withValue(tripLog)' "$MOVE" || fail "the send's requests are not counted (prd §1605)"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  xcrun swiftc -O "$work/m.swift" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "the last stage runs to nothing"   's/entries\[i \+ 1\]\.at : end/entries[i + 1].at : e.at/'
mutate "a repeated stage is counted anew" 's/guard entries\.last\?\.mark != mark else \{ return \}//'
mutate "a re-entered stage overwrites"    's/out\[j\]\.seconds \+= seconds/out[j].seconds = seconds/'
mutate "the total starts at the last stage" 's/end\.timeIntervalSince\(entries\[0\]\.at\)/end.timeIntervalSince(entries.last!.at)/'
mutate "a request counts in the stage after it began" 's/entries\.last \{ \$0\.at <= date \}/entries.first { \$0.at >= date }/'
mutate "the slowest is the fastest"         's/mine\.map\(\\\.seconds\)\.max\(\)/mine.map(\\.seconds).min()/'
print "✓ move clock"
