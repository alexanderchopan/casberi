#!/bin/zsh
# Casberi note-sheet self-test — the SHIPPED pure judgement behind every note
# thing sheet (prd §366, 2026-08-12):
#
#   Casberi/Casberi/Model/NoteSheet.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
# Everything touching `Thing`, SwiftData or the catalog lives in
# `NoteSheetSource.swift`, which no harness can compile and which holds lookups
# rather than judgement.
#
# WHY A HARNESS. Every failure mode in this file is a SILENT WRONG ANSWER that
# renders perfectly, and neither a build nor a simulator sweep can see any of
# them:
#
#   · a word count taken over a CLAMPED body understates a real note by
#     thousands while looking exactly like a measurement — the whole reason the
#     `+` valve exists, and the reading a person would trust instantly
#   · a passage classified as an entry draws a date hero over somebody else's
#     sentence, putting our clock on their words
#   · a vault note classified as an entry loses its name and leads with the
#     modification time of a file, which is a fact about your editor
#   · a read time on a twelve-word note is the app padding itself out, and no
#     screen can tell you it is wrong
#   · an "imported on" clause that fires when the two dates agree turns the
#     receipt back into the form it replaced
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHEET="Casberi/Casberi/Model/NoteSheet.swift"
SOURCE="Casberi/Casberi/Model/NoteSheetSource.swift"
VIEWS="Casberi/Casberi/Screens/NoteSheetViews.swift"
VIEW="Casberi/Casberi/Screens/ThingSheetView.swift"
KINDLE="Casberi/Casberi/Model/KindleImport.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
for f in "$SHEET" "$SOURCE" "$VIEWS" "$VIEW" "$KINDLE" "$CATALOG"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled functions cannot prove about themselves. A perfect
# `shape` is worthless if the sheet never asks it, and a perfect `compose` is
# worthless if the spec table still prints `From` beside its sentence.
fail=0
guard() {  # name, pattern, file
  if grep -qE -- "$2" "$3"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi
}
absent() { # name, pattern, file — reads a COMMENT-STRIPPED copy, see below
  if grep -qE -- "$2" "$3"; then echo "  ✗ $1"; fail=1; else echo "  ✓ $1"; fi
}

echo "Drift guards"

# The gate itself, and that the sheet reaches it.
guard "the sheet asks NoteSheetSource for its shape" \
  'NoteSheetSource\.shape\(for: thing\)' "$VIEW"
guard "the note head replaces the title block" \
  'else if let noteShape \{' "$VIEW"
guard "the reception block is drawn by the sheet" \
  'NoteReceptionCard\(reception: noteReception\)' "$VIEW"

# THE HEADLINE FIX. The generic content view is where a journal entry's prose
# was set at `callout15` in `textSecondary` and cut at twelve lines. If a note
# reaches it again, every entry prints twice — the second time worse — and
# nothing on screen says so.
guard "a note never falls through to the generic content view" \
  'socialShape != \.person && noteShape == nil' "$VIEW"
# …except a voice note, whose player and transcript belong together.
guard "a voice note keeps its player" \
  'noteShape == \.entry, thing\.kind == \.voice' "$VIEW"

# The From row must stand down where the sentence speaks, or the sheet says the
# same fact twice in two voices — which is what this pass set out to end.
guard "the From spec row stands down for a composed note sentence" \
  'noteReception\?\.provenance == nil' "$VIEW"

# The prose tier. This is the fix, spelled as a test: reading tier, primary
# ink. A `callout15`/`textSecondary` body here is the defect returning.
#
# The tier became a PARAMETER on 2026-08-20 so an agent turn could reuse this
# renderer at bubble size, and the §366 ruling moved with it: it is now the
# DEFAULT, which is what every note call site takes. Guarded in its new
# location rather than deleted — a guarded rule that moves takes its guard with
# it. Both halves matter: the default must be the reading tier, AND the note
# sheet must not start passing a smaller one, which is the only way the defect
# could come back now.
guard "the note body's tier defaults to the reading tier" \
  'var tier: DSTextStyle = \.reading20' "$VIEWS"
if grep -qE 'NoteProse\([^)]*tier:' "$VIEW"; then
  echo "  ✗ the note sheet passes an explicit tier — §366's reading tier is the"
  echo "    default for a reason: on these sources the body IS the thing."
  exit 1
fi
echo "  ✓ the note sheet takes the default tier rather than overriding it"
guard "note prose is set in primary ink" \
  'foregroundStyle\(DS\.textPrimary\)' "$VIEWS"

# Tags are DRAWN now (they were stamped by two sources and rendered nowhere).
guard "the sheet draws the note's own tags" 'NoteTagRow\(tags: tags\)' "$VIEW"
guard "the kind tag is filtered out of them" 'typeTags\.contains' "$SOURCE"

# The two shelves, and the graph reading.
guard "the passage shelf is drawn" 'NoteSiblingList\(rows: siblingPassages' "$VIEW"
guard "the same-day shelf is drawn" 'NoteSameDayShelf\(rows: sameDayThings' "$VIEW"
guard "the vault graph counts are drawn" 'NoteGraphCounts\(linksOut:' "$VIEW"
# The two directions are never summed — a note that both links to and is linked
# from another would be counted twice, and the directions are the information.
absent "the graph counts are not summed" \
  'linksOut \+ linkedFrom' "$VIEWS"

# THE KINDLE DATA-LOSS FIX. Three halves, each independently able to fail
# silently: the passage must land on `content`, the work must land where a room
# can rank it, and an already-landed row must be REPAIRED rather than skipped —
# without the heal the fix reaches only files imported from today on, and every
# existing row stays truncated forever.
guard "the Kindle importer lands the passage as the body" \
  'content: body,' "$KINDLE"
guard "the Kindle importer lands the work on authorHandle" \
  'thing\.authorHandle = work' "$KINDLE"
guard "the Kindle importer heals a row it has already seen" \
  'if let existing = landed\[ref\], heal\(existing' "$KINDLE"
guard "a heal-only pass still saves" 'added > 0 \|\| healed > 0' "$KINDLE"
guard "a repaired row is re-indexed" \
  'if changed \{ SpotlightIndex\.index\(\[thing\]\) \}' "$KINDLE"
guard "the repair is reported to the person" 'summary\.healed' \
  "Casberi/Casberi/Screens/KindleImportScreen.swift"

# NEGATIVE GUARDS read a COMMENT-STRIPPED copy. Every file here DOCUMENTS what
# it must no longer do by naming it — `KindleImport.swift` explains at length
# that it used to write `content = "Book — Author"` — so a guard grepping raw
# source fires against the prose explaining itself (the Obsidian/Cursor lesson,
# now paid for a fifth time).
strip() { sed -E 's://.*$::' "$1" | sed -E '/^[[:space:]]*\/\/\//d'; }
strip "$KINDLE" > "$TMP/kindle.nc"
strip "$VIEWS"  > "$TMP/views.nc"

# The exact line that destroyed the passage for a month.
absent "the Kindle importer no longer files the book as the body" \
  'content: source,' "$TMP/kindle.nc"
# A ref Set cannot heal — only the map can. Reverting this quietly turns the
# repair off while every other guard above still passes.
absent "the Kindle importer no longer walks a bare ref set" \
  'existingSourceRefs\(context, source: "Kindle"\)' "$TMP/kindle.nc"
# The clamp this pass replaced with a real disclosure.
absent "note prose carries no fixed twelve-line clamp" \
  'lineLimit\(12\)$' "$TMP/views.nc"

# The source set is a literal for speed; the catalog is the authority. A
# `Notes` seat added or renamed without this list fails the build rather than
# silently losing its whole anatomy. Split into offer blocks for the reason
# `social-sheet-selftest.sh` records: `finditer` returns non-overlapping
# matches, so a preceding offer's `name:` swallows the real one.
python3 - "$CATALOG" "$SOURCE" <<'PY' || fail=1
import re, sys
catalog, source = (open(p).read() for p in sys.argv[1:3])
offers = set()
for block in catalog.split("Offer(")[1:]:
    block = block.split("needsSetup")[0]
    name = re.search(r'name:\s*"([^"]+)"', block)
    if name and re.search(r'group:\s*"Notes"', block):
        offers.add(name.group(1))
if not offers:
    print("  \u2717 no catalog Notes seats found — the group was renamed")
    sys.exit(1)
listed = set(re.findall(r'"([^"]+)"', re.search(
    r'static let sources: Set<String> = \[(.*?)\]', source, re.S).group(1)))
missing = offers - listed
if missing:
    print("  \u2717 catalog Notes seats missing from NoteSheetSource.sources: "
          + ", ".join(sorted(missing)))
    sys.exit(1)
# Kindle browses under Reading and Voice has no seat at all — both are notes,
# and both are named here so a rename of either is caught too.
for extra in ("Kindle", "Voice"):
    if extra not in listed:
        print("  \u2717 %s is missing from NoteSheetSource.sources" % extra)
        sys.exit(1)
print("  \u2713 every catalog Notes seat is in NoteSheetSource.sources (%d + Kindle + Voice)"
      % len(offers))
PY

# --- §399: the sheet reads like a note ---------------------------------------
# The photograph §398 landed and nothing drew. Its whole failure mode was
# silence: the pixels were in the store, the row and the sheet both ignored
# them, and only a DIFFERENT entry's day shelf ever showed one.
guard "the entry sheet draws its own photograph" \
  'NoteEntryPhoto\(thing: thing\)' "$VIEW"
guard "and the row does too" 'thing\.previewImageData != nil' \
  "Casberi/Casberi/Screens/ShapedRows.swift"
# `PhotoWell`, never a hand-rolled `Image`: it is the one image view here that
# honours `redactionReasons`, and a private photograph at 220pt surviving into
# the app-switcher snapshot is exactly the leak that guard exists to stop.
guard "the photograph is drawn by the redaction-aware well" \
  'PhotoWell\(thing: thing, size: nil\)' "$VIEWS"

# The two bounded reads, and that the sheet actually asks for them.
guard "the sheet reads the same date in other years" \
  'NoteSheetSource\s*$|otherYears\(of: thing' "$VIEW"
guard "the sheet reads the entries either side" \
  'NoteSheetSource\.neighbours\(of: thing' "$VIEW"
guard "both shelves are drawn" 'NoteOtherYearsList\(rows: otherYears' "$VIEW"
guard "the neighbour doors are drawn" 'NoteNeighbourDoors\(previous:' "$VIEW"
# Bounded, never a walk: one `fetchLimit = 1` read per candidate year, capped.
guard "the other-years read is capped" 'static let yearSpan = 12' "$SOURCE"
guard "each year is a single-row read" 'd\.fetchLimit = 1' "$SOURCE"

# Markdown is a per-source FACT. Rendering Apple Journal's HTML-derived text or
# a hand-typed note as markdown would eat a literal asterisk somebody meant.
guard "markdown is decided per source" \
  'static let markdownSources: Set<String> = \["Day One", "Obsidian"\]' "$SOURCE"
guard "the sheet passes both per-source facts to the renderer" \
  'markdown: prose\.markdown' "$VIEW"
# A tapped wikilink walks THROUGH the sheet's own walker rather than opening a
# second presentation (the one-screen-one-sheet rule, paid for three times).
guard "an inline wikilink resolves before it walks" \
  'NoteLinks\.resolve\(\[target\]' "$VIEW"

# §399's ruling: a note under `You` gets the anatomy, and claims nothing about
# who wrote it.
guard "a kept note reaches the anatomy" 'isKeptNote\(thing\)' "$SOURCE"
guard "…and only when it is a note" \
  'thing\.source == keptSource && thing\.kind == \.note' "$SOURCE"
# NOT by joining `sources`, which the catalog guard below checks against the
# Notes group — `You` is not a catalog seat.
absent "You is not smuggled into the catalog-checked source set" \
  '"Obsidian", "Day One", "Apple Journal", "Apple Notes", "Kindle", "Voice", "You"' "$SOURCE"
# The day shelf excludes SIBLINGS, not the whole source — the old rule hid every
# screenshot, link and voice note from the same day in the room this widened to.
guard "the day shelf excludes same source AND same kind" \
  '\$0\.source == source && \$0\.kind == kind' "$SOURCE"

[[ $fail -eq 0 ]] || { echo "note-sheet-selftest: ✗ drift guard(s) failed"; exit 1; }

# --- the harness ------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

func facts(notes: Bool = true, kind: String = "note",
           cited: Bool = false, named: Bool = false) -> NoteSheet.Facts {
    .init(notes: notes, kind: kind, cited: cited, named: named)
}

print("Shape — the gate is a data test, never a source list")

// A non-notes source gets no note anatomy at all, whatever it carries.
check("a non-notes source has no shape",
      NoteSheet.shape(facts(notes: false, kind: "note")) == nil)

// The three shapes, each reached on the strength of the record alone.
check("a journal entry is an entry", NoteSheet.shape(facts()) == .entry)
check("a voice note is an entry", NoteSheet.shape(facts(kind: "voice")) == .entry)
check("a vault note is a note", NoteSheet.shape(facts(named: true)) == .note)
check("a marked passage is a passage", NoteSheet.shape(facts(cited: true)) == .passage)

// ORDER. A citation outranks a name: a highlight is somebody else's writing
// however the record is filed, and it is the one shape where a date hero would
// put OUR clock on THEIR sentence.
check("a citation outranks a name",
      NoteSheet.shape(facts(cited: true, named: true)) == .passage)
// …and a name outranks the kind, or a vault note leads with a file's
// modification time instead of the name the person gave it.
check("a name outranks the kind",
      NoteSheet.shape(facts(kind: "note", named: true)) == .note)

// Everything else in a notes room keeps the layout it had — an import
// receipt, a folder-picked PDF, a link. Nothing is drawn badly; it is simply
// not a note.
check("a link in a notes room has no note shape",
      NoteSheet.shape(facts(kind: "link")) == nil)
check("a file in a notes room has no note shape",
      NoteSheet.shape(facts(kind: "file")) == nil)
check("a screenshot in a notes room has no note shape",
      NoteSheet.shape(facts(kind: "screenshot")) == nil)

print("")
print("Words and read time")

check("words are whitespace-separated tokens",
      NoteSheet.words(in: "the beauty of the house is immeasurable") == 7)
check("newlines separate words too",
      NoteSheet.words(in: "one\ntwo\n\nthree") == 3)
check("padding does not invent words",
      NoteSheet.words(in: "   one   two   ") == 2)
check("an empty body has no words", NoteSheet.words(in: "   \n  ") == 0)

// The floor. A read-time claim under it is the app padding itself out, and
// nothing on screen can tell you it is wrong.
check("a short note gets no read time", NoteSheet.readMinutes(words: 99) == nil)
check("the floor itself reads", NoteSheet.readMinutes(words: 100) == 1)
check("a long note rounds to whole minutes",
      NoteSheet.readMinutes(words: 1_240) == 6)
// Never zero: a body over the floor always takes at least a minute to say so.
check("a body just over the floor never reads as zero minutes",
      NoteSheet.readMinutes(words: 101) == 1)

print("")
print("The dateline — the identity an entry never stated")

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}
let today = date(2026, 8, 12)
let old = date(2024, 5, 14)

let thisYear = NoteSheet.dateline(date(2026, 5, 14), act: .wrote,
                                  now: today, calendar: cal)
let pastYear = NoteSheet.dateline(old, act: .wrote, now: today, calendar: cal)

// The headline is the DAY, on both — that is what an entry is.
check("the headline names the day",
      thisYear.headline.contains("14") && !thisYear.headline.contains("2026"))
// THE RULE: the year appears only when it isn't this one. A hero that says
// "2026" over something written this morning is the obvious, in the loudest
// slot on the sheet.
check("this year's entry omits the year", !thisYear.detail.contains("2026"))
check("an older entry states its year", pastYear.detail.contains("2024"))
// The act is the verb, and it differs by what the person actually did.
check("a written entry says written", thisYear.detail.contains("written"))
check("a recording says recorded",
      NoteSheet.dateline(old, act: .recorded, now: today, calendar: cal)
        .detail.contains("recorded"))
// The detail carries the time, whatever the locale renders it as — asserted by
// ASSEMBLY, never by a literal, since `Date.FormatStyle` is the reader's own
// (the lesson `social-sheet-selftest.sh` recorded about word order).
check("the detail carries the clock",
      pastYear.detail.contains(old.formatted(date: .omitted, time: .shortened)))

print("")
print("How it landed — the block that replaced one spec row")

func input(shape: NoteSheet.Shape = .entry, source: String = "Day One",
           origin: NoteReception.Origin = .export, act: NoteSheet.Act = .wrote,
           originFile: String? = nil,
           path: String? = nil, words: Int? = nil, clamped: Bool = false,
           editedAt: Date? = nil, markedAt: Date? = nil, siblings: Int? = nil,
           writtenAt: Date? = nil, landedAt: Date? = nil,
           truncatedPassage: Bool = false) -> NoteReception.Input {
    .init(shape: shape, source: source, origin: origin, act: act,
          originFile: originFile,
          path: path, words: words, clamped: clamped, editedAt: editedAt,
          markedAt: markedAt, siblings: siblings, writtenAt: writtenAt,
          landedAt: landedAt, truncatedPassage: truncatedPassage, now: today)
}

// THE HONESTY VALVE — the reading this whole card exists to get right. A body
// we clamped is at LEAST this long, and a bare number over a clamped body
// understates a real note by thousands while looking exactly like a
// measurement.
check("a whole body reports a count",
      NoteReception.compose(input(words: 318))?.readings.first?.text == "318")
check("a clamped body reports a floor",
      NoteReception.compose(input(words: 1_240, clamped: true))?
        .readings.first?.text == "1,240+")
check("a clamped read time is a floor too",
      NoteReception.compose(input(words: 1_240, clamped: true))?
        .readings.last?.text == "6+ min")
check("a whole read time is not",
      NoteReception.compose(input(words: 1_240))?.readings.last?.text == "6 min")

// An absent measurement has no cell. Unchanged from the rule the social block
// keeps, and the only reason any number here can be trusted.
check("no body means no readings",
      NoteReception.compose(input(words: nil))?.readings.isEmpty == true)
check("a short body reports words and no read time",
      NoteReception.compose(input(words: 40))?.readings.count == 1)

// A vault note's own clock, which an entry does not have (an entry's clock is
// its hero).
let edited = NoteReception.compose(input(shape: .note, source: "Obsidian",
                                         origin: .vault, path: "Notes/Legibility.md",
                                         words: 1_240,
                                         editedAt: today.addingTimeInterval(-240)))
check("a vault note states how long since you edited it",
      edited?.readings.last?.text == "4m")
check("an entry has no edited reading",
      NoteReception.compose(input(words: 318, editedAt: today))?
        .readings.contains(where: { $0.noun.contains("edited") }) == false)

// A PASSAGE measures something else entirely. "24 words" says nothing about a
// sentence somebody chose to mark; how many you have marked in that work, and
// when, are the two facts worth stating.
let passage = NoteReception.compose(input(shape: .passage, source: "Kindle",
                                          originFile: "My Clippings.txt",
                                          words: 24, markedAt: old, siblings: 12))
check("a passage reports its siblings", passage?.readings.first?.text == "12")
check("a passage reports when you marked it",
      passage?.readings.count == 2)
check("a passage never reports a word count",
      passage?.readings.contains(where: { $0.noun == "words" }) == false)
check("a lone passage still gets a cell",
      NoteReception.compose(input(shape: .passage, source: "Kindle",
                                  markedAt: old, siblings: 1))?
        .readings.first?.text == "1")

print("")
print("The sentence — three grammars")

check("a vault names the path",
      NoteReception.compose(input(shape: .note, source: "Obsidian", origin: .vault,
                                  path: "Notes/Legibility.md", words: 300))?
        .provenance == "Read from your vault at Notes/Legibility.md.")
check("a vault with no path still says where it read from",
      NoteReception.compose(input(shape: .note, source: "Obsidian", origin: .vault,
                                  words: 300))?
        .provenance == "Read from your Obsidian vault.")
check("a device recording says so",
      NoteReception.compose(input(source: "Voice", origin: .device,
                                  act: .recorded, words: 31))?
        .provenance == "Recorded here, on this device.")
check("an export names the source",
      NoteReception.compose(input(words: 318))?
        .provenance == "From your Day One export.")
check("an export with one named file names the file",
      NoteReception.compose(input(shape: .passage, source: "Kindle",
                                  originFile: "My Clippings.txt", markedAt: old))?
        .provenance == "From My Clippings.txt, written by your Kindle.")

// THE IMPORT CLAUSE. An export brings years of entries in one afternoon, and
// the gap between the two dates is the fact worth stating. Where they agree —
// you wrote it today and it landed today — the clause says nothing and is
// dropped, or the receipt is a form again.
check("an old entry brought in later says when it arrived",
      NoteReception.compose(input(words: 318, writtenAt: old, landedAt: today))?
        .provenance?.contains("Imported") == true)
check("an entry written and landed the same day states no import date",
      NoteReception.compose(input(words: 318, writtenAt: old,
                                  landedAt: old.addingTimeInterval(600)))?
        .provenance?.contains("Imported") == false)
check("a missing landing date drops the clause, not the sentence",
      NoteReception.compose(input(words: 318, writtenAt: old))?
        .provenance == "From your Day One export.")
// A vault and a device never wear it — they were not brought here at all.
check("a vault sentence never carries an import clause",
      NoteReception.compose(input(shape: .note, source: "Obsidian", origin: .vault,
                                  path: "a.md", words: 300,
                                  writtenAt: old, landedAt: today))?
        .provenance?.contains("Imported") == false)

print("")
print("The ceiling — the one stated limit")

check("a passage stored clipped says so",
      NoteReception.compose(input(shape: .passage, source: "Kindle",
                                  markedAt: old, siblings: 3,
                                  truncatedPassage: true))?.ceiling != nil)
check("a whole passage states no limit",
      NoteReception.compose(input(shape: .passage, source: "Kindle",
                                  markedAt: old, siblings: 3))?.ceiling == nil)
// Never anywhere else: saying it over a journal entry would be inventing a
// limitation the record does not have.
check("an entry never states the passage limit",
      NoteReception.compose(input(words: 318, truncatedPassage: true))?.ceiling == nil)

// Nothing honest to say means no card at all — never a spinner, never a zero.
check("a record with nothing to measure and nowhere to be from has no card",
      NoteReception.compose(.init(shape: .entry, source: "", origin: .device,
                                  now: today)) != nil)

print("")
print("Relative time")

check("under a minute is just now",
      NoteSheet.relative(today.addingTimeInterval(-30), now: today) == "just now")
check("minutes", NoteSheet.relative(today.addingTimeInterval(-600), now: today) == "10m")
check("hours", NoteSheet.relative(today.addingTimeInterval(-7_200), now: today) == "2h")
check("days", NoteSheet.relative(today.addingTimeInterval(-259_200), now: today) == "3d")
check("weeks", NoteSheet.relative(today.addingTimeInterval(-1_209_600), now: today) == "2w")
check("years", NoteSheet.relative(today.addingTimeInterval(-63_072_000), now: today) == "2y")
// A clock that ran backwards must not render a negative age.
check("a future date reads as just now",
      NoteSheet.relative(today.addingTimeInterval(600), now: today) == "just now")

print("")
print("")
print("The body's own structure (prd §399)")
// A source whose body is NOT markdown takes no MARKERS, whatever it contains —
// the whole point of the per-source fact. A dash somebody typed is a dash.
check("a non-markdown body takes no markers",
      NoteSheet.blocks("- milk\n- bread", markdown: false) == [.paragraph("- milk\n- bread")])
// …but a blank line ends a paragraph for EVERY source (2026-08-21). The flag
// governs markers, not splitting. Without this the body is one block, `folded`
// has nothing to cut between, and every non-markdown source keeps the
// twelve-line clamp §399 exists to replace — a mutation that reads as a
// harmless simplification and silently disables the fold.
check("a blank line splits a non-markdown body",
      NoteSheet.blocks("First para.\n\nSecond para.", markdown: false)
        == [.paragraph("First para."), .paragraph("Second para.")])
// The departure from CommonMark survives the change: a SINGLE newline is the
// writer's line break and is kept inside the paragraph, not split on.
check("a single newline does not split a non-markdown body",
      NoteSheet.blocks("One line.\nNext line.", markdown: false)
        == [.paragraph("One line.\nNext line.")])
// And the fold can now actually reach a non-markdown body, which is the whole
// point of the split — asserted as the OUTCOME, since the two checks above
// would both pass against a splitter whose blocks nothing ever folds.
check("a long non-markdown body folds",
      NoteSheet.folded(NoteSheet.blocks(
        (0..<40).map { "Paragraph \($0), long enough to count toward the budget." }
            .joined(separator: "\n\n"), markdown: false)).count < 40)
check("an empty body has no blocks", NoteSheet.blocks("   \n\n ", markdown: true).isEmpty)
check("a heading is a heading",
      NoteSheet.blocks("# Monday", markdown: true) == [.heading(level: 1, text: "Monday")])
check("its level is kept", NoteSheet.blocks("### Deep", markdown: true)
      == [.heading(level: 3, text: "Deep")])
// EVERY marker needs a space after it, and this is the whole of its
// correctness: `#hashtag` is Obsidian's own inline tag syntax, landed by that
// ingest, and drawing it as a heading would promote a tag to a title.
check("a hashtag is not a heading",
      NoteSheet.blocks("#legibility matters", markdown: true)
        == [.paragraph("#legibility matters")])
check("seven hashes is not a heading",
      NoteSheet.blocks("####### too deep", markdown: true)
        == [.paragraph("####### too deep")])
check("a bullet is a bullet", NoteSheet.blocks("- milk", markdown: true) == [.bullet("milk")])
check("so are the other two marks",
      NoteSheet.blocks("* milk", markdown: true) == [.bullet("milk")]
        && NoteSheet.blocks("+ milk", markdown: true) == [.bullet("milk")])
check("a negative number is not a bullet",
      NoteSheet.blocks("-5 degrees and falling", markdown: true)
        == [.paragraph("-5 degrees and falling")])
// The index is the one WRITTEN, never a re-count: a list starting at 3 was
// started at 3 on purpose, and renumbering somebody's note is editing it.
check("a numbered item keeps the number it was given",
      NoteSheet.blocks("3. third", markdown: true) == [.numbered(index: 3, text: "third")])
check("a date is not a numbered item",
      NoteSheet.blocks("2019. What a year", markdown: true)
        == [.paragraph("2019. What a year")])
check("a quote is a quote", NoteSheet.blocks("> said Sam", markdown: true) == [.quote("said Sam")])
// THE DEPARTURE FROM COMMONMARK, stated as a test: a journal's line breaks are
// the writer's, and joining them would run an entry into one wall.
check("single newlines stay inside one paragraph",
      NoteSheet.blocks("one\ntwo", markdown: true) == [.paragraph("one\ntwo")])
check("a blank line starts a new block",
      NoteSheet.blocks("one\n\ntwo", markdown: true) == [.paragraph("one"), .paragraph("two")])
// A thematic break draws nothing (no hairlines), so it acts as the break it
// already is rather than printing "---" as a line of prose.
check("a thematic break is not printed",
      NoteSheet.blocks("one\n---\ntwo", markdown: true)
        == [.paragraph("one"), .paragraph("two")])
check("a mixed body splits into its real shapes",
      NoteSheet.blocks("# Monday\n\nWoke late.\n\n- coffee\n- walk", markdown: true)
        == [.heading(level: 1, text: "Monday"), .paragraph("Woke late."),
            .bullet("coffee"), .bullet("walk")])

print("")
print("Fenced code (2026-08-20) — the shape an agent's answer cannot do without")
check("a fence becomes a code block",
      NoteSheet.blocks("```\nlet x = 1\n```", markdown: true)
        == [.code(language: nil, text: "let x = 1")])
check("the info string is kept as a label",
      NoteSheet.blocks("```swift\nlet x = 1\n```", markdown: true)
        == [.code(language: "swift", text: "let x = 1")])
// THE WHOLE REASON THE CASE EXISTS. Inside a fence a `#` is a comment, a `- `
// is a flag and a `> ` is a shell prompt. Without the suspension every one of
// those became a heading, a bullet and a quote — an answer's program silently
// rewritten as prose.
check("markers INSIDE a fence are code, not markdown",
      NoteSheet.blocks("```python\n# TODO: fix\n- flag\n> prompt\n```", markdown: true)
        == [.code(language: "python", text: "# TODO: fix\n- flag\n> prompt")])
// Indentation is the shape of a program, so it survives where prose is trimmed.
check("leading indentation is kept",
      NoteSheet.blocks("```\nif x:\n    go()\n```", markdown: true)
        == [.code(language: nil, text: "if x:\n    go()")])
// A blank line inside a fence is part of the program, not a block break.
check("a blank line inside a fence does not split it",
      NoteSheet.blocks("```\na\n\nb\n```", markdown: true)
        == [.code(language: nil, text: "a\n\nb")])
// NOT AN EDGE CASE — the common one. Transcripts are stored under an
// 8,000-character clamp, so a long answer's last fence is routinely cut
// mid-program, and dropping it deletes what the sheet was opened to read.
check("an UNCLOSED fence still yields its code",
      NoteSheet.blocks("intro\n\n```swift\nlet x = 1", markdown: true)
        == [.paragraph("intro"), .code(language: "swift", text: "let x = 1")])
check("prose before and after a fence stays prose",
      NoteSheet.blocks("try this\n```\nrun()\n```\nthen check", markdown: true)
        == [.paragraph("try this"), .code(language: nil, text: "run()"),
            .paragraph("then check")])
// An inline `code` span must never open a block — one backtick is not a fence.
// The fixture must OPEN with the backtick: "use `let` here" does not start with
// one, so it passes whatever the prefix test says and proves nothing (caught by
// this file's own mutation, which is the third fixture this session to give the
// right answer for the wrong reason).
check("a line OPENING with an inline span is not a fence",
      NoteSheet.blocks("`let` is a binding", markdown: true)
        == [.paragraph("`let` is a binding")])
check("a double backtick is not a fence either",
      NoteSheet.blocks("``x`` means literal", markdown: true)
        == [.paragraph("``x`` means literal")])
// A non-markdown source is untouched: a `You` note that happens to contain
// backticks is whatever somebody typed.
check("a non-markdown body never fences",
      NoteSheet.blocks("```\nx\n```", markdown: false)
        == [.paragraph("```\nx\n```")])
check("an empty fence yields nothing rather than an empty block",
      NoteSheet.blocks("```\n\n```", markdown: true).isEmpty)

print("")
print("The fold cuts at a block, never mid-sentence")
let long = (0..<40).map { "Paragraph number \($0), with enough words in it to matter." }
    .joined(separator: "\n\n")
let longBlocks = NoteSheet.blocks(long, markdown: true)
check("a long body really has many blocks", longBlocks.count == 40)
let shown = NoteSheet.folded(longBlocks)
check("the fold keeps fewer blocks than there are", shown.count < longBlocks.count)
check("every kept block is whole", shown.allSatisfy { longBlocks.contains($0) })
check("a short body is not folded at all",
      NoteSheet.folded(NoteSheet.blocks("Short.", markdown: true)).count == 1)
// Always at least one, so a fold can never show an empty opening — and a
// single block longer than the limit is shown rather than hidden behind a
// disclosure that reveals the only thing there is.
check("one enormous block is still shown",
      NoteSheet.folded([.paragraph(String(repeating: "x", count: 5_000))]).count == 1)
// The boundary that makes "always keep one" load-bearing rather than
// incidental. At the shipped limit the first block is appended before `used`
// can exceed anything, so the guard reads as redundant — at limit 0 it is the
// only thing standing between the reader and a "Read the rest" button with
// nothing above it.
check("even a zero limit shows one block",
      NoteSheet.folded(longBlocks, limit: 0).count == 1)

print("")
print("Wikilinks become links, and only ours are ours")
check("a body with no wikilink is untouched",
      NoteSheet.markdownWithWikilinks("plain words") == "plain words")
check("a bare wikilink becomes a markdown link",
      NoteSheet.markdownWithWikilinks("see [[Other note]]")
        == "see [Other note](casberi-note://Other%20note)")
// The alias split MIRRORS `NoteLinks.extract`, and must: the shelf under the
// note is built from that function, so a different split here draws a link the
// shelf doesn't list.
check("an alias is what the reader sees, the target is where it goes",
      NoteSheet.markdownWithWikilinks("[[Target|Alias]]")
        == "[Alias](casberi-note://Target)")
check("a heading anchor is not part of the target",
      NoteSheet.markdownWithWikilinks("[[Target#Section]]")
        == "[Target](casberi-note://Target)")
check("an empty link is left exactly as written",
      NoteSheet.markdownWithWikilinks("[[]]") == "[[]]")
check("text either side survives",
      NoteSheet.markdownWithWikilinks("a [[One]] b [[Two]] c")
        == "a [One](casberi-note://One) b [Two](casberi-note://Two) c")
// An alias is somebody's own text and may hold a bracket, which ends a markdown
// link early and spills the rest of the URL into the note as visible prose.
//
// `[` and not `]`: the capture is `[^\]]+`, so an alias holding a CLOSING
// bracket is never matched at all and the escaper's `]` case cannot be reached
// from here. It stays in the source as insurance against that pattern changing,
// and is deliberately not asserted — a test that passes because its input never
// reaches the code is the "right result for the wrong reason" class.
check("an opening bracket in an alias is escaped",
      NoteSheet.markdownWithWikilinks("[[T|a[b]]").contains("\\["))
check("…and a wikilink whose alias holds a CLOSING bracket is left alone entirely",
      NoteSheet.markdownWithWikilinks("[[T|a]b]]") == "[[T|a]b]]")
check("our scheme resolves to the note it names",
      NoteSheet.wikiTarget(URL(string: "casberi-note://Other%20note")!) == "Other note")
// NOT `casberi://` — that is the app's real deep-link scheme and `RootShell`
// acts on it, so a note holding a crafted link could otherwise reach a router.
check("the app's own scheme is NOT a wikilink",
      NoteSheet.wikiTarget(URL(string: "casberi://settings")!) == nil)
check("a real URL somebody wrote is not a wikilink",
      NoteSheet.wikiTarget(URL(string: "https://example.com")!) == nil)
check("a hostless one names nothing",
      NoteSheet.wikiTarget(URL(string: "casberi-note://")!) == nil)

print("")
print("What you KEPT, which is neither writing nor recording (prd §399)")
// The ruling §366 deferred: a note shared out of Apple Notes is
// indistinguishable from one typed here, so the verb claims neither.
check("kept is its own verb", NoteSheet.Act.kept.verb == "kept")
check("and it is not written", NoteSheet.Act.kept.verb != NoteSheet.Act.wrote.verb)
let keptLine = NoteSheet.dateline(date(2026, 5, 14), act: .kept, now: date(2026, 6, 1))
check("the dateline says you kept it", keptLine.detail.contains("kept at"))
let keptDevice = NoteReception.compose(.init(
    shape: .entry, source: "You", origin: .device, act: .kept,
    words: 40, writtenAt: date(2026, 5, 14), landedAt: date(2026, 5, 14),
    now: date(2026, 6, 1)))!
check("a kept note is not said to have been recorded",
      keptDevice.provenance == "Kept here, on this device.")
let recorded = NoteReception.compose(.init(
    shape: .entry, source: "Voice", origin: .device, act: .recorded,
    words: 40, writtenAt: date(2026, 5, 14), landedAt: date(2026, 5, 14),
    now: date(2026, 6, 1)))!
check("a voice note still is", recorded.provenance == "Recorded here, on this device.")

if failures > 0 { print("note-sheet-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
SWIFT

if ! swiftc -O -o "$TMP/ns-selftest" "$SHEET" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
echo ""
"$TMP/ns-selftest"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation below is a plausible
# "simplification" of the shipped logic, and each must break at least one
# assertion above.
echo ""
echo "Mutations (each must break something)"

mutate() {
  local name="$1" from="$2" to="$3"
  local a="$TMP/mut.swift"
  cp "$SHEET" "$a"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$a" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$a"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$a" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# THE ORDER. A citation outranking a name is what keeps our clock off somebody
# else's sentence; swapping them is the plausible "tidy" that breaks it.
mutate "a name is checked before a citation" \
  'if f.cited { return .passage }
        if f.named { return .note }' \
  'if f.named { return .note }
        if f.cited { return .passage }'
# A vault note demoted to an entry — it loses the name the person gave it and
# leads with a file modification time instead.
mutate "a vault note falls through to an entry" \
  'if f.named { return .note }' \
  'if f.named && f.kind == "vault" { return .note }'
# The widening reverted: only `.note` kinds get an anatomy, so every voice note
# goes back to a bare title.
mutate "a voice note stops being an entry" \
  'if f.kind == "note" || f.kind == "voice" { return .entry }' \
  'if f.kind == "note" { return .entry }'
# The gate stops being a gate — a link or a file in a notes room would be drawn
# as prose it does not have.
mutate "everything in a notes room becomes an entry" \
  'if f.kind == "note" || f.kind == "voice" { return .entry }' \
  'return .entry'

# THE HONESTY VALVE, both directions. A clamped body reported as a measurement
# is the silent wrong answer this card is most likely to give…
mutate "a clamped body reports a bare count" \
  'let text = i.clamped
                ? "\(words.formatted(.number))+"
                : words.formatted(.number)' \
  'let text = words.formatted(.number)'
# …and its inverse: every count wearing a `+` makes a true measurement look
# like a guess, which is the same fault pointed the other way.
mutate "every count wears a plus" \
  'let text = i.clamped
                ? "\(words.formatted(.number))+"
                : words.formatted(.number)' \
  'let text = "\(words.formatted(.number))+"'
# The read time follows the same rule as the count, and forgetting it is the
# subtler half: "6 min" over a body we clamped is a promise about how long
# something takes that we cannot make.
mutate "a clamped read time loses its plus" \
  'out.append(Reading(text: i.clamped ? "\(minutes)+ min" : "\(minutes) min",' \
  'out.append(Reading(text: "\(minutes) min",'

# THE FLOOR. Without it a twelve-word note claims a minute of reading.
mutate "the read-time floor is removed" \
  'guard words >= readTimeFloor else { return nil }' \
  'guard words >= 0 else { return nil }'
# …and the `max(1, …)` that keeps a body over the floor from reading as zero.
mutate "a read time can round to zero" \
  'return max(1, Int((Double(words) / Double(wordsPerMinute)).rounded()))' \
  'return Int((Double(words) / Double(wordsPerMinute)).rounded())'

# A PASSAGE measuring words — the reading that says nothing about a sentence
# somebody chose to mark, and which would displace the two that do.
mutate "a passage starts counting words" \
  'if i.shape == .passage {' \
  'if false {'

# THE YEAR RULE, both directions. Stating this year is the obvious in the
# loudest slot; omitting an old year makes a 2024 entry read as this week.
mutate "the dateline always states the year" \
  'guard !sameYear else { return Dateline(headline: headline, detail: clause) }' \
  'guard false else { return Dateline(headline: headline, detail: clause) }'
mutate "the dateline never states the year" \
  'guard !sameYear else { return Dateline(headline: headline, detail: clause) }' \
  'guard true else { return Dateline(headline: headline, detail: clause) }'

# THE IMPORT CLAUSE, both directions. Firing when the dates agree turns the
# receipt back into a form reporting both halves of one moment; never firing
# loses the fact that an archive's writing is older than its arrival.
mutate "the import clause fires whenever both dates exist" \
  'guard landed.timeIntervalSince(written) > 86_400 else { return nil }' \
  'guard landed.timeIntervalSince(written) > -1 else { return nil }'
mutate "the import clause never fires" \
  'guard landed.timeIntervalSince(written) > 86_400 else { return nil }' \
  'guard false else { return nil }'

# The vault sentence dropping its path — "Read from your Obsidian vault" is
# true of every note in it and identifies none of them.
mutate "the vault sentence drops its path" \
  'return String(localized: "Read from your vault at \(path).")' \
  'return String(localized: "Read from your Obsidian vault.")'

# The stated ceiling escaping its one case, which would invent a limitation
# every journal entry in the corpus does not have.
mutate "the ceiling escapes the passage shape" \
  'guard i.shape == .passage, i.truncatedPassage else { return nil }' \
  'guard i.truncatedPassage else { return nil }'
# …and disappearing, which leaves a clipped passage claiming to be whole.
mutate "the ceiling never fires" \
  'guard i.shape == .passage, i.truncatedPassage else { return nil }' \
  'guard false else { return nil }'

# NOT MUTATED, deliberately, and worth recording rather than faking: the
# negative age (a device whose clock moved back, a vault file stamped in the
# future) is defended TWICE and no single-line mutation can break it. Removing
# `max(0, …)` leaves `minutes` negative and `minutes < 1` catches it; narrowing
# `minutes < 1` to `minutes == 0` leaves the clamp, which already made it zero.
# Both were tried and both ran green. Two overlapping guards is a fine thing to
# have and a bad thing to claim a test for, so the assertion above documents
# the intent and nothing here pretends to prove it.

echo ""
# §399's block grammar. Each of these renders perfectly and says something the
# note does not.
# THE FENCE SUSPENSION. Disable it and every marker inside a code block starts
# applying again, so an answer's Python `# TODO` becomes a heading and its
# shell `- flag` becomes a bullet — the program silently rewritten as prose.
mutate "markers apply INSIDE a fenced block again" \
  'if fenceLines != nil {' \
  'if false {'

# A clamped transcript's last fence is never closed, so this is the common case
# rather than an edge one: dropping it deletes exactly the part of the answer
# somebody opened the sheet to read.
mutate "an unclosed fence is discarded" \
  'if !text.isEmpty { out.append(.code(language: fenceLanguage, text: text)) }' \
  'if false { out.append(.code(language: fenceLanguage, text: text)) }'

# One backtick is an inline span, not a block opener.
mutate "a single backtick opens a fence" \
  'guard trimmed.hasPrefix("```") else { return (false, nil) }' \
  'guard trimmed.hasPrefix("`") else { return (false, nil) }'

mutate "a marker needs no space, so a hashtag becomes a heading" \
  'if hashes <= 6, rest.hasPrefix(" ") {' \
  'if hashes <= 6 {'
mutate "any depth of hash is a heading" \
  'if hashes <= 6, rest.hasPrefix(" ") {' \
  'if hashes <= 99, rest.hasPrefix(" ") {'
mutate "a numbered item is renumbered from one" \
  'return .numbered(index: index, text: text)' \
  'return .numbered(index: 1, text: text)'
mutate "an unbounded run of digits starts a list" \
  'if !digits.isEmpty, digits.count <= 3, let index = Int(digits) {' \
  'if !digits.isEmpty, let index = Int(digits) {'
# CommonMark's own behaviour, which is wrong for a journal: a body's line breaks
# are the writer's, and joining them runs an entry into one wall.
mutate "single newlines are joined the way CommonMark would" \
  'para.joined(separator: "\n")' \
  'para.joined(separator: " ")'
mutate "a non-markdown body is parsed as markdown anyway" \
  'let takesMarkers = markdown' \
  'let takesMarkers = true'
# The 2026-08-21 split, from the other side: putting the blank-line break back
# under the per-source gate returns every non-markdown body to ONE block, which
# `folded` cannot cut — so the fold silently dies and the twelve-line clamp is
# back everywhere §366 did not reach. It reads as tidying the gate up.
mutate "the blank-line break is gated per source again" \
  'if line.isEmpty { flush(); continue }' \
  'if line.isEmpty && takesMarkers { flush(); continue }'
# A fold that keeps nothing shows an empty opening above a "read the rest".
mutate "the fold can keep no blocks at all" \
  'if !out.isEmpty && used >= limit { break }' \
  'if used >= limit { break }'
mutate "the fold never fires" \
  'if !out.isEmpty && used >= limit { break }' \
  'if false { break }'
# The alias split must mirror `NoteLinks.extract`, or the body draws a link the
# shelf beneath the note does not list.
mutate "a heading anchor is left in the target" \
  '.split(whereSeparator: { $0 == "|" || $0 == "#" })' \
  '.split(separator: "|")'
mutate "an alias bracket is left unescaped" \
  '.replacingOccurrences(of: "[", with: "\\[")' \
  '.replacingOccurrences(of: "[", with: "[")'
# The scheme is the whole containment: `casberi://` is the app's real router.
mutate "wikilinks ride the app's own deep-link scheme" \
  'static let wikiScheme = "casberi-note"' \
  'static let wikiScheme = "casberi"'
mutate "any URL in a note is treated as a wikilink" \
  'guard url.scheme == wikiScheme else { return nil }' \
  'guard url.scheme != nil else { return nil }'
# The §399 ruling itself: a kept note must not claim you wrote it.
mutate "a kept note claims you wrote it" \
  'case .kept:     return String(localized: "kept")' \
  'case .kept:     return String(localized: "written")'
mutate "everything on this device is said to have been recorded" \
  'return i.act == .recorded' \
  'return true'

echo "note-sheet-selftest: OK — assertions and mutations both pass."
