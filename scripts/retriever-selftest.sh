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
# (below). The stubs are deliberately flat: `EmbeddingIndex` refuses to embed
# and `SemanticExpand` answers from a two-entry table rather than NLEmbedding,
# so every ordering asserted here is the engine's own and cannot be an
# embedding accident or an OS-version difference in a word's neighbours. If
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
# Synonyms count toward the relevance floor at HALF the weight of the word they
# stand in for. Both halves matter and each fails differently: full credit lets
# a neighbour of one word answer a two-word query (the shipped "climate change"
# → "Vogue gave another nod" bug), and no credit at all deletes the single-word
# synonym reach the expansion exists for. Fixtures pin both; this guard catches
# the line being removed outright.
grep -q 'matchedMass += 0.5 \* weight' "$RETRIEVER" \
  || { echo "✗ synonyms no longer count toward the relevance floor — either they are exempt again"; \
       echo "  (climate change → 'Vogue gave another nod') or their reach is deleted entirely"; exit 1; }
# A neighbour also carries its own rarity, so a synonym most of the corpus says
# is not evidence. Grep-guarded rather than fixture-pinned: the stub table's two
# entries are rare in every fixture corpus, so no assertion exercises the
# rarity cutoff itself.
grep -q 'if weight >= Self.expansionFloor { expandedIdf\[word\] = weight }' "$RETRIEVER" \
  || { echo "✗ synonym neighbours are no longer rarity-filtered — common words become evidence again"; exit 1; }
grep -q 'synonym += 1.5 \* nWeight' "$RETRIEVER" \
  || { echo "✗ synonym hits are no longer rarity-weighted — a ubiquitous neighbour scores like a rare one"; exit 1; }
grep -q 'expansionsByTerm\[term\] = SemanticExpand.expand(\[term\])' "$RETRIEVER" \
  || { echo "✗ synonyms are no longer attributed to the term they stand in for — the floor cannot credit them"; exit 1; }

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
# The app types `rank` reaches for. Flat BY DESIGN: no embedding at all, and
# synonyms from a fixed two-entry table, so every ordering asserted below is
# the engine's own and reproducible on any machine.
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
    var postText: String?
    var summary: String?
    var authorHandle: String?
    var tags: [String]
    var source: String
    var kind: ThingKind
    var capturedAt: Date
    var embedding: Data?
    init(title: String, content: String = "", enrichedText: String? = nil,
         postText: String? = nil, summary: String? = nil, authorHandle: String? = nil,
         tags: [String] = [], source: String = "You", kind: ThingKind = .note,
         capturedAt: Date = Date(timeIntervalSince1970: 1_750_000_000)) {
        self.title = title; self.content = content; self.enrichedText = enrichedText
        self.postText = postText; self.summary = summary; self.authorHandle = authorHandle
        self.tags = tags; self.source = source; self.kind = kind
        self.capturedAt = capturedAt; self.embedding = nil
    }
}

enum DateQuery {
    struct Match {
        let range: ClosedRange<Date>; let words: Set<String>
        // Carried since 2026-08-13 so a resolved date can name itself on a
        // scope chip. Stubbed with the real field so `ranked` compiles as
        // shipped; still never constructed, since `match` stays inert below.
        let label: String
    }
    // Inert: no fixture here asks a WHEN question, and a live date parse would
    // make these assertions depend on the day they run.
    static func match(in query: String) -> Match? { nil }
}

enum SemanticExpand {
    // A FIXED table, not NLEmbedding: real neighbours differ by OS build, so
    // reading them here would make the harness flaky and its failures
    // unreadable. Two entries, both measured on a real device — "car" →
    // "vehicle" is the reach this feature exists for, and "change" →
    // "another" is the one that put a Vogue piece and a Ford review into a
    // "climate change" answer. Every other term expands to nothing, so the
    // ranking fixtures above stay exact-keyword-only.
    static let table: [String: Set<String>] = [
        "car": ["vehicle"],
        "change": ["another"],
    ]
    // Inert for everything else: NLEmbedding's neighbours differ by OS build,
    // so a synonym landing
    // in the middle of a ranking fixture would make this harness flaky and its
    // failures unreadable. Every ordering below is exact-keyword evidence.
    static func expand(_ terms: [String]) -> Set<String> {
        var out: Set<String> = []
        for t in terms { out.formUnion(table[t] ?? []) }
        out.subtract(terms)
        return out
    }
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
let three4 = Thing(title: "Recipe from the Lisbon trip")
let order = rank("pasta recipe lisbon trip", [one4, three4, two4, all4])
check("the thing answering the whole query leads", order.first == all4.title)
check("more coverage outranks less", place(three4.title, order) < place(two4.title, order))
// And the one-word ride is not merely demoted now — the relevance floor below
// removes it outright.
check("a one-of-four common-word match is gone entirely",
      !order.contains(one4.title))
// The complaint itself, isolated. `ride` says ONE query word — but says it in
// its title AND its tags AND its body, which is the maximum a single term can
// score (3+2+1). `spread` says THREE of the four words, and only in passing in
// its body (1 each). Under the old OR-semantics the one-word ride won 6 to 3
// and took the grounding slot; coverage is what reverses it. The three
// preceding fixtures could NOT prove this — there, raw hit counts already
// ordered things correctly, so deleting coverage changed nothing and the
// mutation survived (this harness's own second finding).
// `ride` says ONE query word — but in its title AND tags AND body, the most a
// single term can score (3+2+1). `spread` says BOTH words, once each, in
// weaker positions. Under the old OR-semantics the one-word ride won 6 units
// to 4 and took the top slot; coverage is what reverses it.
//
// Tuned so BOTH clear the relevance floor (each matches at least one of two
// equally-rare words), because otherwise the floor removes `ride` on its own
// and the fixture proves nothing about coverage — which is exactly what
// happened when the floor landed, and the mutation started surviving.
// `elsewhere` exists only to give "porto" a second holder so the two terms
// weigh the same; without it porto is rarer and rarity, not coverage, decides.
let pad10 = (1...8).map { Thing(title: "unrelated note \($0)") }
let ride = Thing(title: "Lisbon", content: "lisbon notes", tags: ["Lisbon"])
let spread = Thing(title: "Porto", content: "lisbon day trip")
let elsewhere = Thing(title: "Notes", content: "porto")
let byCoverage = rank("lisbon porto", pad10 + [ride, spread, elsewhere])
check("both words in weak positions beat one word said everywhere",
      byCoverage.first == spread.title)
check("the one-word ride still answers (the floor did not remove it)",
      byCoverage.contains(ride.title))

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
check("the rare term's thing answers", byRarity.contains(rare.title))
// Rarity now decides membership, not just order: matching only the word
// eleven things say carries too little of the query to be a match at all,
// while matching the word one thing says carries most of it.
check("matching only the ubiquitous word is not a match",
      !byRarity.contains(ubiquitous.title))

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

print("the relevance floor — matching only the uninformative words is no match")
// The measured simulator case, as a fixture. Nothing here is about climate;
// several things merely say "change". Under ranking alone they all qualified
// and filled the screen ("11 things match", a Ford review at the top).
let noise = [
    Thing(title: "Ford needs another Taurus, and the EV pickup isn't it"),
    Thing(title: "Vogue gave another nod of approval to the tech world"),
    Thing(title: "Car washes can still sponsor workers despite visa changes"),
    Thing(title: "Reddit shifts karma rules, a change for first-time posters"),
    Thing(title: "Half of vaccines are binned - fridge-free versions could change that"),
]
check("a subject the corpus knows nothing about answers NOTHING",
      rank("climate change", noise).isEmpty)
// …and the same corpus still answers the question it CAN answer, so the floor
// is refusing noise rather than refusing everything.
check("the same corpus still answers what it does hold",
      rank("vaccines fridge", noise).count == 1)
// An honest partial match SURVIVES: three of four words, missing the rarest,
// is most of the query's mass. A floor that ate this would be worse than the
// noise it removes.
let partial = Thing(title: "Pasta recipe from the trip")
check("three of four words still matches (the rarest one missing)",
      rank("pasta recipe lisbon trip", [partial] + noise).first == partial.title)
// The synonym path owns its own evidence and is deliberately exempt — a thing
// with NO exact match at all is left exactly as it was.
check("a single term still matches things that say it",
      rank("vaccines", noise).count == 1)

print("the fields a row actually carries are all searched")
// A social row, shaped as the bridges really store one: `content` is the
// PERMALINK, `title` is the 80-char clamp, and the words live on `postText`.
// Before 2026-08-06 the engine read title/tags/content only, so the searchable
// body of every Farcaster, Bluesky, Nostr, Slack and X row was a URL.
let post = Thing(title: "Long thread about the retrieval problem in personal",
                 content: "https://bsky.app/profile/someone/post/3k2f",
                 postText: "Long thread about the retrieval problem in personal corpora — "
                         + "the hard part is ranking, not storage. Vector search alone "
                         + "returns plausible neighbours instead of answers.",
                 authorHandle: "someone.bsky.social",
                 source: "Bluesky", kind: .chat)
let decoy = Thing(title: "Storage prices", content: "nothing to do with it")
check("a word only in postText is findable",
      rank("plausible neighbours", [post, decoy]).first == post.title)
check("the handle is findable (it is nowhere in the title)",
      rank("someone.bsky.social", [post, decoy]).contains(post.title))
// An x402 seller row: the services it sells live on `enrichedText`, its line
// on `summary`, the company on `authorHandle`.
let seller = Thing(title: "Allium · Blockchain prices, tokens, wallets, and SQL",
                   content: "https://allium.so",
                   enrichedText: "onchain data · SQL queries across chains · wallet labels",
                   summary: "12 services from $0.0100",
                   authorHandle: "Allium", tags: ["x402", "Data"], source: "Circle x402", kind: .link)
check("a service only named in enrichedText is findable",
      rank("wallet labels", [seller, decoy]).contains(seller.title))
check("the seller is findable by name", rank("allium", [seller, decoy]).first == seller.title)
// A dotted handle or domain is ONE space-separated word and three tokens. The
// engine split the query on spaces while tokenizing fields on every
// non-alphanumeric, so these could never match — the values a person is most
// likely to search a social or x402 room by.
check("a dotted handle matches", rank("someone.bsky.social", [post, decoy]).contains(post.title))
check("a domain matches", rank("allium.so", [seller, decoy]).contains(seller.title))
// The seam guard: two fields are joined for the phrase scan, so a pair must not
// match ACROSS the seam. Both rows contain both words — the one holding them
// as a real phrase must win.
let seam = Thing(title: "Seam", content: "the ending word carrots",
                 postText: "potatoes start the next field")
let real = Thing(title: "Real", content: "a bag of carrots potatoes and onions")
check("a true phrase outranks the same words split across a seam",
      rank("carrots potatoes", [seam, real]).first == real.title)

print("synonyms stand in for a word — at half its weight, never full")
// The reach the feature exists for: one word, answered by its near-synonym.
// Half of one term's mass is exactly 0.5, which clears the floor.
let vehicle = Thing(title: "Vehicle maintenance schedule")
check("a single word is still answered by its synonym",
      rank("car", [vehicle] + (1...3).map { Thing(title: "filler \($0)") }).contains(vehicle.title))
// …and the bug that survived both the floor and a tighter neighbour distance:
// a synonym for ONE word of two carries 0.25 of the query and is not an answer.
// "another" really is a near neighbour of "change" — tightening distance could
// never separate them, which is why the credit is halved instead.
let vogue = Thing(title: "Vogue just gave another nod of approval to the tech world")
check("a synonym for one word of two does not answer",
      rank("climate change", [vogue] + (1...3).map { Thing(title: "filler \($0)") }).isEmpty)

print("a source scope that empties the answer falls through to the whole corpus")
// The measured case: "wallet" is an app name AND an ordinary word. Scoping to
// the Wallet room finds nothing, while the x402 row answers exactly — before
// the fallback this query returned NOTHING.
let txn = Thing(title: "Swapped 0.5 ETH", source: "Photos")   // a real room, no match
let x402 = Thing(title: "EMC2 · Onchain alpha, wallet flow, and DEX analytics",
                 source: "Circle x402", kind: .link)
check("a scoped read that comes back empty falls through",
      rank("onchain photos analytics", [txn, x402]).contains(x402.title))
// …and the scope is KEPT whenever it answers, which is §307's whole ruling.
let inRoom = Thing(title: "Receipt for the hotel", source: "Photos", kind: .screenshot)
let elsewhereSame = Thing(title: "Receipt for the hotel", source: "Gmail", kind: .link)
check("a scope that answers is not widened",
      rank("photos receipt", [inRoom, elsewhereSame]) == [inRoom.title])

// §340: a source name introduced as a SUBJECT is not a scope. Reported live —
// "what did I post about a wallet" scoped to the Wallet room, stripped the word
// from the terms, and returned that room's newest transactions. NON-EMPTY, so
// §318's escape hatch above never fired and the person's own post was never
// reached by anything. This is the case the empty-result fallback cannot cover.
//
// Sources are named explicitly because `BridgeCatalog` is stubbed here, so the
// default list is empty and every one of these would pass vacuously.
//
// Asserted on `sourceFilter` DIRECTLY, not through `rank`: routing it through
// the whole engine lets term matching decide the outcome, and the first cut of
// these fixtures failed for exactly that reason — "wallet" does not match
// "wallets", so the check proved nothing about scoping either way.
check("\"about a <source>\" is a subject, not a room",
      Retriever.sourceFilter(in: "what did I post about a wallet", sources: ["Wallet"]) == nil)
check("\"a <source>\" is a common noun, not a room",
      Retriever.sourceFilter(in: "I saved a wallet article", sources: ["Wallet"]) == nil)
check("\"about <source>\" is a subject too",
      Retriever.sourceFilter(in: "what did I read about wallet", sources: ["Wallet"]) == nil)
// …and §307's own phrasing is untouched: a bare source name still scopes.
check("a bare source name still scopes",
      Retriever.sourceFilter(in: "search my wallet stuff", sources: ["Wallet"])?.source == "Wallet")

print("the honest-nothing path survives")
check("a query nothing says returns nothing",
      rank("tokyo", [all4, one4, two4]).isEmpty)
// Two RARE words where the corpus holds only one is an honest partial answer
// and must survive — this is the case that set `massFloor` to 0.45 rather than
// 0.5, and it is the counterweight to the noise fixtures above. Padded to a
// realistic corpus size on purpose: with one thing in the store every term is
// trivially "common" and the rarity weights collapse, which measures nothing.
let filler = (1...10).map { Thing(title: "unrelated note \($0)") }
check("two rare words, one of them held, still answers",
      rank("lisbon tokyo", filler + [all4]).contains(all4.title))

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

print("find — the uncapped read, and the filters it admits to")
// THE CAP IS THE MODEL'S, NOT THE CORPUS'S (2026-08-13). `rank` bounds what a
// model is handed; Find reads `find` and must be able to say how many things
// really match. Shipped the other way, a search over a 3,500-post archive
// reported "16 things match" — a cap presented as a count.
let forty = (1...40).map { Thing(title: "work \($0)") }
check("find returns every match, uncapped", Retriever.find("work", in: forty).hits.count == 40)
check("rank still bounds what a model is handed",
      rank("work", forty).count == Retriever.groundingLimit)

let photoRow = Thing(title: "Receipt", source: "Photos")
let yourRow = Thing(title: "Receipt", source: "You")
check("an honoured source is reported as a scope",
      Retriever.find("photos receipt", in: [photoRow, yourRow]).scopes
        == [Retriever.Scope(kind: .source, label: "Photos")])
check("a dropped source is not reported, and does not scope",
      Retriever.find("photos receipt", in: [photoRow, yourRow], dropping: [.source])
        .scopes.isEmpty)

let shotX = Thing(title: "Home screen", kind: .screenshot)
let noteX = Thing(title: "Grocery list", kind: .note)
check("an honoured kind is reported as a scope",
      Retriever.find("screenshots", in: [shotX, noteX]).scopes
        == [Retriever.Scope(kind: .kind, label: "Screenshots")])
check("a dropped kind is not reported, and does not filter",
      Retriever.find("screenshots", in: [shotX, noteX], dropping: [.kind]).scopes.isEmpty)

// A SCOPE THE FALLBACK STOOD DOWN WAS NEVER APPLIED, so reporting it would be
// a chip explaining a result it had no part in. The scoped pass here empties
// (the one Photos row says none of these words), §318's fallback re-reads the
// whole corpus, and the answer comes back with no scope at all.
let pShot = Thing(title: "IMG_4821", source: "Photos")
let x402Row = Thing(title: "Onchain alpha, photos flow and analytics", source: "You")
let stoodDown = Retriever.find("onchain photos analytics", in: [pShot, x402Row])
check("a scope the empty-result fallback stood down is not reported",
      stoodDown.scopes.isEmpty)
check("...and that fallback still answers", stoodDown.hits.map(\.title) == [x402Row.title])

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
mutate "the empty-scope fallback removed (an app-named word walls the answer)" \
  'honourSource: false, dropping: dropping)' 'honourSource: true, dropping: dropping)'
mutate "the fallback fires even when the scope answered (§307 undone)" \
  'guard scoped.hits.isEmpty else { return scoped }' ''
mutate "find re-capped at the grounding limit (a count that is really a cap)" \
  'return Outcome(hits: hits, scopes: scopes)' \
  'return Outcome(hits: Array(hits.prefix(groundingLimit)), scopes: scopes)'
mutate "a scope is reported even when the caller dropped it" \
  'dropping.contains(.kind)' 'false'
mutate "an applied source filter goes unreported (a hidden filter returns)" \
  'if let sourceMatch { scopes.append(Scope(kind: .source, label: sourceMatch.source)) }' ''
mutate "the relevance floor removed (common-word noise returns)" \
  'if !strongMeaning { return nil }' ''
mutate "a synonym credited in FULL (a neighbour of one word answers a two-word query)" \
  'matchedMass += 0.5 * weight' 'matchedMass += weight'
# Both edges of a narrow measured band. 0.5 is the round number the floor was
# nearly set to, and it refuses an honest partial match; 0.3 lets the measured
# noise back in. That both fail is what makes 0.40 a measurement rather than a
# preference.
mutate "the floor rounded up to 0.5 (refuses honest partial matches)" \
  'static let massFloor = 0.40' 'static let massFloor = 0.5'
mutate "the floor dropped to 0.3 (noise returns)" \
  'static let massFloor = 0.40' 'static let massFloor = 0.3'
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
