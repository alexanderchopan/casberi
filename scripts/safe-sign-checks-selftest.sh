#!/bin/zsh
# The co-signer's checks (prd §1514, Phase 3 of docs/signing-safety-spec.md)
# — `SafeSignChecks`: Reown Verify's answer as the pair block reads it (a
# missing context is unknown, never confirmed), unlimited approvals found in
# the calldata itself (ERC-20 approve and increaseAllowance, Permit2,
# setApprovalForAll) with every selector pinned to its signature, and the
# three EIP-712 hashes, the digest pinned to the encoder Safe's own
# getTransactionHash is checked against; then the wiring: an unconfirmed
# pairing is held, never approved on arrival.
set -euo pipefail
cd "$(dirname "$0")/.."

CHECKS="Casberi/Casberi/Model/SafeSignChecks.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
PEER="Casberi/Casberi/Model/SafePeer.swift"
BLOCK="Casberi/Casberi/Screens/SafeQueueCard.swift"
for f in "$CHECKS" "$TX" "$KECCAK" "$CLEARSIGN" "$PEER" "$BLOCK"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done

TMP=$(mktemp -d /tmp/safe-sign-checks-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
typealias C = SafeSignChecks
var bad = 0, ran = 0
func check(_ ok: Bool, _ what: String) { ran += 1; if !ok { print("✗ " + what); bad += 1 } }
func sel(_ s: String) -> String { Keccak256.hexString(Array(Keccak256.hash(Array(s.utf8)).prefix(4))) }

// Verify, as reown-swift 2.3.0 spells it.
check(C.pairing(validation: "valid", origin: "https://app.safe.global", claimedURL: "https://app.safe.global", claimedName: "Safe{Wallet}") == .confirmed, "a valid pairing was not confirmed")
check(C.pairing(validation: nil, origin: nil, claimedURL: "https://app.safe.global", claimedName: "Safe") == .unconfirmed(claimed: "app.safe.global"), "a missing context was not read as unknown")
check(C.pairing(validation: "invalid", origin: "https://evil.xyz", claimedURL: "app.safe.global", claimedName: "Safe") == .unconfirmed(claimed: "app.safe.global"), "an invalid pairing was not unconfirmed")
check(C.pairing(validation: "scam", origin: "https://safe-global-app.xyz", claimedURL: "https://www.app.safe.global/home", claimedName: "Safe{Wallet}")
      == .scam(claimed: "app.safe.global", says: "Safe{Wallet}", really: "safe-global-app.xyz"), "a scam did not name what it says and where it is")
check(C.line(.confirmed) == nil, "a confirmed pairing drew a line")
check(C.line(.unconfirmed(claimed: "app.safe.global")) == "Couldn't confirm it's app.safe.global", "the amber line drifted")
check(C.line(.scam(claimed: "app.safe.global", says: "x", really: nil)) == "Reported as a scam site. It isn't app.safe.global.", "the red line drifted from the canvas")

// The selectors are the signatures they say.
check(C.approve == sel("approve(address,uint256)"), "approve's selector is wrong")
check(C.increase == sel("increaseAllowance(address,uint256)"), "increaseAllowance's selector is wrong")
check(C.forAll == sel("setApprovalForAll(address,bool)"), "setApprovalForAll's selector is wrong")
check(C.permit2Approve == sel("approve(address,address,uint160,uint48)"), "Permit2's approve selector is wrong")

// Unlimited approvals, read from the bytes.
func hex(_ s: String) -> [UInt8] { SafeABI.hexBytes(s)! }
let usdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", spender = "def1c0ded9bec7f1a1670819833240f027b25eff"
let addr = String(repeating: "0", count: 24) + spender
let maxWord = String(repeating: "f", count: 64)
let u = C.unlimited(to: usdc, data: hex("0x" + C.approve + addr + maxWord))
check(u == C.Unlimited(spender: "0x" + spender, token: usdc, collection: false), "type(uint256).max was not unlimited")
check(C.unlimited(to: usdc, data: hex("0x" + C.approve + addr + String(repeating: "0", count: 31) + "1" + String(repeating: "0", count: 32))) != nil, "2^128 was not unlimited")
check(C.unlimited(to: usdc, data: hex("0x" + C.approve + addr + String(repeating: "0", count: 56) + "05f5e100")) == nil, "an exact 100 USDC read as unlimited")
check(C.unlimited(to: usdc, data: hex("0x" + C.approve + addr + String(repeating: "0", count: 32) + String(repeating: "f", count: 32))) == nil, "2^128-1 read as unlimited")
check(C.unlimited(to: usdc, data: hex("0x" + C.increase + addr + maxWord)) != nil, "increaseAllowance(max) was missed")
let nft = "0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d"
check(C.unlimited(to: nft, data: hex("0x" + C.forAll + addr + String(repeating: "0", count: 63) + "1"))?.collection == true, "setApprovalForAll(true) was missed")
check(C.unlimited(to: nft, data: hex("0x" + C.forAll + addr + String(repeating: "0", count: 64))) == nil, "setApprovalForAll(false) read as an approval")
let p2 = "0x" + C.permit2Approve + String(repeating: "0", count: 24) + usdc.dropFirst(2) + addr
    + String(repeating: "0", count: 24) + String(repeating: "f", count: 40) + String(repeating: "0", count: 64)
check(C.unlimited(to: C.permit2, data: hex(p2)) == C.Unlimited(spender: "0x" + spender, token: usdc, collection: false), "Permit2's max uint160 was missed")
check(C.unlimited(to: usdc, data: hex(p2)) == nil, "a Permit2 shape off Permit2's address read as one")
check(C.unlimited(to: usdc, data: hex("0x" + C.approve + "01" + String(repeating: "0", count: 22) + spender + maxWord)) == nil, "a dirty address word was read")
check(C.unlimited(to: usdc, data: hex("0x" + C.approve)) == nil && C.unlimited(to: usdc, data: []) == nil, "short calldata was read")
check(C.line(u!, spender: "0xdef1…5eff", token: "USDC") == "Lets 0xdef1…5eff spend all of this Safe's USDC, with no end.", "the unlimited line drifted from the canvas")

// The hashes: the digest is the encoder's own safeTxHash, built from the other two.
let tx = SafeTransaction(to: usdc, value: "0", data: "0x" + C.approve + addr + maxWord, operation: 0, safeTxGas: "0",
                         baseGas: "0", gasPrice: "0", gasToken: "0x0000000000000000000000000000000000000000",
                         refundReceiver: "0x0000000000000000000000000000000000000000", nonce: 42)
let safe = "0x5A1E7C93b0d24F86a1C3E5b7d9f0A2C4E6B8d203"
let h = C.hashes(chainId: 1, safe: safe, tx: tx)!
check(h.digest == SafeTxEncoder.safeTxHash(chainId: 1, safe: safe, tx: tx), "the digest is not the encoder's safeTxHash")
check(h.digest == Keccak256.hash([0x19, 0x01] + h.domain + h.message), "the digest is not keccak(0x1901 ‖ domain ‖ message)")
check(C.hashes(chainId: 8453, safe: safe, tx: tx)!.domain != h.domain, "the domain hash ignores the chain")

print(bad == 0 ? "safe-sign-checks self-test: \(ran) checks ok" : "safe-sign-checks self-test: \(bad) of \(ran) failed")
exit(bad == 0 ? 0 : 1)
SWIFT
xcrun swiftc -O -o "$TMP/t" "$CHECKS" "$TX" "$KECCAK" "$CLEARSIGN" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ SafeSignChecks.swift does not compile with the Safe encoders alone"; exit 1; }
"$TMP/t" || exit 1

# The wiring: a pairing Verify did not confirm is held for the person.
awk '/private static func handle\(proposal: Session.Proposal, validation/,/^    }$/' "$PEER" | grep -q 'guard verdict == .confirmed else {' \
  || { echo "✗ an unconfirmed pairing is approved on arrival again (prd §1514)"; exit 1; }
grep -q 'let validation = verify.map' "$PEER" || { echo "✗ the proposal's VerifyContext is dropped again"; exit 1; }
grep -q 'SafeSignDetails(chainId: ready.chainId' "$BLOCK" || { echo "✗ the sign block lost its unlimited line and Details"; exit 1; }
true
