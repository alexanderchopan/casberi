#!/bin/zsh
# Deposit's on-chain half (prd §1604): the curator's signature read, the
# reservation and the release encoded exactly as Peer's OrchestratorV3 on
# Base takes them.
#
#   Casberi/Casberi/Model/PeerIntent.swift
#
# compiled WHOLE with `SafeTransaction.swift`, `Keccak256.swift` and
# `ClearSign.swift` (it encodes through `SafeABI`), against vectors recorded
# from the chain itself (`scripts/support/peer-intent-vectors.json`):
#   · signalIntent: the calldata that simulated clean from a Safe on Base
#     (eth_call, two nodes) while the curator's signature was live;
#   · fulfillIntent: three real transactions' input, Peer's attribution tag
#     cut off — the encoder must rebuild them byte for byte from the
#     attestation fields alone;
#   · a real signal's receipt, for the intent's hash.
#
# WHY. A wrong word in either call is not an error the person sees as one: a
# signal the curator did not sign reverts after Face ID, and a fulfil that
# mis-encodes the proof leaves the seller's USDC reserved for six hours while
# the person's money has already left their bank. And reading the curator's
# answer loosely is worse than either: a signature over a different amount,
# recipient or caller is one the chain honours for someone else's trade.
#
# Pure, local, deterministic — no network, no key, no simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
INTENT="Casberi/Casberi/Model/PeerIntent.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
VECTORS="scripts/support/peer-intent-vectors.json"
for f in "$INTENT" "$TX" "$KECCAK" "$CLEARSIGN" "$VECTORS"; do [[ -f "$f" ]] || { print -u2 "✗ $f not found"; exit 1; }; done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias P = PeerIntent
let v = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let hex = { (b: [UInt8]?) in b.map(SafeABI.hex) ?? "nil" }

// The order and the curator's answer.
let o = v["signOrder"] as! [String: String]
let order = P.Order(processorName: o["processorName"]!, paymentMethod: o["paymentMethod"]!,
                    payeeDetails: o["payeeDetails"]!, depositId: o["depositId"]!, amount: o["amount"]!,
                    fiatCurrency: o["fiatCurrency"]!, conversionRate: o["conversionRate"]!, to: o["to"]!)
let caller = v["signCaller"] as! String
let response = v["signResponse"] as! [String: Any]
let request = P.signRequest(order, caller: caller)
check(request["callerAddress"] as? String == caller && request["orchestratorAddress"] as? String == P.orchestrator,
      "the sign request names the caller and the orchestrator")
check((request["referralFees"] as? [Any])?.isEmpty == true, "we ask for no referral fee of our own")

guard case .signed(let signed) = P.readSign(status: 200, json: response, asked: order, caller: caller) else {
    print("  ✗ the recorded answer reads as signed"); exit(1)
}
check(signed.referralFees == [P.ReferralFee(recipient: "0x0bc26ff515411396dd588abd6ef6846e04470227", fee: "9500000000000000")],
      "Peer's 0.95% is read as the referral fee the curator added")
check(signed.expiration == "1793309100", "the signature's expiry is read")
check(hex(P.signalCalldata(signed)) == v["signalCalldata"] as? String,
      "signalIntent encodes to the calldata that simulated clean from the Safe")
check(SafeABI.hex(P.selector(P.signalSignature)) == "0x" + String((v["signalCalldata"] as! String).dropFirst(2).prefix(8)),
      "signalIntent's selector is the chain's")

func answer(_ edit: (inout [String: Any]) -> Void) -> [String: Any] {
    var r = response, o = r["responseObject"] as! [String: Any], d = o["intentData"] as! [String: Any]
    edit(&d); o["intentData"] = d; r["responseObject"] = o; return r
}
var other = order; other.to = "0x000000000000000000000000000000000000dEaD"
check(P.readSign(status: 200, json: response, asked: other, caller: caller) == .refused("signed a different order"),
      "a signature for another recipient is refused")
check(P.readSign(status: 200, json: response, asked: order, caller: "0xe3e6d278796080adf387c7eb0e4f174362b4680d") == .refused("signed a different order"),
      "a signature for another caller is refused")
check(P.readSign(status: 200, json: answer { $0["amount"] = "99999999" }, asked: order, caller: caller) == .refused("signed a different order"),
      "a signature over another amount is refused")
check(P.readSign(status: 200, json: answer { $0["escrowAddress"] = "0x0000000000000000000000000000000000000001" }, asked: order, caller: caller) == .refused("signed a different order"),
      "a signature for another escrow is refused")
check(P.readSign(status: 200, json: answer { $0["referralFees"] = [["recipient": "0x12", "fee": "1"]] }, asked: order, caller: caller) == .refused("unreadable fee"),
      "a malformed fee is refused")
check(P.readSign(status: 409, json: ["message": "This deposit is enforced on-chain and does not require a curator signature"], asked: order, caller: caller) == .enforcedOnChain,
      "the on-chain-gating 409 is told apart")
check(P.readSign(status: 409, json: ["message": "Payment method inactive"], asked: order, caller: caller) == .refused("Payment method inactive"),
      "any other 409 is a refusal, never an ungated signal")

// The intent's hash, off a real signal's receipt.
let receipt = v["signaledReceipt"] as! [String: Any]
let logs = receipt["logs"] as! [[String: Any]]
check(P.intentHash(fromLogs: logs) == (receipt["intentHash"] as! String).lowercased(), "the intent's hash is read off IntentSignaled")
check(P.intentHash(fromLogs: logs.filter { ($0["topics"] as? [String])?.first?.lowercased() != P.intentSignaledTopic }) == nil,
      "no IntentSignaled, no hash")
check(P.intentHash(fromLogs: logs + logs) == nil, "two IntentSignaled logs are not one intent")

// fulfillIntent, rebuilt from the attestation alone, against real transactions.
for (i, f) in (v["fulfils"] as! [[String: Any]]).enumerated() {
    let a = f["attestation"] as! [String: String]
    let att = P.Attestation(intentHash: a["intentHash"]!, releaseAmount: a["releaseAmount"]!, dataHash: a["dataHash"]!,
                            signature: a["signature"]!, signer: a["signer"]!,
                            encodedPaymentDetails: a["encodedPaymentDetails"]!, metadata: a["metadata"]!)
    check(hex(P.fulfillCalldata(att)) == f["calldata"] as? String, "fulfil \(i + 1) rebuilds the real transaction byte for byte")
}

// The enclave's answer.
let a0 = (v["fulfils"] as! [[String: Any]])[0]["attestation"] as! [String: String]
let intent = P.Signaled(intentHash: a0["intentHash"]!, amount: "999999999", timestamp: 1_793_300_000,
                        paymentMethod: order.paymentMethod, fiatCurrency: order.fiatCurrency,
                        conversionRate: order.conversionRate, payeeDetails: order.payeeDetails)
func verify(_ edit: (inout [String: Any], inout [String: Any]) -> Void = { _, _ in }) -> [String: Any] {
    var o: [String: Any] = ["signature": a0["signature"]!, "signer": a0["signer"]!,
                            "encodedPaymentDetails": a0["encodedPaymentDetails"]!, "metadata": a0["metadata"]!]
    var td: [String: Any] = ["intentHash": a0["intentHash"]!, "releaseAmount": a0["releaseAmount"]!, "dataHash": a0["dataHash"]!]
    edit(&o, &td); o["typedDataValue"] = td
    return ["success": true, "responseObject": o]
}
check(P.readVerify(json: verify(), for: intent)?.releaseAmount == a0["releaseAmount"], "a real attestation reads")
check(P.readVerify(json: verify { o, _ in o["signer"] = "0x0000000000000000000000000000000000000bad" }, for: intent) == nil,
      "an attestation signed by anyone but the enclave is refused")
check(P.readVerify(json: verify { _, td in td["intentHash"] = "0x" + String(repeating: "ab", count: 32) }, for: intent) == nil,
      "an attestation for another intent is refused")
var small = intent; small.amount = "1"
check(P.readVerify(json: verify(), for: small) == nil, "a release larger than the reservation is refused")
check(P.readVerify(json: verify { _, td in td["releaseAmount"] = "0" }, for: intent) == nil, "a release of nothing is refused")
check(P.readVerify(json: verify { o, _ in o["signature"] = "0x1234" }, for: intent) == nil, "a signature that is not 65 bytes is refused")
let vr = P.verifyRequest(sealed: "a.b.c.d.e", params: [:], intent: intent)
check((vr["intent"] as? [String: String])?["timestampMs"] == "1793300000000", "the intent's time goes to the enclave in milliseconds")
check(P.verifyPath(platform: "revolut", actionType: "transfer_revolut") == "/buyer/verify/revolut/transfer_revolut", "the verify path")

// The encoder on its own.
check(P.Arg.encode([.bytes([])]) == SafeABI.word(uint: 32)! + SafeABI.word(uint: 0)!, "empty bytes: an offset and a zero length")
check(P.Arg.encode([.bytes([1])]).count == 96, "one byte pads to a word")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   the curator's answer read strictly, signalIntent as simulated, three real fulfils rebuilt, the enclave's answer refused unless it is this intent's")
SWIFT

build() { xcrun swiftc -O "$1" "$TX" "$KECCAK" "$CLEARSIGN" "$work/main.swift" -o "$2" 2>&1 | grep -v "^$" || true; }
build "$INTENT" "$work/t"
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" "$VECTORS" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$INTENT" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$INTENT" "$work/m.swift" && fail "mutation matched nothing: $why"
  rm -f "$work/m"
  xcrun swiftc -O "$work/m.swift" "$TX" "$KECCAK" "$CLEARSIGN" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 \
    || fail "mutation did not compile: $why"
  if "$work/m" "$VECTORS" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "the caller never compared"        's/same\("callerAddress", caller\), //'
mutate "the amount never compared"        's/same\("amount", order\.amount\),\n\s*//'
mutate "the recipient never compared"     's/same\("recipientAddress", order\.to\), //'
mutate "every 409 read as on-chain"       's/\? \.enforcedOnChain : \.refused\(message\)/? .enforcedOnChain : .enforcedOnChain/'
mutate "the referral fees dropped"        's/\.array\(fees\),/.array([]),/'
mutate "the expiry and hook swapped"      's/\.word\(expiration\), \.word\(hook\)/.word(hook), .word(expiration)/'
mutate "a dynamic offset off by a word"   's/head \+= length\(headSize \+ tail\.count\)/head += length(headSize + tail.count + 32)/'
mutate "bytes left unpadded"              's/\+ \[UInt8\]\(repeating: 0, count: \(32 - b\.count % 32\) % 32\)//'
mutate "the proof's signatures not an array" 's/\.array\(\[\.bytes\(sig\)\]\)/.bytes(sig)/'
mutate "the signer not in verificationData"   's/\.bytes\(proof\), \.bytes\(signer\)\]/.bytes(proof), .bytes([])]/'
mutate "any signer accepted"              's/signer\.lowercased\(\) == attestationSigner/!signer.isEmpty/'
mutate "any release accepted"             's/releaseW\.lexicographicallyPrecedes\(reserved\) \|\| releaseW == reserved,/true,/'
mutate "another intent's attestation"     's/hash\.lowercased\(\) == intent\.intentHash\.lowercased\(\)/!hash.isEmpty/'
mutate "two signals read as one"          's/guard hits\.count == 1,/guard hits.count >= 1,/'
mutate "seconds sent as milliseconds"     's/String\(intent\.timestamp \* 1000\)/String(intent.timestamp)/'
