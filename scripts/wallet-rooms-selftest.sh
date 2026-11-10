#!/bin/zsh
# Casberi wallet-room self-test — the SHIPPED pure judgement behind the
# wallet-riding seats (prd §349, 2026-08-10):
#
#   Casberi/Casberi/Model/PeerRoom.swift          the Peer head
#   Casberi/Casberi/Model/CardSpendRoom.swift     the onchain cards' head
#   Casberi/Casberi/Model/PrivacyPoolsRoom.swift  Privacy Pools' vocabulary
#   Casberi/Casberi/Model/SafeRoom.swift          the Safe queue's reading
#
# prd §1738 made Safe, Privacy Pools and Railgun no pick in the Wallet's menu,
# so no box draws their heads: the Railgun head (`RailgunRoom`, its source and
# card), the Privacy Pools head (its composition, card, source and cover
# store) and the Safe card are DELETED, and this file's sections, guards and
# mutations for them went with them. What is left of those two files is what
# still ships: the refs and tags the Privacy Pools bridge, Needs you and the
# demo share, and the Safe queue's rules that `SafeBridge`'s rows, `SafeAsk`
# and `-safeRoomProbe` read. The last drift guards below fail if a deleted
# head comes back.
#
# All four are Foundation-only BY DESIGN, so all four are compiled WHOLE AND
# UNMODIFIED rather than extracted — the strongest form of "the harness ran the
# shipped logic". Everything that touches `Thing`/`SafeBridge` lives in the
# `…RoomSource.swift` half, which no harness can compile and which contains no
# judgement to test.
#
# WHY A HARNESS AND NOT A LIVE CHECK. These four seats ride the WATCHED
# WALLETS: there is no key to mint, no account to open, and nothing on this host
# can make a Peer fill settle, a 0xBow screener rule, or an onchain card get
# swiped. A room's numbers can only ever be checked by
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
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
# Absolute, captured BEFORE the cd: the mutation fan-out re-invokes this script
# and `$0` is relative to the caller's cwd.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.."

# ── the mutation child (PERF, 2026-09-05) ────────────────────────────────────
# One mutation, in its own scratch directory so a concurrent sibling cannot see
# it. Sits at the VERY TOP, above every line of setup, because the child must
# not re-run the parent's assertion build: 68 mutations x a compile of EIGHT
# files is exactly the cost this block removes, and paying it again per child
# would make the fan-out slower than the loop it replaces.
#
# It prints ONE line the parent classifies and never exits the whole run — a
# second broken mutation must not cost another full pass to discover
# (`verify.sh`'s 2026-08-19 lesson: report ALL failures, not the first).
if [[ "${1:-}" == "--mutate" ]]; then
  SPOOL="$2"; MID="$3"
  MLABEL="$(cat "$SPOOL/mut/$MID.label")"
  MFILE="$(cat "$SPOOL/mut/$MID.file")"
  MW="$(mktemp -d)"
  trap 'rm -rf "$MW"' EXIT
  cp "$SPOOL"/base/*.swift "$MW/"
  if ! FRM="$(cat "$SPOOL/mut/$MID.from")" TO="$(cat "$SPOOL/mut/$MID.to")" \
       python3 "$SPOOL/mutapply.py" "$MW/$MFILE" 2>/dev/null; then
    # A mutation that matches NOTHING is stale and has silently been testing
    # the shipped code — the failure this whole file exists to prevent.
    print "STALE|$MID|$MLABEL"; exit 0
  fi
  if ! zsh "$SPOOL/build.zsh" "$MW"; then
    print "COMPILE|$MID|$MLABEL"; exit 0
  fi
  if "$MW/run" >/dev/null 2>&1; then
    print "SURVIVED|$MID|$MLABEL"; exit 0
  fi
  print "CAUGHT|$MID|$MLABEL"; exit 0
fi

PEER="Casberi/Casberi/Model/PeerRoom.swift"
LEDE="Casberi/Casberi/Model/RoomLede.swift"   # prd §585 — the shared lede type these rooms now return
POOLS="Casberi/Casberi/Model/PrivacyPoolsRoom.swift"
CARDSPEND="Casberi/Casberi/Model/CardSpendRoom.swift"
SAFE="Casberi/Casberi/Model/SafeRoom.swift"
for f in "$PEER" "$POOLS" "$CARDSPEND" "$SAFE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

SRC_PEER="Casberi/Casberi/Model/PeerRoomSource.swift"
SRC_METAMASK="Casberi/Casberi/Model/MetaMaskCardRoomSource.swift"
SRC_SAFE="Casberi/Casberi/Model/SafeRoomSource.swift"
BR_PEER="Casberi/Casberi/Model/PeerBridge.swift"
BR_POOLS="Casberi/Casberi/Model/PrivacyPoolsBridge.swift"
BR_METAMASK="Casberi/Casberi/Model/MetaMaskCardBridge.swift"
BR_RAILGUN="Casberi/Casberi/Model/RailgunBridge.swift"
CARD_PEER="Casberi/Casberi/Screens/PeerRoomCard.swift"
CARD_SPEND="Casberi/Casberi/Screens/CardSpendRoomCard.swift"
# FeedScreen is split across files (prd §718). Checks read the room as ONE text,
# so a guard can neither fail nor pass because its code moved next door.
FEED_DIR="$(mktemp -d -t feedscreen)"
FEED="$FEED_DIR/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+*.swift > "$FEED"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
DEMO="Casberi/Casberi/Model/DemoSeedAll.swift"

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
for f in "$BR_POOLS" "$POOLS"; do
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
grep -q 'thing.priceValue = value' "$BR_METAMASK" \
  || { echo "✗ MetaMaskCardBridge no longer stamps priceValue — every spend would be unpriced and the card could state no money at all"; exit 1; }
grep -q 'thing.priceCurrency = currency' "$BR_METAMASK" \
  || { echo "✗ MetaMaskCardBridge no longer stamps priceCurrency — spends would drop out of every total with nothing on screen to say so"; exit 1; }
grep -q 'tags: \["Shielded", "Pending"\]' "$BR_POOLS" \
  || { echo "✗ a Privacy Pools deposit no longer lands wearing a state tag — Needs you could never find the one that needs proof"; exit 1; }

# --- prd §397 (2026-08-17) --------------------------------------------------
# The money a deposit's row states (the ledger column, the receipt). Without
# BOTH halves the row keeps its figure inside its sentence.
grep -q 'thing.priceValue = value' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge no longer stamps priceValue — a deposit's row could state no money"; exit 1; }
# One helper stamps both versions' deposits (2026-10-21); v1 hands it OUR pool
# symbol, never the API's.
grep -q 'thing.priceCurrency = symbol' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge no longer stamps priceCurrency — a deposit's row would not say which asset it is"; exit 1; }
grep -q 'symbol: pool?.symbol,' "$BR_POOLS" \
  || { echo "✗ a v1 deposit no longer stamps its pool's own symbol"; exit 1; }
# THE LOOP. Without this the deposit a ragequit undoes keeps its `Declined`
# tag for life — invisible everywhere except search and the row's own chrome,
# which is exactly why it is mechanical.
grep -q 'retag(label: exit.label, to: PrivacyPoolsRoom.State.reclaimed.rawValue' "$BR_POOLS" \
  || { echo "✗ a ragequit no longer moves its own deposit's state tag — the row would keep saying Declined after the money came back"; exit 1; }
# Both halves of the join must build the ref from ONE constant, the
# `depositRefPrefix` lesson applied to the exit.
grep -q 'let ref = PrivacyPoolsRoom.reclaimedPrefix + exit.label' "$BR_POOLS" \
  || { echo "✗ the ragequit ref is spelled by hand again — the reclaim join keys on PrivacyPoolsRoom.reclaimedPrefix and would silently match nothing"; exit 1; }
# One rounding for the sheet's §228 sentence, the shipped one this file tests.
grep -q 'PrivacyPoolsRoom.roundedSet(n)' "$BR_POOLS" \
  || { echo "✗ PrivacyPoolsBridge rounds the anonymity set itself again — the tested rounding is no longer the one the sheet's sentence uses"; exit 1; }
# NEEDS YOU reads the same table (prd §1738: a deposit that needs your proof
# is Needs you's, the head that led with it is deleted). Two spellings of the
# deposit prefix or the tag is §311's bug, one file over.
NEEDS="Casberi/Casberi/Model/WalletNeedsYou.swift"
grep -q 'ref.hasPrefix(PrivacyPoolsRoom.depositPrefix)' "$NEEDS" \
  || { echo "✗ Needs you no longer finds a Privacy Pools deposit by the bridge's own prefix"; exit 1; }
grep -q 'PrivacyPoolsRoom.state(tags: tags) == .needsProof' "$NEEDS" \
  || { echo "✗ Needs you no longer reads a deposit's state off the shipped tag table — a deposit waiting on your proof would ask nobody"; exit 1; }

# Demo parity (the standing ship step): the reclaim pair must be seeded under
# the real prefixes, or the demo shows a deposit the bridge would have retagged.
grep -q 'PrivacyPoolsRoom.reclaimedPrefix + "demo6"' "$DEMO" \
  || { echo "✗ the demo no longer seeds a ragequit joined to a deposit — the §397 loop would ship unexercised"; exit 1; }
grep -q '"privacypools:ragequit:demo"' "$DEMO" \
  || { echo "✗ the demo's ragequit ref prefix is missing from refPrefixes — the exit row would outlive the demo and go on joining to a deposit that is real"; exit 1; }
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
grep -q 'static let source = "MetaMask Card"' "$BR_METAMASK" \
  || { echo "✗ MetaMaskCardBridge.source changed"; exit 1; }
grep -q 'source: source,' "$BR_METAMASK" \
  || { echo "✗ MetaMaskCardBridge no longer lands rows under its own source"; exit 1; }
grep -q 'static let sourceName = "Railgun"' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge.sourceName changed"; exit 1; }

# The move as DATA, still stamped by the bridge that lands it (prd §350) —
# without this a Railgun row's ledger column and receipt have no figure.
grep -q 'thing.priceValue = move.raw / pow(10, Double(decimals))' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge no longer stamps priceValue on a move — every shield/unshield would be unpriced"; exit 1; }
grep -q 'thing.priceCurrency = symbol' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge no longer stamps priceCurrency — a move would not say which token it is"; exit 1; }

# Corollary 4 — filtered live at the boundary, before any stored property is
# read. The caller hands these a debounced snapshot and the foreground sweep
# deletes rows while it is held.
for f in "$SRC_PEER" "$SRC_METAMASK"; do
  grep -q 'things.live' "$f" \
    || { echo "✗ $f no longer filters live at the boundary (corollary 4)"; exit 1; }
done

# Rendered at all. A head that composes and is never drawn is the §219 social
# roster, which spent weeks that way.
grep -q 'case .peer(let room)' "$FEED" \
  || { echo "✗ the Peer head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case .cardSpend(let room, let seat)' "$FEED" \
  || { echo "✗ the onchain-card head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case PeerRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Peer room"; exit 1; }

# --- prd §1738: the three retired heads stay retired --------------------------
# Safe, Privacy Pools and Railgun are no pick in the Wallet's menu, so a head
# for one of them is a card no box can draw (§723: deleted from the surface,
# deleted from the model). A file or a case coming back is that dead model
# returning. Read off COMMENT-STRIPPED copies: the code explains the deletion
# by naming what was deleted.
for gone in Model/RailgunRoom.swift Model/RailgunRoomSource.swift Screens/RailgunRoomCard.swift \
            Model/PrivacyPoolsRoomSource.swift Model/PrivacyPoolsCover.swift \
            Screens/PrivacyPoolsRoomCard.swift Screens/SafeRoomCard.swift; do
  [[ ! -e "Casberi/Casberi/$gone" ]] \
    || { echo "✗ $gone is back — its pick was retired by prd §1738, so nothing can draw it"; exit 1; }
done
strip_comments "$FEED" > "$TMP/feed.nocomment"
strip_comments "$PROBES" > "$TMP/probes.nocomment"
for dead in 'case privacyPools(' 'case railgun(' 'case safe(SafeRoom)' \
            'RailgunRoomSource' 'PrivacyPoolsRoomSource' 'SafeRoomSource.source:' \
            'SeatHoldings.railgun' 'PrivacyPoolsBridge.sourceName {'; do
  if grep -qF "$dead" "$TMP/feed.nocomment"; then
    echo "✗ FeedScreen names '$dead' again — a head or a pick branch for a seat that is no pick (§1738)"; exit 1
  fi
done
for dead in 'privacyPoolsRoomProbe' 'railgunRoomProbe' 'note("privacyPoolsHead"' \
            'note("railgunHead"' 'note("safeHead"'; do
  if grep -qF "$dead" "$TMP/probes.nocomment"; then
    echo "✗ ProbeHooks carries '$dead' again — a probe for a head that no longer exists (§1738)"; exit 1
  fi
done
# The seats themselves must still say where their door lands, or the deletion
# above orphans three Library tiles.
ACCOUNTS="Casberi/Casberi/Model/RoomAccounts.swift"
[[ $(grep -c 'landing: .privateHoldings' "$ACCOUNTS") -eq 2 ]] \
  || { echo "✗ Privacy Pools and Railgun no longer both land on Holdings › Private (§1738)"; exit 1; }
grep -q 'landing: .yourAccount' "$ACCOUNTS" \
  || { echo "✗ Safe no longer lands on Your account (§1738)"; exit 1; }

# The cards draw through the SHIPPED arithmetic and honour the row caps, so a
# card cannot quietly re-rank or over-draw what the room composed.
grep -q 'room.rails.prefix(PeerRoomSource.rowCap)' "$CARD_PEER" \
  || { echo "✗ the Peer card no longer honours the rail cap — the footnote would count rows that are drawn anyway"; exit 1; }
grep -q 'room.currencies.prefix(CardSpendRoom.rowCap)' "$CARD_SPEND" \
  || { echo "✗ the onchain-card head no longer honours the currency cap"; exit 1; }

# prd §858: the head is SHARED, so every card seat must reach it. A rename that
# quietly dropped one would leave that room leading with its newest row and
# nothing would fail — the §83 silence this whole harness exists to break.
grep -q 'case MetaMaskCardRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the MetaMask Card room"; exit 1; }
grep -q 'CardSpendRoomCard(room: room, seat: seat)' "$FEED" \
  || { echo "✗ the shared card is no longer drawn with its seat — the mark would be wrong"; exit 1; }
grep -q 'static let source = MetaMaskCardBridge.source' "Casberi/Casberi/Model/MetaMaskCardRoomSource.swift" \
  || { echo "✗ MetaMaskCardRoomSource spells its own source instead of taking the bridge's"; exit 1; }

# --- prd §868 (2026-09-21): the THIRD onchain card, and the room it shares ---
# ether.fi Cash sat on this shape with no head for seven weeks while its two
# siblings led with what the card cost. The same silence as above: a room that
# leads with its newest row looks finished.
SEAT="Casberi/Casberi/Model/CardSpendSeat.swift"
SRC_ETHERFI="Casberi/Casberi/Model/EtherFiCashRoomSource.swift"
for f in "$SEAT" "$SRC_ETHERFI"; do
  [[ -f "$f" ]] || { echo "✗ $f not found — the ether.fi Cash head is gone (§868)"; exit 1; }
done
grep -q 'case EtherFiCashRoomSource.source:' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the ether.fi Cash room (§868)"; exit 1; }
grep -q 'static let source = EtherFiCash.source' "$SRC_ETHERFI" \
  || { echo "✗ EtherFiCashRoomSource spells its own source instead of taking the bridge's"; exit 1; }

# THE RULE ITSELF, and the whole reason this seat needed more than a copy.
# `EtherFiCash.source` is ONE seat covering two products, so its room also holds
# `EtherFiUnstake`'s queue rows and this seat's risk crossings — both `.link`
# rows with no price. A bare `$0.source == source` filter (right for the other
# two seats, and what a third copy would have said) counts them in `allTime` and
# in the footnote's "spends with no readable amount": a sentence about money
# describing rows that are not purchases (§83). The rule lives in ONE place so
# the head and the door under it can never disagree about what a spend is; its
# LOGIC is proven in `CasberiTests/CardSpendSeatTests.swift`, because it reads a
# `Thing` and no Foundation-only harness can compile it.
grep -qF 'EtherFiCash.spendRefPrefix' "$SEAT" \
  || { echo "✗ CardSpendSeat no longer names the spend namespace — the ether.fi room's unstake and risk rows would count as unpriced spends (§868)"; exit 1; }
grep -qF 'spendRefPrefix + ' "Casberi/Casberi/Model/EtherFiCash.swift" \
  || { echo "✗ EtherFiCash builds a spend ref without its own prefix constant — the room's filter and the bridge's writes could drift (§868)"; exit 1; }
for f in "$SRC_ETHERFI" "$SRC_METAMASK" "Casberi/Casberi/Model/PlasmaOneRoomSource.swift"; do
  grep -qF 'CardSpendSeat.isSpend($0, seat: source)' "$f" \
    || { echo "✗ $(basename "$f") filters its room by something other than CardSpendSeat.isSpend — two card seats would decide what a spend is apart (§868)"; exit 1; }
  if grep -qF 'things.live.filter { $0.source == source }' "$f"; then
    echo "✗ $(basename "$f") still carries a bare source filter — a shared room's non-spend rows would reach the head (§868)"; exit 1
  fi
done
# The DOOR asks the same question the head composed with. It used to match on
# `priceCurrency` alone, which was right only by coincidence: no unstake row
# happens to carry a currency today.
grep -qF 'CardSpendSeat.isSpend(thing, seat: seat)' "$FEED" \
  || { echo "✗ the card head's door no longer asks CardSpendSeat whether the row is a spend (§868)"; exit 1; }

# The demo pours this room, and its rows must wear the REAL namespace — else
# the one surface anyone sees without an account shows a card seat with no card.
# §368's miss, left standing for this seat alone until §868.
grep -qF 'ref: "etherficash:spend:demo' "$DEMO" \
  || { echo "✗ the demo's ether.fi rows do not wear the shipped spend ref — the head would compose nothing and the money receipt would skip them (§368, §868)"; exit 1; }
# Matched as the `ref:` ARGUMENT, never as the bare string: the block's own
# comment explains what `demo:etherfi:<n>` broke, and a guard that greps for the
# prose fails on the record of the fix. A guard asserts the USE.
if grep -qF 'ref: "demo:etherfi:' "$DEMO"; then
  echo "✗ the demo's ether.fi rows are back on an invented ref shape (§368)"; exit 1
fi

# MetaMask Card was missing from the money set for a month (§857 landed the
# seat, §858 its head, neither joined it here) — so "what did I spend?" answered
# with a total that silently left a card out.
grep -qF '"MetaMask Card", "ether.fi"' "Casberi/Shared/Thing.swift" \
  || { echo "✗ Corpus.cardSpendSources no longer holds every onchain card — a spend answer would omit one (§868)"; exit 1; }
# The rooms whose every row is a transfer read as a LEDGER, not as prose: the
# amount leaves the sentence for a right-aligned figure (`BandRow.moneyColumn`,
# §158's reading). Both had no `Shape` case at all until this pass, so both drew
# the generic band. The onchain cards are deliberately absent — see the
# switch's own comment for the two-spellings-of-one-figure reason.
grep -q 'case "Railgun", "Privacy Pools": self = .ledger' "$FEED" \
  || { echo "✗ the wallet-riding money rooms no longer take the ledger shape — their rows would fall back to the generic band and keep the figure inside the sentence"; exit 1; }
grep -q 'case .ledger: BandRow(thing: thing, moneyColumn: true' "$FEED" \
  || { echo "✗ the ledger shape no longer asks for the money column — the shape would exist and change nothing"; exit 1; }
# The stamps that column reads. `transferAmount` has been landed since §369 and
# §397; the SIDE is what this pass added, and without it the pair is half
# stamped and the column can never draw.
grep -q 'thing.transferDirection = "sent"' "$BR_POOLS" \
  || { echo "✗ a Privacy Pools deposit no longer stamps its direction — its rows would keep the amount inside the sentence"; exit 1; }
grep -q 'thing.transferDirection = "received"' "$BR_POOLS" \
  || { echo "✗ a Privacy Pools reclaim no longer stamps its direction"; exit 1; }
grep -q 'thing.transferDirection = direction == .shield ? "sent" : "received"' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge no longer stamps the direction of a move"; exit 1; }
grep -q 'thing.transferAmount = amountLine' "$BR_RAILGUN" \
  || { echo "✗ RailgunBridge no longer stamps transferAmount — the ledger column reads this and nothing else"; exit 1; }
# THE DEMO'S OWN TRAP, paid for on this pass: the money column lifts the figure
# out of the sentence by SUBSTRING, so a seed whose title and stamp are the same
# NUMBER in two spellings ("0.1500 ETH" / "0.15 ETH") prints it twice. One
# string, spent twice, is the only shape that cannot drift.
grep -q 'row(.transaction, "Put \\(p.amount) into Privacy Pools"' "$DEMO" \
  || { echo "✗ the Privacy Pools demo no longer builds its title from the same string it stamps — the demo would print each amount twice"; exit 1; }
grep -q 't.transferAmount = p.amount' "$DEMO" \
  || { echo "✗ the Privacy Pools demo no longer stamps the amount it put in its own title"; exit 1; }
grep -q 't.transferAmount = r.amount' "$DEMO" \
  || { echo "✗ the Railgun demo no longer stamps transferAmount — every seeded move would keep its figure in its sentence and the ledger column would draw on no row at all"; exit 1; }
# The strip exists so that superseding `FeedInsight.cardMonths` costs nothing.
# A head outranks the generic registries, so a head that draws less than the
# card it displaced is a regression wearing a new feature.
grep -q 'CardSpendRoom.monthShare(total: month.total, of: top)' "$CARD_SPEND" \
  || { echo "✗ the onchain-card history strip no longer sizes its columns through the shipped monthShare()"; exit 1; }
# `cardMonths` went with the boards (prd §723); the card head is no longer
# superseding anything, it is simply the room's head.
# Peer's §311 board WAS the head's fallback below `minimumFills`, and prd §723
# deleted every ranked board. Below the minimums Peer now falls through the
# same chain every other room does — to a distribution, a mosaic, its heatmap,
# or to no head and the newest thing as a card. Nothing to assert here that
# `FeedInsight` still owns.
# The §219 failure inverted — see `-roomInsightProbe`'s own comment. A head in
# `shapedSections` with no line here makes the probe confidently report that a
# room "leads with NOTHING" when it leads with a card.
grep -q 'note("peerHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the Peer head"; exit 1; }
grep -q 'note("metamaskCardHead"' "$PROBES" \
  || { echo "✗ -roomInsightProbe no longer mirrors the MetaMask Card head"; exit 1; }
# Each reading gets its own probe, because for these seats an empty room is
# usually the HEALTHY answer and only one or two causes per room are bugs.
for key in peerRoomProbe metamaskCardRoomProbe safeRoomProbe; do
  grep -q "Hook(key: \"$key\")" "$PROBES" \
    || { echo "✗ -$key is gone — an empty head's several causes would be indistinguishable"; exit 1; }
done

# Safe's own `sourceName` — the 2026-08-11 re-source (SafeBridge's top-of-file
# doc, amendment 8). Change it here and the Wallet stops hosting a corpus
# whose rows still carry the OLD source string.
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

# `SafeAsk` reads the composition this file tests (prd §1738: no head draws
# it). If the ask stops reading it, the Safe sections below test a model with
# no reader.
grep -q 'SafeRoomSource.compose()' "Casberi/Casberi/Model/SafeAsk.swift" \
  || { echo "✗ SafeAsk no longer reads SafeRoomSource.compose — the Safe queue's rules below would have no reader but a probe"; exit 1; }
grep -q 'SafeRoom.stateLabel(lead)' "Casberi/Casberi/Model/SafeAsk.swift" \
  || { echo "✗ SafeAsk no longer says the lead's state through SafeRoom.stateLabel"; exit 1; }

# The widget half (the Today tile's Safe call) and the brief's stuck-signature
# rung went with the ask (2026-10-01). `SafeRoom.stuckLine` stays, read by
# `-safeRoomProbe`; its logic is still pinned below.

# The demo has to be able to SHOW all three states, or they ship unseen — the
# standing demo-parity rule.
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
print("Privacy Pools — the vocabulary the bridge, Needs you and the demo share")
// ===========================================================================

// The mirror everything rests on: these raw values ARE the tag strings
// `PrivacyPoolsBridge.retag` writes.
check("the tag vocabulary is the bridge's",
      PrivacyPoolsRoom.states == ["Pending", "Cleared", "Declined", "Needs proof", "Reclaimed"])
check("a state is read off the tag", PrivacyPoolsRoom.state(tags: ["Shielded", "Cleared"]) == .cleared)
check("the state that needs you is read off its tag",
      PrivacyPoolsRoom.state(tags: ["Shielded", "Needs proof"]) == .needsProof)
check("the shielded marker is not a state", PrivacyPoolsRoom.state(tags: ["Shielded"]) == nil)
// Defaulting to pending is a claim about the screener made with no evidence —
// a deposit that cleared two months ago reported as still waiting.
check("no state tag is nil, never pending", PrivacyPoolsRoom.state(tags: []) == nil)

print("")
print("Privacy Pools — one label joins a deposit, its alert and its ragequit")
// §311's bug was two spellings of one prefix. The prefixes are asserted as
// LITERALS on purpose: every device's landed rows carry these exact strings.
check("a deposit lands under dep:", PrivacyPoolsRoom.depositPrefix == "privacypools:dep:")
check("a ragequit lands under ragequit:", PrivacyPoolsRoom.reclaimedPrefix == "privacypools:ragequit:")
check("a deposit's label is its ref's suffix",
      PrivacyPoolsRoom.label(ref: PrivacyPoolsRoom.depositPrefix + "42") == "42")
check("its ragequit carries the same label",
      PrivacyPoolsRoom.label(ref: PrivacyPoolsRoom.reclaimedPrefix + "42") == "42")
check("its status alert carries the same label",
      PrivacyPoolsRoom.label(ref: "privacypools:status:42") == "42")
check("a ref no prefix names has no label", PrivacyPoolsRoom.label(ref: "peer:42") == nil)
check("no ref has no label", PrivacyPoolsRoom.label(ref: nil) == nil)

print("")
print("Privacy Pools — the set size's rounding (prd §228's sentence)")
// Locale-independent: the grouping separator differs by region, the digits do
// not.
check("two significant figures, rounded down",
      PrivacyPoolsRoom.roundedSet(3947).filter(\.isNumber) == "3900")
check("five digits keep two figures too",
      PrivacyPoolsRoom.roundedSet(12_345).filter(\.isNumber) == "12000")
check("a small set is stated exactly", PrivacyPoolsRoom.roundedSet(12) == "12")
check("a three-digit set is rounded as well", PrivacyPoolsRoom.roundedSet(742) == "740")
check("ninety-nine is still exact", PrivacyPoolsRoom.roundedSet(99) == "99")

// ===========================================================================
print("")
print("Onchain card — composing")
// ===========================================================================

func spend(_ amount: Double?, _ code: String?, at: Date) -> CardSpendRoom.Sighting {
    CardSpendRoom.Sighting(amount: amount, currency: code, at: at)
}

let cardRoom = CardSpendRoom.compose(spends: [
    spend(12.50, "EUR", at: day(-1)),
    spend(30.00, "EUR", at: day(-10)),
    spend(7.50,  "GBP", at: day(-3)),
    spend(nil,   "EUR", at: day(-5)),      // decimals never resolved
    spend(9.99,  nil,   at: day(-5)),      // no currency
    spend(20.00, "EUR", at: day(-40)),     // the window before
    spend(5.00,  "EUR", at: day(-200)),    // old enough to prove we were watching
], now: t0)
check("the window's spends are summed per currency",
      cardRoom.lead?.code == "EUR" && abs((cardRoom.lead?.total ?? 0) - 42.50) < 0.0001)
// EUR + GBP is an exchange rate this app does not have.
check("currencies are never summed into one figure", cardRoom.currencies.count == 2)
check("the second currency keeps its own total",
      abs((cardRoom.currencies.last?.total ?? 0) - 7.50) < 0.0001)
// A zero is a spend of nothing, which is a different and false claim. BOTH
// shapes land here: no amount, and an amount with no currency to put it in.
check("an unreadable amount is counted, never treated as zero", cardRoom.unpriced == 2)
check("a missing amount alone is counted",
      CardSpendRoom.compose(spends: [spend(nil, "EUR", at: day(-1))], now: t0).unpriced == 1)
check("a missing CURRENCY alone is counted too — it drops from every total",
      CardSpendRoom.compose(spends: [spend(9.99, nil, at: day(-1))], now: t0).unpriced == 1)
check("the window's spend count excludes the unpriced", cardRoom.lead?.spends == 2)
check("all-time counts every row the room holds", cardRoom.allTime == 7)
check("the oldest spend is remembered", cardRoom.oldest == day(-200))

print("")
print("Onchain card — the comparison is refused rather than estimated")
check("the prior window is known when history reaches past it",
      CardSpendRoom.knowsPriorWindow(oldest: day(-200), now: t0))
// A first sync backfills about six days. The prior window is then not quiet,
// it is unobserved — and "up 400%" against it would be a fabrication.
check("a young room knows nothing about the window before",
      CardSpendRoom.knowsPriorWindow(oldest: day(-6), now: t0) == false)
check("a room with no spends at all knows nothing",
      CardSpendRoom.knowsPriorWindow(oldest: nil, now: t0) == false)
check("the prior total is carried when it is knowable",
      abs((cardRoom.lead?.prior ?? 0) - 20.00) < 0.0001)
let young = CardSpendRoom.compose(spends: [spend(10, "EUR", at: day(-2))], now: t0)
check("a young room carries no prior at all", young.lead?.prior == nil)
check("and says the count alone, no comparison (prd §1416)",
      CardSpendRoom.note(young) == "1 spend")
// Plasma One (prd §1311): a row is a DAY's settlement, so every count says
// days and the footnote says the newest day is yesterday's — while the money
// is summed exactly as a spend's would be.
let daily = CardSpendRoom.compose(spends: [spend(10, "USD", at: day(-2)), spend(5.5, "USD", at: day(-1))],
                                  now: t0, unit: .settledDay)
check("a daily card counts days, never spends",
      CardSpendRoom.note(daily).hasPrefix("2 days of spending")
      && !CardSpendRoom.note(daily).contains("spends"))
check("a daily card's money sums like any card's", abs((daily.lead?.total ?? 0) - 15.5) < 0.0001)
check("a used card's foot says nothing (prd §1416)",
      CardSpendRoom.footnote(daily, now: t0) == nil)
var dailyHeld = daily
dailyHeld.balance = .init(amount: 3850.84, code: "USD", at: t0)
check("the balance is a line of its own, never in the window's total",
      CardSpendRoom.balanceLine(dailyHeld.balance!, locale: Locale(identifier: "en_US")) == "$3,850.84 on the card"
      && abs((dailyHeld.lead?.total ?? 0) - 15.5) < 0.0001)
check("a hidden balance hides this one too",
      CardSpendRoom.balanceLine(dailyHeld.balance!, mask: "••••") == "•••• on the card")

print("")
print("Onchain card — the change")
func cur(_ total: Double, prior: Double?, spends: Int = 3) -> CardSpendRoom.Currency {
    CardSpendRoom.Currency(code: "EUR", total: total, spends: spends, prior: prior, newest: t0)
}
check("a rise is a fraction", abs((CardSpendRoom.delta(cur(120, prior: 100)) ?? 0) - 0.2) < 0.0001)
check("a fall is negative", (CardSpendRoom.delta(cur(80, prior: 100)) ?? 0) < 0)
// Coming back from nothing has no percentage, and printing +100% for it is an
// arithmetic accident.
check("a zero prior window does not divide", CardSpendRoom.delta(cur(50, prior: 0)) == nil)
check("an unknown prior claims nothing", CardSpendRoom.delta(cur(50, prior: nil)) == nil)
// Card spending is lumpy — one weekly shop lands differently in two windows.
check("a small move is noise and gets no word", CardSpendRoom.deltaLabel(cur(105, prior: 100)) == nil)
check("a real rise is stated in words",
      CardSpendRoom.deltaLabel(cur(130, prior: 100)) == "30% more than the 30 days before")
check("a real fall is stated in words",
      CardSpendRoom.deltaLabel(cur(70, prior: 100)) == "30% less than the 30 days before")

print("")
print("Onchain card — the history strip")
// This head OUTRANKS `FeedInsight.cardMonths`, the 12-month leaderboard the
// room drew before it. A head that showed less than the card it displaced would
// be a regression wearing a new feature, so the months come with it.
func monthsOf(_ n: Int, _ code: String = "EUR", each: Double = 10) -> [CardSpendRoom.Sighting] {
    (0..<n).map { spend(each, code, at: cal.date(byAdding: .month, value: -$0, to: t0)!) }
}
let hist = CardSpendRoom.compose(spends: monthsOf(5), now: t0)
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
      CardSpendRoom.monthKey(dec)! < CardSpendRoom.monthKey(jan)!)
check("a key round-trips to the month it names",
      CardSpendRoom.monthKey(CardSpendRoom.monthStart(key: CardSpendRoom.monthKey(dec)!)!)
        == CardSpendRoom.monthKey(dec))
// A one-column history is not a history — one lone bar reads as a level.
check("one month draws no strip", CardSpendRoom.compose(spends: monthsOf(1), now: t0).months.isEmpty)
// Silent truncation: a dropped month looks exactly like a quiet one.
let long = CardSpendRoom.compose(spends: monthsOf(20), now: t0)
check("the strip is capped", long.months.count == CardSpendRoom.monthCap)
check("and the months it dropped are COUNTED, not silently truncated",
      long.monthsHidden == 20 - CardSpendRoom.monthCap)
check("the cap keeps the NEWEST months",
      long.months.last?.key == CardSpendRoom.monthKey(t0))
// The strip follows the currency the HEADLINE states, so one card is never
// about two different sorts of money.
let mixed = CardSpendRoom.compose(spends:
    monthsOf(4, "EUR") + monthsOf(4, "GBP") + [spend(1, "EUR", at: day(-1))], now: t0)
check("the strip follows the lead currency", mixed.lead?.code == "EUR")
check("spends in another currency are counted, not folded in",
      mixed.monthsOtherCurrency == 4)
check("the caption names the currency it drew",
      (CardSpendRoom.historyNote(mixed) ?? "").contains("EUR"))
check("and narrates nothing it left out (prd §1416)",
      !(CardSpendRoom.historyNote(mixed) ?? "").contains("other currencies"))
check("no strip, no caption",
      CardSpendRoom.historyNote(CardSpendRoom.compose(spends: monthsOf(1), now: t0)) == nil)
// Scaled against the biggest DRAWN month: scaling to one off the end of the
// strip would flatten every visible column against something nobody can see.
check("the tallest drawn month is full height", CardSpendRoom.monthShare(total: 50, of: 50) == 1)
check("half is half", CardSpendRoom.monthShare(total: 25, of: 50) == 0.5)
check("a zero peak can't divide by zero", CardSpendRoom.monthShare(total: 5, of: 0) == 0)
check("a month abbreviates", CardSpendRoom.monthLabel(dec, locale: us) == "Dec")

print("")
print("Onchain card — ranking never compares magnitudes across currencies")
func c(_ code: String, spends: Int, total: Double, at: Date = t0) -> CardSpendRoom.Currency {
    CardSpendRoom.Currency(code: code, total: total, spends: spends, prior: nil, newest: at)
}
// 400 EUR against 380 GBP is the cross-currency sum this file refuses, wearing
// a sort instead of a plus.
check("more spends wins, even against a bigger total in another currency",
      CardSpendRoom.ordered([c("GBP", spends: 2, total: 9000),
                             c("EUR", spends: 9, total: 10)]).first?.code == "EUR")
check("a tie breaks on recency",
      CardSpendRoom.ordered([c("GBP", spends: 2, total: 1, at: day(-9)),
                             c("EUR", spends: 2, total: 1, at: day(-1))]).first?.code == "EUR")
check("a full tie breaks on code",
      CardSpendRoom.ordered([c("USD", spends: 2, total: 1),
                             c("EUR", spends: 2, total: 1)]).first?.code == "EUR")
check("the bar is a share of the spend COUNT", CardSpendRoom.share(spends: 3, of: 6) == 0.5)
check("a zero denominator can't divide by zero", CardSpendRoom.share(spends: 3, of: 0) == 0)

print("")
print("Onchain card — words")
check("money is rendered in its own currency",
      CardSpendRoom.money(42.5, code: "GBP", locale: us) == "£42.50")
check("a zero-decimal currency is not forced to two",
      CardSpendRoom.money(1200, code: "JPY", locale: us) == "¥1,200")
check("a single-currency headline states the money and the window",
      CardSpendRoom.headline(young, locale: us) == "€10.00 on your card in 30 days")
check("several currencies are named as several, never added",
      CardSpendRoom.headline(cardRoom, locale: us).contains("plus another currency"))
// The honest reading a list of old rows never states.
let quiet = CardSpendRoom.compose(spends: [spend(10, "EUR", at: day(-90))], now: t0)
check("a quiet window on a real room says so",
      CardSpendRoom.headline(quiet) == "Nothing spent in the last 30 days")
check("and the room still draws rather than vanishing", !quiet.isEmpty)
check("an unused card is stated once the gap outruns the window",
      CardSpendRoom.idleNote(newest: day(-90), now: t0) == "unused for 90 days")
// It must never contradict a headline that just reported spending in the
// window.
check("a card used inside the window is never called unused",
      CardSpendRoom.idleNote(newest: day(-3), now: t0) == nil)
check("a room with no spends at all is no card", CardSpendRoom.compose(spends: [], now: t0).isEmpty)

print("")
print("Safe — ranking is your-turn first, then ready, then oldest first")
func safeEntry(_ ref: String, have: Int = 1, required: Int = 3, yourTurn: Bool = false,
               submittedAt: Date? = nil, nonce: Int? = nil,
               safe: String = "0xSafe", description: String = "a transfer",
               waitingOn: [String] = [], safeNonce: Int? = nil) -> SafeRoom.Entry {
    SafeRoom.Entry(ref: ref, safeAddress: safe, have: have, required: required,
                   yourTurn: yourTurn, submittedAt: submittedAt, descriptionText: description,
                   nonce: nonce, waitingOn: waitingOn, safeNonce: safeNonce)
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
print("Safe — the head names PEOPLE, and the queue decides what 'ready' means (2026-09-07)")
// §238 ruled this bridge is about who to go ask, and the head could only ever
// say "2 more signatures needed" because the tracking store kept counts and no
// roster. It keeps the outstanding owners now, so the sentence names them.
check("one outstanding owner is named",
      SafeRoom.stateLabel(safeEntry("a", have: 2, required: 3, waitingOn: ["alice.eth"]))
        == "Waiting on alice.eth")
check("two are one name and a count, never a list that truncates mid-row",
      SafeRoom.stateLabel(safeEntry("a", have: 1, required: 3,
                                    waitingOn: ["alice.eth", "bob.eth"]))
        == "Waiting on alice.eth and 1 other")
check("three or more count the rest",
      SafeRoom.stateLabel(safeEntry("a", have: 0, required: 3,
                                    waitingOn: ["alice.eth", "bob.eth", "carol.eth"]))
        == "Waiting on alice.eth and 2 others")
// AN EMPTY ROSTER IS A READ THAT DID NOT ANSWER, never a transaction nobody
// owes. Falling back to the count is what keeps a failed owner read from
// rendering as "waiting on nobody" beside a fraction saying two are missing.
check("an empty roster falls back to the signature count, never to silence",
      SafeRoom.stateLabel(safeEntry("a", have: 1, required: 3))
        == "2 more signatures needed")
check("…and the phrase itself is nil rather than empty when nothing is known",
      SafeRoom.waitingOnPhrase(safeEntry("a", have: 1, required: 3)) == nil)
// YOUR TURN AND READY BOTH OUTRANK THE ROSTER. Naming somebody else while the
// missing signature is yours points at the wrong person.
check("your own turn is never rendered as waiting on somebody else",
      SafeRoom.stateLabel(safeEntry("a", have: 1, required: 3, yourTurn: true,
                                    waitingOn: ["alice.eth"])) == "Your turn")

// A THRESHOLD MET IS NOT A TRANSACTION THAT CAN BE SENT. A Safe executes one
// per nonce in order, so "Ready to execute" at position N+2 sends somebody to
// press a button that is not there — the honesty rule's dead control, in a
// sentence.
check("a fully-signed transaction at the front is executable",
      safeEntry("a", have: 3, required: 3, nonce: 42, safeNonce: 42).isExecutable)
check("a fully-signed transaction behind two others is NOT executable",
      !safeEntry("a", have: 3, required: 3, nonce: 44, safeNonce: 42).isExecutable)
check("…and it is still 'ready' for the ranking, which asks a different question",
      safeEntry("a", have: 3, required: 3, nonce: 44, safeNonce: 42).isReady)
check("…and it says how many are in front of it",
      safeEntry("a", have: 3, required: 3, nonce: 44, safeNonce: 42).blockedBy == 2)
check("a transaction with no known position claims nothing about the queue",
      safeEntry("a", have: 3, required: 3, nonce: nil, safeNonce: 42).blockedBy == nil
        && safeEntry("a", have: 3, required: 3, nonce: 44, safeNonce: nil).blockedBy == nil)
check("…and an unknown position is EXECUTABLE, not blocked — nil is not zero",
      safeEntry("a", have: 3, required: 3, nonce: nil).isExecutable)
check("a blocked transaction says so instead of promising an execution",
      SafeRoom.stateLabel(safeEntry("a", have: 3, required: 3, nonce: 43, safeNonce: 42))
        == "Fully signed — behind 1 earlier transaction")
let safeBlockedRoom = SafeRoom.compose(
    entries: [safeEntry("a", have: 3, required: 3, nonce: 44, safeNonce: 42)], safeCount: 1)
check("a headline never promises 'ready to execute' when nothing can be sent",
      !SafeRoom.headline(safeBlockedRoom).contains("ready to execute")
        && SafeRoom.headline(safeBlockedRoom).contains("waiting its turn"))
check("…and the plural agrees with itself",
      SafeRoom.headline(SafeRoom.compose(
        entries: [safeEntry("a", have: 3, required: 3, nonce: 44, safeNonce: 42),
                  safeEntry("b", have: 2, required: 2, nonce: 45, safeNonce: 42)],
        safeCount: 1)).contains("waiting their turn"))
check("…while a front-of-queue one still promises it",
      SafeRoom.headline(SafeRoom.compose(
        entries: [safeEntry("a", have: 3, required: 3, nonce: 42, safeNonce: 42)],
        safeCount: 1)).contains("ready to execute"))
// The second sentence exists to say there is something to GO AND DO.
check("the state note counts only what can actually be sent",
      SafeRoom.stateNote(SafeRoom.compose(
        entries: [safeEntry("a", have: 1, required: 3, yourTurn: true, nonce: 42, safeNonce: 42),
                  safeEntry("b", have: 3, required: 3, nonce: 44, safeNonce: 42)],
        safeCount: 1)) == nil)

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
check("with only one Safe followed there is nothing to disambiguate, so the name would be noise",
      SafeRoom.note(safeRoomModule)?.contains("treasury.eth") == false)
// Naming it is the whole point once there is more than one: "1 module can move
// funds without a signature" says a drain is possible and not WHERE.
let safeRoomModuleNamed = SafeRoom.compose(entries: [], safeCount: 3,
                                           moduleSafes: [.init(label: "treasury.eth", count: 1)])
check("with several Safes followed the module warning names the one it means",
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

print("")
print("Safe — the row's own words (2026-08-24, prd §464)")
// The card drew a 60pt ring per entry and said the state in COLOUR alone —
// tint for your turn, green for ready, tertiary for everything else, painted
// onto the wait caption. Three rings reading "3 days" in three tints are one
// ring in greyscale, in a PDF export, and to a red-green viewer. Every failure
// here renders as a perfectly ordinary row.
check("your turn is a WORD, not a tint",
      SafeRoom.stateLabel(safeEntry("a", have: 1, required: 3, yourTurn: true)) == "Your turn")
check("a met threshold says the act, not the wait",
      SafeRoom.stateLabel(safeEntry("a", have: 3, required: 3)) == "Ready to execute")
// Your turn OUTRANKS ready in the sentence exactly as it does in `ordered`:
// anybody can execute a signed transaction and only you can add your signature.
check("a transaction that is BOTH yours and short still leads with your turn",
      SafeRoom.stateLabel(safeEntry("a", have: 2, required: 3, yourTurn: true)) == "Your turn")
check("a fully-signed transaction you never signed is ready, never your turn",
      SafeRoom.stateLabel(safeEntry("a", have: 2, required: 2, yourTurn: true)) == "Ready to execute")
// It counts SIGNATURES and never people: this card holds no owner roster (that
// is SafeQueueCard's, one screen deeper), so "2 others" would be a claim about
// WHO built from a number that only says how many more.
check("the waiting form counts signatures still needed",
      SafeRoom.stateLabel(safeEntry("a", have: 1, required: 3)) == "2 more signatures needed")
check("one short is singular",
      SafeRoom.stateLabel(safeEntry("a", have: 2, required: 3)) == "1 more signature needed")
// A transaction whose `confirmationsRequired` never parsed arrives as 0/0 —
// `isReady`'s own guard, one rung down. "0 more signatures needed" would be a
// claim about a threshold we could not read.
check("an unread threshold gets the bare word, never a fabricated shortfall",
      SafeRoom.stateLabel(safeEntry("a", have: 0, required: 0)) == "Waiting")

// The subject. It was cached on every entry and drawn ONLY inside the card's
// VoiceOver label, so a sighted reader got strictly less than a VoiceOver one.
check("the row is about what the transaction IS",
      SafeRoom.subject(safeEntry("a", description: "a transfer of 1,500 USDC to alice.eth"))
        == "a transfer of 1,500 USDC to alice.eth")
check("a description the bridge never cached falls back to a noun, not to nothing",
      SafeRoom.subject(safeEntry("a", description: "")) == "Pending transaction")

print("")
print("Safe — the stuck-signature line (the brief and the widget read it until 2026-10-01)")
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
check("a fully-signed transaction is never reported as a stuck signature",
      SafeRoom.stuckDays(SafeRoom.compose(
        entries: [safeEntry("a", have: 3, required: 3, yourTurn: true, submittedAt: day(-40))],
        safeCount: 1), now: t0) == nil)
check("an unknown submission date yields no duration rather than a fabricated one",
      SafeRoom.stuckDays(SafeRoom.compose(
        entries: [safeEntry("a", have: 1, required: 3, yourTurn: true, submittedAt: nil)],
        safeCount: 1), now: t0) == nil)

print("")
if failures > 0 { print("\(failures) failed"); exit(1) }
print("all assertions passed")
SWIFT

echo "wallet-rooms-selftest: compiling the four models WHOLE and unmodified…"
# `-Onone`, not `-O`: 97% of this harness's wall time was the optimizer,
# and it bought nothing an assertion can see — measured 9.2x faster here
# (2026-09-02). NOT a blanket rule: `-O` can change a harness's OBSERVABLE
# behaviour (a trapping one prints NOTHING under `-O`), so this file was
# proven equivalent run-for-run by `scripts/support/harness-opt-probe.sh`.
# Re-probe before trusting it again after adding mutations.
# ONE compile line, written once and run by both the assertion build and every
# mutation child. Two copies of an eight-file compile drift, and the drift is
# invisible: the mutants would be measured against a different file set than the
# assertions (§468's bug, which scored thirty-four type errors as
# thirty-four catches).
cat > "$TMP/build.zsh" <<'BUILDSH'
MW="$1"
swiftc -Onone -o "$MW/run" \
  "$MW/PeerRoom.swift" "$MW/PrivacyPoolsRoom.swift" "$MW/CardSpendRoom.swift" \
  "$MW/SafeRoom.swift" \
  "$MW/RoomLede.swift" "$MW/main.swift" 2>/dev/null
BUILDSH

# The applier, written to a file so the child needs no heredoc of its own.
cat > "$TMP/mutapply.py" <<'MUTAPPLY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if frm not in src:
    sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
MUTAPPLY

# The pristine tree every mutation is cut from. Staged ONCE; a child copies it
# rather than re-reading the repo, so an edit landing in the working tree
# mid-run cannot make two mutations disagree about what "the shipped source" is.
mkdir -p "$TMP/base"
cp "$PEER"    "$TMP/base/PeerRoom.swift"
cp "$POOLS"   "$TMP/base/PrivacyPoolsRoom.swift"
cp "$CARDSPEND"  "$TMP/base/CardSpendRoom.swift"
cp "$SAFE"    "$TMP/base/SafeRoom.swift"
cp "$LEDE"    "$TMP/base/RoomLede.swift"
cp "$TMP/main.swift" "$TMP/base/main.swift"

zsh "$TMP/build.zsh" "$TMP/base" \
  || { echo "✗ the shipped room heads do not compile Foundation-only — something reached Thing/SwiftUI"; exit 1; }
"$TMP/base/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Every mutation below is a silent wrong answer that renders perfectly. A
# mutation that survives means nothing here was testing that line.
echo ""
echo "mutations (each must be caught):"

# RECORD a mutation; the fan-out below runs them.
#
# **They run CONCURRENTLY (PERF, 2026-09-05).** Every mutation is PURE — it
# edits its own scratch copy and reads nothing the others write — so running
# them one at a time on one core of eight was the whole of this harness's cost:
# 68 mutations x an eight-file compile measured 320s in the 2026-09-05 nightly.
#
# `xargs -P`, never a `jobs -r` slot loop: job control is OFF in a
# non-interactive zsh, so `jobs -r` reports NOTHING and the loop degrades
# silently to "launch all 68 at once", which on 8 cores thrashes to slower than
# serial while every check still passes (`verify.sh`'s own paid-for trap,
# 2026-08-19).
#
# The `which` keyword and the call sites are UNCHANGED: 68 lines that each name
# their subject are the readable part of this file, and a port that rewrote them
# would be a port nobody could review against the old one.
MUTN=0
mutate() {
  local name="$1" which="$2" frm="$3" to="$4"
  local file
  case "$which" in
    peer)    file=PeerRoom.swift ;;
    pools)   file=PrivacyPoolsRoom.swift ;;
    card)    file=CardSpendRoom.swift ;;
    safe)    file=SafeRoom.swift ;;
    *)       echo "✗ mutation '$name' names no known file: $which"; exit 1 ;;
  esac
  MUTN=$((MUTN + 1))
  local id
  id="$(printf '%03d' "$MUTN")"
  mkdir -p "$TMP/mut"
  # `printf '%s'`, never `echo`: a trailing newline appended to `frm` makes the
  # pattern match nothing, which this harness reports as a STALE mutation — a
  # confusing failure for a mutation that is perfectly correct.
  printf '%s' "$name" > "$TMP/mut/$id.label"
  printf '%s' "$file" > "$TMP/mut/$id.file"
  printf '%s' "$frm"  > "$TMP/mut/$id.from"
  printf '%s' "$to"   > "$TMP/mut/$id.to"
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
# The mirror. A raw value that stops matching the tag `retag` writes reads a
# deposit waiting on your proof as untagged, and Needs you never asks.
mutate "a state's raw value stops mirroring the bridge's tag" pools \
  'case needsProof   = "Needs proof"' \
  'case needsProof   = "NeedsProof"'
# §311's bug itself: the deposit prefix spelled the way it was looked up, not
# the way it lands. Every landed row stops matching.
mutate "the deposit prefix goes back to the spelling nothing lands under" pools \
  'static let depositPrefix   = "privacypools:dep:"' \
  'static let depositPrefix   = "privacypools:deposit:"'
# A ragequit that no longer yields its deposit's label retags nothing, so the
# deposit it undid says Declined for life.
mutate "a ragequit ref no longer yields its deposit's label" pools \
  'for prefix in [depositPrefix, statusPrefix, reclaimedPrefix]' \
  'for prefix in [depositPrefix, statusPrefix]'
# The label is the SUFFIX. Returning the whole ref joins nothing to anything.
mutate "a label keeps its prefix" pools \
  'return String(ref.dropFirst(prefix.count))' \
  'return ref'
# Three significant figures states a precision the sentence says it does not have.
mutate "the set size is rounded to three figures instead of two" pools \
  'let unit = Int(pow(10.0, Double(digits - 2)))' \
  'let unit = Int(pow(10.0, Double(digits - 3)))'
# The floor moves up a digit, so a pool of 742 is stated to the deposit: the
# exact count the sentence says is noise.
mutate "a three-digit set is stated exactly" pools \
  'guard n >= 100 else { return "\(n)" }' \
  'guard n >= 1000 else { return "\(n)" }'
# The cross-currency sum this file exists to refuse.
mutate "every currency lands in one bucket" card \
  'var bucket = buckets[code] ?? (total: 0, spends: 0, newest: sighting.at)' \
  'let code = "ALL"; var bucket = buckets[code] ?? (total: 0, spends: 0, newest: sighting.at)'
# "Up 400%" against a window the room was never watching.
mutate "a comparison is claimed against an unobserved window" card \
  'guard let oldest else { return false }
        return oldest <= windowStart(now, back: 2, calendar: calendar)' \
  'return true'
# Coming back from nothing has no percentage.
mutate "a zero prior window divides anyway" card \
  'guard let prior = currency.prior, prior > 0 else { return nil }' \
  'guard let prior = currency.prior else { return nil }'
# A zero is a spend of nothing, which is a different and false claim. Again
# written to compile, so the catch is behavioural.
mutate "an unreadable amount is folded into the total as zero" card \
  '            let code = sighting.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let amount = sighting.amount, let code, !code.isEmpty else {
                if sighting.at >= start { unpriced += 1 }
                continue
            }' \
  '            let code = sighting.currency?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "EUR"
            let amount = sighting.amount ?? 0'
# A dropped month looks exactly like a quiet one, which is the failure the
# import drop counters exist to prevent, one room over.
mutate "the strip truncates its history silently" card \
  'return (months, keys.count - drawn.count, other)' \
  'return (months, 0, other)'
# The oldest months kept instead of the newest — a "history" that stops a year
# ago and renders perfectly.
mutate "the strip keeps the oldest months instead of the newest" card \
  'let drawn = Array(keys.suffix(monthCap))' \
  'let drawn = Array(keys.prefix(monthCap))'
# A month key that resets each year sorts December after the January following
# it, so the strip runs backwards across every year boundary.
mutate "a month key stops surviving the year boundary" card \
  'return year * 12 + (month - 1)' \
  'return month - 1'
# One card, two sorts of money: the strip drawn in a currency the headline is
# not talking about.
mutate "spends in another currency are folded into the strip" card \
  'for (otherCode, otherCells) in monthly where otherCode != code {' \
  'for (otherCode, otherCells) in monthly where otherCode == "\u{0}" && otherCode != code {'
# Ranking by amount compares 400 EUR against 380 GBP as if they were on one
# scale — the refused sum, wearing a sort instead of a plus.
mutate "currencies are ranked by amount instead of count" card \
  'if a.spends != b.spends { return a.spends > b.spends }' \
  'if a.total != b.total { return a.total > b.total }'

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
# --- 2026-08-24: the row's own words (prd §464) -----------------------------
# Your turn stops outranking ready IN THE SENTENCE, so a transaction that needs
# your signature and has most of them announces itself as ready to execute —
# the state word is the loudest thing on the row and it names the wrong act.
mutate "the state word stops leading with your turn" safe \
  'if entry.awaitsYou { return String(localized: "Your turn") }' \
  'if false { return String(localized: "Your turn") }'
# The shortfall is computed the wrong way round: a 1-of-3 reports that it needs
# minus-two more, which the guard below then swallows into the bare "Waiting" —
# so the one row genuinely furthest from executing looks the least urgent.
mutate "the signatures still needed are counted backwards" safe \
  'let short = entry.required - entry.have' \
  'let short = entry.have - entry.required'
# An unread 0/0 threshold claims a shortfall it has no evidence for. Same
# reasoning as `isReady`'s own `required > 0`, one rung down.
mutate "an unread threshold states a shortfall anyway" safe \
  'guard entry.required > 0, short > 0 else { return String(localized: "Waiting") }' \
  'guard true else { return String(localized: "Waiting") }'
# A row whose description never reached the tracking store leads with an empty
# line — a row with a ring, a state and no subject, which reads as a rendering
# bug rather than as a missing field.
mutate "a missing description leaves the row with no subject at all" safe \
  'entry.descriptionText.isEmpty' \
  'false'
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
# ── the last mutation must precede the fan-out ───────────────────────────────
# A `mutate` call BELOW the fan-out is silently never run and the pass still
# goes green. It is a file-ORDER bug, so no care inside the block can catch it —
# only the file can. This reads itself.
MUT_LAST="$(grep -n '^mutate ' "$SELF" | tail -1 | cut -d: -f1)"
FANOUT_AT="$(grep -n '^# --- run every recorded mutation, concurrently' "$SELF" | head -1 | cut -d: -f1)"
if [[ -n "$MUT_LAST" && -n "$FANOUT_AT" ]] && (( MUT_LAST > FANOUT_AT )); then
  echo "✗ a mutation is declared at line $MUT_LAST, BELOW the fan-out at line $FANOUT_AT — it would never run and the pass would still go green. Move it above."
  exit 1
fi

# HOW MANY AT ONCE, and why it is not simply `ncpu`. This harness may be run
# TWO ways: on its own, where it should take the whole machine, and inside
# `verify.sh` / `verify-mac.sh`, which already run the harnesses themselves
# under `xargs -P ncpu`. Nested at full width that is ncpu x ncpu — 64 `swiftc`
# processes on 8 cores here — and the cost is not merely scheduling: each is
# hundreds of MB against 16 GB, so the failure mode is memory pressure and swap,
# which looks like the machine hanging rather than like a test being slow. The
# outer runners export `HARNESS_INNER_JOBS`; standalone there is no outer swarm
# and the default is the whole machine.
MUT_JOBS="${HARNESS_INNER_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || print 4)}"

# --- run every recorded mutation, concurrently -------------------------------
# One core per mutation up to the machine's count. Output is KEPT and sorted by
# id so the report reads in declaration order regardless of which finished
# first — `xargs` interleaves, and a mutation list that reshuffles between runs
# is one nobody can diff.
: > "$TMP/mut-results"
ls "$TMP"/mut/*.label | sed 's#.*/##; s#\.label$##' \
  | xargs -P "$MUT_JOBS" -I{} zsh "$SELF" --mutate "$TMP" {} \
  >> "$TMP/mut-results" 2>&1

MUT_FAILS=0
MUT_OK=0
while IFS='|' read -r verdict mid label; do
  case "$verdict" in
    CAUGHT)   printf '  ✓ %s\n' "$label"; MUT_OK=$((MUT_OK + 1)) ;;
    COMPILE)  printf '  ✓ %s (rejected at compile)\n' "$label"; MUT_OK=$((MUT_OK + 1)) ;;
    SURVIVED) printf '  ✗ %s — the harness still passed, so nothing was testing this\n' "$label"
              MUT_FAILS=$((MUT_FAILS + 1)) ;;
    STALE)    printf '  ✗ %s — the mutation did not apply (the shipped source moved)\n' "$label"
              MUT_FAILS=$((MUT_FAILS + 1)) ;;
    *)        [[ -n "$verdict" ]] && printf '  %s\n' "$verdict" ;;
  esac
done < <(sort "$TMP/mut-results")

# Every mutation must have reported. A child that died without a line is a
# mutation nobody ran, and a silently skipped mutation is exactly the false
# green this whole file exists to prevent.
if (( MUT_OK + MUT_FAILS != MUTN )); then
  echo "✗ $((MUTN - MUT_OK - MUT_FAILS)) of $MUTN mutation(s) never reported — they did not run"
  exit 1
fi
(( MUT_FAILS == 0 )) || { echo "✗ $MUT_FAILS mutation(s) failed"; exit 1; }

echo ""
echo "wallet-rooms-selftest: OK — assertions pass and every mutation is caught."
