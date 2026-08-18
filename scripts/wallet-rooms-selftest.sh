#!/bin/zsh
# Casberi wallet-room self-test — the SHIPPED pure judgement behind the FIVE
# WALLET-RIDING feed-room heads (prd §349, 2026-08-10; Railgun added §350,
# Safe added §349's own amendment, both 2026-08-11):
#
#   Casberi/Casberi/Model/PeerRoom.swift
#   Casberi/Casberi/Model/PrivacyPoolsRoom.swift
#   Casberi/Casberi/Model/GnosisPayRoom.swift
#   Casberi/Casberi/Model/RailgunRoom.swift
#   Casberi/Casberi/Model/SafeRoom.swift
#
# All five are Foundation-only BY DESIGN, so all five are compiled WHOLE AND
# UNMODIFIED rather than extracted — the strongest form of "the harness ran the
# shipped logic". Everything that touches `Thing`/`SafeBridge` lives in the
# `…RoomSource.swift` half, which no harness can compile and which contains no
# judgement to test.
#
# WHY A HARNESS AND NOT A LIVE CHECK. These four seats ride the WATCHED
# WALLETS: there is no key to mint, no account to open, and nothing on this host
# can make a Peer fill settle, a 0xBow screener rule, a Gnosis Pay card get
# swiped, or a Railgun shield land. A room's numbers can only ever be checked by
# somebody who already has the history — and every failure mode here is a
# SILENT WRONG ANSWER that renders perfectly:
#
#   · every SALE counted as a purchase, because `peer:sell:` also starts
#     `peer:` — a card reporting that you only ever buy, on an account that
#     mostly sells
#   · a dormant room dated by a fall-through, whose timestamp records when we
#     LOOKED and not when anything happened
#   · a fill with no rail bucketed under an invented "Unknown" that then ranks
#     beside the real ones
#   · a deposit carrying no state tag reported as "in review", which is a claim
#     about the screener made with no evidence
#   · a cleared deposit counted twice — once as itself, once as its own alert
#   · one deposit stuck on proof-of-innocence ranked below forty that cleared
#   · EUR added to GBP and printed as one figure
#   · "up 400%" against a window the room was never watching
#   · a spend whose amount could not be read folded into a total as zero
#   · a shield with no readable token bucketed under an invented "Unknown"
#   · a token's shielded amount presented as complete when one shield in it
#     carried no readable amount at all
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PEER="Casberi/Casberi/Model/PeerRoom.swift"
POOLS="Casberi/Casberi/Model/PrivacyPoolsRoom.swift"
GNOSIS="Casberi/Casberi/Model/GnosisPayRoom.swift"
RAILGUN="Casberi/Casberi/Model/RailgunRoom.swift"
SAFE="Casberi/Casberi/Model/SafeRoom.swift"
for f in "$PEER" "$POOLS" "$GNOSIS" "$RAILGUN" "$SAFE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

SRC_PEER="Casberi/Casberi/Model/PeerRoomSource.swift"
SRC_POOLS="Casberi/Casberi/Model/PrivacyPoolsRoomSource.swift"
SRC_GNOSIS="Casberi/Casberi/Model/GnosisPayRoomSource.swift"
SRC_RAILGUN="Casberi/Casberi/Model/RailgunRoomSource.swift"
SRC_SAFE="Casberi/Casberi/Model/SafeRoomSource.swift"
BR_PEER="Casberi/Casberi/Model/PeerBridge.swift"
BR_POOLS="Casberi/Casberi/Model/PrivacyPoolsBridge.swift"
BR_GNOSIS="Casberi/Casberi/Model/GnosisPayBridge.swift"
BR_RAILGUN="Casberi/Casberi/Model/RailgunBridge.swift"
CARD_PEER="Casberi/Casberi/Screens/PeerRoomCard.swift"
CARD_POOLS="Casberi/Casberi/Screens/PrivacyPoolsRoomCard.swift"
CARD_GNOSIS="Casberi/Casberi/Screens/GnosisPayRoomCard.swift"
CARD_RAILGUN="Casberi/Casberi/Screens/RailgunRoomCard.swift"
CARD_SAFE="Casberi/Casberi/Screens/SafeRoomCard.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled functions cannot prove about themselves. A perfect
# `ordered` is worthless if the card draws its own order, and a perfect
# `compose` is worthless if the head is never rendered or the bridge stops
# stamping the field it reads.

# THE BUG THIS PASS FIXED, made mechanical. §311 landed deposits under
# `privacypools:dep:` and had `retag` look them up under
# `privacypools:deposit:`, so the fetch matched nothing on any device, ever:
# every deposit stayed tagged `Pending` for life, cleared ones included.
# Invisible — the alert row still landed and still rained, and the only casualty
# was the tag nobody was reading yet. One constant now, and this guard is what
# keeps it one.
grep -q 'let ref = depositRefPrefix + label' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge.retag no longer builds its ref from depositRefPrefix — the §311 tag can silently stop moving again"; exit 1; }
grep -q 'let ref = depositRefPrefix + (label ?? deposit.commitment)' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge no longer LANDS deposits under depositRefPrefix — the constant no longer joins the two halves"; exit 1; }
grep -q 'static let depositRefPrefix = PrivacyPoolsRoom.depositPrefix' "$BR_POOLS" \
  || { echo "✗ the bridge's deposit prefix no longer comes from PrivacyPoolsRoom — the room could count deposits the bridge doesn't land"; exit 1; }

# The negative half of the same guard, and it reads a COMMENT-STRIPPED copy on
# purpose. Both files DOCUMENT the broken spelling by quoting it (that is how
# the fix explains itself), so a guard grepping raw source fires against the
# prose explaining the fix — the Obsidian/Cursor lesson, earned again here on
# this guard's own first run. Line-leading `//` only, which is where all of that
# prose lives; a URL in a string literal survives untouched.
strip_comments() {
  python3 -c 'import sys
for line in open(sys.argv[1]):
    if line.lstrip().startswith("//"): continue
    sys.stdout.write(line)' "$1"
}
for f in "$BR_POOLS" "$POOLS" "$SRC_POOLS"; do
  strip_comments "$f" > "$TMP/stripped.swift"
  if grep -q 'privacypools:deposit:' "$TMP/stripped.swift"; then
    echo "✗ the dead 'privacypools:deposit:' spelling is back in $f — deposits land under 'privacypools:dep:'"; exit 1
  fi
done

# The fields each head reads, still stamped by the bridge that lands them.
# Without these a head composes perfectly over nothing.
grep -q 'thing.authorHandle = story.method' "$BR_PEER" \
  || { echo "✗ PeerBridge no longer stamps the funding rail on a BUY — every purchase would be an unplaced fill"; exit 1; }
grep -q 'thing.authorHandle = signal.method' "$BR_PEER" \
  || { echo "✗ PeerBridge no longer stamps the funding rail on a SELL — the room would rank half its traffic"; exit 1; }
grep -q 'thing.priceValue = amount' "$BR_GNOSIS" \
  || { echo "✗ GnosisPayBridge no longer stamps priceValue — every spend would be unpriced and the card could state no money at all"; exit 1; }
grep -q 'thing.priceCurrency = spend.token.currency' "$BR_GNOSIS" \
  || { echo "✗ GnosisPayBridge no longer stamps priceCurrency — spends would drop out of every total with nothing on screen to say so"; exit 1; }
grep -q 'tags: \["Shielded", "Pending"\]' "$BR_POOLS" \
  || { echo "✗ a Privacy Pools deposit no longer lands wearing a state tag — every deposit would compose as untagged"; exit 1; }

# The source name each room filters on, still the one the bridge lands under.
# The constants exist so the two agree; these check they still describe reality.
grep -q 'static let sourceName = "Peer"' "$BR_PEER" \
  || { echo "✗ PeerBridge.sourceName changed — PeerRoomSource would filter for a source nothing lands under"; exit 1; }
grep -q 'source: "Peer"' "$BR_PEER" \
  || { echo "✗ PeerBridge no longer lands rows under \"Peer\""; exit 1; }
grep -q 'static let sourceName = "Privacy Pools"' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge.sourceName changed"; exit 1; }
grep -q 'source: "Privacy Pools"' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge no longer lands rows under \"Privacy Pools\""; exit 1; }
grep -q 'static let sourceName = "Gnosis Pay"' "$BR_GNOSIS" \
  || { echo "✗ GnosisPayBridge.sourceName changed"; exit 1; }
grep -q 'source: "Gnosis Pay"' "$BR_GNOSIS" \
  || { echo "✗ GnosisPayBridge no longer lands rows under \"Gnosis Pay\""; exit 1; }
grep -q 'static let sourceName = "Railgun"' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge.sourceName changed"; exit 1; }

# The move as DATA, still stamped by the bridge that lands it (prd §350) —
# without this the Railgun head composes perfectly over nothing.
grep -q 'thing.priceValue = move.raw / pow(10, Double(decimals))' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge no longer stamps priceValue on a move — every shield/unshield would be unpriced"; exit 1; }
grep -q 'thing.priceCurrency = symbol' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge no longer stamps priceCurrency — moves would drop out of every token grouping"; exit 1; }

# Corollary 4 — filtered live at the boundary, before any stored property is
# read. The caller hands these a debounced snapshot and the foreground sweep
# deletes rows while it is held.
for f in "$SRC_PEER" "$SRC_POOLS" "$SRC_GNOSIS" "$SRC_RAILGUN"; do
  grep -q 'things.live' "$f" \
    || { echo "✗ $f no longer filters live at the boundary (corollary 4)"; exit 1; }
done

# Rendered at all. A head that composes and is never drawn is the §219 social
# roster, which spent weeks that way.
grep -q 'case .peer(let room)' "$FEED" \
  || { echo "✗ the Peer head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case .privacyPools(let room)' "$FEED" \
  || { echo "✗ the Privacy Pools head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case .gnosisPay(let room)' "$FEED" \
  || { echo "✗ the Gnosis Pay head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case .railgun(let room)' "$FEED" \
  || { echo "✗ the Railgun head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case .safe(let room)' "$FEED" \
  || { echo "✗ the Safe head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case PeerRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Peer room"; exit 1; }
grep -q 'case PrivacyPoolsRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Privacy Pools room"; exit 1; }
grep -q 'case GnosisPayRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Gnosis Pay room"; exit 1; }
grep -q 'case RailgunRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Railgun room"; exit 1; }
grep -q 'case SafeRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Safe room"; exit 1; }

# The cards draw through the SHIPPED arithmetic and honour the row caps, so a
# card cannot quietly re-rank or over-draw what the room composed.
grep -q 'room.rails.prefix(PeerRoomSource.rowCap)' "$CARD_PEER" \
  || { echo "✗ the Peer card no longer honours the rail cap — the footnote would count rows that are drawn anyway"; exit 1; }
grep -q 'room.currencies.prefix(GnosisPayRoomSource.rowCap)' "$CARD_GNOSIS" \
  || { echo "✗ the Gnosis Pay card no longer honours the currency cap"; exit 1; }
grep -q 'room.tokens.prefix(RailgunRoomSource.rowCap)' "$CARD_RAILGUN" \
  || { echo "✗ the Railgun card no longer honours the token cap"; exit 1; }
grep -q 'room.entries.prefix(SafeRoomSource.rowCap)' "$CARD_SAFE" \
  || { echo "✗ the Safe card no longer honours the entry cap"; exit 1; }
# The strip exists so that superseding `FeedInsight.cardMonths` costs nothing.
# A head outranks the generic registries, so a head that draws less than the
# card it displaced is a regression wearing a new feature.
grep -q 'GnosisPayRoom.monthShare(total: month.total, of: top)' "$CARD_GNOSIS" \
  || { echo "✗ the Gnosis Pay history strip no longer sizes its columns through the shipped monthShare()"; exit 1; }
grep -q 'case "Gnosis Pay":' "Casberi/Casberi/Model/FeedInsight.swift" \
  || { echo "✗ FeedInsight's cardMonths entry for Gnosis Pay is gone — it is the head's FALLBACK below the minimums, not dead code"; exit 1; }
grep -q 'case "Peer":' "Casberi/Casberi/Model/FeedInsight.swift" \
  || { echo "✗ FeedInsight's §311 leaderboard for Peer is gone — it is the head's fallback below minimumFills"; exit 1; }
grep -q 'case "Privacy Pools": return shieldedReview' "Casberi/Casberi/Model/FeedInsight.swift" \
  || { echo "✗ FeedInsight's §311 distribution for Privacy Pools is gone — it is the head's fallback"; exit 1; }
grep -q 'PrivacyPoolsRoom.share(count: segment.count,' "$CARD_POOLS" \
  || { echo "✗ the Privacy Pools split no longer sizes its segments through the shipped share()"; exit 1; }
grep -q 'of: room.deposits' "$CARD_POOLS" \
  || { echo "✗ the Privacy Pools split no longer divides through EVERY deposit — untagged ones would vanish and partial knowledge would draw as complete"; exit 1; }
grep -q 'state.resolved ? Self.mark.opacity' "$CARD_POOLS" \
  || { echo "✗ the Privacy Pools split no longer encodes open-vs-resolved — its two weights are the card's only reading"; exit 1; }

# The §219 failure inverted — see `-roomInsightProbe`'s own comment. A head in
# `shapedSections` with no line here makes the probe confidently report that a
# room "leads with NOTHING" when it leads with a card.
grep -q 'note("peerHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Peer head"; exit 1; }
grep -q 'note("privacyPoolsHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Privacy Pools head"; exit 1; }
grep -q 'note("gnosisPayHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Gnosis Pay head"; exit 1; }
grep -q 'note("railgunHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Railgun head"; exit 1; }
grep -q 'note("safeHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Safe head"; exit 1; }
# Each head gets its own probe, because for these five seats an empty room is
# usually the HEALTHY answer and only one or two causes per room are bugs.
for key in peerRoomProbe privacyPoolsRoomProbe gnosisPayRoomProbe railgunRoomProbe safeRoomProbe; do
  grep -q "Hook(key: \"$key\")" "$PROBES" \
    || { echo "✗ -$key is gone — an empty head's several causes would be indistinguishable"; exit 1; }
done

# Safe's own `sourceName` — the 2026-08-11 re-source (SafeBridge's top-of-file
# doc, amendment 8). Change it here and the room head silently stops
# composing over a corpus whose rows still carry the OLD source string.
grep -q 'static let sourceName = "Safe"' "Casberi/Casberi/Model/SafeBridge.swift" \
  || { echo "✗ SafeBridge.sourceName changed"; exit 1; }

# --- 2026-08-17 drift guards ------------------------------------------------
# Wiring the compiled functions above cannot prove about themselves, each one a
# failure that renders as a perfectly good-looking card.

# THE LANDED ROW AND THE HEAD MUST AGREE. `syncPending` skipped an
# already-landed row entirely while `trackPending` kept refreshing the same
# counts for the head, so the feed said "2 of 3 — your signature is needed"
# after two more people had signed, one line under a head that said otherwise.
grep -q 'heals.append(Heal(' "Casberi/Casberi/Model/SafeBridge.swift" \
  || { echo "✗ SafeBridge no longer heals an already-landed pending row — its title and tag would freeze at landing while the room head stays live"; exit 1; }
# ONE definition of the three states. Two copies of "what does ready mean"
# drift, and then a row and the head above it describe the same transaction
# differently.
grep -q 'SafeRoom.Entry(ref: "", safeAddress: ""' "Casberi/Casberi/Model/SafeBridge.swift" \
  || { echo "✗ SafeBridge.rowFace no longer derives ready/awaitsYou from SafeRoom — the feed row and the room head would each carry their own copy of the rule"; exit 1; }
# The notification tag rides `awaitsYou`, never the raw `yourTurn` — otherwise
# a threshold already met without you fires a lock-screen alarm asking for a
# signature nobody needs.
grep -q 'if entry.awaitsYou {' "Casberi/Casberi/Model/SafeBridge.swift" \
  || { echo "✗ the 'Your turn' tag no longer rides awaitsYou — a fully-signed transaction would alarm for a signature it does not need"; exit 1; }
# The nonce is what makes a rival a rival. Stop stamping it and the collision
# warning silently never fires again, with the card still rendering perfectly.
grep -q 'nonce: tx\["nonce"\] as? Int' "Casberi/Casberi/Model/SafeBridge.swift" \
  || { echo "✗ SafeBridge no longer stamps the queue nonce — same-nonce rivals become undetectable"; exit 1; }

# THE DEAD CONTROL. `compose` returns a card on module risk ALONE, and both of
# the card's tap paths used to resolve through `room.lead` — so that exact card
# announced "Opens this Safe" and did nothing.
grep -q 'room.lead?.ref ?? fallbackRef' "$CARD_SAFE" \
  || { echo "✗ the Safe card no longer falls back to a real destination — a module-only card would announce a door it does not have"; exit 1; }
grep -q 'SafeRoomSource.fallbackRef(things:' "$FEED" \
  || { echo "✗ FeedScreen no longer hands the Safe card its fallback ref"; exit 1; }
# ...and when there is no destination at all, BOTH the gesture and the
# accessibility action must be withheld rather than left announcing one.
grep -q 'if let destination {' "$CARD_SAFE" \
  || { echo "✗ the Safe card's tap is no longer gated on having somewhere to go"; exit 1; }
# The card must draw the state line, or a nonce collision is computed and never
# said — the one fact nothing else in this app surfaces.
grep -q 'SafeRoom.stateNote(room)' "$CARD_SAFE" \
  || { echo "✗ the Safe card no longer draws the state note — rival transactions would be detected and never mentioned"; exit 1; }
grep -q 'room.isContested(entry)' "$CARD_SAFE" \
  || { echo "✗ the Safe card no longer marks WHICH rings collide — the sentence says two of these contest and nothing says which"; exit 1; }

# The chip's long-press peek must preview the room it opens. Safe's head is a
# FIGURE (rings), not a text hero, so it belongs in this chain for X's exact
# reason — without it the peek drew a blank.
grep -q 'source == SafeRoomSource.source, let room = SafeRoomSource.compose' \
  "Casberi/Casberi/Model/RoomFigure.swift" \
  || { echo "✗ the Safe chip peek no longer previews the Safe head — long-pressing the chip would draw nothing"; exit 1; }

# The widget half. A your-turn signature has NO due date, so it can never be a
# WidgetDeadline without inventing one — and an invented date would sort among
# real deadlines and draw itself late.
grep -q 'static func safeCall(things:' "Casberi/Casberi/Model/WidgetPublish.swift" \
  || { echo "✗ the Needs-you tile no longer receives the Safe signature call"; exit 1; }
grep -q 'enum WidgetSafe {' "Casberi/Shared/WidgetPayload.swift" \
  || { echo "✗ the WidgetSafe payload is gone"; exit 1; }
# It is a READING, so it takes the short window. Sharing the deadlines' 36
# hours would leave a count on the Home Screen a day and a half after it
# stopped being true.
grep -q 'static let freshness: TimeInterval = 6 \* 3600' "Casberi/Shared/WidgetPayload.swift" \
  || { echo "✗ the Safe call no longer carries the READING freshness window — a stale count would sit on the Home Screen for 36 hours"; exit 1; }
# "Nothing due" while a signature waits is the bug this payload exists to fix.
grep -q 'var isEmpty: Bool { rows.isEmpty && (safe?.awaitsYou ?? 0) == 0 }' \
  "Casberi/CasberiWidgets/NeedsYouWidget.swift" \
  || { echo "✗ the Needs-you tile can say 'Nothing due' while a signature is waiting on you"; exit 1; }

# The brief's rung — the ONLY surface that can re-raise a your-turn signature,
# since §306's news window forbids a second notification forever after.
grep -q 'safeStuckLine(now: now)' "Casberi/Casberi/Model/TodayBrief.swift" \
  || { echo "✗ the Today brief no longer carries the stuck-signature rung — a request nobody answered would have no surface at all after its landing day"; exit 1; }

# The demo has to be able to SHOW all three states, or they ship unseen — the
# standing demo-parity rule, and what verify.sh's room-head check reads.
grep -q 'wallet:safe:eth:demo3' "Casberi/Casberi/Model/DemoSeedAll.swift" \
  || { echo "✗ the demo no longer seeds a rival pair / fully-signed Safe queue — the three states would ship unseen"; exit 1; }


cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

let cal = Calendar.current
let t0 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: t0)! }
// A locale pinned so money strings are assertable at all — the app never
// passes one.
let us = Locale(identifier: "en_US")

// ===========================================================================
print("Peer — reading a row")
// ===========================================================================

// THE ordering fact: every ref begins `peer:`, so a bare-prefix-first table
// reads every sale as a purchase.
check("a buy is read from its ref", PeerRoom.kind(ref: "peer:0xabc") == .bought)
check("a SELL is not read as a buy", PeerRoom.kind(ref: "peer:sell:0xabc") == .sold)
check("an expired fill is its own kind", PeerRoom.kind(ref: "peer:expired:0xabc") == .fellThrough)
check("a ref this build doesn't know is nil, never guessed",
      PeerRoom.kind(ref: "peer2:0xabc") == nil)
check("no ref at all is nil", PeerRoom.kind(ref: nil) == nil)
check("a fall-through settled nothing", PeerRoom.Kind.fellThrough.settled == false)
check("a sale settled", PeerRoom.Kind.sold.settled)

func fill(_ ref: String, rail: String? = nil, at: Date = t0) -> PeerRoom.Sighting {
    PeerRoom.Sighting(ref: ref, rail: rail, at: at)
}

print("")
print("Peer — composing")
let peer = PeerRoom.compose(fills: [
    fill("peer:1", rail: "Venmo", at: day(-1)),
    fill("peer:2", rail: "Venmo", at: day(-3)),
    fill("peer:sell:3", rail: "Venmo", at: day(-5)),
    fill("peer:4", rail: "Cash App", at: day(-2)),
    fill("peer:5", at: day(-6)),                    // no rail at all
    fill("peer:expired:6", at: day(0)),             // "dated" today, but isn't
])
check("buys are counted", peer.bought == 4)
check("sells are counted apart", peer.sold == 1)
// Counted as a buy AND as unplaced: the fill is real, the rail is not known.
check("a fill with no rail is counted, not bucketed", peer.unplaced == 1)
check("a fall-through is counted", peer.fellThrough == 1)
check("a fall-through is NOT a fill", peer.fills == 5)
check("no 'Unknown' rail was invented", peer.rails.allSatisfy { $0.name != "Unknown" })
check("two real rails", peer.rails.count == 2)
check("the busiest rail leads", peer.lead?.name == "Venmo")
check("a rail counts both directions", peer.lead?.fills == 3)
// THE date fact: an expired row is stamped when we looked. Letting it date the
// room makes a dormant account read as active this morning.
check("a fall-through never dates the room", peer.newest == day(-1))

print("")
print("Peer — ranking is total")
func rail(_ n: String, b: Int, s: Int = 0, at: Date = t0) -> PeerRoom.Rail {
    PeerRoom.Rail(name: n, bought: b, sold: s, newest: at)
}
check("more fills wins",
      PeerRoom.ordered([rail("a", b: 1), rail("b", b: 9)]).first?.name == "b")
check("a tie on fills breaks on recency",
      PeerRoom.ordered([rail("a", b: 2, at: day(-9)), rail("b", b: 2, at: day(-1))]).first?.name == "b")
// Without this the order comes off a dictionary, and the card reshuffles
// between opens over identical rows — which reads as broken.
check("a tie on fills AND recency breaks on name",
      PeerRoom.ordered([rail("zulu", b: 2), rail("alpha", b: 2)]).first?.name == "alpha")

print("")
print("Peer — the bar")
check("a share is a fraction of the busiest", PeerRoom.share(fills: 3, of: 6) == 0.5)
check("the busiest is full", PeerRoom.share(fills: 6, of: 6) == 1)
// A zero denominator draws as a NaN-width capsule, which SwiftUI renders as
// nothing (the AgentPanel lesson).
check("a zero denominator can't divide by zero", PeerRoom.share(fills: 3, of: 0) == 0)
check("a share never exceeds one", PeerRoom.share(fills: 9, of: 6) == 1)

print("")
print("Peer — words")
check("both directions are named when both happened",
      PeerRoom.railLine(rail("a", b: 3, s: 2)) == "3 in · 2 out")
check("a sell-only rail says sales", PeerRoom.railLine(rail("a", b: 0, s: 2)) == "2 sales")
check("a buy-only rail says purchases", PeerRoom.railLine(rail("a", b: 4)) == "4 purchases")
check("one purchase is singular", PeerRoom.railLine(rail("a", b: 1)) == "1 purchase")
check("the headline names the leading rail",
      PeerRoom.headline(peer).contains("Venmo"))
check("the headline counts every settled fill, placed or not",
      PeerRoom.headline(peer).contains("5 fills"))
check("one rail gets a simpler sentence",
      PeerRoom.headline(PeerRoom.compose(fills: [fill("peer:1", rail: "Revolut"),
                                                 fill("peer:2", rail: "Revolut")]))
        == "2 fills settled through Revolut")
// Naming a rail here would be the invention `unplaced` exists to refuse.
check("fills with no rail at all still get an honest headline",
      PeerRoom.headline(PeerRoom.compose(fills: [fill("peer:1"), fill("peer:2")]))
        == "2 fills settled on Peer")
check("the note carries the direction, not the rail",
      PeerRoom.note(peer) == "4 bought · 1 sold")
check("a cash-out-only room says so",
      PeerRoom.note(PeerRoom.compose(fills: [fill("peer:sell:1", rail: "Venmo")]))
        == "Cashing out — 1 sold, nothing bought")

print("")
print("Peer — the footnote never hides a row")
let footnote = PeerRoom.footnote(peer, drawn: 1, now: t0) ?? ""
check("undrawn rails are counted", footnote.contains("1 more rail"))
check("unplaced fills are counted", footnote.contains("1 fill has no rail"))
check("fall-throughs are counted", footnote.contains("1 sale fell through"))
// Never dated, never called recent — see PeerRoom's own type note.
check("a fall-through is never dated in the footnote",
      !footnote.contains("day") || footnote.contains("nothing for"))
check("a busy room needs no idle clause",
      PeerRoom.idleNote(newest: day(-3), now: t0) == nil)
check("a long silence is stated",
      PeerRoom.idleNote(newest: day(-40), now: t0) == "nothing for 40 days")
check("a fortnight is not a fact about anything",
      PeerRoom.idleNote(newest: day(-14), now: t0) == nil)

print("")
print("Peer — when there is no card")
check("one fill is a row, not a card",
      PeerRoom.compose(fills: [fill("peer:1", rail: "Venmo")]).isEmpty)
check("two fills earn a card",
      !PeerRoom.compose(fills: [fill("peer:1", rail: "Venmo"), fill("peer:2")]).isEmpty)
// Real fills nobody could place still have plenty to say, and hiding the card
// would leave no hint that anything is missing.
check("unplaced fills still earn a card",
      !PeerRoom.compose(fills: [fill("peer:1"), fill("peer:2")]).isEmpty)
// `unplaced` is a SUBSET of `fills`, not a sibling: a fill is counted as bought
// or sold before its rail is looked at. Adding the two makes ONE unplaced fill
// clear the minimum on its own and draw a card over a single row.
check("one unplaced fill is one fill, not two",
      PeerRoom.compose(fills: [fill("peer:1")]).isEmpty)
check("the counts don't double up",
      PeerRoom.compose(fills: [fill("peer:1")]).fills == 1
        && PeerRoom.compose(fills: [fill("peer:1")]).unplaced == 1)
check("fall-throughs alone do not earn a card",
      PeerRoom.compose(fills: [fill("peer:expired:1"), fill("peer:expired:2")]).isEmpty)

// ===========================================================================
print("")
print("Privacy Pools — reading a row")
// ===========================================================================

func pp(_ ref: String, _ tags: [String] = [], at: Date = t0) -> PrivacyPoolsRoom.Sighting {
    PrivacyPoolsRoom.Sighting(ref: ref, tags: tags, at: at)
}

// The mirror the whole card rests on: these raw values ARE the tag strings
// `PrivacyPoolsBridge.retag` writes.
check("the tag vocabulary is the bridge's",
      PrivacyPoolsRoom.states == ["Pending", "Cleared", "Declined", "Needs proof"])
check("a state is read off the tag", PrivacyPoolsRoom.state(tags: ["Shielded", "Cleared"]) == .cleared)
check("the shielded marker is not a state", PrivacyPoolsRoom.state(tags: ["Shielded"]) == nil)
// Defaulting to pending is a claim about the screener made with no evidence —
// a deposit that cleared two months ago reported as still waiting.
check("no state tag is nil, never pending", PrivacyPoolsRoom.state(tags: []) == nil)
check("only proof needs YOU", PrivacyPoolsRoom.State.needsProof.needsYou)
check("a decline is a decision already made", PrivacyPoolsRoom.State.declined.needsYou == false)
check("cleared and declined are both over",
      PrivacyPoolsRoom.State.cleared.resolved && PrivacyPoolsRoom.State.declined.resolved)
check("pending is not resolved", PrivacyPoolsRoom.State.pending.resolved == false)

print("")
print("Privacy Pools — composing")
let pools = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:1", ["Shielded", "Pending"], at: day(-2)),
    pp("privacypools:dep:2", ["Shielded", "Pending"], at: day(-4)),
    pp("privacypools:dep:3", ["Shielded", "Cleared"], at: day(-9)),
    pp("privacypools:dep:4", ["Shielded", "Needs proof"], at: day(-6)),
    pp("privacypools:dep:5", ["Shielded"], at: day(-20)),          // pre-§311
    pp("privacypools:ragequit:6", at: day(-1)),
    // The announcement of deposit 3 clearing. Counting it would report that
    // deposit twice — once as itself, once as its own news.
    pp("privacypools:status:3", at: day(-9)),
    pp("privacypools:poi:4", at: day(-6)),
])
check("deposits are counted", pools.deposits == 5)
check("an untagged deposit is counted apart", pools.untagged == 1)
check("an alert is NOT a deposit", pools.deposits == 5 && pools.segments.reduce(0) { $0 + $1.count } == 4)
check("a reclaim is counted apart from the states", pools.reclaimed == 1)
check("what is still open is counted", pools.waiting == 3)
check("a reclaim never dates the room", pools.newest == day(-2))

print("")
print("Privacy Pools — the ranking that matters")
// One stuck deposit outranks forty that cleared: the forty need nothing from
// anybody, and the one is the entire reason to look.
check("proof-required leads everything", pools.lead?.state == .needsProof)
check("the stuck deposit is found", pools.needsYou?.count == 1)
check("a decline outranks a pending", PrivacyPoolsRoom.rank(.declined) > PrivacyPoolsRoom.rank(.pending))
check("a pending outranks a cleared", PrivacyPoolsRoom.rank(.pending) > PrivacyPoolsRoom.rank(.cleared))
let lopsided = PrivacyPoolsRoom.compose(rows:
    (0..<40).map { pp("privacypools:dep:c\($0)", ["Cleared"]) }
    + [pp("privacypools:dep:stuck", ["Needs proof"])])
check("one stuck deposit still leads forty cleared ones", lopsided.lead?.state == .needsProof)
check("and the headline says so",
      PrivacyPoolsRoom.headline(lopsided, now: t0) == "A deposit needs your proof")

print("")
print("Privacy Pools — oldest-in-state and observed review time")
let staleRoom = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:old", ["Pending"], at: day(-10)),
])
check("the headline names the wait once it clears the floor",
      PrivacyPoolsRoom.headline(staleRoom, now: t0).contains("10 days"))
let freshRoom = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:new", ["Pending"], at: day(-1)),
])
check("a wait under the floor says nothing extra",
      PrivacyPoolsRoom.headline(freshRoom, now: t0) == "1 deposit is still in review")

// A deposit and its own status alert share the SAME label suffix — that is
// what lets the room pair "when it landed" to "when we saw it resolve" with
// no new field and no new read.
let reviewed = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:r1", ["Cleared"], at: day(-9)),
    pp("privacypools:status:r1", [], at: day(-4)),
])
check("a deposit paired with its own status alert yields a real review time",
      reviewed.reviewDays == 5)
let unresolved = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:r2", ["Pending"], at: day(-9)),
])
check("no observed resolution means no review-time claim", unresolved.reviewDays == nil)
let reversed = PrivacyPoolsRoom.compose(rows: [
    pp("privacypools:dep:r3", ["Cleared"], at: day(-1)),
    pp("privacypools:status:r3", [], at: day(-9)),
])
check("a resolution dated before its own deposit is never used", reversed.reviewDays == nil)
check("median, not mean, over several observed reviews",
      PrivacyPoolsRoom.medianDays([1, 3, 100]) == 3)

print("")
print("Privacy Pools — the split")
// The denominator is EVERY deposit, so the drawn segments legitimately fall
// short and the gap is the unknown. Dividing through the tagged count alone
// would present partial knowledge as complete.
check("the split divides through every deposit including untagged ones",
      abs(PrivacyPoolsRoom.share(count: 1, of: pools.deposits) - 0.2) < 0.0001)
check("the drawn segments deliberately do not fill the bar",
      abs(pools.segments.reduce(0.0) {
          $0 + PrivacyPoolsRoom.share(count: $1.count, of: pools.deposits) } - 0.8) < 0.0001)
check("a zero denominator can't divide by zero", PrivacyPoolsRoom.share(count: 2, of: 0) == 0)

print("")
print("Privacy Pools — words")
check("a state's line says what it MEANS, not just the verdict",
      PrivacyPoolsRoom.meaning(.declined) == "reclaim to your wallet")
check("cleared says what you can now do",
      PrivacyPoolsRoom.meaning(.cleared) == "ready to withdraw privately")
check("the note carries the shape of the rest",
      PrivacyPoolsRoom.note(pools) == "3 of 5 still waiting on the screener")
check("an all-resolved room says so",
      PrivacyPoolsRoom.note(PrivacyPoolsRoom.compose(rows: [pp("privacypools:dep:1", ["Cleared"])]))
        == "Every review is finished")
check("a wholly unruled room says so",
      PrivacyPoolsRoom.note(PrivacyPoolsRoom.compose(rows: [pp("privacypools:dep:1", ["Pending"])]))
        == "None of them have been ruled on yet")
let ppFoot = PrivacyPoolsRoom.footnote(pools, now: t0) ?? ""
check("untagged deposits are named in the footnote",
      ppFoot.contains("1 deposit's status is unknown"))
check("reclaims are named", ppFoot.contains("1 reclaimed"))
check("a room of pre-tag deposits gets an honest headline",
      PrivacyPoolsRoom.headline(PrivacyPoolsRoom.compose(rows: [
          pp("privacypools:dep:1"), pp("privacypools:dep:2")]))
        == "2 deposits in Privacy Pools")
check("a fully reclaimed room still draws",
      !PrivacyPoolsRoom.compose(rows: [pp("privacypools:ragequit:1")]).isEmpty)
check("an alert on its own is no card",
      PrivacyPoolsRoom.compose(rows: [pp("privacypools:status:1")]).isEmpty)

// ===========================================================================
print("")
print("Gnosis Pay — composing")
// ===========================================================================

func spend(_ amount: Double?, _ code: String?, at: Date) -> GnosisPayRoom.Sighting {
    GnosisPayRoom.Sighting(amount: amount, currency: code, at: at)
}

let gnosis = GnosisPayRoom.compose(spends: [
    spend(12.50, "EUR", at: day(-1)),
    spend(30.00, "EUR", at: day(-10)),
    spend(7.50,  "GBP", at: day(-3)),
    spend(nil,   "EUR", at: day(-5)),      // decimals never resolved
    spend(9.99,  nil,   at: day(-5)),      // no currency
    spend(20.00, "EUR", at: day(-40)),     // the window before
    spend(5.00,  "EUR", at: day(-200)),    // old enough to prove we were watching
], now: t0)
check("the window's spends are summed per currency",
      gnosis.lead?.code == "EUR" && abs((gnosis.lead?.total ?? 0) - 42.50) < 0.0001)
// EUR + GBP is an exchange rate this app does not have.
check("currencies are never summed into one figure", gnosis.currencies.count == 2)
check("the second currency keeps its own total",
      abs((gnosis.currencies.last?.total ?? 0) - 7.50) < 0.0001)
// A zero is a spend of nothing, which is a different and false claim. BOTH
// shapes land here: no amount, and an amount with no currency to put it in.
check("an unreadable amount is counted, never treated as zero", gnosis.unpriced == 2)
check("a missing amount alone is counted",
      GnosisPayRoom.compose(spends: [spend(nil, "EUR", at: day(-1))], now: t0).unpriced == 1)
check("a missing CURRENCY alone is counted too — it drops from every total",
      GnosisPayRoom.compose(spends: [spend(9.99, nil, at: day(-1))], now: t0).unpriced == 1)
check("the window's spend count excludes the unpriced", gnosis.lead?.spends == 2)
check("all-time counts every row the room holds", gnosis.allTime == 7)
check("the oldest spend is remembered", gnosis.oldest == day(-200))

print("")
print("Gnosis Pay — the comparison is refused rather than estimated")
check("the prior window is known when history reaches past it",
      GnosisPayRoom.knowsPriorWindow(oldest: day(-200), now: t0))
// A first sync backfills about six days. The prior window is then not quiet,
// it is unobserved — and "up 400%" against it would be a fabrication.
check("a young room knows nothing about the window before",
      GnosisPayRoom.knowsPriorWindow(oldest: day(-6), now: t0) == false)
check("a room with no spends at all knows nothing",
      GnosisPayRoom.knowsPriorWindow(oldest: nil, now: t0) == false)
check("the prior total is carried when it is knowable",
      abs((gnosis.lead?.prior ?? 0) - 20.00) < 0.0001)
let young = GnosisPayRoom.compose(spends: [spend(10, "EUR", at: day(-2))], now: t0)
check("a young room carries no prior at all", young.lead?.prior == nil)
check("and says so out loud rather than leaving a blank",
      GnosisPayRoom.note(young).contains("not watching long enough to compare"))

print("")
print("Gnosis Pay — the change")
func cur(_ total: Double, prior: Double?, spends: Int = 3) -> GnosisPayRoom.Currency {
    GnosisPayRoom.Currency(code: "EUR", total: total, spends: spends, prior: prior, newest: t0)
}
check("a rise is a fraction", abs((GnosisPayRoom.delta(cur(120, prior: 100)) ?? 0) - 0.2) < 0.0001)
check("a fall is negative", (GnosisPayRoom.delta(cur(80, prior: 100)) ?? 0) < 0)
// Coming back from nothing has no percentage, and printing +100% for it is an
// arithmetic accident.
check("a zero prior window does not divide", GnosisPayRoom.delta(cur(50, prior: 0)) == nil)
check("an unknown prior claims nothing", GnosisPayRoom.delta(cur(50, prior: nil)) == nil)
// Card spending is lumpy — one weekly shop lands differently in two windows.
check("a small move is noise and gets no word", GnosisPayRoom.deltaLabel(cur(105, prior: 100)) == nil)
check("a real rise is stated in words",
      GnosisPayRoom.deltaLabel(cur(130, prior: 100)) == "30% more than the 30 days before")
check("a real fall is stated in words",
      GnosisPayRoom.deltaLabel(cur(70, prior: 100)) == "30% less than the 30 days before")

print("")
print("Gnosis Pay — the history strip")
// This head OUTRANKS `FeedInsight.cardMonths`, the 12-month leaderboard the
// room drew before it. A head that showed less than the card it displaced would
// be a regression wearing a new feature, so the months come with it.
func monthsOf(_ n: Int, _ code: String = "EUR", each: Double = 10) -> [GnosisPayRoom.Sighting] {
    (0..<n).map { spend(each, code, at: cal.date(byAdding: .month, value: -$0, to: t0)!) }
}
let hist = GnosisPayRoom.compose(spends: monthsOf(5), now: t0)
check("a month per month of history", hist.months.count == 5)
// Oldest first, so the strip reads left to right as time.
check("the strip runs oldest to newest",
      hist.months.map(\.key) == hist.months.map(\.key).sorted())
check("each month carries its own total and count",
      hist.months.allSatisfy { $0.spends == 1 && abs($0.total - 10) < 0.0001 })
// A month key must survive a year boundary, which a bare month number does not.
let dec = cal.date(from: DateComponents(year: 2025, month: 12, day: 15))!
let jan = cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!
check("December sorts before the January after it",
      GnosisPayRoom.monthKey(dec)! < GnosisPayRoom.monthKey(jan)!)
check("a key round-trips to the month it names",
      GnosisPayRoom.monthKey(GnosisPayRoom.monthStart(key: GnosisPayRoom.monthKey(dec)!)!)
        == GnosisPayRoom.monthKey(dec))
// A one-column history is not a history — one lone bar reads as a level.
check("one month draws no strip", GnosisPayRoom.compose(spends: monthsOf(1), now: t0).months.isEmpty)
// Silent truncation: a dropped month looks exactly like a quiet one.
let long = GnosisPayRoom.compose(spends: monthsOf(20), now: t0)
check("the strip is capped", long.months.count == GnosisPayRoom.monthCap)
check("and the months it dropped are COUNTED, not silently truncated",
      long.monthsHidden == 20 - GnosisPayRoom.monthCap)
check("the cap keeps the NEWEST months",
      long.months.last?.key == GnosisPayRoom.monthKey(t0))
// The strip follows the currency the HEADLINE states, so one card is never
// about two different sorts of money.
let mixed = GnosisPayRoom.compose(spends:
    monthsOf(4, "EUR") + monthsOf(4, "GBP") + [spend(1, "EUR", at: day(-1))], now: t0)
check("the strip follows the lead currency", mixed.lead?.code == "EUR")
check("spends in another currency are counted, not folded in",
      mixed.monthsOtherCurrency == 4)
check("the caption names the currency it drew",
      (GnosisPayRoom.historyNote(mixed) ?? "").contains("EUR"))
check("and says what it left out",
      (GnosisPayRoom.historyNote(mixed) ?? "").contains("in other currencies"))
check("no strip, no caption",
      GnosisPayRoom.historyNote(GnosisPayRoom.compose(spends: monthsOf(1), now: t0)) == nil)
// Scaled against the biggest DRAWN month: scaling to one off the end of the
// strip would flatten every visible column against something nobody can see.
check("the tallest drawn month is full height", GnosisPayRoom.monthShare(total: 50, of: 50) == 1)
check("half is half", GnosisPayRoom.monthShare(total: 25, of: 50) == 0.5)
check("a zero peak can't divide by zero", GnosisPayRoom.monthShare(total: 5, of: 0) == 0)
check("a month abbreviates", GnosisPayRoom.monthLabel(dec, locale: us) == "Dec")

print("")
print("Gnosis Pay — ranking never compares magnitudes across currencies")
func c(_ code: String, spends: Int, total: Double, at: Date = t0) -> GnosisPayRoom.Currency {
    GnosisPayRoom.Currency(code: code, total: total, spends: spends, prior: nil, newest: at)
}
// 400 EUR against 380 GBP is the cross-currency sum this file refuses, wearing
// a sort instead of a plus.
check("more spends wins, even against a bigger total in another currency",
      GnosisPayRoom.ordered([c("GBP", spends: 2, total: 9000),
                             c("EUR", spends: 9, total: 10)]).first?.code == "EUR")
check("a tie breaks on recency",
      GnosisPayRoom.ordered([c("GBP", spends: 2, total: 1, at: day(-9)),
                             c("EUR", spends: 2, total: 1, at: day(-1))]).first?.code == "EUR")
check("a full tie breaks on code",
      GnosisPayRoom.ordered([c("USD", spends: 2, total: 1),
                             c("EUR", spends: 2, total: 1)]).first?.code == "EUR")
check("the bar is a share of the spend COUNT", GnosisPayRoom.share(spends: 3, of: 6) == 0.5)
check("a zero denominator can't divide by zero", GnosisPayRoom.share(spends: 3, of: 0) == 0)

print("")
print("Gnosis Pay — words")
check("money is rendered in its own currency",
      GnosisPayRoom.money(42.5, code: "GBP", locale: us) == "£42.50")
check("a zero-decimal currency is not forced to two",
      GnosisPayRoom.money(1200, code: "JPY", locale: us) == "¥1,200")
check("a single-currency headline states the money and the window",
      GnosisPayRoom.headline(young, locale: us) == "€10.00 on your card in 30 days")
check("several currencies are named as several, never added",
      GnosisPayRoom.headline(gnosis, locale: us).contains("plus another currency"))
// The honest reading a list of old rows never states.
let quiet = GnosisPayRoom.compose(spends: [spend(10, "EUR", at: day(-90))], now: t0)
check("a quiet window on a real room says so",
      GnosisPayRoom.headline(quiet) == "Nothing spent in the last 30 days")
check("and the room still draws rather than vanishing", !quiet.isEmpty)
check("an unused card is stated once the gap outruns the window",
      GnosisPayRoom.idleNote(newest: day(-90), now: t0) == "unused for 90 days")
// It must never contradict a headline that just reported spending in the
// window.
check("a card used inside the window is never called unused",
      GnosisPayRoom.idleNote(newest: day(-3), now: t0) == nil)
check("a room with no spends at all is no card", GnosisPayRoom.compose(spends: [], now: t0).isEmpty)
let gpFoot = GnosisPayRoom.footnote(gnosis, now: t0) ?? ""
check("unreadable spends are named — that is money missing from the total above",
      gpFoot.contains("2 spends have no readable amount"))

print("")
print("Railgun — reading a row")
check("a shield is read from its ref", RailgunRoom.direction(ref: "railgun:shield:0xabc:0") == .shield)
check("an unshield is read from its ref", RailgunRoom.direction(ref: "railgun:unshield:0xabc:0") == .unshield)
check("a ref this build doesn't know is nil, never guessed",
      RailgunRoom.direction(ref: "railgun:0xabc") == nil)
check("no ref at all is nil", RailgunRoom.direction(ref: nil) == nil)

func move(_ ref: String, token: String? = nil, amount: Double? = nil, at: Date = t0) -> RailgunRoom.Sighting {
    RailgunRoom.Sighting(ref: ref, token: token, amount: amount, at: at)
}

print("")
print("Railgun — composing")
let railgun = RailgunRoom.compose(moves: [
    move("railgun:shield:1:0", token: "ETH", amount: 1.0, at: day(-1)),
    move("railgun:shield:2:0", token: "ETH", amount: 2.0, at: day(-3)),
    move("railgun:unshield:3:0", token: "ETH", amount: 0.5, at: day(-5)),
    move("railgun:shield:4:0", token: "USDC", amount: 100, at: day(-2)),
    move("railgun:shield:5:0", at: day(-6)),                    // no token at all
    move("railgun:shield:6:0", token: "WBTC", at: day(-1)),     // token known, amount not
])
check("shields are counted", railgun.shields == 5)
check("unshields are counted apart", railgun.unshields == 1)
// Counted as a shield AND as unplaced: the move is real, the token is not known.
check("a move with no readable token is counted, not bucketed", railgun.unplaced == 1)
check("no 'Unknown' token was invented", railgun.tokens.allSatisfy { $0.symbol != "Unknown" })
check("three real tokens", railgun.tokens.count == 3)
check("the busiest token leads", railgun.lead?.symbol == "ETH")
check("a token counts both directions", railgun.lead?.moves == 3)
check("the newest move dates the room, regardless of token", railgun.newest == day(-1))

print("")
print("Railgun — token amounts")
let eth = railgun.tokens.first { $0.symbol == "ETH" }!
check("a token's shielded amount sums only its shields", eth.shieldedAmount == 3.0)
check("a token's unshielded amount sums only its unshields", eth.unshieldedAmount == 0.5)
let wbtc = railgun.tokens.first { $0.symbol == "WBTC" }!
check("a token with an unknown amount states no total at all, never a partial one",
      wbtc.shieldedAmount == nil)

print("")
print("Railgun — ranking is total")
func rgToken(_ s: String, shields: Int, unshields: Int = 0, at: Date = t0) -> RailgunRoom.Token {
    RailgunRoom.Token(symbol: s, shields: shields, unshields: unshields,
                      shieldedAmount: nil, unshieldedAmount: nil, newest: at)
}
check("more moves wins",
      RailgunRoom.ordered([rgToken("A", shields: 1), rgToken("B", shields: 9)]).first?.symbol == "B")
check("more moves wins even against a fresher runner-up",
      RailgunRoom.ordered([rgToken("A", shields: 9, at: day(-9)),
                           rgToken("B", shields: 1, at: day(-1))]).first?.symbol == "A")
check("a tie on moves breaks on recency",
      RailgunRoom.ordered([rgToken("A", shields: 2, at: day(-9)),
                           rgToken("B", shields: 2, at: day(-1))]).first?.symbol == "B")
check("a full tie breaks on symbol",
      RailgunRoom.ordered([rgToken("B", shields: 2, at: t0),
                           rgToken("A", shields: 2, at: t0)]).first?.symbol == "A")

print("")
print("Railgun — words")
check("the headline names the leading token", RailgunRoom.headline(railgun).contains("ETH"))
check("a card with no moves at all says so",
      RailgunRoom.headline(RailgunRoom.compose(moves: [])) == "Nothing has moved yet")
check("both directions are named in the note",
      RailgunRoom.note(railgun).contains("shielded") && RailgunRoom.note(railgun).contains("received"))
let rgFoot = RailgunRoom.footnote(railgun, drawn: 3, now: t0) ?? ""
check("unplaced moves are named — a move missing from every token bucket above",
      rgFoot.contains("1 move has no readable token"))
check("a room with no moves at all is no card", RailgunRoom.compose(moves: []).isEmpty)
check("share is a fraction of the busiest token's moves", RailgunRoom.share(moves: 3, of: 6) == 0.5)
check("a zero denominator can't divide by zero", RailgunRoom.share(moves: 3, of: 0) == 0)

print("")
print("Safe — ranking is your-turn first, then ready, then oldest first")
func safeEntry(_ ref: String, have: Int = 1, required: Int = 3, yourTurn: Bool = false,
               submittedAt: Date? = nil, nonce: Int? = nil,
               safe: String = "0xSafe", description: String = "a transfer") -> SafeRoom.Entry {
    SafeRoom.Entry(ref: ref, safeAddress: safe, have: have, required: required,
                   yourTurn: yourTurn, submittedAt: submittedAt, descriptionText: description,
                   nonce: nonce)
}
check("your turn always outranks waiting on others, even when it arrived later",
      SafeRoom.ordered([safeEntry("a", yourTurn: false, submittedAt: day(-9)),
                        safeEntry("b", yourTurn: true, submittedAt: day(-1))]).first?.ref == "b")
check("within the same group, the longest-waiting entry leads",
      SafeRoom.ordered([safeEntry("a", submittedAt: day(-1)),
                        safeEntry("b", submittedAt: day(-9))]).first?.ref == "b")
check("a nil submittedAt sorts as if it arrived at the dawn of time — never hides a real wait behind an unknown one",
      SafeRoom.ordered([safeEntry("a", submittedAt: day(-1)),
                        safeEntry("b", submittedAt: nil)]).first?.ref == "b")
check("a full tie breaks on ref, for a total order that never reshuffles on identical data",
      SafeRoom.ordered([safeEntry("b"), safeEntry("a")]).first?.ref == "a")

print("")
print("Safe — fully signed is not pending (2026-08-17)")
// THE FALSE ALARM THIS FIXES. `yourTurn` is `!hasSigned(you)` alone, so a
// 2-of-3 whose other two owners both signed said "your signature is needed",
// ranked it first, and fired a lock-screen alarm — for a transaction that
// needs nothing from you.
check("a met threshold is ready, not pending",
      safeEntry("a", have: 3, required: 3).isReady)
check("an unread threshold is never 'ready' — 0/0 is no evidence at all",
      !safeEntry("a", have: 0, required: 0).isReady)
check("more signatures than required is still ready, never a fourth state",
      safeEntry("a", have: 4, required: 3).isReady)
check("your signature can't be needed on something already fully signed without you",
      !safeEntry("a", have: 2, required: 2, yourTurn: true).awaitsYou)
check("your signature IS needed when the threshold is genuinely short",
      safeEntry("a", have: 1, required: 2, yourTurn: true).awaitsYou)
// The ready candidate is given the STRONGER raw position on purpose — it is
// really yourTurn and really newer — so this can only pass because `isReady`
// is being honoured, not because raw wait already ordered them.
let safeReadyRank = SafeRoom.ordered([
    safeEntry("ready", have: 3, required: 3, yourTurn: true, submittedAt: day(-1)),
    safeEntry("short", have: 1, required: 3, yourTurn: true, submittedAt: day(-9)),
])
check("a genuinely-short signature outranks a fully-signed one — only you can add yours",
      safeReadyRank.first?.ref == "short")
let safeReadyOverWaiting = SafeRoom.ordered([
    safeEntry("waiting", have: 1, required: 3, yourTurn: false, submittedAt: day(-9)),
    safeEntry("ready", have: 3, required: 3, yourTurn: false, submittedAt: day(-1)),
])
check("fully-signed outranks still-collecting even when it arrived later",
      safeReadyOverWaiting.first?.ref == "ready")
let safeRoomReady = SafeRoom.compose(
    entries: [safeEntry("a", have: 3, required: 3, submittedAt: day(-2))], safeCount: 1)
check("a fully-signed queue says 'ready to execute', never 'waiting on others'",
      SafeRoom.headline(safeRoomReady).contains("ready to execute")
      && !SafeRoom.headline(safeRoomReady).contains("waiting on others"))
check("a fully-signed transaction is not counted as a pending signature",
      safeRoomReady.readyCount == 1 && safeRoomReady.awaitsYouCount == 0)
let safeRoomBoth = SafeRoom.compose(
    entries: [safeEntry("a", have: 1, required: 3, yourTurn: true, submittedAt: day(-2)),
              safeEntry("b", have: 3, required: 3, submittedAt: day(-2))], safeCount: 1)
check("the ready count the headline couldn't carry lands in the state note",
      SafeRoom.stateNote(safeRoomBoth)?.contains("ready to execute") == true)
check("the state note never restates a headline that already led with ready",
      SafeRoom.stateNote(safeRoomReady) == nil)

print("")
print("Safe — rival transactions at one nonce (2026-08-17)")
// A Safe executes exactly ONE transaction per nonce, so a signature spent on
// the loser is spent for nothing (§238). Rivals share a Safe AND a nonce.
// The unrelated entry sits BETWEEN the pair by age on purpose. The first
// version of this fixture dated them -2/-1/-3, which plain age-sorting
// already returns as c,a,b — so the pair was adjacent by accident and the
// regroup mutation survived while the check read green (the harness trap this
// file's siblings have paid for twice).
let safeRivals = [safeEntry("a", submittedAt: day(-9), nonce: 7),
                  safeEntry("b", submittedAt: day(-1), nonce: 7),
                  safeEntry("c", submittedAt: day(-5), nonce: 8)]
let safeRivalRoom = SafeRoom.compose(entries: safeRivals, safeCount: 1)
check("two transactions at one nonce are contested", safeRivalRoom.contestedCount == 2)
check("a lone transaction at its own nonce is not contested",
      !safeRivalRoom.isContested(safeEntry("c", submittedAt: day(-5), nonce: 8)))
check("an unknown nonce is never called a rival — we can't prove a collision we can't see",
      SafeRoom.contestedKeys(in: [safeEntry("a", nonce: nil), safeEntry("b", nonce: nil)]).isEmpty)
check("the same nonce on two DIFFERENT Safes is not a collision",
      SafeRoom.contestedKeys(in: [safeEntry("a", nonce: 7, safe: "0xOne"),
                                  safeEntry("b", nonce: 7, safe: "0xTwo")]).isEmpty)
// The regroup is the point: ranked strictly by wait this is a, c, b — the
// unrelated entry wedged between the rivals — and a pair that reads as two
// unrelated rings invites exactly the wasted signature this warning exists to
// prevent.
check("rivals are drawn adjacent, even when an unrelated entry sorts between them",
      Array(safeRivalRoom.entries.map { $0.ref }.prefix(3)) == ["a", "b", "c"])
check("the regroup keeps every entry exactly once",
      Set(safeRivalRoom.entries.map { $0.ref }).count == 3)
check("a rival pair is said out loud, and says only one of them can execute",
      SafeRoom.stateNote(safeRivalRoom)?.contains("only one of them can execute") == true)
let safeTwoGroups = SafeRoom.compose(
    entries: [safeEntry("a", nonce: 7), safeEntry("b", nonce: 7),
              safeEntry("c", nonce: 9), safeEntry("d", nonce: 9)], safeCount: 1)
check("two contested positions are counted as positions, not folded into one",
      SafeRoom.stateNote(safeTwoGroups)?.contains("2 queue positions") == true)
check("a rival warning outranks the ready count in the one note slot",
      SafeRoom.stateNote(SafeRoom.compose(
        entries: [safeEntry("a", have: 1, required: 3, yourTurn: true, nonce: 7),
                  safeEntry("b", have: 1, required: 3, nonce: 7),
                  safeEntry("c", have: 3, required: 3)],
        safeCount: 1))?.contains("only one of them can execute") == true)

print("")
print("Safe — words")
let safeRoomYourTurn = SafeRoom.compose(
    entries: [safeEntry("a", have: 2, required: 3, yourTurn: true, submittedAt: day(-2))],
    safeCount: 1)
check("your-turn count leads the headline over a bare pending count",
      SafeRoom.headline(safeRoomYourTurn).contains("Your signature is needed"))
let safeRoomWaiting = SafeRoom.compose(
    entries: [safeEntry("a", have: 1, required: 3, yourTurn: false, submittedAt: day(-2))],
    safeCount: 1)
check("nobody's turn but something is pending — 'waiting on others', not the your-turn wording",
      SafeRoom.headline(safeRoomWaiting).contains("waiting on others"))
let safeRoomQuiet = SafeRoom.compose(entries: [], safeCount: 2)
check("a quiet room with more than one Safe pluralises 'Safes'",
      SafeRoom.headline(safeRoomQuiet).contains("Safes"))
let safeRoomModule = SafeRoom.compose(entries: [], safeCount: 1,
                                      moduleSafes: [.init(label: "treasury.eth", count: 1)])
check("a module warning is stated even with nothing pending — the highest-stakes fact this bridge can carry",
      SafeRoom.note(safeRoomModule)?.contains("without a signature") == true)
check("with only one Safe watched there is nothing to disambiguate, so the name would be noise",
      SafeRoom.note(safeRoomModule)?.contains("treasury.eth") == false)
// Naming it is the whole point once there is more than one: "1 module can move
// funds without a signature" says a drain is possible and not WHERE.
let safeRoomModuleNamed = SafeRoom.compose(entries: [], safeCount: 3,
                                           moduleSafes: [.init(label: "treasury.eth", count: 1)])
check("with several Safes watched the module warning names the one it means",
      SafeRoom.note(safeRoomModuleNamed)?.contains("treasury.eth") == true)
let safeRoomModulesSpread = SafeRoom.compose(
    entries: [], safeCount: 3,
    moduleSafes: [.init(label: "treasury.eth", count: 2), .init(label: "ops.eth", count: 1)])
check("modules across several Safes count both the modules and the Safes",
      SafeRoom.note(safeRoomModulesSpread)?.contains("3 modules across 2 Safes") == true)
check("a Safe carrying no modules is not counted as a carrier",
      SafeRoom.note(SafeRoom.compose(entries: [], safeCount: 2,
                                     moduleSafes: [.init(label: "a.eth", count: 0)])) == nil)
check("no module means no note at all — a second sentence that says nothing doesn't get to exist",
      SafeRoom.note(safeRoomWaiting) == nil)
check("a Safe never detected at all is no card", SafeRoom.compose(entries: [], safeCount: 0).isEmpty)
check("today reads as 'today', not '0 days'",
      SafeRoom.waitLabel(safeEntry("a", submittedAt: t0), now: t0) == "today")
check("a nil submittedAt reads as 'waiting', never a fabricated duration",
      SafeRoom.waitLabel(safeEntry("a", submittedAt: nil), now: t0) == "waiting")
let safeFoot = SafeRoom.footnote(SafeRoom.compose(entries: [safeEntry("a"), safeEntry("b"), safeEntry("c"), safeEntry("d")],
                                                  safeCount: 1), drawn: 3)
check("entries beyond the row cap are counted in the footnote, never silently dropped",
      safeFoot == "1 more pending")

print("")
print("Safe — the stuck-signature line the brief and the widget read")
// A your-turn signature notifies ONCE at landing and §306's 36-hour news
// window forbids a second buzz forever after, so this is the only surface that
// can ever re-raise a request nobody answered.
let safeStuck = SafeRoom.compose(
    entries: [safeEntry("a", have: 1, required: 3, yourTurn: true, submittedAt: day(-6),
                        description: "a transfer of 1,500 USDC to payroll.eth")],
    safeCount: 1)
check("a signature waiting past the floor is measured in whole days",
      SafeRoom.stuckDays(safeStuck, now: t0) == 6)
check("the line names what is actually being asked of you",
      SafeRoom.stuckLine(safeStuck, now: t0)?.contains("payroll.eth") == true)
check("a request from this morning is not 'stuck' — that would just repeat yesterday's notification",
      SafeRoom.stuckLine(SafeRoom.compose(
        entries: [safeEntry("a", have: 1, required: 3, yourTurn: true, submittedAt: day(-1))],
        safeCount: 1), now: t0) == nil)
check("nothing awaiting you means nothing stuck, however old the queue is",
      SafeRoom.stuckDays(SafeRoom.compose(
        entries: [safeEntry("a", have: 1, required: 3, yourTurn: false, submittedAt: day(-40))],
        safeCount: 1), now: t0) == nil)

print("")
if failures > 0 { print("\(failures) failed"); exit(1) }
print("all assertions passed")
SWIFT

echo "wallet-rooms-selftest: compiling the five heads WHOLE and unmodified…"
swiftc -O -o "$TMP/run" "$PEER" "$POOLS" "$GNOSIS" "$RAILGUN" "$SAFE" "$TMP/main.swift" \
  || { echo "✗ the shipped room heads do not compile Foundation-only — something reached Thing/SwiftUI"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Every mutation below is a silent wrong answer that renders perfectly. A
# mutation that survives means nothing here was testing that line.
echo ""
echo "mutations (each must be caught):"

mutate() {
  local name="$1" which="$2" frm="$3" to="$4"
  cp "$PEER" "$TMP/PeerRoom.swift"
  cp "$POOLS" "$TMP/PrivacyPoolsRoom.swift"
  cp "$GNOSIS" "$TMP/GnosisPayRoom.swift"
  cp "$RAILGUN" "$TMP/RailgunRoom.swift"
  cp "$SAFE" "$TMP/SafeRoom.swift"
  local a="$TMP/PeerRoom.swift" b="$TMP/PrivacyPoolsRoom.swift" c="$TMP/GnosisPayRoom.swift" d="$TMP/RailgunRoom.swift" e="$TMP/SafeRoom.swift"
  local target
  case "$which" in
    peer)    target="$a" ;;
    pools)   target="$b" ;;
    gnosis)  target="$c" ;;
    railgun) target="$d" ;;
    safe)    target="$e" ;;
  esac
  FRM="$frm" TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if frm not in src:
    sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$a" "$b" "$c" "$d" "$e" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# THE Peer bug: every ref begins `peer:`, so testing the bare prefix first folds
# the whole sell side into the buy side. A room reporting that you only ever
# buy, on an account that mostly sells, renders perfectly.
mutate "the bare peer: prefix is tested before peer:sell:" peer \
  '        ("peer:sell:", .sold),
        ("peer:expired:", .fellThrough),
        ("peer:", .bought),' \
  '        ("peer:", .bought),
        ("peer:sell:", .sold),
        ("peer:expired:", .fellThrough),'
# An expired row is stamped when we LOOKED. Letting it date the room makes a
# dormant account read as active this morning.
mutate "a fall-through is allowed to date the room" peer \
  '            guard kind.settled else { fellThrough += 1; continue }
            // Over SETTLED fills only — an expired row'"'"'s date is when we
            // looked, not when anything happened.
            if newest == nil || sighting.at > newest! { newest = sighting.at }' \
  '            if newest == nil || sighting.at > newest! { newest = sighting.at }
            guard kind.settled else { fellThrough += 1; continue }'
# A rail nobody named, invented and then ranked beside the real ones. Written
# to COMPILE rather than to trip the type-checker: a mutation rejected at build
# proves the edit was malformed, not that anything was testing the behaviour.
mutate "an unplaced fill is bucketed under an invented rail" peer \
  '            let name = sighting.rail?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { unplaced += 1; continue }' \
  '            let name = sighting.rail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"'
# Without the last tiebreak the order comes off a dictionary and the card
# reshuffles between opens over identical data.
mutate "the rail order stops being total" peer \
  'return a.name < b.name' \
  'return a.name > b.name'
# Caught in this pass's own review: `unplaced` is a subset of `fills`, so adding
# them lets ONE unplaced fill clear the minimum and draw a card over a single
# row — the exact thing `minimumFills` exists to prevent.
mutate "unplaced fills are added to a total that already contains them" peer \
  'var isEmpty: Bool { fills < PeerRoom.minimumFills }' \
  'var isEmpty: Bool { fills + unplaced < PeerRoom.minimumFills }'
# A NaN-width capsule, which SwiftUI draws as nothing.
mutate "a zero denominator divides anyway" peer \
  'guard top > 0 else { return 0 }
        return min(max(Double(fills) / Double(top), 0), 1)' \
  'return min(max(Double(fills) / Double(top), 0), 1)'

# A claim about the screener made with no evidence — a deposit that cleared two
# months ago reported as still waiting.
mutate "an untagged deposit defaults to pending" pools \
  '    static func state(tags: [String]) -> State? {
        for tag in tags {
            if let found = State(rawValue: tag) { return found }
        }
        return nil
    }' \
  '    static func state(tags: [String]) -> State? {
        for tag in tags {
            if let found = State(rawValue: tag) { return found }
        }
        return .pending
    }'
# A cleared deposit counted twice — once as itself, once as its own alert.
mutate "an alert is counted as a second deposit" pools \
  'if ref.hasPrefix(statusPrefix) || ref.hasPrefix(poiPrefix) { return .alert }' \
  'if ref.hasPrefix(statusPrefix) || ref.hasPrefix(poiPrefix) { return .deposit(state(tags: tags)) }'
# One deposit stuck on proof, buried under forty that cleared — exactly on the
# accounts that use this seat most.
mutate "proof-required stops outranking everything" pools \
  'case .needsProof: return 3' \
  'case .needsProof: return 0'
# Partial knowledge drawn as complete: the bar fills, and the deposits nobody
# could place vanish out of the denominator.
mutate "untagged deposits drop out of the split's denominator" pools \
  'var deposits: Int { segments.reduce(0) { $0 + $1.count } + untagged }' \
  'var deposits: Int { segments.reduce(0) { $0 + $1.count } }'
# The mirror the whole card rests on. A raw value that stops matching the tag
# `retag` writes reads every deposit as untagged.
mutate "a state's raw value stops mirroring the bridge's tag" pools \
  'case needsProof   = "Needs proof"' \
  'case needsProof   = "NeedsProof"'
# A resolution dated before its own deposit is not evidence of anything, and
# using it anyway would let a clock oddity invent a negative — or worse, a
# fabricated positive — review time.
mutate "a review-time pair no longer checks the resolution came after the deposit" pools \
  'guard let resolved = resolvedAt[label], resolved >= landed else { return nil }' \
  'guard let resolved = resolvedAt[label] else { return nil }'

# The cross-currency sum this file exists to refuse.
mutate "every currency lands in one bucket" gnosis \
  'var bucket = buckets[code] ?? (total: 0, spends: 0, newest: sighting.at)' \
  'let code = "ALL"; var bucket = buckets[code] ?? (total: 0, spends: 0, newest: sighting.at)'
# "Up 400%" against a window the room was never watching.
mutate "a comparison is claimed against an unobserved window" gnosis \
  'guard let oldest else { return false }
        return oldest <= windowStart(now, back: 2, calendar: calendar)' \
  'return true'
# Coming back from nothing has no percentage.
mutate "a zero prior window divides anyway" gnosis \
  'guard let prior = currency.prior, prior > 0 else { return nil }' \
  'guard let prior = currency.prior else { return nil }'
# A zero is a spend of nothing, which is a different and false claim. Again
# written to compile, so the catch is behavioural.
mutate "an unreadable amount is folded into the total as zero" gnosis \
  '            let code = sighting.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let amount = sighting.amount, let code, !code.isEmpty else {
                if sighting.at >= start { unpriced += 1 }
                continue
            }' \
  '            let code = sighting.currency?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "EUR"
            let amount = sighting.amount ?? 0'
# A dropped month looks exactly like a quiet one, which is the failure the
# import drop counters exist to prevent, one room over.
mutate "the strip truncates its history silently" gnosis \
  'return (months, keys.count - drawn.count, other)' \
  'return (months, 0, other)'
# The oldest months kept instead of the newest — a "history" that stops a year
# ago and renders perfectly.
mutate "the strip keeps the oldest months instead of the newest" gnosis \
  'let drawn = Array(keys.suffix(monthCap))' \
  'let drawn = Array(keys.prefix(monthCap))'
# A month key that resets each year sorts December after the January following
# it, so the strip runs backwards across every year boundary.
mutate "a month key stops surviving the year boundary" gnosis \
  'return year * 12 + (month - 1)' \
  'return month - 1'
# One card, two sorts of money: the strip drawn in a currency the headline is
# not talking about.
mutate "spends in another currency are folded into the strip" gnosis \
  'for (otherCode, otherCells) in monthly where otherCode != code {' \
  'for (otherCode, otherCells) in monthly where otherCode == "\u{0}" && otherCode != code {'
# Ranking by amount compares 400 EUR against 380 GBP as if they were on one
# scale — the refused sum, wearing a sort instead of a plus.
mutate "currencies are ranked by amount instead of count" gnosis \
  'if a.spends != b.spends { return a.spends > b.spends }' \
  'if a.total != b.total { return a.total > b.total }'

# A partial sum presented as complete — the failure `PeerRoom.Token` and
# `RailgunRoom.Token` both exist to refuse. One shield with an unreadable
# amount would otherwise silently understate the token's real total rather
# than say nothing.
mutate "a token's shielded amount is shown even when one shield's amount is unknown" railgun \
  'shieldedAmount: (b.shields > 0 && b.shieldedKnown) ? b.shieldedAmount : nil,' \
  'shieldedAmount: (b.shields > 0) ? b.shieldedAmount : nil,'
# Reordering the rank so recency beats volume — the same class of bug
# `PeerRoom.ordered` and `GnosisPayRoom.ordered` are both mutation-tested
# against: a token with nine moves losing to one with a single, fresher move.
mutate "tokens are ranked by recency before move count" railgun \
  'if a.moves != b.moves { return a.moves > b.moves }
            if a.newest != b.newest { return a.newest > b.newest }' \
  'if a.newest != b.newest { return a.newest > b.newest }
            if a.moves != b.moves { return a.moves > b.moves }'

# A signature request only YOU can unblock loses its priority — the exact bug
# that would make the room's own reason for existing (surfacing what's
# waiting on you) silently stop working while every other reading stays
# correct.
mutate "your turn no longer outranks waiting on others" safe \
  'if a.awaitsYou != b.awaitsYou { return a.awaitsYou && !b.awaitsYou }' \
  'if false { return a.awaitsYou && !b.awaitsYou }'
# The longest-waiting entry within a group loses its lead — a transaction
# that has sat for nine days ranks behind one from yesterday, which is
# exactly backwards for a card whose whole point is surfacing what has been
# ignored longest.
mutate "the oldest pending entry no longer leads within its group" safe \
  'if da != db { return da < db }' \
  'if da != db { return da > db }'

# --- 2026-08-17: the three states, and the rivals ---------------------------

# THE FALSE ALARM. `yourTurn` is `!hasSigned(you)` with no check that the
# threshold isn't already met WITHOUT you, so a 2-of-3 whose other two owners
# both signed claimed your signature was needed, ranked it first, and — since
# §349's (7) — fired a lock-screen alarm for a transaction that needs nothing
# from you. Dropping the `isReady` term restores exactly that bug.
mutate "your signature is 'needed' on a transaction already fully signed without you" safe \
  'var awaitsYou: Bool { yourTurn && !isReady }' \
  'var awaitsYou: Bool { yourTurn }'
# A transaction whose `confirmationsRequired` didn't parse arrives as 0/0.
# Reading that as a met threshold reports something ready to execute on no
# evidence at all — and it renders as a full green ring.
mutate "an unread threshold counts as fully signed" safe \
  'var isReady: Bool { required > 0 && have >= required }' \
  'var isReady: Bool { have >= required }'
# Fully-signed folded back into the pending count: "3 of 3 signatures pending —
# waiting on others", which is false twice in one line (nobody's signature is
# pending, and it isn't the others holding it up).
mutate "fully-signed transactions are counted as pending signatures again" safe \
  'if room.readyCount > 0 {' \
  'if false {'
# Ready loses its rank and sorts purely by age, so the one transaction anybody
# can finish right now falls below one still collecting.
mutate "a fully-signed transaction no longer outranks one still collecting" safe \
  'if a.isReady != b.isReady { return a.isReady && !b.isReady }' \
  'if false { return a.isReady && !b.isReady }'
# A nonce we could not read becomes a rival of every other unreadable one —
# a collision warning asserted on the absence of evidence, on the card whose
# whole job is telling you which signature not to waste.
mutate "an unknown nonce is treated as a queue position" safe \
  'nonce.map { "\(safeAddress.lowercased())#\($0)" }' \
  '"\(safeAddress.lowercased())#\(nonce ?? -1)"'
# The same nonce on two DIFFERENT Safes reads as a collision. They are separate
# queues; only the pair (Safe, nonce) is a position.
mutate "a queue position stops being scoped to its own Safe" safe \
  '"\(safeAddress.lowercased())#\($0)"' \
  '"#\($0)"'
# Rivals stop being pulled adjacent. The sentence still says two of these
# collide and nothing on screen says WHICH two — worse than silence, since it
# invites the wasted signature.
mutate "rivals are no longer drawn beside each other" safe \
  'guard !contested.isEmpty else { return sorted }' \
  'return sorted; guard !contested.isEmpty else { return sorted }'
# The rival warning yields the note slot to the ready count — losing the one
# fact nothing else in this app surfaces, in favour of one the rings already
# show.
mutate "the ready count outranks a nonce collision in the one note slot" safe \
  'if room.contestedCount > 1 {' \
  'if false {'
# The module warning stops naming its Safe once several are watched, so a
# person told their funds can move without a signature is not told where.
mutate "the module warning stops naming which Safe it means" safe \
  'guard room.safeCount > 1, let only = carriers.first else {' \
  'guard false, let only = carriers.first else {'
# A Safe with zero modules counts as a carrier, so a room with no module risk
# at all grows an alarm sentence about nothing.
mutate "a Safe carrying no modules is counted as a carrier" safe \
  'let carriers = room.moduleSafes.filter { $0.count > 0 }' \
  'let carriers = room.moduleSafes'
# The stuck floor disappears, so the brief repeats yesterday's notification as
# today's headline, every day, forever.
mutate "a signature asked for this morning is already 'stuck'" safe \
  'guard let days = stuckDays(room, now: now), days >= stuckFloor,' \
  'guard let days = stuckDays(room, now: now), days >= 0,'
# The brief's lede reports a fully-signed transaction as a signature waiting on
# you — the false alarm again, one surface over.
mutate "a fully-signed transaction is reported as a stuck signature" safe \
  'let dates = room.entries.filter(\.awaitsYou).compactMap(\.submittedAt)' \
  'let dates = room.entries.filter(\.yourTurn).compactMap(\.submittedAt)'
echo ""
echo "wallet-rooms-selftest: OK — assertions pass and every mutation is caught."
