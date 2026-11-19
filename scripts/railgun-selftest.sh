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
[[ $(grep -c 'try await relaysReady()' Casberi/Casberi/Model/RailgunEngine.swift) == 4 ]] \
  && echo "  ✓ Tor is up before Waku dials, for the broadcasters and every quote (§1875, §1877)" \
  || { echo "  ✗ Waku can dial before Tor is up (§1725)"; fail=1; }

# §1721 item 3: one door to RailgunPocket.send, and its recipient is your account.
# The DEBUG probe (Shell/RailgunEngineProbe.swift, compiled out of Release)
# is the one other caller: it drives the pocket with a test wallet's own money.
grep -q '^#if DEBUG' Casberi/Casberi/Shell/RailgunEngineProbe.swift \
  || { echo "  ✗ the Railgun probe is no longer DEBUG-only"; fail=1; }
calls=$(grep -rn 'RailgunPocket\.send(token:' Casberi/Casberi/Screens Casberi/Casberi/Shell | grep -v 'RailgunEngineProbe.swift' | grep -v '^\S*:\s*///' || true)
count=$(printf '%s\n' "$calls" | grep -c 'RailgunPocket\.send(token:' || true)
if [[ "$count" != "1" ]] || ! printf '%s' "$calls" | grep -qE 'to: account[,)]'; then
  echo "  ✗ a screen reaches your account's Railgun send other than taking back to your account (§1721 item 3)"
  printf '%s\n' "$calls"
  fail=1
else
  echo "  ✓ your account sends from Railgun only to your account"
fi
# §1723: the broadcaster's send asks for you and signs nothing with your account.
body=$(awk '/static func send\(_ q: RailgunEngineWire.Quote/{on=1} on{print} on && /^    }$/{exit}' "$POCKET")
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

use "$MOVEF" "PrivateStepRows(run: run, confirmed: move.unlockedFirst" "the steps stand in Move's foot, Aztec's rows (§1728 item 5)"
use "$MOVEF" "steps.fail(Self.words(error))" "a failure stays on the step it reached"
use "$MOVEF" "steps.begin(.move, plan: .signed(.ethereum))" "a move-in's rows are signed, as Aztec's Shield deposit's"
use "Casberi/Casberi/Model/RailgunEngine.swift" 'PrivateSendSteps.shared.mark(key, from: .railgun)' "the engine's step lines move the rows"
[[ $(grep -c "say('step proving')" "$ENGINE") == 7 && $(grep -c "say('step sent')" "$ENGINE") == 3 ]] \
  && echo "  ✓ every proof says it starts, and the broadcaster's hand-over says it left" \
  || { echo "  ✗ a Railgun proof or hand-over no longer says its step (§1728 item 5)"; fail=1; }
grep -q "step proving" Casberi/Casberi/Resources/railgun-engine.js \
  && echo "  ✓ the bundled engine carries the step lines" \
  || { echo "  ✗ the bundled engine was not rebuilt with the step lines"; fail=1; }

# §1875: a swap inside your private balance, through the CLASSIC relay adapter only.
echo "railgun-selftest: the private swap (§1875)"
SWAP="Casberi/Casberi/Model/RailgunSwap.swift"
mkdir -p "$TMP/swap"
cat > "$TMP/swap/stubs.swift" <<'SWIFT'
import Foundation
enum SafeABI {
    static func word(uint256 s: String) -> [UInt8]? {
        guard let d = Decimal(string: s), s.allSatisfy(\.isNumber) else { return nil }
        var n = d, out = [UInt8](repeating: 0, count: 32), i = 31
        while n > 0, i >= 0 {
            var q = n / 256, f = Decimal(); NSDecimalRound(&f, &q, 0, .down)
            let r = n - f * 256
            out[i] = UInt8(NSDecimalNumber(decimal: r).intValue); n = f; i -= 1
        }
        return out
    }
    static func word(address a: String) -> [UInt8]? {
        let h = a.lowercased().replacingOccurrences(of: "0x", with: "")
        guard h.count == 40 else { return nil }
        var b = [UInt8](repeating: 0, count: 12), idx = h.startIndex
        while idx < h.endIndex { let n = h.index(idx, offsetBy: 2); b.append(UInt8(h[idx..<n], radix: 16)!); idx = n }
        return b
    }
    static func hex(_ b: [UInt8]) -> String { "0x" + b.map { String(format: "%02x", $0) }.joined() }
}
enum YourAccountSwap {
    struct Call: Equatable { let to: String; let value: String; let data: [UInt8] }
    static let approveSelector: [UInt8] = [0x09, 0x5e, 0xa7, 0xb3]
    static let transferSelector: [UInt8] = [0xa9, 0x05, 0x9c, 0xbb]
    static func routers(_ c: Int) -> Set<String> { ["0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45"] }
}
enum RailgunEngineWire { struct Swap { struct Call { let to: String; let data: String } } }
SWIFT
cat > "$TMP/swap/main.swift" <<'SWIFT'
import Foundation
var bad = 0
func check(_ ok: Bool, _ what: String) { if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); bad += 1 } }
let dai = "0x6b175474e89094c44da98b954eedeac495271d0f"
let router = "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45"
let adapter = "0xac9f360ae85469b27aeddeafc579ef2d052ad405"
check(RailgunSwap.fee("400000000000000000000", bps: 25) == "1000000000000000000", "Railgun keeps 0.25% of 400 DAI: 1 DAI")
check(RailgunSwap.afterFee("400000000000000000000", bps: 25) == "399000000000000000000", "399 DAI reaches the adapter")
check(RailgunSwap.fee("399", bps: 25) == "0", "the fee rounds down, as the contract does")
check(RailgunSwap.afterFee("0", bps: 25) == nil && RailgunSwap.afterFee("1e18", bps: 25) == nil, "nothing, or no whole number, is no swap")
let net = "399000000000000000000"
let hand = YourAccountSwap.Call(to: dai, value: "0",
    data: YourAccountSwap.approveSelector + SafeABI.word(address: router)! + SafeABI.word(uint256: net)!)
let swap = YourAccountSwap.Call(to: router, value: "0", data: [0x5a, 0xe4, 0x01, 0xdc] + SafeABI.word(address: adapter)! + [1, 2, 3])
check(RailgunSwap.checked([hand, swap], sell: dai, amount: net, adapter: adapter), "an exact approval then the router, paying the adapter, passes")
let elsewhere = YourAccountSwap.Call(to: router, value: "0", data: [0x5a, 0xe4, 0x01, 0xdc] + SafeABI.word(address: "0x000000000000000000000000000000000000dead")! )
check(!RailgunSwap.checked([hand, elsewhere], sell: dai, amount: net, adapter: adapter), "a router call paying anyone but the adapter is refused")
let more = YourAccountSwap.Call(to: dai, value: "0",
    data: YourAccountSwap.approveSelector + SafeABI.word(address: router)! + SafeABI.word(uint256: "400000000000000000000")!)
check(!RailgunSwap.checked([more, swap], sell: dai, amount: net, adapter: adapter), "an approval of more than reaches the adapter is refused")
let stranger = YourAccountSwap.Call(to: "0x1111111111111111111111111111111111111111", value: "0", data: swap.data)
check(!RailgunSwap.checked([hand, stranger], sell: dai, amount: net, adapter: adapter), "a router not in Ethereum's book is refused")
let paid = YourAccountSwap.Call(to: router, value: "1", data: swap.data)
check(!RailgunSwap.checked([hand, paid], sell: dai, amount: net, adapter: adapter), "a call carrying ETH is refused")
check(!RailgunSwap.checked([hand, swap, swap], sell: dai, amount: net, adapter: adapter), "a third call is refused")
check(!RailgunSwap.checked([hand, swap], sell: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", amount: net, adapter: adapter), "an approval on another token than the one sold is refused")
if bad > 0 { exit(1) }
SWIFT
if ! xcrun swiftc -O -o "$TMP/swap/run" "$SWAP" "$TMP/swap/stubs.swift" "$TMP/swap/main.swift" 2> "$TMP/swap/err"; then
  echo "  ✗ RailgunSwap.swift does not compile alone"; cat "$TMP/swap/err" | head -20; fail=1
elif ! "$TMP/swap/run"; then fail=1; fi
[[ $(grep -c 'getAddress(RELAY_ADAPT)' "$ENGINE") -ge 3 ]] \
  && echo "  ✓ every swap transaction must go to the classic relay adapter" \
  || { echo "  ✗ a swap transaction is no longer held to the classic relay adapter"; fail=1; }
grep -q "7702" <(grep -E "^import|from '@railgun-community/wallet'|CrossContractCalls7702" "$ENGINE") \
  && { echo "  ✗ the engine imports a 7702 cross-contract call: its shield may wait the hour"; fail=1; } \
  || echo "  ✓ the engine never imports the 7702 relay adapter's calls"
use "$ENGINE" "q.selected.tokenFee.feesID,
      CHAIN, populated.nullifiers ?? [], q.gasPrice, true," "the broadcaster is told the swap goes through the relay adapter"
use "$ENGINE" "const selected = pickBroadcaster(feeToken, true);" "a swap's broadcaster is one that carries relay-adapt sends"
use "$POCKET" "guard RailgunSwap.checked(quote.calls, sell: sellToken, amount: net, adapter: adapter)," "every swap's calls are checked before anything is proved"
use "$POCKET" "YourAccountChain.swapQuote(accountNetwork, sell: sell, buy: buy, amount: net, account: adapter)" "the route sells what reaches the adapter, the adapter receiving"
swaprun=$(awk '/case \.swap where viaFresh:/{on=1} on&&/case \.takeBack:/{exit} on' "$MOVEF")
if [[ -z "$swaprun" ]] || printf '%s' "$swaprun" | grep -q "RailgunPocket.send(token:" \
   || ! printf '%s' "$swaprun" | grep -q "RailgunPocket.swap(plan" || ! printf '%s' "$swaprun" | grep -q "RailgunPocket.swapFromFresh(plan"; then
  echo "  ✗ a private swap reaches your account's send"; fail=1
else
  echo "  ✓ a private swap never goes through your account"
fi
grep -q "quoteSwap" Casberi/Casberi/Resources/railgun-engine.js \
  && echo "  ✓ the bundled engine carries the swap" \
  || { echo "  ✗ the bundled engine was not rebuilt with the swap"; fail=1; }

# §1877: a send to someone's private balance stays inside Railgun; Receive shows your private address.
echo "railgun-selftest: the private send (§1877)"
use "$ENGINE" "if (!validateRailgunAddress(to)) throw" "a private send goes only to a private address the SDK accepts"
use "$ENGINE" "if (to === getRailgunAddress(walletID)) throw" "never to your own private address"
[[ $(grep -c "getAddress(tx.to) !== getAddress(PROXY)\|getAddress(transaction.to) !== getAddress(PROXY)" "$ENGINE") -ge 3 ]] \
  && echo "  ✓ every private send is a transaction to Railgun's proxy" \
  || { echo "  ✗ a private send's transaction is no longer held to Railgun's proxy"; fail=1; }
use "$ENGINE" "generateTransferProof(V2, NETWORK, walletID, encryptionKey, false," "the receiver is never shown who sent it"
use "$POCKET" "guard RailgunSwap.isPrivateAddress(to)" "the pocket refuses anything but a private address"
privrun=$(awk '/case \.takeBack where toPrivate && viaFresh:/{on=1} on&&/case \.takeBack where toSomeoneElse && viaFresh:/{exit} on' "$MOVEF")
if [[ -z "$privrun" ]] || printf '%s' "$privrun" | grep -q "RailgunPocket.send(token:" \
   || ! printf '%s' "$privrun" | grep -q "RailgunPocket.transfer(plan" || ! printf '%s' "$privrun" | grep -q "RailgunPocket.transferFromFresh(plan"; then
  echo "  ✗ a send to a private address reaches your account, or leaves Railgun"; fail=1
else
  echo "  ✓ a send to a private address stays inside Railgun, carried by a broadcaster or a fresh sender"
fi
mkdir -p "$TMP/addr"
cat > "$TMP/addr/main.swift" <<'SWIFT'
import Foundation
var bad2 = 0
func check2(_ ok: Bool, _ what: String) { if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); bad2 += 1 } }
let good = "0zk1qyqrw8a5h9mc0tk3n6fz2l4s7vxj9uq8e5pd3rjkm6g2wa0tyz4h7cxs9ld3unv8kq2fe6mrx5pa4w0jg7t3yhs9cvz2lm8dq6rkue0xan5tw3pfy8hg4jv7f3a"
check2(RailgunSwap.isPrivateAddress(good), "a 127-character 0zk address is private")
check2(!RailgunSwap.isPrivateAddress(String(good.dropLast())), "one character short is not")
check2(!RailgunSwap.isPrivateAddress(good.replacingOccurrences(of: "q6r", with: "qbr")), "a character outside bech32 is not")
check2(!RailgunSwap.isPrivateAddress("0x8ba1f109551bd432803012645ac136ddd64dba72"), "a public address is not")
if bad2 > 0 { exit(1) }
SWIFT
if ! xcrun swiftc -O -o "$TMP/addr/run" "$SWAP" "$TMP/swap/stubs.swift" "$TMP/addr/main.swift" 2> "$TMP/swap/err2"; then
  echo "  ✗ the private address check does not compile"; head -10 "$TMP/swap/err2"; fail=1
elif ! "$TMP/addr/run"; then fail=1; fi
use "Casberi/Casberi/Screens/MoveFreshReceive.swift" "privateAddress = try await RailgunPocket.privateAddress()" "Receive reads your private address from your own wallet"
grep -q "broadcastTransfer" Casberi/Casberi/Resources/railgun-engine.js \
  && echo "  ✓ the bundled engine carries the private send" \
  || { echo "  ✗ the bundled engine was not rebuilt with the private send"; fail=1; }

# §1885: the first sync says so and how far it is; a swap is said as swapped.
echo "railgun-selftest: the first sync and a swap's words (§1885)"
use "$POCKET" "RailgunSync.shared.firstTime = opened.keptLeaves == 0" "the first sync is known by the engine's kept leaves"
use "Casberi/Casberi/Model/RailgunEngine.swift" 'if line.hasPrefix("progress ") { RailgunSync.shared.heard(line) }' "Railgun's own scan progress reaches the row"
use "Casberi/Casberi/Screens/PrivateStepRows.swift" ".onChange(of: railgunSync.firstReady)" "a first sync that finishes says so in a toast"
use "$MOVEF" "self?.started(Self.swapStepsPlan, away: true)" "a swap's steps say swapping and swapped, never sent"
use "$MOVEF" "self?.started(Self.swapFreshPlan, away: true)" "a new address's swap says it pays gas from your private ETH, never Checking"
use "Casberi/Casberi/Model/FreshTx.swift" "if t == railgunRelayAdapt { return d.hasPrefix(railgunRelay) && carried.isEmpty }" "a new address of yours may send a private swap: the classic adapter's relay, no ETH"
grep -q 'railgunRelayAdapt = "0xac9f360ae85469b27aeddeafc579ef2d052ad405"' Casberi/Casberi/Model/FreshTx.swift \
  && echo "  ✓ that adapter is the classic one, never its 7702 twin" \
  || { echo "  ✗ the new address's swap is not held to the classic relay adapter"; fail=1; }
use "$MOVEF" "RailgunHoldings.shared.afterMove()" "a move done reads the private balance again as it lands (§1887)"
use "Casberi/Casberi/Model/RailgunHoldings.swift" "for wait in [20, 45, 90, 180, 300] {" "the re-reads wait for the block and the screening node, five at most"
use "tools/railgun-engine/src/engine.js" "      await syncTxidTree();" "the sync ties our own transactions to their notes before the proofs we owe"
use "tools/railgun-engine/src/engine.js" "if (validated == null || after >= validated || (round > 0 && after === before)) return;" "a TXID tree stuck short of the screening node fills its missing unshields, and stops when that does not move it"
use "Casberi/Casberi/Screens/FeedScreen+Actions.swift" "Task { await RailgunHoldings.shared.refresh(force: true) }" "a pull on the Wallet forces Railgun's read"
use "tools/railgun-engine/src/engine.js" "const r = indexedDB.open('casberi-railgun-artifacts', 1);" "Railgun's proving files are kept on this phone (§1891)"
use "tools/railgun-engine/src/engine.js" "if (!/Timed out downloading artifact/i.test(String(e?.message))) throw e;" "a slow download proves once more, nothing else does"
[[ $(grep -c "await proving(() => generate" tools/railgun-engine/src/engine.js) -ge 7 ]] && echo "  ✓ every proof waits out a slow download" || { echo "  ✗ a proof skips the slow-download retry"; fail=1; }
use "tools/railgun-engine/src/engine.js" "if (broadcaster) refusedBroadcasters.add(broadcaster);" "a broadcaster that refused is passed over"
use "tools/railgun-engine/src/engine.js" "const REFUSED_FOR = 7 * 86400 * 1000;" "and for a week, not a launch"
[[ $(grep -c "const selected = pickBroadcaster(feeToken" tools/railgun-engine/src/engine.js) -eq 3 ]] && echo "  ✓ every broadcast picks past a refusal" || { echo "  ✗ a broadcast picks a broadcaster that refused"; fail=1; }
use "Casberi/Casberi/Screens/MoveRailgunPrivate.swift" '"BroadcastRefused"' "a refusal says nothing was sent"
if (( fail )); then echo "railgun-selftest: FAILED"; exit 1; fi
echo "railgun-selftest: ok"
