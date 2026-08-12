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
guard "note prose is set at the reading tier" \
  'dsText\(\.reading20\)' "$VIEWS"
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
           origin: NoteReception.Origin = .export, originFile: String? = nil,
           path: String? = nil, words: Int? = nil, clamped: Bool = false,
           editedAt: Date? = nil, markedAt: Date? = nil, siblings: Int? = nil,
           writtenAt: Date? = nil, landedAt: Date? = nil,
           truncatedPassage: Bool = false) -> NoteReception.Input {
    .init(shape: shape, source: source, origin: origin, originFile: originFile,
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
      NoteReception.compose(input(source: "Voice", origin: .device, words: 31))?
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
echo "note-sheet-selftest: OK — assertions and mutations both pass."
