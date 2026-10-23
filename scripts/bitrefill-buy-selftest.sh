#!/bin/zsh
# Buy, Move's fourth verb (prd §1473), compiled AS SHIPPED.
#
# `Model/BitrefillBuy.swift` is Foundation-only, so this compiles it WHOLE,
# with the typed-data encoder beside it, and holds it to what was MEASURED on
# Bitrefill's accountless door on 2026-10-22: the search's product shape and
# its forty category slugs, the detail's priced packages, the sign-in
# challenge and the exact message and header the server took, the invoice,
# the payment challenge and the authorization the account signs, and the
# order's standing. What it guards renders fine and pays the wrong thing: a
# card folded into the wrong group, a sign-in the server refuses with a 402
# that says nothing, an authorization whose typehash USDC does not know, a
# code read off the wrong field.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/BitrefillBuy.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
TYPED="Casberi/Casberi/Model/SafeTypedData.swift"
X402="Casberi/Casberi/Model/BitrefillX402.swift"
MOVE="Casberi/Casberi/Screens/MoveSentence.swift"
SHEET="Casberi/Casberi/Screens/ThingSheetView.swift"
BRIDGE="Casberi/Casberi/Model/BitrefillBridge.swift"
MESSAGE="Casberi/Casberi/Model/YourAccountMessage.swift"
for f in "$SRC" "$TX" "$KECCAK" "$CLEARSIGN" "$TYPED" "$X402" "$MOVE" "$SHEET" "$BRIDGE" "$MESSAGE"; do
  [[ -f "$f" ]] || { print -u2 "✗ $f not found"; exit 1; }
done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
func json(_ text: String) -> Any { try! JSONSerialization.jsonObject(with: text.data(using: .utf8)!) }
typealias B = BitrefillBuy

// ── The search, as measured ────────────────────────────────────────────────
let searchJSON = """
{"categories":[{"count":211,"value":"food"}],"products":[
 {"_id":"virtual-prepaid-visa-usa","categories":["payment-cards"],"countries":["US"],"currency":"USD","in_stock":true,"keywords":[],"name":"Digital Prepaid Visa USA","slug":"virtual-prepaid-visa-usa","type":"giftcards"},
 {"_id":"amazon_com-usa","categories":["online-marketplaces"],"countries":["US","PR"],"currency":"USD","in_stock":true,"keywords":["whole foods"],"name":"Amazon.com USA","slug":"amazon_com-usa","type":"giftcards"},
 {"_id":"doordash-usa","categories":["food","food-delivery"],"countries":["US"],"currency":"USD","in_stock":true,"name":"DoorDash USA","slug":"doordash-usa","type":"giftcards"},
 {"_id":"apple-usa","categories":["electronics"],"countries":["US"],"currency":"USD","in_stock":true,"name":"Apple USA","slug":"apple-usa","type":"giftcards"},
 {"_id":"uber-eats-usa","categories":["food","food-delivery"],"countries":["US"],"currency":"USD","in_stock":true,"name":"Uber Eats USA","slug":"uber-eats-usa","type":"giftcards"},
 {"_id":"uber-usa","categories":["transportation"],"countries":["US"],"currency":"USD","in_stock":true,"name":"Uber USA","slug":"uber-usa","type":"giftcards"},
 {"_id":"steam-usa","categories":["games","game-stores"],"countries":["US"],"currency":"USD","in_stock":true,"name":"Steam USD","slug":"steam-usa","type":"giftcards"},
 {"_id":"airbnb-usa","categories":["travel","accommodation"],"countries":["US"],"currency":"USD","in_stock":true,"name":"Airbnb USA","slug":"airbnb-usa","type":"giftcards"},
 {"_id":"stubhub-usa","categories":["entertainment","experiences"],"countries":["US"],"currency":"USD","in_stock":true,"name":"StubHub USA","slug":"stubhub-usa","type":"giftcards"},
 {"_id":"openai-usa","categories":["vpn"],"countries":["US"],"currency":"USD","in_stock":true,"name":"OpenAI ChatGPT USA","slug":"openai-usa","type":"giftcards"},
 {"_id":"netflix-usa","categories":["streaming"],"countries":["US"],"currency":"USD","in_stock":false,"name":"Netflix USA","slug":"netflix-usa","type":"giftcards"},
 {"_id":"atandt-usa","categories":["refill"],"countries":["US"],"currency":"USD","in_stock":true,"name":"AT&T USA","slug":"atandt-usa","type":"refills"},
 {"_id":"bitrefill-esim-europe","categories":["esim"],"countries":["FR"],"currency":"USD","in_stock":true,"name":"Bitrefill eSIM Europe","slug":"bitrefill-esim-europe","type":"esims"},
 {"_id":"nameless","categories":[],"countries":[],"currency":"USD","in_stock":true,"slug":"nameless","type":"giftcards"}
],"found":14,"page":1,"per_page":25}
"""
let products = B.products(in: json(searchJSON))
check(products.count == 13, "every product with a slug and a name is read, the nameless one not (\(products.count))")
func product(_ id: String) -> B.Product { products.first { $0.id == id }! }
check(product("amazon_com-usa").countries == ["US", "PR"] && product("amazon_com-usa").currency == "USD", "the measured fields are read")
check(product("netflix-usa").inStock == false && !product("netflix-usa").buyable, "out of stock is not buyable")
check(!product("bitrefill-esim-europe").buyable, "an eSIM is not offered yet")
check(product("atandt-usa").buyable && product("atandt-usa").noun == "top-up", "a top-up is a top-up")

// ── The fold: Bitrefill's slugs → seven, never Casberi's categories ─────────
let folds: [(String, B.Group)] = [
    ("amazon_com-usa", .shopping), ("apple-usa", .shopping), ("virtual-prepaid-visa-usa", .money), ("openai-usa", .money),
    ("doordash-usa", .food), ("uber-eats-usa", .food), ("uber-usa", .travel), ("airbnb-usa", .travel),
    ("steam-usa", .games), ("stubhub-usa", .entertainment), ("netflix-usa", .entertainment),
    ("atandt-usa", .phone), ("bitrefill-esim-europe", .phone)
]
for (id, g) in folds { check(B.group(of: product(id)) == g, "\(id) stands in \(g) (got \(B.group(of: product(id))))") }
check(B.Group.allCases.count == 7, "seven groups")
check(Set(B.slugGroups.values).count == 7, "every group has a slug")
let measuredSlugs = ["food","restaurants","apparel","games","entertainment","travel","in-game-currencies","home","experiences","accommodation","game-stores","food-delivery","sports-n-outdoors","department-stores","streaming","vpn","groceries","health-beauty","multi-brand","kids","gifts","electronics","gasoline","flights","cruises","literature","car-rental","transportation","pets","bitcoin","cosmetics","online-travel-agencies","spa","payment-cards","online-marketplaces","bus","train","pharmacy","natural-herbal-care","voip"]
let unplaced = measuredSlugs.filter { B.slugGroups[$0] == nil }
check(unplaced.isEmpty, "every measured slug is placed (\(unplaced))")
let travel = B.products(in: .travel, of: products + products)
check(travel.map(\.id) == ["uber-usa", "airbnb-usa"], "a group lists its products in Bitrefill's order, each once (\(travel.map(\.id)))")
check(B.search("ube", in: products).map(\.id) == ["uber-eats-usa", "uber-usa"], "typing narrows, prefix first (\(B.search("ube", in: products).map(\.id)))")
check(B.search("eats", in: products).map(\.id) == ["uber-eats-usa"], "a word inside a name is found")

// ── Names ──────────────────────────────────────────────────────────────────
check(B.shortName("Amazon.com USA") == "Amazon.com", "the country Bitrefill appends is not the name")
check(B.shortName("Steam USD") == "Steam" && B.shortName("G2A Digital Marketplace International") == "G2A Digital Marketplace", "USD and International go too")
check(B.stem("Amazon.com") == "amazon" && B.stem("Amazon.com USA") == "amazon", "the stem drops the suffix and the country")
check(B.stem("SQ *Delta Air Lines") == "delta air lines" && B.stem("Uber Eats US") == "uber eats", "a card descriptor's prefix goes")
let spend = B.whereYouSpend(["Amazon", "Uber Eats", "Netflix.com", "Nowhere Café", "Uber", "Amazon.com"], in: products)
check(spend.map(\.id) == ["amazon_com-usa", "uber-eats-usa", "uber-usa"], "Where you spend matches by name, each once, never a card out of stock (\(spend.map(\.id)))")
check(B.whereYouSpend(["Ub"], in: products).isEmpty, "two letters match nothing")

// ── The detail: priced packages ────────────────────────────────────────────
let detailJSON = """
{"id":"amazon_com-usa","name":"Amazon.com USA","country_code":"US","currency":"USD","categories":["online-marketplaces"],"recipient_type":"none","in_stock":true,
 "packages":[{"package_value":"1000","package_currency":"USD","payment_price":"1029.33","payment_currency":"USD"},{"package_value":"50","package_currency":"USD","payment_price":"52.50","payment_currency":"USD"},{"package_value":"5","package_currency":"USD","payment_price":"5.25","payment_currency":"USD"},{"package_value":"7.5","package_currency":"USD","payment_price":"7.9","payment_currency":"USD"}]}
"""
var amazon = B.Product.parse(json(detailJSON) as! [String: Any])!
check(amazon.id == "amazon_com-usa" && amazon.countries == ["US"], "a detail parses as a product too")
check(amazon.packages.map(\.value) == [5, 7.5, 50, 1000], "packages smallest first (\(amazon.packages.map(\.value)))")
check(amazon.package(for: 50)?.price == 52.50, "the price is what you pay, the value what the card is worth")
check(amazon.refusal(50) == nil && amazon.refusal(7) != nil && amazon.refusal(0) == "Type an amount first", "an amount it does not sell is refused with a reason")
check(amazon.suggestedValue == 50, "the sentence opens on $50 where it is sold")
check(B.Product.valueText(50) == "50" && B.Product.valueText(7.5) == "7.5", "the invoice names the value exactly")
check(amazon.denominationsLine == "$5 · $7.50 · $50 · $1,000", "the line says the values (\(amazon.denominationsLine))")
check(!amazon.needsPhoneNumber, "a gift card needs no phone")
var att = product("atandt-usa"); att.recipientType = "phone_number"
check(att.needsPhoneNumber, "a top-up names the phone")
let body = B.createBody(product: amazon, value: 50)
check((body["items"] as? [[String: Any]])?.first?["product_id"] as? String == "amazon_com-usa"
      && (body["items"] as? [[String: Any]])?.first?["package_value"] as? String == "50", "create names the slug and the exact value")
let topUp = B.createBody(product: att, value: 20, phone: "+15551234567")
check((topUp["items"] as? [[String: Any]])?.first?["refill_input"] as? String == "+15551234567", "a top-up carries the number")

// ── Sign-in: the measured challenge, message and header ────────────────────
let challengeJSON = """
{"x402Version":2,"error":"Payment required","accepts":[],"extensions":{"sign-in-with-x":{"info":{"domain":"api.bitrefill.com","uri":"https://api.bitrefill.com/x402/connect","version":"1","nonce":"a25f360a5d6f84a7c42a898dce1d3655","issuedAt":"2026-10-23T02:06:53.117Z","resources":["https://api.bitrefill.com/x402/connect"],"expirationTime":"2026-10-23T02:11:53.117Z","statement":"Sign in to Bitrefill to access your orders and gift card codes. Sign this message with the same wallet that paid the invoice (no account or password needed)."},"supportedChains":[{"chainId":"eip155:8453","type":"eip191"}]}}}
"""
let challenge = B.SignInChallenge.parse(json(challengeJSON))!
let address = "0xC7909699cD7537C8F33AcF3d304720d4882262d2"
let expectedMessage = """
api.bitrefill.com wants you to sign in with your Ethereum account:
0xC7909699cD7537C8F33AcF3d304720d4882262d2

Sign in to Bitrefill to access your orders and gift card codes. Sign this message with the same wallet that paid the invoice (no account or password needed).

URI: https://api.bitrefill.com/x402/connect
Version: 1
Chain ID: 8453
Nonce: a25f360a5d6f84a7c42a898dce1d3655
Issued At: 2026-10-23T02:06:53.117Z
Expiration Time: 2026-10-23T02:11:53.117Z
Resources:
- https://api.bitrefill.com/x402/connect
"""
check(challenge.message(address: address, chainId: 8453) == expectedMessage, "the sign-in message is the one the server took, byte for byte")
let sig: [UInt8] = [0xab, 0xcd]
let header = challenge.header(address: address, chainId: 8453, signature: sig)!
let decoded = json(String(data: Data(base64Encoded: header)!, encoding: .utf8)!) as! [String: Any]
check(decoded["chainId"] as? String == "eip155:8453", "the header's chain is CAIP-2 (the bare number was refused)")
check(decoded["type"] as? String == "eip191" && decoded["signature"] as? String == "0xabcd", "type and signature")
check(decoded["statement"] as? String == challenge.statement && decoded["expirationTime"] as? String == "2026-10-23T02:11:53.117Z"
      && (decoded["resources"] as? [String]) == ["https://api.bitrefill.com/x402/connect"], "the statement, the expiry and the resources ride the header")
check(decoded["address"] as? String == address && decoded["nonce"] as? String == challenge.nonce, "address and nonce")
check(B.SignInChallenge.parse(json("{\"x402Version\":2}")) == nil, "no challenge, no sign-in")
let session = B.Session.parse(json("{\"token\":\"eyJ\",\"token_header\":\"X-Access-Token\",\"expires_in\":7200}"), now: Date(timeIntervalSince1970: 0))!
check(session.header == "X-Access-Token" && session.expires == Date(timeIntervalSince1970: 7200) && !session.live, "a session knows its header and its end")

// ── The invoice, as measured ───────────────────────────────────────────────
let invoice = B.Invoice.parse(json("""
{"invoice_id":"f6d5eff4-e42b-4403-806d-83737b04a10d","price_usdc":"5250000","price_usd":5.25,"price_satoshi":6467,"networks":["eip155:8453"],"expires_in_minutes":30}
"""))!
check(invoice.priceUnits == "5250000" && invoice.priceUSD == 5.25 && invoice.expiresMinutes == 30, "the invoice's price in USDC units and dollars")
check(invoice.body["invoice_id"] as? String == invoice.id, "pay names the invoice")
check(B.Invoice.parse(json("{\"price_usdc\":\"1\"}")) == nil, "no id, no invoice")

// ── The payment challenge, as measured ─────────────────────────────────────
let payJSON = """
{"x402Version":2,"error":"Payment required","resource":{"url":"https://api.bitrefill.com/x402/invoice/pay","description":"Pay","mimeType":"application/json"},
 "accepts":[
  {"scheme":"upto","network":"eip155:8453","amount":"1000000000","asset":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","payTo":"0x480CD46E6faDe651a0437DeaddA53D5c8e7D846A","maxTimeoutSeconds":1800,"extra":{"name":"USD Coin","version":"2"}},
  {"scheme":"exact","network":"eip155:137","amount":"5250000","asset":"0x3c499c542cef5e3811e1192ce70d8cc03d5c3359","payTo":"0x480CD46E6faDe651a0437DeaddA53D5c8e7D846A","maxTimeoutSeconds":1800,"extra":{"name":"USD Coin","version":"2"}},
  {"scheme":"exact","network":"eip155:8453","amount":"5250000","asset":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","payTo":"0x480CD46E6faDe651a0437DeaddA53D5c8e7D846A","maxTimeoutSeconds":1800,"extra":{"name":"USD Coin","version":"2"}},
  {"scheme":"exact","network":"solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp","amount":"5250000","asset":"EPjF","payTo":"5yAS","maxTimeoutSeconds":1800,"extra":{"feePayer":"BENr"}}],
 "extensions":{"builder-code":{"info":{"a":"bc_suil8bdj"}}}}
"""
let pay = json(payJSON)
let usdcBase = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
let requirement = B.Requirement.payable(in: pay, chainId: 8453, asset: usdcBase.lowercased())!
check(requirement.scheme == "exact" && requirement.network == "eip155:8453" && requirement.chainId == 8453 && requirement.amount == "5250000"
      && requirement.payTo == "0x480CD46E6faDe651a0437DeaddA53D5c8e7D846A" && requirement.maxTimeoutSeconds == 1800
      && requirement.name == "USD Coin" && requirement.version == "2", "the Base USDC requirement, exactly as offered")
check(B.Requirement.payable(in: pay, chainId: 1, asset: usdcBase) == nil, "nothing payable on a network not offered")
check(B.Requirement.all(in: pay).count == 4, "every requirement is read, Solana's and the upto one included")

let nonce = [UInt8](repeating: 0x11, count: 32)
let now = Date(timeIntervalSince1970: 1_792_721_250)
let auth = B.Authorization.make(from: "0x4F673302Fb21b0C6aC5423897dB6375Fb9443DFB", requirement: requirement, now: now, nonce: nonce)
check(auth.validAfter == "0" && auth.validBefore == "1792723050" && auth.value == "5250000" && auth.to == requirement.payTo, "the authorization: now plus the timeout, the exact amount, to Bitrefill")
check(auth.nonce == "0x" + String(repeating: "11", count: 32), "a 32-byte nonce, hex")
let td = EIP712.parse(auth.typedData(requirement: requirement))!
check(td.primaryType == "TransferWithAuthorization", "the primary type")
check(EIP712.typeHash("TransferWithAuthorization", types: td.types).map { SafeABI.hex($0) } == "0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267",
      "the typehash is USDC's own TRANSFER_WITH_AUTHORIZATION_TYPEHASH")
check(EIP712.digest(td) != nil && EIP712.digest(td)!.count == 32, "the digest is 32 bytes")
// The domain under which USDC on Base checks the signature: "USD Coin", "2", 8453, the token.
let dom = td.domain
check(EIP712.numberText(dom["chainId"]!) == "8453", "the domain's chain is Base (\(String(describing: dom["chainId"])))")
let payHeader = B.paymentHeader(requirement: requirement, authorization: auth, signature: [0x01, 0x02], challenge: pay)!
let payDecoded = json(String(data: Data(base64Encoded: payHeader)!, encoding: .utf8)!) as! [String: Any]
check(payDecoded["x402Version"] as? Int == 2, "x402 version 2")
let accepted = payDecoded["accepted"] as! [String: Any]
check(accepted["scheme"] as? String == "exact" && accepted["network"] as? String == "eip155:8453" && accepted["amount"] as? String == "5250000"
      && accepted["maxTimeoutSeconds"] as? Int == 1800 && (accepted["extra"] as? [String: Any])?["name"] as? String == "USD Coin",
      "the requirement is echoed as it came")
let payload = payDecoded["payload"] as! [String: Any]
check(payload["signature"] as? String == "0x0102", "the signature, hex")
let authJSON = payload["authorization"] as! [String: Any]
check(authJSON["from"] as? String == auth.from && authJSON["validBefore"] as? String == "1792723050" && authJSON["nonce"] as? String == auth.nonce, "the authorization's fields are decimal strings and hex")
check((payDecoded["resource"] as? [String: Any])?["url"] as? String == "https://api.bitrefill.com/x402/invoice/pay", "the resource is echoed")
check(((payDecoded["extensions"] as? [String: Any])?["builder-code"] as? [String: Any]) != nil, "the extensions are echoed")
check(B.paymentAccepted(json("{\"accepted\":true}")) && B.paymentAccepted(json("{\"success\":true,\"status\":\"payment_confirmed\"}")) && !B.paymentAccepted(json("{\"error\":\"x\"}")), "a payment taken, either way it is said")
check(B.refusal(json("{\"error_code\":\"INVOICE_NOT_PAYABLE\",\"agent_instructions\":\"Request could not be completed; see error_code.\"}"), status: 403) == "Request could not be completed; see error_code.", "a refusal in Bitrefill's words")
check(B.refusal(json("{\"error\":\"Payment required\"}"), status: 402) == "Bitrefill refused (402)", "a bare 402 is not a reason")

// ── The order ──────────────────────────────────────────────────────────────
let delivered = B.Standing.parse(json("""
{"invoice_id":"f6d5","status":"complete","delivery_status":"all_delivered","redemption_info":{"orders":[{"redemption_info":{"code":"ABCD-EFGH","pin":"1234"}}]}}
"""))!
check(delivered.delivered && !delivered.failed && delivered.redemption?.code == "ABCD-EFGH" && delivered.redemption?.pin == "1234", "the status route's nested orders, read")
let flat = B.Standing.parse(json("{\"orders\":[{\"id\":\"o1\",\"status\":\"delivered\",\"redemption_info\":{\"link\":\"https://redeem\"}}]}"))!
check(flat.delivered && flat.redemption?.link == "https://redeem", "orders at the root, read")
let waiting = B.Standing.parse(json("{\"status\":\"payment_confirmed\",\"delivery_status\":\"pending\"}"))!
check(!waiting.delivered && !waiting.failed && waiting.redemption == nil, "not yet")
let failed = B.Standing.parse(json("{\"status\":\"complete\",\"delivery_status\":\"failed\"}"))!
check(failed.failed, "a failed delivery is said")
let mine = B.Standing.parse(orders: json("{\"orders\":[{\"invoice_id\":\"other\",\"status\":\"delivered\"},{\"invoice_id\":\"f6d5\",\"status\":\"delivered\",\"redemption_info\":{\"code\":\"Z\"}}]}"), invoiceID: "f6d5")!
check(mine.delivered && mine.redemption?.code == "Z", "my/orders picks this invoice's row")
check(B.Standing.parse(orders: json("{\"orders\":[]}"), invoiceID: "f6d5") == nil, "no row, no standing")
check(B.Redemption.parse(["code": "  "]) == nil, "blank is nothing")
check(B.orderID(ref: B.ref(invoiceID: "f6d5")) == "f6d5" && B.orderID(ref: "bitrefill:invoice:1") == nil, "the ref round-trips in the §103 shape")
check(B.faceWords(spoken: "52.5", value: "$50", product: amazon) == "Pay 52.5 USDC to Bitrefill for a $50 Amazon.com gift card", "what Face ID says")
check(B.money(52.5, currency: "USD") == "$52.50" && B.money(50, currency: "USD") == "$50", "money, whole without cents")

if failures > 0 { print("✗ \(failures) failures"); exit(1) }
print("✓ bitrefill-buy-selftest: the fold, the sign-in, the invoice, the authorization, the order")
SWIFT

compile() { xcrun swiftc -O "$1" "$TX" "$KECCAK" "$CLEARSIGN" "$TYPED" "$work/main.swift" -o "$2" 2>"$work/err.txt"; }
compile "$SRC" "$work/t" || { cat "$work/err.txt" | head -40; fail "did not compile"; }
"$work/t" || fail "the self-test failed"

# ── Mutations: a drift that compiles and looks right ───────────────────────
mutate() {
  local expr="$1" why="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  compile "$work/m.swift" "$work/m" || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
}
mutate 's/"transportation": \.travel/"transportation": .shopping/' "Uber folded into Shopping"
mutate 's/"chainId": "eip155:\\\(chainId\)"/"chainId": String(chainId)/' "the header's chain as a bare number, which the server refuses"
mutate 's/validAfter: "0",/validAfter: "1",/' "an authorization valid from 1"
mutate 's/if let extensions = root\["extensions"\] \{ payload\["extensions"\] = extensions \}//' "the extensions not echoed"
mutate 's/\$0\.scheme == "exact" && \$0\.chainId == chainId/\$0.chainId == chainId/' "a requirement of another scheme taken"
mutate 's/if let statement, !statement\.isEmpty \{ lines \+= \[statement, ""\] \}//' "the statement left out of the message"
mutate 's/\.sorted \{ \$0\.value < \$1\.value \}//' "packages in the server's order"

# ── Reachability: the words are wired (a guard asserts the USE) ────────────
grep -q 'case .buy: buyClauses' "$MOVE" || fail "Move's sentence has no Buy clauses"
grep -q 'Verb.allCases.filter { \$0 != .buy || buyAvailable }' "$MOVE" || fail "Buy is drawn with no account (§83)"
grep -q 'if verb == .buy { buyNow(); return }' "$MOVE" || fail "the foot's verb does not buy"
grep -q 'BitrefillCodeRows(thing: thing)' "$SHEET" || fail "the sheet draws no code rows"
grep -q 'paid\["PAYMENT-SIGNATURE"\] = header' "$X402" || fail "the payment is not sent in PAYMENT-SIGNATURE"
grep -q '"SIGN-IN-WITH-X": header' "$X402" || fail "the sign-in is not sent in SIGN-IN-WITH-X"
grep -q 'YourAccountMessage.signTypedData' "$X402" || fail "the authorization is not signed by the account"
grep -q 'SafeWebAuthn.isMagic(answer)' "$MESSAGE" || fail "a message signature leaves the phone unchecked"
grep -q 'redemption_info.*NEVER read here' "$BRIDGE" || fail "the keyed seat's rule on codes is gone"
grep -q 'x402Version": 2' "$SRC" || fail "x402 version 2"
print "✓ bitrefill-buy-selftest: mutations caught, the words are wired"
