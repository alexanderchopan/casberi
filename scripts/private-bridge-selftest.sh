#!/bin/zsh
# private-bridge-selftest.sh — round-ups saved from Base or Robinhood (prd §1574):
# the handler's message on Ethereum (approve the router, the deposit, drain to
# the account, NO fallback recipient so a failed deposit refunds where it
# left), what is sent so the budget arrives (Across's fee and half again,
# capped), and the two calls on the network the money is on.
set -u
cd "$(dirname "$0")/.."
BRIDGE="Casberi/Casberi/Model/PrivateBridge.swift"
ACROSS="Casberi/Casberi/Model/YourAccountAcross.swift"
SWAP="Casberi/Casberi/Model/YourAccountSwap.swift"
ACCOUNT="Casberi/Casberi/Model/YourAccount.swift"
OP="Casberi/Casberi/Model/YourAccountOp.swift"
ADAPTER="Casberi/Casberi/Model/YourAccount7579.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
WEBAUTHN="Casberi/Casberi/Model/SafeWebAuthnSignature.swift"
TYPED="Casberi/Casberi/Model/SafeTypedData.swift"
ROUNDUPS="Casberi/Casberi/Model/RoundUps.swift"
TMP=$(mktemp -d /tmp/private-bridge-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/stub.swift" <<'SWIFT'
enum YourAccountDemo {
    static var isOn: Bool { false }
    static var roundUps: RoundUps.Setting { RoundUps.Setting() }
}
enum PrivateMainnet { static let on = true }
enum YourAccountKey { static var address: String? { "0xd30c41652e0330df0c8c1334ffd70e948a50ca8d" } }
SWIFT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
typealias B = PrivateBridge
var bad = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ " + what); bad += 1 } }
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
let account = "0xd30c41652e0330df0c8c1334ffd70e948a50ca8d"
let router = "0xe76e00000000000000000000000000000000a110"
let deposit: [UInt8] = [0xde, 0xad, 0xbe, 0xef] + [UInt8](repeating: 7, count: 40)

check(B.carries(from: 8453) && B.carries(from: 4663) && !B.carries(from: 1), "a save leaves from Ethereum, or not from Base or Robinhood")
check(B.gasHeadroomBps == 5_000, "Across is no longer paid half again its fee (0xBow: fills at the quote went unfilled)")

// The message: approve the router for the budget, the deposit, drain to the account, zero fallback.
let m = hex(B.message(router: router, deposit: deposit, budget: "10100000", account: account)!)
let usdc = "a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
check(m.contains(usdc), "the handler does not approve USDC on Ethereum")
check(m.contains(hex(YourAccount.sel("approve(address,uint256)")) + "000000000000000000000000" + router.dropFirst(2)),
      "the handler does not approve the router")
check(m.contains(String(format: "%064x", 10_100_000)), "the router is not approved for exactly the budget")
check(m.contains(hex(deposit)), "the proved deposit is not the call the handler runs")
check(m.contains(hex(YourAccount.sel("drainLeftoverTokens(address,address)"))), "what the router leaves stays in the shared handler")
// abi.encode((Call[], address)): word 0 the tuple's offset, word 1 the array's, word 2 the fallback.
check(m.dropFirst(128).prefix(64) == Substring(String(repeating: "0", count: 64)),
      "the fallback recipient is not zero: a failed deposit would strand USDC on Ethereum instead of refunding")
check(B.message(router: router, deposit: [], budget: "10100000", account: account) == nil, "a message is written with no deposit")

// What is sent: budget + fee + half the fee, capped at Across's ceiling.
check(B.input(budget: "10100000", quotedOutput: "10050000") == "10175000", "the input is not budget + fee + half the fee")
check(B.input(budget: "10000000", quotedOutput: "9000000") == nil, "a fee past Across's 5% ceiling is paid")
check(B.input(budget: "10000000", quotedOutput: "10000001") == nil, "a quote paying out more than it takes is believed")

// The calls on Base.
let fees = YourAccountAcross.Fees(outputAmount: "10050000", quoteTimestamp: 1_800_000_000, fillDeadline: 1_800_003_600,
                                  exclusiveRelayer: "0x0000000000000000000000000000000000000000", exclusivity: 0, seconds: 7,
                                  spokePool: YourAccountAcross.spokes[8453]!, tooLow: false, minDeposit: nil, maxDeposit: nil)
let msg = B.message(router: router, deposit: deposit, budget: "10100000", account: account)!
let calls = B.calls(from: 8453, input: "10175000", budget: "10100000", fees: fees, message: msg, account: account)!
check(calls.count == 2, "a bridged save is not two calls: approve, then deposit")
check(calls[0].to == "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913" && hex(calls[0].data).contains(String(format: "%064x", 10_175_000)),
      "Base's USDC is not approved to the SpokePool for the input")
check(calls[1].to == YourAccountAcross.spokes[8453]! && calls[1].value == "0", "the deposit does not go to Base's SpokePool, or carries ETH")
let d = hex(calls[1].data)
check(d.hasPrefix(hex(YourAccount.sel(YourAccountAcross.depositSignature))), "the deposit is not the SpokePool's deposit")
check(d.contains("000000000000000000000000" + YourAccountAcross.handler.dropFirst(2)), "the deposit's recipient is not the handler")
check(d.contains(String(format: "%064x", 10_100_000)) && d.contains(String(format: "%064x", 1)),
      "the deposit does not deliver exactly the budget on Ethereum")
check(B.calls(from: 8453, input: "10000000", budget: "10100000", fees: fees, message: msg, account: account) == nil,
      "a deposit delivering more than it sends is written")
let wrongPool = YourAccountAcross.Fees(outputAmount: "10050000", quoteTimestamp: 1, fillDeadline: 2, exclusiveRelayer: "0x0000000000000000000000000000000000000000",
                                       exclusivity: 0, seconds: nil, spokePool: "0x0000000000000000000000000000000000000001", tooLow: false, minDeposit: nil, maxDeposit: nil)
check(B.calls(from: 8453, input: "10175000", budget: "10100000", fees: wrongPool, message: msg, account: account) == nil,
      "a quote naming another SpokePool is used")
exit(bad == 0 ? 0 : 1)
SWIFT
xcrun swiftc -Onone -o "$TMP/run" "$BRIDGE" "$ACROSS" "Casberi/Shared/AddressTail.swift" "$SWAP" "$ACCOUNT" "$OP" "$ADAPTER" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" "$TMP/stub.swift" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err" | head -20; echo "✗ PrivateBridge.swift does not compile alone"; exit 1; }
"$TMP/run" || { echo "✗ the bridged save drifted — see above"; exit 1; }
# Save now is deleted (prd §1578): a round-up saves with your sends only.
grep -qF 'saveRoundUpsNow' Casberi/Casberi/Screens/MoveSecurity.swift \
  && { echo "✗ Save now is back: round-ups save with your sends only (prd §1578)"; exit 1; }
grep -qF ': try await PrivateBridge.ride(budget: rideUnits, from: net, account: account)' Casberi/Casberi/Screens/MoveSentence.swift \
  || { echo "✗ a send on Base or Robinhood no longer carries the save"; exit 1; }
echo "✓ private bridge: the handler's message, the fee and the two calls (prd §1574)"
