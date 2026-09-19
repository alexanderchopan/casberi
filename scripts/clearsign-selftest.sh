#!/bin/zsh
# Casberi clear-signing self-test — ERC-7730 descriptors read on the device
# (prd §834):
#
#   Casberi/Casberi/Model/ClearSign.swift            compiled WHOLE
#   Casberi/Casberi/Model/SafeTransaction.swift      compiled WHOLE (the reader that asks it)
#   Casberi/Casberi/Model/Keccak256.swift            their one dependency
#   Casberi/Casberi/Resources/ClearSignRegistry.json the bundled snapshot
#   scripts/support/clearsign-vectors.json           the registry's OWN test vectors
#
# WHY. The Safe sign block is the one screen where a fluent wrong summary costs
# money, and a descriptor-driven summary is fluent by construction. So this
# holds the renderer to the registry's own answers — every test transaction the
# registry ships for a contract on the Safe room's six chains, with the display
# its maintainers expect — and to the refusals that make it safe to show:
#
#   1. hostile calldata (an offset or length built to overflow) is REFUSED,
#      never a crash and never a partial reading
#   2. a `mustMatch` rule that fails withdraws the whole reading
#   3. two formats sharing a selector describe nothing (the spec's rule)
#   4. an amount whose token is unknown never lands inside a sentence
#   5. the Safe reader's own cases keep priority — a USDT `transfer` stays a
#      transfer even though USDT has a descriptor — and with no chain it never
#      asks the registry at all
#   6. the snapshot and the vectors come from the SAME registry commit
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
#   scripts/clearsign-selftest.sh [--self-test]
set -euo pipefail
cd "$(dirname "$0")/.."

CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
BUNDLE="Casberi/Casberi/Resources/ClearSignRegistry.json"
VECTORS="scripts/support/clearsign-vectors.json"
for f in "$CLEARSIGN" "$TX" "$KECCAK" "$BUNDLE" "$VECTORS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- 6. one registry commit --------------------------------------------------------
python3 - "$BUNDLE" "$VECTORS" <<'PY' || exit 1
import json, sys
b, v = (json.load(open(p)) for p in sys.argv[1:3])
if b["source"]["commit"] != v["source"]["commit"]:
    sys.exit(f"✗ the bundle ({b['source']['commit'][:10]}) and the vectors ({v['source']['commit'][:10]}) "
             "come from different registry commits — re-run scripts/clearsign-registry.py")
if len(b["descriptors"]) < 100 or len(v["vectors"]) < 300:
    sys.exit("✗ the snapshot shrank below 100 descriptors / 300 vectors — the generator lost most of the registry")
PY

# ClearSign.swift must stay compilable whole: it may reach nothing but Foundation.
CODE=$(grep -vE '^[[:space:]]*//' "$CLEARSIGN")
for reach in 'URLSession' 'import SwiftUI' 'import SwiftData' 'import UIKit' 'UserDefaults' 'WalletStore'; do
  printf '%s' "$CODE" | grep -q "$reach" \
    && { echo "✗ ClearSign.swift reached $reach — it must stay Foundation-only (and never read a descriptor off the network)"; exit 1; }
done

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failed = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failed += 1 }
}
func bytes(_ h: String) -> [UInt8] {
    var s = h.hasPrefix("0x") ? String(h.dropFirst(2)) : h
    var out: [UInt8] = []
    while s.count >= 2 { out.append(UInt8(s.prefix(2), radix: 16)!); s.removeFirst(2) }
    return out
}
func hex(_ b: [UInt8]) -> String { "0x" + Keccak256.hexString(b) }
func word(_ n: UInt64) -> [UInt8] {
    Array(repeating: 0, count: 24) + (0..<8).map { UInt8((n >> (8 * (7 - $0))) & 0xff) }
}

let args = CommandLine.arguments
let registry = try! JSONDecoder().decode(ClearSign.Registry.self,
                                         from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let root = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]

// --- the registry's own vectors ------------------------------------------------------
// Allowed to differ, each with its reason. A stale allowance fails too.
let allowed: [String: String] = [
    // The WCT descriptor names its own token (metadata.token: WCT, 18), which
    // the renderer uses; the registry's fixture gives its data provider no WCT,
    // so its expected output is the bare integer. Ours is the better reading.
    "walletconnect/testsv2/calldata-wct": "descriptor names its own token",
]
var passed = 0, allowedSeen = Set<String>()
let vectors = root["vectors"] as! [[String: Any]]
for v in vectors {
    let file = v["file"] as! String
    let tokens = (v["tokens"] as? [String: [String: Any]]) ?? [:]
    let names = (v["names"] as? [String: String]) ?? [:]
    let collections = (v["collections"] as? [String: String]) ?? [:]
    var style = ClearSign.Style.canonical
    style.token = { a in
        guard let t = tokens[a], let tk = t["ticker"] as? String, let d = t["decimals"] as? Int else { return nil }
        return ClearSign.Token(ticker: tk, decimals: d)
    }
    style.name = { names[$0] }
    style.collection = { collections[$0] }
    let expected = v["expected"] as! [String: Any]
    var diffs: [String] = []
    if let r = ClearSign.describe(chainId: v["chainId"] as! Int, to: v["to"] as! String,
                                  data: bytes(v["data"] as! String), value: v["value"] as! String,
                                  from: v["from"] as? String, style: style, registry: registry) {
        if let intent = expected["intent"] as? String, intent != r.intent {
            diffs.append("intent \(r.intent) ≠ \(intent)")
        }
        if let sentence = expected["interpolatedIntent"] as? String, sentence != r.sentence {
            diffs.append("sentence \(r.sentence ?? "nil") ≠ \(sentence)")
        }
        let got = r.lines.map { "\($0.label)=\($0.value)" }
        // An EMPTY expected value is the registry tool declining to render
        // embedded calldata; any value of ours stands there.
        let want = ((expected["fields"] as? [[String: Any]]) ?? []).enumerated().map { i, f -> String in
            let w = "\(f["label"] as? String ?? "")=\(f["value"] as? String ?? "")"
            return w.hasSuffix("=") && i < got.count && got[i].hasPrefix(w) ? got[i] : w
        }
        if got != want { diffs.append("fields \(got) ≠ \(want)") }
    } else {
        diffs.append("no reading")
    }
    if diffs.isEmpty {
        passed += 1
    } else if allowed[file] != nil {
        allowedSeen.insert(file)
    } else {
        check(false, "\(file) — \(v["description"] ?? ""): " + diffs.joined(separator: "; "))
    }
}
for file in allowed.keys where !allowedSeen.contains(file) {
    check(false, "allowance for \(file) is stale — it matches now; delete it")
}
check(passed >= 300, "only \(passed) registry vectors matched")

// --- 1. hostile calldata ---------------------------------------------------------------
// Uniswap's `exactInput((bytes path, …) params)` — a dynamic tuple, so every
// offset and length word is reachable from the outside.
let router = "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45"
let exactInput = registry.descriptors[registry.contracts["1:" + router]!].formats
    .first { $0.key.hasPrefix("exactInput(") }!
let selector = ClearSign.Function(key: exactInput.key)!.selector
func hostile(_ tail: [UInt8], _ what: String) {
    let r = ClearSign.describe(chainId: 1, to: router, data: selector + tail, registry: registry)
    check(r == nil, "hostile calldata was described: \(what)")
}
hostile(word(UInt64.max), "tuple offset near UInt64.max")
hostile(word(UInt64(Int32.max)), "tuple offset past the buffer")
hostile(word(0x20) + word(0x80) + word(0x20), "tuple head truncated")
// params at 0x20; inside it `path`'s offset 0x80 lands on the sixth word,
// which claims a length of 2^31 over a 192-byte buffer.
hostile(word(0x20) + word(0x80) + word(0) + word(1) + word(1) + word(UInt64(Int32.max)),
        "bytes length near Int32.max")
hostile(word(0x20) + word(0x80) + word(0) + word(1) + word(1) + word(UInt64.max),
        "bytes length near UInt64.max")
hostile([], "no arguments at all")
hostile([0x01, 0x02], "a stub under one word")

// --- 2, 3. a synthetic registry ---------------------------------------------------------
let synthetic = """
{"source":{"repo":"x","commit":"x","date":"x"},
 "contracts":{"1:0x00000000000000000000000000000000000000aa":0,"1:0x00000000000000000000000000000000000000bb":1},
 "tokens":{},
 "descriptors":[
  {"owner":"Test","name":"Guarded","formats":[
    {"key":"guarded(uint256 mode,uint256 amount)","intent":"Guarded","interpolatedIntent":"Move {amount}",
     "fields":[{"path":"mode","visible":{"mustMatch":["1"]}},
               {"path":"amount","label":"Amount","format":"tokenAmount","params":{"token":"0x00000000000000000000000000000000000000cc"}}]}]},
  {"owner":"Test","name":"Twins","formats":[
    {"key":"twin(uint256 a)","intent":"One","fields":[]},
    {"key":"twin(uint256 b)","intent":"Two","fields":[]}]}
 ]}
"""
let fake = try! JSONDecoder().decode(ClearSign.Registry.self, from: Data(synthetic.utf8))
let guardedSel = ClearSign.Function(key: "guarded(uint256 mode,uint256 amount)")!.selector
let guardedTo = "0x00000000000000000000000000000000000000aa"
let ok = ClearSign.describe(chainId: 1, to: guardedTo, data: guardedSel + word(1) + word(5_000_000), registry: fake)
check(ok != nil, "a call that passes mustMatch was not described")
check(ClearSign.describe(chainId: 1, to: guardedTo, data: guardedSel + word(2) + word(5_000_000),
                         registry: fake) == nil,
      "a failed mustMatch still produced a reading")
let twinSel = ClearSign.Function(key: "twin(uint256 a)")!.selector
check(ClearSign.describe(chainId: 1, to: "0x00000000000000000000000000000000000000bb",
                         data: twinSel + word(1), registry: fake) == nil,
      "two formats sharing a selector still described a call")

// --- 4. an unknown token never lands inside a sentence ----------------------------------
var app = ClearSign.Style.canonical
app.rawFallbacks = false
let unknown = ClearSign.describe(chainId: 1, to: guardedTo, data: guardedSel + word(1) + word(5_000_000),
                                 style: app, registry: fake)
check(unknown?.sentence == nil, "an unknown token's amount landed in a sentence: \(unknown?.sentence ?? "")")
check(unknown?.lines.first?.value.hasPrefix("5000000 base units of") == true,
      "an unknown token's amount is not stated in base units: \(unknown?.lines.first?.value ?? "nil")")
app.token = { _ in ClearSign.Token(ticker: "USDC", decimals: 6) }
let known = ClearSign.describe(chainId: 1, to: guardedTo, data: guardedSel + word(1) + word(5_000_000),
                               style: app, registry: fake)
check(known?.sentence == "Move 5 USDC", "a known token's sentence reads \(known?.sentence ?? "nil")")

// --- 5. the Safe reader keeps priority ---------------------------------------------------
// `SafeCalldata.read` opens the BUNDLED snapshot (ClearSign.shared), which the
// harness places beside this binary.
check(ClearSign.shared != nil, "the bundled snapshot did not load from beside the binary")
let usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7"
let safe = "0x00000000000000000000000000000000000000ee"
let transfer = hex(Array(bytes(SafeCalldata.selector("transfer(address,uint256)"))) + word(0xabc) + word(7))
if case .erc20Transfer = SafeCalldata.read(data: transfer, to: usdt, value: "0", safe: safe, chainId: 1) {} else {
    check(false, "a USDT transfer was not read as a transfer once the registry was open")
}
// A Morpho call the reader has no case for (not a transfer/approve/transferFrom).
let named: Set<String> = ["0xa9059cbb", "0x095ea7b3", "0x23b872dd"]
let morpho = vectors.first {
    ($0["file"] as! String).hasPrefix("morpho/") && ($0["chainId"] as! Int) == 1
        && !named.contains(String(($0["data"] as! String).prefix(10)))
}!
let described = SafeCalldata.read(data: morpho["data"] as! String, to: morpho["to"] as! String,
                                  value: "0", safe: safe, chainId: 1)
if case .described(let r) = described {
    check(r.owner != nil && !r.lines.isEmpty, "a described Morpho call carries no owner or lines")
} else {
    check(false, "a Morpho call the registry describes read as \(described)")
}
if case .undecoded = SafeCalldata.read(data: morpho["data"] as! String, to: morpho["to"] as! String,
                                       value: "0", safe: safe) {} else {
    check(false, "with no chain the reader still asked the registry")
}

print("  \(passed)/\(vectors.count) registry vectors match (\(allowedSeen.count) allowed)")
if failed > 0 { print("\n✗ \(failed) clear-signing check(s) failed"); exit(1) }
SWIFT

build() {   # <clearsign.swift> <out>
  xcrun swiftc -Onone -o "$2" "$1" "$TX" "$KECCAK" "$TMP/main.swift" 2>/dev/null
}
run() {     # <binary>
  cp "$BUNDLE" "$(dirname "$1")/ClearSignRegistry.json"
  "$1" "$BUNDLE" "$VECTORS"
}
echo "clearsign-selftest: compiling ClearSign + SafeTransaction + Keccak256 WHOLE…"
build "$CLEARSIGN" "$TMP/run" \
  || { echo "✗ the harness did not compile — ClearSign.swift is no longer Foundation-only"; exit 1; }
run "$TMP/run" || exit 1

# --- does this check catch anything? (--self-test) -------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
  echo
  echo "self-test: each mutation below MUST be caught"
  st_fail=0
  mkdir -p "$TMP/mut"
  mutate() {   # <perl-expr> <name>
    local out="$TMP/mut/ClearSign.swift"
    perl -0pe "$1" "$CLEARSIGN" > "$out"
    if cmp -s "$out" "$CLEARSIGN"; then
      echo "  FAIL mutation never applied (anchor drifted): $2"; st_fail=1; return
    fi
    if build "$out" "$TMP/mut/run" && run "$TMP/mut/run" >/dev/null 2>&1; then
      echo "  FAIL not caught: $2"; st_fail=1
    else
      echo "  ok   caught: $2"
    fi
  }
  mutate 's/parts\.allSatisfy\(\\\.clean\) else \{ return nil \}/true else { return nil }/' \
         "an unclean value allowed inside a sentence"
  mutate 's/return values\.allSatisfy\(\{ matches\(\$0, list\) \}\) \? \.hidden : \.refused/return .hidden/' \
         "a failed mustMatch hidden instead of refused"
  mutate 's/if matched != nil \{ return nil \}/if matched != nil { continue }/' \
         "a duplicate selector no longer refused"
  mutate 's/guard let length = int\(data, at\), length <= data\.count - at - 32 else \{ return nil \}/guard let length = int(data, at) else { return nil }/' \
         "a bytes length no longer bounded by the buffer"
  mutate 's/let cut = padded\.index\(padded\.endIndex, offsetBy: -decimals\)/let cut = padded.index(padded.endIndex, offsetBy: -decimals + 1)/' \
         "token decimals shifted by one"
  mutate 's/!less\(word, threshold\)/less(word, threshold)/' \
         "the unlimited threshold compared the wrong way"
  mutate 's/case \.address: return "address"/case .address: return "addr"/' \
         "a canonical type spelled wrong (every selector changes)"
  (( st_fail == 0 )) || { echo "✗ a mutation survived"; exit 1; }
  echo "  ✓ every mutation caught"
fi

echo
echo "✓ clear signing: the registry's own vectors read as its maintainers expect, and every refusal holds"
