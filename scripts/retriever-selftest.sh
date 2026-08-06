#!/bin/zsh
# Casberi retriever self-test — verifies the SHIPPED ranking engine behind
# every free-text ask (prd §318, 2026-08-06):
#
#   Casberi/Casberi/Model/Retriever.swift
#     — rank            (the whole engine, compiled AS SHIPPED against stubs)
#     — idfWeight       (a term's rarity weight: "Lisbon" pulls harder than "work")
#     — coverageFactor  (a thing matching one of four query words is demoted)
#     — matchWindow     (the model's snippet centers on the passage that MATCHED)
#     — contentTerms    (the query's content words, sharing rank's own stop set)
#
# WHY A HARNESS. The complaint these changes answer — "search gives general
# answers" — is the class that renders perfectly: a grounding set diluted by
# one-common-word matches still paints 16 plausible rows, and the model's
# general prose over them still reads as an answer. No build, screen sweep or
# probe can see a RANKING be wrong; only fixtures with a known right order can.
#
# HOW `rank` COMPILES AT ALL. It takes `[Thing]`, a SwiftData model, and calls
# five app types. The ENTIRE `Retriever` enum is extracted from the shipped
# source — never copied — and compiled against minimal STUBS of those types
# (below). The stubs are deliberately inert: `SemanticExpand` returns no
# synonyms and `EmbeddingIndex` refuses to embed, so every ordering asserted
# here is the KEYWORD engine's alone and cannot be an embedding accident. If
# `rank` starts reading a property or calling a function the stubs don't have,
# the compile FAILS LOUDLY rather than asserting nothing — which is the point.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

RETRIEVER="Casberi/Casberi/Model/Retriever.swift"
ROOTSHELL="Casberi/Casberi/Shell/RootShell.swift"
for f in "$RETRIEVER" "$ROOTSHELL"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled engine can't prove about its CALLERS. A perfect
# `matchWindow` is worthless if the snippet path never hands it the query's
# terms — the model then reads the head-300 characters exactly as before.

grep -q 'Retriever.matchWindow(in: squeezed, terms: terms)' "$ROOTSHELL" \
  || { echo "✗ answerSnippet no longer centers on the match — the model reads the head-300 again"; exit 1; }
grep -q 'Retriever.contentTerms(query)' "$ROOTSHELL" \
  || { echo "✗ no call site hands the snippet its query terms — matchWindow never runs"; exit 1; }
# The honesty rail, unchanged by this pass and easy to lose in a rescore: a
# thing with NO keyword evidence may only answer on a STRONG semantic match.
grep -q 'score > 0 || sim >= semanticQualifyFloor' "$RETRIEVER" \
  || { echo "✗ the semantic qualify floor is gone — loosely-related things can answer alone"; exit 1; }

TMP=$(mktemp -d /tmp/retriever-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- extract the shipped engine --------------------------------------------
python3 - "$RETRIEVER" "$TMP/extracted.swift" <<'PY'
import sys
retriever, out = sys.argv[1:3]
src = open(retriever).read()

def grab(signature):
    """The whole declaration whose line contains `signature`, brace-matched
    from the shipped source. Never a copy."""
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {retriever}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1]

# The whole enum: rank, its filters, the scoring primitives and the stop set,
# exactly as the app runs them.
open(out, "w").write("import Foundation\nimport NaturalLanguage\n\n"
                     + grab("enum Retriever {").replace("private ", "") + "\n")
PY

# --- stubs ------------------------------------------------------------------
# The app types `rank` reaches for. Inert BY DESIGN: no synonyms, no embedding,
# so every ordering asserted below is the keyword engine's own.
cat > "$TMP/stubs.swift" <<'SWIFT'
import Foundation
import NaturalLanguage

enum ThingKind: String, CaseIterable {
    case note, screenshot, link, chat
    var typeTag: String {
        switch self {
        case .note: return "Note"; case .screenshot: return "Screenshot"
        case .link: return "Link"; case .chat: return "Chat"
        }
    }
    var typeTagPlural: String { typeTag + "s" }
}

final class Thing {
    var title: String
    var content: String
    var enrichedText: String?
    var tags: [String]
    var source: String
    var kind: ThingKind
    var capturedAt: Date
    var embedding: Data?
    init(title: String, content: String = "", enrichedText: String? = nil,
         tags: [String] = [], source: String = "You", kind: ThingKind = .note,
         capturedAt: Date = Date(timeIntervalSince1970: 1_750_000_000)) {
        self.title = title; self.content = content; self.enrichedText = enrichedText
        self.tags = tags; self.source = source; self.kind = kind
        self.capturedAt = capturedAt; self.embedding = nil
    }
}

enum DateQuery {
    struct Match { let range: ClosedRange<Date>; let words: Set<String> }
    // Inert: no fixture here asks a WHEN question, and a live date parse would
    // make these assertions depend on the day they run.
    static func match(in query: String) -> Match? { nil }
}

enum SemanticExpand {
    // Inert: NLEmbedding's neighbours differ by OS build, so a synonym landing
    // in the middle of a ranking fixture would make this harness flaky and its
    // failures unreadable. Every ordering below is exact-keyword evidence.
    static func expand(_ terms: [String]) -> Set<String> { [] }
}

enum EmbeddingIndex {
    // Refuses to embed, so the semantic branch never runs.
    static func queryVector(for text: String) -> (vector: [Float], language: NLLanguage)? { nil }
    static func norm(_ v: [Float]) -> Float { 0 }
    static func similarity(query: [Float], queryNorm: Float, packed: Data,
                           language: NLLanguage) -> Double { 0 }
}

enum BridgeCatalog {
    struct Offer { let name: String }
    static var offers: [Offer] { [Offer(name: "Photos"), Offer(name: "Files"),
                                  Offer(name: "Apple Health"), Offer(name: "Apple Music")] }
}
SWIFT

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
// Competing fixtures share one timestamp so the freshness bonus cancels and
// an ordering assertion is about SCORE, never about which was built first.
func rank(_ q: String, _ corpus: [Thing]) -> [String] {
    Retriever.rank(q, in: corpus, isPoolRefinement: false).map(\.title)
}
// Rank position, or a sentinel — never a force unwrap. A fixture that grows
// past the top-16 cap drops its own tail, and `firstIndex(of:)!` on a dropped
// title TRAPS: the harness then dies with no output at all, which reads as a
// broken engine rather than a broken test. (Paid for on this file's first run.)
func place(_ title: String, _ order: [String]) -> Int {
    order.firstIndex(of: title) ?? Int.max
}

print("coverage — matching more of the query wins (the 'general answers' fix)")
// The reported complaint, as a fixture: OR-semantics let a thing sharing ONE
// common word ride into the grounding set beside one that answers the whole
// question, and the model then synthesized over the pile.
let all4 = Thing(title: "Pasta recipe from the Lisbon trip")
let one4 = Thing(title: "Notes from the trip")
let two4 = Thing(title: "Lisbon trip planning")
let order = rank("pasta recipe lisbon trip", [one4, two4, all4])
check("the thing answering the whole query leads", order.first == all4.title)
check("more coverage outranks less", place(two4.title, order) < place(one4.title, order))
// The complaint itself, isolated. `ride` says ONE query word — but says it in
// its title AND its tags AND its body, which is the maximum a single term can
// score (3+2+1). `spread` says THREE of the four words, and only in passing in
// its body (1 each). Under the old OR-semantics the one-word ride won 6 to 3
// and took the grounding slot; coverage is what reverses it. The three
// preceding fixtures could NOT prove this — there, raw hit counts already
// ordered things correctly, so deleting coverage changed nothing and the
// mutation survived (this harness's own second finding).
let ride = Thing(title: "Trip", content: "trip notes", tags: ["Trip"])
let spread = Thing(title: "Untitled", content: "pasta recipe from lisbon")
let byCoverage = rank("pasta recipe lisbon trip", [ride, spread])
check("three words in passing beat one word said everywhere",
      byCoverage.first == spread.title)

print("rarity — a distinctive word pulls harder than a ubiquitous one")
// Both candidates match exactly ONE of two terms, so coverage is equal and
// only IDF can separate them. "work" is said by eleven things here, "lisbon"
// by one. Kept under the top-16 cap so both are certain to be in the result
// and the assertion is about ORDER, not survival.
// The ubiquitous thing is given the STRONGER raw position on purpose — its
// word sits in title, tags and body (6 units) against the rare word's title
// alone (3). Rarity is then the only thing that can reverse them, so deleting
// it is provably caught rather than landing on a tie the sort breaks by luck.
var common: [Thing] = (1...10).map { Thing(title: "work item \($0)") }
let rare = Thing(title: "Lisbon")
let ubiquitous = Thing(title: "work", content: "work work", tags: ["work"])
common.append(contentsOf: [rare, ubiquitous])
let byRarity = rank("work lisbon", common)
check("both candidates are in the result (or the order proves nothing)",
      byRarity.contains(rare.title) && byRarity.contains(ubiquitous.title))
check("the rare term's thing leads the common term's",
      place(rare.title, byRarity) < place(ubiquitous.title, byRarity))

print("adjacency — a phrase beats the same two words scattered")
// Again the weaker-looking candidate is given the stronger raw position:
// `scattered` says both words in its title AND both in its tags (10 units) to
// `phrase`'s title alone (6). Only the adjacency bonus can reverse that, so
// deleting the bonus is provably caught instead of landing on a tie.
let phrase = Thing(title: "Climate change report")
let scattered = Thing(title: "Change management and the office climate",
                      tags: ["Climate", "Change"])
let byPhrase = rank("climate change", [scattered, phrase])
check("the phrase leads", byPhrase.first == phrase.title)
check("the scattered pair still qualifies (a bonus, not a filter)",
      byPhrase.contains(scattered.title))

print("field weighting still holds — title over tags over content")
let inTitle = Thing(title: "Lisbon")
let inTags = Thing(title: "Untitled", tags: ["Lisbon"])
let inBody = Thing(title: "Untitled", content: "we went to Lisbon in May")
let byField = rank("lisbon", [inBody, inTags, inTitle])
check("title, then tags, then content", byField == [inTitle.title, inTags.title, inBody.title])

print("the honest-nothing path survives")
check("a query nothing says returns nothing",
      rank("tokyo", [all4, one4, two4]).isEmpty)
// Coverage is a demotion, never a hard AND: one unknown word must not empty a
// query whose other words really are in the corpus.
check("one unmatched word does not empty the result",
      !rank("lisbon tokyo", [all4]).isEmpty)

print("regressions — the filters this pass rewrote around")
let shotA = Thing(title: "Home screen", kind: .screenshot)
let shotB = Thing(title: "Fitness", kind: .screenshot)
let noteA = Thing(title: "Grocery list", kind: .note)
check("a bare kind word still lists that kind",
      Set(rank("screenshots", [shotA, shotB, noteA])) == Set([shotA.title, shotB.title]))
let fromPhotos = Thing(title: "Receipt", source: "Photos")
let fromYou = Thing(title: "Receipt", source: "You")
check("a source word still filters", rank("photos", [fromPhotos, fromYou]) == [fromPhotos.title])
check("a kind word filters WITH content terms",
      rank("screenshots about fitness", [shotA, shotB, noteA]) == [shotB.title])
check("the top-16 cap still holds",
      rank("work", (1...40).map { Thing(title: "work \($0)") }).count == 16)

print("idfWeight — the rarity curve itself")
check("a word ONE thing says gets the ceiling (1.5)",
      abs(Retriever.idfWeight(corpus: 2000, holding: 0) - 1.5) < 0.0001)
check("a word EVERY thing says gets the floor (0.3)",
      abs(Retriever.idfWeight(corpus: 2000, holding: 2000) - 0.3) < 0.0001)
check("monotonic: rarer always pulls harder",
      Retriever.idfWeight(corpus: 2000, holding: 1) > Retriever.idfWeight(corpus: 2000, holding: 50)
      && Retriever.idfWeight(corpus: 2000, holding: 50) > Retriever.idfWeight(corpus: 2000, holding: 1000))
check("rare vs common spread is at least 2×",
      Retriever.idfWeight(corpus: 2000, holding: 1)
        / Retriever.idfWeight(corpus: 2000, holding: 1000) > 2.0)
// Bounded on purpose: a common word stays a real (small) signal instead of
// being deleted, so an all-common-words query still answers.
check("bounded to 0.3…1.5 on a small corpus too",
      Retriever.idfWeight(corpus: 10, holding: 1) > 0.3
      && Retriever.idfWeight(corpus: 10, holding: 1) < 1.5)
check("an empty corpus is a neutral 1", Retriever.idfWeight(corpus: 0, holding: 0) == 1)

print("coverageFactor — the curve itself")
check("full coverage is 1.0 (single term)", Retriever.coverageFactor(matched: 1, of: 1) == 1.0)
check("full coverage is 1.0 (four terms)",  Retriever.coverageFactor(matched: 4, of: 4) == 1.0)
check("one-of-four is demoted to ~a third",
      abs(Retriever.coverageFactor(matched: 1, of: 4) - 1.5 / 4.5) < 0.0001)
check("strictly increasing in matched terms",
      Retriever.coverageFactor(matched: 1, of: 4) < Retriever.coverageFactor(matched: 2, of: 4)
      && Retriever.coverageFactor(matched: 2, of: 4) < Retriever.coverageFactor(matched: 3, of: 4)
      && Retriever.coverageFactor(matched: 3, of: 4) < Retriever.coverageFactor(matched: 4, of: 4))
check("zero matches keeps a sliver, not zero", Retriever.coverageFactor(matched: 0, of: 4) > 0)
check("no terms at all is neutral", Retriever.coverageFactor(matched: 0, of: 0) == 1)

print("matchWindow — the snippet carries the passage that matched")
let pad = String(repeating: "filler words about nothing in particular here. ", count: 10) // ~470 chars
let body = pad + "The Lisbon restaurant was Cervejaria Ramiro on Avenida Almirante Reis. " + pad
if let w = Retriever.matchWindow(in: body, terms: ["lisbon"]) {
    check("finds a hit past the head and carries it", w.contains("Lisbon"))
    check("carries the surrounding fact, not just the word", w.contains("Cervejaria"))
    check("leads with an ellipsis (it is mid-body)", w.hasPrefix("…"))
    check("trails with an ellipsis (more text follows)", w.hasSuffix("…"))
    check("stays within the snippet budget", w.count < 330)
} else {
    check("finds a hit past the head at all", false)
}
check("case-insensitive: LISBON still hits",
      Retriever.matchWindow(in: body, terms: ["LISBON"])?.contains("Lisbon") == true)
let tail = pad + "finally we booked lisbon"
check("a hit at the end trails no ellipsis",
      Retriever.matchWindow(in: tail, terms: ["lisbon"])?.hasSuffix("lisbon") == true)
// Whole words only — "art" inside "restart" is not a hit (the 2026-07-10
// substring lesson, kept at the snippet layer too). Its OWN pad, holding no
// "art" substring anywhere: the general pad's "particular" carries one inside
// the head window, where an early bogus hit returns nil for the WRONG reason
// and a dropped boundary check sails through green (this harness's own first
// mutation finding).
let plainPad = String(repeating: "plain filler prose goes here with nothing tricky in it. ", count: 6)
check("a substring inside another word is NOT a hit",
      Retriever.matchWindow(in: plainPad + "we must restart the server. " + plainPad,
                            terms: ["art"]) == nil)
check("a hit already inside the head window → nil",
      Retriever.matchWindow(in: "the lisbon trip " + pad + pad, terms: ["lisbon"]) == nil)
check("no term present → nil", Retriever.matchWindow(in: body, terms: ["tokyo"]) == nil)
check("no terms → nil",        Retriever.matchWindow(in: body, terms: []) == nil)
check("empty body → nil",      Retriever.matchWindow(in: "", terms: ["lisbon"]) == nil)

print("contentTerms — the query's content words, order kept, stops stripped")
check("a question strips to its subject",
      Retriever.contentTerms("What did I save about climate change?") == ["climate", "change"])
check("the §307 polite form strips to its one real word",
      Retriever.contentTerms("Can you search my X stuff") == ["x"])
check("punctuation splits, order survives",
      Retriever.contentTerms("pasta—recipe from Lisbon!") == ["pasta", "recipe", "lisbon"])
check("command verbs are not content",
      Retriever.contentTerms("show me all my saved links") == ["links"])

print("")
if failures == 0 {
    print("✓ retriever self-test: all assertions passed")
} else {
    print("✗ retriever self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

swiftc -O -o "$TMP/run" "$TMP/stubs.swift" "$TMP/extracted.swift" "$TMP/main.swift" 2>&1 \
  | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ the extracted retriever engine did not compile against the stubs"; exit 1; }
"$TMP/run"

# --- mutation pass ----------------------------------------------------------
# Each mutation is a silent-wrong-answer this harness must catch; a check that
# cannot fail proves nothing. Applied to the EXTRACTED source, recompiled, and
# the run must FAIL.
mutate() {
  local label="$1" find="$2" replace="$3"
  python3 - "$TMP/extracted.swift" "$TMP/mutated.swift" "$find" "$replace" <<'PY'
import sys
src_path, out, find, replace = sys.argv[1:5]
src = open(src_path).read()
if find not in src:
    sys.exit(f"✗ mutation target not found (the harness is testing stale code): {find!r}")
open(out, "w").write(src.replace(find, replace, 1))
PY
  rm -f "$TMP/mutrun"
  swiftc -O -o "$TMP/mutrun" "$TMP/stubs.swift" "$TMP/mutated.swift" "$TMP/main.swift" \
    >/dev/null 2>&1 || true
  if [[ -x "$TMP/mutrun" ]] && "$TMP/mutrun" >/dev/null 2>&1; then
    echo "✗ mutation SURVIVED: $label — the assertions don't pin this behaviour"
    exit 1
  fi
  echo "  ✓ mutation caught: $label"
}

echo "mutations — each shipped behaviour is load-bearing"
mutate "coverage removed from rank (OR-semantics returns)" \
  '* Self.coverageFactor(matched: matchedTerms, of: terms.count)' ''
mutate "rarity removed from rank (every word weighs the same)" \
  'let weight = idf[term] ?? 1' 'let weight = 1.0'
mutate "the phrase bonus removed from rank" \
  'if entry.titleText.contains(pair) { score += 2.5 }' ''
mutate "idf inverted (common outweighs rare)" \
  '(Double(n) + 1) / (Double(df) + 1)' '(Double(df) + 1) / (Double(n) + 1)'
mutate "coverage flattened (one word scores like four)" \
  'return (Double(matched) + 0.5) / (Double(total) + 0.5)' 'return 1'
mutate "coverage hardened into an AND (a query with one unknown word empties)" \
  'return (Double(matched) + 0.5) / (Double(total) + 0.5)' \
  'return matched == total ? 1 : 0'
mutate "word boundary dropped in matchWindow (art matches restart)" \
  'if beforeOK, afterOK {' 'if true {'
mutate "head-hit no longer defers to the head excerpt" \
  'guard start > body.startIndex else { return nil }' ''
mutate "contentTerms keeps stop words" \
  '!$0.isEmpty && !Self.stops.contains($0)' '!$0.isEmpty'

echo ""
echo "✓ retriever self-test: extraction, assertions and mutations all green"
