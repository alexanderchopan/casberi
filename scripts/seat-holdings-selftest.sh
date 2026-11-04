#!/bin/zsh
# Casberi seat-holdings self-test (prd §1701) — what an app picked in the
# Wallet shows under Holdings when no wallet read carries it, compiled WHOLE
# and unmodified:
#
#   Casberi/Casberi/Model/SeatHoldings.swift   (+ Shared/AddressTail.swift)
#
# Every failure here renders as a perfectly good-looking Holdings page:
#
#   · an ENS name nobody registered listed as one you follow and hold
#   · a CardPointers card dropped once its offers are used, or an offer
#     already used counted as unused
#   · a closed Privacy.com card listed, or a monthly limit that never goes
#     down as the month spends it
#   · MetaMask Card's "Can spend" taking the allowance when the wallet holds
#     less (the usual case: allowances are often unlimited)
#   · Peer's escrow counting only what is free, not what a buyer has locked
#   · a token with no dollar price stated as dollars
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/SeatHoldings.swift"
TAIL="Casberi/Shared/AddressTail.swift"
[[ -f "$SRC" && -f "$TAIL" ]] || { echo "✗ SeatHoldings sources not found"; exit 1; }

fail() { echo "✗ seat-holdings-selftest: $1"; exit 1 }

# ── Drift guards: the use, not the declaration ──────────────────────────────
W="Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift"
for seat in MetaMaskCardBridge.source WalletCards.privacySource EtherFiCash.source \
            PeerBridge.sourceName ENSWatch.source CardPointersIngest.source; do
  grep -qF "case $seat" "$W" || fail "$seat no longer stands in its pick's Holdings"
done
grep -qF 'walletSeatOwnHeld(visible).isEmpty ? "empty" : "full"' Casberi/Casberi/Screens/FeedScreen+AppPageProbe.swift \
  || grep -qF '&& walletSeatOwnHeld(visible).isEmpty ? "empty" : "full"' Casberi/Casberi/Screens/FeedScreen+AppPageProbe.swift \
  || fail "the app-page probe no longer counts an app's own holdings"
grep -qF 'ForEach(walletSeatItems(all), id: \.name)' Casberi/Casberi/Screens/FeedScreen+WalletPages.swift \
  || fail "Holdings no longer lists the app's own holdings"
grep -qF 'await readCanSpend(addresses: addresses)' Casberi/Casberi/Model/MetaMaskCardBridge.swift \
  || fail "MetaMask Card's sync no longer reads what the card can draw"
grep -qF 'await readCards(token: token, transactions: rows)' Casberi/Casberi/Model/PrivacyBridge.swift \
  || fail "Privacy.com's pass no longer reads its cards"
grep -qF 'await readEscrowed(addresses:' Casberi/Casberi/Model/PeerBridge.swift \
  || fail "Peer's sync no longer reads its escrow"
grep -qF 'SeatHoldingsStore.keep(SeatHoldings.etherFi(' Casberi/Casberi/Model/EtherFiCash.swift \
  || fail "ether.fi's book no longer keeps its Cash accounts"
# A Privacy.com read stays a GET: no card is ever made, closed or funded here.
grep -nE 'POST|httpMethod' Casberi/Casberi/Model/PrivacyBridge.swift | grep -vE '^\s*[0-9]+:\s*///' \
  && fail "PrivacyBridge.swift writes"
# Every new read says what it has not measured (prd §780b).
for f in Casberi/Casberi/Model/PrivacyBridge.swift Casberi/Casberi/Model/PeerBridge.swift \
         Casberi/Casberi/Model/MetaMaskCardBridge.swift; do
  grep -q 'UNMEASURED (prd §780b)' "$f" || fail "$f's new read does not say it is UNMEASURED"
done
echo "  ok   drift guards"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("✗ \(what)"); failures += 1 } }
typealias S = SeatHoldings

// ENS: followed names with their expiry words; an unregistered one is left out.
let ens = S.ens([
    (ref: "ens:name:nick.eth", title: "nick.eth expires 9 Dec 2027", live: true),
    (ref: "ens:name:ghost.eth", title: "ghost.eth — nobody has registered it", live: true),
    (ref: "ens:registered:uma.eth:demo", title: "uma.eth registered", live: true),
    (ref: "ens:name:gone.eth", title: "gone.eth expires 1 Jan 2030", live: false),
    (ref: "ens:name:alpha.eth", title: "alpha.eth", live: true),
])
check(ens.map(\.name) == ["alpha.eth", "nick.eth"], "ENS lists the registered followed names, A–Z: \(ens.map(\.name))")
check(ens.last?.figure == "expires 9 Dec 2027", "ENS keeps the title's expiry words")
check(ens.last?.ref == "ens:name:nick.eth", "an ENS item opens its row")
check(ens.allSatisfy { $0.usd == 0 }, "a name is no money")

// CardPointers: every card its offers name, with the unused ones counted.
let cp = S.cardPointers([
    (card: "Amex Gold", done: false, live: true), (card: "Amex Gold", done: false, live: true),
    (card: "Chase Sapphire", done: false, live: true), (card: "Chase Sapphire", done: true, live: true),
    (card: "Old Card", done: true, live: true), (card: "Gone", done: false, live: false),
])
check(cp.map(\.name) == ["Amex Gold", "Chase Sapphire", "Old Card"], "CardPointers lists every card it tracks: \(cp.map(\.name))")
check(cp.map(\.figure) == ["2 unused offers", "1 unused offer", "No unused offers"], "CardPointers counts the unused offers: \(cp.map(\.figure))")

// Privacy.com: open and paused cards; a monthly limit spends down.
let cards = [
    S.PrivacyCard(token: "a", lastFour: "1111", memo: "Streaming", state: "OPEN", limitCents: 4_000, duration: "MONTHLY"),
    S.PrivacyCard(token: "b", lastFour: "2222", memo: nil, state: "OPEN", limitCents: 1_000, duration: "TRANSACTION"),
    S.PrivacyCard(token: "c", lastFour: "3333", memo: "Closed one", state: "CLOSED", limitCents: 500, duration: "MONTHLY"),
    S.PrivacyCard(token: "d", lastFour: "4444", memo: "Paused one", state: "PAUSED", limitCents: 500, duration: "MONTHLY"),
    S.PrivacyCard(token: "e", lastFour: "5555", memo: "Over", state: "OPEN", limitCents: 1_000, duration: "MONTHLY"),
]
let privacy = S.privacy(cards, spentCents: ["a": 2_298, "e": 5_000])
check(!privacy.contains { $0.name == "Closed one" }, "a closed card is not listed")
check(privacy.first { $0.name == "Streaming" }?.figure == "$17.02 left of $40.00 a month", "a monthly limit spends down: \(privacy.map(\.figure))")
check(privacy.first { $0.name == "Card ending 2222" }?.figure == "$10.00 a purchase", "a per-purchase limit is stated, named by its last four")
check(privacy.first { $0.name == "Paused one" }?.figure == "Paused", "a paused card says so")
check(privacy.first { $0.name == "Over" }?.figure == "$0.00 left of $10.00 a month", "an overspent month never reads negative")
check(privacy.allSatisfy { $0.usd == 0 }, "a limit is no money held")
let raw = S.privacyCard(["token": "t", "last_four": "9", "memo": "", "state": "open", "spend_limit": 0, "spend_limit_duration": "monthly"])
check(raw?.memo == nil && raw?.limitCents == nil && raw?.state == "OPEN", "an empty memo and a zero limit read as none")
check(S.privacyCard(["last_four": "9"]) == nil, "a card with no token is skipped")

// MetaMask Card: the lower of allowance and balance, per token, summed.
check(S.canSpend([(allowance: 1e30, balance: 120), (allowance: 50, balance: 80)]) == 170, "Can spend takes the lower of allowance and balance")
check(S.canSpend([(allowance: 0, balance: 500)]) == 0, "no allowance, nothing to spend")
check(S.metaMask(0).isEmpty, "nothing to spend lists nothing")

// ether.fi: collateral in dollars, what it can borrow in words.
let fi = S.etherFi([(safe: "0x00000000000000000000000000000000000abc12", collateralUSD: 4_148.11, remainingUSD: 398.10)])
check(fi.first?.usd == 4_148.11 && fi.first?.figure == "$398.10 to borrow", "ether.fi states collateral and what it can borrow")
check(fi.first?.name.hasSuffix("...bc12") == true, "a Cash account is named by its tail: \(fi.first?.name ?? "")")

// Peer: free plus locked; dollars only for a dollar stablecoin.
check(S.peerHeld(remaining: 300, outstanding: 200) == 500, "escrow counts what a buyer has locked too")
let peer = S.peer([(id: "7", symbol: "USDC", amount: 500), (id: "8", symbol: "WETH", amount: 0.25), (id: "9", symbol: "USDC", amount: 0)])
check(peer.count == 2, "an empty deposit is not listed")
check(peer.first?.usd == 500 && peer.first?.name == "Deposit #7", "a USDC deposit is dollars")
check(peer.last?.usd == 0 && peer.last?.figure == "0.25 WETH", "an unpriced token is stated as itself: \(peer.last?.figure ?? "")")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   ENS, CardPointers, Privacy.com, MetaMask Card, ether.fi, Peer")
SWIFT

build() { swiftc -Onone -o "$work/run" "$1" "$TAIL" "$work/main.swift" 2>"$work/err" || return 1 }

build "$SRC" || { cat "$work/err"; fail "the shipped source does not compile"; }
"$work/run" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  if build "$work/m.swift" && "$work/run" >/dev/null 2>&1; then
    fail "mutation SURVIVED — $why"
  fi
  echo "  ok   catches  $why"
}

mutate "an unregistered ENS name listed" \
  's/guard !rest\.hasPrefix\("—"\) else \{ return nil \}//'
mutate "a used offer counted as unused" \
  's/unused\[card, default: 0\] \+= row\.done \? 0 : 1/unused[card, default: 0] += 1/'
mutate "a closed Privacy.com card listed" \
  's/cards\.filter \{ \$0\.state == "OPEN" \|\| \$0\.state == "PAUSED" \}/cards.filter { _ in true }/'
mutate "a monthly limit never spends down" \
  's/dollars\(max\(0, limit - spent\)\)/dollars(limit)/'
mutate "Can spend takes the allowance" \
  's/max\(0, min\(\$1\.allowance, \$1\.balance\)\)/max(0, $1.allowance)/'
mutate "escrow counts only what is free" \
  's/remaining \+ outstanding/remaining/'
mutate "an unpriced token stated as dollars" \
  's/let usd = dollarStables\.contains\(symbol\.uppercased\(\)\) \? deposit\.amount : 0/let usd = deposit.amount/'

echo "✓ seat holdings: ENS, CardPointers, Privacy.com, MetaMask Card, ether.fi, Peer — 7 mutations"
