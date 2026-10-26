#!/bin/zsh
# private-money-selftest.sh — Move to private and the private rows (prd §1547).
#
# Compiles the pure halves WHOLE and drives them:
#   - the ASP's answer: pending and unknown are waiting, approved, rejected,
#     poi_required; anything else changes nothing; asked by the label's HASH;
#   - Holdings' rows: one per token and state, summed, private first, a
#     waiting row dated by its oldest note;
#   - amounts: "0.001" ⇄ base units ⇄ 0x-hex, the ladder the balance allows
#     after the gas a first move keeps back;
#   - the testnet transaction's bytes, against viem 2.45.3's own
#     serialisation (unsigned, signed with each parity, a 70-byte payload so
#     the long-length head is used), and no transaction for a non-testnet;
#   - where the engine's node requests go: logs to the node that keeps them,
#     back to the network's own node past its head, a 429 waited out.
# It also asserts the USE: the store asks by `labelHash`, the engine's door
# routes before it sends, the deposit is kept with the engine's label hash,
# Sepolia's first block is the keystore's, the sender is DEBUG-only and its
# key device-only, and the bundle carries the label hash. Mutations prove the
# assertions bite, each checked to have CHANGED the source.
set -euo pipefail
cd "$(dirname "$0")/.."
PM="Casberi/Casberi/Model/PrivateMoney.swift"
TX="Casberi/Casberi/Model/TestnetTx.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
WIRE="Casberi/Casberi/Model/PrivacyEngineWire.swift"
ART="Casberi/Casberi/Model/PrivacyArtifacts.swift"
PINS="Casberi/Casberi/Model/PrivacyArtifactPins.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
STORE="Casberi/Casberi/Model/PrivateMoneyStore.swift"
MOVE="Casberi/Casberi/Model/PrivateMove.swift"
SENDER="Casberi/Casberi/Model/PrivacyTestnetSender.swift"
ENGINE="Casberi/Casberi/Model/PrivacyEngine.swift"
ENGJS="tools/privacy-pools-engine/src/engine.js"
BUNDLE="Casberi/Casberi/Resources/privacy-engine.js"
for f in "$PM" "$TX" "$KECCAK" "$WIRE" "$ART" "$PINS" "$REACH" "$STORE" "$MOVE" "$SENDER" "$ENGINE" "$ENGJS" "$BUNDLE"; do
    [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
echo "private-money self-test"

use() { grep -qF -- "$2" "$1" || { echo "✗ $3"; exit 1; } }
use "$STORE" 'PrivateMoney.statusURL(aspUrl: PrivacyNetwork.sepolia.aspUrl, labelHash: note.labelHash)' "the store no longer asks the ASP by the label's hash"
use "$MOVE" 'labelHash: deposit.labelHash' "a deposit is no longer kept with the engine's label hash"
use "$ENGINE" 'let routed = PrivacyEngineWire.routed(url, body: text, rpcUrl: network.rpcUrl,' "the engine's door no longer routes log reads"
use "$ENGINE" 'await Self.send(request, to: routed, fallback: url)' "the engine's door no longer sends the routed request"
use "$WIRE" 'fromBlock: 10_932_354)' "Sepolia's first block is no longer the keystore's (10,932,354)"
use "$ENGJS" 'labelHash: await labelHashOf(r.pendingNote.label),' "the engine no longer returns a deposit's label hash"
use "$BUNDLE" 'labelHash' "the shipped bundle has no label hash — rebuild with tools/privacy-pools-engine/build.mjs"
[[ $(head -1 "$SENDER") == "#if DEBUG" && $(tail -1 "$SENDER") == "#endif" ]] || { echo "✗ the testnet sender is not DEBUG-only"; exit 1; }
use "$SENDER" 'kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,' "the testnet sender's key is not device-only"
use "$SENDER" 'kSecAttrSynchronizable as String: false,' "the testnet sender's key may sync"
use "$SENDER" 'guard let tx = TestnetTx.Tx(chainId: network.chainId,' "the sender no longer builds through TestnetTx's testnet guard"
awk '/static var available: Bool/,/^    }$/' "$MOVE" | grep -q '#else' || { echo "✗ Move to private is no longer DEBUG-only"; exit 1; }
echo "  ok   asked by hash, routed before sent, the keystore's first block, a DEBUG-only device-only sender"

TMP=$(mktemp -d /tmp/private-money-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
enum DS { static let device = "Casberi" }
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias P = PrivateMoney

// The ASP's answer.
func asp(_ s: String) -> P.Status? { P.status(asp: Data(s.utf8)) }
check(asp(#"{"status":"pending"}"#) == .waiting, "pending is waiting")
check(asp(#"{"status":"unknown"}"#) == .waiting, "unknown is waiting (not indexed yet)")
check(asp(#"{"status":"approved","timestamp":1}"#) == .approved, "approved")
check(asp(#"{"status":"rejected"}"#) == .rejected, "rejected")
check(asp(#"{"status":"poi_required"}"#) == .needsProof, "poi_required needs proof")
check(asp(#"{"status":"teapot"}"#) == nil && asp("<html>") == nil && asp("{}") == nil, "anything else changes nothing")
check(P.statusURL(aspUrl: "https://api-dev.0xbow.io", labelHash: "1926704")?.absoluteString == "https://api-dev.0xbow.io/labels/1926704/status",
      "the status URL carries the hash")
check(P.statusURL(aspUrl: "https://api-dev.0xbow.io", labelHash: "0x1a2b") == nil, "a hex label is never asked")
check(P.statusURL(aspUrl: "https://api-dev.0xbow.io", labelHash: "12/../x") == nil, "a path is never asked")

// Rows.
let t0 = Date(timeIntervalSince1970: 1_000_000), t1 = t0.addingTimeInterval(60)
func note(_ c: String, _ amount: String, _ s: P.Status, _ at: Date = t0, _ sym: String = "ETH") -> P.Note {
    .init(commitment: c, label: "0x1", labelHash: "1", symbol: sym, amount: amount, decimals: 18, chainId: 11155111, tx: "0x", at: at, status: s)
}
let notes = [note("a", "1000000000000000", .approved), note("b", "3000000000000000", .approved),
             note("c", "1000000000000000", .waiting, t1), note("d", "500000000000000", .needsProof, t0),
             note("e", "2000000000000000", .rejected), note("f", "7", .approved, t0, "USDC")]
let rows = P.rows(notes)
check(rows.map(\.id) == ["0:ETH", "0:USDC", "1:ETH", "2:ETH"], "private first, then waiting, then refused, A–Z within (\(rows.map(\.id)))")
check(rows.first?.amount == "4000000000000000", "a token's private notes are summed")
check(rows[2].amount == "1500000000000000" && rows[2].since == t0, "a waiting row sums its notes and dates from the oldest")
check(rows[0].since == nil, "a private row has no since")
check(rows[0].title == "ETH, private" && rows[2].title == "ETH, moving in" && rows[3].title == "ETH, not approved", "the rows' names")
check(P.rows([note("z", "0", .approved), note("y", "x", .approved)]).isEmpty, "a zero or unreadable amount draws nothing")
check(P.anyWaiting(notes) && !P.anyWaiting([note("a", "1", .approved)]), "waiting is asked again, approved is not")
check(P.held(notes, symbol: "ETH") == Decimal(string: "4000000000000000"), "held counts approved notes only")

// Amounts.
check(P.figure("1000000000000000", decimals: 18, symbol: "ETH") == "0.001 ETH", "0.001 ETH (\(P.figure("1000000000000000", decimals: 18, symbol: "ETH")))")
check(P.baseUnits("0.001", decimals: 18) == "1000000000000000", "0.001 ETH in wei")
check(P.baseUnits("1", decimals: 18) == "1000000000000000000", "1 ETH in wei")
check(P.baseUnits("0.0000000000000000001", decimals: 18) == nil, "more places than the token has is refused")
check(P.baseUnits("0", decimals: 18) == nil && P.baseUnits("abc", decimals: 18) == nil && P.baseUnits("-1", decimals: 18) == nil, "nothing that is not a positive amount")
check(P.hex("1000000000000000") == "0x38d7ea4c68000", "wei to 0x-hex")
check(P.hex("0") == "0x0" && P.hex("255") == "0xff" && P.hex("0x1") == nil, "0, 255 and a non-decimal")
check(P.reserve(gasPrice: "1000") == "4400000000", "the reserve is the budget at twice the price")
check(P.choices(balance: "6000000000000000", reserve: "1000000000000000") == ["0.0001", "0.0005", "0.001", "0.005"], "the ladder the balance allows after the reserve")
check(P.choices(balance: "1000000000000000", reserve: "1000000000000000").isEmpty, "nothing when the reserve takes it all")

// The testnet transaction, against viem.
let data70 = "0x" + String(repeating: "ab", count: 70)
let tx = TestnetTx.Tx(chainId: 11155111, nonce: "0x7", maxPriorityFeePerGas: "0xf4240", maxFeePerGas: "0x9502f900", gas: "0x10c8e0",
                      to: "0xEB3e3961008952348445513e418ad6F43C23ca9a", value: "0x38d7ea4c68000", data: data70)!
check(TestnetTx.hex(tx.unsigned) == "0x02f87883aa36a707830f4240849502f9008310c8e094eb3e3961008952348445513e418ad6f43c23ca9a87038d7ea4c68000b846" + String(repeating: "ab", count: 70) + "c0",
      "the unsigned payload is viem's")
check(TestnetTx.hex(tx.signingHash) == "0xdd20d0f8081f4084fbd091675298005740de494d2802dbc7224054e2407b54cf", "the signing hash is viem's")
let r1 = [UInt8(0)] + [UInt8](repeating: 0x11, count: 31), s1 = [UInt8](repeating: 0x22, count: 32)
check(tx.signed(yParity: 1, r: r1, s: s1).map(TestnetTx.hex) == "0x02f8ba83aa36a707830f4240849502f9008310c8e094eb3e3961008952348445513e418ad6f43c23ca9a87038d7ea4c68000b846" + String(repeating: "ab", count: 70) + "c0019f" + String(repeating: "11", count: 31) + "a0" + String(repeating: "22", count: 32),
      "signed, parity 1, a leading zero byte dropped from r")
let tx0 = TestnetTx.Tx(chainId: 11155111, nonce: "0x0", maxPriorityFeePerGas: "0xf4240", maxFeePerGas: "0x9502f900", gas: "0x10c8e0",
                       to: "0xEB3e3961008952348445513e418ad6F43C23ca9a", value: "0x0", data: "0x")!
check(TestnetTx.hex(tx0.unsigned) == "0x02ea83aa36a780830f4240849502f9008310c8e094eb3e3961008952348445513e418ad6f43c23ca9a8080c0", "zero nonce, value and data")
check(tx0.signed(yParity: 0, r: [UInt8](repeating: 0x33, count: 32), s: [0, 0] + [UInt8](repeating: 0x44, count: 30)).map(TestnetTx.hex)
      == "0x02f86b83aa36a780830f4240849502f9008310c8e094eb3e3961008952348445513e418ad6f43c23ca9a8080c080a0" + String(repeating: "33", count: 32) + "9e" + String(repeating: "44", count: 30),
      "signed, parity 0")
check(tx.signed(yParity: 2, r: r1, s: s1) == nil && tx.signed(yParity: 0, r: [1], s: s1) == nil, "a bad signature is refused")
for chain in [1, 8453, 4663, 84532] {
    check(TestnetTx.Tx(chainId: chain, nonce: "0x0", maxPriorityFeePerGas: "0x1", maxFeePerGas: "0x1", gas: "0x1",
                       to: "0xEB3e3961008952348445513e418ad6F43C23ca9a", value: "0x0", data: "0x") == nil, "no transaction on chain \(chain)")
}
check(TestnetTx.Tx(chainId: 11155111, nonce: "0x0", maxPriorityFeePerGas: "0x1", maxFeePerGas: "0x1", gas: "0x1",
                   to: "0xEB3e", value: "0x0", data: "0x") == nil, "a short address is refused")

// Where the engine's node requests go.
typealias W = PrivacyEngineWire
let node = "https://ethereum-sepolia-rpc.publicnode.com", logs = PrivacyNetwork.sepoliaLogsUrl
func route(_ url: String, _ body: String?) -> String { W.routed(URL(string: url)!, body: body, rpcUrl: node, logsUrl: logs).absoluteString }
check(route(node, #"{"jsonrpc":"2.0","id":1,"method":"eth_getLogs","params":[]}"#) == logs, "a log read goes to the node that keeps them")
check(route(node, #"[{"method":"eth_blockNumber"},{"method":"eth_getLogs"}]"#) == logs, "a batch with a log read goes there too")
check(route(node, #"{"method":"eth_call"}"#) == node, "anything else stays on the network's node")
check(route("https://api-dev.0xbow.io/x", #"{"method":"eth_getLogs"}"#) == "https://api-dev.0xbow.io/x", "another host is never routed")
check(route(node, nil) == node && route(node, "not json") == node, "no body stays")
check(W.missesHead(#"{"error":{"message":"block range extends beyond current head block"}}"#), "past the head goes back")
check(!W.missesHead(#"{"result":[]}"#), "an answer stays")
check(W.throttled(status: 429, body: "") && W.throttled(status: 200, body: #"{"error":{"message":"Too Many Requests"}}"#), "a 429 is waited out")
check(!W.throttled(status: 200, body: #"{"result":"0x1"}"#), "an answer is not throttled")
check(PrivacyNetwork.sepolia.fromBlock == 10_932_354, "Sepolia scans from the keystore's first block")
check(PrivacyNetwork.sepolia.hosts.contains("sepolia.gateway.tenderly.co"), "the logs node is the network's host")
let engine = NetworkReach.endpoint(forService: "Privacy Pools engine")
check(engine.map { W.allows(URL(string: logs + "/")!, declared: $0.hosts) } == true, "the logs node is declared for the engine")
check(engine?.refusesTor.contains("sepolia.gateway.tenderly.co") == true, "the logs node is listed as refusing Tor")

if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
print("ok")
SWIFT

compile_and_run() {
    swiftc -Onone "$1" "$2" "$3" "$KECCAK" "$ART" "$PINS" "$REACH" "$TMP/main.swift" -o "$TMP/run" 2>"$TMP/err" \
        || { head -20 "$TMP/err"; return 2; }
    "$TMP/run"
}
compile_and_run "$PM" "$TX" "$WIRE" || { echo "✗ Move to private's rules fail their own self-test"; exit 1; }
echo "  ok   the ASP's answer, the rows, amounts, viem's bytes and the node routes"

mutate() {
    local name="$1" file="$2" perl_expr="$3"
    cp "$file" "$TMP/mut.swift"
    perl -0pi -e "$perl_expr" "$TMP/mut.swift"
    if cmp -s "$file" "$TMP/mut.swift"; then echo "✗ mutation did not apply: $name"; exit 1; fi
    local pm="$PM" tx="$TX" wire="$WIRE"
    case "$file" in
        "$PM") pm="$TMP/mut.swift" ;;
        "$TX") tx="$TMP/mut.swift" ;;
        "$WIRE") wire="$TMP/mut.swift" ;;
    esac
    local ok
    ok=$(compile_and_run "$pm" "$tx" "$wire" >/dev/null 2>&1 && echo y || echo n)
    [[ "$ok" == n ]] || { echo "✗ SURVIVED  $name"; exit 1; }
    echo "  ok   catches  $name"
}
mutate "unknown no longer waits" "$PM" 's/case "pending", "unknown": return \.waiting/case "pending": return .waiting/'
mutate "the ASP is asked by any label" "$PM" 's/guard labelHash\.range\(of: #"\^\[0-9\]\{1,80\}\$"#/guard labelHash.range(of: #".+"#/'
mutate "a waiting row dates from its newest note" "$PM" 's/min\(had\.since, note\.at\)/max(had.since, note.at)/'
mutate "more places than the token has" "$PM" 's/guard fraction\.count <= decimals else \{ return nil \}\n//'
mutate "the reserve forgets the price can double" "$PM" 's/plain\(gasBudget \* price \* 2\)/plain(gasBudget * price)/'
mutate "any chain gets a transaction" "$TX" 's/guard TestnetTx\.testnets\.contains\(chainId\) else \{ return nil \}\n//'
mutate "the long-length head" "$TX" 's/if length < 56 \{/if length < 256 {/'
mutate "parity 0 is a zero byte" "$TX" 's/\.bytes\(yParity == 0 \? \[\] : \[1\]\)/.bytes([UInt8(yParity)])/'
mutate "r keeps its leading zero" "$TX" 's/\.bytes\(TestnetTx\.stripped\(r\)\)/.bytes(r)/'
mutate "every request goes to the logs node" "$WIRE" 's/rpcMethods\(body\)\.contains\("eth_getLogs"\)/!rpcMethods(body).isEmpty/'
mutate "past the head is an answer" "$WIRE" 's/body\.range\(of: "beyond current head", options: \.caseInsensitive\) != nil/body.isEmpty/'
echo "  ok   11 mutations"
