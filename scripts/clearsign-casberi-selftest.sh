#!/bin/zsh
# Casberi's own clear-signing descriptors self-test (2026-10-12, prd §1282):
#
#   scripts/support/clearsign-casberi.json   zRouter, zFi's boards, Tacit, CoW
#   scripts/clearsign-casberi.py             merged after the registry snapshot
#
# Real mainnet calldata (scripts/fixtures/clearsign-casberi/mainnet-calls.json)
# and hand-built CoW order ids, read through the SAME `ClearSign` renderer the
# Safe sign block uses. Every failure below is a sign block that says
# something false about money:
#
#   • an exact-output swap described as exact-in — its amounts name the wrong
#     tokens (the descriptor refuses it, so it stays "can't read");
#   • "Swap 0 ETH" for a step that spends the whole balance a step before left;
#   • an NFT bid priced as token units;
#   • a CoW order's owner read off the wrong bytes of its id;
#   • words Casberi wrote drawn under a protocol's name, or over an address the
#     upstream registry already describes.
set -euo pipefail
cd "$(dirname "$0")/.."

CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
BUNDLE="Casberi/Casberi/Resources/ClearSignRegistry.json"
OURS="scripts/support/clearsign-casberi.json"
CALLS="scripts/fixtures/clearsign-casberi/mainnet-calls.json"
for f in "$CLEARSIGN" "$TX" "$KECCAK" "$BUNDLE" "$OURS" "$CALLS" scripts/clearsign-casberi.py; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
grep -q 'clearsign-casberi.py' scripts/clearsign-registry.py \
  || { echo "✗ a fresh registry snapshot would drop Casberi's descriptors"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The committed bundle is the merge of the snapshot and this file, exactly.
cp "$BUNDLE" "$TMP/bundle.json"
CLEARSIGN_BUNDLE="$TMP/bundle.json" CLEARSIGN_CASBERI="$OURS" python3 scripts/clearsign-casberi.py > /dev/null
python3 - "$BUNDLE" "$TMP/bundle.json" <<'PY' || exit 1
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:3])
if a != b:
    sys.exit("✗ the bundled registry is not the merge of clearsign-casberi.json — run scripts/clearsign-casberi.py")
base = a["casberi"]["base"]
if any(d.get("owner") != "Casberi" for d in a["descriptors"][base:]):
    sys.exit("✗ a descriptor past the snapshot does not say owner Casberi")
PY

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what) (line \(line))"); failures += 1 }
}
let env = ProcessInfo.processInfo.environment
let reg = try! JSONDecoder().decode(ClearSign.Registry.self, from: Data(contentsOf: URL(fileURLWithPath: env["CS_BUNDLE"]!)))
let calls = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: env["CS_CALLS"]!))) as! [String: [String: Any]]
var style = ClearSign.Style.canonical
style.rawFallbacks = false
style.address = { $0 }
let tokens: [String: ClearSign.Token] = [
    "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": .init(ticker: "WETH", decimals: 18),
    "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": .init(ticker: "USDC", decimals: 6)]
style.token = { tokens[$0] }

func read(_ name: String, patch: ((inout [UInt8]) -> Void)? = nil, chain: Int = 1) -> ClearSign.Reading? {
    let c = calls[name]!
    var data = SafeABI.hexBytes(c["data"] as! String)!
    patch?(&data)
    return ClearSign.describe(chainId: chain, to: c["to"] as! String, data: data, value: c["value"] as! String,
                              from: c["from"] as? String, style: style, registry: reg)
}
func line(_ r: ClearSign.Reading?, _ label: String) -> [String] { r?.lines.filter { $0.label == label }.map(\.value) ?? [] }
/// Sets argument word `i` (after the selector) to `n`.
func word(_ i: Int, _ n: UInt8) -> (inout [UInt8]) -> Void {
    { d in for b in 0..<32 { d[4 + 32 * i + b] = b == 31 ? n : 0 } }
}

print("zRouter")
let v4 = read("zRouter.swapV4")
check(v4?.headline == "Swap 0.01 ETH for at least 25.44902 USDC", "a V4 swap in one sentence: \(v4?.headline ?? "nil")")
check(v4?.owner == "Casberi", "…described by Casberi, never zFi")
check(line(v4, "Recipient") == ["0xffc5fa5c95e22b2ec1b539eecc2024d3ca62d8ed"], "…to its recipient")
let exactOut = read("zRouter.swapV4", patch: word(1, 1))
// The same bytes with exactOut set: the amount is now what is BOUGHT, in the
// output token, and the limit what may be PAID, in the input token.
check(exactOut?.headline == "Buy exactly 10000000000 USDC for at most 0.00000000002544902 ETH",
      "an exact-output swap names each amount in its own token: \(exactOut?.headline ?? "nil")")
check(line(exactOut, "Sell").isEmpty, "…and never borrows the exact-in wording")
let exactOutV2 = read("zRouter.swapV2", patch: word(1, 1))
check(line(exactOutV2, "Pay at most") == ["0.015354759544905336 ETH"] && line(exactOutV2, "Buy exactly").first?.contains("0xde34") == true,
      "a V2 exact-output swap: the limit in ETH, the exact amount in its token")
let multi = read("zRouter.multicall")
check(multi?.intent == "Several zFi steps" && line(multi, "Step").count == 2, "a batch reads each step")
check(!(multi?.lines.contains { $0.value.contains("Swap 0 ") } ?? true), "a step spending the whole balance never says \"Swap 0\"")
check(read("zRouter.swapV4", chain: 137) == nil, "no descriptor on a chain zRouter is not listed for")

print("zFi boards")
check(read("Swapboard.cancelOrder")?.headline == "Cancel an order" && line(read("Swapboard.cancelOrder"), "Order") == ["14"],
      "cancel order 14")
check(read("Dutchboard.cancelUnwrap")?.headline == "Cancel an auction", "cancel an auction")
let nftBid = read("Floorboard.bid")
check(nftBid?.intent == "Bid on NFTs" && line(nftBid, "Pieces") == ["5"] && line(nftBid, "Up to") == ["0.015 ETH"],
      "an NFT bid counts pieces, never token units")
check(line(nftBid, "Collection") == ["0x00000000008835cef3e0d2333695f288ee6b63a6"] && line(nftBid, "Only ids").isEmpty,
      "…names its collection; a floor bid lists no ids")
let tokenBid = read("Floorboard.bid", patch: word(8, 0))
check(tokenBid?.intent == "Place a bid" && line(tokenBid, "Opening bid") == ["0.005 ETH"] && line(tokenBid, "Up to") == ["0.015 ETH"],
      "a token bid: opening 0.005 ETH, up to 0.015 ETH")
check(line(tokenBid, "Rises over") == ["168:00:00"], "…rising over a week")

print("Tacit")
let deposit = read("TacitPool.transact-deposit")
check(line(deposit, "Deposit") == ["0.01 ETH"] && line(deposit, "Withdraws to").isEmpty, "a deposit: its value, no recipient")
let withdraw = read("TacitPool.transact")
check(line(withdraw, "Deposit").isEmpty && line(withdraw, "Withdraws to").count == 1, "a withdrawal: its recipient, no deposit")
check(read("TacitZap.zapTokenWithPermit")?.headline == "Deposit 9.19956 USDC into Tacit", "a token zapped in")
check(read("WrapTip.wrapWithTip")?.headline == "Deposit 0.4 ETH into Tacit", "an ETH wrap into the confidential pool")

print("CoW Protocol")
let settlement = "0x9008d19f58aabd9ed0d60971565aa8510560ab41"
let owner = "0x5afe5afe5afe5afe5afe5afe5afe5afe5afe5afe"
func preSign(_ uid: [UInt8], signed: Bool) -> [UInt8] {
    let sel: [UInt8] = Array(Keccak256.hash(Array("setPreSignature(bytes,bool)".utf8)).prefix(4))
    func w(_ n: Int) -> [UInt8] { Array(repeating: 0, count: 28) + withUnsafeBytes(of: UInt32(n).bigEndian, Array.init) }
    let padded = uid + Array(repeating: 0, count: (32 - uid.count % 32) % 32)
    return sel + w(64) + w(signed ? 1 : 0) + w(uid.count) + padded
}
let digest = [UInt8](repeating: 0xab, count: 32)
let validTo: [UInt8] = [0x6a, 0x00, 0x00, 0x00]   // 1778384896, 2026-05-10
let uid = digest + SafeABI.hexBytes(owner)! + validTo
let cow = ClearSign.describe(chainId: 8453, to: settlement, data: preSign(uid, signed: true), style: style, registry: reg)
check(cow?.intent == "Sign a CoW Protocol order" && line(cow, "Approval") == ["Approve the order"], "a pre-signature approves an order")
check(line(cow, "Order owner") == [owner], "…its owner read off bytes 32–52 of the id")
check(line(cow, "Valid until") == ["2026-05-10 03:48:16Z"], "…valid until its last four bytes")
check(line(ClearSign.describe(chainId: 1, to: settlement, data: preSign(uid, signed: false), style: style, registry: reg), "Approval")
      == ["Withdraw approval"], "signed false withdraws it")
// An order id that is not 56 bytes is not refused here (the renderer clamps a
// slice); GPv2Settlement reverts on it (`extractOrderUidParams`), so it cannot
// execute. Pinned in prd §1282.
check(ClearSign.describe(chainId: 1, to: settlement, data: preSign(uid, signed: true), style: style, registry: reg) != nil,
      "the same order on Ethereum")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
SWIFT

build() { xcrun swiftc -Onone -o "$1" "$CLEARSIGN" "$TX" "$KECCAK" "$TMP/main.swift" 2>"$TMP/build.log"; }
echo "Casberi's descriptors through ClearSign, compiled whole"
build "$TMP/run" || { echo "✗ the harness did not compile:"; sed -n '1,30p' "$TMP/build.log"; exit 1; }
CS_BUNDLE="$PWD/$BUNDLE" CS_CALLS="$PWD/$CALLS" "$TMP/run" || exit 1

echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" from="$2" to="$3"
  cp "$BUNDLE" "$TMP/m-bundle.json"
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$OURS" "$TMP/m-ours.json" <<'PY'
import os, sys
s = open(sys.argv[1]).read(); f, t = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if f not in s: sys.exit(2)
open(sys.argv[2], "w").write(s.replace(f, t, 1))
PY
  then echo "  ✗ $name — the mutation did not apply"; exit 1; fi
  if ! CLEARSIGN_BUNDLE="$TMP/m-bundle.json" CLEARSIGN_CASBERI="$TMP/m-ours.json" python3 scripts/clearsign-casberi.py > /dev/null 2>&1; then
    echo "  ✓ $name (refused by the merge)"; return
  fi
  if CS_BUNDLE="$TMP/m-bundle.json" CS_CALLS="$PWD/$CALLS" "$TMP/run" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}
mutate "an exact-output swap's tokens swapped" \
  '"label": "Buy exactly",
       "format": "tokenAmount",
       "visible": "always",
       "params": {
        "tokenPath": "tokenOut",' \
  '"label": "Buy exactly",
       "format": "tokenAmount",
       "visible": "always",
       "params": {
        "tokenPath": "tokenIn",'
mutate "a condition that never matches" '"equals": "true"' '"equals": "1"'
mutate "a whole-balance step read as zero" \
  '"path": "amountIn",
       "label": "Sell",
       "format": "tokenAmount",
       "visible": {
        "ifNotIn": [
         "0"
        ]
       }' \
  '"path": "amountIn",
       "label": "Sell",
       "format": "tokenAmount",
       "visible": "always"'
mutate "an NFT bid priced as tokens" \
  '"path": "terms.isNFT",
      "equals": "true"' \
  '"path": "terms.isNFT",
      "equals": "false"'
mutate "a CoW owner off the wrong bytes" '"orderUid.[32:52]"' '"orderUid.[0:20]"'
mutate "Casberi's words under zFi's name" '"owner": "Casberi",
   "name": "zRouter (zFi)"' '"owner": "zFi",
   "name": "zRouter (zFi)"'

# The matcher itself (ClearSign.swift): a condition that is not checked.
cp "$CLEARSIGN" "$TMP/ClearSign.swift"
python3 - "$TMP/ClearSign.swift" <<'PY' || { echo "  ✗ a condition not checked — the mutation did not apply"; exit 1; }
import sys
p = sys.argv[1]; s = open(p).read()
f = "return values[0].comparable == ClearSign.comparable(when.equals)"
if f not in s: sys.exit(2)
open(p, "w").write(s.replace(f, "return true", 1))
PY
if xcrun swiftc -Onone -o "$TMP/mut" "$TMP/ClearSign.swift" "$TX" "$KECCAK" "$TMP/main.swift" 2>/dev/null \
   && CS_BUNDLE="$PWD/$BUNDLE" CS_CALLS="$PWD/$CALLS" "$TMP/mut" > /dev/null 2>&1; then
  echo "  ✗ a condition not checked — the harness still passed"; exit 1
fi
echo "  ✓ a condition not checked"

echo "✓ Casberi clear-signing descriptors self-test passed"
