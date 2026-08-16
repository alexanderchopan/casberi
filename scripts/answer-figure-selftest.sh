#!/bin/zsh
# Casberi answer-figure self-test (2026-08-15) — the deterministic figure above
# a free-text answer's prose.
#
#   Casberi/Casberi/Model/AnswerFigure.swift        — compiled WHOLE, unmodified
#   Casberi/Casberi/Model/TodayBrief.swift          — sourceMixLine, faces, ownHandles
#   Casberi/Casberi/Model/KeptAskComposers.swift    — dailyBars, contactSheetLine,
#                                                     runwayAxis, sourceMapLine
#   Casberi/Casberi/Model/SocialBridge.swift        — the person gate (extracted)
#   Casberi/Shared/Thing.swift                      — the receipt rule (extracted)
#   Casberi/Casberi/Shell/RootShell.swift           — drift guards on the call site
#
# THE LADDER GREW FROM TWO RUNGS TO SIX (2026-08-16), which changes what this
# harness has to prove. With two emitters, "the ranking" was one comparison. With
# six it is an ORDER, and an order is only tested by fixtures where the losing
# rungs could also have drawn — so every fixture in the ladder section is one
# that clears several floors at once. Two of the four new rungs
# (`contactSheetLine`, `faces`) were unreachable before this pass, `faces` with
# no caller anywhere, so their floors had never been exercised through any
# caller at all.
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
SOCIAL="Casberi/Casberi/Model/SocialBridge.swift"

for f in "$FIGURE" "$BRIEF" "$COMPOSERS" "$THING" "$ROOTSHELL" "$SOCIAL"; do
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
# The four rungs added 2026-08-16. Each was file-private before that pass and
# `faces` had no caller AT ALL, so re-privatising one is a one-word change that
# silently drops the ladder back to where it started — the answer still paints,
# just never with that figure again.
grep -qE '^\s*static func contactSheetLine\(' "$COMPOSERS" \
  || { print "✗ KeptAskComposers.contactSheetLine is no longer reachable — the pictures rung is dead"; exit 1; }
grep -qE '^\s*static func runwayAxis\(' "$COMPOSERS" \
  || { print "✗ KeptAskComposers.runwayAxis is no longer reachable — the time rung is dead"; exit 1; }
grep -qE '^\s*static func sourceMapLine\(' "$COMPOSERS" \
  || { print "✗ KeptAskComposers.sourceMapLine is no longer reachable — the board rung is dead"; exit 1; }
grep -qE '^\s*static func faces\(' "$BRIEF" \
  || { print "✗ TodayBrief.faces is no longer reachable — the people rung is dead, and this"; \
       print "  figure has already spent one release orphaned with no caller at all."; exit 1; }

# THE DEADLINE FILTER. `runwayAxis` formats a nil `dueAt` as `now`, so handing
# it undated rows draws a rail claiming every match is due this second. The
# filter lives at the call site, one file from the fallback it is correcting —
# the same shape as the bars window, and invisible for the same reason.
grep -q 'rows.filter { $0.dueAt != nil }' "$TMP/figure.nc.swift" \
  || { print "✗ the time rung no longer filters to rows carrying a real deadline —"; \
       print "  runwayAxis formats a nil dueAt as now, so undated matches would pile"; \
       print "  onto the marker and read as all due this instant."; exit 1; }

# ── Extract the shipped logic ───────────────────────────────────────────────
python3 - "$BRIEF" "$COMPOSERS" "$THING" "$TMP/extracted.swift" "$SOCIAL" <<'PY'
import sys
brief, composers, thing, out, social = sys.argv[1:6]

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
    var id = UUID()
    var capturedAt: Date
    var source: String
    var sourceRef: String?
    var isLive: Bool
    var title: String
    var dueAt: Date?
    var previewImageURL: String?
    var imageURLs: [String]
    var authorHandle: String?
    var postAuthor: String?
    var authorAvatarURL: String?
    init(capturedAt: Date, source: String, sourceRef: String? = nil, isLive: Bool = true,
         title: String = "", dueAt: Date? = nil,
         previewImageURL: String? = nil, imageURLs: [String] = [],
         authorHandle: String? = nil, postAuthor: String? = nil,
         authorAvatarURL: String? = nil) {
        self.capturedAt = capturedAt
        self.source = source
        self.sourceRef = sourceRef
        self.isLive = isLive
        self.title = title
        self.dueAt = dueAt
        self.previewImageURL = previewImageURL
        self.imageURLs = imageURLs
        self.authorHandle = authorHandle
        self.postAuthor = postAuthor
        self.authorAvatarURL = authorAvatarURL
    }
}

/// The social stores `ownHandles` reads, inert — no account is marked yours, so
/// the "you are excluded" rule is exercised through the literal "you" the demo
/// stamps. A real store here would make the assertion depend on device state.
struct StubAccount { var username = ""; var handle = ""; var mine = false }
enum FarcasterStore { static let shared = Self.self; static var accounts: [StubAccount] { [] } }
enum BlueskyStore { static let shared = Self.self; static var accounts: [StubAccount] { [] } }

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
    # The person gate, shipped — `faces` refuses a source that names a
    # masthead rather than a human, and that set is maintained in one place for
    # exactly this distinction. A stub here would let the roster drift back to
    # drawing "The Verge" as somebody in your life.
    "enum SocialThread {",
    grabline(social, "static let sources: Set<String>"),
    grabline(social, "static let contextSources: Set<String>"),
    grabline(social, "static func hasContext"),
    "}\n",
    "enum TodayBrief {",
    grab(brief, "static func sourceMixLine"),
    grab(brief, "static func faces"),
    grab(brief, "static func ownHandles"),
    grab(brief, "static func tileSafe"),
    grab(brief, "static func genSafe"),
    "}\n",
    "enum KeptAskComposers {",
    grab(composers, "static func dailyBars"),
    grab(composers, "static func contactSheetLine"),
    grab(composers, "static func runwayAxis"),
    grab(composers, "static func sourceMapLine"),
    grab(composers, "static func mapSafe"),
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
print("the ladder — six rungs, each outranking everything beneath it")

func pic(_ source: String, _ n: Int, _ url: String) -> Thing {
    Thing(capturedAt: daysAgo(n), source: source, previewImageURL: url)
}
func due(_ source: String, _ inDays: Int) -> Thing {
    Thing(capturedAt: daysAgo(1), source: source,
          dueAt: cal.date(byAdding: .day, value: inDays, to: now))
}
func person(_ handle: String, _ n: Int) -> Thing {
    Thing(capturedAt: daysAgo(n), source: "Bluesky",
          authorHandle: handle, authorAvatarURL: "https://x/\(handle).jpg")
}

// 1 — PICTURES. Every fixture in this section is one where the rungs BELOW it
// would also have drawn; a ladder tested on sets only one rung can answer
// proves the floors and nothing about the order.
let shots = [pic("Photos", 1, "a"), pic("Photos", 1, "b"),
             pic("Bluesky", 2, "c"), pic("Bluesky", 2, "d")]
check("four pictures → the sheet leads", comp(AnswerFigure.line(for: shots, now: now)) == "ContactSheet")
check("three pictures → it yields to the rung below",
      comp(AnswerFigure.line(for: Array(shots.prefix(3)), now: now)) != "ContactSheet")
// One picture per THING, deduped by URL: four rows sharing a placeholder are
// one picture, not four — the demo-corpus lesson, asserted through this caller.
let placeholder = (0..<4).map { _ in pic("Photos", 1, "same") }
check("four rows sharing one URL are not four pictures",
      comp(AnswerFigure.line(for: placeholder, now: now)) != "ContactSheet")

// 2 — TIME.
let deadlines = [due("Reminders", 2), due("Stripe", 5), due("Reminders", 9), due("Linear", 12)]
check("dated rows → the rail leads", comp(AnswerFigure.line(for: deadlines, now: now)) == "Runway")
check("one dot per deadline",
      (AnswerFigure.line(for: deadlines, now: now) ?? "").filter { $0 == ";" }.count == 3)
// THE FILTER, and the assertion the guard above cannot make: a single dated row
// among undated ones must not become a four-dot rail with three of them pinned
// to now. `runwayAxis` floors at 2, so the correct answer here is a DIFFERENT
// figure — which is only true if the undated rows never reached it.
let oneDated = [due("Reminders", 2), thing("GitHub", 1), thing("GitHub", 2), thing("Notion", 1)]
check("one deadline among undated rows → no rail at all",
      comp(AnswerFigure.line(for: oneDated, now: now)) != "Runway")

// 3 — PEOPLE.
let people = [person("mira", 1), person("mira", 2), person("sam", 1), person("lena", 3)]
check("three people → the roster leads", comp(AnswerFigure.line(for: people, now: now)) == "Faces")
check("the busiest person leads it",
      (AnswerFigure.line(for: people, now: now) ?? "").contains("mira|"))
// A MASTHEAD IS NOT A PERSON. `authorHandle` is stamped by RSS, Substack,
// Podcasts and YouTube too, where it holds a publication — the roster's gate is
// `SocialThread.hasContext`, extracted from the shipped set rather than stubbed
// so this can't drift back to drawing "The Verge" as somebody in your life.
let bylines = [Thing(capturedAt: daysAgo(1), source: "RSS", authorHandle: "The Verge"),
               Thing(capturedAt: daysAgo(1), source: "RSS", authorHandle: "Ars"),
               Thing(capturedAt: daysAgo(2), source: "Substack", authorHandle: "Platformer"),
               Thing(capturedAt: daysAgo(2), source: "Substack", authorHandle: "Garbage Day")]
check("RSS/Substack bylines are not a roster",
      comp(AnswerFigure.line(for: bylines, now: now)) != "Faces")
// YOU are excluded: every social bridge stamps your own handle on your own
// posts, so an unfiltered roster ranks you first in every corpus.
let withYou = [person("you", 1), person("you", 2), person("mira", 1), person("sam", 2)]
check("your own handle doesn't count toward the roster",
      comp(AnswerFigure.line(for: withYou, now: now)) != "Faces")

// 4/5 — the same question at two scales. This is the eight-row fixture that
// used to test the miniature, moved here: at six hits the board is what should
// answer it, and the cell the miniature had to drop is the proof.
let wide = [thing("Zulip", 1), thing("Zulip", 1), thing("Zulip", 2),
            thing("Apple", 1), thing("Apple", 2),
            thing("Bluesky", 1), thing("Bluesky", 2), thing("Notion", 1)]
let board = AnswerFigure.line(for: wide, now: now) ?? ""
check("six or more hits → the full board", comp(AnswerFigure.line(for: wide, now: now)) == "TagMap")
check("the board keeps the room the miniature dropped", board.contains("Notion 1"))
check("the board's subline is the span of years, ungrouped", !board.contains("2,0"))

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
// FIVE rows, not eight: at six the richer board outranks the miniature (see
// the pair below), so a set large enough to test the mix's own 3-cell cap has
// to stay under the board's floor. The original eight-row fixture moved down
// to the board section, where it now belongs.
let ranked = [thing("Zulip", 1), thing("Zulip", 2),
              thing("Apple", 1), thing("Bluesky", 2), thing("Notion", 1)]
let mix = AnswerFigure.line(for: ranked, now: now) ?? ""
check("the mix draws under the board's floor", comp(AnswerFigure.line(for: ranked, now: now)) == "SourceMix")
check("the biggest room leads", mix.contains("[Zulip 2, "))
check("a tie breaks alphabetically", mix.contains("Zulip 2, Apple 1, Bluesky 1"))
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
# Counted rather than spelled: the summary said "8 mutations" for as long as
# there were eight, and a harness that misreports its own coverage is the shape
# of problem it exists to catch.
MUT_RUN=0
mutate() {  # name, sed-expression over AnswerFigure.swift
  local name="$1" expr="$2"
  MUT_RUN=$((MUT_RUN + 1))
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
# ── The 2026-08-16 rungs. Each renders as a perfectly good figure; what breaks
# is WHICH one, or what it is drawn over.
# The pictures rung demoted: a set of photographs would answer with a treemap of
# the rooms they came from, which is a true sentence about the wrong subject.
mutate "pictures rung skipped" \
  's/^        if let sheet = KeptAskComposers.contactSheetLine(rows) { return sheet }$/        if false, let sheet = KeptAskComposers.contactSheetLine(rows) { return sheet }/'
# THE ONE WITH NO VISIBLE SYMPTOM. Undated rows reach the axis, `runwayAxis`
# formats their nil `dueAt` as `now`, and the rail draws a dot per match piled
# on the marker — a chart claiming everything you matched is due this second.
mutate "the deadline filter dropped" \
  's/let dated = rows.filter { \$0.dueAt != nil }/let dated = rows.filter { _ in true }/'
# The people rung demoted — the roster this pass un-orphaned goes straight back
# to having no caller, and nothing anywhere says so.
mutate "people rung skipped" \
  's/^        if let roster = TodayBrief.faces(rows) { return roster }$/        if false, let roster = TodayBrief.faces(rows) { return roster }/'
# The two WHERE scales swapped: the miniature would answer sets big enough for
# the board, silently dropping every room past the third.
mutate "the miniature ranked above the board" \
  's/^        if let board = KeptAskComposers.sourceMapLine(rows) { return board }$/        if false, let board = KeptAskComposers.sourceMapLine(rows) { return board }/'
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
  print "✓ answer-figure self-test: assertions + $MUT_RUN mutations all held"
else
  print "✗ answer-figure self-test: $MUT mutation(s) not caught"
  exit 1
fi
