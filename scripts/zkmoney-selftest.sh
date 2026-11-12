#!/bin/zsh
# Casberi zk.money self-test — the SHIPPED wire behind zk.money's public
# edges (2026-10-11):
#
#   Casberi/Casberi/Model/ZkMoneyWire.swift (+ Keccak256.swift, pure)
#   Casberi/Shared/ZkMoneyLink.swift (the link reader, app and share extension)
#     — tag / nameHash / account / record   (the NameRegistry and its metadata)
#     — isDepositAddress / isPortal / move  (what a watched wallet's transfer is)
#     — link / requestPacket / CBOR / title (a shared link, read without fetching)
#     — dai                                  (the portal's DAI)
#
# Pure, local, deterministic, against replies saved off Ethereum mainnet
# (scripts/fixtures/zkmoney/) and a request link encoded with cbor-x, the
# reference encoder. Every failure below renders as a good-looking row:
#
#   • a namehash built without the `.zk.money` labels — every tag "unclaimed";
#   • any minimal proxy read as a deposit address — a send to ANY clone
#     contract titled "Deposited to zk.money";
#   • a DAI transfer FROM any address read as a withdrawal;
#   • a payment link kept WITH its fragment — the claim secret, a bearer
#     credential, synced to iCloud in a library row;
#   • the request amount read little-endian — "20.5 DAI" becomes nonsense.
set -euo pipefail
cd "$(dirname "$0")/.."

WIRE="Casberi/Casberi/Model/ZkMoneyWire.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
LINK="Casberi/Shared/ZkMoneyLink.swift"
FIX="scripts/fixtures/zkmoney"
for f in "$WIRE" "$KECCAK" "$LINK" "$FIX/ownerof-zac.json" "$FIX/userrecord-zac.json" "$FIX/code-deposit.json" \
         "$FIX/code-portal-head.json" "$FIX/portal-dai.json" "$FIX/request-link.txt" "$FIX/request-link-v3.txt" "$FIX/request-link-v4.txt" "$FIX/short-link-record.json" \
         "$FIX/code-swap-escrow.json" "$FIX/code-swap-escrow-v2.json" "$FIX/code-savings-escrow.json" \
         "$FIX/code-deposit-aztec-v6.json" "$FIX/code-registration-aztec-v6.json" "$FIX/resolve-call-zac.txt" \
         "$FIX/lookup-zac.txt" "$FIX/lookup-charlie.txt" "$FIX/lookup-unclaimed.txt" "$FIX/gateway-zac.json" \
         "$FIX/callback-call-zac.txt" "$FIX/callback-zac.txt"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# The capture path (app half, not compiled here): a scheme-less payment link
# is no URL to the detector, so the scrubbed secret must name the link, and
# the branch must read the ORIGINAL text (seen on a simulator, 2026-10-17:
# both slips saved a payment link as a note with no Claim).
grep -q 'scrubbed.secrets.first.flatMap(URL.init(string:))' Casberi/Shared/Capture.swift \
  || { echo "✗ a scheme-less payment link no longer names its row (it saves as a note)"; exit 1; }
grep -q 'ZkMoneyLink.capture(url: url, text: original)' Casberi/Shared/Capture.swift \
  || { echo "✗ the zk.money branch reads the scrubbed text and misses every payment link"; exit 1; }

TMP="$(mktemp -d)"
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what) (line \(line))"); failures += 1 }
}
let fix = ProcessInfo.processInfo.environment["ZK_FIX"]!
func result(_ name: String) -> String? {
    let data = try! Data(contentsOf: URL(fileURLWithPath: fix + "/" + name))
    return (try! JSONSerialization.jsonObject(with: data) as! [String: Any])["result"] as? String
}

print("tags")
check(ZkMoneyWire.tag("Zac.zk.money") == "zac", "a tag, folded")
check(ZkMoneyWire.tag(" @zac.zk.money. ") == "zac", "…from a mention")
check(ZkMoneyWire.tag("zac") == nil, "a bare word is no tag by itself")
check(ZkMoneyWire.tag("zac", bareAllowed: true) == "zac", "…unless the caller knows it is one")
check(ZkMoneyWire.tag("zac.eth") == nil && ZkMoneyWire.tag("a b.zk.money") == nil, "not a tag")
check(ZkMoneyWire.nameHash("zac") == "0x46f127163101255dc25a533a904a5fc10a98a3c27d675dc2944f876109dd0df9",
      "namehash(zac.zk.money) matches viem")
let account = ZkMoneyWire.account(result("ownerof-zac.json"))
check(account == "0xf5f6b47e15825e27bced1fe99ba90f8c2334fccf", "ownerOf reads the account")
check(ZkMoneyWire.account("0x" + String(repeating: "0", count: 64)) == nil, "a zero owner is an unclaimed tag")
let record = ZkMoneyWire.record(tag: "zac", account: account!, userRecord: result("userrecord-zac.json"))
check(record.aztec == "0x0e35b5beb1c09008a0388066efad062cd3e5fa060fdcddeef04d8753cad71d27", "the Aztec address")
check(record.onMainnet, "made on Aztec mainnet's rollup")

print("moves")
let me = "0xf4a56a0d8d04bc17df79241ce7c3c2eb2ef8b067"
let deposit = "0x32dec5945f023b441e6d6aa1b5d0f15ce1d7c588"
check(ZkMoneyWire.isDepositAddress(code: result("code-deposit.json")), "a swept deposit address is zk.money's proxy")
check(!ZkMoneyWire.isDepositAddress(code: result("code-portal-head.json")), "the portal's own code is not")
check(!ZkMoneyWire.isDepositAddress(code: "0x363d3d373d3d3d363d73" + String(repeating: "ab", count: 20) + "5af43d82803e903d91602b57fd5bf3"),
      "a minimal proxy to anything else is not")
check(!ZkMoneyWire.isDepositAddress(code: "0x"), "an address with no code yet is not (yet)")
check(ZkMoneyWire.move(token: ZkMoneyWire.dai, from: me, to: deposit, watched: me, counterpartyCode: result("code-deposit.json")) == .deposit,
      "DAI out to a deposit address is a deposit")
check(ZkMoneyWire.move(token: ZkMoneyWire.dai, from: "0xdf410ad448a0f7165181fbdb32f8896f4a0d9449", to: me, watched: me, counterpartyCode: nil) == .withdrawal,
      "DAI in from the portal is a withdrawal")
check(ZkMoneyWire.move(token: ZkMoneyWire.dai, from: "0x6534905c84f13af94d649706e4ec711770d3603c", to: me, watched: me, counterpartyCode: nil) == .withdrawal,
      "…from an old portal too")
check(ZkMoneyWire.move(token: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", from: "0xdf410ad448a0f7165181fbdb32f8896f4a0d9449", to: me, watched: me, counterpartyCode: nil) == nil,
      "a portal only ever pays out DAI")
check(ZkMoneyWire.move(token: ZkMoneyWire.dai, from: "0xc2363b7155ee8391c5395b72c46a6d22bf49151c", to: me, watched: me, counterpartyCode: nil) == .withdrawal,
      "DAI in from the withdrawal executor is a withdrawal (how DAI withdrawals are paid since September)")
check(ZkMoneyWire.move(token: ZkMoneyWire.dai, from: "0x63e6cd9ff886cff198eaaab01cec2b707e7f5475", to: me, watched: me, counterpartyCode: nil) == .withdrawal,
      "…and from the savings deployment's executor")
let usdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
let swapEscrow = "0xb838d7ac708beaad5b1de7b24fd9bc7ec95152ad"
check(ZkMoneyWire.role(code: result("code-swap-escrow.json")) == .swapOut && ZkMoneyWire.role(code: result("code-swap-escrow-v2.json")) == .swapOut,
      "both swap escrows pay out")
check(ZkMoneyWire.move(token: usdc, from: swapEscrow, to: me, watched: me, counterpartyCode: result("code-swap-escrow.json")) == .withdrawal,
      "USDC in from a swap escrow is a withdrawal")
check(ZkMoneyWire.move(token: usdc, from: me, to: swapEscrow, watched: me, counterpartyCode: result("code-swap-escrow.json")) == nil,
      "a send TO a swap escrow is not a deposit")
check(ZkMoneyWire.role(code: result("code-savings-escrow.json")) == .deposit
      && ZkMoneyWire.move(token: ZkMoneyWire.dai, from: me, to: "0xb6aec98d3fe048f6add3b2d8f6e14e208fa144fe", watched: me,
                          counterpartyCode: result("code-savings-escrow.json")) == .deposit,
      "DAI out to a savings escrow is a deposit")
check(ZkMoneyWire.move(token: usdc, from: "0xb6aec98d3fe048f6add3b2d8f6e14e208fa144fe", to: me, watched: me,
                       counterpartyCode: result("code-savings-escrow.json")) == nil,
      "anything in from a savings escrow is not a withdrawal")
check(ZkMoneyWire.move(token: usdc, from: me, to: deposit, watched: me, counterpartyCode: result("code-deposit.json")) == .deposit,
      "USDC out to a deposit address is a deposit (it is swapped on the way in)")
check(ZkMoneyWire.move(token: ZkMoneyWire.dai, from: deposit, to: me, watched: me, counterpartyCode: nil) == nil,
      "DAI in from anyone else is nothing of zk.money's")
// Aztec V6 (2026-11-03): measured clones and the executor that paid 9 of 9.
check(ZkMoneyWire.role(code: result("code-deposit-aztec-v6.json")) == .deposit, "an Aztec V6 deposit address (a SIPA clone) is a deposit")
check(ZkMoneyWire.role(code: result("code-registration-aztec-v6.json")) == .deposit, "…and so is the registration clone a first deposit uses")
check(ZkMoneyWire.move(token: ZkMoneyWire.dai, from: "0x7c8c2147d1bb8b83e0a0501097372de170ee702a", to: me, watched: me, counterpartyCode: nil) == .withdrawal,
      "DAI in from Aztec V6's withdrawal executor is a withdrawal")
check(ZkMoneyWire.isPortal("0xCB99C58Fe81Ae6b2cB4835e46F7b703745879042") && ZkMoneyWire.currentPortal == "0xcb99c58fe81ae6b2cb4835e46f7b703745879042",
      "the current portal is Aztec V6's")
check(ZkMoneyWire.title(.deposit, amount: "459.58", symbol: "DAI") == "Deposited 459.58 DAI to zk.money", "the deposit's words")
check(ZkMoneyWire.dai(result("portal-dai.json")).map { $0 > 25_000 && $0 < 26_000 } == true, "the portal's DAI, whole units")

print("links")
let request = (try! String(contentsOfFile: fix + "/request-link.txt", encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)
guard case .request(let tag, let amount, let symbol, let note, let expires)? = ZkMoneyLink.link(request) else {
    print("  ✗ the request link did not decode"); exit(1)
}
check(tag == "zac" && symbol == "DAI" && note == "dinner", "tag, token and note")
check(amount == Decimal(string: "20.5"), "the amount, big-endian over 18 decimals: \(String(describing: amount))")
check(expires.map { Int($0.timeIntervalSince1970) } == 1_791_900_000, "the expiry, a cbor-x float64")
check(ZkMoneyLink.title(ZkMoneyLink.link(request)!) == "Payment request — 20.5 DAI to zac.zk.money", "the request's title")
check(ZkMoneyLink.capture(url: URL(string: request)!, text: request)!.note?.hasPrefix("“dinner”") == true, "its note is the row's body")
let v3 = (try! String(contentsOfFile: fix + "/request-link-v3.txt", encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)
guard case .request(let tag3, let amount3, _, let note3, let expires3)? = ZkMoneyLink.link(v3) else {
    print("  ✗ a /pay/<tag> request link did not decode"); exit(1)
}
check(tag3 == "zac" && amount3 == Decimal(string: "20.5") && note3 == "dinner", "zk.money's current /pay/<tag> request link")
let captured3 = ZkMoneyLink.capture(url: URL(string: v3)!, text: v3)!
check(captured3.expires == expires3 && captured3.expires != nil && captured3.secret == nil, "a request is dated by its expiry and holds no secret")
check(ZkMoneyLink.link("https://zk.money/pay/zac/extra#" + v3.split(separator: "#")[1]) == nil, "a deeper /pay/ path is not a request")
let pay = "https://zk.money/link#AbCdSeCrEtClAiMkEy-123"
check(ZkMoneyLink.link(pay) == .payment(kept: "https://zk.money/link"), "a payment link keeps no fragment")
check(ZkMoneyLink.link("https://wallet.zk.money/claim#zzz") == .payment(kept: "https://wallet.zk.money/claim"), "…a claim link neither")
check(ZkMoneyLink.title(.payment(kept: "x")) == "zk.money payment link", "a payment link's title")
let captured = ZkMoneyLink.capture(url: URL(string: pay)!, text: "claim this: " + pay)!
check(!captured.content.contains("SeCrEt") && captured.content == "claim this: https://zk.money/link", "capture drops the secret from the surrounding words too")
check(captured.note?.contains("was not kept") == true, "and the row's body says so until the caller keeps it")
check(captured.secret == pay, "the whole link is handed to the caller, for the Keychain alone")
check(ZkMoneyLink.paymentNote(kept: true).contains("never synced"), "a kept secret's note says where it is")
// Every payment link in ANY text, however spelled (review, 2026-10-17).
let bare = ZkMoneyLink.scrub("claim this: zk.money/link#BareSeCrEt-9 thanks")
check(bare.text == "claim this: zk.money/link thanks" && bare.secrets == ["https://zk.money/link#BareSeCrEt-9"],
      "a link with no scheme loses its secret too, and the secret gains one")
let mixed = ZkMoneyLink.scrub("see https://example.com/a then https://wallet.zk.money/claim#SeCoNd and zk.money/link#ThIrD")
check(!mixed.text.contains("SeCoNd") && !mixed.text.contains("ThIrD") && mixed.secrets.count == 2,
      "a payment link after another URL, and a second one, are scrubbed")
check(mixed.secrets.first == "https://wallet.zk.money/claim#SeCoNd", "the first secret comes first")
check(ZkMoneyLink.scrub("https://zk.money/request#abc").secrets.isEmpty && ZkMoneyLink.scrub("https://zk.money/request#abc").text == "https://zk.money/request#abc",
      "a request link is never scrubbed: it holds no secret")
check(ZkMoneyLink.scrub("https://evil.example/link#SeCrEt").secrets.isEmpty, "another host is left alone")
let bareCaptured = ZkMoneyLink.capture(url: URL(string: "http://zk.money/link#BareSeCrEt-9")!, text: "zk.money/link#BareSeCrEt-9")!
check(!bareCaptured.content.contains("BareSeCrEt") && bareCaptured.secret == "https://zk.money/link#BareSeCrEt-9",
      "capture of a scheme-less paste keeps no secret in the row (the detector adds the scheme)")
check(ZkMoneyLink.link("https://evil.example/request#" + request.split(separator: "#")[1]) == nil, "another host is not zk.money")
check(ZkMoneyLink.link("https://zk.money/request#!!") == nil, "a broken fragment is no request")
check(CBOR.decode([0xbf]) == nil, "an indefinite map is refused")

print("paying a tag (Aztec V6)")
func text(_ name: String) -> String {
    (try! String(contentsOfFile: fix + "/" + name, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)
}
// Every vector below was produced by viem against mainnet: the call on
// 2026-11-03, the lookup, gateway reply and proof again on 2026-11-11 from
// the resolver ENS names since (prd §1746).
check(ZkMoneyWire.resolveCall(tag: "zac") == text("resolve-call-zac.txt"), "resolve(dnsName, addr(node)) as viem encodes it")
guard case .offchain(let lookup) = ZkMoneyWire.lookup(revert: text("lookup-zac.txt")) else {
    print("  ✗ a V6 tag's OffchainLookup did not decode"); exit(1)
}
check(lookup.sender == ZkMoneyWire.resolver && lookup.url == "https://rop-v6.v6-prod.oxide.zk.money/{sender}/{data}.json",
      "the lookup names zk.money's resolver and its gateway")
check("0x" + Keccak256.hexString(lookup.callData) == text("resolve-call-zac.txt"), "…and asks the gateway the same call")
check(ZkMoneyWire.gatewayURL(lookup)?.host == ZkMoneyWire.gatewayHost, "the gateway's URL, filled in")
let elsewhere = ZkMoneyWire.Offchain(sender: lookup.sender, url: "https://evil.example/{sender}/{data}.json",
                                     callData: lookup.callData, callback: lookup.callback, extraData: lookup.extraData)
check(ZkMoneyWire.gatewayURL(elsewhere) == nil, "a gateway on any other host is refused")
let gateway = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fix + "/gateway-zac.json")))
guard let response = ZkMoneyWire.gatewayData(gateway) else { print("  ✗ the gateway's data did not read"); exit(1) }
check(ZkMoneyWire.callbackCall(lookup, response: response) == text("callback-call-zac.txt"), "resolveWithProof(response, extraData) as viem encodes it")
check(ZkMoneyWire.depositAddress(callbackResult: text("callback-zac.txt")) == "0xf29c42fc19059af433cc7f83a082d367356cf33d",
      "the proven deposit address")
check(ZkMoneyWire.lookup(revert: text("lookup-charlie.txt")) == .notOnV6, "a tag still on Alpha V5 is refused by the resolver itself")
check(ZkMoneyWire.lookup(revert: text("lookup-unclaimed.txt")) == .unclaimed, "an unclaimed tag")
check(ZkMoneyWire.lookup(revert: "0x08c379a0") == .unreadable && ZkMoneyWire.lookup(revert: nil) == .unreadable, "any other revert reads nothing")
// The resolver is ENS's, asked at pay time (prd §1750).
let namedWord = "0x000000000000000000000000" + "3DC71762063D7B87B3F79B3B98E03F0051B00A6E"
check(ZkMoneyWire.namedResolver(result: namedWord) == "0x3dc71762063d7b87b3f79b3b98e03f0051b00a6e", "the registry's answer, as an address")
check(ZkMoneyWire.namedResolver(result: "0x" + String(repeating: "0", count: 64)) == nil && ZkMoneyWire.namedResolver(result: nil) == nil
      && ZkMoneyWire.namedResolver(result: "0x1234") == nil && ZkMoneyWire.namedResolver(result: "0x01" + String(repeating: "0", count: 62)) == nil,
      "no resolver set, no answer, and anything that is not an address name none")
check(ZkMoneyWire.ensResolverCall == "0x0178b8bff605999a299a7229da9f2a3c65acf5cb829ae965cfe467f053e1b97c50b0eec2", "resolver(namehash(zk.money)), as viem encodes it")
let moved = "0x1111111111111111111111111111111111111111"
check(ZkMoneyWire.lookup(revert: text("lookup-zac.txt"), from: moved) == .unreadable, "a lookup from the pinned resolver is refused once ENS names another")
var relabel = text("lookup-zac.txt")
relabel = relabel.replacingOccurrences(of: "3dc71762063d7b87b3f79b3b98e03f0051b00a6e", with: "1111111111111111111111111111111111111111")
if case .offchain(let fromMoved) = ZkMoneyWire.lookup(revert: relabel, from: moved) { check(fromMoved.sender == moved, "…and one from the resolver ENS names is read") }
else { check(false, "a lookup from the resolver ENS names did not read") }
var forged = text("lookup-zac.txt")
forged = forged.replacingOccurrences(of: "3dc71762063d7b87b3f79b3b98e03f0051b00a6e", with: "1111111111111111111111111111111111111111")
check(ZkMoneyWire.lookup(revert: forged) == .unreadable, "a lookup from any other contract is refused")
check(ZkMoneyWire.payRefusal(chainId: 1, token: ZkMoneyWire.dai, usd: 20) == nil, "20 DAI on Ethereum pays")
check(ZkMoneyWire.payRefusal(chainId: 1, token: "0xA0b86991c6218b36c1d19d4a2e9eb0ce3606eB48", usd: 20) == nil, "…and USDC, checksummed")
check(ZkMoneyWire.payRefusal(chainId: 8453, token: ZkMoneyWire.usdc, usd: 20) != nil, "not on Base")
check(ZkMoneyWire.payRefusal(chainId: 1, token: nil, usd: 20) != nil, "not ETH")
check(ZkMoneyWire.payRefusal(chainId: 1, token: ZkMoneyWire.dai, usd: 0.35) != nil, "not the fee or less")
check(ZkMoneyWire.payRefusal(chainId: 1, token: ZkMoneyWire.dai, usd: 5_000) != nil, "not $5,000 or more")
check(ZkMoneyWire.dnsName(String(repeating: "a", count: 64)) == nil, "a label DNS cannot carry")

// Paying a request (prd §1745): the amount asked plus the deposit's fee, in
// the token asked for; anything a deposit does not take is left to you.
let payDai = ZkMoneyWire.requestPayment(tag: "zac", amount: Decimal(string: "20.5"), symbol: "DAI")
check(payDai == ZkMoneyWire.RequestPayment(to: "zac.zk.money", amount: "20.85", asked: "20.5", token: ZkMoneyWire.dai),
      "20.5 DAI asked is written as 20.85 DAI to zac.zk.money")
check(ZkMoneyWire.requestPayment(tag: "zac", amount: 100, symbol: "usdc").amount == "100.35"
      && ZkMoneyWire.requestPayment(tag: "zac", amount: 100, symbol: "usdc").token == ZkMoneyWire.usdc, "USDC, however its symbol is cased")
check(ZkMoneyWire.requestPayment(tag: "zac", amount: 5, symbol: "USDT").token == ZkMoneyWire.usdt, "USDT")
// Format 4 (prd §1746): the shape of a real request of 2026-11-11, with a made-up tag and id.
let v4 = text("request-link-v4.txt")
guard case .request(let tag4, let amount4, let symbol4, let note4, let expires4)? = ZkMoneyLink.link(v4) else {
    print("  ✗ a format-4 request did not read"); exit(1)
}
check(tag4 == "zac" && amount4 == Decimal(string: "0.01") && symbol4 == nil && note4 == "dinner" && expires4.map { Int($0.timeIntervalSince1970) } == 1_814_364_000,
      "format 4: a 16-byte id, no token, the amount, note and expiry")
check(ZkMoneyLink.title(ZkMoneyLink.link(v4)!) == "Payment request — $0.01 to zac.zk.money", "a request that names no token is titled in dollars")
// Short links (prd §1748): a record sealed as zk.money's wallet seals one
// (noble's HKDF, AES-CTR and Ed25519, a made-up key and the format-4 packet above).
let shortFix = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fix + "/short-link-record.json"))) as! [String: Any]
let shortURL = shortFix["link"] as! String, shortPay = shortFix["paymentLink"] as! String
let shortFields = shortFix["fields"] as! [String]
guard let short = ZkMoneyLink.short(shortURL), case .shortRequest(let shortSeed)? = ZkMoneyLink.link(shortURL) else {
    print("  ✗ a short request link did not read"); exit(1)
}
check(short.kind == 2 && short.seed.count == 16 && short.seed == shortSeed, "a short link is a kind and a 16-byte seed")
check(ZkMoneyLink.short("https://zk.money/r#AhAREhMUFRYXGBkaGxwdHh8g") == nil && ZkMoneyLink.short("https://zk.money/r#AxAREhMUFRYXGBkaGxwdHh8") == nil
      && ZkMoneyLink.short("https://evil.example/r#" + shortURL.split(separator: "#")[1]) == nil, "not a short link: 17 bytes too many, an unknown kind, another host")
let opened = ZkMoneyLink.open(fields: shortFields, short: short)
check(opened.map { Data($0).base64EncodedString() } == ZkMoneyLink.base64url(shortFix["packet"] as! String).map { Data($0).base64EncodedString() },
      "its record opens to the packet that was sealed")
check(opened.flatMap(ZkMoneyLink.requestPacket(bytes:)) == ZkMoneyLink.link(v4), "…which is the request")
check(ZkMoneyLink.open(fields: shortFix["forgedFields"] as! [String], short: short) == nil, "a record sealed by another key under the link's tag opens to nothing")
check(ZkMoneyLink.open(fields: shortFix["unsignedFields"] as! [String], short: short) == nil, "the link's key over another signature opens to nothing")
var bent = shortFields; bent[7] = "0x00" + String(repeating: "5a", count: 31)
check(ZkMoneyLink.open(fields: bent, short: short) == nil, "a changed field opens to nothing")
check(ZkMoneyLink.open(fields: Array(shortFields.dropLast()), short: short) == nil, "fourteen fields are not a record")
var high = shortFields; high[0] = "0x01" + high[0].dropFirst(4)
check(ZkMoneyLink.open(fields: high, short: short) == nil, "a field over 31 bytes is not a record's")
check(ZkMoneyLink.open(fields: shortFields, short: ZkMoneyLink.Short(kind: 2, seed: Array(short.seed.reversed()))) == nil, "another link's seed opens nothing")
// A short PAYMENT link holds money: its seed is the claim secret.
check(ZkMoneyLink.link(shortPay) == .payment(kept: "https://zk.money/r"), "a short payment link is kept without its fragment")
let shortMixed = ZkMoneyLink.scrub("pay me \(shortURL) or claim \(shortPay) thanks")
check(shortMixed.text == "pay me \(shortURL) or claim https://zk.money/r thanks" && shortMixed.secrets == [shortPay],
      "a short payment link loses its secret wherever it stands; a short request keeps its fragment")
let shortKept = ZkMoneyLink.capture(url: URL(string: shortURL)!, text: shortURL)
check(shortKept?.title == "Payment request — zk.money" && shortKept?.content == shortURL && shortKept?.secret == nil && shortKept?.title.hasPrefix(ZkMoneyLink.requestTitleLead) == true,
      "a short request is kept whole, titled by where it is from")
let payDollars = ZkMoneyWire.requestPayment(tag: "zac", amount: amount4, symbol: nil)
check(payDollars == ZkMoneyWire.RequestPayment(to: "zac.zk.money", amount: "0.36", asked: "0.01", token: nil),
      "no token named: the fee is added in dollars and the token is yours to pick")
check(ZkMoneyWire.payOrder == [ZkMoneyWire.usdc, ZkMoneyWire.dai, ZkMoneyWire.usdt] && ZkMoneyWire.payOrder.allSatisfy(ZkMoneyWire.payTokens.contains),
      "a request in dollars picks among the tokens a deposit takes, USDC first")
let payOther = ZkMoneyWire.requestPayment(tag: "zac", amount: 5, symbol: "sUSDS")
check(payOther.amount.isEmpty && payOther.token == nil && payOther.asked == nil, "a token a deposit does not take is left to you: no amount, no fee guessed")
let payOpen = ZkMoneyWire.requestPayment(tag: "zac", amount: nil, symbol: "DAI")
check(payOpen.amount.isEmpty && payOpen.asked == nil && payOpen.token == ZkMoneyWire.dai, "a request with no amount writes none")
check(ZkMoneyWire.plainAmount(Decimal(string: "1234567.891")! ) == "1234567.891", "an amount is plain digits: no grouping, no exponent")
check(ZkMoneyWire.plainAmount(Decimal(string: "0.1234567")!) == "0.123457", "…and at most six places")
let payNow = Date(timeIntervalSince1970: 1_800_000_000)
check(ZkMoneyWire.requestOpen(expires: payNow.addingTimeInterval(60), now: payNow), "a request is open until its expiry")
check(!ZkMoneyWire.requestOpen(expires: payNow.addingTimeInterval(-60), now: payNow) && !ZkMoneyWire.requestOpen(expires: payNow, now: payNow), "…and shut from it on")
check(ZkMoneyWire.requestOpen(expires: nil, now: payNow), "one with no expiry stays open")
check(ZkMoneyLink.title(.request(tag: "zac", amount: 20.5, symbol: "DAI", note: nil, expires: nil)).hasPrefix(ZkMoneyLink.requestTitleLead),
      "every request's title begins with the words Pay's gate reads")
// A fee bigger than the amount says so, and a paid request says Paid (prd §1752).
check(ZkMoneyWire.feeWarning(total: ZkMoneyWire.requestPayment(tag: "zac", amount: Decimal(string: "0.01"), symbol: "DAI").amount)
      == "The fee is 35 times the amount", "a cent asked: the fee is 35 times the amount")
check(ZkMoneyWire.feeWarning(total: "0.6") == "The fee is more than the amount", "a quarter asked: the fee is more than the amount, under twice")
check(ZkMoneyWire.feeWarning(total: "0.7") == nil && ZkMoneyWire.feeWarning(total: payDai.amount) == nil,
      "an amount the size of the fee or over says nothing")
check(ZkMoneyWire.feeWarning(total: "0.35") == nil && ZkMoneyWire.feeWarning(total: "") == nil && ZkMoneyWire.feeWarning(total: "0.2") == nil,
      "…nor does a total that is the fee alone, less than it, or not a number")
let askedTitle = ZkMoneyLink.title(.request(tag: "zac", amount: Decimal(string: "0.01"), symbol: "DAI", note: nil, expires: nil))
check(ZkMoneyLink.paidTitle(askedTitle) == "Paid — 0.01 DAI to zac.zk.money", "a paid request's title leads with Paid, on the same one seam")
check(ZkMoneyLink.paidTitle(ZkMoneyLink.requestTitleLead + "zk.money", asked: "0.01 DAI", to: "zac.zk.money") == "Paid — 0.01 DAI to zac.zk.money",
      "a short link's row takes what Send read from it")
check(ZkMoneyLink.paidTitle(ZkMoneyLink.requestTitleLead + "zk.money") == "Paid — zk.money", "…and keeps its own words when Send read nothing")
check(ZkMoneyLink.paidTitle("zk.money payment link") == "zk.money payment link" && !ZkMoneyLink.paidTitle(askedTitle).hasPrefix(ZkMoneyLink.requestTitleLead),
      "any other title is left alone, and a paid one no longer reads as open")

// A format-3 request as zk.money's wallet writes one (made-up ids, the real
// packet's shape, prd §1751): its token is named as it stands on Aztec.
let oxLink = "https://zk.money/pay/zac#2QEDqQEDAlggAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAcDY3phYwRQAAAAAAAAAAAAI4byb8EAAAh4KjB4MTExMTExMTExMTExMTExMTExMTExMTExMTExMTExMTExMTExMTExMQpYICIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiCRIFZU9YREFJBmZjb2ZmZWU"
if case .request(let tag, let amount, let symbol, _, _)? = ZkMoneyLink.link(oxLink) {
    let pay = ZkMoneyWire.requestPayment(tag: tag, amount: amount, symbol: symbol)
    check(symbol == "DAI" && pay == ZkMoneyWire.RequestPayment(to: "zac.zk.money", amount: "0.36", asked: "0.01", token: ZkMoneyWire.dai),
          "a request in oxDAI is one in DAI: the amount and the fee are written")
    check(ZkMoneyLink.title(.request(tag: tag, amount: amount, symbol: symbol, note: nil, expires: nil)) == "Payment request — 0.01 DAI to zac.zk.money",
          "…and its row says DAI")
} else { check(false, "a format-3 request in oxDAI is read") }
check(ZkMoneyLink.dollarName("oxDAI") == "DAI" && ZkMoneyLink.dollarName("OXDAI") == "DAI" && ZkMoneyLink.dollarName("USDC") == "USDC" && ZkMoneyLink.dollarName("oxETH") == "oxETH",
      "only zk.money's dollar is renamed")
// A legacy link names no decimals: its amount is six places, as the codec says.
if case .request(_, let amount, _, _, _)? = ZkMoneyLink.link("https://zk.money/pay/zac#2QEDpgECAlggAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAcDY3phYwRCJxAFY0RBSQZmY29mZmVl") {
    check(amount == Decimal(string: "0.01"), "a link with no decimals is read at six places")
} else { check(false, "a legacy request is read") }

check(ZkMoneyLink.spellsLink(" https://zk.money/r#AmW2BnPW7YhL8BwsIi2CraA ") && ZkMoneyLink.spellsLink("https://wallet.zk.money/pay/zac#2QED") && ZkMoneyLink.spellsLink("HTTPS://zk.money/r#A"),
      "a zk.money link is known by its address, read or not")
check(!ZkMoneyLink.spellsLink("zac.zk.money") && !ZkMoneyLink.spellsLink("https://zk.money.example.com/r#A") && !ZkMoneyLink.spellsLink("https://example.com/zk.money") && !ZkMoneyLink.spellsLink("0x6b175474e89094c44da98b954eedeac495271d0f") && !ZkMoneyLink.spellsLink(""),
      "…and a tag, another site and an address are not one")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
SWIFT

echo "ZkMoneyWire, compiled whole"
if ! swiftc -Onone -o "$TMP/run" "$WIRE" "$KECCAK" "$LINK" "$TMP/main.swift" > "$TMP/build.log" 2>&1; then
  echo "✗ the harness did not compile against the shipped ZkMoneyWire:"
  sed -n '1,40p' "$TMP/build.log"
  exit 1
fi
ZK_FIX="$PWD/$FIX" "$TMP/run" || exit 1

# --- mutations ----------------------------------------------------------------
echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$WIRE" "$WORK/ZkMoneyWire.swift"
  cp "$LINK" "$WORK/ZkMoneyLink.swift"
  # The anchor names its own file: the wire's, else the Shared link reader's.
  local target="$WORK/ZkMoneyWire.swift" original="$WIRE"
  if ! grep -qF -- "$from" "$target"; then target="$WORK/ZkMoneyLink.swift"; original="$LINK"; fi
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  then echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1; fi
  if cmp -s "$original" "$target"; then
    echo "  ✗ $name — the mutation changed nothing"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/ZkMoneyWire.swift" "$KECCAK" "$WORK/ZkMoneyLink.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if ZK_FIX="$PWD/$FIX" "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "a lookup trusted from any contract" \
  'sender == expected.lowercased(),' \
  'sender.count == 42,'
mutate "a request in oxDAI left with no amount" \
  '== .orderedSame ? "DAI" : symbol' \
  '== .orderedSame ? symbol : symbol'
mutate "a legacy amount read at eighteen places" \
  'static let legacyDecimals = 6' \
  'static let legacyDecimals = 18'
mutate "any site's link named a zk.money request" \
  'return isZkMoneyHost(url.host)' \
  'return url.host != nil'
mutate "a gateway on any host" \
  'url.scheme == "https", url.host == gatewayHost else { return nil }' \
  'url.scheme == "https" else { return nil }'
mutate "a V5 tag not refused" \
  'if selector == Selector3668.rollupMismatch { return .notOnV6 }' \
  'if selector == Selector3668.rollupMismatch { return .unreadable }'
mutate "a deposit over the cap paid" \
  'if usd >= payCapUSD {' \
  'if usd > payCapUSD * 2 {'
mutate "a deposit on another network paid" \
  'guard chainId == 1, let token,' \
  'guard let token,'
mutate "an Aztec V6 deposit clone not read" \
  '|| registrationImplementations.contains(implementation)' \
  '|| false'
mutate "the withdrawal executor not named" \
  'return isPortal(a) || withdrawalExecutors.contains(a)' \
  'return isPortal(a)'
mutate "a swap escrow read as a deposit" \
  'if swapEscrowImplementations.contains(implementation) { return .swapOut }' \
  'if swapEscrowImplementations.contains(implementation) { return .deposit }'
mutate "a savings escrow not read" \
  '|| savingsEscrowImplementations.contains(implementation) { return .deposit }' \
  '{ return .deposit }'
mutate "the /pay/ path refused" \
  '|| (path.hasPrefix("/pay/") && path.split(separator: "/").count == 2)' \
  '|| false'
mutate "a request left undated" \
  'secret: clean.secrets.first, expires: expires)' \
  'secret: clean.secrets.first, expires: nil)'
mutate "a scheme-less link left whole" \
  '((?:https?://)?(?:[a-z0-9-]+' \
  '((?:https?://)(?:[a-z0-9-]+'
mutate "only the first link scrubbed" \
  'for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {' \
  'for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).prefix(1) {'
mutate "a payment link kept with its secret" \
  'parts?.fragment = nil' \
  'parts?.fragment = parts?.fragment'
mutate "any minimal proxy read as a deposit address" \
  'if deployments.contains(where: { $0.depositImplementation == implementation })' \
  'if true'
mutate "DAI from anyone read as a withdrawal" \
  'if to.lowercased() == me, paysWithdrawals(from), token?.lowercased() == dai { return .withdrawal }' \
  'if to.lowercased() == me, token?.lowercased() == dai { return .withdrawal }'
mutate "the namehash built bottom-up" \
  'for label in display(tag).split(separator: ".").reversed() {' \
  'for label in display(tag).split(separator: ".") {'
mutate "the amount read little-endian" \
  'for byte in raw { value = value * 256 + Decimal(byte) }' \
  'for byte in raw.reversed() { value = value * 256 + Decimal(byte) }'
mutate "a zero owner read as an account" \
  'return address.allSatisfy { $0 == "0" } ? nil : "0x" + address' \
  'return "0x" + address'
mutate "a bare word taken as a tag" \
  '} else if !bareAllowed {' \
  '} else if false {'
mutate "the cbor-x tag not unwrapped" \
  'return item(b, &i, depth: depth + 1)
        case 7 where info == 27:' \
  'return nil
        case 7 where info == 27:'

mutate "a request paid without the fee" \
  'amount: plainAmount(amount + fee), asked' \
  'amount: plainAmount(amount), asked'
mutate "a request's USDC paid in DAI" \
  'case "USDC": usdc' \
  'case "USDC": dai'
mutate "a fee added to a token a deposit does not take" \
  'guard let amount, amount > 0, symbol == nil || token != nil, let fee' \
  'guard let amount, amount > 0, let fee'
mutate "a format-4 request refused" \
  '(1...4).contains(format),' \
  '(1...3).contains(format),'
mutate "a request with no token titled without its dollars" \
  '?? "$\(plain(a))" }' \
  '?? plain(a) }'
mutate "an expired request still open" \
  'expires.map { $0 > now } ?? true' \
  'expires.map { _ in true } ?? true'
mutate "a short link's record opened without its key's commitment" \
  'guard Array(SHA256.hash(data: Data(publicKey)).prefix(16)) == short.seed,' \
  'guard true,'
mutate "a short link's record opened without its signature" \
  'signer.isValidSignature(Data(signature), for: Data("zk.money link".utf8) + [1, short.kind] + payload) else { return nil }' \
  'signer.rawRepresentation.count == 32 else { return nil }'
mutate "a short payment link kept with its secret" \
  'if path.hasSuffix("/link") || path.hasSuffix("/claim") || shortLink?.kind == Short.payment {' \
  'if path.hasSuffix("/link") || path.hasSuffix("/claim") {'
mutate "a short request scrubbed of the fragment that is the request" \
  'else if base.lowercased().hasSuffix("/r") { continue }' \
  ''
mutate "a request's record opened with a payment link's key" \
  'info: Data("zk.money link cipher".utf8) + [1, short.kind], outputByteCount: 32)' \
  'info: Data("zk.money link cipher".utf8) + [1, 1], outputByteCount: 32)'
mutate "a lookup held to the pin, whatever ENS names" \
  'sender == expected.lowercased(),' \
  'sender == resolver,'
mutate "no resolver read as one" \
  'b[12...].contains(where: { $0 != 0 }) else { return nil }' \
  'b.count == 32 else { return nil }'
mutate "a request's title losing the words Pay reads" \
  'return requestTitleLead + (what.map' \
  'return "Request — " + (what.map'
mutate "a fee many times the amount left unsaid" \
  'guard asked > 0.000_000_5, payFeeUSD > asked else { return nil }' \
  'guard asked > 0.000_000_5, payFeeUSD > asked * 100 else { return nil }'
mutate "a fee smaller than the amount warned of" \
  'guard asked > 0.000_000_5, payFeeUSD > asked else { return nil }' \
  'guard asked > 0.000_000_5 else { return nil }'
mutate "a paid request still titled as open" \
  'return paidTitleLead + title.dropFirst(requestTitleLead.count)' \
  'return title'

# Pay a request, read (prd §1745): what a screen cannot show. Pay drawn with no
# account to pay from, or on a row already paid, is a dead control; a row
# marked paid by a send to someone else, or by a dry run, is a false status.
VERBS="Casberi/Casberi/Model/Verbs.swift"
ZK="Casberi/Casberi/Model/ZkMoney.swift"
SEND="Casberi/Casberi/Screens/MoveSentence.swift"
grep -q 'if YourAccountDemo.shownAddress != nil, ZkMoney.payableRequest(thing) != nil {' "$VERBS" \
  || { echo "✗ Pay is drawn with no account to pay from, or on a row that is not an open request"; exit 1; }
grep -q 'guard thing.kind == .link, thing.mark != .done, thing.title.hasPrefix(ZkMoneyLink.requestTitleLead),' "$ZK" \
  && grep -q 'guard ZkMoneyWire.requestOpen(expires: expires, now: now) else { return nil }' "$ZK" \
  || { echo "✗ Pay stands on a request already paid or expired, or every row parses its link (the title gate is gone)"; exit 1; }
[[ $(grep -c 'MoveSentence.payDraft(found, thing: thing.id)' Casberi/Casberi/Screens/ThingSheetView.swift Casberi/Casberi/Screens/FeedScreen+Actions.swift | awk -F: '{n+=$2} END{print n}') -eq 2 ]] \
  || { echo "✗ Pay no longer opens Send written for the request from the sheet and the row"; exit 1; }
awk '/private func settleRequest\(/,/^    }/' "$SEND" > "$TMP/settle.txt"
grep -q 'guard let request = payingRequest, outcome != .dryRun else { return }' "$TMP/settle.txt" \
  && grep -q 'requestDeposits.contains(p.to.lowercased())' "$TMP/settle.txt" \
  && awk '/guard paid else \{ return \}/{g=NR} /thing.mark = .done/{m=NR} END{exit !(g && m && g<m)}' "$TMP/settle.txt" \
  || { echo "✗ a request is marked paid by a dry run, or by a send that did not pay its tag"; exit 1; }
grep -q 'if text.lowercased() == payingRequest?.to { requestDeposits.insert(address.lowercased()) }' "$SEND" \
  && grep -q 'settleRequest(batch, outcome: sent.outcome)' "$SEND" \
  || { echo "✗ a paid request is never marked: no address is kept for its tag, or the landing no longer settles it"; exit 1; }
grep -q 'amount == request.amount, to.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == request.to else { return nil }' "$SEND" \
  || { echo "✗ the line says the fee was added after the amount or the tag was changed"; exit 1; }

# A request link in To (prd §1748), read: To looks a link up before it reads
# an address or a name; a short link nobody can read says so instead of
# resolving to nothing; a pasted link has no row, so nothing is marked.
awk '/private func resolve\(\) async \{/{r=NR} /if await takeRequestLink\(text\) \{ return \}/{t=NR} /if text.lowercased\(\).hasPrefix\("0x"\) \{/{if(!x) x=NR} END{exit !(r && t && x && r<t && t<x)}' "$SEND" \
  || { echo "✗ Send's To no longer reads a request link before an address"; exit 1; }
awk '/private func takeRequestLink\(/,/^    }/' "$SEND" > "$TMP/take.txt"
grep -q 'link = await ZkMoney.request(short:' "$TMP/take.txt" \
  && grep -q 'guard ZkMoneyWire.requestOpen(expires: expires, now: .now) else {' "$TMP/take.txt" \
  && grep -q 'payingRequest = Self.paying(pay, symbol: symbol, thing: payingRequest?.thing)' "$TMP/take.txt" \
  || { echo "✗ a pasted request link is not looked up, pays an expired request, or forgets the row Pay opened it from"; exit 1; }
grep -q 'guard let id = request.thing else { return }' "$SEND" \
  || { echo "✗ a link pasted into To, which has no row, reaches the row fetch"; exit 1; }
grep -q 'if DemoMode.isActive { return demoRequest }' "$ZK" \
  || { echo "✗ the demo asks Aztec for a short link's record: the demo reads no chain"; exit 1; }

# The token and the amount of a pasted request (prd §1749), read. On build 980
# a request pasted while Send held Base's token kept that token under
# Ethereum, and DAI picked by hand cleared the amount: the sentence named who
# and never how much.
grep -q 'with = pick' "$TMP/take.txt" && grep -q 'inDollars = pick == nil' "$TMP/take.txt" \
  && grep -q 'let wanted = (pay.token.map { \[$0\] } ?? \[\]) + ZkMoneyWire.payOrder' "$TMP/take.txt" \
  || { echo "✗ a pasted request keeps another network's token, or picks none of the tokens you hold"; exit 1; }
awk '/private func choose\(_ h: Tokens.Held\) \{/,/^    }/' "$SEND" \
  | grep -q 'if let request = payingRequest, amount == request.amount, ZkMoneyWire.payTokens.contains(h.id) {' \
  || { echo "✗ picking a deposit token clears the amount a request asked for"; exit 1; }

# A link in To is named while it is read, never spelled (prd §1751).
awk '/private var toWord: some View \{/,/^    }/' "$SEND" \
  | grep -q 'ZkMoneyLink.spellsLink(to) ? String(localized: "zk.money request")' \
  || { echo "✗ To spells a request link out while it is looked up"; exit 1; }

# Quality of life (prd §1752), read. A link pasted from the sentence that is
# not a request would sit in To as an address nobody answers to; a paid row
# that kept its title would read as open; a fee warning drawn after the
# amount changed would warn about a sentence that is no longer there.
awk '/private func pasteLink\(\) \{/,/^    }/' "$SEND" > "$TMP/paste.txt"
awk '/guard ZkMoneyLink.spellsLink\(text\) else \{/{g=NR} /to = text/{t=NR} END{exit !(g && t && g<t)}' "$TMP/paste.txt" \
  || { echo "✗ Paste link puts any link into To, not only a request"; exit 1; }
grep -q 'UIPasteboard.general.detectedPatterns(for: \[link\])' "$SEND" \
  && ! awk '/private func readClipboard\(\) async \{/,/^    }/' "$SEND" | grep -q 'UIPasteboard.general.string' \
  || { echo "✗ the clipboard is read before the tap: Paste link must ask the system for a pattern only"; exit 1; }
grep -q 'thing.title = ZkMoneyLink.paidTitle(thing.title, asked: request.asked, to: request.to)' "$TMP/settle.txt" \
  && grep -q 'if case .landed(let transaction?, _) = outcome {' "$TMP/settle.txt" \
  || { echo "✗ a paid request keeps its open title, or keeps an explorer page for a send never seen on chain"; exit 1; }
grep -q 'if thing.mark == .done, thing.title.hasPrefix(ZkMoneyLink.paidTitleLead),' "$VERBS" \
  || { echo "✗ Explorer is drawn on a request that was not paid from here"; exit 1; }
awk '/private var requestFeeWarning: String\? \{/,/^    }/' "$SEND" | grep -q 'guard requestPrint != nil, let request = payingRequest else { return nil }' \
  || { echo "✗ the fee warning outlives the request: it is said after the amount or the tag changed"; exit 1; }
awk '/static func againDraft\(_ thing: Thing\) -> Draft\? \{/,/^    }/' "$SEND" > "$TMP/again.txt"
grep -q 'guard thing.transferDirection == "sent", let to = sendableCounterparty(thing)' "$TMP/again.txt" \
  && grep -q 'WalletWatch.sameAddress(thing.walletAddress ?? "", account)' "$TMP/again.txt" \
  || { echo "✗ Again is offered on a transfer this account did not send, or to someone Send would refuse"; exit 1; }
awk '/enum RecentTo \{/,/^    }/' "$SEND" > "$TMP/recent.txt"
grep -q 'if let name = p.toName, ZkMoneyWire.tag(name) != nil { return name.lowercased() }' "$TMP/recent.txt" \
  && grep -q 'return ZkMoney.knownName(for: p.to) == nil ? p.to : nil' "$TMP/recent.txt" \
  || { echo "✗ Recent keeps a zk.money deposit address, which is spent once paid, instead of the tag"; exit 1; }
grep -q 'if verb == .send, !sweeping, sent.outcome != .dryRun, !YourAccountDemo.isDemo(account) {' "$SEND" \
  || { echo "✗ Recent records a dry run, a sweep, a card's payment or the demo's send"; exit 1; }

# The resolver is asked of ENS before each lookup (prd §1750), and the lookup
# must come from the one it names: the pin alone went stale in eight days.
awk '/static func depositAddress\(tag: String\) async -> PayAnswer \{/,/^    }/' "$ZK" > "$TMP/deposit.txt"
awk '/to: ZkMoneyWire.ensRegistry/{e=NR} /resolver = named/{n=NR} /to: resolver, data: call/{c=NR} /ZkMoneyWire.lookup\(revert: data, from: resolver\)/{l=NR} END{exit !(e && n && c && l && e<n && n<c && c<l)}' "$TMP/deposit.txt" \
  || { echo "✗ paying a tag no longer asks ENS for the resolver first, or reads a lookup from another contract"; exit 1; }

echo "✓ zk.money self-test passed"
