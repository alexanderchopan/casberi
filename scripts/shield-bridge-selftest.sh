#!/bin/zsh
# Shield bridge self-test (prd §1700b, §1700d, §1700e) — the words Casberi
# writes to Shield's contracts and the guards around them:
#
#   Casberi/Casberi/Model/Aztec/ShieldWire.swift
#     — depositCalldata   (the portal's depositToAztecPrivate, cleanHands blank)
#     — withdrawCalldata  (the portal's withdraw, finishing an exit on Ethereum)
#     — leafID            (the outbox's key for "already withdrawn")
#     — message(in:)      (the deposit's event: what Aztec will carry)
#
# Expected bytes were encoded by viem (tools/aztec-account) on 2026-11-04;
# Shield's portal is unverified on Etherscan, so its ABI is Shield's own web
# app's. Every failure below moves real money wrong:
#
#   • the two signature tuples swapped — the deposit reverts, or worse, a
#     Clean Hands (government ID) slot filled by the Passport limit;
#   • a withdraw whose path offset is off — the portal reverts, and the money
#     waits on Ethereum while the app says it can be finished;
#   • a leaf id off by the tree's depth — a finished exit offered again forever;
#   • an exit that pays another address than its sentence names, one the
#     co-signer never approved, an authwit for the
#     bridge instead of its minter proxy (the burn reverts after proving), or a
#     content hash under another selector (the exit can never be finished);
#   • any request to Proof of Clean Hands (ID) — Passport only, §1700e item 1.
#
#   Casberi/Casberi/Model/Aztec/BrowserEthereum.swift — your account as an
#   Ethereum provider on Human Passport's page: a page that could send, sign
#   for another chain or account, read accounts before connecting, or get a
#   hash signed dressed as a message. In Apps on Aztec's browser it sends
#   (prd §1700k): only there, only connected, only from your account on
#   Ethereum to a named address, the value read exactly, an approval read
#   with its limit, and never a raw transaction or a batch. That browser says
#   it is a Mac (prd §1700n), so RainbowKit's phone picker does not drop Casberi.
#   A sign-in (EIP-4361) is read into words only for the page's own site
#   (prd §1700o).
set -euo pipefail
cd "$(dirname "$0")/.."

WIRE="Casberi/Casberi/Model/Aztec/ShieldWire.swift"
PROVIDER="Casberi/Casberi/Model/Aztec/BrowserEthereum.swift"
APP="Casberi/Casberi/Model/Aztec/ShieldBridge.swift"
ENGINE="tools/aztec-engine/src/main.js"
for f in "$WIRE" "$PROVIDER" "$APP" "$ENGINE"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done

# ── The app half, read ──────────────────────────────────────────────────
grep -q 'shield.human.tech' Casberi/Casberi/Model/NetworkReach.swift \
  || { echo "✗ Shield's host is not declared in NetworkReach"; exit 1; }
if grep -n 'attestation/poch\|cleanHands"\]\s*=' "$APP" "$WIRE" | grep -v '^\s*[0-9]*:\s*///' | grep -q .; then
  echo "✗ Shield's Proof of Clean Hands (government ID) is asked for: Passport only (prd §1700e)"; exit 1
fi
grep -q '"shieldExit", \[asset.symbol, units, recipient, text\]' "$APP" \
  && grep -q 'recipient: recipient, transaction: transaction' "$APP" \
  || { echo "✗ an exit no longer pays exactly the address in its sentence, or keeps another"; exit 1; }
grep -q 'try await AztecCoSign.approve(' "$APP" \
  || { echo "✗ an exit no longer asks the co-signer first (prd §1700f item 4)"; exit 1; }
grep -q "caller: AztecAddress.fromStringUnsafe(asset.proxy), call: burn" "$ENGINE" \
  || { echo "✗ the exit's authwit no longer names the bridge's minter proxy: the burn reverts after proving"; exit 1; }
grep -q "Buffer.from('69328dec', 'hex')" "$ENGINE" \
  || { echo "✗ the exit's content is no longer withdraw(address,uint256,address)'s: it could never be finished"; exit 1; }
grep -q "proxyClass: '0x18fa95a66c31125278bf4d07166e30fff3ad7e12b232710bf7e376f36f2d4b8a'" "$ENGINE" \
  || { echo "✗ the minter proxy's class is no longer pinned"; exit 1; }

# ── The wire, run ──────────────────────────────────────────────────────
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'EOF'
import Foundation
var failed = 0
func check(_ ok: Bool, _ what: String) { if !ok { failed += 1; print("✗ \(what)") } }

let sig = "0x" + String(repeating: "11", count: 32) + String(repeating: "22", count: 32) + "1b"
let limit = ShieldBridge.Limit(maxAmount: "1000000000", nonce: "7", deadline: "1767225600", signature: sig)
let deposit = ShieldBridge.depositCalldata(units: "25000000",
    secretHash: "0x0abc000000000000000000000000000000000000000000000000000000000def", limit: limit)
check(deposit == "0x62470a1000000000000000000000000000000000000000000000000000000000017d78400abc000000000000000000000000000000000000000000000000000000000def0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b9aca000000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000006955b90000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000041111111111111111111111111111111111111111111111111111111111111111122222222222222222222222222222222222222222222222222222222222222221b00000000000000000000000000000000000000000000000000000000000000",
      "depositToAztecPrivate is not viem's bytes")

let withdraw = ShieldBridge.withdrawCalldata(recipient: "0xef4d9e1f4e9e2dd9e747b53f4be3d04bfa935f2d", units: "5000000",
    epoch: "812", checkpoints: "3", leaf: "5",
    path: ["0x" + String(repeating: "aa", count: 32), "0x" + String(repeating: "bb", count: 32), "0x00" + String(repeating: "cc", count: 31)])
check(withdraw == "0xaab5a3f1000000000000000000000000ef4d9e1f4e9e2dd9e747b53f4be3d04bfa935f2d00000000000000000000000000000000000000000000000000000000004c4b400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000032c0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000003aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb00cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      "the portal's withdraw is not viem's bytes")
check(ShieldBridge.withdrawCalldata(recipient: "0xef4d", units: "1", epoch: "1", checkpoints: "1", leaf: "0", path: ["0xzz"]) == nil,
      "a sibling that is not hex was written anyway")

check(ShieldBridge.leafID(leaf: "5", depth: 3) == "13", "leaf id is not 2^depth + leaf")
check(ShieldBridge.leafID(leaf: "0", depth: 0) == "1", "leaf id of a one-message epoch")
check(ShieldBridge.word(decimal: "115792089237316195423570985008687907853269984665640564039457584007913129639935") == String(repeating: "f", count: 64),
      "2^256 - 1 is not one full word")
check(ShieldBridge.word(decimal: "115792089237316195423570985008687907853269984665640564039457584007913129639936") == nil,
      "2^256 overflowed into a word")

// The deposit's event, as a receipt carries it (amount after fee 24,875,000; leaf 702).
let words = ["00000000000000000000000000000000000000000000000000000000017b8ff8",
             "000000000000000000000000000000000000000000000000000000000001e848",
             "0abc000000000000000000000000000000000000000000000000000000000def",
             "00967aa4307fc16f08f3dc9a0b2974ebe4ce4905d7b4dc7fff3a97283e89719a",
             "00000000000000000000000000000000000000000000000000000000000002be"]
let portal = ShieldBridge.assets[0].portal
let receipt: [String: Any] = ["logs": [
    ["address": "0x0000000000000000000000000000000000000001", "topics": [ShieldBridge.depositTopic], "data": "0x" + words.joined()],
    ["address": portal.uppercased().replacingOccurrences(of: "0X", with: "0x"), "topics": [ShieldBridge.depositTopic], "data": "0x" + words.joined()],
]]
let m = ShieldBridge.message(in: receipt, portal: portal)
check(m?.amount == "24875000", "the deposit's amount after fee")
check(m?.key == "0x00967aa4307fc16f08f3dc9a0b2974ebe4ce4905d7b4dc7fff3a97283e89719a", "the deposit's message key")
check(m?.index == "702", "the deposit's leaf index")
check(ShieldBridge.message(in: ["logs": [receipt["logs"].map { ($0 as! [[String: Any]])[0] }!]], portal: portal) == nil,
      "another contract's event was read as Shield's portal")

exit(failed == 0 ? 0 : 1)
EOF
xcrun swiftc -Onone -o "$TMP/run" "$WIRE" "$TMP/main.swift" 2>"$TMP/err" || { cat "$TMP/err"; echo "✗ the wire did not compile"; exit 1; }
"$TMP/run" || exit 1

# ── The provider, run ──────────────────────────────────────────────────
mkdir -p "$TMP/prov.d"; cat > "$TMP/prov.d/main.swift" <<'EOF'
import Foundation
var failed = 0
func check(_ ok: Bool, _ what: String) { if !ok { failed += 1; print("✗ provider: \(what)") } }
let me = "0x1111111111111111111111111111111111111111"
let other = "0x2222222222222222222222222222222222222222"
func need(_ m: String, _ p: [Any], _ c: Bool = true, sends: Bool = false) -> BrowserEthereum.Need {
    let json = String(data: try! JSONSerialization.data(withJSONObject: p), encoding: .utf8)!
    return BrowserEthereum.need(method: m, paramsJSON: json, account: me, connected: c, sends: sends)
}
func signs(_ n: BrowserEthereum.Need) -> Bool {
    switch n { case .signText, .signTyped: true; default: false }
}
check(need("eth_accounts", [], false) == .answer(.result("[]")), "accounts read before connecting")
check(need("eth_requestAccounts", [], false) == .connect, "a connect not asked")
check(need("eth_sendTransaction", [[:]]) == .answer(.unsupported), "a page can send")
check(need("eth_sign", [me, "0x" + String(repeating: "ab", count: 32)]) == .answer(.unsupported), "raw eth_sign answered")
check(need("wallet_switchEthereumChain", [["chainId": "0x2105"]]) != .answer(.result(nil)), "another chain accepted")
check(need("personal_sign", ["0x68656c6c6f", me]) == .signText("hello"), "a hex message not read as its text")
check(need("personal_sign", [me, "0x68656c6c6f"]) == .signText("hello"), "params the other way round")
check(need("personal_sign", ["0x68656c6c6f", other]) == .answer(.wrongAccount), "signed for another account")
check(!signs(need("personal_sign", ["0x00ff10aa", me])), "bytes that are not text signed")
check(!signs(need("personal_sign", ["0x68656c6c6f", me], false)), "signed before connecting")
check(!signs(need("eth_signTypedData_v4", [me, "{\"domain\":{\"chainId\":8453},\"primaryType\":\"X\"}"])), "typed data for Base signed")
check(signs(need("eth_signTypedData_v4", [me, "{\"domain\":{\"chainId\":1,\"name\":\"P\"},\"primaryType\":\"X\"}"])), "typed data for Ethereum refused")
check(!signs(need("eth_signTypedData_v4", [other, "{\"domain\":{\"chainId\":1},\"primaryType\":\"X\"}"])), "typed data for another account")
check(need("eth_call", [[:], "latest"]) == .read(method: "eth_call", params: []), "a read not passed through")
check(need("eth_chainId", []) == .answer(.result("\"0x1\"")), "chain is not Ethereum")

// Sending (prd §1700k): Apps on Aztec's browser only.
let olla = "0x3333333333333333333333333333333333333333"
func sends(_ tx: [String: Any], _ c: Bool = true) -> BrowserEthereum.Need { need("eth_sendTransaction", [tx], c, sends: true) }
func isSend(_ n: BrowserEthereum.Need) -> Bool { if case .send = n { true } else { false } }
check(!isSend(need("eth_sendTransaction", [["to": olla, "data": "0x"]])), "a page that may not send sends")
check(!isSend(sends(["to": olla, "data": "0x"], false)), "a send before connecting")
check(!isSend(sends(["from": other, "to": olla, "data": "0x"])), "a send from another account")
check(!isSend(sends(["data": "0x6080"])), "a contract made from a page")
check(!isSend(sends(["to": olla, "data": "0x", "chainId": "0x2105"])), "a send on Base")
check(!isSend(sends(["to": olla, "data": "0xzz"])), "data that is not hex sent")
check(!isSend(sends(["to": "0x12", "data": "0x"])), "a send to something that is not an address")
check(sends(["from": me.uppercased().replacingOccurrences(of: "0X", with: "0x"), "to": olla, "data": "0xABCD", "value": "0xde0b6b3a7640000"])
      == .send(to: olla, data: "0xabcd", value: "1000000000000000000"), "one ETH not read as 10^18 wei")
check(sends(["to": olla, "input": "0x01"]) == .send(to: olla, data: "0x01", value: "0"), "`input` not read as the data")
check(!isSend(need("eth_sendRawTransaction", ["0x02"], sends: true)), "a raw transaction sent")
check(!isSend(need("wallet_sendCalls", [[:]], sends: true)), "a batch sent")
check(BrowserEthereum.decimal(hexQuantity: "0x" + String(repeating: "f", count: 64))
      == "115792089237316195423570985008687907853269984665640564039457584007913129639935", "uint256 max not exact")
check(BrowserEthereum.decimal(hexQuantity: "0x0") == "0", "zero")
let spender = "4444444444444444444444444444444444444444"
let capped = BrowserEthereum.approval("0x095ea7b3" + String(repeating: "0", count: 24) + spender
                                      + String(repeating: "0", count: 56) + "05f5e100")
check(capped == BrowserEthereum.Approval(spender: "0x" + spender, amount: "100000000", unlimited: false), "a 100 USDC approval misread")
let noLimit = BrowserEthereum.approval("0x095ea7b3" + String(repeating: "0", count: 24) + spender + String(repeating: "f", count: 64))
check(noLimit?.unlimited == true, "an approval with no limit read as limited")
check(BrowserEthereum.approval("0xa9059cbb" + String(repeating: "0", count: 128)) == nil, "a transfer read as an approval")

// Connected as your co-signer (prd §1700l): it never sends, a page that
// connects again is asked again, and anything else keeps the connection.
check(BrowserEthereum.asCoSigner(method: "eth_sendTransaction", connected: true, sends: false).sends == false, "the co-signer sends where the page may not")
check(BrowserEthereum.asCoSigner(method: "eth_sendTransaction", connected: true, sends: true).sends == true, "the co-signer cannot pay where the page may send")
check(BrowserEthereum.hexQuantity(decimal: "1000000000000000000") == "0xde0b6b3a7640000", "one ETH not 0xde0b6b3a7640000")
check(BrowserEthereum.hexQuantity(decimal: "0") == "0x0", "zero not 0x0")
let maxWei = "115792089237316195423570985008687907853269984665640564039457584007913129639935"
check(BrowserEthereum.hexQuantity(decimal: maxWei).flatMap { BrowserEthereum.decimal(hexQuantity: $0) } == maxWei, "uint256 max does not survive decimal to hex and back")
check(BrowserEthereum.hexQuantity(decimal: "12a") == nil && BrowserEthereum.hexQuantity(decimal: "") == nil, "a value that is not digits sent")
// The co-signer's shortfall (prd §1700l item 10): 0.01 ETH at 1 gwei from
// nothing needs 0.01 + 0.0006 (300,000 gas, twice the price); enough needs none.
check(BrowserEthereum.topUp(balanceHex: "0x0", valueWei: "10000000000000000", gasPriceHex: "0x3b9aca00") == "10600000000000000", "an empty co-signer's top-up misread")
check(BrowserEthereum.topUp(balanceHex: "0x2386f26fc10000", valueWei: "10000000000000000", gasPriceHex: "0x3b9aca00") == "600000000000000", "a top-up not just the difference")
check(BrowserEthereum.topUp(balanceHex: "0xde0b6b3a7640000", valueWei: "10000000000000000", gasPriceHex: "0x3b9aca00") == nil, "a funded co-signer asked to be topped up")
check(BrowserEthereum.topUp(balanceHex: "0x0", valueWei: "1", gasPriceHex: "0x0") == "100000000000000", "a top-up not rounded up to 0.0001 ETH")
check(BrowserEthereum.isTransactionHash("0x" + String(repeating: "ab", count: 32)) && !BrowserEthereum.isTransactionHash("0x1234"), "a transaction hash misread")
check(BrowserEthereum.asCoSigner(method: "eth_requestAccounts", connected: true, sends: true).connected == false, "connecting again is not asked again")
check(BrowserEthereum.asCoSigner(method: "wallet_requestPermissions", connected: true, sends: true).connected == false, "permissions again are not asked again")
check(BrowserEthereum.asCoSigner(method: "personal_sign", connected: true, sends: true).connected == true, "the co-signer's sign-in loses its connection")
check(BrowserEthereum.asCoSigner(method: "eth_accounts", connected: false, sends: true).connected == false, "connected without connecting")
// A sign-in your account gave, then a connect within five minutes: the app
// turned it down, so Connect is asked again, co-signer first.
let signed = Date(timeIntervalSince1970: 1_000_000)
check(BrowserEthereum.asksAgainAfterSign(method: "eth_requestAccounts", signedAt: signed, now: signed.addingTimeInterval(20), hasCoSigner: true), "a retry after a sign-in not asked again")
check(!BrowserEthereum.asksAgainAfterSign(method: "eth_requestAccounts", signedAt: signed, now: signed.addingTimeInterval(20), hasCoSigner: false), "asked again with no co-signer to offer")
check(!BrowserEthereum.asksAgainAfterSign(method: "eth_requestAccounts", signedAt: signed, now: signed.addingTimeInterval(400), hasCoSigner: true), "asked again long after the sign-in")
check(!BrowserEthereum.asksAgainAfterSign(method: "eth_requestAccounts", signedAt: nil, now: signed, hasCoSigner: true), "asked again with no sign-in")
check(!BrowserEthereum.asksAgainAfterSign(method: "eth_accounts", signedAt: signed, now: signed.addingTimeInterval(20), hasCoSigner: true), "a read of accounts asked again")
// A sign-in, read (prd §1700o): Private Inference's own message, 2026-11-07.
let siwe = """
privateinference.gg wants you to sign in with your Ethereum account:
0x1111111111111111111111111111111111111111

By signing, you are proving you own this wallet and logging in. This does not initiate a transaction or cost any fees.

URI: https://privateinference.gg
Version: 1
Chain ID: 1
Nonce: f81269978ee92638ef58cd06eb50a0662ab6d40c314b37a6e7dd8d78036ba01f
Issued At: 2026-11-07T19:04:37.804Z
Resources:
- https://privy.io
"""
let si = BrowserEthereum.signIn(siwe)
check(si?.site == "privateinference.gg" && si?.address == me, "a sign-in's site or account misread")
check(si?.statement == "By signing, you are proving you own this wallet and logging in. This does not initiate a transaction or cost any fees.", "a sign-in's sentence misread")
check(si?.chainId == "1" && si?.expires == nil && si?.resourceHosts == ["privy.io"], "a sign-in's chain, expiry or resources misread")
check(si?.isFor(host: "privateinference.gg") == true, "a sign-in for its own page read as another site's")
check(si?.isFor(host: "privateinference.gg.evil.xyz") == false, "a sign-in for another site read as this page's")
let otherURI = siwe.replacingOccurrences(of: "URI: https://privateinference.gg", with: "URI: https://evil.xyz/login")
check(BrowserEthereum.signIn(otherURI)?.isFor(host: "privateinference.gg") == false, "a sign-in whose URI is another site's read as this page's")
let otherDomain = siwe.replacingOccurrences(of: "privateinference.gg wants", with: "evil.xyz wants")
check(BrowserEthereum.signIn(otherDomain)?.isFor(host: "privateinference.gg") == false, "a sign-in naming another site read as this page's")
let schemed = siwe.replacingOccurrences(of: "privateinference.gg wants", with: "https://privateinference.gg:443 wants")
check(BrowserEthereum.signIn(schemed)?.isFor(host: "privateinference.gg") == true, "a sign-in naming its scheme and port misread")
let noStatement = siwe.replacingOccurrences(of: "By signing, you are proving you own this wallet and logging in. This does not initiate a transaction or cost any fees.\n\n", with: "")
check(BrowserEthereum.signIn(noStatement) != nil && BrowserEthereum.signIn(noStatement)?.statement == nil, "a sign-in with no sentence misread")
check(BrowserEthereum.signIn("Hello from privateinference.gg") == nil, "a plain message read as a sign-in")
check(BrowserEthereum.signIn(siwe.replacingOccurrences(of: "Nonce: ", with: "Nonc: ")) == nil, "a sign-in with no nonce read as one")
// Apps on Aztec's browser says it is a Mac (prd §1700n): RainbowKit's
// isMobile() and its isSafari() read the agent alone.
let agent = BrowserEthereum.desktopAgent(majorVersion: 26)
check(agent.range(of: "iPhone|iPod|iPad|android", options: [.regularExpression, .caseInsensitive]) == nil, "the agent reads as a phone to RainbowKit")
check(agent.range(of: #"Version/([0-9._]+).*Safari"#, options: .regularExpression) != nil, "the agent is not Safari's")
check(agent.contains("Macintosh") && agent.contains("Version/26.0 "), "the agent is not this phone's Safari on a Mac")
exit(failed == 0 ? 0 : 1)
EOF
xcrun swiftc -Onone -o "$TMP/prov" "$PROVIDER" "$TMP/prov.d/main.swift" 2>"$TMP/perr" || { cat "$TMP/perr"; echo "✗ the provider did not compile"; exit 1; }
"$TMP/prov" || exit 1
if grep -n "eth_sendRawTransaction\|wallet_sendCalls" "$PROVIDER" | grep -v '^\s*[0-9]*:\s*///' | grep -q .; then
  echo "✗ the provider names a raw or batch send: one call per eth_sendTransaction only (prd §1700k)"; exit 1
fi
# Sending is on where Aztec's directory opens a page, and nowhere else (prd §1700k, §1700p).
DOORS=$(grep -rln "sends: true" Casberi/Casberi '--include=*.swift' | sort | tr '\n' ' ')
# ProbeHooks is DEBUG's door (`-aztecAppEthereum`, prd §1700l), compiled out of every shipped build.
# SettingsHome is Library's Wallet folder, Aztec's directory (prd §1700m).
[[ "$DOORS" == "Casberi/Casberi/Screens/SettingsHome.swift Casberi/Casberi/Screens/ThingSheetView.swift Casberi/Casberi/Shell/ProbeHooks.swift " ]] \
  || { echo "✗ sending is on beyond Apps on Aztec's doors: $DOORS"; exit 1; }
grep -q "AztecBrowserView(url: AztecApps.directory, ethereum: true, sends: true)" Casberi/Casberi/Screens/SettingsHome.swift \
  || { echo "✗ Library's Aztec directory no longer offers your account to an Ethereum app"; exit 1; }
# The directory is how the Aztec account first gets used, so its tile may not
# wait for that use (prd §1700s).
grep -q 'YourAccountKey.address != nil && AztecProver.isAvailable && !DemoMode.isActive' Casberi/Casberi/Model/Aztec/AztecApps.swift \
  && ! awk '/static var doorShown/,/^    }/' Casberi/Casberi/Model/Aztec/AztecApps.swift | grep -q 'isShown' \
  || { echo "✗ Aztec's directory tile waits for an Aztec account already used, so nobody new reaches it"; exit 1; }
grep -q 'if case .notChecked = simulated.checked' "Casberi/Casberi/Model/YourAccountChain.swift" \
  || { echo "✗ an app's call may be signed without being run on Ethereum first"; exit 1; }
# Only the browser that may send says it is a Mac (prd §1700n).
grep -q 'if ethereum && sends {' Casberi/Casberi/Screens/AztecBrowser.swift \
  && grep -q 'page.customUserAgent = BrowserEthereum.desktopAgent(' Casberi/Casberi/Screens/AztecBrowser.swift \
  || { echo "✗ Apps on Aztec's browser sends the phone's agent: RainbowKit's phone picker drops Casberi (prd §1700n)"; exit 1; }
[[ $(grep -c 'customUserAgent' Casberi/Casberi/Screens/AztecBrowser.swift) -eq 1 ]] \
  || { echo "✗ the browser's agent is set more than once (prd §1700n)"; exit 1; }
# The co-signer's sign-in has its own one-method pairing, never the kept
# Signer session (Safe approvals only), and is checked against the key.
grep -q 'connect(signer: signer, chainIds: \[chainId\], method: appMethod' Casberi/Casberi/Model/YourAccountSignerLink.swift \
  || { echo "✗ an app's sign-in rides the Signer's kept session (prd §1700l)"; exit 1; }
grep -q 'EcRecover.address(digest: digest, signature: signature)?.caseInsensitiveCompare(signer)' Casberi/Casberi/Model/YourAccountSignerLink.swift \
  || { echo "✗ an app's sign-in is passed on without recovering to the co-signer (prd §1700l)"; exit 1; }
# An app's send by the co-signer runs on Ethereum from the co-signer first,
# goes to its wallet from its own address only (prd §1700l item 9).
grep -q '"eth_estimateGas", \[tx\]' Casberi/Casberi/Screens/AztecBrowser.swift \
  || { echo "✗ the co-signer's send asks its wallet without running first (prd §1700l item 9)"; exit 1; }
grep -q 'guard tx\["from"\]?.caseInsensitiveCompare(signer) == .orderedSame' Casberi/Casberi/Model/YourAccountSignerLink.swift \
  || { echo "✗ the co-signer's wallet is asked to send from another address (prd §1700l item 9)"; exit 1; }
# A co-signer that cannot pay is offered a top-up from your account, and the
# send runs again before its wallet is asked (prd §1700l item 10).
grep -q 'if let toppedUp = await topUp(signer: signer, value: value, host: host)' Casberi/Casberi/Screens/AztecBrowser.swift \
  && grep -q 'guard await runsFrom(tx) else' Casberi/Casberi/Screens/AztecBrowser.swift \
  || { echo "✗ the co-signer's top-up is skipped, or its send is not run again (prd §1700l item 10)"; exit 1; }
# Connected, the request goes and the wallet is opened onto it, with Ask
# again: a wallet left in the background misses it (prd §1700l item 6).
grep -q 'await sent(door(of: pairing.topic))' Casberi/Casberi/Model/YourAccountSignerLink.swift \
  || { echo "✗ an app's sign-in never opens the wallet onto its request (prd §1700l item 6)"; exit 1; }
grep -q 'resend: ask.resends,' Casberi/Casberi/Screens/AztecBrowser.swift && grep -q 'sent: { ask.ask(kept: \$0) }' Casberi/Casberi/Screens/AztecBrowser.swift \
  || { echo "✗ the browser's co-signer sign-in has no Ask again or wallet door (prd §1700l item 6)"; exit 1; }
# The Signer sheet waits for the ask sheet to leave: raised while it slid
# away, it went with it and nothing showed (build 951, prd §1700l item 7).
[[ $(grep -c 'await untilAskSheetGone()' Casberi/Casberi/Screens/AztecBrowser.swift) -ge 2 ]] \
  || { echo "✗ the Signer sheet is raised over a leaving ask sheet (prd §1700l item 7)"; exit 1; }
# The provider's own mutations: each must fail the run.
pmutate() { # label, perl expression
  sed -e '' "$PROVIDER" > "$TMP/prov.swift"
  perl -0pi -e "$2" "$TMP/prov.swift"
  cmp -s "$PROVIDER" "$TMP/prov.swift" && { echo "✗ mutation '$1' changed nothing (its anchor drifted)"; exit 1; }
  if xcrun swiftc -Onone -o "$TMP/pmut" "$TMP/prov.swift" "$TMP/prov.d/main.swift" 2>/dev/null && "$TMP/pmut" >/dev/null; then
    echo "✗ mutation survived: $1"; exit 1
  fi
}
pmutate "any page sends" 's/guard sends else \{ return \.answer\(\.unsupported\) \}//'
pmutate "send from any account" 's/from\.lowercased\(\) != account\.lowercased\(\)/false/'
pmutate "value divided wrong" 's/let q = n \/ 10/let q = n \/ 16/'
pmutate "every approval unlimited" 's/unlimited: amountWord\.prefix\(2\) == "ff"/unlimited: true/'
pmutate "the co-signer sends anywhere" 's/\["eth_requestAccounts", "wallet_requestPermissions"\]\.contains\(method\), sends\)/["eth_requestAccounts", "wallet_requestPermissions"].contains(method), true)/'
pmutate "a top-up without the fee" 's/let need = v \+ p \* topUpGas \* 2/let need = v/'
pmutate "a wei value read as hex wrong" 's/let q = cur \/ 16/let q = cur \/ 10/'
pmutate "a retry never asked again" 's/return since >= 0 && since < retryWindow/return false/'
pmutate "a sign-in for any site" 's/guard site == h else \{ return false \}//'
pmutate "the agent says iPhone" 's/Macintosh; Intel Mac OS X 10_15_7/iPhone; CPU iPhone OS 18_0 like Mac OS X/'
pmutate "the co-signer is not asked again" 's/\(connected && !\["eth_requestAccounts", "wallet_requestPermissions"\]\.contains\(method\),/(connected,/'

# ── Mutations: the checks above catch what they claim ───────────────────
# **Into Aztec from your co-signer (prd §1720).** Shield's portal takes a
# deposit only from the wallet whose score it signed (its "For" variant is
# Shield's router's alone), so a co-signer deposit is the co-signer's own
# send of the plain deposit, signed in by the co-signer, and Move reaches it
# only when your account is not eligible and your co-signer is.
grep -q 'let limit = try await limit(.intoAztec, asset: asset, units: units, account: coSigner, aztec: aztec, coSigner: true)' "$APP" \
  || { echo "✗ the co-signer's deposit is not signed in by the co-signer (prd §1720)"; exit 1; }
grep -q 'try await coSend(\["from": coSigner, "to": asset.portal, "data": deposit, "value": "0x0"\]' "$APP" \
  || { echo "✗ the co-signer's deposit is not the co-signer's own send of the plain deposit (prd §1720)"; exit 1; }
! grep -q '6641be24\|depositToAztecPrivateFor(' "$APP" "$WIRE" \
  || { echo "✗ a deposit-for call is written: only Shield's router may make one (NotTrustedForwarder, prd §1720)"; exit 1; }
grep -q 'personalSignDigest(message), signer: account' "$APP" \
  || { echo "✗ the co-signer's sign-in is not checked against the message Casberi wrote (prd §1720)"; exit 1; }
MOVEAZ="Casberi/Casberi/Screens/MoveAztecPrivate.swift"
awk '/if !standing.eligible, !standing.sanctioned,/{a=NR} /theirs.eligible \{/{b=NR} /viaCoSigner = coSigner/{c=NR} END{exit !(a && b && c && a<b && b<c)}' "$MOVEAZ" \
  || { echo "✗ Move deposits from your co-signer other than when your account is not eligible and it is (prd §1720)"; exit 1; }
# Any amount (prd §1700q): typed, never a list; Send and run() both wait on a clear amount.
! grep -q 'usdcSteps\|wethSteps' "$MOVEAZ" \
  || { echo "✗ Move's Aztec amount is a fixed list again (prd §1700q)"; exit 1; }
grep -q 'guard stage == .ready, amountOK, let units' "$MOVEAZ" \
  || { echo "✗ an Aztec move runs without a clear amount (prd §1700q)"; exit 1; }
grep -q 'move.stage == .ready && move.amountOK &&' "$MOVEAZ" \
  || { echo "✗ Send stands lit over an unclear amount (prd §1700q)"; exit 1; }
awk '/static func exit\(/{e=1} e&&/let theirs = await eligibility\(coSigner\), theirs.eligible/{t=NR} e&&/limit\(.outOfAztec, asset: asset, units: units, account: signer, aztec: aztec, coSigner: byCoSigner\)/{l=NR} END{exit !(t && l && t<l)}' "$APP" \
  || { echo "✗ an exit asks Shield only for your account, never your co-signer (prd §1700r)"; exit 1; }
grep -q 'guard stage == .reading || stage == .ready else { return }' "$MOVEAZ" \
  || { echo "✗ a refresh behind the stored balance can undo a move under way (prd §1700r)"; exit 1; }
grep -q 'if typed.hasPrefix(".") { typed = "0" + typed }' "$MOVEAZ" \
  || { echo "✗ \".5\" no longer reads as half: Send stays off (prd §1700r)"; exit 1; }
grep -q 'case moreThanHeld' "$MOVEAZ" && grep -q 'want > have' "$MOVEAZ" \
  || { echo "✗ an amount over what you hold is not said (prd §1700q)"; exit 1; }

mutate() { # label, perl expression
  sed -e '' "$WIRE" > "$TMP/wire.swift"
  perl -0pi -e "$2" "$TMP/wire.swift"
  cmp -s "$WIRE" "$TMP/wire.swift" && { echo "✗ mutation '$1' changed nothing (its anchor drifted)"; exit 1; }
  if xcrun swiftc -Onone -o "$TMP/mut" "$TMP/wire.swift" "$TMP/main.swift" 2>/dev/null && "$TMP/mut" >/dev/null; then
    echo "✗ mutation survived: $1"; exit 1
  fi
}
mutate "tuples swapped" 's/cleanHands \+ passport/passport + cleanHands/'
mutate "path offset off" 's/word\(int: 7 \* 32\)/word(int: 6 * 32)/'
mutate "leaf id without depth" 's/pow\(Decimal\(2\), depth\) \+ l/l/'
mutate "decimal carry dropped" 's/guard carry == 0 else \{ return nil \}/_ = carry/'
mutate "any contract's event" 's/\(log\["address"\] as\? String\)\?\.lowercased\(\) == portal\.lowercased\(\),/true,/'

echo "✓ Shield bridge self-test (deposit + withdraw bytes match viem, leaf ids, the deposit event, Passport only, the provider's rules, the browser's Mac agent, a sign-in read, the co-signer's deposit, any amount, 5 + 11 mutations caught)"
