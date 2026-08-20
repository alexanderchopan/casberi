#!/bin/zsh
# Walletbeat's pure logic, compiled AS SHIPPED (prd §419).
#
# WHY THIS IS THE ONLY PROOF THESE NUMBERS ARE RIGHT: nothing on this host can make
# Walletbeat revise a rating or publish a security incident, and their registry is a third
# party's live document. The build cannot see any of it — a wallet whose coverage gate is
# inverted, an incident whose severity silently defaults, a bar that rescales away its own
# unrated segment all render perfectly. So the four Foundation-only files are compiled
# WHOLE and unmodified, and every rule §419 states is asserted against them.
#
# The sharpest thing it guards is the COVERAGE GATE. Measured 2026-08-20, sixteen of the 32
# rated wallets have under a quarter of their attributes judged and two have none at all —
# so a surface that draws a bar from raw counts shows the wallet nobody has examined as the
# cleanest one on the screen. That is the failure this whole feature is shaped around, and
# it is invisible to every other check in the tree.

set -euo pipefail
cd "$(dirname "$0")/.."

RATING="Casberi/Casberi/Model/WalletbeatRating.swift"
NEWS="Casberi/Casberi/Model/WalletbeatNews.swift"
ROOM="Casberi/Casberi/Model/WalletbeatRoom.swift"
DIR="Casberi/Casberi/Model/WalletbeatDirectory.swift"
BRIDGE="Casberi/Casberi/Model/WalletbeatBridge.swift"
SRC="Casberi/Casberi/Model/WalletbeatRoomSource.swift"
VIEWS="Casberi/Casberi/Screens/WalletbeatViews.swift"
ROWS="Casberi/Casberi/Screens/WalletbeatRow.swift"
CARD="Casberi/Casberi/Screens/WalletbeatRoomCard.swift"
DIRSCREEN="Casberi/Casberi/Screens/WalletbeatDirectoryScreen.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
SHEET="Casberi/Casberi/Model/WalletbeatSheet.swift"
SHEETSRC="Casberi/Casberi/Model/WalletbeatSheetSource.swift"
SHEETVIEWS="Casberi/Casberi/Screens/WalletbeatSheetViews.swift"
CARDSCREEN="Casberi/Casberi/Screens/WalletbeatCardScreen.swift"
FIGURE="Casberi/Casberi/Model/RoomFigure.swift"
SHEETVIEW="Casberi/Casberi/Screens/ThingSheetView.swift"
RETRIEVER="Casberi/Casberi/Model/Retriever.swift"
SNAP="scripts/walletbeat-snapshot.py"

for f in "$RATING" "$NEWS" "$ROOM" "$DIR" "$BRIDGE" "$SRC" "$VIEWS" "$ROWS" "$CARD" "$DIRSCREEN" "$SHEET" "$SHEETSRC" "$SHEETVIEWS" "$CARDSCREEN" "$SNAP"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --------------------------------------------------------------------------------------
# 1 · Drift guards — the wiring the compiled functions cannot prove about themselves.
#
# Several read a COMMENT-STRIPPED copy: these files DOCUMENT their rules by naming what
# they must never do ("nothing here ranks wallets or sums a dimension into a score"), so a
# guard over raw source fires on the prose explaining the rule and reports a correct file
# as broken. Earned on this feature's own snapshot generator, first run.
# --------------------------------------------------------------------------------------
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = "\n".join(l for l in src.split("\n") if not l.lstrip().startswith("//"))
print(src)
PY
}

guard() { # guard <literal> <file> <human sentence>
  grep -qF -- "$1" "$2" || { echo "✗ $3"; exit 1; }
}

strip_comments "$ROOM" > "$TMP/room.nc"
strip_comments "$SRC" > "$TMP/src.nc"
strip_comments "$VIEWS" > "$TMP/views.nc"
strip_comments "$BRIDGE" > "$TMP/bridge.nc"

echo "Drift guards"

guard 'things.live' "$SRC" \
  "WalletbeatRoomSource no longer filters live at the boundary (corollary 4)"
guard 'WalletbeatRoom.ranked(items)' "$SRC" \
  "the room's wallets are no longer ranked — an unresolved incident would sort arbitrarily"
guard 'ranked.prefix(rowCap)' "$SRC" \
  "the room head no longer honours its row cap"
guard 'case .walletbeat(let room)' "$FEED" \
  "the Walletbeat head is no longer rendered from the sourceHead chain"
guard 'case WalletbeatRoomSource.source:' "$FEED" \
  "FeedScreen no longer dispatches a Walletbeat head"
guard 'case "Walletbeat":          self = .walletbeat' "$FEED" \
  "the Walletbeat room lost its Shape case — it would fall back to plain bands"
guard 'note("walletbeatHead"' "$PROBES" \
  "-roomInsightProbe no longer mirrors the Walletbeat head; it would report 'leads with NOTHING'"
guard 'walletbeat.eth.limo' "$REACH" \
  "Walletbeat's ratings host is not declared in NetworkReach"
guard 'raw.githubusercontent.com' "$REACH" \
  "Walletbeat's registry host is not declared in NetworkReach"

# THE coverage gate. If a view stops asking, every screen silently starts drawing verdicts
# nobody reached — the one failure this feature exists to prevent.
guard 'WalletbeatCoverage.of(counts).showsShape' "$TMP/views.nc" \
  "WalletbeatShape no longer gates on coverage — an unexamined wallet would draw a bar"
guard 'WalletbeatCoverage.of(counts).showsShape' "$ROWS" \
  "the wallet row no longer gates its bars on coverage"
guard 'WalletbeatShape(counts:' "$DIRSCREEN" \
  "the directory no longer draws through the gated shape component"

# The unrated segment must stay in the bar; dropping it rescales the rest to full width.
guard '(.unrated, counts.unrated' "$TMP/views.nc" \
  "the bar no longer draws its UNRATED segment — five of twenty-nine would paint as full"

# The §311 shape: one constant read by the landing that writes it and the head that matches.
guard 'WalletbeatNewsParse.openTag' "$TMP/bridge.nc" \
  "the incident landing no longer stamps the shared open tag"
guard 'WalletbeatNewsParse.openTag' "$TMP/src.nc" \
  "the room head no longer matches the shared open tag — the room would go quiet, not break"

# The card's sort must keep its id tiebreak, or a report card reshuffles between opens
# over unchanged data — which reads as broken.
#
# A GUARD RATHER THAN A MUTATION, deliberately, and this is the interesting case: the
# pre-sort order comes from iterating a JSON dictionary, and Swift seeds its hashing
# randomly per process, so a card built without the tiebreak lands in an order that varies
# run to run. Removing it therefore fails the assertion only SOMETIMES — measured: the
# mutation survived a full run of this harness. A gate that fails one run in three is
# worse than no gate, so the property is asserted in the harness and the mechanism is
# pinned here, where it cannot be luck.
guard 'return ai == bi ? a.id < b.id : ai < bi' "$RATING" \
  "the card's attribute sort lost its id tiebreak — a report card would reshuffle between opens"

# The sheet arm (prd §419 amendment). BOTH halves: an arm that draws without being
# subtracted from `contentShown` renders the head AND lets ThingContentView redraw the
# body underneath it.
guard 'walletbeatHead(walletbeatShape)' "$SHEETVIEW" \
  "the Walletbeat sheet arm is gone — its three records fall back to the generic link sheet"
guard '&& walletbeatShape == nil' "$SHEETVIEW" \
  "the Walletbeat arm is not subtracted from contentShown — the body would draw twice"
guard 'WalletbeatReportCard(walletID:' "$SHEETVIEW" \
  "a watched wallet's sheet no longer draws its report card"

# The chip peek must preview the room it opens — X's and Safe's rule (§334).
guard 'source == WalletbeatRoomSource.source' "$FIGURE" \
  "the Walletbeat chip peek no longer previews its head — long-pressing the chip draws nothing"
# The bar's VALUE is the judged count, never the pass count: a bar drawn from passes ranks
# the wallet nobody examined alongside one that passed nothing.
guard 'value: $0.counts.judged' "$FIGURE" \
  "the peek's bars no longer measure how much was JUDGED — they would imply a verdict"

# §308 facets, and the rule that they only narrow behind a named source.
guard '"Incident")' "$RETRIEVER" \
  "the Walletbeat incident facet is gone — 'security incidents in Walletbeat' stops narrowing"
guard '"Rating")' "$RETRIEVER" \
  "the Walletbeat rating facet is gone"

# Negative guards: no score, no ranking of wallets by quality, ever.
if grep -qiE '(qualityScore|overallScore|walletScore|bestWallet)' "$TMP/room.nc" "$TMP/views.nc" "$TMP/src.nc"; then
  echo "✗ a composite score appeared — §419 forbids one; Walletbeat publishes none"
  exit 1
fi
# The directory must never offer a "best" sort.
if grep -qiE 'case best|\.best\b' "$DIRSCREEN"; then
  echo "✗ the directory grew a 'best' order — that needs a composite nobody published"
  exit 1
fi
# The bridge must never issue a write. There is no endpoint to write to, and that is the
# promise the connect screen makes.
if grep -qE 'httpMethod|postJSON|deleteJSON|"POST"|"PUT"|"DELETE"' "$TMP/bridge.nc"; then
  echo "✗ WalletbeatBridge gained a write verb — the seat promises read-only"
  exit 1
fi
echo "  ✓ all drift guards hold"
echo ""

# --------------------------------------------------------------------------------------
# 2 · Assertions against the SHIPPED source, compiled whole.
# --------------------------------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

func counts(pass: Int = 0, partial: Int = 0, fail: Int = 0,
            unrated: Int = 0, exempt: Int = 0) -> WalletbeatCounts {
    WalletbeatCounts(pass: pass, partial: partial, fail: fail, unrated: unrated, exempt: exempt)
}

print("Counts and coverage")

// EXEMPT leaves BOTH halves of the fraction: a question that does not apply to a wallet
// is not a gap in what is known about it.
let withExempt = counts(pass: 4, fail: 2, unrated: 2, exempt: 2)
check("total counts every attribute", withExempt.total == 10)
check("judged counts only real verdicts", withExempt.judged == 6)
check("applicable excludes exempt", withExempt.applicable == 8)

// The measured distribution's two ends.
check("zero judged is .none", WalletbeatCoverage.of(counts(unrated: 25)) == .none)
check("an all-exempt wallet is .none, not a division by zero",
      WalletbeatCoverage.of(counts(exempt: 5)) == .none)
check("1 of 29 is .thin (Uniswap Wallet, measured)",
      WalletbeatCoverage.of(counts(pass: 1, unrated: 28)) == .thin)
check("10 of 29 is .partial (Safe, measured)",
      WalletbeatCoverage.of(counts(pass: 7, partial: 1, fail: 2, unrated: 19)) == .partial)
check("25 of 29 is .deep (Rabby, measured)",
      WalletbeatCoverage.of(counts(pass: 5, partial: 5, fail: 15, unrated: 4)) == .deep)

// THE GATE. A thin wallet must never be drawn as a comparable shape.
check("a shape is refused below the floor", WalletbeatCoverage.thin.showsShape == false)
check("a shape is refused for the unexamined", WalletbeatCoverage.none.showsShape == false)
check("a shape is allowed at partial", WalletbeatCoverage.partial.showsShape)
check("a shape is allowed at deep", WalletbeatCoverage.deep.showsShape)

// Exactly at the floor counts as deep — a boundary that silently excludes 0.7 would put
// a well-examined wallet in the "barely rated" band.
check("exactly 0.7 is deep", WalletbeatCoverage.of(counts(pass: 7, unrated: 3)) == .deep)
check("exactly 0.3 is partial", WalletbeatCoverage.of(counts(pass: 3, unrated: 7)) == .partial)

print("")
print("Verdicts")
check("PASS is judged", WalletbeatVerdict.pass.isJudged)
check("PARTIAL is judged", WalletbeatVerdict.partial.isJudged)
check("FAIL is judged", WalletbeatVerdict.fail.isJudged)
check("UNRATED is not judged", WalletbeatVerdict.unrated.isJudged == false)
// EXEMPT is not "examined" — counting it would inflate coverage.
check("EXEMPT is not judged", WalletbeatVerdict.exempt.isJudged == false)

print("")
print("The report card's lead")

func attribute(_ id: String, _ d: WalletbeatDimension, _ v: WalletbeatVerdict,
               _ text: String = "because reasons") -> WalletbeatAttribute {
    WalletbeatAttribute(id: id, dimension: d, name: id, question: "q?", verdict: v, explanation: text)
}
func card(_ attributes: [WalletbeatAttribute]) -> WalletbeatCard {
    WalletbeatCard(walletID: "w", name: "W", hardware: false, stage: nil,
                   lastUpdated: "2026-08-01", site: nil, attributes: attributes,
                   fetchedAt: Date(timeIntervalSince1970: 1_780_000_000))
}

// Thin coverage OUTRANKS a finding. A lone FAIL from a wallet with two judged attributes
// would imply the other twenty-three were fine.
let barely = card([attribute("a", .security, .fail)] + (0..<9).map { attribute("u\($0)", .security, .unrated) })
if case .barelyExamined = barely.lead {
    check("thin coverage outranks a finding", true)
} else {
    check("thin coverage outranks a finding — got \(barely.lead)", false)
}

let nothing = card((0..<5).map { attribute("u\($0)", .security, .unrated) })
if case .unexamined = nothing.lead { check("an unexamined wallet says so", true) }
else { check("an unexamined wallet says so", false) }

// With real coverage, the first FAIL in Walletbeat's own dimension order leads — and
// SECURITY comes before PRIVACY, so a privacy fail must not jump the queue.
let deep = card([
    attribute("hardwareWalletSupport", .security, .pass),
    attribute("scamPrevention", .security, .fail, "leaks your browsed websites"),
    attribute("appIsolation", .privacy, .fail, "no new account on connect"),
    attribute("openSource", .transparency, .partial),
    attribute("funding", .transparency, .pass),
    attribute("browserIntegration", .ecosystem, .pass),
    attribute("chainAbstraction", .ecosystem, .partial),
])
if case .finding(let a) = deep.lead {
    check("the first FAIL leads", a.id == "scamPrevention")
    check("the lead is concerning", deep.lead.isConcerning)
} else {
    check("the first FAIL leads", false)
}

// A PARTIAL leads only when nothing failed, and it is NOT reported as concerning.
let partialOnly = card([
    attribute("a", .security, .pass), attribute("b", .security, .pass),
    attribute("c", .security, .partial), attribute("d", .privacy, .pass),
])
if case .finding(let a) = partialOnly.lead {
    check("a partial leads when nothing failed", a.id == "c")
    check("a partial is not called concerning", partialOnly.lead.isConcerning == false)
} else { check("a partial leads when nothing failed", false) }

// Nothing failing is stated as "nothing failed", NEVER as "good".
let clean = card((0..<8).map { attribute("p\($0)", .security, .pass) })
if case .noFailures = clean.lead { check("a clean wallet says nothing failed", true) }
else { check("a clean wallet says nothing failed", false) }
check("a clean lead is not concerning", clean.lead.isConcerning == false)

print("")
print("Dimensions")
// Driven by the enum, never by dictionary order — a Dictionary's own order would reshuffle
// the bars between launches, which reads as broken.
let mixed = card([attribute("e", .ecosystem, .pass), attribute("s", .security, .pass)])
check("dimensions come back in Walletbeat's order", mixed.dimensions == [.security, .ecosystem])
check("a dimension with no attributes is absent", mixed.dimensions.contains(.maintenance) == false)
check("per-dimension counts are scoped", mixed.counts(in: .security).pass == 1)

print("")
print("Revisions")
let before = card([attribute("scamPrevention", .security, .unrated, ""),
                   attribute("openSource", .transparency, .pass)])
let after = card([attribute("scamPrevention", .security, .fail, "leaks browsed sites"),
                  attribute("openSource", .transparency, .fail, "went proprietary")])
let revisions = WalletbeatRevisions.between(before, after)
check("both changes are reported", revisions.count == 2)
check("a first judgment is marked as one",
      revisions.first { $0.attributeID == "scamPrevention" }?.isFirstJudgment == true)
check("a changed verdict is not a first judgment",
      revisions.first { $0.attributeID == "openSource" }?.isFirstJudgment == false)

// A verdict LOST is housekeeping, not news about the wallet.
//
// The fixture must isolate that ONE transition: diffing `after` against `before` wholesale
// also flips openSource FAIL -> PASS, which is a real change and correctly reported, so the
// first cut of this check asserted an empty list and failed against correct code. A
// withdrawal-only pair is what makes the guard load-bearing.
let withdrawn = card([attribute("scamPrevention", .security, .unrated, ""),
                      attribute("openSource", .transparency, .fail, "went proprietary")])
let lost = WalletbeatRevisions.between(after, withdrawn)
check("a withdrawn rating is not reported", lost.isEmpty)
check("the fixture really did withdraw one",
      after.attributes.first { $0.id == "scamPrevention" }?.verdict == .fail
        && withdrawn.attributes.first { $0.id == "scamPrevention" }?.verdict == .unrated)

// Never cross wallets.
let other = WalletbeatCard(walletID: "z", name: "Z", hardware: false, stage: nil,
                           lastUpdated: nil, site: nil, attributes: after.attributes,
                           fetchedAt: Date(timeIntervalSince1970: 1_780_000_000))
check("two different wallets never diff", WalletbeatRevisions.between(before, other).isEmpty)

print("")
print("Parsing Walletbeat's ratings JSON")
let ratingsJSON = """
{"walletId":"rabby","displayName":"Rabby","types":["SOFTWARE"],"stage":"Stage 0",
 "lastUpdated":"2026-07-20","website":"https://rabby.io",
 "overall":{"security":{"scamPrevention":{"attribute":{"attributeDisplayName":"Scam prevention",
 "shortQuestion":"Does it warn you?"},"evaluation":{"rating":"FAIL",
 "shortExplanation":"Rabby warns you about potential scams,\\nbut leaks your browsed websites."}},
 "hardwareWalletSupport":{"attribute":{"attributeDisplayName":"Hardware wallets"},
 "evaluation":{"rating":"PASS","shortExplanation":"Rabby supports hardware wallets."}}},
 "privacy":{"addressCorrelation":{"attribute":{"attributeDisplayName":"Address privacy"},
 "evaluation":{"rating":"UNRATED","shortExplanation":"See full details on the wallet page."}}},
 "nonsenseGroup":{"x":{"evaluation":{"rating":"PASS"}}}}}
"""
let parsed = WalletbeatRatingParse.card(from: Data(ratingsJSON.utf8),
                                        fetchedAt: Date(timeIntervalSince1970: 1_780_000_000))
check("the card parses", parsed != nil)
if let parsed {
    check("wallet id survives", parsed.walletID == "rabby")
    check("display name survives", parsed.name == "Rabby")
    check("hardware is false for SOFTWARE", parsed.hardware == false)
    check("stage survives", parsed.stage == "Stage 0")
    check("three attributes land", parsed.attributes.count == 3)
    // A group we do not know is skipped rather than guessed into a dimension.
    check("an unknown group is skipped", parsed.attributes.contains { $0.id == "x" } == false)
    let scam = parsed.attributes.first { $0.id == "scamPrevention" }
    check("the verdict is read", scam?.verdict == .fail)
    check("the display name is read", scam?.name == "Scam prevention")
    check("the question is read", scam?.question == "Does it warn you?")
    // Their formatter hard-wraps inside string literals; those are the formatter's line
    // breaks, not the writer's.
    check("a wrapped explanation is unwrapped",
          scam?.explanation == "Rabby warns you about potential scams, but leaks your browsed websites.")
    // Placeholder prose is not a finding.
    let addr = parsed.attributes.first { $0.id == "addressCorrelation" }
    check("the placeholder sentence is dropped", addr?.explanation == "")
    check("a missing displayName falls back to the id",
          parsed.attributes.first { $0.id == "hardwareWalletSupport" }?.name == "Hardware wallets")
    // The order is TOTAL, so a card never reshuffles between opens.
    check("attributes sort by dimension then id",
          parsed.attributes.map(\.id) == ["hardwareWalletSupport", "scamPrevention", "addressCorrelation"])
}

// An unknown verdict must be COUNTED as unrated, never dropped — a dropped attribute
// shrinks the denominator, which inflates coverage.
let oddJSON = """
{"walletId":"w","overall":{"security":{"a":{"evaluation":{"rating":"SOMETHING_NEW"}}}}}
"""
let odd = WalletbeatRatingParse.card(from: Data(oddJSON.utf8), fetchedAt: Date())
check("an unknown verdict is kept as unrated", odd?.attributes.first?.verdict == .unrated)
check("an unknown verdict is not dropped", odd?.attributes.count == 1)

check("a card with no attributes is nil",
      WalletbeatRatingParse.card(from: Data("{\"walletId\":\"w\",\"overall\":{}}".utf8),
                                 fetchedAt: Date()) == nil)
check("garbage is nil",
      WalletbeatRatingParse.card(from: Data("not json".utf8), fetchedAt: Date()) == nil)

print("")
print("Parsing Walletbeat's incidents")
// The real shape, from data/news/2026-08-19-rabby-silent-signature-extraction.ts.
let newsTS = """
import { Severity } from '@/types/content/news'

export default {
\tslug: 'rabby-silent-signature-extraction',
\ttype: NewsType.VULNERABILITY,
\tref: [
\t\t{
\t\t\tlabel: 'V12 on X: Silent signature extraction',
\t\t\turl: 'https://x.com/v12sec/status/2090114226320977931',
\t\t},
\t\t{
\t\t\tlabel: 'Rabby Wallet on X: resolved',
\t\t\turl: 'https://x.com/Rabby_io/status/2090269706087514615',
\t\t},
\t],
\timpact: {
\t\tcategory: ImpactCategory.SIGNING_BUG,
\t\tfundsImpacted: true,
\t},
\tpublishedAt: '2026-08-19',
\tseverity: Severity.LOW,
\tstatus: IncidentStatus.RESOLVED,
\tsummary:
\t\t'A malicious app can   queue a fund-draining signature\nrequest hidden \tby a pop-under bug.',
\ttitle: 'Silent Signature Extraction Vulnerability in Rabby Browser Extension',
\tupdatedAt: '2026-08-20',
\twallets: ['rabby'],
} as const satisfies WalletSecurityNews
"""
let incident = WalletbeatNewsParse.incident(from: newsTS)
check("the incident parses", incident != nil)
if let incident {
    check("slug is read", incident.slug == "rabby-silent-signature-extraction")
    check("title is read", incident.title.hasPrefix("Silent Signature Extraction"))
    // `title:` must not be satisfied by a citation's `label:` field.
    check("title is not a citation label", incident.title.contains("V12") == false)
    check("type is read", incident.type == .vulnerability)
    check("severity is read", incident.severity == .low)
    check("status is read", incident.status == .resolved)
    check("a resolved incident is not open", incident.status.isOpen == false)
    check("wallets are read", incident.wallets == ["rabby"])
    // Nested two tabs deep inside `impact: { … }` — read as nil for every incident until
    // the nested lookup landed.
    check("fundsImpacted is read from inside impact", incident.fundsImpacted == true)
    check("both citations are read", incident.sources.count == 2)
    check("citations keep their order", incident.sources.first?.url.contains("v12sec") == true)
    check("citation labels are paired correctly",
          incident.sources.last?.label == "Rabby Wallet on X: resolved")
    // Collapses a RUN of whitespace, not just the newline — the fixture carries three
    // spaces and a tab on purpose. Without them the newline replacement alone satisfies
    // this and the collapse could be deleted with every check still green (measured).
    check("the summary is unwrapped and runs collapse",
          incident.summary == "A malicious app can queue a fund-draining signature request hidden by a pop-under bug.")
    // `type:` must not be satisfied by `impact.category`.
    check("type is not impact.category", incident.type != .other)
}

// `ref` is EITHER an array OR a single object — measured, BitBox writes `{`.
let singleRef = """
export default {
\tslug: 'x',
\tref: {
\t\tlabel: 'BitBox Blog',
\t\turl: 'https://blog.bitbox.swiss/',
\t},
\tpublishedAt: '2026-08-17',
\ttitle: 'BitBox firmware update',
} as const
"""
let bitbox = WalletbeatNewsParse.incident(from: singleRef)
check("a single-object ref parses", bitbox?.sources.count == 1)
check("its url is read", bitbox?.sources.first?.url == "https://blog.bitbox.swiss/")

// An empty wallets list is REAL — SafePal and Slope name no rated wallet.
let noWallets = WalletbeatNewsParse.incident(from: """
export default {
\tslug: 'safepal',
\tpublishedAt: '2026-08-16',
\tstatus: IncidentStatus.MITIGATED,
\ttitle: 'Unauthorized Access to SafePal Customer Order Information',
\twallets: [],
} as const
""")
check("an empty wallets list still parses", noWallets != nil)
check("an empty wallets list is empty, not a failure", noWallets?.wallets.isEmpty == true)
// MITIGATED is not RESOLVED and is not open either — a contained breach still happened.
check("mitigated is its own status", noWallets?.status == .mitigated)
check("mitigated is not open", noWallets?.status.isOpen == false)

// An unknown severity is nil, NEVER a reassuring default.
check("a missing severity is nil", noWallets?.severity == nil)
// An unknown status reads as unknown, and unknown counts as OPEN — not knowing an
// incident is closed is not the same as knowing it is.
check("a missing status is unknown", noWallets == nil || noWallets!.status == .mitigated)
let noStatus = WalletbeatNewsParse.incident(from: """
export default {
\tslug: 's',
\tpublishedAt: '2026-01-01',
\ttitle: 'T',
} as const
""")
check("no status reads unknown", noStatus?.status == .unknown)
check("unknown counts as open", noStatus?.status.isOpen == true)

// A bare identifier is not an enum member — reading it would be a confident wrong status.
check("a bare identifier is refused",
      WalletbeatNewsParse.enumCase(field: "status", in: "\n\tstatus: someVariable,") == nil)
check("an enum member is read",
      WalletbeatNewsParse.enumCase(field: "status", in: "\n\tstatus: X.RESOLVED,") == "RESOLVED")

// No title or no date means no row.
check("no title is nil", WalletbeatNewsParse.incident(from: "export default {\n\tpublishedAt: '2026-01-01',\n}") == nil)
check("no date is nil", WalletbeatNewsParse.incident(from: "export default {\n\ttitle: 'T',\n}") == nil)

print("")
print("Incident dates")
// NOON UTC, not midnight: a midnight stamp lands on the previous day for every reader
// west of Greenwich, so an incident published today files under yesterday.
var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
if let d = WalletbeatNewsParse.day("2026-08-19") {
    let c = utc.dateComponents([.year, .month, .day, .hour], from: d)
    check("the date is exact", c.year == 2026 && c.month == 8 && c.day == 19)
    check("the hour is noon UTC, not midnight", c.hour == 12)
    // The day must survive a westward timezone, which is the whole reason for noon.
    var la = Calendar(identifier: .gregorian)
    la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    check("the day survives US Pacific", la.dateComponents([.day], from: d).day == 19)
} else {
    check("the date parses", false)
}
check("a malformed date is nil", WalletbeatNewsParse.day("19-08-2026") == nil)
check("month 13 is refused", WalletbeatNewsParse.day("2026-13-01") == nil)
check("year 1200 is refused", WalletbeatNewsParse.day("1200-01-01") == nil)

check("a slug is cut from a filename",
      WalletbeatNewsParse.slug(fromFilename: "2026-08-19-rabby-silent-signature-extraction.ts")
        == "rabby-silent-signature-extraction")

print("")
print("Severity order")
check("critical outranks high", WalletbeatSeverity.critical > WalletbeatSeverity.high)
check("high outranks medium", WalletbeatSeverity.high > WalletbeatSeverity.medium)
check("medium outranks low", WalletbeatSeverity.medium > WalletbeatSeverity.low)

print("")
print("The room head")

func item(_ name: String, counts c: WalletbeatCounts, lead: WalletbeatLead,
          open: Int = 0, recent: Int = 0, read: Bool = true) -> WalletbeatRoom.Item {
    WalletbeatRoom.Item(id: "walletbeat:wallet:\(name.lowercased())",
                        walletID: name.lowercased(), name: name, hardware: false,
                        counts: c, lead: lead, openIncidents: open,
                        recentIncidents: recent, read: read)
}

let failAttr = attribute("scamPrevention", .security, .fail, "leaks your browsed websites")
let rabby = item("Rabby", counts: counts(pass: 5, partial: 5, fail: 15, unrated: 4),
                 lead: .finding(failAttr))
let ledger = item("Ledger", counts: counts(unrated: 25), lead: .unexamined(applicable: 25))
let clean2 = item("Frame", counts: counts(pass: 8, unrated: 2),
                  lead: .noFailures(judged: 8, applicable: 10))

// An unresolved incident outranks every rating.
let ranked = WalletbeatRoom.ranked([rabby, ledger, item("Zerion", counts: counts(pass: 7, fail: 12, unrated: 5), lead: .finding(failAttr), open: 1)])
check("an unresolved incident leads", ranked.first?.name == "Zerion")

// A wallet with findings outranks one nobody has looked at — the head surfaces what is
// knowable, and an unexamined wallet sorts low because there is nothing to read.
check("a rated wallet outranks an unexamined one",
      WalletbeatRoom.ranked([ledger, rabby]).first?.name == "Rabby")
check("a failing wallet outranks a clean one",
      WalletbeatRoom.ranked([clean2, rabby]).first?.name == "Rabby")

// TOTAL order — a head that reshuffles over unchanged data reads as broken.
let a1 = item("Alpha", counts: counts(pass: 8, unrated: 2), lead: .noFailures(judged: 8, applicable: 10))
let b1 = item("Beta", counts: counts(pass: 8, unrated: 2), lead: .noFailures(judged: 8, applicable: 10))
check("ties fall through to the name",
      WalletbeatRoom.ranked([b1, a1]).map(\.name) == ["Alpha", "Beta"])
check("ranking is stable across calls",
      WalletbeatRoom.ranked([b1, a1]).map(\.name) == WalletbeatRoom.ranked([a1, b1]).map(\.name))

let room = WalletbeatRoom(items: [rabby, ledger], total: 2, snapshotDay: "2026-08-20")
check("the headline names the top wallet", WalletbeatRoom.headline(room).contains("Rabby"))
check("the note reports coverage, not the headline again",
      WalletbeatRoom.note(room).contains("1 of 2"))
check("the coverage note attributes", WalletbeatRoom.coverageNote(room)?.contains("Walletbeat") == true)
check("examined counts only wallets past the gate", room.examined == 1)
check("a room with items is not empty", room.isEmpty == false)

// When the best-ranked wallet is unexamined, SAY SO rather than reaching down the list.
let allThin = WalletbeatRoom(items: [ledger], total: 1, snapshotDay: "2026-08-20")
check("an unexamined top wallet is stated plainly",
      WalletbeatRoom.headline(allThin).contains("hasn't examined"))

// An unresolved incident is said in words in the headline.
let alarmed = WalletbeatRoom(items: [item("Zerion", counts: counts(pass: 7, fail: 12, unrated: 5),
                                          lead: .finding(failAttr), open: 1)],
                             total: 1, snapshotDay: "2026-08-20")
check("an open incident leads the headline",
      WalletbeatRoom.headline(alarmed).contains("unresolved"))

// A wallet whose ratings have not been read yet must not read as unrated.
let unread = item("New", counts: counts(unrated: 29), lead: .unexamined(applicable: 29), read: false)
check("an unread wallet says it is being read",
      WalletbeatRoom.leadLine(unread).contains("Reading"))
// Asserted on the MEANING, not the exact wording: the shipped copy is "Not rated yet",
// and pinning the whole string makes a copy tweak look like a logic break.
check("an unexamined wallet says not rated",
      WalletbeatRoom.leadLine(ledger).contains("Not rated"))
check("a finding shows Walletbeat's own sentence",
      WalletbeatRoom.leadLine(rabby) == "leaks your browsed websites")

// The cap must be visible in the coverage note, so the headline can't disagree with it.
let capped = WalletbeatRoom(items: [rabby, ledger], total: 5, snapshotDay: "2026-08-20")
check("a folded tail is named", WalletbeatRoom.coverageNote(capped)?.contains("2 of 5") == true)

print("")
print("Sheet anatomies")

func facts(_ ref: String?, source: String = "Walletbeat",
           receipt: Bool = false) -> WalletbeatSheet.Facts {
    WalletbeatSheet.Facts(source: source, sourceRef: ref, isImportReceipt: receipt)
}

check("a watch ref draws the wallet anatomy",
      WalletbeatSheet.shape(facts("walletbeat:wallet:rabby")) == .wallet)
check("a news ref draws the incident anatomy",
      WalletbeatSheet.shape(facts("walletbeat:news:some-slug")) == .incident)
check("a revision ref draws the revision anatomy",
      WalletbeatSheet.shape(facts("walletbeat:rev:rabby:appIsolation:FAIL:2026-07-20")) == .revision)

// Our own note about a sync is not one of these records.
check("an import receipt keeps the generic sheet",
      WalletbeatSheet.shape(facts("walletbeat:news:x", receipt: true)) == nil)
check("another source is never claimed",
      WalletbeatSheet.shape(facts("walletbeat:wallet:rabby", source: "Wallet")) == nil)
check("a ref-less row keeps the generic sheet",
      WalletbeatSheet.shape(facts(nil)) == nil)
check("an unknown namespace keeps the generic sheet",
      WalletbeatSheet.shape(facts("walletbeat:other:x")) == nil)

// The ref grammar is ONE grammar — the producer and the parser read the same constants.
check("the wallet prefix is shared", WalletbeatIdentity.walletPrefix == "walletbeat:wallet:")
check("the news prefix is shared", WalletbeatNewsParse.refPrefix == WalletbeatIdentity.newsPrefix)

print("")
print("A revision, read back out of its own ref")
let rev = WalletbeatSheet.revision(
    fromRef: "walletbeat:rev:rabby:appIsolation:FAIL:2026-07-20")
check("the wallet is read", rev?.walletID == "rabby")
check("the attribute is read", rev?.attributeID == "appIsolation")
check("the verdict is read", rev?.after == .fail)
check("the day is read", rev?.day == "2026-07-20")

// A revision landed before the entry carried a date — the stamp is empty, not absent.
let noDay = WalletbeatSheet.revision(fromRef: "walletbeat:rev:rabby:appIsolation:PASS:")
check("an empty day reads as none", noDay?.day == nil)
check("the rest still parses", noDay?.after == .pass)

check("a non-revision ref is refused",
      WalletbeatSheet.revision(fromRef: "walletbeat:news:x") == nil)
check("a truncated ref is refused",
      WalletbeatSheet.revision(fromRef: "walletbeat:rev:rabby") == nil)
// An unknown verdict must not become a confident wrong one.
check("an unknown verdict is refused",
      WalletbeatSheet.revision(fromRef: "walletbeat:rev:r:a:NONSENSE:2026-01-01") == nil)
check("an empty wallet id is refused",
      WalletbeatSheet.revision(fromRef: "walletbeat:rev::a:PASS:2026-01-01") == nil)

print("")
print("The bundled directory")
check("the directory is populated", WalletbeatDirectory.wallets.count >= 30)
check("it carries software and hardware",
      WalletbeatDirectory.wallets.contains { $0.hardware }
        && WalletbeatDirectory.wallets.contains { !$0.hardware })
check("every entry has an id and a name",
      WalletbeatDirectory.wallets.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
check("ids are unique",
      Set(WalletbeatDirectory.wallets.map(\.id)).count == WalletbeatDirectory.wallets.count)
check("every entry has at least one dimension",
      WalletbeatDirectory.wallets.allSatisfy { !$0.dimensions.isEmpty })
// The measured reality this feature is shaped around — if this ever stops holding, the
// coverage-first design should be revisited rather than silently kept.
check("most wallets are still mostly unrated (the finding §419 rests on)",
      WalletbeatDirectory.wallets.filter { $0.coverage == .deep }.count
        < WalletbeatDirectory.wallets.count / 2)
check("a page URL is built for every entry",
      WalletbeatDirectory.wallets.allSatisfy { $0.pageURL != nil })
// maintenance is hardware-only in Walletbeat's own schema.
check("no software wallet carries a maintenance group",
      WalletbeatDirectory.wallets.filter { !$0.hardware }
        .allSatisfy { !$0.dimensions.contains(.maintenance) })
check("the demo's wallets are all in the directory",
      ["rabby", "metamask", "ledger"].allSatisfy { id in
          WalletbeatDirectory.wallets.contains { $0.id == id }
      })
check("the demo's attributes are seeded",
      ["rabby", "metamask", "ledger"].allSatisfy {
          (WalletbeatDirectory.demoAttributes[$0]?.isEmpty == false)
      })
// The demo must exercise BOTH sides of the gate, or it demos a feature that isn't there.
let demoDeep = WalletbeatDirectory.demoAttributes["rabby"].map { attrs -> Bool in
    let c = attrs.reduce(WalletbeatCounts.zero) { acc, a in
        acc + WalletbeatCounts(pass: a.verdict == .pass ? 1 : 0,
                              partial: a.verdict == .partial ? 1 : 0,
                              fail: a.verdict == .fail ? 1 : 0,
                              unrated: a.verdict == .unrated ? 1 : 0,
                              exempt: a.verdict == .exempt ? 1 : 0)
    }
    return WalletbeatCoverage.of(c).showsShape
} ?? false
let demoThin = WalletbeatDirectory.demoAttributes["ledger"].map { attrs -> Bool in
    let c = attrs.reduce(WalletbeatCounts.zero) { acc, a in
        acc + WalletbeatCounts(pass: a.verdict == .pass ? 1 : 0,
                              partial: a.verdict == .partial ? 1 : 0,
                              fail: a.verdict == .fail ? 1 : 0,
                              unrated: a.verdict == .unrated ? 1 : 0,
                              exempt: a.verdict == .exempt ? 1 : 0)
    }
    return WalletbeatCoverage.of(c).showsShape == false
} ?? false
check("the demo seeds a wallet past the coverage gate", demoDeep)
check("the demo seeds a wallet below it, so 'not rated' is demoed too", demoThin)

print("")
if failures > 0 {
    print("walletbeat-selftest: ✗ \(failures) assertion(s) failed")
    exit(1)
}
print("walletbeat-selftest: OK — every assertion passed against the shipped source.")
SWIFT

build() { swiftc -O -o "$TMP/wb-selftest" "$1" "$2" "$3" "$4" "$SHEET" "$TMP/main.swift" 2>"$TMP/build.log"; }

echo "Assertions (shipped source, compiled whole)"
if ! build "$RATING" "$NEWS" "$ROOM" "$DIR"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/wb-selftest"

# --------------------------------------------------------------------------------------
# 3 · Mutations. A check that cannot fail proves nothing.
# --------------------------------------------------------------------------------------
echo ""
echo "Mutations (each must be caught)"

mutate() { # mutate <name> <rating|news|room> <from> <to>
  local name="$1" which="$2" from="$3" to="$4"
  local a="$TMP/m-rating.swift" b="$TMP/m-news.swift" c="$TMP/m-room.swift" d="$TMP/m-sheet.swift"
  cp "$RATING" "$a"; cp "$NEWS" "$b"; cp "$ROOM" "$c"; cp "$SHEET" "$d"
  local target="$a"
  [[ "$which" == "news" ]] && target="$b"
  [[ "$which" == "room" ]] && target="$c"
  [[ "$which" == "sheet" ]] && target="$d"
  # Literal replacement through env, never a regex — escaping killed the first cut of
  # every harness in this tree that tried it.
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$a" "$b" "$c" "$DIR" "$d" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# THE gate. Letting `.thin` draw a shape is the failure the whole feature is built around.
mutate "thin coverage may not draw a shape" rating \
  'var showsShape: Bool { self == .deep || self == .partial }' \
  'var showsShape: Bool { self != .none }'

# The floors are measured; moving them regroups the wallets.
mutate "the deep floor is load-bearing" rating \
  'static let deepFloor = 0.7' 'static let deepFloor = 0.2'
mutate "the partial floor is load-bearing" rating \
  'static let partialFloor = 0.3' 'static let partialFloor = 0.01'

# EXEMPT folded into the coverage gap under-reports how much was examined.
mutate "exempt must leave the denominator" rating \
  'var applicable: Int { total - exempt }' 'var applicable: Int { total }'
mutate "exempt is not a judgment" rating \
  'self == .pass || self == .partial || self == .fail' \
  'self == .pass || self == .partial || self == .fail || self == .exempt'

# Coverage must outrank a finding, or one FAIL from two judged attributes implies the rest are fine.
mutate "thin coverage outranks a finding" rating \
  'case .thin:
			return .barelyExamined(judged: counts.judged, applicable: counts.applicable)' \
  'case .thin:
			return firstAttribute(verdict: .fail).map { WalletbeatLead.finding($0) } ?? .barelyExamined(judged: counts.judged, applicable: counts.applicable)'

# A withdrawn rating reported as news reads as a downgrade of the wallet.
mutate "a withdrawn rating stays unreported" rating \
  'guard was.verdict != attribute.verdict, attribute.verdict.isJudged else { continue }' \
  'guard was.verdict != attribute.verdict else { continue }'

# A dropped attribute inflates coverage — the one number this file exists to keep honest.
mutate "an unknown verdict is kept" rating \
  'let verdict = WalletbeatVerdict(rawValue: verdictText) ?? .unrated' \
  'guard let verdict = WalletbeatVerdict(rawValue: verdictText) else { continue }'

# Placeholder prose is not a finding.
mutate "the placeholder sentence is dropped" rating \
  'placeholders.contains(explanation) ? "" : explanation' 'explanation'

# Midnight files an incident under the previous day west of Greenwich.
mutate "incident dates are noon UTC" news 'components.hour = 12' 'components.hour = 0'

# A default severity puts a reassuring word we invented next to their name.
mutate "a missing severity stays nil" news \
  'severity: severityRaw.flatMap(WalletbeatSeverity.init(rawValue:)),' \
  'severity: severityRaw.flatMap(WalletbeatSeverity.init(rawValue:)) ?? .low,'

# Not knowing an incident is closed is not knowing it is.
mutate "unknown status counts as open" news \
  'var isOpen: Bool { self == .ongoing || self == .unknown }' \
  'var isOpen: Bool { self == .ongoing }'

# Mitigated folded into resolved loses the distinction a security feed exists for.
mutate "mitigated is not resolved" news \
  'case mitigated = "MITIGATED"' 'case mitigated = "RESOLVED_TOO"'

# A bare identifier read as an enum member is a confident wrong status.
mutate "a bare identifier is refused" news \
  'guard token.contains(".") else { return nil }' 'guard !token.isEmpty else { return nil }'

# The formatter's line breaks must not survive into a row.
mutate "wrapped prose is unwrapped" news \
  '.split(separator: " ", omittingEmptySubsequences: true)
			.joined(separator: " ")' \
  '.split(separator: "\u{1}", omittingEmptySubsequences: true)
			.joined(separator: " ")'

# An open incident that stops leading is an alarm nobody sees.
mutate "an unresolved incident leads the ranking" room \
  'if a.openIncidents != b.openIncidents { return a.openIncidents > b.openIncidents }' \
  'if a.openIncidents != b.openIncidents { return a.openIncidents < b.openIncidents }'

# A head that reshuffles over unchanged data reads as broken.
mutate "the ranking is total" room \
  'return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending' \
  'return false'

# An unexamined wallet outranking a rated one would lead with "nothing is known".
mutate "an unexamined wallet does not outrank a rated one" room \
  'case .barelyExamined, .unexamined: return 0' \
  'case .barelyExamined, .unexamined: return 9'

# A wallet still being read must not be reported as unrated.
mutate "an unread wallet is not called unrated" room \
  'guard item.read else { return String(localized: "Reading Walletbeat…") }' \
  'guard true else { return String(localized: "Reading Walletbeat…") }'

# A namespace that matches everything makes every row claim an anatomy — including our
# own import receipt, which would open a wallet report card for a note about a sync.
mutate "the sheet namespace is exact" sheet \
  'if ref.hasPrefix(WalletbeatIdentity.walletPrefix) { return .wallet }' \
  'if ref.hasPrefix("walletbeat") { return .wallet }'

# An import receipt claiming an anatomy is the same failure from the other side.
mutate "an import receipt is excluded" sheet \
  'guard f.source == WalletbeatIdentity.source, !f.isImportReceipt else { return nil }' \
  'guard f.source == WalletbeatIdentity.source else { return nil }'

# An unparseable verdict read as a real one puts a confident wrong word on the sheet.
mutate "an unknown verdict is refused" sheet \
  'guard let verdict = WalletbeatVerdict(rawValue: parts[2]) else { return nil }' \
  'let verdict = WalletbeatVerdict(rawValue: parts[2]) ?? .unrated'

echo ""
echo "walletbeat-selftest: OK — assertions pass and every mutation is caught."
