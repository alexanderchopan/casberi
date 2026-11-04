#!/bin/zsh
# round-ups-pot-selftest.sh — Round-ups, set aside as you go (prd §1690): one
# send's step (change, carry with what was owed, a move decided by what is
# ALREADY set aside), Across's floor, the pot and owed after a send, the
# aUSDC split that keeps Round-ups out of Lend, the withdrawal that moves the
# interest only when nothing else is lent, the old counts becoming owed once,
# and the handler's message and calls that carry change to Aave on Base.
set -u
cd "$(dirname "$0")/.."
M="Casberi/Casberi/Model"
TMP=$(mktemp -d /tmp/round-ups-pot-selftest.XXXXXX)
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
typealias P = RoundUpsPot
var bad = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ " + what); bad += 1 } }
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
let account = "0xd30c41652e0330df0c8c1334ffd70e948a50ca8d"

// The threshold: $10, or 0xBow's minimum when more; nothing moves while it is unread.
check(P.moveAt(poolMinimum: "10050000") == "10050000", "the move ignores 0xBow's smallest deposit")
check(P.moveAt(poolMinimum: "2000000") == "10000000", "Round-ups moves under $10")
check(P.moveAt(poolMinimum: nil) == nil, "Round-ups moves on a guessed minimum")

// One send: the move is decided by what is ALREADY in Round-ups.
let s1 = P.step(change: "400000", owed: "300000", pot: "9900000", moveAt: "10000000")
check(s1.carry == "700000", "the change does not carry what was owed")
check(!s1.moves, "a move counts change not yet set aside (it is not in Aave to withdraw)")
check(P.step(change: "400000", owed: "0", pot: "10000000", moveAt: "10000000").moves, "a full Round-ups does not move")
check(!P.step(change: "400000", owed: "0", pot: "10000000", moveAt: nil).moves, "Round-ups moves with the minimum unread")

// Across's floor: anything on Base, at least $0.51 from elsewhere.
check(P.carries("10000", from: 8453), "Base cannot set aside a cent")
check(!P.carries("400000", from: 1) && P.carries("510000", from: 4663), "the change under Across's minimum is carried")
check(!P.carries("0", from: 8453), "nothing is set aside as something")

// After a send.
let set = P.after(s1, pot: "5000000", setAside: true, moved: nil)
check(set == (pot: "5700000", owed: "0"), "a set-aside does not join Round-ups and clear what was owed")
let missed = P.after(s1, pot: "5000000", setAside: false, moved: nil)
check(missed == (pot: "5000000", owed: "700000"), "a carry that did not go is not owed to the next send")
let moved = P.after(P.step(change: "400000", owed: "0", pot: "10200000", moveAt: "10000000"), pot: "10200000", setAside: true, moved: "10200000")
check(moved.pot == "400000", "a move does not leave just this send's change")
check(P.after(s1, pot: "100", setAside: false, moved: "900").pot == "0", "Round-ups goes below zero")

// Held to the chain: Round-ups is never lent, never more than is there.
check(P.split(aBalance: "156200000", pot: "6200000") == (roundUps: "6200000", lent: "150000000"), "Round-ups is counted as lent")
check(P.split(aBalance: "3000000", pot: "6200000") == (roundUps: "3000000", lent: "0"), "Round-ups claims more than Aave holds")
check(P.healed(pot: "6200000", aBalance: "0") == "0", "a refunded set-aside stays in Round-ups")

// A carry still crossing is never healed away.
check(!P.mayHeal(carriedAt: Date(timeIntervalSinceNow: -600)), "a pot is cut while change from Ethereum is still crossing")
check(P.mayHeal(carriedAt: Date(timeIntervalSinceNow: -7 * 3600)) && P.mayHeal(carriedAt: nil), "a pot is never held to the chain")

// The withdrawal: everything when nothing else is lent (the interest moves too), else exactly the pot.
check(P.withdrawal(pot: "10000000", aBalance: "10030000").map { $0.amount == "10030000" && $0.all } == true,
      "Round-ups' interest is left behind as dust")
check(P.withdrawal(pot: "10000000", aBalance: "160000000").map { $0.amount == "10000000" && !$0.all } == true,
      "a move withdraws what you lent")
check(P.withdrawal(pot: "0", aBalance: "100") == nil, "an empty Round-ups moves")

// The old counts become owed, once; a test network's are dropped.
let d = UserDefaults(suiteName: "round-ups-pot-selftest")!
d.removePersistentDomain(forName: "round-ups-pot-selftest")
d.set("2600000", forKey: "yourAccount.roundUps.private.1")
d.set("400000", forKey: "yourAccount.roundUps.saved.8453")
d.set("9000000", forKey: "yourAccount.roundUps.private.11155111")
P.migrate(d)
check(d.string(forKey: "yourAccount.roundUps.owed") == "3000000", "the old counts are not owed (or a test network's are)")
check(d.string(forKey: "yourAccount.roundUps.private.1") == nil && d.string(forKey: "yourAccount.roundUps.private.11155111") == nil,
      "the old count keys are kept")
d.set("5", forKey: "yourAccount.roundUps.saved.1")
P.migrate(d)
check(d.string(forKey: "yourAccount.roundUps.owed") == "3000000", "the migration runs twice")
d.removePersistentDomain(forName: "round-ups-pot-selftest")

// The handler's message on Base: approve the Pool, supply on behalf of the account, drain, zero fallback.
let m = hex(P.message(budget: "700000", account: account)!)
let pool = "a238dd80c259a72e81d7e4664a9801593f98d1c5", usdc = "833589fcd6edb6e08f4c7c32d4f71b54bda02913"
check(m.contains(hex(YourAccount.sel("approve(address,uint256)")) + "000000000000000000000000" + pool), "the handler does not approve Aave's Pool")
check(m.contains(hex(YourAccount.sel("supply(address,uint256,address,uint16)")) + "000000000000000000000000" + usdc
                 + String(format: "%064x", 700_000) + "000000000000000000000000" + account.dropFirst(2)),
      "the handler does not supply exactly what arrives, on behalf of the account")
check(m.contains(hex(YourAccount.sel("drainLeftoverTokens(address,address)"))), "what is left stays in the shared handler")
check(m.dropFirst(128).prefix(64) == Substring(String(repeating: "0", count: 64)),
      "the fallback recipient is not zero: a failed supply would strand USDC in the handler instead of refunding")

// The two calls on Ethereum.
let fees = YourAccountAcross.Fees(outputAmount: "695000", quoteTimestamp: 1_800_000_000, fillDeadline: 1_800_003_600,
                                  exclusiveRelayer: "0x0000000000000000000000000000000000000000", exclusivity: 0, seconds: 2,
                                  spokePool: YourAccountAcross.spokes[1]!, tooLow: false, minDeposit: nil, maxDeposit: nil)
let input = PrivateBridge.input(budget: "700000", quotedOutput: fees.outputAmount)!
let calls = P.calls(from: 1, input: input, budget: "700000", fees: fees, message: P.message(budget: "700000", account: account)!, account: account)!
check(calls.count == 2 && calls[0].to == "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", "Ethereum's USDC is not approved first")
let dep = hex(calls[1].data)
check(calls[1].to == YourAccountAcross.spokes[1]! && dep.contains(String(format: "%064x", 8453)), "the deposit does not go to Base")
check(dep.contains("000000000000000000000000" + YourAccountAcross.handler.dropFirst(2)), "the deposit's recipient is not the handler")
check(P.calls(from: 8453, input: input, budget: "700000", fees: fees, message: [1], account: account) == nil,
      "Base carries its own change through Across")
exit(bad == 0 ? 0 : 1)
SWIFT
xcrun swiftc -Onone -o "$TMP/run" "$M/RoundUpsPot.swift" "$M/RoundUpsPot+Across.swift" "$M/AaveLend.swift" "$M/PrivateBridge.swift" \
  "$M/YourAccountAcross.swift" "Casberi/Shared/AddressTail.swift" "$M/YourAccountSwap.swift" "$M/YourAccount.swift" "$M/YourAccountOp.swift" \
  "$M/YourAccount7579.swift" "$M/SafeTransaction.swift" "$M/Keccak256.swift" "$M/ClearSign.swift" "$M/SafeWebAuthnSignature.swift" \
  "$M/SafeTypedData.swift" "$M/RoundUps.swift" "$TMP/stub.swift" "$TMP/main.swift" 2>"$TMP/err" \
  || { head -20 "$TMP/err"; echo "✗ RoundUpsPot does not compile alone"; exit 1; }
"$TMP/run" || { echo "✗ Round-ups drifted — see above"; exit 1; }
# The send carries Round-ups, and a send elsewhere moves it under the same Face ID.
S="Casberi/Casberi/Screens/MoveSentence.swift"
grep -qF 'RoundUpsPot.setAside(roundUp.carry, on: net, account: account)' "$S" \
  || { echo "✗ a send no longer sets its change aside (prd §1690)"; exit 1; }
grep -qF 'try await RoundUpsPot.moveAlone(account: account,' "$S" \
  || { echo "✗ a send on Ethereum or Robinhood no longer moves Round-ups"; exit 1; }
grep -qF 'YourAccountKey.$ahead.withValue(unlock?.again())' "$S" \
  || { echo "✗ the move after a send asks for its own Face ID"; exit 1; }
grep -qF 'all: all && !(RoundUpsPot.market == m && roundUps != "0")' "Casberi/Casberi/Model/LendMove.swift" \
  || { echo "✗ Take back all can withdraw Round-ups"; exit 1; }
echo "✓ Round-ups: set aside as you go, held to the chain, moved at \$10 (prd §1690)"
