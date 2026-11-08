#!/bin/zsh
# Casberi Railgun self-test (prd §1713, §1721): your private balance on
# Ethereum for every token but ETH and USDC.
#
#   Casberi/Casberi/Model/RailgunRouting.swift   (compiled whole, unmodified)
#   Casberi/Casberi/Model/RailgunPocket.swift     (the calls it may send)
#   Casberi/Casberi/Model/RailgunHoldings.swift   (what the screens read)
#   Casberi/Casberi/Screens/MoveRailgunPrivate.swift, MoveSentence.swift
#
# WHY A HARNESS. Every failure here looks like a working wallet:
#
#   • a routing rule that lets USDC or ETH into Railgun moves money into the
#     wrong pool with no error, and one that lets DAI into Privacy Pools
#     fails only at the deposit;
#   • a missing floor shields a dollar for a dollar's fees, and a token with
#     no price gets a floor of zero;
#   • a Safe unshield written as the SDK's EIP-7702 form, or to a contract
#     that is not the proxy, signs something nobody reviewed;
#   • a Private block drawn from what Casberi routed, not from the engine's
#     balances, hides a token someone else shielded to you (item 4);
#   • a screen that reaches `RailgunPocket.send` with any recipient but your
#     own account shows your account paying a stranger (§1721 item 3).
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROUTE="Casberi/Casberi/Model/RailgunRouting.swift"
POCKET="Casberi/Casberi/Model/RailgunPocket.swift"
HOLD="Casberi/Casberi/Model/RailgunHoldings.swift"
SENT="Casberi/Casberi/Screens/MoveRailgunPrivate.swift"
MOVE="Casberi/Casberi/Screens/MoveSentence.swift"
PRIV="Casberi/Casberi/Screens/FeedScreen+WalletPrivate.swift"
INGEST="Casberi/Casberi/Model/WalletIngest.swift"
ENGINE="tools/railgun-engine/src/engine.js"

fail=0
use() {   # file, literal, message
  if ! grep -qF -- "$2" "$1"; then echo "  ✗ $3"; fail=1; else echo "  ✓ $3"; fi
}

echo "railgun-selftest: the rule, compiled"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var bad = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  ✓ \(what)" : "  ✗ \(what)"); if !ok { bad += 1 } }
let dai = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
check(RailgunRouting.goesToRailgun(symbol: "DAI", contract: dai, chainId: 1), "DAI on Ethereum goes to Railgun")
check(!RailgunRouting.goesToRailgun(symbol: "USDC", contract: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", chainId: 1), "USDC on Ethereum never goes to Railgun")
check(!RailgunRouting.goesToRailgun(symbol: "ETH", contract: nil, chainId: 1), "ETH never goes to Railgun")
check(!RailgunRouting.goesToRailgun(symbol: "WETH", contract: nil, chainId: 1), "a token with no contract never goes to Railgun")
check(!RailgunRouting.goesToRailgun(symbol: "DAI", contract: dai, chainId: 8453), "nothing off Ethereum goes to Railgun")
// $10 floor at $1 a DAI, 18 decimals, 400 held: 10, 20, 50, 100, then all.
let e18 = "000000000000000000"
let held = "400" + e18
let steps = RailgunRouting.ladder(decimals: 18, held: held, price: 1, floorUSD: 10)
check(steps.map(\.units) == ["10" + e18, "20" + e18, "50" + e18, "100" + e18, held], "DAI moves in from $10, then all of it")
check(steps.last?.all == true && steps.dropLast().allSatisfy { !$0.all }, "only the last step is all of it")
check(RailgunRouting.ladder(decimals: 18, held: held, price: nil, floorUSD: 10).isEmpty, "a token with no price is not offered in")
check(RailgunRouting.ladder(decimals: 18, held: "5" + e18, price: 1, floorUSD: 10).isEmpty, "less than $10 worth is not offered in")
// LINK at $15: $10 is 0.666…, rounded up to 1.
let link = RailgunRouting.ladder(decimals: 18, held: "3" + e18, price: 15, floorUSD: 10)
check(link.first?.units == "1" + e18, "the floor rounds up to 1, 2 or 5 of its power of ten")
// Taking back: no floor, all of it always, priced or not.
check(RailgunRouting.ladder(decimals: 18, held: "6" + "00000000000000000", price: nil, floorUSD: nil).map(\.all) == [true], "taking back offers all of it with no price")
check(RailgunRouting.ladder(decimals: 18, held: "4" + e18, price: 1, floorUSD: nil).last?.units == "4" + e18, "taking back always ends on all of it")
check(RailgunRouting.nice(0.666) == 1 && RailgunRouting.nice(12) == 20 && RailgunRouting.nice(10) == 10, "nice rounds up to 1, 2, 5")
check(RailgunRouting.nextNice(1) == 2 && RailgunRouting.nextNice(2) == 5 && RailgunRouting.nextNice(5) == 10, "the next step is 1, 2, 5, 10")
exit(bad == 0 ? 0 : 1)
SWIFT
if ! xcrun swiftc -O -o "$TMP/rule" "$ROUTE" "$TMP/main.swift" 2> "$TMP/err"; then
  cat "$TMP/err"; echo "  ✗ RailgunRouting.swift no longer compiles alone"; exit 1
fi
"$TMP/rule" || fail=1

echo "railgun-selftest: the wiring"
use "$POCKET" 'u.tx.to.lowercased() == proxy, u.type != 4, u.delegate == nil' "a Safe unshield is the proxy's plain call, never type 4 (§1713 item 3)"
use "$POCKET" 'prepareUnshield(token: token, amount: hexAmount, to: to, forSafe: true)' "the unshield is prepared for a Safe"
use "$POCKET" 'approve.data.lowercased() == approveCall(amount: hexAmount)' "a shield asks the exact approval and nothing more"
use "$ENGINE" 'casberi railgun shield v1' "the shield key is derived from Casberi's own string (§1713 item 3)"
use "$HOLD" 'for b in synced.balances {' "the Private block reads the engine's balances, not the routing (§1713 item 4)"
use "$HOLD" 'RailgunPocket.hasWallet' "no root is made just to read (§1721 item 1)"
use "$INGEST" 'await RailgunHoldings.shared.walletHolding()' "Railgun counts in the Wallet's number"
use "$PRIV" 'walletRailgunRows(mask: mask)' "Holdings draws Railgun's rows in Private"
use "$PRIV" 'String(localized: "Private in about an hour")' "a shield in screening reads as a state (§1713 item 5)"
use "$MOVE" 'RailgunRouting.goesToRailgun(symbol: held.token.symbol, contract: held.token.contract, chainId: network.chainId)' "Your private balance · Ethereum routes by the picked token"
use "$SENT" 'MovePhrase(String(localized: "your account."), glue: String(localized: "to"))' "taking back says your account and nothing else"

# §1721 item 3: one door to RailgunPocket.send, and its recipient is your account.
# The DEBUG probe (Shell/RailgunEngineProbe.swift, compiled out of Release)
# is the one other caller: it drives the pocket with a test wallet's own money.
grep -q '^#if DEBUG' Casberi/Casberi/Shell/RailgunEngineProbe.swift \
  || { echo "  ✗ the Railgun probe is no longer DEBUG-only"; fail=1; }
calls=$(grep -rn 'RailgunPocket\.send(' Casberi/Casberi/Screens Casberi/Casberi/Shell | grep -v 'RailgunEngineProbe.swift' | grep -v '^\S*:\s*///' || true)
count=$(printf '%s\n' "$calls" | grep -c 'RailgunPocket\.send(' || true)
if [[ "$count" != "1" ]] || ! printf '%s' "$calls" | grep -qF 'to: account)'; then
  echo "  ✗ a screen reaches RailgunPocket.send other than taking back to your account (§1721 item 3)"
  printf '%s\n' "$calls"
  fail=1
else
  echo "  ✓ one screen sends from Railgun, to your account"
fi
use "$SENT" 'guard let account = YourAccountKey.address else' "the take-back recipient is your account's address"

if (( fail )); then echo "railgun-selftest: FAILED"; exit 1; fi
echo "railgun-selftest: ok"
