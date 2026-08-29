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
ROUTE="Casberi/Casberi/Shell/HomeRoute.swift"
SURFACE="Casberi/Casberi/Shell/MainSurface.swift"
DEMO="Casberi/Casberi/Model/DemoSeedAll.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
SHEET="Casberi/Casberi/Model/WalletbeatSheet.swift"
MATCH="Casberi/Casberi/Model/WalletbeatMatch.swift"
APPS="Casberi/Casberi/Model/WalletConnectApps.swift"
WCBRIDGE="Casberi/Casberi/Model/WalletConnectBridge.swift"
SETUP="Casberi/Casberi/Screens/WalletbeatScreen.swift"
SHEETSRC="Casberi/Casberi/Model/WalletbeatSheetSource.swift"
SHEETVIEWS="Casberi/Casberi/Screens/WalletbeatSheetViews.swift"
CARDSCREEN="Casberi/Casberi/Screens/WalletbeatCardScreen.swift"
FIGURE="Casberi/Casberi/Model/RoomFigure.swift"
SHEETVIEW="Casberi/Casberi/Screens/ThingSheetView.swift"
RETRIEVER="Casberi/Casberi/Model/Retriever.swift"
SNAP="scripts/walletbeat-snapshot.py"

for f in "$RATING" "$NEWS" "$ROOM" "$DIR" "$BRIDGE" "$SRC" "$VIEWS" "$ROWS" "$CARD" "$DIRSCREEN" "$SHEET" "$SHEETSRC" "$SHEETVIEWS" "$CARDSCREEN" "$MATCH" "$APPS" "$WCBRIDGE" "$SETUP" "$SNAP"; do
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
strip_comments "$DEMO" > "$TMP/demo.nc"

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
# --------------------------------------------------------------------------------------
# The two tiers (prd §421). Following alone reads the incidents; watching adds the cards.
#
# Every one of these guards a failure that is SILENT: the seat simply goes quiet, which
# from outside is indistinguishable from Walletbeat having published nothing. That is
# §311 exactly, and it is the shape this bridge already shipped once — the incident read
# was gated on the watch list while the incidents themselves were never filtered by it.
# --------------------------------------------------------------------------------------
guard 'guard WalletbeatWatch.following || !watched.isEmpty' "$TMP/bridge.nc" \
  "the sync is gated on the watch list again — following alone would read nothing, silently"
guard 'guard following || count > 0' "$TMP/bridge.nc" \
  "the seat no longer registers for a follower — no seat means BridgeRefresh never sweeps it"
guard 'following = true' "$TMP/bridge.nc" \
  "watching no longer implies following — the incidents would stop arriving for a watcher"
guard 'following = false' "$TMP/bridge.nc" \
  "disconnect no longer clears the follow flag — the seat would re-register itself"
# The room composes for EITHER tier. Demanding a watch here is the same silent gate one
# file over: incidents land, the chip appears, and the head returns nil above them.
guard '!watches.isEmpty || !incidents.isEmpty' "$TMP/src.nc" \
  "the room head demands a watched wallet again — a follower's incidents would head nothing"
guard 'newsSummary(incidents' "$TMP/src.nc" \
  "the room no longer summarises the incidents — the followed head has nothing to say"
# §234's ruling: a browse is mounted by the ROOM, "never by a setup screen". Routing
# through the connect screen is what made reading the list a trip into the catalog.
guard 'route.path.append(.walletbeatDirectory)' "$FEED" \
  "the room's browse no longer opens the directory directly"
guard 'case walletbeatDirectory' "$ROUTE" \
  "the directory lost its own route node — the room can only reach it via the catalog"
guard 'case .walletbeatDirectory:' "$SURFACE" \
  "the directory route node is declared but never resolved to a screen"
if grep -qF 'route.path.append(.bridge(.walletbeat))' "$FEED"; then
  echo "✗ the room's browse pushes the CONNECT screen again (§234 — connecting is not browsing)"
  exit 1
fi
guard 'walletbeatFollow' "$PROBES" \
  "-walletbeatFollow is gone; following with nothing watched has no headless door"

# --------------------------------------------------------------------------------------
# Whether a row is about a wallet YOU use, and whether a wallet has an open incident
# (prd §422). Both facts were landed and on no screen; both are read from the BOOK.
#
# THE BOOK, NEVER `authorHandle`, and this is the guard worth understanding: the row
# stamps `wallets.first` only, so an incident Walletbeat files under SafePal AND Ledger
# reaches a Ledger user's feed wearing no marker at all if the join goes through the row.
# The failure is silent and it is exactly backwards — the multi-wallet incidents are the
# serious ones.
# --------------------------------------------------------------------------------------
guard 'WalletbeatIncidentBook.facts(ref: thing.sourceRef)' "$ROWS" \
  "the news row no longer reads the incident book — a multi-wallet incident would lose its marker"
guard 'var watchedWallets: Set<String> = []' "$ROWS" \
  "the news row no longer takes the watch list; it would have to fetch, which a row must never do"
guard 'watchedWallets: walletbeatWatchedIDs' "$FEED" \
  "FeedScreen no longer hands the room's watch list to its incident rows"
guard 'WalletbeatWatch.walletID(from: $0)' "$FEED" \
  "the feed's watch list is no longer derived from the room's own rows"
# A row must not fetch. The whole reason the set is handed in is that the room already
# holds the watch rows a fetch would go looking for.
if grep -qE 'FetchDescriptor|modelContext' "$ROWS"; then
  echo "✗ a Walletbeat row fetches — the watch list is handed in precisely so it cannot"
  exit 1
fi
guard 'openIncidents.contains(entry.id)' "$DIRSCREEN" \
  "the directory stopped marking wallets with an unresolved incident"
guard '.filter { $0.status.isOpen }' "$DIRSCREEN" \
  "the directory marks RESOLVED incidents too — a permanent warning on a wallet whose bug was fixed"
guard 'WalletbeatIncidentBook.forgetDemo(demoWalletbeatSlugs)' "$TMP/demo.nc" \
  "the demo no longer forgets its seeded incidents by slug (§401 — a dev install holds real ones)"
# THE CALL, not the declaration, and on a STRIPPED copy — two corrections, both bought
# by mutating the real tree. Commenting the call out left the literal in the file (the
# Obsidian/Cursor lesson), and stripping comments alone STILL passed, because the bare
# name also appears in `private static func seedWalletbeatIncidents() {`. A guard that
# matches a function's own declaration proves the function exists, never that anything
# calls it — which is the whole failure it was written to catch.
# Spelled out rather than through `guard`, which is `grep -F` here: this one needs a
# REGEX to tell the call from the declaration, and a fixed string cannot.
if grep -qE '^[[:space:]]+seedWalletbeatIncidents\(\)$' "$TMP/demo.nc"; then
  echo "  ✓ the demo seeds the incident book"
else
  echo "✗ the demo no longer seeds the incident book — the sheet's fact card and both new markers read empty"
  exit 1
fi
# The demo must never claim a named company currently has an unpatched hole. Its own
# ruling, and the reason the OPEN branch stays undemoed.
if grep -qE 'status: \.ongoing' "$TMP/demo.nc"; then
  echo "✗ the demo seeds an ONGOING incident — it must not assert a real company is currently exposed"
  exit 1
fi

# --------------------------------------------------------------------------------------
# The WalletConnect join, the incident's door, and the revision's before (prd §430).
#
# The join's failure is SILENT in the way this bridge has already shipped once: no offer
# appears, and from outside that is indistinguishable from having connected no wallet at
# all. Every guard here defends one link of a chain nothing else in the tree can see.
# --------------------------------------------------------------------------------------
strip_comments "$WCBRIDGE" > "$TMP/wc.nc"
strip_comments "$APPS" > "$TMP/apps.nc"
strip_comments "$CARD" > "$TMP/card.nc"
strip_comments "$SHEETVIEWS" > "$TMP/sheetviews.nc"

# BOTH connect paths, counted rather than merely present: `connect(open:)` and
# `connectViaModal` are two doors to the same handshake, and a person on a phone takes the
# modal one — a guard satisfied by the other door would prove nothing about them.
wc_records=$(grep -cF 'WalletConnectApps.record(appNamed: session.peer.name)' "$TMP/wc.nc" || true)
if [[ "$wc_records" != "2" ]]; then
  echo "✗ the peer name is recorded on $wc_records of the 2 connect paths — the modal path is the one a phone takes"
  exit 1
fi
# POSITIONALLY, because both orders compile and which comes first is the entire feature
# (§424's lesson): the session is destroyed the moment it is read, so a record placed after
# the teardown is reading a session that no longer exists.
if ! python3 - "$TMP/wc.nc" <<'PYW'
import sys
lines = open(sys.argv[1]).read().split("\n")
rec = [i for i, l in enumerate(lines) if "WalletConnectApps.record(appNamed:" in l]
tear = [i for i, l in enumerate(lines) if "tearDownShielded(topic:" in l]
sys.exit(0 if len(rec) == 2 and len(tear) >= 2 and all(r < t for r, t in zip(rec, sorted(tear))) else 1)
PYW
then
  echo "✗ the peer name is recorded AFTER the session is torn down — there is nothing left to read"
  exit 1
fi
# THE RAW NAME, never a resolved id. Resolving at write time freezes today's directory into
# the record, so a wallet Walletbeat adds later is never offered to somebody who connected
# with it last year — and it is what makes every held item in §430 §5 cheap.
if grep -qE 'WalletbeatMatch|WalletbeatDirectory|WalletbeatEntry' "$TMP/apps.nc"; then
  echo "✗ the sightings book resolves a wallet id at write time — it must store the app's raw name"
  exit 1
fi
# Not Walletbeat's data (§401's by-name rule): the seat's teardown takes what the SEAT
# planted, and this was planted by the WalletConnect flow.
if grep -qF 'WalletConnectApps.forgetAll()' "$TMP/bridge.nc"; then
  echo "✗ Walletbeat's disconnect clears the WalletConnect sightings — they are not its data"
  exit 1
fi
guard 'WalletbeatWatch.connectedSuggestions(context: modelContext)' "$SETUP" \
  "the setup screen no longer offers the wallets you have connected with — naming is homework again"
guard 'WalletbeatWatch.connectedIDs()' "$DIRSCREEN" \
  "the directory no longer marks the wallets whose apps have really connected here"
guard 'WalletbeatCopy.connectedMarker' "$DIRSCREEN" \
  "the directory spells its own marker — three surfaces describing one fact in three words"
guard 'WalletbeatRoom.browseLabel(room)' "$CARD" \
  "the room card composes its own button label — the one piece of this room's copy nothing proves"
# The NEGATIVE half: a label composed in the view is a label the harness never sees.
if grep -qF 'Watch the wallet apps you use' "$TMP/card.nc"; then
  echo "✗ the room card carries button copy of its own again (§430 — every word lives in WalletbeatRoom)"
  exit 1
fi
guard 'connectedName: connectedName' "$TMP/src.nc" \
  "the room source no longer carries the connected wallet through — the button can never name one"
guard 'watched: watches.compactMap { WalletbeatWatch.walletID(from: $0) }' "$TMP/src.nc" \
  "the head's offer no longer excludes on the rows it is holding — it could offer a wallet it draws as watched"
guard 'walletbeatConnectedApp' "$PROBES" \
  "-walletbeatConnectedApp is gone; a sighting has no headless door and no simulator can make one"

# The before, written and read. Appended LAST so a four-component ref keeps parsing.
guard ':\(revision.before.rawValue)' "$TMP/bridge.nc" \
  "a revision no longer records the verdict it moved from"
guard 'parts.count > 4 ? WalletbeatVerdict(rawValue: parts[4]) : nil' "$SHEET" \
  "the revision ref's before is read from the wrong component, or not at all"
guard 'if let before = revision.before {' "$TMP/sheetviews.nc" \
  "the revision sheet stopped drawing the pair — it would show only where a rating landed"

# The card says what has moved, and the incident is a door to the card.
guard 'WalletbeatSheetSource.revisions(forWallet: walletID, context: modelContext)' "$CARDSCREEN" \
  "the report card no longer joins the revisions it has landed — 'what changed?' is unanswerable again"
guard 'revision: revised[attribute.id]' "$CARDSCREEN" \
  "the card joins revisions and never hands them to a row"
guard 'WalletbeatCardScreen(walletID: walletID)' "$TMP/sheetviews.nc" \
  "an incident no longer opens the report card of a wallet it names — the sheet is a dead end again"
# A wallet Walletbeat does not rate has no card, so it must not be offered one (§83).
guard 'if let entry = WalletbeatDirectory.wallets.first(where: { $0.id == id })' "$TMP/sheetviews.nc" \
  "an unrated wallet is offered a report card that does not exist"

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
print("The followed head — no wallet watched (prd §421)")

func newsRoom(total: Int, open: Int = 0, recent: Int = 0) -> WalletbeatRoom {
    WalletbeatRoom(items: [], total: 0, snapshotDay: "2026-08-20",
                   news: WalletbeatRoom.News(total: total, open: open, recent: recent))
}

// STANDING outranks volume: one thing still open asks something of you, a busy month
// that closed does not.
let openOne = newsRoom(total: 9, open: 1, recent: 4)
check("an unresolved incident leads the followed head",
      WalletbeatRoom.headline(openOne).contains("unresolved"))
check("one is said as one, not as a figure",
      WalletbeatRoom.headline(openOne).contains("One"))
let openMany = newsRoom(total: 12, open: 3, recent: 9)
check("several unresolved are counted",
      WalletbeatRoom.headline(openMany).contains("3"))
// The busier window must NOT win while something is open — this fixture has nine recent
// against one open, so it fails if the order is ever flipped.
check("open beats recent even when recent is far larger",
      WalletbeatRoom.headline(newsRoom(total: 20, open: 1, recent: 19)).contains("unresolved"))

// COUNTED, not merely dated: the quiet sentence also ends in "in the last 30 days", so a
// fixture asserting that phrase passes whether or not the recent branch was reached. Its
// first cut did exactly that and the mutation survived — a fixture only tests the rule it
// names if it fails that rule and passes every other one.
let recentOnly = newsRoom(total: 9, open: 0, recent: 2)
check("a closed but recent window says how many, in the window",
      WalletbeatRoom.headline(recentOnly).contains("2 wallet security incidents in the last 30 days"))
check("a recent window is never reported as quiet",
      WalletbeatRoom.headline(recentOnly).hasPrefix("No") == false)
check("one recent incident is said as one",
      WalletbeatRoom.headline(newsRoom(total: 3, open: 0, recent: 1)).contains("One wallet security incident in the last 30 days"))
check("a closed window never says unresolved",
      WalletbeatRoom.headline(recentOnly).contains("unresolved") == false)

let quiet = newsRoom(total: 9, open: 0, recent: 0)
check("a quiet window is a real answer, not an empty frame",
      WalletbeatRoom.headline(quiet).contains("No wallet security incidents"))

// THE HONESTY GATE, and the sharpest thing here: nothing landed is a fact about the READ,
// never a clean bill of health for thirty-two wallets.
let nothingRead = WalletbeatRoom(items: [], total: 0, snapshotDay: "2026-08-20", news: nil)
check("no incident landed reads as reading, not as none exist",
      WalletbeatRoom.headline(nothingRead).contains("Reading"))
check("no incident landed never claims a quiet window",
      WalletbeatRoom.headline(nothingRead).contains("No wallet security") == false)

// The second line is always the upgrade — what following does NOT cover. THE REASON,
// NOT THE VERB (2026-08-29): the button one line below is the instruction, and the note
// carried it too, in a different word ("Name" against the button's "Watch").
check("the followed note says what the upgrade adds",
      WalletbeatRoom.note(openOne).contains("where its keys are made"))
check("the followed note before anything lands still names the upgrade",
      WalletbeatRoom.note(nothingRead).contains("Watching the wallet you use"))
check("the followed note leaves the verb to the button",
      !WalletbeatRoom.note(openOne).contains("Name the wallet apps"))

// It never names a wallet: the incidents are rows directly beneath, and promoting one of
// thirty-two into the headline reads as a warning about software you may not use.
check("the followed headline names no wallet",
      WalletbeatRoom.headline(openOne).contains("Rabby") == false)

check("a followed room attributes in its small print",
      WalletbeatRoom.coverageNote(openOne)?.contains("Walletbeat") == true)
check("a room with neither wallets nor news has no small print",
      WalletbeatRoom.coverageNote(nothingRead) == nil)
check("a followed room is empty of wallets", openOne.isEmpty)

// A watched room still carries the news summary without letting it take the headline —
// the wallet you named outranks the ecosystem.
let watchedWithNews = WalletbeatRoom(items: [rabby], total: 1, snapshotDay: "2026-08-20",
                                     news: WalletbeatRoom.News(total: 9, open: 2, recent: 3))
check("a watched wallet still leads its own head",
      WalletbeatRoom.headline(watchedWithNews).contains("Rabby"))

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


// --------------------------------------------------------------------------------------
// The WalletConnect join (prd §430).
//
// A MISS COSTS NOTHING and a WRONG MATCH offers somebody a security review of software
// they do not run, so every assertion below is about refusing rather than reaching.
// --------------------------------------------------------------------------------------
print("")
print("Which wallet app you use")

check("a plain name is its own key", WalletbeatMatch.key("Rabby") == "rabby")
check("case and spacing collapse", WalletbeatMatch.key("  MetaMask ") == "metamask")
check("punctuation is a separator, not a character",
      WalletbeatMatch.key("Safe{Wallet}") == "safe")
check("an id's own separators collapse the same way",
      WalletbeatMatch.key("uniswap-wallet") == "uniswap")

// THE MEASURED TRANSFORM. Walletbeat appends "Wallet" where the app itself does not, so
// without this the join misses nearly every hardware wallet in the registry — and misses
// silently, which is the whole failure class.
check("Walletbeat's trailing 'Wallet' is dropped",
      WalletbeatMatch.key("Ledger Wallet") == "ledger")
check("...so the app's own name lands on the same key",
      WalletbeatMatch.key("Ledger") == WalletbeatMatch.key("Ledger Wallet"))
check("a wallet actually called Wallet keeps its name",
      WalletbeatMatch.key("Wallet") == "wallet")
check("only a TRAILING 'wallet' goes", WalletbeatMatch.key("Wallet Guard") == "walletguard")
check("nothing but punctuation is not a name", WalletbeatMatch.key(" -- ") == nil)
check("an empty name is not a name", WalletbeatMatch.key("") == nil)

// The collision the transform could have caused, and did not. SafePal is named in
// Walletbeat's own incident feed, so folding it onto Safe would mark the wrong wallet.
check("stripping 'wallet' does not fold SafePal onto Safe",
      WalletbeatMatch.key("SafePal") != WalletbeatMatch.key("Safe{Wallet}"))

let real = WalletbeatDirectory.wallets.map { (id: $0.id, name: $0.name) }

// AGAINST THE SHIPPED SNAPSHOT, not a fixture: the table is built out of Walletbeat's own
// names, so a rename on their side is what would break it, and this is where that gets
// caught. A key claimed by two wallets resolves to NOTHING by design — this asserts the
// design never has to fire.
var claimed: [String: Set<String>] = [:]
for entry in real {
    for spelling in [entry.name, entry.id] {
        if let k = WalletbeatMatch.key(spelling) { claimed[k, default: []].insert(entry.id) }
    }
}
check("no two rated wallets share a comparison key",
      claimed.allSatisfy { $0.value.count == 1 })
check("every rated wallet resolves from its own display name",
      real.allSatisfy { WalletbeatMatch.walletID(forAppNamed: $0.name, in: real) == $0.id })
check("every rated wallet resolves from Walletbeat's own id",
      real.allSatisfy { WalletbeatMatch.walletID(forAppNamed: $0.id, in: real) == $0.id })

// The three the transform exists for, named individually so a regression says WHICH.
check("Ledger resolves", WalletbeatMatch.walletID(forAppNamed: "Ledger", in: real) == "ledger")
check("Trezor resolves", WalletbeatMatch.walletID(forAppNamed: "Trezor", in: real) == "trezor")
check("Keystone resolves", WalletbeatMatch.walletID(forAppNamed: "Keystone", in: real) == "keystone")
check("Safe's own app name resolves",
      WalletbeatMatch.walletID(forAppNamed: "Safe{Wallet}", in: real) == "safe")
check("an id Walletbeat spells its own way resolves",
      WalletbeatMatch.walletID(forAppNamed: "OneKey", in: real) == "onekey")

// A wallet Walletbeat does not rate is the COMMON answer here and must be silent.
check("a wallet Walletbeat does not rate resolves to nothing",
      WalletbeatMatch.walletID(forAppNamed: "Trust Wallet", in: real) == nil)
check("a near-miss is not a match",
      WalletbeatMatch.walletID(forAppNamed: "Rabby Points", in: real) == nil)

// AMBIGUITY IS REFUSED. Two entries that would key alike take each other out rather than
// resolving to whichever was listed first.
let colliding = [(id: "one", name: "Foo"), (id: "two", name: "Foo Wallet")]
check("an ambiguous key resolves to nothing",
      WalletbeatMatch.walletID(forAppNamed: "Foo", in: colliding) == nil)
check("...and takes the other spelling with it",
      WalletbeatMatch.walletID(forAppNamed: "Foo Wallet", in: colliding) == nil)

print("")
print("What gets offered")

let t0 = Date(timeIntervalSince1970: 1_000_000)
let apps: [(name: String, seenAt: Date)] = [
    (name: "Rabby", seenAt: t0),
    (name: "MetaMask", seenAt: t0.addingTimeInterval(600)),
    (name: "Trust Wallet", seenAt: t0.addingTimeInterval(900)),
]
check("the most recent handshake leads",
      WalletbeatMatch.suggestions(apps: apps, watched: [], entries: real) == ["metamask", "rabby"])
check("a wallet Walletbeat does not rate is not offered",
      WalletbeatMatch.suggestions(apps: apps, watched: [], entries: real).contains("trust") == false)
check("a wallet already watched is not offered",
      WalletbeatMatch.suggestions(apps: apps, watched: ["metamask"], entries: real) == ["rabby"])
check("nothing to offer is an empty list, not a nil",
      WalletbeatMatch.suggestions(apps: apps, watched: ["metamask", "rabby"], entries: real).isEmpty)
// One wallet reached by two spellings is ONE offer.
check("two spellings of one wallet are offered once",
      WalletbeatMatch.suggestions(
        apps: [(name: "Safe", seenAt: t0), (name: "Safe{Wallet}", seenAt: t0.addingTimeInterval(60))],
        watched: [], entries: real) == ["safe"])
check("no handshake at all offers nothing",
      WalletbeatMatch.suggestions(apps: [], watched: [], entries: real).isEmpty)

print("")
print("The room's one button")

let noWatches = WalletbeatRoom(items: [], total: 0, snapshotDay: "2026-08-20",
                               news: WalletbeatRoom.News(total: 3, open: 0, recent: 1),
                               connectedName: "Rabby")
check("with nothing watched it names the wallet you connected with",
      WalletbeatRoom.browseLabel(noWatches).contains("Rabby"))
let noWatchesNoApp = WalletbeatRoom(items: [], total: 0, snapshotDay: "2026-08-20",
                                    news: WalletbeatRoom.News(total: 3, open: 0, recent: 1))
check("with no handshake it keeps §421's verb",
      WalletbeatRoom.browseLabel(noWatchesNoApp).contains("Rabby") == false
        && WalletbeatRoom.browseLabel(noWatchesNoApp).isEmpty == false)
// Once anything is watched the button's job is the rest of the registry again — a label
// that went on naming one wallet forever is a nag, not a shortcut.
let watching = WalletbeatRoom(
    items: [WalletbeatRoom.Item(id: "walletbeat:wallet:zerion", walletID: "zerion",
                                name: "Zerion", hardware: false,
                                counts: counts(pass: 20, fail: 4, unrated: 5),
                                lead: .noFailures(judged: 24, applicable: 29),
                                openIncidents: 0, recentIncidents: 0, read: true)],
    total: 1, snapshotDay: "2026-08-20", news: nil, connectedName: "Rabby")
check("a watched room stops naming a wallet on its button",
      WalletbeatRoom.browseLabel(watching).contains("Rabby") == false)

print("")
print("A revision remembers where it came from")

// The §430 field, and the migration that matters more than it: a ref landed before the
// field existed has FOUR components and must keep parsing as one.
let legacy = "walletbeat:rev:rabby:addressCorrelation:FAIL:2026-07-22"
let modern = legacy + ":PARTIAL"
check("a ref written before §430 still parses",
      WalletbeatSheet.revision(fromRef: legacy)?.after == .fail)
check("...and reports no before rather than guessing one",
      WalletbeatSheet.revision(fromRef: legacy)?.before == nil)
check("a ref written after §430 carries the verdict it moved from",
      WalletbeatSheet.revision(fromRef: modern)?.before == .partial)
check("the after is unmoved by the new field",
      WalletbeatSheet.revision(fromRef: modern)?.after == .fail)
check("the day is unmoved by the new field",
      WalletbeatSheet.revision(fromRef: modern)?.day == "2026-07-22")
// An entry Walletbeat has never dated writes an EMPTY day, so the before sits after an
// empty component — the one shape a naive index would read as the date.
check("an undated revision still yields its before",
      WalletbeatSheet.revision(fromRef: "walletbeat:rev:rabby:a:PASS::FAIL")?.before == .fail)
check("...and still reports no day",
      WalletbeatSheet.revision(fromRef: "walletbeat:rev:rabby:a:PASS::FAIL")?.day == nil)
// A before we cannot spell is ABSENT, never a refusal: the row's anatomy must not be lost
// over its least important field.
check("an unreadable before does not fail the whole ref",
      WalletbeatSheet.revision(fromRef: "walletbeat:rev:rabby:a:PASS:2026-01-01:WAT")?.after == .pass)
check("...and reads as absent",
      WalletbeatSheet.revision(fromRef: "walletbeat:rev:rabby:a:PASS:2026-01-01:WAT")?.before == nil)

print("")
if failures > 0 {
    print("walletbeat-selftest: ✗ \(failures) assertion(s) failed")
    exit(1)
}
print("walletbeat-selftest: OK — every assertion passed against the shipped source.")
SWIFT

build() { swiftc -O -o "$TMP/wb-selftest" "$1" "$2" "$3" "$4" "$SHEET" "$5" "$TMP/main.swift" 2>"$TMP/build.log"; }

echo "Assertions (shipped source, compiled whole)"
if ! build "$RATING" "$NEWS" "$ROOM" "$DIR" "$MATCH"; then
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

mutate() { # mutate <name> <rating|news|room|sheet|match> <from> <to>
  local name="$1" which="$2" from="$3" to="$4"
  local a="$TMP/m-rating.swift" b="$TMP/m-news.swift" c="$TMP/m-room.swift" d="$TMP/m-sheet.swift"
  local e="$TMP/m-match.swift"
  cp "$RATING" "$a"; cp "$NEWS" "$b"; cp "$ROOM" "$c"; cp "$SHEET" "$d"; cp "$MATCH" "$e"
  local target="$a"
  [[ "$which" == "news" ]] && target="$b"
  [[ "$which" == "room" ]] && target="$c"
  [[ "$which" == "sheet" ]] && target="$d"
  [[ "$which" == "match" ]] && target="$e"
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
  if ! swiftc -O -o "$TMP/mut" "$a" "$b" "$c" "$DIR" "$d" "$e" "$TMP/main.swift" 2>/dev/null; then
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

# The two tiers (prd §421). Each of these renders perfectly and says the wrong thing.
#
# The first is the sharpest: a followed seat whose first read has not landed yet would
# announce a clean ecosystem for all thirty-two wallets. The anchor carries its own
# comment line because "Reading Walletbeat…" is also `note`'s unread branch and
# `leadLine`'s, and the replacement takes the FIRST match.
mutate "nothing landed must not read as a quiet ecosystem" room \
  $'// what is known.\n\t\t\treturn String(localized: "Reading Walletbeat…")' \
  $'// what is known.\n\t\t\treturn String(localized: "No wallet security incidents in the last 30 days")'
mutate "open must outrank recent" room \
  'if news.open > 0 {' 'if news.open > 99 {'
mutate "the recent window must be reported" room \
  'if news.recent > 0 {' 'if news.recent > 99 {'
mutate "the followed note must carry the upgrade" room \
  "Watching yours adds where its keys are made, and who sees your addresses" \
  "Walletbeat publishes these on their own schedule"
mutate "a followed room must still attribute" room \
  "Walletbeat's reading, not ours · every wallet they cover" \
  "Read on this device"

# --------------------------------------------------------------------------------------
# The WalletConnect join and the revision's before (prd §430).
# --------------------------------------------------------------------------------------

# THE MEASURED TRANSFORM. Without it "Ledger" never matches "Ledger Wallet" and the offer
# simply never appears — for nearly every hardware wallet in the registry, silently.
mutate "Walletbeat's trailing 'Wallet' must be dropped" match \
  'if tokens.count > 1, tokens.last == "wallet" { tokens.removeLast() }' \
  'if tokens.count > 99, tokens.last == "wallet" { tokens.removeLast() }'

# ...and only a TRAILING one. Dropping the word anywhere folds "Wallet Guard" onto a
# stranger, which is the wrong-answer half of this asymmetry.
mutate "only a trailing 'wallet' may go" match \
  'if tokens.count > 1, tokens.last == "wallet" { tokens.removeLast() }' \
  'if tokens.count > 1 { tokens.removeAll { $0 == "wallet" } }'

# AMBIGUITY IS REFUSED. Resolving to whichever entry came first is how somebody is offered
# a security review of software they do not run.
mutate "an ambiguous key must resolve to nothing" match \
  'return claims.compactMapValues { $0.count == 1 ? $0.first : nil }' \
  'return claims.compactMapValues { $0.first }'

# The three rules the offer list keeps.
mutate "a wallet already watched must not be offered" match \
  'guard !already.contains(id), seen.insert(id).inserted else { continue }' \
  'guard seen.insert(id).inserted else { continue }'
mutate "one wallet reached twice is one offer" match \
  'guard !already.contains(id), seen.insert(id).inserted else { continue }' \
  'guard !already.contains(id) else { continue }'
mutate "the most recent handshake must lead" match \
  'for app in apps.sorted(by: { $0.seenAt > $1.seenAt }) {' \
  'for app in apps {'

# The button names a wallet only while nothing is watched — otherwise it is a nag.
mutate "a watched room must stop naming a wallet" room \
  '		guard room.items.isEmpty else {' \
  '		guard true else {'

# THE MIGRATION. A ref landed before §430 has four components and must keep its anatomy.
mutate "a ref written before the before existed must still parse" sheet \
  'guard parts.count >= 3 else { return nil }' \
  'guard parts.count >= 5 else { return nil }'
# The empty-day shape is the one a naive index reads as the date.
mutate "the before is read from its own component" sheet \
  'let before = parts.count > 4 ? WalletbeatVerdict(rawValue: parts[4]) : nil' \
  'let before = parts.count > 3 ? WalletbeatVerdict(rawValue: parts[3]) : nil'

echo ""
echo "walletbeat-selftest: OK — assertions pass and every mutation is caught."
