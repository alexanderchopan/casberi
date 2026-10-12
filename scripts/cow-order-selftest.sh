#!/bin/zsh
# Casberi CoW order self-test (2026-10-12, prd §1285):
#
#   Casberi/Casberi/Model/CowOrder.swift
#     — preSignature   (setPreSignature's order id and flag, decoded exactly)
#     — parse / digest / verify (CoW's API answer, re-hashed to the id)
#     — reading / enrich (the sign block's words, swapped in only when verified)
#
# Nine real orders read off CoW's API by the ids the settlement contract
# emitted (scripts/fixtures/cow/orders-mainnet.json). Every failure below is
# the sign block stating an order that is not the one being signed:
#
#   • an API answer drawn without re-hashing it — any amount CoW's server says;
#   • a different chain's order taken for this one (the domain's chainId);
#   • an expiry that does not match the id's last four bytes;
#   • a verified reading pasted over a call whose order did NOT verify.
set -euo pipefail
cd "$(dirname "$0")/.."

COW="Casberi/Casberi/Model/CowOrder.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
FIX="scripts/fixtures/cow/orders-mainnet.json"
for f in "$COW" "$CLEARSIGN" "$TX" "$KECCAK" "$FIX" Casberi/Casberi/Model/CowOrders.swift; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
grep -q '"api.cow.fi"' Casberi/Casberi/Model/NetworkReach.swift || { echo "✗ api.cow.fi is not declared in NetworkReach"; exit 1; }
grep -q 'let reading = await CowOrders.enrich(read, to: tx.to, data: tx.data, safe: safeAddress,' Casberi/Casberi/Model/SafeSigner.swift \
  || { echo "✗ the signer no longer states a verified CoW order"; exit 1; }
grep -q 'contracts.formUnion(await CowOrders.prefetch(txs, chainId: chain.chainId))' Casberi/Casberi/Model/SafeBridge.swift \
  || { echo "✗ the Safe queue no longer proves CoW orders before titling them"; exit 1; }
grep -q 'let order = CowOrder.verify(json: json, uid: uid, chainId: chainId)' Casberi/Casberi/Model/CowOrders.swift \
  || { echo "✗ CowOrders draws an API answer it did not verify"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what) (line \(line))"); failures += 1 }
}
let orders = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ProcessInfo.processInfo.environment["COW_FIX"]!))) as! [[String: Any]]
func uid(_ o: [String: Any]) -> [UInt8] { SafeABI.hexBytes(o["uid"] as! String)! }
func edited(_ o: [String: Any], _ k: String, _ v: Any?) -> [String: Any] { var c = o; c[k] = v; return c }

print("verify")
check(orders.count == 9 && orders.allSatisfy { CowOrder.verify(json: $0, uid: uid($0), chainId: 1) != nil },
      "all nine real orders hash to their ids")
let o0 = orders[0]
check(CowOrder.verify(json: o0, uid: uid(o0), chainId: 8453) == nil, "the same order is not Base's (the domain carries the chain)")
check(CowOrder.verify(json: edited(o0, "sellAmount", "166000001"), uid: uid(o0), chainId: 1) == nil, "one more base unit sold: refused")
check(CowOrder.verify(json: edited(o0, "receiver", "0x" + String(repeating: "1", count: 40)), uid: uid(o0), chainId: 1) == nil,
      "another receiver: refused")
check(CowOrder.verify(json: edited(o0, "kind", "buy"), uid: uid(o0), chainId: 1) == nil, "sell read as buy: refused")
check(CowOrder.verify(json: edited(o0, "validTo", (o0["validTo"] as! Int) + 1), uid: uid(o0), chainId: 1) == nil,
      "an expiry that is not the id's: refused")
check(CowOrder.verify(json: orders[1], uid: uid(o0), chainId: 1) == nil, "another order's answer for this id: refused")
var shifted = uid(o0); shifted[55] ^= 1
check(CowOrder.verify(json: o0, uid: shifted, chainId: 1) == nil, "an id whose expiry bytes disagree with the hashed order: refused")
check(CowOrder.verify(json: o0, uid: Array(uid(o0).dropLast()), chainId: 1) == nil, "a 55-byte id: refused")

print("parse")
check(CowOrder.parse(edited(o0, "kind", "limit")) == nil, "an unknown kind")
check(CowOrder.parse(edited(o0, "sellAmount", "-1")) == nil && CowOrder.parse(edited(o0, "sellAmount", "1e9")) == nil, "a malformed amount")
check(CowOrder.parse(edited(o0, "appData", "0x1234")) == nil, "a short appData")
check(CowOrder.parse(edited(o0, "buyToken", nil)) == nil, "a missing token")

print("a receiver signed as zero")
var signed = CowOrder.parse(edited(o0, "receiver", nil))!
let digest = CowOrder.digest(signed, chainId: 1)!
let owner = (o0["owner"] as! String).lowercased()
let zeroUID = digest + SafeABI.hexBytes(owner)! + Array(uid(o0).suffix(4))
check(CowOrder.verify(json: o0, uid: zeroUID, chainId: 1)?.receiver == nil, "the API's owner-as-receiver verifies as the zero it was signed as")
signed = CowOrder.parse(o0)!

print("calldata")
func preSign(_ id: [UInt8], _ flag: Bool, offset: Int = 64) -> [UInt8] {
    func w(_ n: Int) -> [UInt8] { Array(repeating: 0, count: 24) + withUnsafeBytes(of: UInt64(n).bigEndian, Array.init) }
    let sel = Array(Keccak256.hash(Array("setPreSignature(bytes,bool)".utf8)).prefix(4))
    return sel + w(offset) + w(flag ? 1 : 0) + w(id.count) + id + Array(repeating: 0, count: (32 - id.count % 32) % 32)
}
check(CowOrder.preSignature(preSign(uid(o0), true)).map { $0.uid == uid(o0) && $0.signed } == true, "the id and true")
check(CowOrder.preSignature(preSign(uid(o0), false))?.signed == false, "…and false")
check(CowOrder.preSignature(preSign(uid(o0), true, offset: 96)) == nil, "an offset that is not the head's end: refused")
check(CowOrder.preSignature(preSign(Array(uid(o0).dropLast()), true)) == nil, "a 55-byte id: refused")

print("the reading")
let tokens: [String: ClearSign.Token] = ["0xdac17f958d2ee523a2206206994597c13d831ec7": .init(ticker: "USDT", decimals: 6),
                                         "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9": .init(ticker: "AAVE", decimals: 18)]
let r = CowOrder.reading(signed, uid: uid(o0), signed: true, safe: owner, token: { tokens[$0] }, address: { $0 }, date: { _ in "the date" })
check(r?.headline == "Sell 166 USDT for at least 1.004078716069741972 AAVE", "a sell order in one sentence: \(r?.headline ?? "nil")")
check(r?.lines.first { $0.label == "Paid to" }?.value == "this Safe" && r?.owner == "Casberi", "paid to this Safe, described by Casberi")
let unknown = CowOrder.reading(signed, uid: uid(o0), signed: true, safe: owner, token: { _ in nil }, address: { $0 }, date: { _ in "" })
check(unknown?.sentence == nil, "unknown decimals: no sentence, base units on the lines")

print("enrich")
let settlement = CowOrder.settlement
let call = SafeCalldata.BatchCall(operation: 0, to: settlement, value: "0", reading: .undecoded(selector: "0xec6cb13f"),
                                  data: SafeABI.hex(preSign(uid(o0), true)))
let other = SafeCalldata.BatchCall(operation: 0, to: settlement, value: "0", reading: .undecoded(selector: "0xec6cb13f"),
                                   data: SafeABI.hex(preSign(uid(orders[1]), true)))
let batch = SafeCalldata.batch([call, other])
check(CowOrder.preSignatures(to: "0x0", data: "0x", reading: batch).count == 2, "both pre-signatures in a batch are found")
let out = CowOrder.enrich(batch, to: "0x0", data: "0x", safe: owner, verified: [SafeABI.hex(uid(o0)): signed],
                          token: { tokens[$0] }, address: { $0 }, date: { _ in "" })
if case .batch(let calls) = out {
    if case .described(let d) = calls[0].reading { check(d.headline.hasPrefix("Sell 166 USDT"), "the verified one is stated") }
    else { check(false, "the verified one is stated") }
    if case .undecoded = calls[1].reading { check(true, "the unverified one keeps its reading") }
    else { check(false, "the unverified one keeps its reading") }
} else { check(false, "the batch stays a batch") }

print("the queue's title")
func multiSend(_ calls: [(to: String, data: [UInt8])]) -> String {
    var packed: [UInt8] = []
    for c in calls {
        packed += [0] + SafeABI.hexBytes(c.to)! + Array(repeating: 0, count: 32)
        packed += Array(repeating: 0, count: 24) + withUnsafeBytes(of: UInt64(c.data.count).bigEndian, Array.init) + c.data
    }
    func w(_ n: Int) -> [UInt8] { Array(repeating: 0, count: 24) + withUnsafeBytes(of: UInt64(n).bigEndian, Array.init) }
    let sel = Array(Keccak256.hash(Array("multiSend(bytes)".utf8)).prefix(4))
    return SafeABI.hex(sel + w(32) + w(packed.count) + packed + Array(repeating: 0, count: (32 - packed.count % 32) % 32))
}
let usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7"
let approve = Array(Keccak256.hash(Array("approve(address,uint256)".utf8)).prefix(4))
    + SafeABI.word(address: "0xc92e8bdf79f0507f65a392b0ab4667716bfe0110")! + SafeABI.word(uint256: "166000000")!
let transfer = Array(Keccak256.hash(Array("transfer(address,uint256)".utf8)).prefix(4))
    + SafeABI.word(address: owner)! + SafeABI.word(uint256: "1")!
let multi = "0x38869bf66a61cf6bdb996a6ae40d5853fd43b526"
let proven: ([UInt8]) -> CowOrder.Order? = { $0 == uid(o0) ? signed : nil }
check(CowOrder.queueTitle(to: multi, data: multiSend([(usdt, approve), (settlement, preSign(uid(o0), true))]), value: "0",
                          operation: 1, order: proven, token: { tokens[$0] })
      == "“Sell 166 USDT for at least 1.004078716069741972 AAVE”", "approve + pre-sign: the order is the row")
check(CowOrder.queueTitle(to: multi, data: multiSend([(usdt, approve), (settlement, preSign(uid(o0), true)), (usdt, transfer)]),
                          value: "0", operation: 1, order: proven, token: { tokens[$0] })?.hasSuffix("and 1 more action") == true,
      "…and a transfer besides: one more action, said")
check(CowOrder.queueTitle(to: multi, data: multiSend([(settlement, preSign(uid(o0), true))]), value: "0",
                          operation: 1, order: { _ in nil }, token: { tokens[$0] }) == nil, "an order not proven: no title")
check(CowOrder.queueTitle(to: settlement, data: SafeABI.hex(preSign(uid(o0), false)), value: "0",
                          operation: 0, order: proven, token: { tokens[$0] }) == nil, "a withdrawal keeps the old wording")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
SWIFT

echo "CowOrder, compiled whole"
xcrun swiftc -Onone -o "$TMP/run" "$COW" "$CLEARSIGN" "$TX" "$KECCAK" "$TMP/main.swift" > "$TMP/build.log" 2>&1 \
  || { echo "✗ the harness did not compile:"; sed -n '1,30p' "$TMP/build.log"; exit 1; }
COW_FIX="$PWD/$FIX" "$TMP/run" || exit 1

echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" from="$2" to="$3"
  cp "$COW" "$TMP/CowOrder.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$TMP/CowOrder.swift" <<'PY' || { echo "  ✗ $name — the mutation did not apply"; exit 1; }
import os, sys
p = sys.argv[1]; s = open(p).read(); f, t = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if f not in s: sys.exit(2)
open(p, "w").write(s.replace(f, t, 1))
PY
  if ! xcrun swiftc -Onone -o "$TMP/mut" "$TMP/CowOrder.swift" "$CLEARSIGN" "$TX" "$KECCAK" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if COW_FIX="$PWD/$FIX" "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}
mutate "an API answer drawn unhashed" \
  'if digest(order, chainId: chainId) == id.digest { return order }' 'return order'
mutate "the chain left out of the domain" \
  'k("Gnosis Protocol") + k("v2") + word(UInt64(chainId)) + settle' 'k("Gnosis Protocol") + k("v2") + word(1) + settle'
mutate "an expiry not checked" \
  'let order = parse(json), order.validTo == id.validTo else { return nil }' 'let order = parse(json) else { return nil }'
mutate "an unverified call given a verified reading" \
  'let p = preSignature(bytes), let order = verified[SafeABI.hex(p.uid)],' 'let p = preSignature(bytes), let order = verified.values.first,'
mutate "sell and buy swapped in the sentence" \
  '? (isSell ? "Sell \(sell.text) for at least \(buy.text)"' '? (isSell ? "Sell \(buy.text) for at least \(sell.text)"'
mutate "the approval counted as another action" \
  'if case .erc20Approve = call.reading { return false }' 'if case .erc20Approve = call.reading { return true }'
echo "✓ CoW order self-test passed"
