#!/bin/zsh
# L2BEAT's pure logic, compiled AS SHIPPED (prd §428).
#
# WHY THIS IS THE ONLY PROOF THESE NUMBERS ARE RIGHT: nothing on this host can make L2BEAT
# re-rate a chain or record an incident, and their registry is a third party's live
# document served from an UNDOCUMENTED site endpoint (their documented API answers 401
# without a key). The build cannot see any of it — a sentiment that silently defaults to
# good, a stage that sorts "not applicable" as a zero, a nested second reading dropped or
# merged into the first all render perfectly.
#
# The sharpest thing it guards is the SECOND READING. Measured 2026-08-21, thirteen risks
# carry a `regular` block and four a `warning` one, and Arbitrum is among them: its Exit
# Window is `None`/bad at the top with `10d`/warning underneath. Dropping the nested block
# throws away the number an Arbitrum user wants; merging it into the top-level sentiment
# states a reassurance L2BEAT did not make. Both failures look identical from outside.

set -euo pipefail
cd "$(dirname "$0")/.."

RATING="Casberi/Casberi/Model/L2beatRating.swift"
NEWS="Casberi/Casberi/Model/L2beatNews.swift"
ROOM="Casberi/Casberi/Model/L2beatRoom.swift"
SHEET="Casberi/Casberi/Model/L2beatSheet.swift"
DIR="Casberi/Casberi/Model/L2beatDirectory.swift"
BRIDGE="Casberi/Casberi/Model/L2beatBridge.swift"
SRC="Casberi/Casberi/Model/L2beatRoomSource.swift"
SHEETSRC="Casberi/Casberi/Model/L2beatSheetSource.swift"
VIEWS="Casberi/Casberi/Screens/L2beatViews.swift"
ROWS="Casberi/Casberi/Screens/L2beatRow.swift"
CARD="Casberi/Casberi/Screens/L2beatRoomCard.swift"
DIRSCREEN="Casberi/Casberi/Screens/L2beatDirectoryScreen.swift"
CARDSCREEN="Casberi/Casberi/Screens/L2beatCardScreen.swift"
SHEETVIEWS="Casberi/Casberi/Screens/L2beatSheetViews.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
ROUTE="Casberi/Casberi/Shell/HomeRoute.swift"
SURFACE="Casberi/Casberi/Shell/MainSurface.swift"
DEMO="Casberi/Casberi/Model/DemoSeedAll.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
FIGURE="Casberi/Casberi/Model/RoomFigure.swift"
SHEETVIEW="Casberi/Casberi/Screens/ThingSheetView.swift"
NOTIFY="Casberi/Casberi/Model/NotifySweep.swift"
SNAP="scripts/l2beat-snapshot.py"

for f in "$RATING" "$NEWS" "$ROOM" "$SHEET" "$DIR" "$BRIDGE" "$SRC" "$SHEETSRC" "$VIEWS" \
         "$ROWS" "$CARD" "$DIRSCREEN" "$CARDSCREEN" "$SHEETVIEWS" "$SNAP"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --------------------------------------------------------------------------------------
# 1 · Drift guards — the wiring the compiled functions cannot prove about themselves.
#
# Several read a COMMENT-STRIPPED copy: these files DOCUMENT their rules by naming what
# they must never do ("nothing here ranks chains or folds five risks into a verdict"), so a
# guard over raw source fires on the prose explaining the rule and reports a correct file
# as broken. The Obsidian/Cursor lesson, earned again on §419's own generator.
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

strip_comments "$RATING" > "$TMP/rating.nc"
strip_comments "$ROOM"   > "$TMP/room.nc"
strip_comments "$SRC"    > "$TMP/src.nc"
strip_comments "$VIEWS"  > "$TMP/views.nc"
strip_comments "$BRIDGE" > "$TMP/bridge.nc"
strip_comments "$DEMO"   > "$TMP/demo.nc"
strip_comments "$ROWS"   > "$TMP/rows.nc"
strip_comments "$DIRSCREEN" > "$TMP/dirscreen.nc"
strip_comments "$CARDSCREEN" > "$TMP/cardscreen.nc"
strip_comments "$FIGURE" > "$TMP/figure.nc"

echo "Drift guards"

# ---- The room and its wiring ----------------------------------------------------------
guard 'things.live' "$SRC" \
  "L2beatRoomSource no longer filters live at the boundary (corollary 4)"
guard 'L2beatRoom.ranked(items)' "$SRC" \
  "the room's chains are no longer ranked — a recent incident would sort arbitrarily"
guard 'ranked.prefix(rowCap)' "$SRC" \
  "the room head no longer honours its row cap"
guard 'case .l2beat(let room)' "$FEED" \
  "the L2BEAT head is no longer rendered from the sourceHead chain"
guard 'case L2beatRoomSource.source:' "$FEED" \
  "FeedScreen no longer composes the L2BEAT head"
guard 'case "L2BEAT":              self = .l2beat' "$FEED" \
  "the L2BEAT source no longer maps to its own room shape — it would fall back to plain bands"
guard 'L2beatChainRow(thing: thing)' "$FEED" \
  "a watched chain no longer draws its assessment row"
guard 'L2beatNewsRow(thing: thing, watchedChains: l2beatWatchedIDs)' "$FEED" \
  "the milestone rows no longer get the watch list — no row could say 'you watch this'"
guard 'L2beatWatch.chainID(from: $0)' "$FEED" \
  "the feed's watch list is no longer derived from the room's own rows"

# ---- The peek figure -------------------------------------------------------------------
guard 'source == L2beatRoomSource.source' "$FIGURE" \
  "the chip peek lost its L2BEAT figure — long-pressing the chip draws a blank"
# The peek must never draw a league table of chains. A bar of STAGE RUNGS at tile scale,
# with no legend, reads as taller-is-better — which is the one reading this refuses.
#
# On a COMMENT-STRIPPED copy: `RoomFigure` documents this very rule by naming what it must
# not chart ("a bar chart of rungs is a league table"), so a guard over raw source fires on
# the prose explaining it. Caught on this guard's own first run — the fifth time this
# codebase has paid for it, and the first time in a guard written the same afternoon as the
# comment it tripped over.
if grep -qE 'value: \$0\.stage|rung' "$TMP/figure.nc"; then
  echo "✗ the chip peek charts the STAGE — that is a league table of chains, not a tally"
  exit 1
fi

# ---- Never a composite ------------------------------------------------------------------
# The rule §419 had to enforce by refusal and this one satisfies by citation: L2BEAT
# publishes a stage, so we show theirs. Nothing may compute one.
if grep -qiE 'func +score|var +score|riskScore|overallScore|safetyScore' "$TMP/rating.nc" "$TMP/room.nc"; then
  echo "✗ something computes a score — L2BEAT publishes a stage and this app publishes nothing"
  exit 1
fi
# The directory must never offer a "safest" sort.
if grep -qiE 'case safest|\.safest\b|case best\b' "$DIRSCREEN"; then
  echo "✗ the directory grew a 'safest' order — that needs a composite nobody published"
  exit 1
fi
# The RISK CARD must draw L2BEAT's own axis order, never a flagged-first re-sort: the strip
# beside every row paints these five in this order, and re-sorting the card breaks the one
# correspondence that lets somebody read a strip without reading a word.
guard 'ForEach(project.orderedRisks)' "$TMP/cardscreen.nc" \
  "the risk card re-sorts the five axes — the strip and the card would no longer agree"
if grep -qE 'sorted.*sentiment|\.sorted \{.*flagged' "$TMP/cardscreen.nc"; then
  echo "✗ the risk card sorts by sentiment — see the axis-order ruling in its own header"
  exit 1
fi

# ---- Read-only ---------------------------------------------------------------------------
# There is no endpoint to write to, and that is the promise the connect screen makes.
if grep -qE 'httpMethod|postJSON|deleteJSON|"POST"|"PUT"|"DELETE"' "$TMP/bridge.nc"; then
  echo "✗ L2beatBridge gained a write verb — the seat promises read-only"
  exit 1
fi

# ---- The two identifiers -----------------------------------------------------------------
# MEASURED 2026-08-21: `id` and `slug` differ for ten of the 105, including OP Mainnet,
# ZKsync Era, World Chain and Ronin. The milestone read joins on `id` and the page URL is
# built from `slug`; getting either backwards loses four of the biggest chains SILENTLY —
# a chain with no config file reads exactly like a chain with no milestones.
guard 'projects/\(projectID)/\(projectID).ts' "$TMP/rating.nc" \
  "the milestone URL no longer uses the project id — ten chains would 404, silently"
guard 'scaling/projects/\(slug)' "$TMP/rating.nc" \
  "the page URL no longer uses the slug — ten chains would link to a 404"
guard 'L2beatFetch.milestones(projectID: $0)' "$TMP/bridge.nc" \
  "the milestone walk no longer passes a project id"

# ---- The two tiers ------------------------------------------------------------------------
# Every one of these guards a failure that is SILENT: the seat simply goes quiet, which
# from outside is indistinguishable from L2BEAT having recorded nothing (§311).
guard 'guard L2beatWatch.following || !watched.isEmpty' "$TMP/bridge.nc" \
  "the sync is gated on the watch list — following alone would read nothing, silently"
guard 'guard following || count > 0' "$TMP/bridge.nc" \
  "the seat no longer registers for a follower — no seat means BridgeRefresh never sweeps it"
guard 'following = true' "$TMP/bridge.nc" \
  "watching no longer implies following — the incidents would stop arriving for a watcher"
guard 'following = false' "$TMP/bridge.nc" \
  "disconnect no longer clears the follow flag — the seat would re-register itself"
guard '!watches.isEmpty || !milestones.isEmpty' "$TMP/src.nc" \
  "the room head demands a watched chain again — a follower's incidents would head nothing"
guard 'isWatched || milestone.kind.isIncident' "$TMP/bridge.nc" \
  "every milestone lands for every chain — a follower's feed becomes 274 launches and upgrades"
guard 'case .stage: return true' "$TMP/bridge.nc" \
  "a stage move no longer lands for an unwatched chain — the one piece of ecosystem news this data produces"
guard 'case .risk: return watched' "$TMP/bridge.nc" \
  "risk revisions land for every chain — 105 chains of them in the feed of somebody who watches none"
guard 'l2beatFollow' "$PROBES" \
  "-l2beatFollow is gone; following with nothing watched has no headless door"

# ---- The bundled baseline -------------------------------------------------------------------
guard 'L2beatDirectory.seededIncidents' "$TMP/bridge.nc" \
  "the bundled incident history is never landed — a follower with no network sees an empty room"
guard 'L2beatState.hasSeededIncidents' "$TMP/bridge.nc" \
  "the seed is no longer guarded by its own flag — it would re-run every sweep"
guard 'rotationSlice' "$TMP/bridge.nc" \
  "the rotating milestone walk is gone — the incident feed would only ever refresh on an app update"

# ---- §234: a browse is mounted by the ROOM ------------------------------------------------
guard 'route.path.append(.l2beatDirectory)' "$FEED" \
  "the room's browse no longer opens the directory directly"
guard 'case l2beatDirectory' "$ROUTE" \
  "the directory lost its own route node — the room can only reach it via the catalog"
guard 'case .l2beatDirectory:' "$SURFACE" \
  "the directory route node is declared but never resolved to a screen"
if grep -qF 'route.path.append(.bridge(.l2beat))' "$FEED"; then
  echo "✗ the room's browse pushes the CONNECT screen (§234 — connecting is not browsing)"
  exit 1
fi

# ---- A row must not fetch --------------------------------------------------------------------
if grep -qE 'FetchDescriptor|modelContext' "$ROWS"; then
  echo "✗ an L2BEAT row fetches — the watch list is handed in precisely so it cannot"
  exit 1
fi

# ---- The sheet's three anatomies ---------------------------------------------------------------
guard 'l2beatHead(l2beatShape)' "$SHEETVIEW" \
  "the thing sheet no longer draws the L2BEAT anatomies — all three fall back to a link"
guard '&& walletbeatShape == nil && l2beatShape == nil' "$SHEETVIEW" \
  "the generic content block draws UNDER an L2BEAT head — the row's URL printed twice"
guard 'L2beatMilestoneHead(thing: thing)' "$SHEETVIEW" \
  "a milestone's sheet lost its own head"

# ---- Reach --------------------------------------------------------------------------------------
guard 'Endpoint(service: "L2BEAT"' "$REACH" \
  "L2BEAT's hosts are undeclared — the privacy screen would be quietly wrong (§205)"
guard '"l2beat.com", "raw.githubusercontent.com"' "$REACH" \
  "L2BEAT's declared hosts no longer match what the bridge reads"

# ---- No notification, and that is a DECISION ------------------------------------------------------
# §428: L2BEAT's milestone schema carries NO severity and NO status, so the recorded
# incidents run from "patched, no funds at risk" to a major exploit with nothing in the data
# separating them. Alarming on the class as a whole would spend a lock-screen slot on a
# patch note; grading them ourselves would be the §83 fake status. The row still arrives and
# the room head still ranks it first. Revisit the day L2BEAT publishes a severity.
if grep -qiE 'l2beat' "$NOTIFY"; then
  echo "✗ L2BEAT reached NotifySweep — see the no-severity ruling in prd §428 before adding one"
  exit 1
fi

# ---- The demo -------------------------------------------------------------------------------------
guard 'L2beatMilestoneBook.forgetDemo(demoL2beatKeys)' "$TMP/demo.nc" \
  "the demo no longer forgets its seeded milestones by key (§401 — a dev install holds real ones)"
guard 'demoL2beatIDs: [String] { L2beatDirectory.demoChains }' "$TMP/demo.nc" \
  "the demo's chains are hand-spelled again — they must come from the snapshot's own list"
# THE CALL, not the declaration, and on a STRIPPED copy — §422's lesson, which cost that
# feature a guard that passed against a commented-out call and then against the function's
# own `private static func` line.
if grep -qE '^[[:space:]]+seedL2beatMilestones\(\)$' "$TMP/demo.nc"; then
  echo "  ✓ the demo seeds the milestone book"
else
  echo "✗ the demo no longer seeds the milestone book — the sheet's fact card reads empty"
  exit 1
fi
# The demo's findings must be DERIVED, never written: a fabricated risk finding attributed
# to a real chain is the §83 failure inside the one feature built to stop it.
guard 'if case .finding(let risk) = project.lead' "$TMP/demo.nc" \
  "the demo hand-writes a chain's finding instead of deriving it from L2BEAT's own reading"

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

func risk(_ axis: L2beatRiskAxis, _ value: String, _ sentiment: L2beatSentiment,
          _ explanation: String = "because", second: L2beatRiskNote? = nil) -> L2beatRisk {
    L2beatRisk(axis: axis, value: value, sentiment: sentiment,
               explanation: explanation, second: second)
}

func project(id: String = "demo", slug: String? = nil, name: String = "Demo",
             layer: L2beatLayer = .layer2, stage: L2beatStage? = .stage0,
             underReview: Bool = false, risks: [L2beatRisk] = []) -> L2beatProject {
    L2beatProject(id: id, slug: slug ?? id, name: name, layer: layer,
                  hostChain: "Ethereum", category: "Optimistic Rollup", stage: stage,
                  underReview: underReview, archived: false, risks: risks)
}

// The five, all fine — the shape only four of 105 projects actually have.
let clean: [L2beatRisk] = L2beatRiskAxis.allCases.map { risk($0, "Fine", .good) }

print("Sentiment")

// THE default that must never happen. A sentiment we do not recognise reading as `good`
// is a clean bill of health this app invented.
check("an unknown sentiment word is .unknown", L2beatSentiment.read("spicy") == .unknown)
check("a missing sentiment is .unknown", L2beatSentiment.read(nil) == .unknown)
check("an unknown sentiment is NOT good", L2beatSentiment.read("spicy") != .good)
check("a capitalised sentiment still reads", L2beatSentiment.read("Bad") == .bad)
check("neutral is a real case, measured once in 525", L2beatSentiment.read("neutral") == .neutral)
check("only `bad` is concerning", L2beatSentiment.bad.isConcerning
      && !L2beatSentiment.warning.isConcerning && !L2beatSentiment.unknown.isConcerning)
check("concern orders bad over warning over neutral over good",
      L2beatSentiment.bad.concern > L2beatSentiment.warning.concern
      && L2beatSentiment.warning.concern > L2beatSentiment.neutral.concern
      && L2beatSentiment.neutral.concern > L2beatSentiment.good.concern)

print("")
print("The second reading (the Arbitrum case)")

// Arbitrum, measured: Exit Window `None`/bad at the top, `10d`/warning underneath.
let arbitrumExit = risk(.exitWindow, "None", .bad, "There is no window.",
                        second: L2beatRiskNote(value: "10d", sentiment: .warning,
                                               explanation: "Ten days for a normal upgrade."))
check("the headline sentiment is untouched by the nested one", arbitrumExit.sentiment == .bad)
check("the nested reading keeps its own value", arbitrumExit.second?.value == "10d")
check("a MILDER nested reading never softens the worst", arbitrumExit.worstSentiment == .bad)
check("the worst explanation is the headline's when the headline is worse",
      arbitrumExit.worstExplanation == "There is no window.")

// The honeypot, measured: neutral at the top, `bad` underneath — "the single hardcoded
// address can withdraw all funds". The one case where the nested block must win.
let honeypot = risk(.exitWindow, "Not applicable", .neutral, "Deposits are donations.",
                    second: L2beatRiskNote(value: "One address can withdraw all funds.",
                                           sentiment: .bad, explanation: nil))
check("a WORSE nested reading is what the lead sees", honeypot.worstSentiment == .bad)
check("the strip still shows L2BEAT's headline call", honeypot.sentiment == .neutral)
check("a nested block with no sentence falls back to its value",
      honeypot.worstExplanation == "One address can withdraw all funds.")

// A THIRD fixture, and the reason it exists is a mutation that survived without it: the
// two above cannot tell the nested SENTENCE apart from the nested VALUE, because the
// honeypot's nested block carries no sentence and Arbitrum's nested block never wins. So
// disabling the sentence branch left both green while `worstExplanation` silently handed
// back a value where a sentence was published.
//
// The standing rule, third instance in this codebase: a fixture only tests the rule it
// names if it FAILS that rule and passes every other one.
let nestedWorse = risk(.exitWindow, "7d", .warning, "A week to leave.",
                       second: L2beatRiskNote(value: "None", sentiment: .bad,
                                              explanation: "An emergency upgrade is instant."))
check("a worse nested reading brings its OWN sentence, not its value",
      nestedWorse.worstExplanation == "An emergency upgrade is instant.")
check("and its own severity", nestedWorse.worstSentiment == .bad)

print("")
print("Their stage")

check("Stage 0 is rung 0", L2beatStage.stage0.rung == 0)
check("Stage 2 is rung 2", L2beatStage.stage2.rung == 2)
// The reason this is an enum: a chain L2BEAT excludes from the ladder is NOT a worse
// Stage 0, and any code sorting on a raw string would place it as one.
check("not-applicable has NO rung, never zero", L2beatStage.notApplicable.rung == nil)
check("a stage word reads", L2beatStage.read("Stage 1") == .stage1)
check("an unrecognised stage is nil, never Stage 0", L2beatStage.read("Stage 9") == nil)
check("an empty stage is nil", L2beatStage.read("") == nil)
check("every stage says what the rung means", L2beatStage.allCases.allSatisfy { !$0.meaning.isEmpty })

print("")
print("Which finding leads")

// Under review outranks everything: L2BEAT saying "we are re-examining this" outranks any
// reading of theirs that may be about to change.
let reviewing = project(underReview: true, risks: [risk(.exitWindow, "None", .bad)])
if case .underReview = reviewing.lead {
    check("under review outranks a finding", true)
} else {
    check("under review outranks a finding", false)
}

// The first BAD in L2BEAT's own axis order, not the first in the array.
let outOfOrder = project(risks: [
    risk(.proposerFailure, "Cannot withdraw", .bad),
    risk(.sequencerFailure, "No mechanism", .bad),
])
if case .finding(let hit) = outOfOrder.lead {
    check("the lead is the first BAD in L2BEAT's axis order", hit.axis == .sequencerFailure)
} else {
    check("the lead is the first BAD in L2BEAT's axis order", false)
}

// A warning leads only when nothing is flagged.
let warned = project(risks: [
    risk(.sequencerFailure, "Enqueue via L1", .warning),
    risk(.stateValidation, "Validity proofs", .good),
])
if case .finding(let hit) = warned.lead {
    check("a warning leads when nothing is flagged", hit.sentiment == .warning)
} else {
    check("a warning leads when nothing is flagged", false)
}
// And a flagged risk beats a warning that comes FIRST in the axis order.
let bothKinds = project(risks: [
    risk(.sequencerFailure, "Enqueue via L1", .warning),
    risk(.stateValidation, "None", .bad),
])
if case .finding(let hit) = bothKinds.lead {
    check("a flagged risk outranks an earlier warning", hit.axis == .stateValidation)
} else {
    check("a flagged risk outranks an earlier warning", false)
}

// The rare clean case — measured, only 4 of 105 — and it is worded as "nothing flagged",
// never as safe.
if case .nothingFlagged(let count) = project(risks: clean).lead {
    check("nothing flagged says how many were checked", count == 5)
} else {
    check("nothing flagged says how many were checked", false)
}
check("a chain with no readings is unread, not clean", project(risks: []).lead == .unread)
check("only a flagged lead is concerning",
      project(risks: [risk(.exitWindow, "None", .bad)]).lead.isConcerning
      && !project(risks: clean).lead.isConcerning
      && !project(risks: []).lead.isConcerning)
// The honeypot again, end to end: the lead must SEE the nested bad reading.
check("the lead promotes a nested flagged reading",
      project(risks: [risk(.sequencerFailure, "Self sequence", .good), honeypot]).lead.isConcerning)

print("")
print("Order and counting")

let shuffled = project(risks: [
    risk(.proposerFailure, "Self propose", .good),
    risk(.exitWindow, "None", .bad),
    risk(.sequencerFailure, "Self sequence", .good),
])
check("orderedRisks uses OUR axis order, not the payload's",
      shuffled.orderedRisks.map(\.axis) == [.sequencerFailure, .exitWindow, .proposerFailure])
check("a missing axis is skipped, never invented", shuffled.orderedRisks.count == 3)
check("flagged counts only what L2BEAT flags", shuffled.flagged == 1)
check("risk(_:) finds by axis", shuffled.risk(.exitWindow)?.value == "None")
check("the page URL is built from the SLUG",
      project(id: "optimism", slug: "op-mainnet").pageURL?.absoluteString
        == "https://l2beat.com/scaling/projects/op-mainnet")

print("")
print("Parsing the summary")

let payload = """
{"projects": {
  "optimism": {"id":"optimism","slug":"op-mainnet","name":"OP Mainnet","type":"layer2",
    "hostChain":"Ethereum","category":"Optimistic Rollup","stage":"Stage 1",
    "isUnderReview":false,"isArchived":false,
    "risks":[
      {"name":"Proposer Failure","value":"Self propose","sentiment":"good","description":"p"},
      {"name":"Exit Window","value":"None","sentiment":"bad","description":"e",
       "regular":{"value":"10d","sentiment":"warning","description":"r"}},
      {"name":"Teleportation","value":"Bad","sentiment":"bad","description":"t"},
      {"name":"Sequencer Failure","value":"","sentiment":"good","description":"s"}
    ]},
  "tiny": {"type":"layer3","isUnderReview":true,"stage":"Not applicable"}
}}
"""
let parsed = L2beatSummaryParse.projects(from: Data(payload.utf8))
check("both projects parse", parsed.count == 2)
let op = parsed.first { $0.id == "optimism" }
check("the repo id and the public slug are kept apart",
      op?.id == "optimism" && op?.slug == "op-mainnet")
check("their stage is read verbatim", op?.stage == .stage1)
check("an unknown axis is dropped, never guessed into a slot",
      op?.risks.count == 2)
check("an empty value is dropped", op?.risk(.sequencerFailure) == nil)
check("the nested regular block survives the parse",
      op?.risk(.exitWindow)?.second?.value == "10d")
check("parsed risks come back in OUR axis order",
      op?.risks.map(\.axis) == [.exitWindow, .proposerFailure])
let tiny = parsed.first { $0.id == "tiny" }
check("a project with no name falls back to its id", tiny?.name == "tiny")
check("a project with no slug falls back to its id", tiny?.slug == "tiny")
check("an L3 keeps its layer", tiny?.layer == .layer3)
check("under review survives", tiny?.underReview == true)
check("not-applicable parses to its own case", tiny?.stage == .notApplicable)
check("a project with no readable risks still lands", tiny?.risks.isEmpty == true)
check("the parse sorts by name so two reads agree",
      parsed.map(\.name) == ["OP Mainnet", "tiny"])
check("a payload with no projects key yields nothing",
      L2beatSummaryParse.projects(from: Data("{}".utf8)).isEmpty)
check("junk yields nothing rather than crashing",
      L2beatSummaryParse.projects(from: Data("not json".utf8)).isEmpty)

print("")
print("Revisions")

let before = project(stage: .stage0, risks: [
    risk(.sequencerFailure, "No mechanism", .bad),
    risk(.exitWindow, "None", .bad),
])
let after = project(stage: .stage1, risks: [
    risk(.sequencerFailure, "Self sequence", .good),
    risk(.exitWindow, "None", .bad),
])
let changes = L2beatRevisions.between(before, after)
check("a stage move and a risk change are two changes", changes.count == 2)
if case .stage(let was, let now) = changes.first {
    check("the stage move leads", was == .stage0 && now == .stage1)
} else {
    check("the stage move leads", false)
}
check("a stage move upward is an improvement", changes.first?.isImprovement == true)
check("an unchanged risk is not a change",
      L2beatRevisions.between(after, after).isEmpty)
check("two different projects never compare",
      L2beatRevisions.between(project(id: "a"), project(id: "b")).isEmpty)

// Our information degrading is not the chain's safety changing.
let wentUnknown = project(risks: [risk(.sequencerFailure, "?", .unknown)])
check("a risk going unknown is never reported",
      L2beatRevisions.between(before, wentUnknown).allSatisfy {
          if case .risk = $0 { return false } else { return true } })
// But L2BEAT taking a chain OFF the ladder is a real change and is reported.
let unstaged = project(stage: .notApplicable, risks: before.risks)
check("a stage move to not-applicable IS reported",
      L2beatRevisions.between(before, unstaged).contains {
          if case .stage(_, let now) = $0 { return now == .notApplicable } else { return false } })
check("losing the ladder is not an improvement",
      L2beatRevisions.between(before, unstaged).allSatisfy { !$0.isImprovement })
// A first reading has nothing to compare against, so nothing is a change.
check("a project that gained its first risks reports no risk change",
      L2beatRevisions.between(project(risks: []), after).allSatisfy {
          if case .risk = $0 { return false } else { return true } })

print("")
print("Milestones")

let config = """
export const arbitrum: ScalingProject = {
  id: ProjectId('arbitrum'),
  milestones: [
    {
      subtitle: 'WRONG — this must never be read as the title',
      title: 'Bridge emergency upgrade',
      url: 'https://forum.example/t/action{2}/30910',
      date: '2026-05-24T00:00:00Z',
      description:
        'Security Council patches a
         governance DoS. No funds at risk.',
      type: 'incident',
    },
    { title: 'Nitro upgrade', date: '2022-08-31T00:00:00Z', type: 'general' },
    { title: 'No date here', type: 'incident' },
  ],
  display: { name: 'Arbitrum One' },
}
"""
let stones = L2beatNewsParse.milestones(from: config, projectID: "arbitrum")
check("both dated milestones parse", stones.count == 2)
check("the incident type is read", stones.first?.kind == .incident)
check("only the day survives an ISO stamp", stones.first?.day == "2026-05-24")
// `title:` must not be found inside `subtitle:`. §419 learned this the other way round —
// its unanchored search found a nested `label:` and reported one object's value as
// another's.
//
// AND THE FIXTURE HAD TO BE CORRECTED: the first cut used `sourceUrl:` before `url:`,
// which cannot collide at all — `range(of:)` is case-sensitive and `sourceUrl` carries a
// capital U — so deleting the anchor check left the suite green. `subtitle:` really does
// contain `title:`, lowercase and adjacent. Second instance of this in one run.
check("a field name is anchored, so subtitle is not title",
      stones.first?.title == "Bridge emergency upgrade")
check("the citation still reads", stones.first?.url == "https://forum.example/t/action{2}/30910")
// A brace inside a URL must not end the object.
check("a brace inside a value does not split the object",
      stones.count == 2 && stones[1].title == "Nitro upgrade")
check("hard-wrapped prose collapses to spaces",
      stones.first?.summary == "Security Council patches a governance DoS. No funds at risk.")
check("a milestone with no date is dropped", !stones.contains { $0.title == "No date here" })
check("a milestone with no description survives", stones[1].summary == nil)
check("an untyped milestone is general, never dropped",
      L2beatNewsParse.milestones(from: "milestones: [{title: 'x', date: '2024-01-02'}]",
                                 projectID: "p").first?.kind == .general)
check("an unknown type is kept as general",
      L2beatNewsParse.milestones(from: "milestones: [{title: 'x', date: '2024-01-02', type: 'gossip'}]",
                                 projectID: "p").first?.kind == .general)
check("a file with no milestones yields none",
      L2beatNewsParse.milestones(from: "export const x = {}", projectID: "p").isEmpty)
check("only incidents are the follow tier's half",
      L2beatMilestoneKind.incident.isIncident && !L2beatMilestoneKind.general.isIncident)

// NOON, not midnight. L2BEAT's own stamps ARE midnight UTC, so a midnight parse files a
// milestone under the previous day for every reader west of Greenwich.
let noon = L2beatNewsParse.date(fromISO: "2026-05-24")!
var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
check("a milestone lands at UTC noon", utc.component(.hour, from: noon) == 12)
check("an implausible year is refused", L2beatNewsParse.date(fromISO: "1899-01-01") == nil)
check("a malformed day is refused", L2beatNewsParse.date(fromISO: "2026-13-40") == nil)
check("the day is cut from an ISO stamp",
      L2beatNewsParse.dayString("2026-05-24T00:00:00Z") == "2026-05-24")

// The ref carries the project AND the day, so one chain's repeated annual event does not
// dedupe against its own history.
let stone = stones[0]
check("the ref names the project and the day",
      stone.ref == "l2beat:news:arbitrum:2026-05-24:bridge-emergency-upgrade")
check("a slug is capped at eight words",
      L2beatNewsParse.slug((0..<20).map(String.init).joined(separator: " "))
        .split(separator: "-").count == 8)

print("")
print("The sheet's ref grammar")

check("a chain ref is the chain anatomy",
      L2beatSheet.shape(.init(source: "L2BEAT", sourceRef: "l2beat:chain:base")) == .chain)
check("a news ref is the milestone anatomy",
      L2beatSheet.shape(.init(source: "L2BEAT", sourceRef: "l2beat:news:base:2025-01-01:x")) == .milestone)
check("a rev ref is the revision anatomy",
      L2beatSheet.shape(.init(source: "L2BEAT", sourceRef: "l2beat:rev:base:exitWindow:bad:2026-01-01")) == .revision)
check("another source draws nothing here",
      L2beatSheet.shape(.init(source: "Walletbeat", sourceRef: "l2beat:chain:base")) == nil)
check("an import receipt keeps the plain sheet",
      L2beatSheet.shape(.init(source: "L2BEAT", sourceRef: "l2beat:chain:base",
                              isImportReceipt: true)) == nil)
check("an unknown namespace draws nothing",
      L2beatSheet.shape(.init(source: "L2BEAT", sourceRef: "l2beat:other:x")) == nil)

let riskRev = L2beatSheet.revision(fromRef: "l2beat:rev:zksync2:exitWindow:bad:2026-08-21")
check("a risk revision reads its project", riskRev?.projectID == "zksync2")
check("a risk revision reads its axis", riskRev?.axis == .exitWindow)
check("a risk revision reads where it landed", riskRev?.afterSentiment == .bad)
check("a risk revision is not a stage move", riskRev?.isStageMove == false)
let stageRev = L2beatSheet.revision(fromRef: "l2beat:rev:base:stage:stage1:2026-08-19")
check("a stage move reads its rung", stageRev?.afterStage == .stage1)
check("a stage move knows it is one", stageRev?.isStageMove == true)
check("a stage token round-trips",
      L2beatSheet.stage(fromToken: L2beatSheet.token(for: .stage2)) == .stage2)
check("an unstaged token round-trips",
      L2beatSheet.stage(fromToken: L2beatSheet.token(for: .notApplicable)) == .notApplicable)
check("a token with no meaning is refused", L2beatSheet.stage(fromToken: "stage7") == nil)
check("an unparseable revision ref is nil",
      L2beatSheet.revision(fromRef: "l2beat:rev:onlyone") == nil)
check("a revision ref with an unknown axis is nil",
      L2beatSheet.revision(fromRef: "l2beat:rev:base:teleport:bad:2026-01-01") == nil)

print("")
print("The room head")

func item(_ name: String, stage: L2beatStage? = .stage0, review: Bool = false,
          risks: [L2beatRisk] = [], recent: Int = 0, read: Bool = true) -> L2beatRoom.Item {
    L2beatRoom.Item(id: "l2beat:chain:\(name)", chainID: name, name: name, layer: .layer2,
                    stage: stage, underReview: review, risks: risks,
                    lead: project(stage: stage, underReview: review, risks: risks).lead,
                    recentIncidents: recent, totalIncidents: recent, read: read)
}

let ranked = L2beatRoom.ranked([
    item("Quiet", risks: clean),
    item("Flagged", risks: [risk(.exitWindow, "None", .bad)]),
    item("Incident", risks: clean, recent: 1),
    item("Reviewing", review: true, risks: clean),
])
check("a recent incident ranks first", ranked.first?.name == "Incident")
check("under review ranks above a finding", ranked[1].name == "Reviewing")
check("a finding ranks above a quiet chain", ranked[2].name == "Flagged")

// TOTAL: a head that reshuffles between opens over unchanged data reads as broken.
let tied = L2beatRoom.ranked([item("Zulu", risks: clean), item("Alpha", risks: clean)])
check("ties fall through to the name", tied.map(\.name) == ["Alpha", "Zulu"])
check("ranking is stable over a reversed input",
      L2beatRoom.ranked(tied.reversed()).map(\.name) == tied.map(\.name))

// THE STAGE IS NEVER A SORT KEY. Sorting on the rung turns a displayed composite into an
// implied league table — the one reading this feature refuses.
let byStage = L2beatRoom.ranked([
    item("Bravo", stage: .stage0, risks: clean),
    item("Alpha", stage: .stage2, risks: clean),
])
check("the stage does not reorder the head", byStage.map(\.name) == ["Alpha", "Bravo"])

func room(_ items: [L2beatRoom.Item], news: L2beatRoom.News? = nil) -> L2beatRoom {
    L2beatRoom(items: items, total: items.count, snapshotDay: "2026-08-21", news: news)
}

let flagged = room([item("Base", risks: [risk(.exitWindow, "None", .bad)])])
check("the headline names the top chain and its axis",
      L2beatRoom.headline(flagged).contains("Base")
      && L2beatRoom.headline(flagged).lowercased().contains("exit window"))
check("the headline attributes the finding to L2BEAT",
      L2beatRoom.headline(flagged).contains("L2BEAT"))
let withIncident = room([item("Base", risks: clean, recent: 1)])
check("a recent incident is the headline", L2beatRoom.headline(withIncident).contains("incident"))
let reviewed = room([item("Base", review: true, risks: clean)])
check("under review is said in the headline",
      L2beatRoom.headline(reviewed).contains("re-examining"))
let quiet = room([item("Base", risks: clean)])
check("a clean chain is 'flags nothing', never 'safe'",
      L2beatRoom.headline(quiet).contains("flags nothing")
      && !L2beatRoom.headline(quiet).lowercased().contains("safe"))
let unread = room([item("Base", risks: [], read: false)])
check("an unread chain says the read has not run",
      L2beatRoom.headline(unread).contains("Reading"))
check("and so does the note", L2beatRoom.note(unread).contains("Reading"))

// The note's SECOND fact is always the ladder, in the rung's own meaning.
check("all-Stage-0 is said as what it means",
      L2beatRoom.note(room([item("A", risks: clean), item("B", risks: clean)]))
        .contains("operators can still change the rules"))
check("a mixed ladder counts how many passed Stage 0",
      L2beatRoom.note(room([item("A", stage: .stage0, risks: clean),
                            item("B", stage: .stage1, risks: clean)]))
        .contains("1 of 2"))
check("a chain off the ladder says so rather than being called Stage 0",
      L2beatRoom.note(room([item("A", stage: .notApplicable, risks: clean)]))
        .contains("doesn't place"))
check("staged counts only chains on the ladder",
      room([item("A", stage: .notApplicable, risks: clean),
            item("B", stage: .stage1, risks: clean)]).staged == 1)
check("bestRung ignores the unstaged",
      room([item("A", stage: .notApplicable, risks: clean),
            item("B", stage: .stage1, risks: clean)]).bestRung == 1)

// The row's own sub-line: L2BEAT's sentence verbatim where there is one.
check("the lead line quotes L2BEAT's sentence",
      L2beatRoom.leadLine(item("A", risks: [risk(.exitWindow, "None", .bad, "no window")]))
        == "no window")
check("an unread row says so rather than claiming nothing was found",
      L2beatRoom.leadLine(item("A", risks: [], read: false)).contains("Reading"))
check("a clean row counts the checks", L2beatRoom.leadLine(item("A", risks: clean)).contains("5"))

print("")
print("The news-led head (following, nothing watched)")

let followed = room([], news: .init(total: 12, recent: 2, chains: 7))
check("the followed headline counts the recent ones",
      L2beatRoom.headline(followed).contains("2"))
check("the followed headline never names a chain",
      !L2beatRoom.headline(followed).contains("Base"))
let calm = room([], news: .init(total: 12, recent: 0, chains: 7))
check("a quiet window is a real answer",
      L2beatRoom.headline(calm).contains("No incidents"))
check("the note names how many chains, not just how many incidents",
      L2beatRoom.newsNote(calm).contains("7"))
check("the note always states the upgrade",
      L2beatRoom.newsNote(calm).contains("Name the chains"))
// "none landed" and "none exist" are different claims, and only the second would be a
// clean bill of health for every chain L2BEAT covers.
let nothing = room([])
check("nothing landed reads as the read not having run",
      L2beatRoom.headline(nothing).contains("Reading"))
check("nothing landed offers the upgrade anyway",
      L2beatRoom.newsNote(nothing).contains("Name the chains"))
check("a room with no items and no news has no coverage note",
      L2beatRoom.coverageNote(nothing) == nil)
check("a capped room says how many it is showing",
      (L2beatRoom(items: [item("A", risks: clean)], total: 9, snapshotDay: "x").pipe {
          L2beatRoom.coverageNote($0) ?? "" }).contains("1 of 9"))
check("every head states whose reading it is",
      (L2beatRoom.coverageNote(quiet) ?? "").contains("not ours"))

print("")
print(failures == 0 ? "all checks passed" : "FAILED: \(failures)")
exit(failures == 0 ? 0 : 1)

extension L2beatRoom {
    func pipe<T>(_ f: (L2beatRoom) -> T) -> T { f(self) }
}
SWIFT

# The BUNDLE's own invariants, in a second main compiled ONCE.
#
# Split from the logic assertions for a measured reason: `L2beatDirectory.swift` is 124KB of
# struct literals, and including it in every mutation build took this harness past ten
# minutes — a new long pole in a pass whose current one is three. The mutations do not touch
# the bundle, so they no longer compile it. This binary is built once and proves the shipped
# snapshot satisfies every invariant the strip and the room rest on.
mkdir -p "$TMP/bundle"
cat > "$TMP/bundle/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

print("")
print("The bundled directory")

let bundled = L2beatDirectory.projects
check("the bundle is not empty", !bundled.isEmpty)
check("every bundled project has an id", bundled.allSatisfy { !$0.id.isEmpty })
check("ids are unique", Set(bundled.map(\.id)).count == bundled.count)
check("slugs are unique", Set(bundled.map(\.slug)).count == bundled.count)
// The measured invariant the whole strip rests on. If this ever fails, the five-cell shape
// needs a gate in front of it before it needs a sixth cell.
check("every bundled project carries all five risks",
      bundled.allSatisfy { $0.risks.count == 5 })
check("every risk has a value and a sentence",
      bundled.allSatisfy { $0.risks.allSatisfy { !$0.value.isEmpty && !$0.explanation.isEmpty } })
check("no bundled risk reads as unknown",
      bundled.allSatisfy { $0.risks.allSatisfy { $0.sentiment != .unknown } })
// The two identifiers really do diverge in the shipped bundle — the reason both exist.
check("the bundle really does hold ids that differ from their slugs",
      bundled.contains { $0.id != $0.slug })
check("the demo chains are all in the bundle",
      L2beatDirectory.demoChains.allSatisfy { id in bundled.contains { $0.id == id } })
check("lookup by id works", L2beatDirectory.project(L2beatDirectory.demoChains[0]) != nil)
check("lookup by an unknown id is nil", L2beatDirectory.project("nope") == nil)
check("the snapshot states the day it was taken", !L2beatDirectory.generated.isEmpty)

let seeds = L2beatDirectory.seededIncidents
check("the bundle carries incidents", !seeds.isEmpty)
check("every seeded incident is an incident", seeds.allSatisfy { $0.kind == .incident })
check("every seeded incident names a project in the bundle",
      seeds.allSatisfy { seed in bundled.contains { $0.id == seed.projectID } })
check("every seeded incident has a usable date", seeds.allSatisfy { $0.day.count == 10 })
check("seeded refs are unique", Set(seeds.map(\.ref)).count == seeds.count)
check("the seeds are newest first",
      zip(seeds, seeds.dropFirst()).allSatisfy { $0.day >= $1.day })
print("")
print(failures == 0 ? "all bundle checks passed" : "FAILED: \(failures)")
exit(failures == 0 ? 0 : 1)
SWIFT

echo "Assertions"
build() { swiftc -O -o "$TMP/l2b-selftest" "$1" "$2" "$3" "$4" "$TMP/main.swift" 2>"$TMP/build.log"; }
if ! build "$RATING" "$NEWS" "$ROOM" "$SHEET"; then
  echo "✗ the shipped source did not compile with the harness"
  tail -25 "$TMP/build.log"
  exit 1
fi
"$TMP/l2b-selftest"

echo ""
if ! swiftc -O -o "$TMP/l2b-bundle" "$RATING" "$NEWS" "$ROOM" "$SHEET" "$DIR" \
     "$TMP/bundle/main.swift" 2>"$TMP/bundle.log"; then
  echo "✗ the generated bundle did not compile against the shipped model"
  tail -25 "$TMP/bundle.log"
  exit 1
fi
"$TMP/l2b-bundle"

# --------------------------------------------------------------------------------------
# 3 · Mutations. A check that cannot fail proves nothing.
# --------------------------------------------------------------------------------------
echo ""
echo "Mutations (each must be caught)"

mutate() { # mutate <name> <rating|news|room|sheet> <from> <to>
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
  # WITHOUT the directory — see the split above. Measured: including that 124KB file in
  # every mutation build took this harness past ten minutes.
  if ! swiftc -O -o "$TMP/mut" "$a" "$b" "$c" "$d" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# THE default that must never happen.
mutate "an unknown sentiment must not read as good" rating \
  'return L2beatSentiment(rawValue: raw.lowercased()) ?? .unknown' \
  'return L2beatSentiment(rawValue: raw.lowercased()) ?? .good'
# The Arbitrum/honeypot case: the nested reading must reach the lead.
mutate "a worse nested reading must reach the lead" rating \
  'guard let second, second.sentiment.concern > sentiment.concern else { return sentiment }' \
  'guard let second, false, second.sentiment.concern > sentiment.concern else { return sentiment }'
mutate "the nested sentence must go with the nested severity" rating \
  'if let text = second.explanation, !text.isEmpty { return text }' \
  'if let text = second.explanation, false, !text.isEmpty { return text }'
# A chain off the ladder is not a worse Stage 0.
mutate "not-applicable must have no rung" rating \
  'case .notApplicable: return nil' 'case .notApplicable: return 0'
mutate "an unrecognised stage must not become Stage 0" rating \
  'return L2beatStage(rawValue: raw)' 'return L2beatStage(rawValue: raw) ?? .stage0'
# The lead ladder.
mutate "under review must outrank a finding" rating \
  'if underReview { return .underReview }' 'if false { return .underReview }'
mutate "a warning must lead when nothing is flagged" rating \
  'if risk.worstSentiment == .warning { return .finding(risk) }' \
  'if false { return .finding(risk) }'
mutate "a chain with no readings must read unread, not clean" rating \
  'guard !risks.isEmpty else { return .unread }' \
  'guard !risks.isEmpty || true else { return .unread }'
# The axis order the strip depends on.
mutate "the card must not read the payload's own risk order" rating \
  'L2beatRiskAxis.allCases.compactMap { axis in risks.first { $0.axis == axis } }' \
  'risks'
mutate "an unknown axis must be dropped, not guessed" rating \
  'let axis = L2beatRiskAxis.named(name),' \
  'let axis = L2beatRiskAxis.named(name) ?? .exitWindow,'
mutate "the page URL must be built from the slug" rating \
  'scaling/projects/\(slug)' 'scaling/projects/\(id)'
# Revisions.
mutate "a risk going unknown must not be reported" rating \
  'guard now.sentiment != .unknown else { continue }' \
  'guard true else { continue }'
mutate "a stage move must be reported" rating \
  'if let now = after.stage, now != before.stage {' \
  'if let now = after.stage, false, now != before.stage {'
# Milestones.
mutate "a milestone must land at UTC noon" news 'components.hour = 12' 'components.hour = 0'
mutate "a field name must be anchored so sourceUrl is not url" news \
  'if prior.isLetter || prior.isNumber || prior == "_" { continue }' \
  'if false { continue }'
mutate "an undated milestone must be dropped" news \
  'let day = string(field: "date", in: entry).map(dayString),' \
  'let day = string(field: "date", in: entry).map(dayString) ?? "2020-01-01",'
mutate "wrapped prose must be unwrapped" news \
  'raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })' \
  'raw.split(whereSeparator: { $0 == "\u{0}" })'
mutate "the ref must carry the day" news \
  '"\(L2beatIdentity.newsPrefix)\(projectID):\(day):\(L2beatNewsParse.slug(title))"' \
  '"\(L2beatIdentity.newsPrefix)\(projectID):\(L2beatNewsParse.slug(title))"'
# The room.
mutate "a recent incident must rank first" room \
  'if a.recentIncidents != b.recentIncidents { return a.recentIncidents > b.recentIncidents }' \
  'if false { return a.recentIncidents > b.recentIncidents }'
mutate "the ranking must be total" room \
  'return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending' \
  'return false'
mutate "a clean chain must not be called safe" room \
  'return String(localized: "L2BEAT flags nothing on \(top.name)")' \
  'return String(localized: "\(top.name) is safe")'
mutate "the note must count how many passed Stage 0" room \
  'return String(localized: "\(above) of \(onLadder.count) have passed Stage 0; the rest are still Stage 0.")' \
  'return String(localized: "mixed")'
mutate "the followed head must name how many chains" room \
  'let across = news.chains == 1' 'let across = true || news.chains == 1'
# The sheet grammar.
mutate "a stage revision ref must not read as a risk one" sheet \
  'if parts[1] == stageSubject {' 'if false {'
mutate "an unknown stage token must be refused" sheet \
  'default: return nil' 'default: return .stage0'

echo ""
echo "l2beat-selftest: all checks passed"
