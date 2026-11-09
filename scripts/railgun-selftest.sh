#!/bin/zsh
# Casberi Railgun self-test (prd §1713, §1721, §1723): your private balance
# on Ethereum for every token but ETH and USDC.
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
#   • a screen that reaches your account's send (`RailgunPocket.send(token:`)
#     with any recipient but your own account shows your account paying a
#     stranger (§1721 item 3); a send to someone else is a broadcaster's
#     (`RailgunPocket.send(quote)`), and your account signs nothing in it;
#   • a fee token picked from what the wallet cannot spend, or a check that
#     lets the send and its fee overdraw one token, fails at the broadcaster
#     after the proof, with Face ID already spent;
#   • a relay socket to any host but the three declared ones reaches
#     wherever Waku's peer exchange points (§1723).
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
// §1727: any typed amount moves in at $10 worth or more.
let e18 = "000000000000000000"
check(RailgunRouting.meetsFloor(units: "10" + e18, decimals: 18, price: 1, floorUSD: 10), "$10 of DAI moves in")
check(RailgunRouting.meetsFloor(units: "13250000000000000000", decimals: 18, price: 1, floorUSD: 10), "a typed 13.25 DAI moves in")
check(!RailgunRouting.meetsFloor(units: "7" + e18, decimals: 18, price: 1, floorUSD: 10), "$7 of DAI is under the minimum")
check(!RailgunRouting.meetsFloor(units: "400" + e18, decimals: 18, price: nil, floorUSD: 10), "a token with no price is not offered in")
check(RailgunRouting.meetsFloor(units: "1" + e18, decimals: 18, price: 15, floorUSD: 10), "1 LINK at $15 moves in")
check(!RailgunRouting.meetsFloor(units: "600000000000000000", decimals: 18, price: 15, floorUSD: 10), "0.6 LINK at $15 does not")
check(RailgunRouting.meetsFloor(units: "20000", decimals: 8, price: 60000, floorUSD: 10), "WBTC's eight places")
check(RailgunRouting.nice(0.666) == 1 && RailgunRouting.nice(12) == 20 && RailgunRouting.nice(10) == 10, "nice rounds up to 1, 2, 5")
// §1723: the broadcaster's fee token and the relays.
let weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
let taken = [weth, usdc]
check(RailgunRouting.feeToken(sending: dai, taken: taken, spendable: [dai.lowercased(): 400, usdc.lowercased(): 3]) == usdc, "DAI pays in a token a broadcaster takes and the wallet holds")
check(RailgunRouting.feeToken(sending: weth, taken: taken, spendable: [weth.lowercased(): 1, usdc.lowercased(): 3]) == weth, "a token a broadcaster takes pays its own fee")
check(RailgunRouting.feeToken(sending: dai, taken: taken, spendable: [dai.lowercased(): 400, weth.lowercased(): 0]) == nil, "nothing to pay in is nil, never a token the wallet cannot spend")
check(RailgunRouting.feeToken(sending: dai, taken: [], spendable: [usdc.lowercased(): 3]) == nil, "no broadcaster, no fee token")
check(!RailgunRouting.covers(amount: 1, of: weth, fee: Decimal(string: "0.001")!, in: weth, spendable: [weth.lowercased(): 1]), "a send and its fee in one token cannot overdraw it")
check(RailgunRouting.covers(amount: 400, of: dai, fee: Decimal(string: "0.14")!, in: usdc, spendable: [dai.lowercased(): 400, usdc.lowercased(): 3]), "a send and its fee in two tokens each draw on their own")
check(!RailgunRouting.covers(amount: 400, of: dai, fee: 4, in: usdc, spendable: [dai.lowercased(): 400, usdc.lowercased(): 3]), "a fee the wallet cannot pay is refused before the proof")
let relays = ["rootedinprivacy.com"]
check(RailgunRouting.allowsSocket(URL(string: "wss://relay-a.rootedinprivacy.com:8000/")!, declared: relays), "a declared relay's Waku socket opens")
check(RailgunRouting.allowsSocket(URL(string: "wss://support-1.rootedinprivacy.com:8000/")!, declared: relays), "a relay peer exchange names under the operator's domain opens")
check(!RailgunRouting.allowsSocket(URL(string: "wss://evilrootedinprivacy.com:8000/")!, declared: relays), "a lookalike domain never opens")
check(!RailgunRouting.allowsSocket(URL(string: "ws://relay-a.rootedinprivacy.com:8000/")!, declared: relays), "a plain ws socket never opens")
check(!RailgunRouting.allowsSocket(URL(string: "wss://relay-a.rootedinprivacy.com:9000/")!, declared: relays), "another port never opens")
check(!RailgunRouting.allowsSocket(URL(string: "wss://node-01.waku.org:8000/")!, declared: relays), "a peer Waku found elsewhere never opens")
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
use "$SENT" 'move.toSomeoneElse ? YourAccount.short(move.recipient ?? "") + "." : String(localized: "your account.")' "the recipient is your account, or someone else by their tail"
use "$SENT" 'case .takeBack where toSomeoneElse:' "a send to someone else is the broadcaster's path, before taking back"
# §1727: the amount is typed, the $10 floor holds on what is typed, and
# nothing moves on an amount the line objects to.
use "$SENT" '.keyboardType(.decimalPad)' "the amount is typed on the decimal pad"
use "$SENT" 'if mode == .deposit, !RailgunRouting.meetsFloor(units: units, decimals: h.decimals, price: h.price, floorUSD: Self.floorUSD) {' "a typed amount under \$10 worth does not move in"
use "$SENT" 'guard let picked, amountOK, !DemoMode.isActive else { return }' "nothing runs on an amount the line objects to"
use "$SENT" 'move.stage == .ready && move.amountOK && !DemoMode.isActive' "Send waits on a clear amount"
use "$SENT" 'if let failure = error as? YourAccountChain.Failure { return failure.message }' "your account's own reason is said, never folded into Railgun did not answer"
use "$POCKET" 'RailgunRouting.feeToken(sending: token, taken: taken.map(\.token), spendable: spendable)' "the fee token is the rule's"
use "$POCKET" 'RailgunRouting.covers(amount: wanted, of: token, fee: fee, in: feeToken, spendable: spendable)' "the fee is checked against the wallet before any proof"
use "$ENGINE" 'useDNSDiscovery: false' "the broadcasters are found through the relays only, no DNS discovery"
use "$ENGINE" "if (getAddress(tx.to) !== getAddress(PROXY)) throw Object.assign(new Error(\`broadcast goes to" "a broadcast is Railgun's proxy call and nothing else"
use "$ENGINE" '|| getAddress(p.feeToken) !== q.feeToken || BigInt(p.fee) !== q.fee) {' "the page sends only the send and fee it quoted"
use "Casberi/Casberi/Model/RailgunEngine.swift" 'RailgunRouting.allowsSocket(url, declared: RailgunEngine.broadcasterHosts)' "every relay socket passes the rule"
# §1726: no broadcaster, a fresh sender — its gas your private ETH's, the proof behind Face ID, your account untouched.
body=$(awk '/static func sendFromFresh\(/{on=1} on{print} on && /^    }$/{exit}' "$POCKET")
if [[ -z "$body" ]] || printf '%s' "$body" | grep -q 'YourAccountChain' || ! printf '%s' "$body" | grep -q 'PrivateRootKey.unlock' \
   || ! printf '%s' "$body" | grep -qF 'u.tx.data.lowercased().hasPrefix(FreshTx.railgunTransact)' \
   || ! printf '%s' "$body" | grep -qF 'u.to.lowercased() == to.lowercased()' \
   || ! printf '%s' "$body" | grep -qF 'guard estimate > 0, estimate <= FreshTx.railgunSendGas'; then
  echo "  ✗ a fresh sender's send touches your account, skips Face ID, or sends what it did not check (§1726)"; fail=1
else
  echo "  ✓ a fresh sender's send asks for you, is Railgun's send to the recipient under its gas, your account untouched"
fi
use "$POCKET" 'UserDefaults.standard.set(Int(sender.index - FreshAddress.senderBase) + 1, forKey: senderKey(sender.root))' "each send takes a new fresh sender, counted the moment it is sent"
use "$SENT" 'where [.noFeeToken, .feeTokenPending, .noBroadcaster].contains(failure) {' "no broadcaster, or nothing to pay one in, tries a fresh sender"

# §1725: the relays through Tor on the phone, never a direct socket instead.
use "Casberi/Casberi/Model/RailgunEngine.swift" 'guard let tor = await TorClient.shared.session(isolation: Self.circuit) else { return nil }' "a relay socket rides Tor, or does not open"
use "Casberi/Casberi/Model/RailgunEngine.swift" 'engine?.toPage(socket: id, "error", "Tor did not connect")' "no Tor, no socket: the page hears an error, never a direct socket"
[[ $(grep -c 'try await relaysReady()' Casberi/Casberi/Model/RailgunEngine.swift) == 2 ]] \
  && echo "  ✓ Tor is up before Waku dials, for the broadcasters and the quote" \
  || { echo "  ✗ Waku can dial before Tor is up (§1725)"; fail=1; }

# §1721 item 3: one door to RailgunPocket.send, and its recipient is your account.
# The DEBUG probe (Shell/RailgunEngineProbe.swift, compiled out of Release)
# is the one other caller: it drives the pocket with a test wallet's own money.
grep -q '^#if DEBUG' Casberi/Casberi/Shell/RailgunEngineProbe.swift \
  || { echo "  ✗ the Railgun probe is no longer DEBUG-only"; fail=1; }
calls=$(grep -rn 'RailgunPocket\.send(token:' Casberi/Casberi/Screens Casberi/Casberi/Shell | grep -v 'RailgunEngineProbe.swift' | grep -v '^\S*:\s*///' || true)
count=$(printf '%s\n' "$calls" | grep -c 'RailgunPocket\.send(token:' || true)
if [[ "$count" != "1" ]] || ! printf '%s' "$calls" | grep -qF 'to: account)'; then
  echo "  ✗ a screen reaches your account's Railgun send other than taking back to your account (§1721 item 3)"
  printf '%s\n' "$calls"
  fail=1
else
  echo "  ✓ your account sends from Railgun only to your account"
fi
# §1723: the broadcaster's send asks for you and signs nothing with your account.
body=$(awk '/static func send\(_ q: RailgunEngineWire.Quote\)/{on=1} on{print} on && /^    }$/{exit}' "$POCKET")
if [[ -z "$body" ]] || printf '%s' "$body" | grep -q 'YourAccountChain' || ! printf '%s' "$body" | grep -q 'PrivateRootKey.unlock'; then
  echo "  ✗ the broadcaster's send touches your account, or does not ask for you first (§1723)"; fail=1
else
  echo "  ✓ a send to someone else asks for you and your account signs nothing"
fi
use "$SENT" 'guard let account = YourAccountKey.address else' "the take-back recipient is your account's address"
# §1724: what a fresh address is paid moves into Railgun, its shield your engine's.
FRESH="Casberi/Casberi/Model/FreshReceive.swift"
use "$FRESH" 'await lookRailgunTokens(entry, eth: balance, network: network, interactive: force, context: context)' "a fresh address's other tokens are looked at once ETH and USDC are not there"
use "$FRESH" 'prepared.token.lowercased() == token.contract,' "the shield is of the token that arrived"
use "$FRESH" 'PrivateMoney.decimal(hex: prepared.amount) == held,' "the shield is of exactly what arrived"
use "$FRESH" 'guard estimate > 0, estimate <= FreshTx.railgunShieldGas else { throw FreshFailure.gas(estimate) }' "a shield over its gas budget is refused"
use "$FRESH" 'guard interactive, spendable >= cost else {' "private ETH pays the gas only while you look"

# §1728: dollars, under the floor, ready early, one cost.
MOVEF="Casberi/Casberi/Screens/MoveRailgunPrivate.swift"
HOLD="Casberi/Casberi/Model/RailgunHoldings.swift"
use "Casberi/Casberi/Model/MoveWarm.swift" 'RailgunHoldings.shared.warm()' "the Wallet opening syncs your Railgun wallet"
warm=$(awk '/func warm\(\) \{/{on=1} on{print} on && /^    }$/{exit}' "$HOLD")
if [[ -z "$warm" ]] || ! printf '%s' "$warm" | grep -q 'await GestureGate.idle()' \
   || ! printf '%s' "$warm" | grep -q 'RailgunPocket.hasWallet' || ! printf '%s' "$warm" | grep -q 'DemoMode.isActive'; then
  echo "  ✗ the warm sync does not wait for a still hand, or runs with no wallet or in the demo (§1728 item 3)"; fail=1
else
  echo "  ✓ the warm sync waits for a still hand, needs a wallet, never runs in the demo"
fi
use "$POCKET" 'if let running { return try await running.value }' "a quote joins a sync already running, never a second"
use "$MOVEF" 'NSDecimalRound(&up, &tokens, min(h.decimals, 6), .up)' "the \$10 chip rounds up, so it never falls short of the floor"
use "$MOVEF" 'if usd >= 0.01, usd > (underFloor?.usd ?? 0) { underFloor = Short(symbol: h.token.symbol, usd: usd) }' "under the floor, the sentence names the token worth the most"
use "$MOVEF" 'guard let gas = gasUSD(RailgunPocket.unshieldGas, plus: RailgunPocket.lastRelayerFeeWei ?? 0) else { return nil }' "a fresh sender's cost counts the relayer's fee"
use "$MOVEF" 'guard let feeWords, let feeUSD = broadcasterFeeUSD else { return nil }' "a broadcaster's cost is its quoted fee, priced"

if (( fail )); then echo "railgun-selftest: FAILED"; exit 1; fi
echo "railgun-selftest: ok"
