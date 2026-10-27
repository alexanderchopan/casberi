#!/bin/zsh
# Across self-test (prd §1555) — Move's swap to another network: the phone
# asks Across only its fee and writes the SpokePool deposit itself.
#
#   Casberi/Casberi/Model/YourAccountAcross.swift   compiled WHOLE and unmodified
#
# The failures that cost money, each one silent until it signs:
#
#   • A DEPOSIT INTO A CONTRACT NOBODY PINNED, or an approval to one: the
#     account's tokens go to whoever is at that address.
#   • THE WRONG DEPOSITOR: a refund (a deposit nobody fills) goes back to the
#     depositor, so anyone else there keeps the money.
#   • THE WRONG RECIPIENT, or ETH sent straight to the account: a SpokePool
#     pays a contract WETH, never ETH, so ETH goes to Across's handler with a
#     message that unwraps exactly what is filled and pays the account.
#   • A MESSAGE THAT PAYS SOMEONE ELSE, or names another fallback.
#   • ACROSS'S TERMS TAKEN ON FAITH: an output over the input, a fee over 5%,
#     a deadline past six hours, an exclusive relayer without a deadline.
#   • THE CALLDATA ITSELF. Every vector in `fixtures/across-swap/vectors.json`
#     was written by an independent encoder and SIMULATED in eth_simulateV1
#     on its sending network, every call succeeding; the ETH message was run
#     on each receiving network and paid a contract account exactly the fill.
#   • THE FILL GUESSED: the relay hash must equal the destination SpokePool's
#     own `getV3RelayHash` for two real Base deposits, and `fillStatuses`'s
#     answers must read as they mean.
#   • THE WALLET'S ONE ROW: the sending transaction, the arrival (exactly the
#     amount, this wallet, this network, in its window) and the refund (from
#     the SpokePool, after the deadline) are the crossing's, and nothing else.
#   • A SWAP ON THE RECEIVING NETWORK (prd §1565) that pays someone else,
#     names another fallback, takes a looser minimum than the network's
#     slippage, goes through a router of another network, or carries the
#     fee question's message. Every vector in `fixtures/across-swap/
#     arrival.json` was written by an independent encoder, its deposit
#     simulated on the sending network, its message run on the receiving one
#     as a fill runs it (the swap paid the account its quote), and run again
#     with a minimum no pool can pay (the handler paid the account the
#     bridged token, whole: the fallback).
#   • A CROSSING FROM ANOTHER DEVICE AS TWO ROWS: real Across deposits on
#     Base and their fills on Ethereum and Robinhood (`fixtures/across-swap/
#     chain-pairs.json`, read off the public nodes) must fold into one
#     crossing from the chain alone — the deposit's own log, the receiving
#     pool's FilledRelay for that deposit id — and nothing else may.
#
# Pure, local, deterministic — no network, no simulator, no key. Then every
# guard is proven to catch something: each mutation below breaks the shipped
# source one way, and the harness must fail.
set -euo pipefail
cd "$(dirname "$0")/.."

ACROSS="Casberi/Casberi/Model/YourAccountAcross.swift"
SWAP="Casberi/Casberi/Model/YourAccountSwap.swift"
ACCOUNT="Casberi/Casberi/Model/YourAccount.swift"
OP="Casberi/Casberi/Model/YourAccountOp.swift"
ADAPTER="Casberi/Casberi/Model/YourAccount7579.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
WEBAUTHN="Casberi/Casberi/Model/SafeWebAuthnSignature.swift"
TYPED="Casberi/Casberi/Model/SafeTypedData.swift"
ROUNDUPS="Casberi/Casberi/Model/RoundUps.swift"
INGEST="Casberi/Casberi/Model/WalletIngest.swift"
CHAIN="Casberi/Casberi/Model/YourAccountChain.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
FIXTURES="$PWD/scripts/fixtures/across-swap"
for f in "$ACROSS" "$SWAP" "$ACCOUNT" "$OP" "$ADAPTER" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" \
         "$INGEST" "$CHAIN" "$REACH" "$FIXTURES/vectors.json" \
         "$FIXTURES/arrival.json" "$FIXTURES/chain-pairs.json"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/across-swap-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/demo-stub.swift" <<'SWIFT'
enum YourAccountDemo {
    static var isOn: Bool { false }
    static var roundUps: RoundUps.Setting { RoundUps.Setting() }
}
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
typealias X = YourAccountAcross
var bad = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ " + what); bad += 1 } }
let dir = ProcessInfo.processInfo.environment["FIXTURES"]!
let fixture = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/vectors.json"))) as! [String: Any]
let account = fixture["account"] as! String
let names = [1: "Ethereum", 8453: "Base", 4663: "Robinhood"]

// ── The pins ────────────────────────────────────────────────────────────────
check(X.spokes == [1: "0x5c7bcd6e7de5423a257d81b442095a1a6ced35c5", 8453: "0x09aea4b2242abc8bb4bb78d537a67a245a7bec64",
                   4663: "0xd29c85f15df544ba632c9e25829fd29d767d7978"], "a SpokePool address moved")
check(X.handler == "0x0f7ae28de1c8532170ad4ee566b5801485c13a0e", "the handler address moved")
check(X.maxFeeBps == 500 && X.maxDeadlineSeconds == 21_600, "the fee cap or the deadline cap moved")
for a in [X.Asset.eth, .dollar] {
    for f in [1, 8453, 4663] { for t in [1, 8453, 4663] {
        check(X.carries(a, from: f, to: t) == (f != t), "\(a) \(f)→\(t) carried wrongly")
    } }
    check(!X.carries(a, from: 8453, to: 10), "a network the account is not on is carried")
}
check(X.asset(of: YourAccountOp.eth, on: YourAccountOp.base) == .eth
      && X.asset(of: YourAccountOp.dollar(on: YourAccountOp.base), on: YourAccountOp.base) == .dollar
      && X.asset(of: YourAccountOp.dollar(on: YourAccountOp.base), on: YourAccountOp.ethereum) == nil
      && X.asset(of: YourAccountOp.Token(symbol: "AERO", decimals: 18, contract: "0x940181a94a35a4569e4529a3cdfb74e38fd98631"), on: YourAccountOp.base) == nil,
      "what crosses is not exactly ETH and the network's own dollar")
check(X.token(.dollar, on: YourAccountOp.robinhood).symbol == "USDG", "USDC does not arrive on Robinhood as USDG")

// ── The vectors: byte for byte, and the check takes them ──────────────────
func call(_ o: [String: Any]) -> YourAccountSwap.Call {
    YourAccountSwap.Call(to: o["to"] as! String, value: o["value"] as! String, data: SafeABI.hexBytes(o["data"] as! String)!)
}
var legs: [(X.Leg, X.Fees, [YourAccountSwap.Call], Int)] = []
for v in fixture["vectors"] as! [[String: Any]] {
    let name = v["name"] as! String
    check(v["simulated"] as? Bool == true, "\(name) was not simulated green when the fixture was made")
    let asset: X.Asset = (v["asset"] as! String) == "eth" ? .eth : .dollar
    let from = v["from"] as! Int, to = v["to"] as! Int
    let leg = X.Leg(asset: asset, from: from, to: to, toName: names[to]!, inputAmount: v["input"] as! String,
                    outputAmount: v["output"] as! String, seconds: 7, fillDeadline: v["fillDeadline"] as! Int)
    let fees = X.Fees(outputAmount: leg.outputAmount, quoteTimestamp: v["quoteTimestamp"] as! Int, fillDeadline: leg.fillDeadline,
                      exclusiveRelayer: v["relayer"] as! String, exclusivity: v["exclusivity"] as! Int, seconds: 7,
                      spokePool: X.spokes[from]!, tooLow: false, minDeposit: nil, maxDeposit: nil)
    let want = (v["calls"] as! [[String: Any]]).map(call)
    let built = X.calls(leg, fees: fees, account: account)
    check(built == want, "\(name): the builder's bytes are not the independent encoder's")
    let now = (v["quoteTimestamp"] as! Int) + 60
    let ok = X.checked(want, leg: leg, account: account, now: now)
    check(ok != nil && ok!.calls.count == 1 && ok!.approvals.count == (asset == .dollar ? 1 : 0),
          "\(name): the check refuses the simulated calls")
    if asset == .dollar, let a = ok?.approvals.first {
        check(a.spender == X.spokes[from]! && a.amount == leg.inputAmount, "\(name): the approval is not exactly the input to the pool")
    }
    legs.append((leg, fees, want, now))
}

// ── Tampering, each refused ───────────────────────────────────────────────
func tampered(_ i: Int, _ what: String, _ change: (inout [YourAccountSwap.Call]) -> Void) {
    var cs = legs[i].2
    change(&cs)
    check(X.checked(cs, leg: legs[i].0, account: account, now: legs[i].3) == nil, "taken: \(what)")
}
func word(_ data: [UInt8], _ n: Int, _ w: [UInt8]) -> [UInt8] { var d = data; d.replaceSubrange((4 + 32 * n)..<(4 + 32 * n + 32), with: w); return d }
let stranger = YourAccount.w("0x1111111111111111111111111111111111111111")
// 0: ETH Base→Ethereum; 2: USDC Base→Ethereum.
tampered(0, "a deposit to an unpinned contract") { $0[0] = .init(to: "0x1111111111111111111111111111111111111111", value: $0[0].value, data: $0[0].data) }
tampered(0, "another depositor (the refund's)") { $0[0] = .init(to: $0[0].to, value: $0[0].value, data: word($0[0].data, 0, stranger)) }
tampered(0, "ETH straight to the account (it would arrive as WETH)") { $0[0] = .init(to: $0[0].to, value: $0[0].value, data: word($0[0].data, 1, YourAccount.w(account))) }
tampered(0, "more out than written") { $0[0] = .init(to: $0[0].to, value: $0[0].value, data: word($0[0].data, 5, SafeABI.word(uint256: "9999999999999999")!)) }
tampered(0, "another destination network") { $0[0] = .init(to: $0[0].to, value: $0[0].value, data: word($0[0].data, 6, YourAccount.w(10))) }
tampered(0, "ETH sent with a value other than the input") { $0[0] = .init(to: $0[0].to, value: "1", data: $0[0].data) }
tampered(0, "an exclusivity with no relayer") { $0[0] = .init(to: $0[0].to, value: $0[0].value, data: word($0[0].data, 10, YourAccount.w(12))) }
tampered(0, "a second deposit") { $0.append($0[0]) }
tampered(0, "an approval on an ETH crossing") { $0.insert(.init(to: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", value: "0", data: YourAccountSwap.approveSelector + YourAccount.w(X.spokes[8453]!) + SafeABI.word(uint256: "1")!), at: 0) }
tampered(2, "an approval to someone else") { $0[0] = .init(to: $0[0].to, value: "0", data: YourAccountSwap.approveSelector + stranger + Array($0[0].data.suffix(32))) }
tampered(2, "an approval wider than the input") { $0[0] = .init(to: $0[0].to, value: "0", data: Array($0[0].data.prefix(36)) + SafeABI.word(uint256: "25000001")!) }
tampered(2, "a dollar deposit to the handler") { $0[1] = .init(to: $0[1].to, value: "0", data: word($0[1].data, 1, YourAccount.w(X.handler))) }
tampered(2, "ETH sent with a dollar deposit") { $0[1] = .init(to: $0[1].to, value: "1", data: $0[1].data) }
tampered(2, "no approval") { $0.removeFirst() }
// A message paying another account: the handler's two calls, for someone else.
let elsewhere = X.message(to: 1, amount: legs[0].0.outputAmount, account: "0x1111111111111111111111111111111111111111")!
let mine = X.message(to: 1, amount: legs[0].0.outputAmount, account: account)!
check(mine != elsewhere && mine.count == elsewhere.count, "the message does not name the account")
tampered(0, "a message that pays someone else") { cs in
    let d = cs[0].data
    cs[0] = .init(to: cs[0].to, value: cs[0].value, data: Array(d.prefix(d.count - mine.count - (32 - mine.count % 32) % 32))
                  + elsewhere + [UInt8](repeating: 0, count: (32 - mine.count % 32) % 32))
}
var foreign = legs[0]
foreign.2 = [.init(to: legs[0].2[0].to, value: legs[0].2[0].value,
                   data: X.deposit(legs[0].0, fees: legs[0].1, account: account)!.dropLast(0))]
check(X.checked(foreign.2, leg: legs[0].0, account: account, now: legs[0].3) != nil, "the builder's own deposit is refused")
check(X.checked(foreign.2, leg: legs[0].0, account: "0x1111111111111111111111111111111111111111", now: legs[0].3) == nil,
      "a deposit for one account is taken for another")

// Across's terms.
func leg(_ out: String, deadline: Int) -> X.Leg {
    X.Leg(asset: .eth, from: 8453, to: 1, toName: "Ethereum", inputAmount: "10000000000000000", outputAmount: out, seconds: 7, fillDeadline: deadline)
}
check(X.acceptable(leg("9989268712761862", deadline: 1_000_7200), now: 1_000_0000), "a fair crossing is refused")
check(!X.acceptable(leg("10000000000000001", deadline: 1_000_7200), now: 1_000_0000), "more out than in is taken")
check(!X.acceptable(leg("9499999999999999", deadline: 1_000_7200), now: 1_000_0000), "a fee over 5% is taken")
check(X.acceptable(leg("9500000000000000", deadline: 1_000_7200), now: 1_000_0000), "exactly 5% is refused")
check(!X.acceptable(leg("9989268712761862", deadline: 1_000_0000 + 21_601), now: 1_000_0000), "a deadline past six hours is taken")
check(!X.acceptable(leg("9989268712761862", deadline: 1_000_0000), now: 1_000_0000), "a deadline already past is taken")
var late = legs[0]; late.3 = legs[0].0.fillDeadline + 1
check(X.checked(late.2, leg: late.0, account: account, now: late.3) == nil, "a crossing whose deadline passed is signed")

// ── The ETH message, the arrival proven on each network ───────────────────
for a in fixture["arrivals"] as! [[String: Any]] {
    let to = a["to"] as! Int
    check(SafeABI.hex(X.message(to: to, amount: a["amount"] as! String, account: account)!) == (a["message"] as! String),
          "the message for \(to) is not the independent encoder's")
    check((a["statuses"] as! [String]).allSatisfy { $0 == "0x1" } && (a["gained"] as! String) == (a["amount"] as! String),
          "the message did not pay a contract account exactly the fill on \(to) when the fixture was made")
}

// ── Across's answer, read ─────────────────────────────────────────────────
let answer = fixture["fees"] as! [String: Any]
let fees = X.fees(answer, from: 8453)
check(fees?.outputAmount == "9989268712761862" && fees?.quoteTimestamp == 1793052083 && fees?.fillDeadline == 1793059283
      && fees?.exclusiveRelayer == "0x394311a6aaa0d8e3411d8b62de4578d41322d1bd" && fees?.exclusivity == 12 && fees?.seconds == 7
      && fees?.tooLow == false && fees?.minDeposit == "216542082788369",
      "a real suggested-fees answer is misread: \(String(describing: fees))")
check(X.fees(answer, from: 1) == nil, "an answer naming another SpokePool is taken")
var noPool = answer; noPool["spokePoolAddress"] = "0x1111111111111111111111111111111111111111"
check(X.fees(noPool, from: 8453) == nil, "an answer naming an unpinned SpokePool is taken")
var badOut = answer; badOut["outputAmount"] = "12e3"
check(X.fees(badOut, from: 8453) == nil, "an output that is not a number is taken")
let ethURL = X.feesURL(.eth, from: 8453, to: 1, amount: "10000000000000000", account: account)!.absoluteString
check(ethURL.hasPrefix("https://app.across.to/api/suggested-fees?") && ethURL.contains("recipient=\(X.handler)")
      && ethURL.contains("message=0x") && ethURL.contains("originChainId=8453") && ethURL.contains("destinationChainId=1"),
      "the ETH fee question does not price the handler's message: \(ethURL)")
let usdURL = X.feesURL(.dollar, from: 1, to: 8453, amount: "25000000", account: account)!.absoluteString
check(usdURL.contains("recipient=\(account)") && !usdURL.contains("message="), "the dollar's fee question names the handler")
check(X.feesURL(.eth, from: 8453, to: 8453, amount: "1", account: account) == nil, "a same-network fee question is asked")

// ── The fill, read ────────────────────────────────────────────────────────
for d in fixture["deposits"] as! [[String: Any]] {
    let log = d["log"] as! [String: Any]
    let dep = X.deposited([log], origin: 8453, account: d["depositor"] as! String)
    check(dep != nil && SafeABI.hex(X.relayHash(dep!)) == (d["relayHash"] as! String),
          "the relay hash is not the destination SpokePool's own for \(d["tx"] as! String)")
    check(dep?.destinationChainId == (d["destination"] as! Int), "the destination is misread")
    check(X.deposited([log], origin: 8453, account: account) == nil, "another account's deposit is taken as ours")
    check(X.deposited([log], origin: 1, account: d["depositor"] as! String) == nil, "a log from another network's pool is taken")
}
check(X.fill(YourAccount.w(2)) == .filled && X.fill(YourAccount.w(0)) == .waiting && X.fill(YourAccount.w(1)) == .slow
      && X.fill(YourAccount.w(3)) == nil, "fillStatuses' answers are misread")
check(X.fundsDepositedTopic == "0x32ed1a409ef04c7b0227189c3a103dc5ac10e775a15b785dcc510201f7c25ad3", "the FundsDeposited topic moved")

// ── The words ─────────────────────────────────────────────────────────────
check(legs[0].0.feePips == 1074 && X.words(legs[0].0) == "Through Across · 0.11% fee", "the fee is not said as a pool's: \(X.words(legs[0].0))")
check(legs[3].0.feePips == 259 && X.words(legs[3].0) == "Through Across · 0.03% fee", "a small fee is not rounded: \(X.words(legs[3].0))")
check(X.about(7) == "about 7 seconds" && X.time(150) == "About 3 minutes" && X.time(nil) == nil, "the time is not said")

// ── The Wallet's one row ──────────────────────────────────────────────────
let at = Date(timeIntervalSince1970: 1_800_000_000)
var c = X.Crossing(id: "c1", account: account, from: 1, to: 8453, sold: "0.01 ETH", symbol: "USDC",
                   contract: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", decimals: 6, outputUnits: "24870000",
                   refundContract: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", refundSymbol: "USDC", inputUnits: "24900000",
                   fillDeadline: 1_800_007_200, at: at, tx: "0xABC")
func take(_ ref: String = "r", hash: String = "", received: Bool = true, wallet: String = account, chain: Int = 8453,
          contract: String? = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", from: String? = "0x2222222222222222222222222222222222222222",
          value: Double = 24.87, late: TimeInterval = 30, list: [X.Crossing]? = nil) -> X.Take? {
    X.take(ref: ref, hash: hash, received: received, wallet: wallet, chainId: chain, contract: contract, from: from,
           value: value, at: at.addingTimeInterval(late), in: list ?? [c])?.take
}
check(take(hash: "0xabc", received: false, chain: 1, contract: nil, value: 0.01) == .sending, "the sending transaction is landed as its own leg")
check(take(hash: "0xabc", received: false, chain: 8453, contract: nil, value: 0.01) == nil, "the same hash on another network is taken")
check(take() == .settles(.filled), "the arrival is not the crossing's")
check(take(value: 24.86) == nil, "an arrival of another amount is taken")
check(take(wallet: "0x1111111111111111111111111111111111111111") == nil, "another wallet's arrival is taken")
check(take(chain: 1) == nil, "an arrival on the sending network is taken as the fill")
check(take(contract: nil) == nil, "ETH is taken as the USDC that was to arrive")
check(take(late: 4 * 24 * 3600) == nil, "an arrival days later is taken")
var unsent = c; unsent.tx = nil
check(take(list: [unsent]) == nil, "a crossing never sent is filled")
let refund = take(chain: 1, contract: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", from: X.spokes[1]!, value: 24.9, late: 7300)
check(refund == .settles(.refunded), "the refund is not the crossing's")
check(take(chain: 1, contract: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", from: "0x2222222222222222222222222222222222222222",
           value: 24.9, late: 7300) == nil, "a dollar from anyone is taken as the refund")
check(take(chain: 1, contract: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", from: X.spokes[1]!, value: 24.9, late: 600) == nil,
      "a refund before the deadline is taken")
var seen = c; seen.taken = ["arrival"]
check(take("arrival", list: [seen]) == .taken && take("other", list: [seen]) == nil, "a taken leg lands again, or a second is taken")
// The words of each state.
check(X.title(c) == "USDC arriving on Base" && X.line(c, now: 1_800_000_100) == "Swapped 0.01 ETH on Ethereum",
      "the waiting row's words moved: \(X.title(c)) / \(X.line(c, now: 0))")
check(X.line(c, now: 1_800_007_201) == "Not filled · coming back on Ethereum", "past the deadline it still says it is coming")
c.state = .filled
check(X.title(c) == "Swapped 0.01 ETH for USDC" && X.line(c, now: 0) == "Ethereum to Base" && X.figure(c) == "24.87",
      "the filled row's words moved: \(X.title(c)) / \(X.line(c, now: 0)) / \(X.figure(c))")
c.state = .refunded
check(X.title(c) == "Refunded 24.9 USDC on Ethereum" && X.line(c, now: 0) == "The swap to Base wasn't filled"
      && X.figure(c) == "24.90", "the refunded row's words moved: \(X.title(c)) / \(X.figure(c))")
var whole = c; whole.state = .filled; whole.outputUnits = "49700000"
check(X.figure(whole) == "49.70", "a dollar loses its cents: \(X.figure(whole))")
whole.outputUnits = "50000000"
check(X.figure(whole) == "50.00", "a whole dollar is not said with cents: \(X.figure(whole))")
var eth = c; eth.decimals = 18; eth.state = .refunded; eth.inputUnits = "10000000000000000"; eth.refundSymbol = "WETH"
check(X.figure(eth) == "0.01" && X.title(eth) == "Refunded 0.01 WETH on Ethereum", "an ETH refund is not said as WETH")
// What comes back is listed in Move's holdings (prd §1556): WETH for ETH,
// from the deadline on, never before, never for a crossing that filled.
eth.refundContract = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
check(X.returning(eth, now: 0)?.contract == "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
      && X.returning(eth, now: 0)?.symbol == "WETH" && X.returning(eth, now: 0)?.decimals == 18,
      "a refunded ETH crossing's WETH is not listed")
var lapsed = eth; lapsed.state = .waiting
check(X.returning(lapsed, now: lapsed.fillDeadline + 1)?.symbol == "WETH" && X.returning(lapsed, now: lapsed.fillDeadline) == nil,
      "WETH is listed before the deadline, or not after it")
var arrived = eth; arrived.state = .filled
check(X.returning(arrived, now: arrived.fillDeadline + 1) == nil, "a filled crossing lists a refund")
var unsentBack = eth; unsentBack.tx = nil
check(X.returning(unsentBack, now: 0) == nil, "a crossing never sent lists a refund")

// ── A swap on the receiving network (prd §1565) ─────────────────────────────
// Each vector: written by an independent encoder, its deposit simulated on
// the sending network, the handler's message run on the receiving one as a
// fill runs it (the swap paid the account its quote), and run again with a
// minimum no pool can pay (the handler paid the account the bridged token,
// whole: the fallback).
let arrivalFixture = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/arrival.json"))) as! [String: Any]
check((arrivalFixture["account"] as! String) == account, "the arrival vectors name another account")
let strangerAddress = "0x1111111111111111111111111111111111111111"
func depositData(_ leg: X.Leg, _ fees: X.Fees, recipient: String, note: [UInt8]) -> [UInt8] {
    typealias A = YourAccountSwap.Arg
    return YourAccountSwap.call(X.depositSignature, [
        .address(account), .address(recipient), .address(X.bridged(leg.asset, on: leg.from)!), .address(X.bridged(leg.asset, on: leg.to)!),
        A.amount(leg.inputAmount)!, A.amount(leg.outputAmount)!, .uint(leg.to), .address(fees.exclusiveRelayer),
        .uint(fees.quoteTimestamp), .uint(leg.fillDeadline), .uint(fees.exclusivity), .bytes(note)])
}
func withDeposit(_ cs: [YourAccountSwap.Call], _ data: [UInt8]) -> [YourAccountSwap.Call] {
    var out = cs
    out[out.count - 1] = .init(to: out[out.count - 1].to, value: out[out.count - 1].value, data: data)
    return out
}
var arrivals: [(leg: X.Leg, fees: X.Fees, calls: [YourAccountSwap.Call], now: Int, v: [String: Any])] = []
for v in arrivalFixture["vectors"] as! [[String: Any]] {
    let name = v["name"] as! String
    let sim = v["simulated"] as! [String: Any], fb = v["fallback"] as! [String: Any]
    let output = v["output"] as! String, quoted = v["quoted"] as! String, least = v["minimum"] as! String
    check((sim["origin"] as! [String]).allSatisfy { $0 == "0x1" } && (sim["destination"] as! [String]).allSatisfy { $0 == "0x1" }
          && (sim["callsFailed"] as! Bool) == false, "\(name): not simulated green on both networks when the fixture was made")
    let gained = sim["gained"] as! [String]
    check(gained[1] == "0" && YourAccountOp.atMost(least, gained[0]), "\(name): the swap there did not pay the account its minimum")
    check((fb["callsFailed"] as! Bool) && (fb["gained"] as! [String]) == ["0", output] && (fb["statuses"] as! [String]).allSatisfy { $0 == "0x1" },
          "\(name): the fallback did not pay the account the bridged token whole")
    let asset: X.Asset = (v["asset"] as! String) == "eth" ? .eth : .dollar
    let from = v["from"] as! Int, to = v["to"] as! Int
    let book = YourAccountSwap.book(to)!
    let venue = book.venues.first { $0.kind == .uniswap }!
    check(venue.router == (v["router"] as! String), "\(name): the router is not the receiving book's")
    let into = X.bridged(asset, on: to)!
    let target = v["target"] as! String
    let buy = YourAccountOp.Token(symbol: v["symbol"] as! String, decimals: v["decimals"] as! Int, contract: target)
    let route = YourAccountSwap.Route(venue: venue, hops: [.init(from: into, to: target, step: v["fee"] as! Int)])
    check(YourAccountSwap.minimum(quoted, bps: book.slippageBps) == least, "\(name): the minimum is not the quote less the network's slippage")
    var leg = X.Leg(asset: asset, from: from, to: to, toName: names[to]!, inputAmount: v["input"] as! String,
                    outputAmount: output, seconds: 7, fillDeadline: v["fillDeadline"] as! Int)
    leg.swap = X.Arrival(route: route, buy: buy, quoted: quoted, minimum: least)
    let fees = X.Fees(outputAmount: output, quoteTimestamp: v["quoteTimestamp"] as! Int, fillDeadline: leg.fillDeadline,
                      exclusiveRelayer: v["relayer"] as! String, exclusivity: v["exclusivity"] as! Int, seconds: 7,
                      spokePool: X.spokes[from]!, tooLow: false, minDeposit: nil, maxDeposit: nil)
    check(X.viaHandler(leg), "\(name): a swap on arrival is not paid to the handler")
    check(X.message(for: leg, account: account).map(SafeABI.hex) == (v["message"] as! String),
          "\(name): the handler's message is not the independent encoder's")
    let want = (v["calls"] as! [[String: Any]]).map(call)
    check(X.calls(leg, fees: fees, account: account) == want, "\(name): the deposit is not the independent encoder's")
    let pricedNow = (v["pricedDeadline"] as! Int) - X.maxDeadlineSeconds
    check(X.pricing(asset, to: to, amount: leg.inputAmount, route: route, account: account, now: pricedNow).map(SafeABI.hex)
          == (v["pricedMessage"] as! String), "\(name): the fee question's message is not the one Across priced")
    let url = X.feesURL(asset, from: from, to: to, amount: leg.inputAmount, account: account, through: route, now: pricedNow)!.absoluteString
    check(url.contains("recipient=\(X.handler)") && url.contains("message=\(v["pricedMessage"] as! String)"),
          "\(name): the fee question does not price the swap's message: \(url)")
    let now = (v["quoteTimestamp"] as! Int) + 60
    let ok = X.checked(want, leg: leg, account: account, now: now)
    check(ok != nil && ok!.calls.count == 1 && ok!.approvals.count == (asset == .dollar ? 1 : 0), "\(name): the check refuses the simulated calls")
    // The words: the foot's, and Details' one line.
    check(X.arrivalWords(leg) == "On Uniswap · 0.05% pool fee on \(names[to]!)" && X.arrivalBrief(leg) == "Uniswap · 0.05% on \(names[to]!)",
          "\(name): the swap there is not said with its network: \(X.arrivalBrief(leg) ?? "-")")
    arrivals.append((leg, fees, want, now, v))
}

// Tampering, each refused before Face ID.
for a in arrivals {
    let name = a.v["name"] as! String
    func refused(_ what: String, _ cs: [YourAccountSwap.Call], leg: X.Leg? = nil) {
        check(X.checked(cs, leg: leg ?? a.leg, account: account, now: a.now) == nil, "\(name): taken: \(what)")
    }
    let mine = X.arrivalCalls(a.leg, account: account)!
    // The swap paying someone else; the fallback naming someone else.
    refused("a swap there that pays someone else",
            withDeposit(a.calls, depositData(a.leg, a.fees, recipient: X.handler, note: X.message(for: a.leg, account: strangerAddress)!)))
    let otherFallback = YourAccountSwap.encode([.tuple([.array(mine.map { .tuple([.address($0.to), .bytes($0.data), .uint(0)]) }),
                                                        .address(strangerAddress)])])
    refused("a fallback that pays someone else", withDeposit(a.calls, depositData(a.leg, a.fees, recipient: X.handler, note: otherFallback)))
    // A lower minimum written into the router call.
    let book = YourAccountSwap.book(a.leg.to)!
    let looser = YourAccountSwap.calls(a.leg.swap!.route, in: book, sellsETH: false, buysETH: false, amount: a.leg.outputAmount,
                                       minimum: "1", account: account, deadline: a.leg.fillDeadline)!
    let looseNote = YourAccountSwap.encode([.tuple([.array(looser.map { .tuple([.address($0.to), .bytes($0.data), .uint(0)]) }),
                                                    .address(account)])])
    refused("a minimum of one unit", withDeposit(a.calls, depositData(a.leg, a.fees, recipient: X.handler, note: looseNote)))
    // The fee question's message, which Across priced and nobody signs.
    let priced = SafeABI.hexBytes(a.v["pricedMessage"] as! String)!
    refused("the fee question's message", withDeposit(a.calls, depositData(a.leg, a.fees, recipient: X.handler, note: priced)))
    // Paid straight to the account, no swap there.
    refused("a swap on arrival paid to the account", withDeposit(a.calls, depositData(a.leg, a.fees, recipient: account, note: [])))
    // ETH's unwrap message in place of the swap.
    if a.leg.asset == .eth {
        refused("the unwrap message in place of the swap", withDeposit(a.calls, depositData(a.leg, a.fees, recipient: X.handler,
                note: X.message(to: a.leg.to, amount: a.leg.outputAmount, account: account)!)))
    }
    // Legs the builder refuses to write at all.
    var alien = a.leg
    let elsewhere = YourAccountSwap.book(a.leg.to == 1 ? 8453 : 1)!.venues.first { $0.kind == .uniswap }!
    alien.swap = X.Arrival(route: .init(venue: elsewhere, hops: a.leg.swap!.route.hops), buy: a.leg.swap!.buy,
                           quoted: a.leg.swap!.quoted, minimum: a.leg.swap!.minimum)
    check(X.calls(alien, fees: a.fees, account: account) == nil && X.checked(a.calls, leg: alien, account: account, now: a.now) == nil,
          "\(name): a router of another network is written")
    var cheap = a.leg
    cheap.swap = X.Arrival(route: a.leg.swap!.route, buy: a.leg.swap!.buy, quoted: a.leg.swap!.quoted, minimum: "1")
    check(X.calls(cheap, fees: a.fees, account: account) == nil, "\(name): a minimum under the network's slippage is written")
    var itself = a.leg
    let into = X.bridged(a.leg.asset, on: a.leg.to)!
    itself.swap = X.Arrival(route: .init(venue: a.leg.swap!.route.venue, hops: [.init(from: into, to: into, step: 500)]),
                            buy: YourAccountOp.Token(symbol: "X", decimals: 18, contract: into), quoted: "100", minimum: "99")
    check(X.calls(itself, fees: a.fees, account: account) == nil, "\(name): a swap of the bridged token for itself is written")
    var wrongStart = a.leg
    wrongStart.swap = X.Arrival(route: .init(venue: a.leg.swap!.route.venue,
                                             hops: [.init(from: a.leg.swap!.buy.contract!, to: a.leg.swap!.buy.contract!, step: 500)]),
                                buy: a.leg.swap!.buy, quoted: a.leg.swap!.quoted, minimum: a.leg.swap!.minimum)
    check(X.calls(wrongStart, fees: a.fees, account: account) == nil, "\(name): a swap from something that did not arrive is written")
}

// The note this phone keeps for a swap on arrival, and the Wallet's one row.
let usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7", wethMain = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
let sentAt = Date(timeIntervalSince1970: 1_800_000_000)
let swapNote = X.Crossing(id: "s1", account: account, from: 8453, to: 1, sold: "0.01 ETH", symbol: "USDT", contract: usdt, decimals: 6,
                          outputUnits: "23058814", refundContract: "0x4200000000000000000000000000000000000006", refundSymbol: "WETH",
                          inputUnits: "10000000000000000", fillDeadline: 1_800_007_200, at: sentAt, tx: "0xdef",
                          atLeast: true, fallbackContract: wethMain, fallbackSymbol: "WETH", fallbackDecimals: 18,
                          fallbackUnits: "9981835323831359", refundDecimals: 18)
func arrive(_ contract: String?, _ value: Double, from: String = "0x3333333333333333333333333333333333333333", late: TimeInterval = 20,
            in list: [X.Crossing]? = nil) -> X.Take? {
    X.take(ref: "a", hash: "", received: true, wallet: account, chainId: 1, contract: contract, from: from, value: value,
           at: sentAt.addingTimeInterval(late), in: list ?? [swapNote])?.take
}
check(arrive(usdt, 23.128199) == .settles(.filled), "a swap's arrival over its minimum is not the crossing's")
check(arrive(usdt, 23.05) == nil, "an arrival under the swap's minimum is taken")
check(arrive(usdt, 23.128199, late: -60) == nil, "a token that came before the swap was sent is taken")
check(arrive(wethMain, 0.009981835323831359, from: X.handler) == .settles(.filled), "the fallback's WETH from the handler is not the crossing's")
check(arrive(wethMain, 0.009981835323831359) == nil, "WETH from anyone is taken as the fallback")
check(X.title(swapNote) == "USDT arriving on Ethereum" && X.line(swapNote, now: 1_800_000_100) == "Swapped 0.01 ETH on Base",
      "the waiting swap's words moved: \(X.title(swapNote))")
var settled = swapNote
X.settle(&settled, .filled, ref: "a", contract: usdt, value: 23.128199, at: sentAt)
check(settled.state == .filled && settled.outputUnits == "23128199" && settled.atLeast == false && X.figure(settled) == "23.12"
      && X.title(settled) == "Swapped 0.01 ETH for USDT", "what the swap paid is not what the row says: \(X.figure(settled))")
var fellBack = swapNote
X.settle(&fellBack, .filled, ref: "a", contract: wethMain, value: 0.009981835323831359, at: sentAt)
check(fellBack.symbol == "WETH" && fellBack.contract == wethMain && fellBack.outputUnits == "9981835323831359"
      && X.title(fellBack) == "Swapped 0.01 ETH for WETH" && X.figure(fellBack) == "0.009981",
      "a swap that fell back does not say WETH came: \(X.title(fellBack)) \(X.figure(fellBack))")
var swapRefund = swapNote; swapRefund.state = .refunded
check(X.title(swapRefund) == "Refunded 0.01 WETH on Base" && X.figure(swapRefund) == "0.01",
      "a refund counted in the token it was to buy: \(X.title(swapRefund))")
check(X.returning(swapRefund, now: 0)?.decimals == 18, "the WETH a swap's refund returns is not counted in WETH's decimals")

// ── A crossing from another device, read off chain (prd §1565) ─────────────
// Real Across deposits on Base and their fills on Ethereum and Robinhood,
// as the public nodes answered: the deposit's own log names the crossing,
// the receiving pool's FilledRelay names its fill, and the Wallet's two legs
// are one crossing.
let pairsFixture = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/chain-pairs.json"))) as! [String: Any]
for p in pairsFixture["pairs"] as! [[String: Any]] {
    let o = p["origin"] as! Int, d = p["dest"] as! Int, who = p["depositor"] as! String
    let depositTx = p["depositTx"] as! String, fillTx = p["fillTx"] as! String
    let depLogs = p["depositLogs"] as! [[String: Any]], fillLogs = p["fillLogs"] as! [[String: Any]]
    let sent = p["sent"] as! [String: Any], got = p["received"] as! [String: Any]
    let depAt = Date(timeIntervalSince1970: Double(p["depositTime"] as! Int)), fillAt = Date(timeIntervalSince1970: Double(p["fillTime"] as! Int))
    let what = "\(names[o]!)→\(names[d]!) \(depositTx.prefix(10))"
    guard let dep = X.deposited(depLogs, origin: o, account: who),
          var c = X.chainCrossing(dep, tx: depositTx, wallet: who, at: depAt) else {
        check(false, "\(what): the deposit's own log does not read as a crossing"); continue
    }
    check(c.from == o && c.to == d && c.depositId == (p["depositId"] as! String) && c.state == .waiting && c.symbol == "ETH"
          && c.contract == nil && c.outputUnits == (p["outputAmount"] as! String) && c.inputUnits == (p["inputAmount"] as! String)
          && c.refundSymbol == "WETH" && c.atLeast == nil && c.account == who.lowercased(),
          "\(what): the crossing read off chain is wrong: \(c)")
    check(X.deposited(depLogs, origin: o, account: strangerAddress) == nil, "\(what): another account's deposit is read as ours")
    check(X.deposited(depLogs, origin: d, account: who) == nil, "\(what): a deposit is read off the wrong network's pool")
    // The send is the crossing's, never a row of its own.
    check(X.take(ref: "s", hash: depositTx, received: false, wallet: who, chainId: o, contract: nil, from: nil,
                 value: sent["value"] as! Double, at: depAt, in: [c])?.take == .sending, "\(what): the send to Across lands as its own row")
    // The fill, read off the receiving pool.
    let fills = X.filled(fillLogs, dest: d)
    check(fills.count == 1 && fills.first?.depositId == c.depositId && fills.first?.originChainId == o
          && fills.first?.depositor == who.lowercased() && fills.first?.outputAmount == c.outputUnits,
          "\(what): the fill does not read: \(fills)")
    check(X.filled(fillLogs, dest: o).isEmpty, "\(what): a fill is read off another network's pool")
    var forged = fillLogs
    for i in forged.indices { forged[i]["address"] = strangerAddress }
    check(X.filled(forged, dest: d).isEmpty, "\(what): a FilledRelay from an unpinned contract is read")
    check(X.filled(depLogs, dest: o).isEmpty, "\(what): a deposit's log is read as a fill")
    check(X.crossing(filledBy: fills[0], dest: d, in: [c])?.id == c.id, "\(what): the fill does not find its crossing")
    var other = c; other.depositId = "1"
    check(X.crossing(filledBy: fills[0], dest: d, in: [other]) == nil, "\(what): another deposit's fill finishes this crossing")
    var notMine = c; notMine.account = strangerAddress
    check(X.crossing(filledBy: fills[0], dest: d, in: [notMine]) == nil, "\(what): a fill of another depositor finishes this crossing")
    check(X.crossing(filledBy: fills[0], dest: o, in: [c]) == nil, "\(what): a fill on the sending network finishes it")
    X.arrived(&c, received: [.init(contract: nil, symbol: got["asset"] as! String, value: got["value"] as! Double)],
              fillTx: fillTx, at: fillAt)
    check(c.state == .filled && c.fillTx == fillTx.lowercased() && c.settledAt == fillAt && c.outputUnits == (p["outputAmount"] as! String),
          "\(what): the fill does not finish the crossing")
    // Every leg of the fill's transaction is the crossing's; another is not.
    check(X.take(ref: "r", hash: fillTx, received: true, wallet: who, chainId: d, contract: nil, from: got["from"] as? String,
                 value: got["value"] as! Double, at: fillAt, in: [c])?.take == .taken, "\(what): the arrival lands as its own row")
    check(X.take(ref: "r", hash: fillTx, received: true, wallet: who, chainId: o, contract: nil, from: nil,
                 value: 1, at: fillAt, in: [c]) == nil, "\(what): the fill's hash is taken on another network")
    check(X.take(ref: "q", hash: "0xfeed", received: true, wallet: who, chainId: d, contract: usdt, from: nil,
                 value: 5, at: fillAt, in: [c]) == nil, "\(what): an unrelated receive is taken")
    // One row: the user's words (§1555's filled row, "Swapped" the glyph's).
    let amount = YourAccountOp.spoken(p["inputAmount"] as! String, decimals: 18)
    check(X.title(c) == "Swapped \(amount) ETH for ETH" && X.line(c, now: 0) == "\(names[o]!) to \(names[d]!)",
          "\(what): the one row's words: \(X.title(c)) / \(X.line(c, now: 0))")
    if depositTx.hasPrefix("0xde634499") {
        check(X.title(c) == "Swapped 0.5 ETH for ETH" && X.line(c, now: 0) == "Base to Ethereum" && X.figure(c) == "0.499772",
              "the 0.5 ETH Base→Ethereum crossing is not said as one: \(X.title(c)) \(X.figure(c))")
    }
}

// A crossing Casberi sends, read off chain on another phone: the handler is
// its recipient, so what arrives is at least its output until met, and a
// swap there that fell back says WETH.
let av = arrivals[0]
typealias AA = YourAccountSwap.Arg
let depositLogData = YourAccountSwap.encode([
    .address(X.bridged(.eth, on: 8453)!), .address(X.bridged(.eth, on: 1)!), AA.amount(av.leg.inputAmount)!, AA.amount(av.leg.outputAmount)!,
    .uint(av.fees.quoteTimestamp), .uint(av.leg.fillDeadline), .uint(av.fees.exclusivity), .address(X.handler),
    .address(av.fees.exclusiveRelayer), .bytes(X.message(for: av.leg, account: account)!)])
func depositLog(recipientData: [UInt8]) -> [String: Any] {
    ["address": X.spokes[8453]!, "topics": [X.fundsDepositedTopic, SafeABI.hex(YourAccount.w(1)), SafeABI.hex(YourAccount.w(7_000_001)),
                                             SafeABI.hex(YourAccount.w(account))], "data": SafeABI.hex(recipientData)]
}
let casberiDeposit = X.deposited([depositLog(recipientData: depositLogData)], origin: 8453, account: account)!
let viaHandler = X.chainCrossing(casberiDeposit, tx: "0xAAA", wallet: account, at: sentAt, sold: "12 AERO")
check(viaHandler?.atLeast == true && viaHandler?.fallbackContract == wethMain && viaHandler?.fallbackSymbol == "WETH"
      && viaHandler?.fallbackUnits == av.leg.outputAmount && viaHandler?.sold == "12 AERO" && viaHandler?.depositId == "7000001"
      && viaHandler?.tx == "0xaaa", "a Casberi crossing read off chain is wrong: \(String(describing: viaHandler))")
var boughtThere = viaHandler!
X.arrived(&boughtThere, received: [.init(contract: usdt, symbol: "USDT", value: 23.128199)], fillTx: "0xF1", at: sentAt)
check(boughtThere.symbol == "USDT" && boughtThere.contract == usdt && X.title(boughtThere) == "Swapped 12 AERO for USDT"
      && X.figure(boughtThere) == "23.128199", "what a swap there bought is not what the row says: \(X.title(boughtThere)) \(X.figure(boughtThere))")
var fellThere = viaHandler!
X.arrived(&fellThere, received: [.init(contract: wethMain, symbol: "WETH", value: 0.00998183532)], fillTx: "0xF2", at: sentAt)
check(fellThere.symbol == "WETH" && fellThere.outputUnits == av.leg.outputAmount, "a fallback read off chain does not say exactly the WETH that came (the Wallet rounds what it read)")
// A deposit to someone else is a send, not a crossing of the account's.
var toSomeone = depositLogData
toSomeone.replaceSubrange((7 * 32)..<(8 * 32), with: YourAccount.w(strangerAddress))
check(X.chainCrossing(X.deposited([depositLog(recipientData: toSomeone)], origin: 8453, account: account)!, tx: "0xA", wallet: account,
                      at: sentAt) == nil, "a deposit paying someone else is read as the account's crossing")
exit(bad == 0 ? 0 : 1)
SWIFT

SOURCES=("Casberi/Shared/AddressTail.swift" "$SWAP" "$ACCOUNT" "$OP" "$ADAPTER" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" "$TMP/demo-stub.swift")
echo "across-swap-selftest: compiling YourAccountAcross.swift AS SHIPPED…"
xcrun swiftc -Onone -o "$TMP/run" "$ACROSS" "${SOURCES[@]}" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ YourAccountAcross.swift does not compile alone (Foundation and the account's encoders only)"; exit 1; }
FIXTURES="$FIXTURES" "$TMP/run" || { echo "✗ the Across crossing drifted — see above"; exit 1; }
echo "  ok   assertions pass"

# --- the wiring: what no compile of this file alone can see ------------------
wire() { grep -qF -- "$2" "$1" || { echo "  ✗ $3"; exit 1; }; }
wire "$CHAIN" 'guard let checked = YourAccountAcross.checked(crossCalls, leg: leg, account: account,' \
  "assemble no longer holds the crossing's calls to the check before Face ID"
wire "$CHAIN" 'if let crossing = a.crossing, a.sold.contains(where: { $0.across.map(YourAccountAcross.viaHandler) == true }),' \
  "ETH or a swap on arrival is signed without the arrival proven"
wire "$CHAIN" 'if YourAccountAcross.viaHandler(leg) { arrives = await arrivalCheck(dest, leg: leg, account: account) }' \
  "the handler's run on the receiving network is not simulated before Face ID (prd §1565)"
wire "Casberi/Casberi/Model/YourAccountChain+Across.swift" 'let fees = try await acrossFees(asset, from: net, to: dest, amount: bridged, account: account, through: arrivalRoute)' \
  "Across's fee for a swap on arrival is asked without its message"
wire "Casberi/Casberi/Model/YourAccountChain+Across.swift" 'let best = try await bestRoute(dest, sell: into, buy: target, amount: fees.outputAmount),' \
  "the swap on arrival is not quoted on the receiving network for exactly what a relayer pays"
wire "Casberi/Casberi/Model/YourAccountChain+Across.swift" 'read = ["to": bought, "data": SafeABI.hex(YourAccount.sel("balanceOf(address)") + YourAccount.w(account))]' \
  "the simulation on the receiving network does not read the token bought"
wire "$INGEST" 'await WalletAcross.foldFromChain(fresh.compactMap { leg in' \
  "a crossing from another device is not read off chain (prd §1565)"
wire "Casberi/Casberi/Model/WalletAcross.swift" 'let deposit = YourAccountAcross.deposited(logs, origin: first.chainId, account: first.wallet) else { continue }' \
  "the fold off chain does not read the deposit's own log"
wire "Casberi/Casberi/Model/WalletAcross.swift" 'for f in YourAccountAcross.filled(logs, dest: first.chainId) {' \
  "the fold off chain does not read the receiving pool's fill"
wire "Casberi/Casberi/Model/YourAccountChain+Across.swift" '$0.depositId = $0.depositId ?? Across.depositId(deposited)' \
  "a note's deposit id is never kept, so its fill is never met off chain"
wire "Casberi/Casberi/Screens/MoveDetails.swift" 'if let words = s.across.flatMap(YourAccountAcross.arrivalBrief), !out.contains(words) { out.append(words) }' \
  "Details does not name the swap on the receiving network"
wire "Casberi/Casberi/Screens/MoveSentence.swift" 'if verb == .swap, let on = buyOn, on != network {' \
  "For does not offer the receiving network's list"
wire "$CHAIN" 'var mustCheck: Bool { steps.contains { $0.swap != nil } || crossing != nil }' \
  "a crossing signs with no simulation that answered"
wire "$CHAIN" 'guard items.count == 1, let dest = s.to else {' "a crossing is batched with other moves"
wire "$CHAIN" 'if let crossing = a.crossing, !dryRun { YourAccountAcross.note(crossing) }' \
  "the crossing is not kept before Face ID (or a dry run keeps one)"
wire "$INGEST" 'guard let hit = YourAccountAcross.take(ref: leg.ref, hash: leg.hash, received: leg.received,' \
  "the Wallet lands a crossing's legs as rows of their own"
wire "$INGEST" 'var added = await WalletAcross.sync(context: context)' "the crossing's row is never written"
wire "$REACH" '"app.across.to",' "Across's host is not declared in NetworkReach"
wire "Casberi/Casberi/Model/WalletAcross.swift" 'YourAccountTokens.remember(back, on: net)' \
  "a refund's WETH is never listed in Move's holdings (prd §1556)"
wire "Casberi/Casberi/Screens/MoveSentence.swift" 'return (exact ? "" : "≈ ") + Self.figure(back, decimals: token.decimals) + " " + token.symbol' \
  "the print line says ≈ before an exact Across output (prd §1556)"
wire "Casberi/Casberi/Screens/MoveDetails.swift" 's.route.map(YourAccountSwap.brief)' \
  "Details' swap row is the foot's whole sentence again (prd §1556)"

# --- the mutation pass ------------------------------------------------------
mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut-across.swift"
  cp "$ACROSS" "$target"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if src.count(frm) != 1:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! xcrun swiftc -Onone -o "$TMP/mut" "$target" "${SOURCES[@]}" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if FIXTURES="$FIXTURES" "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

echo ""
echo "Mutations — each is a crossing that looks normal:"
mutate "a SpokePool address typo'd" \
  '8453: "0x09aea4b2242abc8bb4bb78d537a67a245a7bec64",' '8453: "0x09aea4b2242abc8bb4bb78d537a67a245a7bec65",'
mutate "the check stops reading the depositor" \
  'guard word(d, 0).flatMap(address) == me,' 'guard word(d, 0) != nil,'
mutate "ETH goes straight to the account (it arrives as WETH)" \
  'let recipient = viaHandler(leg) ? handler : account' 'let recipient = account'
mutate "the check takes any ETH recipient" \
  'guard word(d, 1).flatMap(address) == handler,' 'guard word(d, 1) != nil,'
mutate "the check stops comparing the message" \
  'note == want else { return nil }' 'note.count >= 0 else { return nil }'
mutate "the message pays the handler, not the account" \
  '[.address(YourAccountSwap.native), .address(account)])' '[.address(YourAccountSwap.native), .address(handler)])'
mutate "the message unwraps a different amount" \
  'let unwrap = YourAccountSwap.call("withdraw(uint256)", [units])' 'let unwrap = YourAccountSwap.call("withdraw(uint256)", [.uint(1)])'
mutate "the check stops reading the output" \
  'word(d, 5).map(SafeCalldata.decimal) == leg.outputAmount,' 'word(d, 5) != nil,'
mutate "ETH may leave with any value" \
  'guard call.value == (leg.asset == .eth ? leg.inputAmount : "0") else { return nil }' 'guard !call.value.isEmpty else { return nil }'
mutate "the approval may name any spender" \
  'word(call.data, 0).flatMap(address) == pool,' 'word(call.data, 0) != nil,'
mutate "the fee cap is gone" \
  'Op.atMost(least, leg.outputAmount) else { return false }' 'least.count >= 0 else { return false }'
mutate "the deadline cap is gone" \
  'return leg.fillDeadline > now && leg.fillDeadline <= now + maxDeadlineSeconds' 'return leg.fillDeadline > now'
mutate "an exclusivity with no relayer passes" \
  '(exclusivity == "0") == (relayer == YourAccountSwap.native),' 'exclusivity.count >= 0,'
mutate "the relay hash takes the destination for the origin" \
  '.word(d.outputToken), .word(d.inputAmount), .word(d.outputAmount), .uint(d.originChainId),' '.word(d.outputToken), .word(d.inputAmount), .word(d.outputAmount), .uint(d.destinationChainId),'
mutate "a slow fill reads as filled" \
  '        case 1: return .slow' '        case 1: return .filled'
mutate "any amount arriving is the fill" \
  'if x.to == chainId, x.contract == c, same(value, units: x.outputUnits, decimals: x.decimals) {' 'if x.to == chainId, x.contract == c {'
mutate "another wallet's arrival is the fill" \
  'for x in list where x.account == w && x.state != .refunded' 'for x in list where x.state != .refunded'
mutate "a dollar from anyone is the refund" \
  'c == x.refundContract, sender.map(isSpoke) == true,' 'c == x.refundContract,'
mutate "the sending transaction is matched on any network" \
  '$0.account == w && $0.from == chainId && $0.tx?.lowercased() == hash.lowercased()' '$0.account == w && $0.tx?.lowercased() == hash.lowercased()'
mutate "a taken leg lands again" \
  'if let x = list.first(where: { $0.taken.contains(ref) }) { return (x.id, .taken) }' ''
mutate "a refund is listed before the deadline" \
  'guard c.tx != nil, c.state == .refunded || (c.state == .waiting && now > c.fillDeadline),' 'guard c.tx != nil, c.state != .filled,'
mutate "the fee rounds down (says less than Across keeps)" \
  'NSDecimalRound(&r, &d, 0, .up)' 'NSDecimalRound(&r, &d, 0, .down)'
mutate "the swap on arrival pays the handler" \
  'minimum: s.minimum, account: account, deadline: leg.fillDeadline),' 'minimum: s.minimum, account: handler, deadline: leg.fillDeadline),'
mutate "the swap on arrival's fallback is the handler" \
  'return YourAccountSwap.encode([.tuple([list, .address(account)])])' 'return YourAccountSwap.encode([.tuple([list, .address(handler)])])'
mutate "any minimum is written there" \
  's.minimum == YourAccountSwap.minimum(s.quoted, bps: book.slippageBps),' 'YourAccountSwap.isPositive(s.quoted),'
mutate "a router of another network swaps there" \
  'guard let s = leg.swap, let book = YourAccountSwap.book(leg.to), book.venues.contains(s.route.venue),' 'guard let s = leg.swap, let book = YourAccountSwap.book(leg.to),'
mutate "a swap of something that did not arrive" \
  'let into = bridged(leg.asset, on: leg.to), s.route.hops.first?.from.lowercased() == into,' 'let into = bridged(leg.asset, on: leg.to),'
mutate "a swap on arrival is paid to the account" \
  'static func viaHandler(_ leg: Leg) -> Bool { leg.asset == .eth || leg.swap != nil }' 'static func viaHandler(_ leg: Leg) -> Bool { leg.asset == .eth }'
mutate "the fee question prices no swap" \
  'minimum: "1", account: account, deadline: now + maxDeadlineSeconds)' 'minimum: "1", account: account, deadline: now)'
mutate "an arrival under the swap's minimum is the fill" \
  'if x.contract == c, atLeast(value, units: x.outputUnits, decimals: x.decimals) { return (x, .filled) }' 'if x.contract == c { return (x, .filled) }'
mutate "WETH from anyone is the fallback" \
  'if let fb = x.fallbackContract, c == fb, sender?.lowercased() == handler,' 'if let fb = x.fallbackContract, c == fb,'
mutate "a fill log from an unpinned contract" \
  'guard let from = (log["address"] as? String)?.lowercased(), from == pool,' 'guard let from = (log["address"] as? String)?.lowercased(), !from.isEmpty,'
mutate "another deposit's fill finishes the crossing" \
  '$0.to == dest && $0.from == f.originChainId && $0.depositId == f.depositId && $0.account == f.depositor' '$0.to == dest && $0.from == f.originChainId && $0.account == f.depositor'
mutate "a deposit paying someone else is a crossing" \
  'recipient == me || recipient == handler else { return nil }' 'true else { return nil }'
mutate "the fill's own legs land as rows" \
  '$0.account == w && $0.to == chainId && $0.fillTx == hash.lowercased()' '$0.account == w && $0.fillTx == "never"'
mutate "a swap there that fell back says what it was to buy" \
  '        if let fb, c == fb {
            fellBack(&x)' '        if let fb, c == fb, false {
            fellBack(&x)'
mutate "a refund is counted in the decimals of what it was to buy" \
  'let back = Op.display(c.inputUnits, decimals: c.refundDecimals ?? c.decimals)' 'let back = Op.display(c.inputUnits, decimals: c.decimals)'

echo ""
echo "across-swap-selftest: OK — assertions pass and every mutation is caught."
