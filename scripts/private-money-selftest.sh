#!/bin/zsh
# private-money-selftest.sh — Move to private and the private rows (prd §1554).
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
# It also asserts the USE: the act is Move's sentence and Holdings' rows its
# door (no sheet of Holdings' own), the address drawn by its tail; the store asks by `labelHash`, the engine's door
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

# Private is Send's, never a verb (prd §1554): "Your private balance" leads
# Send's recipients, the Private switch stands under Send's sentence (off, and
# never remembered on: its binding reads false), the verbs are Move's five,
# Holdings' header and rows open Send, and Holdings raises no sheet of its own.
SENT="Casberi/Casberi/Screens/MoveSentence.swift"
MSCREEN="Casberi/Casberi/Screens/MoveScreen.swift"
MPRIV="Casberi/Casberi/Screens/MovePrivate.swift"
HOLD="Casberi/Casberi/Screens/FeedScreen+WalletPrivate.swift"
use "$SENT" '}) { verbs }' "the private sentence is no longer drawn under Move's verbs"
use "$SENT" 'listRow(String(localized: "Your private balance"), sub: "Sepolia", symbol: "eye.slash") {' "your private balance is no longer a recipient"
use "$SENT" 'MovePrivateSwitch(isOn: Binding(get: { false }, set: { if $0 { goPrivate(.send) } }))' "the Private switch is not off on arrival under Send"
awk '/MovePrivateSwitch\(isOn: Binding\(get: \{ false \}/{print prev} {prev=$0}' "$SENT" | grep -q 'if verb == .send, receipt == nil, PrivateMove.available {' \
    || { echo "✗ the Private switch stands somewhere other than Send, or where the sender cannot move"; exit 1; }
! grep -qE 'case (swap|send|receive|buy|sweep), private|case private' "$SENT" || { echo "✗ Private became a verb"; exit 1; }
! grep -q 'PrivateMove.available ? \[nil\]' "$SENT" || { echo "✗ Private is in the verbs row"; exit 1; }
use "$MPRIV" 'if move.mode == .send, !isDone {' "the switch shows on a deposit, or is gone from a private send"
use "$MSCREEN" 'privately: chrome.movePrivately)' "Move no longer opens Send privately when asked"
use "$MSCREEN" 'onDismiss: { chrome.movePrivately = nil }' "a closed Move keeps opening privately"
grep -q 'Button { walletOpenPrivate(.deposit) } label:' "$HOLD" && grep -q 'return Button { walletOpenPrivate(.send) } label:' "$HOLD" \
    || { echo "✗ Holdings' header no longer sends to your private balance, or a row no longer sends from it"; exit 1; }
! grep -q 'feedSheet' "$HOLD" || { echo "✗ Holdings raises a private flow of its own"; exit 1; }
[[ ! -e Casberi/Casberi/Screens/MovePrivateSheet.swift ]] || { echo "✗ the standalone Move to private sheet is back"; exit 1; }
use "$MPRIV" 'MoveWord(YourAccount.short(address), ink: DS.pickInk)' "the address to fund is no longer drawn by its tail"
use "$MPRIV" 'MoveWord(YourAccount.short(to), ink: live ? DS.pickInk : DS.textPrimary)' "the recipient is no longer drawn by its tail"
! grep -qE 'prefix\([0-9]+\)' "$MPRIV" || { echo "✗ the sentence draws an address's head"; exit 1; }
use "Casberi/Casberi/Model/PrivateMove.swift" 'let relayed = try await engine.relay(handle: spend.handle)' "a private send no longer goes through the relayer"
use "Casberi/Casberi/Model/PrivateMove.swift" 'let held = PrivateMoneyStore.shared.spendable(chainId: PrivacyNetwork.sepolia.chainId)' "a private send's amounts are not the approved private balance"
use "tools/privacy-pools-engine/src/engine.js" 'const r = await s.relayWithdraw(option);' "the engine no longer relays a withdrawal"
use "Casberi/Casberi/Resources/privacy-engine.js" 'relayWithdraw' "the shipped bundle cannot relay — rebuild with tools/privacy-pools-engine/build.mjs"
use "Casberi/Casberi/Design/BridgeIcon.swift" 'if PrivateMoney.isActivity(thing.sourceRef) { return "eye.slash" }' "a private move's Activity row lost its eye"
use "Casberi/Casberi/Model/WalletIngest.swift" 'venues: cash + privy + privately,' "private money no longer counts in the Wallet's total"
use "Casberi/Casberi/Screens/FeedScreen+WalletPages.swift" '.filter { $0.symbol != PrivateMoney.walletSymbol }' "the Tokens rows count private money twice"
use "Casberi/Casberi/Screens/FeedScreen+Sheets.swift" 'positions: portfolio.positions.filter { $0.symbol != PrivateMoney.walletSymbol }' "the Tokens sheet counts private money twice"
use "Casberi/Casberi/Design/HoldingsTreemap.swift" 'if tile.id == PrivateMoney.walletSymbol {' "the box's Private block lost its eye"
echo "  ok   private is Send's: a recipient and a switch, opened from Holdings, relayed, the address by its tail"
echo "  ok   private money counts once: in the total and the box, never in Tokens"

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
check(rows.map(\.id) == ["0:ETH:11155111", "0:USDC:11155111", "1:ETH:11155111", "2:ETH:11155111"], "private first, then waiting, then refused, A–Z within (\(rows.map(\.id)))")
check(rows.first?.amount == "4000000000000000", "a token's private notes are summed")
check(rows[2].amount == "1500000000000000" && rows[2].since == t0, "a waiting row sums its notes and dates from the oldest")
check(rows[0].since == nil, "a private row has no since")
check(rows[0].title == "ETH, private" && rows[2].title == "ETH, moving in" && rows[3].title == "ETH, not approved", "the rows' names")
check(P.rows([note("z", "0", .approved), note("y", "x", .approved)]).isEmpty, "a zero or unreadable amount draws nothing")
check(P.anyWaiting(notes) && !P.anyWaiting([note("a", "1", .approved)]), "waiting is asked again, approved is not")
check(P.held(notes, symbol: "ETH") == Decimal(string: "4000000000000000"), "held counts approved notes only")

// In the Wallet's number (prd §1554): approved notes on a network with value, once.
func onChain(_ n: P.Note, _ chain: Int) -> P.Note {
    .init(commitment: n.commitment, label: n.label, labelHash: n.labelHash, symbol: n.symbol, amount: n.amount, decimals: n.decimals,
          chainId: chain, tx: n.tx, at: n.at, status: n.status)
}
let mainnet = notes.map { onChain($0, 1) }
let prices = ["eth": 2000.0, "usdc": 1.0]
check(abs(P.worthUSD(mainnet, prices: prices) - 8) < 1e-9, "approved mainnet notes are worth their price (\(P.worthUSD(mainnet, prices: prices)))")
check(P.worthUSD(notes, prices: prices) == 0, "Sepolia's notes count nothing")
check(P.worthUSD([onChain(note("w", "1000000000000000", .waiting), 1)], prices: prices) == 0, "a deposit waiting for approval counts nothing yet")
check(P.worthUSD(mainnet, prices: ["usdc": 1]) < 1e-9, "a token with no price counts nothing")
check(P.rows(mainnet).first.map { P.rowUSD($0, prices: prices) } == 8, "a mainnet row's dollars")
check(rows.first.map { P.rowUSD($0, prices: prices) } == .some(nil), "a Sepolia row states its quantity")
check(P.rows([note("a", "1", .approved), onChain(note("b", "1", .approved), 1)]).count == 2, "one row per network")
check(P.network(11155111) == "Sepolia" && P.network(1) == "Ethereum", "the row's network")

// Sending from it (prd §1554).
let details = #"{"assets":[{"address":"0xEeee","ticker":"ETH","fixedFeeAmount":"21000","feeBPS":"10"},{"ticker":"USDC","fixedFeeAmount":"21000"}]}"#
let terms = P.relayerTerms(Data(details.utf8))
check(terms == P.RelayerTerms(feeBPS: 10, fixed: "21000"), "the relayer's ETH terms (\(String(describing: terms)))")
check(P.relayerTerms(Data("{}".utf8)) == nil && P.relayerTerms(Data("<html>".utf8)) == nil, "no terms, no fee")
check(terms.map { P.relayFee("50000000000000", terms: $0) } == "50000021000", "10 bps of 0.00005 ETH plus the fixed part (the trial's 0.00000005)")
check(terms.map { P.relayFee("1", terms: $0) } == "21001", "a share is rounded up, never to nothing")
check(P.spendable(notes, chainId: 11155111) == "4000000000000000", "only approved notes are spendable")
check(P.spendable(notes, chainId: 1) == "0", "another network's notes are not")
check(P.isAddress("0xEB3e3961008952348445513e418ad6F43C23ca9a") && !P.isAddress("0xEB3e") && !P.isAddress("vitalik.eth"), "an address is 0x and forty hex digits")
check(P.decimal(hex: "0x38d7ea4c68000") == "1000000000000000" && P.decimal(hex: "0x0") == "0" && P.decimal(hex: "12") == "0", "hex to decimal")
check(P.activityTitle(figure: "0.001 ETH", to: nil) == "0.001 ETH to your private balance", "moving in, with no verb")
check(P.activityTitle(figure: "0.001 ETH", to: "...ca9a") == "0.001 ETH to ...ca9a", "a private send, with no verb")
check(P.isActivity("private:0xab") && !P.isActivity("privacypools:dep:1") && !P.isActivity(nil), "an Activity row is its own ref")

// Amounts.
check(P.figure("1000000000000000", decimals: 18, symbol: "ETH") == "0.001 ETH", "0.001 ETH (\(P.figure("1000000000000000", decimals: 18, symbol: "ETH")))")
check(P.baseUnits("0.001", decimals: 18) == "1000000000000000", "0.001 ETH in wei")
check(P.baseUnits("1", decimals: 18) == "1000000000000000000", "1 ETH in wei")
check(P.baseUnits("0.0000000000000000001", decimals: 18) == nil, "more places than the token has is refused")
check(P.baseUnits("0", decimals: 18) == nil && P.baseUnits("abc", decimals: 18) == nil && P.baseUnits("-1", decimals: 18) == nil, "nothing that is not a positive amount")
check(P.hex("1000000000000000") == "0x38d7ea4c68000", "wei to 0x-hex")
check(P.hex("0") == "0x0" && P.hex("255") == "0xff" && P.hex("0x1") == nil, "0, 255 and a non-decimal")
check(P.reserve(gasPrice: "1000") == "4400000000", "the reserve is the budget at twice the price")
check(P.choices(balance: "6000000000000000", reserve: "1000000000000000") == ["0.00001", "0.00005", "0.0001", "0.0005", "0.001", "0.005"], "the ladder the balance allows after the reserve")
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
mutate "a waiting note is spendable" "$PM" 's/notes\.filter \{ \$0\.status == \.approved && \$0\.chainId == chainId/notes.filter { $0.chainId == chainId/'
mutate "the relayer's share rounds down" "$PM" 's/NSDecimalRound\(&up, &share, 0, \.up\)/NSDecimalRound(\&up, \&share, 0, .down)/'
mutate "a waiting deposit counts in the total" "$PM" 's/guard note\.status == \.approved, !testnets/guard !testnets/'
mutate "test money counts in the total" "$PM" 's/guard note\.status == \.approved, !testnets\.contains\(note\.chainId\),/guard note.status == .approved,/'
mutate "two networks share a row" "$PM" 's/let key = "\\\(k\.rawValue\):\\\(note\.symbol\):\\\(note\.chainId\)"/let key = "\\(k.rawValue):\\(note.symbol)"/'
mutate "more places than the token has" "$PM" 's/guard fraction\.count <= decimals else \{ return nil \}\n//'
mutate "the reserve forgets the price can double" "$PM" 's/plain\(gasBudget \* price \* 2\)/plain(gasBudget * price)/'
mutate "any chain gets a transaction" "$TX" 's/guard TestnetTx\.testnets\.contains\(chainId\) else \{ return nil \}\n//'
mutate "the long-length head" "$TX" 's/if length < 56 \{/if length < 256 {/'
mutate "parity 0 is a zero byte" "$TX" 's/\.bytes\(yParity == 0 \? \[\] : \[1\]\)/.bytes([UInt8(yParity)])/'
mutate "r keeps its leading zero" "$TX" 's/\.bytes\(TestnetTx\.stripped\(r\)\)/.bytes(r)/'
mutate "every request goes to the logs node" "$WIRE" 's/rpcMethods\(body\)\.contains\("eth_getLogs"\)/!rpcMethods(body).isEmpty/'
mutate "past the head is an answer" "$WIRE" 's/body\.range\(of: "beyond current head", options: \.caseInsensitive\) != nil/body.isEmpty/'
echo "  ok   16 mutations"
