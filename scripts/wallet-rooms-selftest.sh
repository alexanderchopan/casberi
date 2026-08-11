#!/bin/zsh
# Casberi wallet-room self-test — the SHIPPED pure judgement behind the three
# WALLET-RIDING feed-room heads (prd §348, 2026-08-10):
#
#   Casberi/Casberi/Model/PeerRoom.swift
#   Casberi/Casberi/Model/PrivacyPoolsRoom.swift
#   Casberi/Casberi/Model/GnosisPayRoom.swift
#
# All three are Foundation-only BY DESIGN, so all three are compiled WHOLE AND
# UNMODIFIED rather than extracted — the strongest form of "the harness ran the
# shipped logic". Everything that touches `Thing` lives in the
# `…RoomSource.swift` half, which no harness can compile and which contains no
# judgement to test.
#
# WHY A HARNESS AND NOT A LIVE CHECK. These three seats ride the WATCHED
# WALLETS: there is no key to mint, no account to open, and nothing on this host
# can make a Peer fill settle, a 0xBow screener rule, or a Gnosis Pay card get
# swiped. A room's numbers can only ever be checked by somebody who already has
# the history — and every failure mode here is a SILENT WRONG ANSWER that
# renders perfectly:
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
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PEER="Casberi/Casberi/Model/PeerRoom.swift"
POOLS="Casberi/Casberi/Model/PrivacyPoolsRoom.swift"
GNOSIS="Casberi/Casberi/Model/GnosisPayRoom.swift"
for f in "$PEER" "$POOLS" "$GNOSIS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

SRC_PEER="Casberi/Casberi/Model/PeerRoomSource.swift"
SRC_POOLS="Casberi/Casberi/Model/PrivacyPoolsRoomSource.swift"
SRC_GNOSIS="Casberi/Casberi/Model/GnosisPayRoomSource.swift"
BR_PEER="Casberi/Casberi/Model/PeerBridge.swift"
BR_POOLS="Casberi/Casberi/Model/PrivacyPoolsBridge.swift"
BR_GNOSIS="Casberi/Casberi/Model/GnosisPayBridge.swift"
CARD_PEER="Casberi/Casberi/Screens/PeerRoomCard.swift"
CARD_POOLS="Casberi/Casberi/Screens/PrivacyPoolsRoomCard.swift"
CARD_GNOSIS="Casberi/Casberi/Screens/GnosisPayRoomCard.swift"
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

# Corollary 4 — filtered live at the boundary, before any stored property is
# read. The caller hands these a debounced snapshot and the foreground sweep
# deletes rows while it is held.
for f in "$SRC_PEER" "$SRC_POOLS" "$SRC_GNOSIS"; do
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
grep -q 'case PeerRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Peer room"; exit 1; }
grep -q 'case PrivacyPoolsRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Privacy Pools room"; exit 1; }
grep -q 'case GnosisPayRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Gnosis Pay room"; exit 1; }

# The cards draw through the SHIPPED arithmetic and honour the row caps, so a
# card cannot quietly re-rank or over-draw what the room composed.
grep -q 'room.rails.prefix(PeerRoomSource.rowCap)' "$CARD_PEER" \
  || { echo "✗ the Peer card no longer honours the rail cap — the footnote would count rows that are drawn anyway"; exit 1; }
grep -q 'room.currencies.prefix(GnosisPayRoomSource.rowCap)' "$CARD_GNOSIS" \
  || { echo "✗ the Gnosis Pay card no longer honours the currency cap"; exit 1; }
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
# Each head gets its own probe, because for these three seats an empty room is
# usually the HEALTHY answer and only one or two causes per room are bugs.
for key in peerRoomProbe privacyPoolsRoomProbe gnosisPayRoomProbe; do
  grep -q "Hook(key: \"$key\")" "$PROBES" \
    || { echo "✗ -$key is gone — an empty head's several causes would be indistinguishable"; exit 1; }
done

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
check("and the headline says so", PrivacyPoolsRoom.headline(lopsided) == "A deposit needs your proof")

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
if failures > 0 { print("\(failures) failed"); exit(1) }
print("all assertions passed")
SWIFT

echo "wallet-rooms-selftest: compiling the three heads WHOLE and unmodified…"
swiftc -O -o "$TMP/run" "$PEER" "$POOLS" "$GNOSIS" "$TMP/main.swift" \
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
  local a="$TMP/PeerRoom.swift" b="$TMP/PrivacyPoolsRoom.swift" c="$TMP/GnosisPayRoom.swift"
  local target
  case "$which" in
    peer)   target="$a" ;;
    pools)  target="$b" ;;
    gnosis) target="$c" ;;
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
  if ! swiftc -O -o "$TMP/mut" "$a" "$b" "$c" "$TMP/main.swift" 2>/dev/null; then
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

echo ""
echo "wallet-rooms-selftest: OK — assertions pass and every mutation is caught."
