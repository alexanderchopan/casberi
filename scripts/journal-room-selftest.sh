#!/bin/zsh
# Casberi journal-room self-test — the SHIPPED judgement behind the Day One and
# Apple Journal room heads (prd §398, 2026-08-17):
#
#   Casberi/Casberi/Model/JournalRoom.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
#
# WHY A HARNESS, and here the reason is stronger than for its neighbours. The
# Stripe and PostHog heads could at least be measured by anyone willing to mint
# a key; a journal head cannot be measured at all without somebody's real diary,
# and no Day One or Apple Journal export has ever been imported on this host. So
# these assertions are the ONLY proof these numbers are right.
#
# Every failure mode here is a silent wrong answer that renders as a perfectly
# convincing card:
#
#   · a streak counted ACROSS a gap — the headline's whole claim, in the largest
#     type on the card, congratulating somebody for days they didn't write
#   · silent years skipped instead of drawn, which quietly rescales the axis and
#     puts two bars four years apart side by side
#   · six weeks across New Year's Eve passing the two-calendar-year floor and
#     drawing a "span" that is a month and a half
#   · a subject claimed off one mention, so a year is named after a place
#     somebody went to once
#   · a tie broken by insertion order, so the card names a different year on
#     each open over rows nobody changed
#   · a year printed as a QUANTITY — "2,019 was your fullest year" — which is
#     what `String(localized:)` does to a bare `Int` and what `XRoom` actually
#     shipped until its own harness caught it
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/JournalRoom.swift"
SOURCE="Casberi/Casberi/Model/JournalRoomSource.swift"
CARD="Casberi/Casberi/Screens/JournalRoomCard.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
HERO="Casberi/Casberi/GenUI/GenRenderer.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
TOPICS="Casberi/Casberi/Model/ScreenshotTopics.swift"
INSIGHT="Casberi/Casberi/Model/FeedInsight.swift"
VERIFY="scripts/verify.sh"
for f in "$ROOM" "$SOURCE" "$CARD" "$FEED" "$HERO" "$PROBES" "$TOPICS" "$INSIGHT" "$VERIFY"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for the NEGATIVE guards. Both of these files DOCUMENT
# what they must never do — `JournalRoom` explains at length why Obsidian is not
# one of these rooms, and `JournalRoomSource` says it again — so a guard
# grepping raw source fires against the prose explaining it (the Obsidian/Cursor
# lesson, earned on those harnesses' own first runs).
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
strip_comments "$FEED"   > "$TMP/feed-bare.swift"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled file cannot prove about itself. A perfect `compose` is
# worthless if no room reaches it, if the card draws its own order, or if the
# anniversary that outranks it stops being scoped.

grep -q 'JournalRoomSource.sources.contains(name)' "$FEED" \
  || { echo "✗ FeedScreen.sourceHead no longer routes the journal rooms through JournalRoomSource — both would fall through to the topic map with nothing saying why"; exit 1; }
grep -q 'JournalRoomCard(room: room, source: name)' "$FEED" \
  || { echo "✗ the journal head composes but nothing draws it"; exit 1; }

# ONE LEAD (§451, 2026-08-22). `headline` is the run or nil, because its other
# branch named the fullest year and its entry count — row one verbatim, and the
# strip's only full-height capsule. The card must promote `note` into the empty
# slot, and must NOT then draw the note a second time underneath itself.
# Guarded on the card rather than the model, because the model returning nil is
# already asserted above and a card that drew nothing in that slot would be a
# head with no lead at all — which compiles, and which nothing else here sees.
grep -q 'JournalRoom.headline(room) ?? JournalRoom.note(room)' "$CARD" \
  || { echo "✗ the journal head no longer promotes the note when there is no run — a room with no streak would draw a head with no lead (§451)"; exit 1; }
grep -q 'if JournalRoom.headline(room) != nil {' "$CARD" \
  || { echo "✗ the journal note is no longer gated — with no run the card would print the same sentence at two tiers (§451)"; exit 1; }

# THE PROMOTION (§398). The anniversary sits ABOVE `sourceHead`, which is only
# safe while it is SCOPED — widen it to a room whose head is a dispute deadline
# and a nostalgia card covers something time-critical.
grep -q 'let sourceHead = liveStream == nil && anniversary == nil' "$FEED" \
  || { echo "✗ the anniversary no longer outranks the room head — 'on this day' would never draw in a journal room, since the years card composes on every open"; exit 1; }
grep -q 'guard JournalRoomSource.sources.contains(source) else { return nil }' "$FEED" \
  || { echo "✗ the anniversary is no longer scoped to the journal rooms — every room's head is now displaceable by a nostalgia card"; exit 1; }

# The text treatment. Without it a journal anniversary composes, suppresses
# every card below it, and draws NOTHING — the head slot blank on exactly the
# days the room had something to say.
grep -q 'if echo.thing.previewImageData != nil { picture } else { words }' "$HERO" \
  || { echo "✗ OnThisDayHero no longer falls back to words — a text anniversary would suppress the head and draw an empty slot"; exit 1; }

# ONE case, TWO probe labels — see the note in ProbeHooks. verify.sh's coverage
# is keyed by these names, so a single label could only assert one journal.
for label in dayOneHead appleJournalHead; do
  grep -q "$label" "$PROBES" \
    || { echo "✗ -roomInsightProbe no longer names $label; a room leading with nothing would have no headless diagnosis"; exit 1; }
  grep -q "$label" "$VERIFY" \
    || { echo "✗ verify.sh's room-head coverage no longer checks $label"; exit 1; }
done
grep -q 'journalRoomYear|' "$SOURCE" \
  || { echo "✗ -journalRoomProbe no longer dumps one line per year (the -todayProbe truncation lesson)"; exit 1; }

# The two registries the same pass gave these rooms. The head DISPLACES the
# topic map, so §349's rule only holds while the map is really there to be
# displaced — and a map with no `topicSource` entry can never have terms, which
# is the §313 "registry entry nothing calls into" failure.
for f in "$TOPICS" "$INSIGHT"; do
  grep -q 'case "Day One", "Apple Journal"' "$f" \
    || { echo "✗ $f no longer registers the journal rooms — the head would displace a card that cannot draw"; exit 1; }
done

# NEGATIVE, on the comment-stripped copy: Obsidian must not join these rooms.
# A vault note is dated by its file's mtime, so an edit moves a 2019 note to
# today and the strip would chart when files were touched while claiming to
# chart when somebody wrote.
grep -q 'Obsidian' "$TMP/source-bare.swift" \
  && { echo "✗ Obsidian joined JournalRoomSource.sources — its capturedAt is a file mtime, so the years would be a chart of edits presented as a chart of writing"; exit 1; }
grep -q 'static let sources: Set<String> = \["Day One", "Apple Journal"\]' "$SOURCE" \
  || { echo "✗ the journal room membership moved — it is read twice in FeedScreen (the head and the anniversary above it) and must stay one list"; exit 1; }

# The card draws the model's own order and scale, never its own.
grep -q 'JournalRoom.rows(room)' "$CARD" \
  || { echo "✗ the card no longer draws the model's ranked rows"; exit 1; }
grep -q 'JournalRoom.share(entries: year.entries, of: top)' "$CARD" \
  || { echo "✗ the card no longer scales bars through the model"; exit 1; }
grep -q 'year.entries == 0 ? 0.18 : 0.85' "$CARD" \
  || { echo "✗ a silent year is no longer drawn faint — dropping or hiding it rescales the axis (JournalRoom's own note)"; exit 1; }

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

typealias Sighting = JournalRoom.Sighting

/// Day 0 is an arbitrary origin — the model only ever does adjacency on these,
/// which is exactly the property being tested.
func entry(_ day: Int, year: Int, _ terms: [String] = [], ref: String? = nil) -> Sighting {
    Sighting(ref: ref ?? "e\(day)", year: year, day: day, terms: terms)
}

/// `n` entries on `n` distinct, NON-adjacent days inside one year — the shape
/// every floor test needs and no streak test wants.
func spread(_ n: Int, year: Int, from: Int = 0, step: Int = 7) -> [Sighting] {
    (0..<n).map { entry(from + $0 * step, year: year) }
}

print("The floors")
check("nothing composes over nothing", JournalRoom.compose([]) == nil)
check("under minimumEntries declines",
      JournalRoom.compose(spread(10, year: 2024) + spread(1, year: 2026, from: 900)) == nil)
check("…and one more entry composes, so the floor is the thing being tested",
      JournalRoom.compose(spread(11, year: 2024) + spread(1, year: 2026, from: 900)) != nil)
// One year is not a span, however much is in it.
check("one calendar year declines however full", JournalRoom.compose(spread(40, year: 2024)) == nil)
// THE NEW YEAR TRAP, and the reason `minimumSpanDays` exists beside the year
// count: six weeks straddling December 31st touches two calendar years.
let newYear = spread(8, year: 2024, from: 0, step: 3) + spread(8, year: 2025, from: 24, step: 3)
check("two calendar years six weeks apart declines", JournalRoom.compose(newYear) == nil)
check("…and it really did clear the OTHER two floors, or the test proves nothing",
      newYear.count >= JournalRoom.minimumEntries
        && Set(newYear.map(\.year)).count >= JournalRoom.minimumYears)
// One day over the floor is enough; one day under is not. The boundary itself,
// since an off-by-one here silently refuses a real journal.
let justUnder = spread(6, year: 2024, from: 0, step: 5) + spread(6, year: 2025, from: 150, step: 5)
check("a span one day short of the floor declines",
      JournalRoom.compose(justUnder + [entry(179, year: 2025)]) == nil)
check("a span exactly at the floor composes",
      JournalRoom.compose(justUnder + [entry(180, year: 2025)]) != nil)

print("")
print("The span is drawn whole, silent years included")
// 2020 and 2022 are written; 2021 is not. Skipping it would put two bars two
// years apart side by side.
let gapped = spread(8, year: 2020) + spread(8, year: 2022, from: 730)
let gap = JournalRoom.compose(gapped)!
check("the strip runs first year to last inclusive", gap.years.map(\.year) == [2020, 2021, 2022])
check("the silent year is a real, drawn column", gap.years[1].entries == 0)
check("and is counted as silent", gap.silent == 1)
check("span is the whole stretch, not the years written in", gap.span == 3)
check("a silent year is never a ROW", !JournalRoom.rows(gap).contains { $0.entries == 0 })

print("")
print("Entries and days are different questions")
// Two entries on one day: "how much you wrote" is 2, "how often you showed up"
// is 1, and a card that conflates them overstates the habit.
let twice = spread(12, year: 2024) + [entry(0, year: 2024)] + spread(6, year: 2025, from: 400)
let both = JournalRoom.compose(twice)!
check("total counts entries", both.total == 19)
check("days counts DISTINCT days", both.days == 18)
check("a year's days never exceed its entries",
      both.years.allSatisfy { $0.days <= $0.entries })
// Per YEAR, not just per room — the room-level total is computed from a
// different set, so an assertion there cannot see a year's own count go wrong.
check("the year that was written in twice counts 13 entries on 12 days",
      both.years[0].entries == 13 && both.years[0].days == 12)

print("")
print("The streak is consecutive days, and only consecutive days")
check("no run at all is a run of one", JournalRoom.longestRun([1, 5, 9]).length == 1)
check("an empty set has no run", JournalRoom.longestRun([]).length == 0)
check("adjacent days join", JournalRoom.longestRun([1, 2, 3, 9]).length == 3)
check("a one-day gap breaks it", JournalRoom.longestRun([1, 2, 4, 5]).length == 2)
check("the run's end is reported", JournalRoom.longestRun([1, 2, 3, 9]).end == 3)
// The tie rule, which is what keeps the headline's year stable between opens.
check("equal runs keep the EARLIER one", JournalRoom.longestRun([1, 2, 20, 21]).end == 2)
// No "a repeated day cannot inflate a run" case, and no mutation for one: the
// parameter is a `Set<Int>`, so `[1, 1, 2]` IS `{1, 2}` and a duplicate cannot
// reach this function at all. A test there would pass for a reason that has
// nothing to do with the code under it, which is the failure this harness style
// exists to avoid — the type is the guard, and it is a stronger one than an
// assertion would be.
let streaky = [entry(500, year: 2026), entry(501, year: 2026), entry(502, year: 2026),
               entry(503, year: 2026)] + spread(10, year: 2024)
let run = JournalRoom.compose(streaky)!
check("the streak is carried onto the room", run.streak == 4)
check("and the year it ended in", run.streakYear == 2026)

print("")
print("The headline — the run, or nothing")
check("a real run leads", JournalRoom.headline(run)?.contains("4 days straight") == true)
check("…and places it", JournalRoom.headline(run)?.contains("2026") == true)
// A year is a NAME, not a quantity. `String(localized:)` groups a bare Int, so
// 2026 would render "2,026" — the bug XRoom actually shipped.
check("the year is never grouped as a number",
      JournalRoom.headline(run)?.contains("2,026") == false)
let noRun = JournalRoom.compose(spread(20, year: 2024) + spread(6, year: 2026, from: 800))!
check("below the floor there is no run to name", noRun.streak < JournalRoom.streakFloor)
// PRD §451. The other branch used to say "2024 was your fullest year — 20
// entries", which is row one verbatim (`rows` sorts by entries under the same
// tie rule `fullest` uses) and the strip's only full-height capsule. There is
// no headline at all now, and the card promotes `note` into the empty slot.
check("with no run there is no headline", JournalRoom.headline(noRun) == nil)
check("two consecutive days are not a streak",
      JournalRoom.headline(JournalRoom.compose(
        [entry(900, year: 2026), entry(901, year: 2026)] + spread(14, year: 2024))!) == nil)
// The property that made the old sentence a repetition, asserted so a future
// pass cannot reintroduce it believing it adds something.
check("row one is the fullest year, so a lead naming it would repeat it",
      JournalRoom.rows(noRun).first?.year == noRun.fullest.year
      && JournalRoom.rows(noRun).first?.entries == noRun.fullest.entries)
// …and the line that stands in must carry what the drawing cannot.
check("the stand-in lead states entries, days and the span",
      JournalRoom.note(noRun).contains("26") && JournalRoom.note(noRun).contains("3"))

print("")
print("The fullest year, and its tie")
check("the fullest year is the one with most entries", noRun.fullest.year == 2024)
// Tie → EARLIER year, so the card names the first time you wrote that much and,
// far more importantly, so two identical opens agree.
let tied = spread(9, year: 2020) + spread(9, year: 2023, from: 1100)
let tie = JournalRoom.compose(tied)!
check("a tie goes to the earlier year", tie.fullest.year == 2020)
let reversed = JournalRoom.compose(tied.reversed())!
check("input order cannot change the answer", tie.fullest.year == reversed.fullest.year)
check("nor the strip", tie.years == reversed.years)
check("nor the streak", tie.streak == reversed.streak)

print("")
print("A year's subject recurs, or it is not claimed")
check("one mention names nothing",
      JournalRoom.subject(["Lisbon": 1], entries: 30) == nil)
check("two mentions in a small year is enough",
      JournalRoom.subject(["Lisbon": 2], entries: 12) == "Lisbon")
// A tenth of the year, so a big year needs proportionally more.
check("two mentions in a hundred-entry year is not",
      JournalRoom.subject(["Lisbon": 2], entries: 100) == nil)
check("ten of a hundred is", JournalRoom.subject(["Lisbon": 10], entries: 100) == "Lisbon")
check("the most common term wins",
      JournalRoom.subject(["Lisbon": 4, "Berlin": 9], entries: 20) == "Berlin")
check("a tie breaks alphabetically, so the answer is stable",
      JournalRoom.subject(["Lisbon": 9, "Berlin": 9], entries: 20) == "Berlin")
check("no terms at all is nil, which is normal",
      JournalRoom.subject([:], entries: 30) == nil)
let subjects = JournalRoom.compose(
    spread(12, year: 2024).map { Sighting(ref: $0.ref, year: $0.year, day: $0.day, terms: ["Berlin"]) }
    + spread(6, year: 2025, from: 400))!
check("…and this fixture really has no silent year, or the note test below "
      + "would pass for the wrong reason", subjects.silent == 0)
check("a subject reaches the year row", subjects.years.first?.subject == "Berlin")
check("and the row line says it", JournalRoom.yearLine(subjects.years[0]).contains("mostly Berlin"))

print("")
print("Rows")
let ranked = JournalRoom.compose(
    spread(4, year: 2020) + spread(9, year: 2021, from: 400)
    + spread(2, year: 2022, from: 800) + spread(6, year: 2023, from: 1200))!
check("fullest first", JournalRoom.rows(ranked).map(\.year) == [2021, 2023, 2020])
check("capped at rowCap", JournalRoom.rows(ranked).count == JournalRoom.rowCap)
check("the strip is NEVER capped — a truncated span is a lie about when you started",
      ranked.years.count == 4)

print("")
print("Shares")
check("the fullest year is full width", JournalRoom.share(entries: 9, of: 9) == 1)
check("a smaller year is its fraction", abs(JournalRoom.share(entries: 3, of: 9) - 1.0/3) < 1e-9)
check("a silent year is zero", JournalRoom.share(entries: 0, of: 9) == 0)
// SwiftUI draws a NaN frame as nothing at all.
check("a zero denominator is zero, never NaN", JournalRoom.share(entries: 5, of: 0) == 0)
check("nothing can exceed the full width", JournalRoom.share(entries: 20, of: 9) == 1)

print("")
print("Words that carry a fact the strip cannot")
check("with no silent years the span is stated whole",
      JournalRoom.note(subjects).contains("across"))
check("with silent years it says how many you wrote in",
      JournalRoom.note(gap).contains("2 of 3 years"))
check("the note carries entries AND days", JournalRoom.note(both).contains("19 entries")
      && JournalRoom.note(both).contains("18 days"))
check("every row unnamed says the sweep hasn't run",
      JournalRoom.footnote(ranked) == "Subjects arrive once the room has been read.")
check("some named, some not, says how many",
      JournalRoom.footnote(subjects)?.contains("of these years") == true)
let allNamed = JournalRoom.compose(
    (spread(12, year: 2024) + spread(12, year: 2026, from: 800)).map {
        Sighting(ref: $0.ref, year: $0.year, day: $0.day, terms: ["Berlin"])
    })!
check("every row named needs no footnote", JournalRoom.footnote(allNamed) == nil)

print("")
if failures > 0 {
    print("journal-room-selftest: \(failures) FAILED")
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
# The headline's whole claim, congratulating somebody for days they didn't write.
mutate "the streak counts across gaps" \
  'current = sorted[i] == sorted[i - 1] + 1 ? current + 1 : 1' \
  'current = current + 1'
# A run that reshuffles its year between two identical opens.
mutate "equal runs keep the later one" \
  'if current > best {' \
  'if current >= best {'
# Six weeks across New Year drawn as a two-year span.
mutate "the day-span floor is dropped" \
  'lastDay - firstDay >= minimumSpanDays' \
  'lastDay - firstDay >= 0'
# One busy month redrawn as a habit.
mutate "the entry floor is dropped" \
  'guard sightings.count >= minimumEntries else { return nil }' \
  'guard sightings.count >= 0 else { return nil }'
# Two bars four years apart, side by side, on a quietly rescaled axis.
mutate "silent years are skipped instead of drawn" \
  'for year in first...last {' \
  'for year in counts.keys.sorted() {'
# A card naming a different year on each open over rows nobody changed.
mutate "the fullest-year tie is broken the other way" \
  'years.max(by: { ($0.entries, $1.year) < ($1.entries, $0.year) })' \
  'years.max(by: { ($0.entries, $0.year) < ($1.entries, $1.year) })'
# A year named after a place somebody went once.
mutate "one mention names a year" \
  'let floor = max(2, entries / 10)' \
  'let floor = 1'
# "How often you showed up" answered with "how much you wrote".
mutate "days are counted as entries" \
  'days: daysByYear[year]?.count ?? 0' \
  'days: entries'
# A year printed as a quantity, in the largest type on the card (XRoom's own
# shipped bug).
mutate "the headline groups the year as a number" \
  'in \(String(year))' \
  'in \(year)'
# The rows' order is the card's whole ranking.
mutate "rows are drawn oldest-first instead of fullest-first" \
  'sorted { ($0.entries, $1.year) > ($1.entries, $0.year) }' \
  'sorted { $0.year < $1.year }'
# A bar wider than the frame, drawn by a year that cannot be the fullest.
mutate "the share is left unclamped" \
  'return min(1, Double(entries) / Double(top))' \
  'return Double(entries) / Double(top)'
# Silent years as rows: a bar of nothing under a label, saying "0" in the shape
# of a finding.
mutate "silent years become rows" \
  'filter { $0.entries > 0 }' \
  'filter { _ in true }'

echo ""
echo "journal-room-selftest: OK — assertions pass and every mutation is caught."
