#!/bin/zsh
# Casberi limit-order self-test (2026-11-02, prd §1673):
#
#   Casberi/Casberi/Model/YourAccountOrder.swift
#     — uid / order / appDataHash  (the id CoW's own API answered, §1430)
#     — calls / cancelCalls        (wrap exactly, approve exactly, pre-sign, withdraw)
#     — buyUnits / Decimal / price (the price arithmetic, digit by digit)
#     — offersWhen / priced        (where the sentence ends "when", and of which token)
#
# Every failure below is the person pre-signing an order that is not the one
# the sentence said: another id, an approval wider than the amount, a price
# that rounds up, or "when" drawn where CoW cannot fill.
set -euo pipefail
cd "$(dirname "$0")/.."

ORDER="Casberi/Casberi/Model/YourAccountOrder.swift"
ACCOUNT="Casberi/Casberi/Model/YourAccount.swift"
OP="Casberi/Casberi/Model/YourAccountOp.swift"
SWAP="Casberi/Casberi/Model/YourAccountSwap.swift"
ACROSS="Casberi/Casberi/Model/YourAccountAcross.swift"
ADAPTER="Casberi/Casberi/Model/YourAccount7579.swift"
COW="Casberi/Casberi/Model/CowOrder.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
WEBAUTHN="Casberi/Casberi/Model/SafeWebAuthnSignature.swift"
TYPED="Casberi/Casberi/Model/SafeTypedData.swift"
ROUNDUPS="Casberi/Casberi/Model/RoundUps.swift"
CHAIN="Casberi/Casberi/Model/YourAccountChain+Order.swift"
MOVE="Casberi/Casberi/Screens/MoveSentence.swift"
for f in "$ORDER" "$ACCOUNT" "$OP" "$SWAP" "$ACROSS" "$ADAPTER" "$COW" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" "$CHAIN" "$MOVE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# The wiring: CoW must name the order back before anything is signed, the
# order goes through the simulated path, and the host is declared.
grep -q 'guard let said = json as? String, SafeABI.hexBytes(said) == uid else' "$CHAIN" \
  || { echo "✗ an order is signed without CoW naming back the id this phone computed"; exit 1; }
grep -q 'let sent = try await privateCalls(calls, on: net, reason: reason, stage: stage)' "$CHAIN" \
  || { echo "✗ the order no longer goes through the simulated path (privateCalls)"; exit 1; }
awk '/service: "Your account"/,/throughTor/' Casberi/Casberi/Model/NetworkReach.swift | grep -q '"api.cow.fi"' \
  || { echo "✗ api.cow.fi is not declared under Your account"; exit 1; }
# The sentence ends "now." at rest, whole and signable, until a price is
# picked (prd §1683, retiring §1673 item 2's "Pick when"); a price places a
# CoW order.
grep -q 'return whenFor == limitPair ? (whenPick ?? .now) : .now' "$MOVE" \
  || { echo "✗ \"when\" no longer answers Now at rest (prd §1683)"; exit 1; }
! grep -q 'Pick when' "$MOVE" || { echo "✗ the foot waits on \"when\" again (prd §1683)"; exit 1; }
grep -q 'if limiting { placeOrder(); return }' "$MOVE" \
  || { echo "✗ sign() no longer places a priced order"; exit 1; }
# The presets and the unit (prd §1683).
grep -q 'static let whenPresets = \[5, 10, 25\]' "$MOVE" \
  || { echo "✗ the presets are no longer +5% +10% +25% (prd §1683)"; exit 1; }
grep -q 'unitChip("%", on: priceInPercent' "$MOVE" && grep -q 'unitChip("\$", on: !priceInPercent' "$MOVE" \
  || { echo "✗ the list no longer offers % and $ (prd §1683)"; exit 1; }

# At rest the sentence says nothing of when (prd §1754): the ledger's When
# row is the door, there before the tokens are picked (prd §1673d), and the
# clause is drawn once a price is picked.
grep -q 'if whenSpoken { whenClause }' "$MOVE" && grep -q 'return with == nil || buy == nil' "$MOVE" \
  && grep -q 'LedgerRow(id: "choicewhen", name: Self.rowName(.when, verb: verb),' "$MOVE" \
  || { echo "✗ \"when\" waits for the bought token again (prd §1673d)"; exit 1; }

grep -q 'priceWords: Self.priceWords(v, places: p.places), seconds: orderSeconds)' "$MOVE" \
  || { echo "✗ the order no longer waits as long as Until says"; exit 1; }

TMP=$(mktemp -d /tmp/limit-order-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/stub.swift" <<'SWIFT'
enum YourAccountDemo {
    static var isOn: Bool { false }
    static var roundUps: RoundUps.Setting { RoundUps.Setting() }
}
enum PrivateMainnet { static let on = true }
enum YourAccountKey { static var address: String? { nil } }
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
typealias Op = YourAccountOp
typealias O = YourAccountOrder
var bad = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("✗ " + what); bad += 1 } }
let base = Op.base, usdc = Op.dollar(on: Op.base), eth = Op.eth
let aero = Op.Token(symbol: "AERO", decimals: 18, contract: "0x940181a94a35a4569e4529a3cdfb74e38fd98631")
let usdt = Op.Token(symbol: "USDT", decimals: 6, contract: "0xfde4c96c8593536e31f229ea8f37b2ada2699bb2")
func d(_ s: String, signed: Bool = false) -> O.Decimal { O.Decimal.parse(s, signed: signed)! }

// The id (prd §1430): the order CoW's API accepted on Base on 2026-10-19,
// rebuilt here from its terms, must hash to the id CoW answered.
let owner = "0xb91a38aA11C903bf5A465326b9c0cf8680F43416"
let order = O.order(sell: eth, buy: usdc, on: base, account: owner,
                    sellUnits: "200000000000000", buyUnits: "474309", validTo: 1792457394)!
let uid = O.uid(order, owner: owner, chainId: 8453)!
check(SafeABI.hex(uid) == "0x32fa77466b4b4845779d6546e6d5a61cec74725646d688962d71c16db94ab24cb91a38aa11c903bf5a465326b9c0cf8680f434166ad6bab2",
      "the order's id is not the one CoW's API answered for it")
check(SafeABI.hex(O.appDataHash) == "0x868db1f7ba62a9708787a6ce366c687ddc6a32e22b6722aebbc0e8bd0c00da59", "the app data hash is not CoW's")
check(!order.partiallyFillable && order.kind == "sell" && Op.decimal(order.feeAmount) == "0", "the order is not all-or-nothing, sell, no fee")
let body = O.orderBody(order, owner: owner)
check(body["signingScheme"] as? String == "presign" && body["sellAmount"] as? String == "200000000000000"
      && body["buyAmount"] as? String == "474309" && body["receiver"] as? String == owner.lowercased(),
      "the body CoW is told is not the order hashed")

// The calls: wrap exactly, approve exactly to the vault relayer, pre-sign.
let calls = O.calls(order: order, uid: uid, sellingETH: true, network: base)!
check(calls.count == 3, "selling ETH is wrap, approve, pre-sign")
check(calls[0].to == O.weth(chainId: 8453)! && calls[0].value == "200000000000000"
      && calls[0].data == SafeABI.hex(YourAccount.sel("deposit()")), "the wrap is not exactly what is sold")
check(calls[1].to.lowercased() == O.weth(chainId: 8453)!.lowercased() && calls[1].value == "0"
      && calls[1].data == SafeABI.hex(YourAccount.sel("approve(address,uint256)") + YourAccount.w(O.vaultRelayer) + order.sellAmount),
      "the approval is not exactly what is sold, to CoW's vault relayer only")
check(calls[2].to == CowOrder.settlement && CowOrder.preSignature(SafeABI.hexBytes(calls[2].data)!).map { $0.uid == uid && $0.signed } == true,
      "the pre-signature is not setPreSignature(uid, true) on the settlement contract")
let tokenOrder = O.order(sell: usdc, buy: eth, on: base, account: owner, sellUnits: "1000000", buyUnits: "1", validTo: 1792457394)!
check(O.calls(order: tokenOrder, uid: O.uid(tokenOrder, owner: owner, chainId: 8453)!, sellingETH: false, network: base)!.count == 2,
      "selling a token wraps nothing")
check(O.calls(order: tokenOrder, uid: uid, sellingETH: true, network: base) == nil, "a wrap was written for an order that does not sell WETH")
check(O.calls(order: order, uid: Array(uid.prefix(55)), sellingETH: true, network: base) == nil, "a malformed id was pre-signed")
let cancel = O.cancelCalls(uid: uid)!
check(cancel.count == 1 && cancel[0].to == CowOrder.settlement
      && cancel[0].data == SafeABI.hex(YourAccount.sel("invalidateOrder(bytes)") + YourAccount.w(32) + YourAccount.dynamic(uid)),
      "cancel is not invalidateOrder(uid) on the settlement")

// The price, digit by digit, always rounded down (the order asks at least).
check(O.buyUnits(sellUnits: "1000000000000000000", sell: eth, buy: usdc, on: base, price: d("2400")) == "2400000000", "1 ETH at $2,400 is 2,400 USDC")
check(O.buyUnits(sellUnits: "500000000000000000", sell: eth, buy: usdc, on: base, price: d("2,400.50")) == "1200250000", "0.5 ETH at $2,400.50")
check(O.buyUnits(sellUnits: "2400000000", sell: usdc, buy: eth, on: base, price: d("2400")) == "1000000000000000000", "2,400 USDC at $2,400 is 1 ETH")
check(O.buyUnits(sellUnits: "1000000", sell: usdc, buy: eth, on: base, price: d("3")) == "333333333333333333", "a third rounds down")
check(O.buyUnits(sellUnits: "1000000000000000000", sell: eth, buy: aero, on: base, price: d("0.5"), sellDollars: 2000)
      == "4000000000000000000000", "1 ETH ($2,000) for AERO at $0.50 is 4,000 AERO")
check(O.buyUnits(sellUnits: "1000000000000000000", sell: eth, buy: aero, on: base, price: d("0.5")) == nil,
      "neither a dollar, no rate for the sold token, and a price was still made")
check(O.buyUnits(sellUnits: "1000000000000000000", sell: eth, buy: usdc, on: base, price: d("0")) == nil, "a zero price made an order")
check(O.buyUnits(sellUnits: "1", sell: eth, buy: usdc, on: base, price: d("2400")) == nil, "an order for nothing back was made")
check(O.times("123456789012345678901234567890", "987654321") == "121932631124828532112482853211126352690", "multiplication")
check(O.divided("1000000000000000000000", by: 7) == "142857142857142857142", "division")
check(O.shiftDown("123", 5) == "0" && O.shiftDown("123456", 2) == "1234", "shifting down")

// What is typed.
check(d("2,400.50") == O.Decimal(digits: "240050", places: 2, negative: false), "2,400.50 parses")
check(d("-3.5", signed: true).negative && O.Decimal.parse("-3.5") == nil, "a sign only where a percent may fall")
check(O.Decimal.parse("1.2.3") == nil && O.Decimal.parse("abc") == nil && O.Decimal.parse(".") == nil, "garbage parses")
check(O.price(percent: d("10"), from: 2000) == d("2200.00"), "+10% of $2,000 is $2,200")
check(O.price(percent: d("-5", signed: true), from: 0.8) == d("0.7600"), "−5% of $0.80 keeps four places")
check(O.price(percent: d("-100", signed: true), from: 2000) == nil, "−100% made a price")
check(O.percentWords(2136, from: 2000) == "+6.8%" && O.percentWords(1938, from: 2000) == "−3.1%", "the percent words")

// Where "when" is drawn, and of which token.
check(O.offersWhen(sell: eth, buy: usdc, from: base, to: base), "ETH for USDC on Base ends when")
check(O.offersWhen(sell: usdc, buy: eth, from: Op.ethereum, to: Op.ethereum), "USDC for ETH on Ethereum ends when")
check(!O.offersWhen(sell: eth, buy: usdc, from: base, to: Op.ethereum), "a swap to another network was offered when (CoW fills on one)")
check(!O.offersWhen(sell: eth, buy: Op.dollar(on: Op.robinhood), from: Op.robinhood, to: Op.robinhood), "when was offered where CoW does not settle")
check(!O.offersWhen(sell: usdc, buy: usdt, from: base, to: base), "a dollar for a dollar was offered a price")
check(O.priced(sell: eth, buy: usdc, on: base) == eth && O.priced(sell: usdc, buy: aero, on: base) == aero
      && O.priced(sell: eth, buy: aero, on: base) == aero, "the price is not of the token that is not a dollar (else the one bought)")

// How long it waits: a day, a week, a month, a week by default.
check(O.expiries == [86_400, 604_800, 2_592_000] && O.expiries.contains(O.defaultSeconds), "the expiries are not a day, a week and a month, with the week the default")

if bad > 0 { print("✗ \(bad) limit-order check(s) failed"); exit(1) }
print("✓ limit orders: the id CoW answered, exact calls, prices rounded down, when only where CoW fills")
SWIFT

xcrun swiftc -O -o "$TMP/t" "Casberi/Shared/AddressTail.swift" "$ORDER" "$ACCOUNT" "$OP" "$SWAP" "$ACROSS" "$ADAPTER" "$COW" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" "$TMP/stub.swift" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ YourAccountOrder.swift does not compile alone"; exit 1; }
"$TMP/t"
