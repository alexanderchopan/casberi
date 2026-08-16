#!/bin/zsh
# Casberi answer-figure self-test (2026-08-15) — the deterministic figure above
# a free-text answer's prose.
#
#   Casberi/Casberi/Model/AnswerFigure.swift        — compiled WHOLE, unmodified
#   Casberi/Casberi/Model/TodayBrief.swift          — sourceMixLine (extracted)
#   Casberi/Casberi/Model/KeptAskComposers.swift    — dailyBars (extracted)
#   Casberi/Shared/Thing.swift                      — the receipt rule (extracted)
#   Casberi/Casberi/Shell/RootShell.swift           — drift guards on the call site
#
# WHY A HARNESS. Every failure this feature can have renders as a perfectly
# good-looking answer, and three of them render as a perfectly good-looking
# CHART:
#
#   • THE ALL-ZERO SKYLINE. `dailyBars` charts the last seven days and floors on
#     the total count of what it is HANDED. Over an imported archive a retrieval
#     returns forty rows dated 2015: the floor passes and all seven columns draw
#     at zero, which reads as a broken card rather than an honest nothing —
#     `KeptAskComposers.archiveRecap` documents exactly that rendering as its
#     reason for carrying no bars at all. The window filter that prevents it
#     lives in `AnswerFigure`, one file away from the floor it is correcting, so
#     nothing but this connects the two.
#   • A FIGURE THAT SILENTLY NEVER APPEARS. Both emitters return nil on their
#     own terms, and a nil figure is indistinguishable from the answer shape we
#     had yesterday. A floor that drifts up, a ranking that always picks the
#     one that declined, an eyebrow that stops being passed — every one of those
#     is invisible, and the answer still paints.
#   • A CORRUPTED ROOT. The splice is string surgery on `root = Stack([…])`. Get
#     it wrong and `GenParser` drops the whole document, so the answer that
#     gains a chart loses its prose AND its grounding rows.
#   • THE MODEL REACHING THE DSL. The figure must be chosen and built before any
#     model call, from `capturedAt`/`source` alone. A refactor that computes it
#     after the await hands a model-shaped path to a component grammar — and a
#     chart whose numbers came from a language model is a wrong number nobody
#     can see is wrong.
#
# None of this is visible to `xcodebuild`, to the static audits, or to a screen
# sweep — and the free-text tail needs Apple Intelligence to reach the synthesis
# branch at all, which the simulator does not have, so no sim run exercises one
# line of it either. This harness is the only proof these numbers are right.
#
# The two emitters are EXTRACTED FROM THE SHIPPED SOURCE, never copied, so the
# floors asserted below are the real ones. `AnswerFigure` compiles whole against
# an inert `Thing` — the assertions are its own ranking and window arithmetic,
# and cannot be a SwiftData accident.
#
# WHAT IT CANNOT SEE: whether `GenSourceMix`/`GenBars` still RENDER what these
# lines describe (that is the renderer's own grammar, and `SourceMix` had no
# emitter at all between §386g and this pass), and whether the figure is the one
# a person would want — only that it is true of the rows it was drawn from.
#
# Pure, local, deterministic — no build, no network, no simulator. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FIGURE="Casberi/Casberi/Model/AnswerFigure.swift"
BRIEF="Casberi/Casberi/Model/TodayBrief.swift"
COMPOSERS="Casberi/Casberi/Model/KeptAskComposers.swift"
THING="Casberi/Shared/Thing.swift"
ROOTSHELL="Casberi/Casberi/Shell/RootShell.swift"

for f in "$FIGURE" "$BRIEF" "$COMPOSERS" "$THING" "$ROOTSHELL"; do
  [[ -f "$f" ]] || { print "✗ missing source $f"; exit 1; }
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/casberi-answerfigure.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# ── Drift guards on the wiring the compiled functions cannot prove ──────────
#
# Negative guards read a COMMENT-STRIPPED copy: `AnswerFigure.swift` documents
# these rules by naming the very things it must not do, so a guard grepping raw
# source fires on the prose explaining it (the Obsidian/Cursor lesson).
python3 - "$ROOTSHELL" "$TMP/rootshell.nc.swift" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
src = re.sub(r"//[^\n]*", "", src)
open(sys.argv[2], "w", encoding="utf-8").write(src)
PY
NC="$TMP/rootshell.nc.swift"

# THE ORDERING GUARD, and the reason it is the first check here. The figure is
# computed from `hits` BEFORE `streamSynthesis` is awaited. That single fact is
# what keeps two separate promises: the model never influences the figure, and
# no `Thing` is read across a suspension (corollary 6 — the class that crashed
# build 250 in this very file). Assert the `let figure` line precedes the
# `await streamSynthesis` of the same branch.
FIG_LINE=$(grep -n 'let figure = AnswerFigure.line(for: hits)' "$NC" | head -1 | cut -d: -f1 || true)
[[ -n "$FIG_LINE" ]] \
  || { print "✗ the free-text tail no longer composes a figure over its retrieved set"; exit 1; }
AWAIT_LINE=$(awk -v s="$FIG_LINE" 'NR > s && /await streamSynthesis/ { print NR; exit }' "$NC" || true)
[[ -n "$AWAIT_LINE" ]] \
  || { print "✗ could not find the synthesis await after the figure — the call site moved"; exit 1; }
(( FIG_LINE < AWAIT_LINE )) \
  || { print "✗ the figure is composed AFTER the model call. Two things break at once:"; \
       print "  a Thing read across that suspension is build 250's crash class, and"; \
       print "  the figure is no longer provably independent of what the model wrote."; exit 1; }

# The streaming painter must carry the figure too, or it pops in only once the
# typewriter settles — and the partials would paint a document whose shape
# changes under the reader at the last frame.
grep -q 'onProseDoc: { onProseDoc(AnswerFigure.prepending(figure, to: \$0)) }' "$NC" \
  || { print "✗ the streamed partials no longer carry the figure — it would appear only at the end"; exit 1; }
# …and the settled document.
grep -q 'AnswerFigure.prepending(figure, to: proseDoc(prose))' "$NC" \
  || { print "✗ the settled synthesis document no longer carries the figure"; exit 1; }

# THE DSL GUARD. `AnswerFigure` may read the rows and nothing else: no query, no
# prose, no model. A parameter of any of those shapes is the refactor this
# harness exists to stop.
python3 - "$FIGURE" "$TMP/figure.nc.swift" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
src = re.sub(r"//[^\n]*", "", src)
src = re.sub(r"^\s*///[^\n]*$", "", src, flags=re.M)
open(sys.argv[2], "w", encoding="utf-8").write(src)
PY
for forbidden in 'OnDeviceModel' 'AgentAnswer' 'AnswerTools' 'prose' 'query'; do
  grep -q "$forbidden" "$TMP/figure.nc.swift" \
    && { print "✗ AnswerFigure now names \`$forbidden\` — the figure must be the app's own"; \
         print "  arithmetic over the retrieved rows, never anything the model produced."; exit 1; }
done

# Both emitters must still be reachable. They were file-private until this pass;
# a tidy-up that re-privatises either one breaks the build, but a tidy-up that
# DELETES the now-single caller of `sourceMixLine` and re-privatises it would
# not — it would just make this figure permanently a bar chart.
grep -qE '^\s*static func sourceMixLine\(' "$BRIEF" \
  || { print "✗ TodayBrief.sourceMixLine is no longer reachable — the mix half is dead"; exit 1; }
grep -qE '^\s*static func dailyBars\(' "$COMPOSERS" \
  || { print "✗ KeptAskComposers.dailyBars is no longer reachable — the bars half is dead"; exit 1; }

# ── Extract the shipped logic ───────────────────────────────────────────────
python3 - "$BRIEF" "$COMPOSERS" "$THING" "$TMP/extracted.swift" <<'PY'
import sys
brief, composers, thing, out = sys.argv[1:5]

def grab(path, signature):
    """The whole declaration whose line contains `signature`, brace-matched
    from the shipped source. Never a copy."""
    src = open(path, encoding="utf-8").read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                break
        k += 1
    return src[start:k + 1].replace("private ", "")

def grabline(path, signature):
    """A one-line declaration — `grab` brace-matches from the next `{`, which on
    a closure-less constant swallows the following function (the x-selftest
    trap, recorded there and paid for again here)."""
    src = open(path, encoding="utf-8").read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    end = src.index("\n", i)
    return src[start:end].replace("private ", "")

pieces = [
    "import Foundation\n",
    # An inert Thing: the two fields both figures read, plus the two the
    # shipped receipt rule reads. No SwiftData, so every ordering asserted
    # below is the emitters' own and cannot be a model-graph accident.
    """
final class Thing {
    var capturedAt: Date
    var source: String
    var sourceRef: String?
    var isLive: Bool
    init(capturedAt: Date, source: String, sourceRef: String? = nil, isLive: Bool = true) {
        self.capturedAt = capturedAt
        self.source = source
        self.sourceRef = sourceRef
        self.isLive = isLive
    }
}

extension Array where Element == Thing {
    var live: [Thing] { filter(\\.isLive) }
}
""",
    # The receipt rule, shipped — so "every aggregate excludes the app talking
    # about itself" is tested against the real predicate, not a stand-in.
    "enum Corpus {",
    grabline(thing, "static let bulkImportSources"),
    grab(thing, "static func importReceiptRef"),
    grab(thing, "static func isImportReceipt"),
    "}\n",
    "enum TodayBrief {",
    grab(brief, "static func sourceMixLine"),
    grab(brief, "static func tileSafe"),
    grab(brief, "static func genSafe"),
    "}\n",
    "enum KeptAskComposers {",
    grab(composers, "static func dailyBars"),
    grab(composers, "static func genSafe"),
    "}\n",
]
open(out, "w", encoding="utf-8").write("\n".join(pieces))
PY

# ── The driver ──────────────────────────────────────────────────────────────
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

// `AnswerFigure.line` is `@MainActor` (it reads live `Thing`s, and both
// emitters are), so the whole driver runs there. Top-level code in a plain
// swiftc script is NOT main-actor-isolated — hence the explicit hop rather
// than a bare call, which is a compile error and reads like a broken harness.
@MainActor
func runChecks() -> Int {
var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

let cal = Calendar.current
let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 14)) ?? Date()
func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now) ?? now }

func thing(_ source: String, _ n: Int) -> Thing { Thing(capturedAt: daysAgo(n), source: source) }
func receipt(_ source: String, _ n: Int) -> Thing {
    Thing(capturedAt: daysAgo(n), source: source,
          sourceRef: Corpus.importReceiptRef(source: source))
}

/// The component a line draws, for assertions that care about WHICH figure won.
func comp(_ line: String?) -> String {
    guard let line, let open = line.firstIndex(of: "("),
          let eq = line.range(of: " = ") else { return "none" }
    return String(line[eq.upperBound..<open])
}

print("the ranking — WHERE leads, WHEN follows (§247: when is the weakest lead)")
// Two sources, four rows, all inside the bars window: BOTH emitters would
// draw, and the mix must win. This is the assertion the whole ranking rests
// on, so it is deliberately a case where the loser could have drawn.
let both = [thing("Bluesky", 1), thing("Bluesky", 2), thing("GitHub", 1), thing("GitHub", 3)]
check("both eligible → the mix draws", comp(AnswerFigure.line(for: both, now: now)) == "SourceMix")
check("the mix names the rooms",
      AnswerFigure.line(for: both, now: now)?.contains("Bluesky 2") == true)
check("the eyebrow says 'these', never 'today'",
      AnswerFigure.line(for: both, now: now)?.contains("Where these came from") == true)

// One source: the mix declines on its own ≥2-sources floor, and WHEN is the
// only true thing left.
let oneRoom = [thing("GitHub", 0), thing("GitHub", 1), thing("GitHub", 2), thing("GitHub", 4)]
check("one room → the bars draw", comp(AnswerFigure.line(for: oneRoom, now: now)) == "Bars")
check("the bars eyebrow says 'these' too",
      AnswerFigure.line(for: oneRoom, now: now)?.contains("When these landed") == true)

print("")
print("the floors are the EMITTERS' own — this file adds none")
// sourceMixLine: ≥2 sources AND ≥4 rows. Three rows across two rooms clears
// the source floor and fails the count floor, and bars fails on the same
// count — so the answer is no figure, never a smaller one.
let thin = [thing("Bluesky", 1), thing("GitHub", 1), thing("GitHub", 2)]
check("3 rows over 2 rooms → no figure at all", AnswerFigure.line(for: thin, now: now) == nil)
check("an empty set → no figure", AnswerFigure.line(for: [], now: now) == nil)
// Four rows in ONE room, none of them recent: mix declines on sources, bars
// declines because the window holds nothing. Two declines is silence.
let oldOneRoom = [thing("X", 400), thing("X", 800), thing("X", 1200), thing("X", 2000)]
check("one room, all old → no figure", AnswerFigure.line(for: oldOneRoom, now: now) == nil)

print("")
print("THE ALL-ZERO SKYLINE — the window filter this file adds")
// The failure the window filter exists for: an archive retrieval clears
// `dailyBars`' total-count floor with every column at zero. One room (so the
// mix is out of the way) and forty rows dated years back.
let archive = (1...40).map { thing("X", 300 + $0 * 10) }
check("40 archive rows, one room → no chart (not seven empty columns)",
      AnswerFigure.line(for: archive, now: now) == nil)
// The counterfactual, and it is what proves the filter is load-bearing rather
// than incidental: hand the SAME rows straight to the emitter, as the shipped
// code would if the filter were dropped, and it draws — all zeros.
let unfiltered = KeptAskComposers.dailyBars(archive, eyebrow: "When these landed")
check("…while the emitter alone WOULD have drawn one", unfiltered != nil)
check("…and every one of its columns is zero",
      unfiltered?.contains("\"0,0,0,0,0,0,0\"") == true)
// The boundary: the window is seven days INCLUSIVE of today, so a row from
// six days ago counts and one from eight does not.
let edge = [thing("X", 0), thing("X", 6), thing("X", 6), thing("X", 6), thing("X", 8), thing("X", 40)]
check("a 6-day-old row is inside the window (4 in → the chart draws)",
      comp(AnswerFigure.line(for: edge, now: now)) == "Bars")
let overEdge = [thing("X", 0), thing("X", 6), thing("X", 6), thing("X", 8), thing("X", 9)]
check("an 8-day-old row is outside it (3 in → the chart declines)",
      AnswerFigure.line(for: overEdge, now: now) == nil)
// The exact boundary, and it is the assertion that pins the window to the
// emitter's own: `dailyBars` accepts a day delta of 0…6, so a row from seven
// days ago is one day past the last column it can draw. A window even a day
// wider lets that row clear the floor and then contribute to nothing.
let sevenEdge = [thing("X", 0), thing("X", 6), thing("X", 6), thing("X", 7)]
check("a 7-day-old row is one day too old (3 in → the chart declines)",
      AnswerFigure.line(for: sevenEdge, now: now) == nil)

print("")
print("the exclusions at the boundary")
// The app talking about itself is excluded from every aggregate here — and it
// must be excluded before the FLOOR, or a receipt is what tips a 3-row set
// over the line into a figure that counts it.
let withReceipt = [thing("X", 1), thing("X", 2), thing("X", 3), receipt("X", 1)]
check("an import receipt doesn't tip the count floor",
      AnswerFigure.line(for: withReceipt, now: now) == nil)
let receiptRoom = [thing("X", 1), thing("X", 2), thing("X", 3), thing("X", 4),
                   receipt("Instagram", 1)]
check("a receipt doesn't count as a second room either",
      comp(AnswerFigure.line(for: receiptRoom, now: now)) == "Bars")
// A row deleted between retrieval and compose is dropped, not read. (In the
// app that is a tombstoned `Thing`; here `isLive` is the same switch.)
let dead = [thing("Bluesky", 1), thing("GitHub", 1), thing("GitHub", 2),
            Thing(capturedAt: daysAgo(1), source: "Bluesky", isLive: false)]
check("a dead row is dropped before the floor", AnswerFigure.line(for: dead, now: now) == nil)

print("")
print("the mix's own ordering, through this caller")
// Biggest first with the alphabetical tie, and capped at three cells — the
// emitter's rules, asserted here because this caller is now its only one.
let ranked = [thing("Zulip", 1), thing("Zulip", 1), thing("Zulip", 2),
              thing("Apple", 1), thing("Apple", 2),
              thing("Bluesky", 1), thing("Bluesky", 2),
              thing("Notion", 1)]
let mix = AnswerFigure.line(for: ranked, now: now) ?? ""
check("the biggest room leads", mix.contains("[Zulip 3, "))
check("a tie breaks alphabetically", mix.contains("Zulip 3, Apple 2, Bluesky 2"))
check("the fourth room is left out", !mix.contains("Notion"))

print("")
print("the splice — first child of the root, and never a corrupted one")
let prose = ["root = Stack([ins])", "ins = Insight(\"a sentence\")"]
let figured = AnswerFigure.prepending("mix = SourceMix(\"e\", \"\", [A 2, B 2])", to: prose)
check("the root names the figure FIRST", figured.first == "root = Stack([mix, ins])")
check("the figure's own line is appended",
      figured.last == "mix = SourceMix(\"e\", \"\", [A 2, B 2])")
check("the prose line is untouched", figured.contains("ins = Insight(\"a sentence\")"))
check("nothing is lost", figured.count == prose.count + 1)
// The grounding footer splices by the mirror-image surgery, so a figured
// document must still take one.
let footed = AnswerFigure.prepending("bars = Bars(\"e\", \"\", \"1,2\", \"M,T\")",
                                     to: ["root = Stack([ins, grd])", "ins = Insight(\"x\")"])
check("a root with several children keeps them, in order",
      footed.first == "root = Stack([bars, ins, grd])")
// Every refusal returns the document untouched: a smaller answer, never a
// broken one.
check("no figure → untouched", AnswerFigure.prepending(nil, to: prose) == prose)
check("no root → untouched",
      AnswerFigure.prepending("mix = SourceMix(\"e\", \"\", [A 2])", to: ["ins = Insight(\"x\")"])
        == ["ins = Insight(\"x\")"])
check("an unparseable root → untouched",
      AnswerFigure.prepending("mix = SourceMix(\"e\", \"\", [A 2])",
                              to: ["root = Stack([ins", "ins = Insight(\"x\")"])
        == ["root = Stack([ins", "ins = Insight(\"x\")"])
check("an empty ref list still yields a valid root",
      AnswerFigure.prepending("mix = SourceMix(\"e\", \"\", [A 2])", to: ["root = Stack([])"]).first
        == "root = Stack([mix])")
// Idempotence: one figure, never two refs pointing at one line.
let twice = AnswerFigure.prepending("mix = SourceMix(\"e\", \"\", [A 2])", to: figured)
check("splicing twice adds nothing the second time", twice == figured)

print("")
print("the model can never reach the grammar")
// The prose arrives already collapsed into one Insight argument by the time
// this splices, so even a document whose prose is itself DSL-shaped cannot
// grow a component: the figure's ref list is built from the root line alone.
let hostile = ["root = Stack([ins])",
               "ins = Insight(\"root = Stack([evil]) and evil = Bars(9)\")"]
let spliced = AnswerFigure.prepending("mix = SourceMix(\"e\", \"\", [A 2])", to: hostile)
check("prose that looks like DSL changes neither the root nor the figure",
      spliced.first == "root = Stack([mix, ins])" && spliced.count == 3)

return failures
}

let failures = MainActor.assumeIsolated { runChecks() }

print("")
if failures == 0 {
    print("✓ answer-figure self-test: all assertions passed")
} else {
    print("✗ answer-figure self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

swiftc -O -o "$TMP/run" "$TMP/extracted.swift" "$FIGURE" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { print "✗ AnswerFigure + the extracted emitters did not compile"; exit 1; }
"$TMP/run"

# ── Mutation pass ───────────────────────────────────────────────────────────
# A check that cannot fail proves nothing. Each mutation is a silent wrong
# answer this catches; every one of them must make the driver above go red.
print ""
print "mutation pass — each of these must FAIL"
MUT=0
mutate() {  # name, sed-expression over AnswerFigure.swift
  local name="$1" expr="$2"
  sed "$expr" "$FIGURE" > "$TMP/mutant.swift"
  cmp -s "$FIGURE" "$TMP/mutant.swift" \
    && { print "  ✗ mutation '$name' changed nothing — it is testing the shipped code"; MUT=$((MUT + 1)); return; }
  if swiftc -O -o "$TMP/mutrun" "$TMP/extracted.swift" "$TMP/mutant.swift" "$TMP/main.swift" >/dev/null 2>&1 \
     && "$TMP/mutrun" >/dev/null 2>&1; then
    print "  ✗ mutation '$name' SURVIVED — the assertions do not cover it"
    MUT=$((MUT + 1))
  else
    print "  ✓ mutation '$name' caught"
  fi
}

# The one this file exists for: drop the window filter and the archive draws a
# skyline of zeros.
mutate "window filter dropped (the all-zero skyline)" \
  's/let recent = rows.filter { \$0.capturedAt >= cutoff }/let recent = rows/'
# The ranking inverted — WHEN would lead, and a set spanning two rooms and two
# years would answer with an empty week.
mutate "bars ranked above the mix" \
  's/^        if let mix = TodayBrief.sourceMixLine($/        if false, let mix = TodayBrief.sourceMixLine(/'
# The window widened by one day: an 8-day-old row starts counting, which is the
# boundary that decides whether a chart draws at all.
mutate "window widened to 8 days" 's/static let barsWindowDays = 7/static let barsWindowDays = 8/'
# Receipts counted — the app talking about itself tips a floor and takes a cell.
mutate "import receipts no longer excluded" \
  's/let rows = hits.live.filter { !Corpus.isImportReceipt(\$0) }/let rows = hits.live/'
# Dead rows read.
mutate "dead rows no longer dropped" 's/hits.live.filter/hits.filter/'
# The splice appending instead of prepending — the figure would land UNDER the
# grounding rows, below the fold of every answer.
mutate "figure spliced last instead of first" \
  's/out\[i\] = rootPrefix + (inner.isEmpty ? ref : ref + ", " + inner) + "\])"/out[i] = rootPrefix + (inner.isEmpty ? ref : inner + ", " + ref) + "])"/'
# The root guard removed: a malformed root would be rewritten into a broken one
# rather than left alone, and GenParser drops the whole document.
mutate "the root's closing-bracket guard removed" 's/doc\[i\].hasSuffix("\])")/true/'
# Idempotence lost.
mutate "the duplicate-ref guard removed" \
  's/!doc.contains(where: { \$0.hasPrefix(ref + " = ") })/true/'

print ""
if (( MUT == 0 )); then
  print "✓ answer-figure self-test: assertions + 8 mutations all held"
else
  print "✗ answer-figure self-test: $MUT mutation(s) not caught"
  exit 1
fi
