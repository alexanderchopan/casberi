#!/bin/zsh
# Make TAC private (prd §1971 item 20): the permit your co-signer signs, and
# the checks before it is asked for (`Casberi/Casberi/Model/TacitPermit.swift`),
# compiled WHOLE with the general EIP-712 encoder it leans on.
#   - the permit's digest is ethers' own, for the same domain and message (a
#     vector made 2026-11-25 by `TypedDataEncoder.hash`, throwaway key);
#   - the inbox call's selector is ethers' `id(...)` of its signature;
#   - every check refuses what it exists for, and passes a good deposit.
set -euo pipefail
cd "$(dirname "$0")/.."
M="Casberi/Casberi/Model"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/stub.swift" <<'SWIFT'
import Foundation
enum PrivacyEngineWire { struct Failure: Error, Equatable, Decodable { let name: String; let message: String } }
SWIFT

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias P = TacitPermit
typealias W = TacitEngineWire

// ethers 6, `TypedDataEncoder.hash`, owner the key 0x11…11.
let owner = "0x19e7e376e7c213b7e7e7e46cc70a5dd086daff2a"
let inbox = "0x1d7ce2d419fe75d2e83998db55555b997c4d6b5f"
let data = P.typedData(owner: owner, spender: inbox, value: Decimal(string: "23878189052847000000")!, nonce: 0, deadline: 1795585725)
check(P.digest(data).map(Keccak256.hexString) == "5ccf221bcaf0e52d328d457f9082f83fba25459d9774293d6032390dee174593",
      "the permit's digest is not ethers' for the same permit")

// Selectors: ethers' `id`.
let d = W.Deposit(shares: "0x8bc0c783", amount: "0x8e283640", cx: "0x" + String(repeating: "1", count: 64),
                  cy: "0x" + String(repeating: "2", count: 64), body: "0x" + String(repeating: "3", count: 64))
let call = P.inboxCall(d, back: "0x" + String(repeating: "4", count: 64))
check(call?.hasPrefix("0x226dd043") == true && call?.count == 2 + 8 + 6 * 64, "the inbox call is not inbox(uint256,uint256,bytes32,bytes32,bytes32,bytes32)")
check(P.noncesCall(owner) == "0x7ecebe00" + String(repeating: "0", count: 24) + owner.dropFirst(2), "nonces(owner) is misbuilt")
check(P.address(fromWord: "0x" + String(repeating: "0", count: 24) + inbox.dropFirst(2)) == inbox, "a returned word is not read as an address")
check(P.address(fromWord: "0x" + String(repeating: "f", count: 64)) == nil, "a word that is not an address is read as one")

// A good deposit: 23.85 TAC, the leader's fee 0.0282 TAC, an hour left.
let now = Date(timeIntervalSince1970: 1795582125)
let units: UInt64 = 2_385_000_000
let fee = "0x641c508f683c00"
func proved(value: String = "0x14b6054f3b4793c00", sweepFee: String = fee, inbox i: String = inbox,
            deadline: Int = 1795585725, units u: String = "0x8e283640") -> W.ShieldProved {
    W.ShieldProved(inbox: i, back: "0x" + String(repeating: "4", count: 64), index: 0, deadline: deadline, value: value,
                   sweepFee: sweepFee, fee: "0x17a602", shares: "0x8bc0c783", units: u, proveMs: 8000, deposit: d)
}
let quote = W.ShieldQuote(fee: "0x17a602", arrives: "0x8e0948f5", cap: "0x174876e800", sweepFee: fee)
let plenty = Decimal(string: "100000000000000000000")!
func run(_ p: W.ShieldProved, q: W.ShieldQuote = quote, ownerIs o: String = owner, u: UInt64 = units,
         chainInbox: String = inbox, balance: Decimal = plenty) -> P.Problem? {
    P.check(proved: p, quote: q, coSigner: owner, owner: o, units: u, chainInbox: chainInbox, balance: balance, now: now)
}
check(run(proved()) == nil, "a good deposit is refused")
check(run(proved(), ownerIs: "0x" + String(repeating: "9", count: 40)) == .notTheCoSigner, "a permit from another wallet is let through")
check(run(proved(), chainInbox: "0x" + String(repeating: "8", count: 40)) == .wrongInbox, "an inbox the chain did not compute is let through")
check(run(proved(inbox: "0x" + String(repeating: "8", count: 40))) == .wrongInbox, "the engine's inbox is believed over the chain's")
check(run(proved(value: "0x14b6054f3b4793c01")) == .wrongValue, "a permit for one wei more is let through")
check(run(proved(units: "0x8e283641")) == .wrongValue, "a proof for another amount is let through")
check(run(proved(value: "0x1529d58a325110000", sweepFee: "0x7a1200000000000")) == .feeRose, "a fee well over the one shown is let through")
check(run(proved(deadline: 1795582125 + 3 * 3600)) == .deadline, "a permit standing three hours is let through")
check(run(proved(deadline: 1795582125 + 30)) == .deadline, "a permit about to end is let through")
check(run(proved(), balance: Decimal(string: "23000000000000000000")!) == .notEnough, "more than the wallet holds is let through")
check(run(proved(), q: W.ShieldQuote(fee: "0x17a602", arrives: "0x8e0948f5", cap: "0x3b9aca00", sweepFee: fee)) == .overCap, "a deposit over Tacit's cap is let through")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   ethers' permit digest, the inbox and nonces calls, and every check")
SWIFT

xcrun swiftc -O "$M/TacitPermit.swift" "$M/SafeTypedData.swift" "$M/SafeTransaction.swift" "$M/Keccak256.swift" \
  "$M/ClearSign.swift" "$M/TacitEngineWire.swift" "$work/stub.swift" "$work/main.swift" -o "$work/t" 2>&1 | grep -E "error" || true
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$M/TacitPermit.swift" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$M/TacitPermit.swift" "$work/m.swift" && fail "mutation matched nothing: $why"
  xcrun swiftc -O "$work/m.swift" "$M/SafeTypedData.swift" "$M/SafeTransaction.swift" "$M/Keccak256.swift" \
    "$M/ClearSign.swift" "$M/TacitEngineWire.swift" "$work/stub.swift" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "the inbox is not compared"        's/guard proved\.inbox\.lowercased\(\) == chainInbox\.lowercased\(\), isAddress\(chainInbox\) else \{ return \.wrongInbox \}//'
mutate "the value is not exact"           's/guard value == Decimal\(units\) \* pow\(Decimal\(10\), 10\) \+ fee else \{ return \.wrongValue \}//'
mutate "the fee may rise without limit"   's/guard fee <= shown \+ shown \/ 5 \+ pow\(Decimal\(10\), 10\) else \{ return \.feeRose \}//'
mutate "the deadline is not bounded"      's/left > 60, left <= longest/left > 60/'
mutate "the balance is not checked"       's/guard balance >= value else \{ return \.notEnough \}//'
mutate "the domain's version moves"       's/static let version = "1"/static let version = "2"/'
mutate "the owner is not the co-signer"   's/guard owner\.caseInsensitiveCompare\(coSigner\) == \.orderedSame else \{ return \.notTheCoSigner \}//'
print "✓ tacit permit: ethers' digest, the chain's inbox, the exact value, the fee, the deadline, the balance (7 mutations)"
