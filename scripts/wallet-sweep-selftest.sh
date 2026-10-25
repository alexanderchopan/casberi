#!/bin/zsh
# Wallet-sweep self-test (prd §1506) — Receive › From another wallet: what a
# wallet of your own elsewhere sends to your account, and what stays:
#
#   Casberi/Casberi/Model/WalletSweep.swift   compiled WHOLE and unmodified
#
# The failures that cost money, each one silent until a wallet refuses or a
# coin is lost:
#
#   • THE NETWORK'S OWN COIN SENT WHOLE. The wallet cannot pay for the sends
#     after it, or the last one fails: it must go last and leave the gas.
#   • A TOKEN SENT WITH NO COIN FOR GAS. The wallet refuses every one.
#   • A COIN SENT TO RELAY THAT RELAY DOES NOT BRIDGE, or under its floor.
#     A deposit address takes one route; anything else can be lost.
#   • CALLDATA WRONG BY ONE WORD. `transfer` to the wrong address, or an
#     amount read as hex twice.
#   • A HEX QUANTITY ROUNDED. `Decimal` is exact to 38 digits only.
#
# Pure, local, deterministic — no network, no simulator, no key.
set -euo pipefail
cd "$(dirname "$0")/.."

SWEEP="Casberi/Casberi/Model/WalletSweep.swift"
[[ -f "$SWEEP" ]] || { echo "✗ $SWEEP not found"; exit 1; }
TMP=$(mktemp -d /tmp/wallet-sweep-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
typealias S = WalletSweep
func h(_ chain: Int, _ symbol: String, _ contract: String?, _ raw: String, _ usd: Double, decimals: Int = 18) -> S.Holding {
    .init(chainId: chain, networkName: "n\(chain)", symbol: symbol, contract: contract, decimals: decimals, raw: raw, usd: usd)
}
let usdc = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
let arbUSDT = "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9"
let me = "0x1111111111111111111111111111111111111111"
let you = "0x2222222222222222222222222222222222222222"
let gwei: Decimal = 1_000_000_000

// ── Base units ───────────────────────────────────────────────────────────
check(S.hexQuantity("0") == "0x0", "zero is 0x0")
check(S.hexQuantity("255") == "0xff", "255 is 0xff")
check(S.hexQuantity("1000000000000000000") == "0xde0b6b3a7640000", "one ETH in wei, exactly")
check(S.decimal(fromHex: "0xde0b6b3a7640000") == "1000000000000000000", "hex back to decimal, exactly")
check(S.decimal(fromHex: "0x0") == "0", "0x0 is zero")
check(S.decimal(fromHex: "0x" + String(repeating: "f", count: 40)) == nil, "past 38 digits is refused, never rounded")
check(S.uint256Word("1")?.count == 64 && S.uint256Word("1")?.hasSuffix("01") == true, "a word is 64 hex digits")
check(S.hexQuantity("12.5") == nil, "a fraction is not base units")

// ── Calldata ─────────────────────────────────────────────────────────────
let data = S.transferData(to: you, amount: "1000000")
check(data == "0xa9059cbb" + String(repeating: "0", count: 24) + String(you.dropFirst(2))
      + String(repeating: "0", count: 59) + "f4240", "transfer(address,uint256): selector, address word, amount word")
let tokenLeg = S.Leg(holding: h(8453, "USDC", usdc, "1000000", 1, decimals: 6), amount: "1000000", usd: 1, way: .direct)
let tx = S.transaction(tokenLeg, from: me, to: you)
check(tx?["to"] == usdc && tx?["value"] == "0x0" && tx?["from"] == me, "a token send goes to the token contract, no value")
let ethLeg = S.Leg(holding: h(8453, "ETH", nil, "5000", 1), amount: "4096", usd: 1, way: .direct)
check(S.transaction(ethLeg, from: me, to: you) == ["from": me, "to": you, "data": "0x", "value": "0x1000"],
      "the coin's own send carries the amount as value")
check(S.transaction(ethLeg, from: me, to: "0x12") == nil, "a malformed address asks for nothing")
let relayLeg = S.Leg(holding: h(42161, "USDT", arbUSDT, "9000000", 9, decimals: 6), amount: "9000000", usd: 9,
                     way: .relay(address: "0x3333333333333333333333333333333333333333", arrives: "USDC"))
check(S.destination(relayLeg, account: you) == "0x3333333333333333333333333333333333333333", "a Relay leg goes to its deposit address")
check(S.destination(tokenLeg, account: you) == you, "a direct leg goes to your account")

// ── The plan ─────────────────────────────────────────────────────────────
let holdings = [
    h(8453, "ETH", nil, "100000000000000000", 400),          // 0.1 ETH on Base
    h(8453, "USDC", usdc, "120000000", 120, decimals: 6),
    h(8453, "DUST", "0x4444444444444444444444444444444444444444", "1", 0.2),
    h(42161, "USDT", arbUSDT, "9000000", 9, decimals: 6),
    h(42161, "ETH", nil, "50000000000000000", 200),          // 0.05 ETH on Arbitrum
    h(42161, "ODD", "0x5555555555555555555555555555555555555555", "1", 50),
    h(10, "OP", "0x4200000000000000000000000000000000000042", "1000", 30),  // no ETH on Optimism
]
let relayable: (Int, String?) -> Bool = { chain, contract in
    contract == nil || contract == arbUSDT || contract == "0x4200000000000000000000000000000000000042"
}
let plan = S.plan(holdings, yours: [8453], relayable: relayable, gasPrice: [8453: gwei / 100, 42161: gwei / 100, 10: gwei / 100])
let ids = plan.legs.map(\.holding.symbol)
check(ids == ["USDC", "ETH", "USDT", "ETH"], "your network first, tokens before the coin, then the next network: \(ids)")
check(plan.legs[1].amount != "100000000000000000" && (Decimal(string: plan.legs[1].amount) ?? 0) > 0,
      "the coin's own send leaves the gas behind")
let reserve = Decimal(string: "100000000000000000")! - Decimal(string: plan.legs[1].amount)!
check(reserve >= S.ethFloorWei, "an ETH network keeps at least the L1-fee floor")
check(plan.stays.contains { $0.0.symbol == "DUST" && $0.1 == .tooSmall }, "dust stays, named")
check(plan.stays.contains { $0.0.symbol == "ODD" && $0.1 == .noRoute }, "a coin Relay does not bridge is never sent to a deposit address")
check(plan.stays.contains { $0.0.symbol == "OP" && $0.1 == .noGas }, "a network with no coin for gas sends nothing")
check(abs(plan.totalUSD - (120 + plan.legs[1].usd + 9 + plan.legs[3].usd)) < 0.001, "the total is what moves")

let small = S.plan([h(42161, "USDT", arbUSDT, "3000000", 3, decimals: 6), h(42161, "ETH", nil, "50000000000000000", 200)],
                   yours: [8453], relayable: relayable, gasPrice: [42161: gwei / 100])
check(small.stays.contains { $0.0.symbol == "USDT" && $0.1 == .tooSmall }, "under Relay's floor stays (prd §1485)")
let gasless = S.plan([h(8453, "USDC", usdc, "120000000", 120, decimals: 6)], yours: [8453], relayable: relayable, gasPrice: [8453: gwei / 100])
check(gasless.legs.isEmpty && gasless.stays.first?.1 == .noGas, "a token with no coin for gas is never asked for")
let unread = S.plan([h(8453, "ETH", nil, "100000000000000000", 400)], yours: [8453], relayable: relayable, gasPrice: [:])
check(unread.legs.isEmpty, "no gas price read, nothing sent on that network")
let onlyGas = S.plan([h(8453, "ETH", nil, "10000000000000", 0.04)], yours: [8453], relayable: relayable, gasPrice: [8453: gwei / 100])
check(onlyGas.legs.isEmpty && onlyGas.stays.first?.1 == .forGas, "a coin that is all gas stays for gas")

if failures > 0 { print("✗ wallet-sweep-selftest: \(failures) failure(s)"); exit(1) }
print("✓ wallet-sweep-selftest: base units, calldata and the plan hold")
SWIFT

swiftc -O -o "$TMP/run" "$SWEEP" "$TMP/main.swift" 2>"$TMP/build.log" \
  || { cat "$TMP/build.log"; echo "✗ wallet-sweep-selftest did not compile"; exit 1; }
"$TMP/run"
