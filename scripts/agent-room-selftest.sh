#!/bin/zsh
# Casberi agent-room self-test — the SHIPPED judgement behind the ChatGPT,
# Claude, Gemini and Claude Code room heads (prd §457, 2026-08-23):
#
#   Casberi/Casberi/Model/AgentRoom.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
#
# WHY A HARNESS: no ChatGPT, Claude or Gemini export has ever been imported on
# this host, so these assertions are the ONLY proof these numbers are right —
# `JournalRoom`'s reason, one room over.
#
# Every failure mode here is a silent wrong answer that renders as a perfectly
# convincing card:
#
#   · turns compared ACROSS seats — a Claude Code session narrates its own
#     tool use and runs to hundreds of turns by construction, so ranking by
#     turns instead of conversations would report the chattiest transcript
#     format as the one you rely on, not the one you actually use most
#   · the lead date flipping on a quiet week — a per-month "who's ahead"
#     comparison instead of the whole-stretch-from-here rule
#   · silent months skipped instead of drawn, quietly rescaling the axis
#   · a subject claimed off one mention, so a month is named after a word said
#     once
#   · a tie broken by insertion order, so the card names a different month on
#     each open over rows nobody changed
#   · a month ordinal that doesn't invert back to the month it was built from
#   · a turn figure computed over rows that never carried a count, silently
#     treating "unknown" as "zero"
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/AgentRoom.swift"
SOURCE="Casberi/Casberi/Model/AgentRoomSource.swift"
CARD="Casberi/Casberi/Screens/AgentRoomCard.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
TOPICS="Casberi/Casberi/Model/ScreenshotTopics.swift"
IMPORT="Casberi/Casberi/Model/ClaudeCodeImport.swift"
VERIFY="scripts/verify.sh"
for f in "$ROOM" "$SOURCE" "$CARD" "$FEED" "$PROBES" "$TOPICS" "$IMPORT" "$VERIFY"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for the NEGATIVE guards. `AgentRoomSource` and
# `AgentRoom` both DOCUMENT what they must never do — the header explains at
# length why turns are never compared across seats — so a guard grepping raw
# source fires against the prose explaining the rule (the Obsidian/Cursor
# lesson, earned on every sibling harness's own first run).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'^[ \t]*//.*$', '', src, flags=re.M)
src = re.sub(r'//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$SOURCE" > "$TMP/source-bare.swift"
strip_comments "$ROOM"   > "$TMP/room-bare.swift"

failures=0
check() {
  local name="$1"
  if [[ "$2" == "1" ]]; then echo "  ✗ $name"; failures=$((failures + 1))
  else :; fi
}

# --- drift guards -----------------------------------------------------------
# Wiring the compiled file cannot prove about itself. A perfect `compose` is
# worthless if no room reaches it or if the card draws its own order.

grep -q 'AgentRoomSource.sources.contains(name)' "$FEED" \
  || { echo "✗ FeedScreen.sourceHead no longer routes the agent rooms through AgentRoomSource — all four would fall through to the topic map with nothing saying why"; exit 1; }
grep -q 'AgentRoomCard(room: room, source: name)' "$FEED" \
  || { echo "✗ the agent head composes but nothing draws it"; exit 1; }

# ONE LEAD (§451/§452's rule, inherited from JournalRoomCard). `headline` is
# the longest conversation or nil; the card must promote `note` into the empty
# slot rather than drawing a head with no lead.
grep -q 'AgentRoom.headline(room) ?? AgentRoom.note(room)' "$CARD" \
  || { echo "✗ the agent head no longer promotes the note when nothing is deep enough to lead with — a room with no headline would draw a head with no lead"; exit 1; }
grep -q 'if AgentRoom.headline(room) != nil {' "$CARD" \
  || { echo "✗ the note is no longer conditional on the headline existing — it would draw twice in the slot it was meant to stand in for"; exit 1; }

# THE COMPARISON IS CONVERSATIONS, NEVER TURNS — the header's own load-bearing
# rule, and the one most likely to look like a harmless improvement. Read from
# the COMMENT-STRIPPED copy: the file explains at length why turns must never
# cross seats, and a raw grep would pass against that very explanation.
grep -q 'func comparison' "$TMP/room-bare.swift" \
  || { echo "✗ AgentRoom.comparison is gone — the cross-assistant reading, the one thing this card can say that no single agent product can, is missing"; exit 1; }
python3 - "$TMP/room-bare.swift" <<'PY' || { echo "✗ AgentRoom.comparison reads .turns rather than only .total/.months — turns would be compared across seats of structurally different shape"; exit 1; }
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'static func comparison\(.*?\n    \}', src, re.S)
if not m or '.turns' in m.group(0):
    sys.exit(1)
PY

# --- pure model, compiled and asserted --------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if !ok { print("  ✗ \(name)"); failures += 1 }
}

typealias Sighting = AgentRoom.Sighting
typealias Rival = AgentRoom.Rival

/// A month ordinal from a plain (year, month) pair — the same packing
/// `AgentRoomSource.monthOrdinal` uses, spelled out here so the fixtures read
/// as calendar dates rather than opaque integers.
func m(_ year: Int, _ month: Int) -> Int { year * 12 + (month - 1) }

func convo(_ month: Int, day: Int, turns: Int? = 8, terms: [String] = [],
           ref: String? = nil, title: String = "A conversation") -> Sighting {
    Sighting(ref: ref ?? "c\(day)", month: month, day: day, turns: turns,
             terms: terms, title: title)
}

/// `n` conversations spread across `n` distinct days inside one month — the
/// shape every floor test needs.
func spread(_ n: Int, month: Int, from: Int = 0, step: Int = 3) -> [Sighting] {
    (0..<n).map { convo(month, day: from + $0 * step) }
}

print("monthLabel never groups the year as a quantity")
// `XRoom`'s own shipped bug: `String(localized:)` groups a bare Int, so an
// unwrapped year interpolation renders "2,025" — a year printed as a number,
// in the largest type on the card.
check("the year is never grouped with a thousands separator",
      !AgentRoom.monthLabel(m(2025, 3)).contains(","))
check("…and the month name and year both appear",
      AgentRoom.monthLabel(m(2025, 3)).contains("March")
      && AgentRoom.monthLabel(m(2025, 3)).contains("2025"))

print("")
print("Month arithmetic round-trips")
check("year inverts", AgentRoom.year(ofMonth: m(2026, 3)) == 2026)
check("month-of-year inverts", AgentRoom.monthOfYear(m(2026, 3)) == 3)
check("January inverts to 1, not 0", AgentRoom.monthOfYear(m(2026, 1)) == 1)
check("December inverts to 12", AgentRoom.monthOfYear(m(2026, 12)) == 12)
check("crossing a year boundary still inverts",
      AgentRoom.year(ofMonth: m(2026, 1) - 1) == 2025
      && AgentRoom.monthOfYear(m(2026, 1) - 1) == 12)

print("")
print("The floors")
check("nothing composes over nothing", AgentRoom.compose([]) == nil)
check("under minimumConversations declines",
      AgentRoom.compose(spread(10, month: m(2026, 1))
                        + spread(1, month: m(2026, 6), from: 900)) == nil)
check("…and one more composes, so the floor is the thing being tested",
      AgentRoom.compose(spread(11, month: m(2026, 1))
                        + spread(1, month: m(2026, 6), from: 900)) != nil)
check("one calendar month is not a span, however full",
      AgentRoom.compose(spread(40, month: m(2026, 1))) == nil)
// THE MONTH-BOUNDARY TRAP, and the reason `minimumSpanDays` exists beside the
// month count: a fortnight straddling the 31st touches two calendar months.
let monthEdge = spread(7, month: m(2026, 1), from: 25, step: 1)
              + spread(7, month: m(2026, 2), from: 32, step: 1)
check("a fortnight across a month boundary declines", AgentRoom.compose(monthEdge) == nil)
check("…and it really did clear the other two floors, or the test proves nothing",
      monthEdge.count >= AgentRoom.minimumConversations
      && Set(monthEdge.map(\.month)).count >= AgentRoom.minimumMonths)

print("")
print("The span is drawn whole, silent months included")
let gapped = spread(8, month: m(2025, 1)) + spread(8, month: m(2025, 4), from: 300)
let gap = AgentRoom.compose(gapped)!
check("the strip runs first month to last inclusive",
      gap.months.map(\.month) == [m(2025, 1), m(2025, 2), m(2025, 3), m(2025, 4)])
check("silent months are real, drawn columns", gap.months[1].conversations == 0)
check("and counted as silent", gap.silent == 2)
check("span is the whole stretch, not the months written in", gap.span == 4)
check("a silent month is never a row", !AgentRoom.rows(gap).contains { $0.conversations == 0 })

print("")
print("Turns are counted apart from the conversations that carried none")
let mixed = spread(9, month: m(2025, 1)).map { convo($0.month, day: $0.day, turns: 10) }
          + [convo(m(2025, 1), day: 900, turns: nil)]
          + spread(6, month: m(2025, 3), from: 400)
let mx = AgentRoom.compose(mixed)!
check("total counts every conversation", mx.total == 16)
check("counted excludes the nil", mx.counted == 15)
check("turns sums only what carried a count", mx.turns == 9 * 10 + 6 * 8)
check("nil is never read as zero",
      mx.turns != (9 * 10) + 0 + (6 * 8) - 1) // sanity: the nil contributes nothing either way,
                                               // this just confirms the arithmetic isn't fudged

print("")
print("The longest conversation, and its tie")
let deep = spread(11, month: m(2025, 1), step: 2).map { convo($0.month, day: $0.day, turns: 5) }
         + [convo(m(2025, 1), day: 500, turns: 40, ref: "deep-one", title: "The long one")]
         + spread(6, month: m(2025, 3), from: 800)
let longest = AgentRoom.compose(deep)!
check("the deepest conversation wins", longest.longest?.turns == 40)
check("its title and ref travel", longest.longest?.title == "The long one"
      && longest.longest?.ref == "deep-one")
check("below the floor there is no longest to name",
      AgentRoom.headline(AgentRoom.compose(
        spread(12, month: m(2025, 1)) + spread(6, month: m(2025, 3), from: 800))!) == nil)
// STRICTLY greater — two conversations of equal depth must not swap the title
// between two composes of the same rows.
let tiedDepth = spread(12, month: m(2025, 1)).map { convo($0.month, day: $0.day, turns: 30, ref: "a-\($0.day)") }
              + [convo(m(2025, 1), day: 999, turns: 30, ref: "b", title: "Later, same depth")]
              + spread(6, month: m(2025, 3), from: 800)
let tie = AgentRoom.compose(tiedDepth)!
check("an equal-depth later conversation does not overtake the earlier one",
      tie.longest?.ref != "b")

print("")
print("The headline names the longest, or nothing")
check("a real longest leads", AgentRoom.headline(longest)?.contains("40") == true)
check("below longestFloor there is no headline",
      AgentRoom.compose(spread(12, month: m(2025, 1)).map { convo($0.month, day: $0.day, turns: 5) }
                        + spread(6, month: m(2025, 3), from: 800))
        .flatMap(AgentRoom.headline) == nil)
// The property that would make a lead a repetition of row one — asserted the
// same way JournalRoom's harness pins it, so a future pass can't reintroduce
// the double-telling by accident.
let shallow = AgentRoom.compose(spread(20, month: m(2025, 1)).map { convo($0.month, day: $0.day, turns: 3) }
                                + spread(6, month: m(2025, 3), from: 800))!
check("with no headline the note carries conversations and turns",
      AgentRoom.note(shallow).contains("26") && AgentRoom.note(shallow).contains("turns"))

print("")
print("note() withholds turns entirely when nothing was counted")
let noTurns = spread(12, month: m(2025, 1)).map { convo($0.month, day: $0.day, turns: nil) }
            + spread(6, month: m(2025, 3), from: 800).map { convo($0.month, day: $0.day, turns: nil) }
let nt = AgentRoom.compose(noTurns)!
check("turns is zero when nothing was counted", nt.turns == 0 && nt.counted == 0)
check("the note names conversations without claiming a turn figure",
      AgentRoom.note(nt).contains("conversations") && !AgentRoom.note(nt).contains("turns"))
print("note() flags a PARTIAL count rather than presenting it as whole")
let partial = spread(15, month: m(2025, 1)).map { convo($0.month, day: $0.day, turns: 10) }
            + spread(15, month: m(2025, 3), from: 800).map { convo($0.month, day: $0.day, turns: nil) }
let pt = AgentRoom.compose(partial)!
check("counted is smaller than total", pt.counted < pt.total)
check("the note says how many of the total the turn figure covers",
      AgentRoom.note(pt).contains("of them"))

print("")
print("A month's subject recurs, or it is not claimed")
check("one mention names nothing", AgentRoom.subject(["SwiftUI": 1], conversations: 30) == nil)
check("two mentions in a small month is enough",
      AgentRoom.subject(["SwiftUI": 2], conversations: 12) == "SwiftUI")
check("two mentions in a hundred-conversation month is not",
      AgentRoom.subject(["SwiftUI": 2], conversations: 100) == nil)
check("the most common term wins",
      AgentRoom.subject(["SwiftUI": 4, "CloudKit": 9], conversations: 20) == "CloudKit")
check("a tie breaks alphabetically, so the answer is stable",
      AgentRoom.subject(["SwiftUI": 9, "CloudKit": 9], conversations: 20) == "CloudKit")

print("")
print("The busiest month, and its tie")
// Tie → EARLIER month, so two identical opens agree and the card can't
// reshuffle its own headline over rows nobody changed.
let tiedMonths = spread(9, month: m(2025, 1)) + spread(9, month: m(2025, 6), from: 900)
let busyTie = AgentRoom.compose(tiedMonths)!
check("a tie goes to the earlier month", busyTie.busiest.month == m(2025, 1))
let busyReversed = AgentRoom.compose(tiedMonths.reversed())!
check("input order cannot change the answer", busyTie.busiest.month == busyReversed.busiest.month)
check("nor the strip", busyTie.months == busyReversed.months)

print("")
print("Rows")
let ranked = AgentRoom.compose(
    spread(4, month: m(2025, 1)) + spread(9, month: m(2025, 2), from: 200)
    + spread(2, month: m(2025, 3), from: 400) + spread(6, month: m(2025, 4), from: 600))!
check("busiest first", AgentRoom.rows(ranked).map(\.month) == [m(2025, 2), m(2025, 4), m(2025, 1)])
check("capped at rowCap", AgentRoom.rows(ranked).count == AgentRoom.rowCap)
check("the strip is never capped — a truncated span is a lie about when you started",
      ranked.months.count == 4)

print("")
print("Shares")
check("the busiest month is full width", AgentRoom.share(conversations: 9, of: 9) == 1)
check("a smaller month is its fraction",
      abs(AgentRoom.share(conversations: 3, of: 9) - 1.0/3) < 1e-9)
check("a silent month is zero", AgentRoom.share(conversations: 0, of: 9) == 0)
check("a zero denominator is zero, never NaN", AgentRoom.share(conversations: 5, of: 0) == 0)
check("nothing can exceed the full width", AgentRoom.share(conversations: 20, of: 9) == 1)

print("")
print("leadSince — the whole-stretch rule, not a per-month flip")
// Mine ahead the whole way — leads from the very first month.
let mineAll: [Int: Int] = [m(2025, 1): 5, m(2025, 2): 6, m(2025, 3): 4]
let theirsAll: [Int: Int] = [m(2025, 1): 2, m(2025, 2): 1, m(2025, 3): 1]
check("leading the whole span reports the first month",
      AgentRoom.leadSince(mineAll, over: theirsAll, through: m(2025, 3)) == m(2025, 1))
// A single quiet month must NOT flip the running answer — the reason the walk
// is cumulative from the end rather than month-by-month.
let mineQuiet: [Int: Int] = [m(2025, 1): 20, m(2025, 2): 0, m(2025, 3): 3]
let theirsQuiet: [Int: Int] = [m(2025, 1): 1, m(2025, 2): 5, m(2025, 3): 1]
check("a single quiet month does not lose an otherwise-commanding lead",
      AgentRoom.leadSince(mineQuiet, over: theirsQuiet, through: m(2025, 3)) == m(2025, 1))
// Never led — behind for the whole span, at every prefix from the end.
let mineLosing: [Int: Int] = [m(2025, 1): 1, m(2025, 2): 1, m(2025, 3): 1]
let theirsLosing: [Int: Int] = [m(2025, 1): 5, m(2025, 2): 5, m(2025, 3): 5]
check("never leading reports nil",
      AgentRoom.leadSince(mineLosing, over: theirsLosing, through: m(2025, 3)) == nil)
// A tie is not a lead. "More than" means more than.
let mineTie: [Int: Int] = [m(2025, 1): 5]
let theirsTie: [Int: Int] = [m(2025, 1): 5]
check("an exact tie is not a lead",
      AgentRoom.leadSince(mineTie, over: theirsTie, through: m(2025, 1)) == nil)
// The lead really did BEGIN partway. `leadSince` is a CUMULATIVE walk from
// the end, so the fixture has to make the cumulative sum genuinely flip: a
// merely-losing month 2 is not enough if the deficit is small next to a big
// enough month-3/4 lead, since the running total from month 2 onward can
// still favour mine. Month 2's deficit here is deliberately large enough that
// the cumulative-from-month-2 total stays theirs', and only from month 3
// onward does mine's total overtake.
let mineLater: [Int: Int] = [m(2025, 1): 1, m(2025, 2): 1, m(2025, 3): 10, m(2025, 4): 10]
let theirsLater: [Int: Int] = [m(2025, 1): 5, m(2025, 2): 19, m(2025, 3): 1, m(2025, 4): 1]
check("a lead that begins partway is dated to where it begins",
      AgentRoom.leadSince(mineLater, over: theirsLater, through: m(2025, 4)) == m(2025, 3))
// CUMULATIVE vs PER-MONTH really do disagree here, which is what makes this
// fixture able to catch the mutation that swaps one for the other: month 1
// alone favours mine by a hair, but a per-month rule would stop at month 1,
// while the true cumulative-from-month-1 total is buried under month 2's
// landslide for the rival — so the honest answer is month 3, not month 1.
let mineSpiky: [Int: Int] = [m(2025, 1): 2, m(2025, 2): 0, m(2025, 3): 5]
let theirsSpiky: [Int: Int] = [m(2025, 1): 1, m(2025, 2): 30, m(2025, 3): 1]
check("an isolated month favouring mine does not count as the lead's start",
      AgentRoom.leadSince(mineSpiky, over: theirsSpiky, through: m(2025, 3)) == m(2025, 3))

print("")
print("The comparison line — conversations only, three honest states")
func room(months: [Int: Int], rivalMonths: [Int: Int], rivalName: String = "Claude") -> AgentRoom {
    var sightings: [Sighting] = []
    for (month, n) in months {
        sightings += (0..<max(n, 0)).map { convo(month, day: month * 1000 + $0, turns: 5) }
    }
    return AgentRoom.compose(sightings, rivals: [Rival(name: rivalName, months: rivalMonths)])!
}
let leadingFromStart = room(months: [m(2025, 1): 20, m(2025, 2): 20],
                            rivalMonths: [m(2025, 1): 1, m(2025, 2): 1])
check("leading from the span's own start names no month",
      AgentRoom.comparison(leadingFromStart)?.contains("since") == false)
// Same cumulative-walk shape as `leadSince`'s own fixture above: month 2's
// deficit has to be large enough that the running total from month 2 onward
// still favours the rival, or the lead reads as starting at month 1.
let leadingLater = room(months: [m(2025, 1): 1, m(2025, 2): 1, m(2025, 3): 20],
                        rivalMonths: [m(2025, 1): 5, m(2025, 2): 25, m(2025, 3): 1])
check("leading only later names the month it began",
      AgentRoom.comparison(leadingLater)?.contains("since") == true)
let losing = room(months: [m(2025, 1): 12, m(2025, 2): 12],
                  rivalMonths: [m(2025, 1): 40, m(2025, 2): 40])
check("not leading says so rather than going quiet", AgentRoom.comparison(losing) != nil)
check("…and it is honest about who is ahead", AgentRoom.comparison(losing)?.contains("Claude") == true)
check("no rivals at all means no comparison line",
      AgentRoom.compose(spread(12, month: m(2025, 1)) + spread(6, month: m(2025, 3), from: 800),
                        rivals: []).flatMap(AgentRoom.comparison) == nil)

print("")
if failures > 0 {
    print("agent-room-selftest: \(failures) FAILED")
    exit(1)
}
print("assertions: all pass")
SWIFT

if ! swiftc -O -o "$TMP/run" "$ROOM" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the harness did not compile against the shipped source:"
  cat "$TMP/build.log"
  exit 1
fi
"$TMP/run" || exit 1

# --- mutations --------------------------------------------------------------
# Each is a silent-wrong-answer this file exists to catch. A mutation the
# harness still passes means nothing was testing that behaviour.
mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut.swift"
  cp "$ROOM" "$target"
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
  if ! swiftc -O -o "$TMP/mut" "$target" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

echo ""
echo "Mutations"
# A month-ordinal round-trip broken: bars land right, labels lie.
mutate "monthOfYear stops wrapping at 12" \
  'static func monthOfYear(_ ordinal: Int) -> Int { ordinal % 12 + 1 }' \
  'static func monthOfYear(_ ordinal: Int) -> Int { ordinal + 1 }'
# Six weeks across a month boundary drawn as a real two-month span.
mutate "the day-span floor is dropped" \
  'lastDay - firstDay >= minimumSpanDays' \
  'lastDay - firstDay >= 0'
# One busy week redrawn as a habit.
mutate "the conversation floor is dropped" \
  'guard sightings.count >= minimumConversations else { return nil }' \
  'guard sightings.count >= 0 else { return nil }'
# Two bars months apart, side by side, on a quietly rescaled axis.
mutate "silent months are skipped instead of drawn" \
  'for ordinal in first...last {' \
  'for ordinal in counts.keys.sorted() {'
# A card naming a different month on each open over rows nobody changed.
mutate "the busiest-month tie is broken the other way" \
  '($0.conversations, $1.month) < ($1.conversations, $0.month)' \
  '($0.conversations, $0.month) < ($1.conversations, $1.month)'
# A conversation with an unknown length silently read as zero.
mutate "nil turns are counted as zero rather than excluded" \
  'if let turns = sight.turns {' \
  'do { let turns = sight.turns ?? 0'
# A month named after a word said once.
mutate "one mention names a month" \
  'let floor = max(2, conversations / 10)' \
  'let floor = 1'
# The rows' order is the card's whole ranking.
mutate "rows are drawn oldest-first instead of busiest-first" \
  'sorted { ($0.conversations, $1.month) > ($1.conversations, $0.month) }' \
  'sorted { $0.month < $1.month }'
# A bar wider than the frame.
mutate "the share is left unclamped" \
  'return min(1, Double(conversations) / Double(top))' \
  'return Double(conversations) / Double(top)'
# Silent months as rows: a bar of nothing under a label, saying "0" in the
# shape of a finding.
mutate "silent months become rows" \
  'filter { $0.conversations > 0 }' \
  'filter { _ in true }'
# THE COMPARISON'S WHOLE POINT: a per-month flip instead of the cumulative
# from-the-end walk, which would make the card announce a change of allegiance
# on any single quiet week.
mutate "leadSince stops walking cumulatively from the end" \
  'if mineRunning > theirsRunning { answer = ordinal }' \
  'if (mine[ordinal] ?? 0) > (theirs[ordinal] ?? 0) { answer = ordinal }'
# A tie read as a lead.
mutate "a tie counts as leading" \
  'if mineRunning > theirsRunning { answer = ordinal }' \
  'if mineRunning >= theirsRunning { answer = ordinal }'
# A month printed as a QUANTITY — `XRoom`'s own shipped bug, checked here too
# since `monthLabel` interpolates a bare year the same way.
mutate "the month label groups the year as a number" \
  'return String(localized: "\(name) \(String(year(ofMonth: ordinal)))")' \
  'return String(localized: "\(name) \(year(ofMonth: ordinal))")'

echo ""
echo "agent-room-selftest: OK — assertions pass and every mutation is caught."
