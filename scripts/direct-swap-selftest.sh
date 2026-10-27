#!/bin/zsh
# Direct-swap self-test (prd §1539, §1542) — Move's swaps go straight to the
# exchanges: the phone asks every pool, picks the best output and writes the
# swap's calls itself.
#
#   Casberi/Casberi/Model/YourAccountSwap.swift   compiled WHOLE and unmodified
#   Casberi/Casberi/Model/OpenTokenList.swift      compiled WHOLE and unmodified
#
# The failures that cost money, each one silent until it signs:
#
#   • A CALL TO A CONTRACT NOBODY PINNED. Every byte is the phone's now, so a
#     router address typo'd in the book, or a check that waves any address
#     through, sends the account's tokens to whoever is at that address.
#   • AN APPROVAL WIDER THAN THE SWAP, or to a router other than the one that
#     swaps: a standing allowance anyone holding that router can drain.
#   • A MINIMUM THAT IS NOT THE QUOTE LESS THE LIMIT: zero (a sandwich takes
#     everything) or the full quote (every swap fails).
#   • THE CALLDATA ITSELF. Every vector in `fixtures/direct-swap/vectors.json`
#     was written by an independent encoder and SIMULATED ON BASE in one
#     block, every call succeeding (the note in the file says when); the
#     builder here must write those exact bytes — ETH in and out through the
#     routers' own wrapping, one pool and two, Uniswap, Slipstream and v2.
#   • THE WRONG ROUTE. The best output wins; a tie goes to one pool over two,
#     then to the book's order — never to whichever answered last.
#   • A MULTICALL ANSWER MISREAD: a real `aggregate3` answer from Base, read
#     back to the amounts the independent decoder read.
#   • AN OPEN-LIST ROW TAKEN ON FAITH: a malformed address or decimals kept.
#   • A POOL FEE SAID TO FOUR PLACES (prd §1545): rounded to two, trailing
#     zeros trimmed, "under 0.01%" below that; the route keeps the exact fee.
#   • A ROUND-UP BOUGHT THE WRONG WAY (prd §1545): a buy on the send's own
#     network is the exchanges', never Relay's; the spend limit's session key
#     never buys on them, and its change keeps counting; an exchange buy is
#     known by its own transaction — this account's dollar leaving in exactly
#     the buy's amount, in its window — and nothing else.
#
# Pure, local, deterministic — no network, no simulator, no key. Then every
# guard is proven to catch something: each mutation below breaks the shipped
# source one way, and the harness must fail.
set -euo pipefail
cd "$(dirname "$0")/.."

SWAP="Casberi/Casberi/Model/YourAccountSwap.swift"
ACROSS="Casberi/Casberi/Model/YourAccountAcross.swift"
LIST="Casberi/Casberi/Model/OpenTokenList.swift"
ACCOUNT="Casberi/Casberi/Model/YourAccount.swift"
OP="Casberi/Casberi/Model/YourAccountOp.swift"
ADAPTER="Casberi/Casberi/Model/YourAccount7579.swift"
TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
WEBAUTHN="Casberi/Casberi/Model/SafeWebAuthnSignature.swift"
TYPED="Casberi/Casberi/Model/SafeTypedData.swift"
ROUNDUPS="Casberi/Casberi/Model/RoundUps.swift"
FIXTURES="$PWD/scripts/fixtures/direct-swap"
for f in "$SWAP" "$LIST" "$ACCOUNT" "$OP" "$ADAPTER" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" "$FIXTURES/vectors.json"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/direct-swap-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/demo-stub.swift" <<'SWIFT'
enum YourAccountDemo {
    static var isOn: Bool { false }
    static var roundUps: RoundUps.Setting { RoundUps.Setting() }
}
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
typealias S = YourAccountSwap
var bad = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ " + what); bad += 1 } }
let dir = ProcessInfo.processInfo.environment["FIXTURES"]!
let fixture = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/vectors.json"))) as! [String: Any]
let account = fixture["account"] as! String
let deadline = fixture["deadline"] as! Int
let base = S.base

// ── The book: every router pinned, the quoters on their factories ─────────
check(base.venues.map(\.router) == ["0x2626664c2603336e57b271c5c0b26f421741e481", "0xbe6d8f0d05cc4be24d5167a3ef062215be6d18a5",
                                    "0xcbbb8035cac7d4b3ca7abb74cf7bdf900215ce0d", "0x698cb2b6dd822994581fea6ea4fc755d1363a92f",
                                    "0xcf77a3ba9a5ca399b7c97c74d54e5b1beb874e43"],
      "Base's routers are not the five read on chain (Uniswap SwapRouter02, Slipstream ×3, Aerodrome v2)")
check(S.ethereum.venues.map(\.router) == ["0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45"], "Ethereum's router is not Uniswap's SwapRouter02")
check(S.robinhood.venues.map(\.router) == ["0xcaf681a66d020601342297493863e78c959e5cb2"], "Robinhood Chain's router is not Uniswap's SwapRouter02 there")
check(S.robinhood.weth == "0x0bd7d308f8e1639fab988df18a8011f41eacad73", "Robinhood Chain's WETH is not its router's WETH9()")
check(S.books.allSatisfy { b in b.venues.allSatisfy { $0.router == $0.router.lowercased() && $0.quoter == $0.quoter.lowercased() } },
      "a pinned address is not lowercase, so a comparison against a lowercased call misses it")
check(S.base.slippageBps == 50 && S.robinhood.slippageBps == 50 && S.ethereum.slippageBps == 30,
      "the slippage limits are not 0.5% on Base and Robinhood Chain and 0.3% on Ethereum")
check(S.supported(YourAccountOp.base) && S.supported(YourAccountOp.ethereum) && S.supported(YourAccountOp.robinhood)
      && !S.supported(YourAccountOp.baseSepolia), "swaps are not on exactly the three live networks")
check(S.exchange(ofRouter: "0x2626664C2603336E57B271C5C0B26F421741E481") == "Uniswap"
      && S.exchange(ofRouter: "0x698cb2b6dd822994581fea6ea4fc755d1363a92f") == "Aerodrome"
      && S.exchange(ofRouter: "0x000000000000000000000000000000000000dead") == nil, "a router is not named by its exchange")

// ── The calls, byte for byte against simulated vectors ───────────────────
for v in fixture["vectors"] as! [[String: Any]] {
    let name = v["name"] as! String
    let venue = base.venues[v["venue"] as! Int]
    let hops = (v["hops"] as! [[Any]]).map { S.Hop(from: $0[0] as! String, to: $0[2] as! String, step: $0[1] as! Int) }
    let want = (v["calls"] as! [[String: String]]).map { S.Call(to: $0["to"]!, value: $0["value"]!, data: SafeABI.hexBytes($0["data"]!)!) }
    let got = S.calls(S.Route(venue: venue, hops: hops), in: base, sellsETH: v["sellsETH"] as! Bool, buysETH: v["buysETH"] as! Bool,
                      amount: v["amount"] as! String, minimum: v["minimum"] as! String, account: account, deadline: deadline)
    check(got == want, "\(name): the calls are not the simulated bytes")
    // And the check passes exactly these.
    let sold = (v["sellsETH"] as! Bool) ? YourAccountOp.eth : YourAccountOp.Token(symbol: "T", decimals: 18, contract: hops[0].from)
    let quote = S.Quote(sellAmount: v["amount"] as! String, buyAmount: "2", minimumBuy: "1", route: S.Route(venue: venue, hops: hops), calls: want)
    check(S.checked(quote, sell: sold, amount: v["amount"] as! String, chainId: 8453) != nil, "\(name): the check refuses a simulated swap")
    check(S.checked(quote, sell: sold, amount: v["amount"] as! String, chainId: 1) == nil, "\(name): Base's routers pass the check on Ethereum")
}

// ── The check refuses every way of tampering ─────────────────────────────
let usdc = YourAccountOp.Token(symbol: "USDC", decimals: 6, contract: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913")
let aero = "0x940181a94a35a4569e4529a3cdfb74e38fd98631"
let tokenRoute = S.Route(venue: base.venues[0], hops: [S.Hop(from: usdc.contract!.lowercased(), to: aero, step: 3000)])
let tokenCalls = S.calls(tokenRoute, in: base, sellsETH: false, buysETH: false, amount: "5000000", minimum: "100", account: account, deadline: deadline)!
func q(_ calls: [S.Call], amount: String = "5000000") -> S.Quote {
    S.Quote(sellAmount: amount, buyAmount: "200", minimumBuy: "100", route: tokenRoute, calls: calls)
}
let ok = S.checked(q(tokenCalls), sell: usdc, amount: "5000000", chainId: 8453)
check(ok?.approvals.count == 1 && ok?.approvals[0].spender == base.venues[0].router && ok?.approvals[0].amount == "5000000" && ok?.calls.count == 1,
      "selling a token is not one exact approval to the router that swaps it, then one call")
var wide = tokenCalls; wide[0] = S.Call(to: wide[0].to, value: "0", data: S.approveSelector + YourAccount.w(base.venues[0].router) + SafeABI.word(uint256: "5000001")!)
check(S.checked(q(wide), sell: usdc, amount: "5000000", chainId: 8453) == nil, "an approval for more than is sold passes")
var elsewhere = tokenCalls; elsewhere[0] = S.Call(to: elsewhere[0].to, value: "0", data: S.approveSelector + YourAccount.w(base.venues[1].router) + SafeABI.word(uint256: "5000000")!)
check(S.checked(q(elsewhere), sell: usdc, amount: "5000000", chainId: 8453) == nil, "an approval to a router that does not swap it passes")
var stranger = tokenCalls; stranger[1] = S.Call(to: "0x000000000000000000000000000000000000dead", value: "0", data: stranger[1].data)
check(S.checked(q(stranger), sell: usdc, amount: "5000000", chainId: 8453) == nil, "a call to an unpinned contract passes")
var valued = tokenCalls; valued[1] = S.Call(to: valued[1].to, value: "1", data: valued[1].data)
check(S.checked(q(valued), sell: usdc, amount: "5000000", chainId: 8453) == nil, "ETH leaves with a token sale")
check(S.checked(q(tokenCalls + [tokenCalls[1]]), sell: usdc, amount: "5000000", chainId: 8453) == nil, "two swap calls pass")
check(S.checked(q(Array(tokenCalls.suffix(1))), sell: usdc, amount: "5000000", chainId: 8453) == nil, "a token sale with no approval passes")
check(S.checked(q(tokenCalls), sell: usdc, amount: "4999999", chainId: 8453) == nil, "a quote for another amount passes")
let ethRoute = S.Route(venue: base.venues[0], hops: [S.Hop(from: base.weth, to: usdc.contract!.lowercased(), step: 500)])
let ethCalls = S.calls(ethRoute, in: base, sellsETH: true, buysETH: false, amount: "1000", minimum: "1", account: account, deadline: deadline)!
check(ethCalls.count == 1 && ethCalls[0].value == "1000", "selling ETH is not one call carrying exactly the amount sold")
let ethQ = S.Quote(sellAmount: "1000", buyAmount: "2", minimumBuy: "1", route: ethRoute, calls: [S.Call(to: ethCalls[0].to, value: "1001", data: ethCalls[0].data)])
check(S.checked(ethQ, sell: YourAccountOp.eth, amount: "1000", chainId: 8453) == nil, "selling ETH sends more than is sold")
check(S.calls(S.Route(venue: base.venues[0], hops: [S.Hop(from: aero, to: usdc.contract!.lowercased(), step: 500)]), in: base,
              sellsETH: true, buysETH: false, amount: "1", minimum: "1", account: account, deadline: deadline) == nil,
      "ETH sold into a route that does not start at WETH was written")
check(S.calls(tokenRoute, in: base, sellsETH: false, buysETH: true, amount: "1", minimum: "1", account: account, deadline: deadline) == nil,
      "ETH bought from a route that does not end at WETH was written")
let summed = S.approvalCalls([(usdc.contract!.lowercased(), base.venues[0].router, "100000"), (usdc.contract!.lowercased(), base.venues[0].router, "250000")])!
check(summed.count == 1 && summed[0].data == S.approveSelector + YourAccount.w(base.venues[0].router) + SafeABI.word(uint256: "350000")!,
      "two swaps selling one token through one router approve their sum once (an approval replaces, never adds)")

// ── The minimum ──────────────────────────────────────────────────────────
check(S.minimum("1000000", bps: 50) == "995000", "0.5% under 1000000 is not 995000")
check(S.minimum("999", bps: 30) == "996", "0.3% under 999 is not 996, rounded down")
check(S.minimum("123456789012345678901234567890", bps: 50) == "122839505067283950506728395050", "a 30-digit quote loses digits")
check(S.minimum("0", bps: 50) == nil && S.minimum("5", bps: 10_000) == nil, "a zero quote or a 100% limit gives a minimum")

// ── Asking: the rounds, a real answer, the best route ────────────────────
let agg = fixture["aggregate"] as! [String: Any]
let asks = S.firstRound(base, sell: agg["sell"] as! String, buy: agg["buy"] as! String, amount: agg["amount"] as! String)
check(asks.count == 21, "WETH for USDC on Base does not ask the 21 pools (4 Uniswap, 3 × 5 Slipstream, 2 v2): \(asks.count)")
let request = S.aggregate3(asks.compactMap(\.call))
check(SafeABI.hex(request) == agg["request"] as! String, "the aggregate3 request is not the bytes Base answered")
let answers = S.aggregate3Results(SafeABI.hexBytes(agg["answer"] as! String)!)
check(answers?.count == asks.count, "the aggregate3 answer does not read as one answer per question")
let outs = zip(asks, answers ?? []).map { S.amountOut($0.venue.kind, ok: $1.ok, data: $1.data) }
let wantOuts = (agg["outs"] as! [Any]).map { $0 as? String }
check(outs == wantOuts, "the amounts read off Base's answer are not the independent decoder's: \(outs)")
check(S.aggregate3Results(Array(SafeABI.hexBytes(agg["answer"] as! String)!.dropLast(1))) == nil, "a cut answer reads as whole")
let priced = S.priced(asks, answers: outs, buy: agg["buy"] as! String)
let top = wantOuts.compactMap { $0 }.max { YourAccountOp.atMost($0, $1) && $0 != $1 }
check(S.best(priced, in: base)?.out == top, "the best route is not the most paid")
check(S.secondRound(asks, answers: outs, buy: agg["buy"] as! String).isEmpty, "a swap between the two hubs asked a second round")

// Hubs and two pools: USDC → AERO goes through WETH on every venue.
let first = S.firstRound(base, sell: usdc.contract!, buy: aero, amount: "1000")
check(first.count == 42, "USDC for AERO does not ask every pool straight across and into WETH (21 × 2): \(first.count)")
check(first.allSatisfy { $0.hop.from == usdc.contract!.lowercased() }, "a token is not lowercased before it is compared")
var fake = first.map { _ -> String? in nil }
for (i, a) in first.enumerated() where a.hop.to == base.weth { fake[i] = a.venue.kind == .uniswap ? "70" : "60" }
for (i, a) in first.enumerated() where a.hop.to == aero && a.venue.kind == .aerodromeV2 { fake[i] = "150" }
fake[first.firstIndex { $0.venue.kind == .uniswap && $0.hop.to == base.weth && $0.hop.step == 500 }!] = "80"
let second = S.secondRound(first, answers: fake, buy: aero)
check(second.count == 21 && second.allSatisfy { $0.hops.count == 2 && $0.hop.from == base.weth && $0.hop.to == aero },
      "the second round is not every pool on from WETH, on every venue that reached it")
let uniLeg = second.first { $0.venue.kind == .uniswap }!
check(uniLeg.amount == "80" && uniLeg.hops[0].step == 500, "the second round does not go on from the best pool into the hub, for what it paid")
var secondOuts = second.map { _ -> String? in "100" }
secondOuts[second.firstIndex { $0.venue.kind == .slipstream }!] = "151"
let routes = S.priced(first, answers: fake, buy: aero) + S.priced(second, answers: secondOuts, buy: aero)
check(S.best(routes, in: base)?.route.hops.count == 2 && S.best(routes, in: base)?.out == "151", "two pools paying more did not win")
secondOuts = second.map { _ in "150" }
let tied = S.priced(first, answers: fake, buy: aero) + S.priced(second, answers: secondOuts, buy: aero)
check(S.best(tied, in: base)?.route.hops.count == 1, "a tie went to two pools over one")
let tieOne = [S.Priced(route: S.Route(venue: base.venues[4], hops: [S.Hop(from: "a", to: "b", step: 0)]), out: "9"),
              S.Priced(route: S.Route(venue: base.venues[0], hops: [S.Hop(from: "a", to: "b", step: 500)]), out: "9")]
check(S.best(tieOne, in: base)?.route.venue.kind == .uniswap, "a tie did not go to the book's order")
check(S.best([S.Priced(route: tieOne[0].route, out: "10"), S.Priced(route: tieOne[1].route, out: "9")], in: base)?.out == "10",
      "a longer number lost to a shorter one")

// ── Each pool's fee, in words ────────────────────────────────────────────
check(S.percent(pips: 100) == "0.01%" && S.percent(pips: 500) == "0.05%" && S.percent(pips: 3000) == "0.3%"
      && S.percent(pips: 10000) == "1%", "a pool fee is not said as its percentage")
// Rounded for reading (prd §1545): two places at most, trailing zeros
// trimmed, under a hundredth of a percent said so; the route keeps the exact fee.
check(S.percent(pips: 773) == "0.08%" && S.percent(pips: 675) == "0.07%" && S.percent(pips: 3050) == "0.31%"
      && S.percent(pips: 2999) == "0.3%" && S.percent(pips: 10049) == "1%",
      "a pool fee is not rounded to two places, zeros trimmed: \(S.percent(pips: 773)), \(S.percent(pips: 675)), \(S.percent(pips: 2999))")
check(S.percent(pips: 80) == "under 0.01%" && S.percent(pips: 99) == "under 0.01%" && S.percent(pips: 0) == "under 0.01%",
      "a fee under 0.01% is not said as under it: \(S.percent(pips: 80)), \(S.percent(pips: 99))")
check(S.words(tokenRoute) == "On Uniswap · 0.3% pool fee", "one Uniswap pool is not said with its tier: \(S.words(tokenRoute))")
var aeroRoute = S.Route(venue: base.venues[1], hops: [S.Hop(from: "a", to: "b", step: 100)])
check(S.words(aeroRoute) == "On Aerodrome", "a Slipstream pool whose fee was not read is not the exchange alone")
aeroRoute.fees = [150]
check(S.words(aeroRoute) == "On Aerodrome · 0.02% pool fee", "a Slipstream pool's own fee is not said, rather than its spacing: \(S.words(aeroRoute))")
aeroRoute.fees = [80]
check(S.words(aeroRoute) == "On Aerodrome · under 0.01% pool fee", "a pool under 0.01% is not said so on the foot: \(S.words(aeroRoute))")
check(aeroRoute.fees == [80], "rounding the words changed the route's fee")
aeroRoute.fees = [150]
let two = S.Route(venue: base.venues[0], hops: [S.Hop(from: "a", to: "b", step: 100), S.Hop(from: "b", to: "c", step: 3000)])
check(S.words(two) == "On Uniswap · 0.01% and 0.3% pool fees", "two pools are not both named: \(S.words(two))")
// Details' row (prd §1556): the exchange and the fees, one line.
check(S.brief(tokenRoute) == "Uniswap · 0.3%" && S.brief(two) == "Uniswap · 0.01% + 0.3%"
      && S.brief(aeroRoute) == "Aerodrome · 0.02%" && S.brief(S.Route(venue: base.venues[1], hops: [S.Hop(from: "a", to: "b", step: 100)])) == "Aerodrome",
      "Details' swap row is not the exchange and its fees alone: \(S.brief(two))")
check(S.credit([tokenRoute, tokenRoute]) == "On Uniswap · 0.3% pool fee" && S.credit([tokenRoute, aeroRoute]) == "On Uniswap and Aerodrome"
      && S.credit([]) == nil, "the foot's credit does not name the exchanges")
check(S.fee(base.venues[4], answer: YourAccount.w(30)) == 3000 && S.fee(base.venues[1], answer: YourAccount.w(80)) == 80,
      "v2's basis points or Slipstream's millionths are misread")
check(S.pool(fromAnswer: YourAccount.w(0)) == nil, "the zero address reads as a pool")

// ── The open token list ──────────────────────────────────────────────────
let list = #"{"tokens":[{"chainId":8453,"address":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","symbol":"USDC","name":"USD Coin","decimals":6,"logoURI":"https://assets.coingecko.com/x.png"},{"chainId":8453,"address":"0x833589fcd6edb6e08f4c7c32d4f71b54bda02913","symbol":"USDC","name":"dup","decimals":6},{"chainId":8453,"address":"0x1234","symbol":"BAD","name":"short","decimals":18},{"chainId":8453,"address":"0x940181a94A35A4569E4529A3CDfB74e38FD98631","symbol":"AERO","name":"Aerodrome","decimals":99},{"chainId":10,"address":"0x940181a94A35A4569E4529A3CDfB74e38FD98631","symbol":"OP","name":"other chain","decimals":18},{"chainId":4663,"address":"0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168","symbol":"USDG","name":"Global Dollar","decimals":6,"logoURI":"ipfs://x"}]}"#
let parsed = OpenTokenList.parse(Data(list.utf8), chains: [8453, 1, 4663])
check(parsed[8453]?.map(\.symbol) == ["USDC"], "the list kept a duplicate, a malformed address or wild decimals: \(parsed[8453]?.map(\.symbol) ?? [])")
check(parsed[8453]?.first?.address == "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913" && parsed[8453]?.first?.logo == "https://assets.coingecko.com/x.png",
      "a listed token's address is not lowercased, or its logo dropped")
check(parsed[10] == nil && parsed[4663]?.first?.logo == nil, "another network's token, or a non-https logo, was kept")
check(OpenTokenList.search(parsed[8453]!, "usd").count == 1 && OpenTokenList.search(parsed[8453]!, "0x833589FCD6EDB6E08F4C7C32D4F71B54BDA02913").count == 1
      && OpenTokenList.search(parsed[8453]!, "aero").isEmpty, "the list's search does not find by symbol, name or address")

// ── Round-ups on the exchanges (prd §1545) ───────────────────────────────
let ruETH = RoundUps.Target.ethOnBase
let ruBTC = RoundUps.Target(chainId: 8453, address: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf", symbol: "cbBTC", decimals: 8, network: "Base")
let ruMAG7 = RoundUps.Target(chainId: 4663, address: "0x152f7613f362Abf1C05DB2EF2D6ef220302bf840", symbol: "MAG7", decimals: 18, network: "Robinhood Chain")
check(ruETH.onExchanges(from: 8453) && ruBTC.onExchanges(from: 8453) && !ruMAG7.onExchanges(from: 8453) && !ruETH.onExchanges(from: 1),
      "a round-up on the send's own network is not the exchanges', or one elsewhere is")
check(!RoundUps.sessionCarries(ruETH, from: 8453) && !RoundUps.sessionCarries(ruBTC, from: 8453) && RoundUps.sessionCarries(ruMAG7, from: 8453),
      "the session key may buy on the exchanges, or may no longer carry Relay's transfer to another network")
check(ruETH.contract == nil && ruBTC.contract == "0xcbb7c0000ab88b473b1f5afd9ef808440eed33bf",
      "a round-up's token is not the account's own spelling (nil for ETH, the contract lowercased)")
let ruBuys = RoundUps.plan(dollarSent: "4300000", saved: "4500000", step: 1)
let ruUnder = RoundUps.plan(dollarSent: "4300000", saved: "3400000", step: 1)
check(RoundUps.savedAfter(ruBuys, bought: true) == "0" && RoundUps.savedAfter(ruBuys, bought: false) == "5200000",
      "a send that did not buy emptied the count, or one that did kept it")
check(RoundUps.savedAfter(ruUnder, bought: true) == "4100000" && RoundUps.savedAfter(ruUnder, bought: false) == "4100000",
      "a send under $5 does not count its change either way")
let ruAt = Date(timeIntervalSince1970: 1_800_000_000)
let ruMe = "0xaaaa000000000000000000000000000000000001"
let ruUSDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
let ruNote = RoundUps.SwapBuy(account: ruMe, network: "base-mainnet", dollar: ruUSDC, units: "5200000", target: ruETH, at: ruAt)
typealias RL = RoundUps.Leg
func ruLegs(_ late: TimeInterval = 90) -> [RL] {
    [RL(id: "friend", received: false, contract: ruUSDC, value: 4.3, at: ruAt.addingTimeInterval(late)),
     RL(id: "pool", received: false, contract: ruUSDC, value: 5.2, at: ruAt.addingTimeInterval(late)),
     RL(id: "dust", received: true, contract: nil, value: 0.00001, at: ruAt.addingTimeInterval(late)),
     RL(id: "eth", received: true, contract: nil, value: 0.0022, at: ruAt.addingTimeInterval(late)),
     RL(id: "usdc-in", received: true, contract: ruUSDC, value: 9, at: ruAt.addingTimeInterval(late))]
}
let ruHit = RoundUps.swapBuy(ruLegs(), wallet: ruMe.uppercased().replacingOccurrences(of: "0X", with: "0x"), network: "base-mainnet", buys: [ruNote])
check(ruHit?.sent == "pool" && ruHit?.filled == "eth" && ruHit?.buy == ruNote,
      "the buy's dollar leg and the token it bought are not found in its transaction: \(String(describing: ruHit))")
check(RoundUps.swapBuy(ruLegs().filter { $0.id != "eth" && $0.id != "dust" }, wallet: ruMe, network: "base-mainnet", buys: [ruNote])?.filled == nil
      && RoundUps.swapBuy(ruLegs().filter { $0.id != "eth" && $0.id != "dust" }, wallet: ruMe, network: "base-mainnet", buys: [ruNote])?.sent == "pool",
      "a buy whose fill has not landed yet is not still known by its dollar leg")
check(RoundUps.swapBuy(ruLegs(), wallet: "0xbbbb000000000000000000000000000000000002", network: "base-mainnet", buys: [ruNote]) == nil,
      "another wallet's send reads as this account's buy")
check(RoundUps.swapBuy(ruLegs(), wallet: ruMe, network: "eth-mainnet", buys: [ruNote]) == nil, "a send on another network reads as the buy")
check(RoundUps.swapBuy(ruLegs().filter { $0.id != "pool" }, wallet: ruMe, network: "base-mainnet", buys: [ruNote]) == nil,
      "a send of another amount reads as the buy")
check(RoundUps.swapBuy(ruLegs(25 * 3600), wallet: ruMe, network: "base-mainnet", buys: [ruNote]) == nil
      && RoundUps.swapBuy(ruLegs(-11 * 60), wallet: ruMe, network: "base-mainnet", buys: [ruNote]) == nil,
      "a send long after the note, or well before it, reads as the buy")
check(RoundUps.swapBuy(ruLegs(23 * 3600), wallet: ruMe, network: "base-mainnet", buys: [ruNote])?.sent == "pool"
      && RoundUps.swapBuy(ruLegs(-5 * 60), wallet: ruMe, network: "base-mainnet", buys: [ruNote])?.sent == "pool",
      "a buy landing inside its window is not known")
check(RoundUps.swapBuy(ruLegs(), wallet: ruMe, network: "base-mainnet", buys: []) == nil, "with nothing noted, a send reads as a buy")
let ruBTCNote = RoundUps.SwapBuy(account: ruMe, network: "base-mainnet", dollar: ruUSDC, units: "5200000", target: ruBTC, at: ruAt)
check(RoundUps.swapBuy(ruLegs(), wallet: ruMe, network: "base-mainnet", buys: [ruBTCNote])?.filled == nil,
      "ETH that arrived is taken as the cbBTC the buy was for")

// ── Round-ups into your private balance (prd §1561) ───────────────────────
// Only where a pool is: a send elsewhere sets nothing aside for it; the
// change moves together at the threshold, never per send; a deposit is a
// contract call, so the spend limit's session key never carries one.
var ruPriv = RoundUps.Setting(on: true)
ruPriv.toPrivate = true
let ruPools: Set<Int> = [11155111]
check(RoundUps.privatePools == [1], "a shipped build offers private round-ups somewhere other than Ethereum (prd §1567)")
// On Ethereum the change is dollars, moved as USDC into ppUSDC once it reaches
// $5 and the pool's smallest deposit, read live; unread, it keeps counting.
check(RoundUps.privateMoveAt(on: 1, poolMinimum: "10046461") == "10046461", "Ethereum's round-ups move under ppUSDC's minimum")
check(RoundUps.privateMoveAt(on: 1, poolMinimum: "1000000") == "5000000", "Ethereum's round-ups move under $5")
check(RoundUps.privateMoveAt(on: 1, poolMinimum: nil) == nil, "round-ups move before the pool's minimum is read")
check(RoundUps.privateMoveAt(on: 11155111, poolMinimum: nil) == RoundUps.privateMoveAt, "a test network's threshold is not its coin's")
let ruEth = RoundUps.privatePlan(dollarSent: "4300000", saved: "9900000", step: 1, threshold: "10046461")
check(ruEth.change == "700000" && ruEth.buy == "10600000" && ruEth.savedAfter == "0", "a $4.30 send that reaches the minimum does not move the whole count")
let ruEthWait = RoundUps.privatePlan(dollarSent: "4300000", saved: "2000000", step: 1, threshold: "10046461")
check(ruEthWait.buy == nil && ruEthWait.savedAfter == "2700000", "the change moves before the minimum (one deposit a send)")
check(RoundUps.privatePlan(dollarSent: "4300000", saved: "99000000", step: 1, threshold: nil).buy == nil, "it moves with no minimum read")
check(RoundUps.movesPrivately(ruPriv, pools: ruPools) && !RoundUps.movesPrivately(ruPriv, pools: [])
      && !RoundUps.movesPrivately(RoundUps.Setting(on: true), pools: ruPools), "moving privately is the pick, where a pool is")
check(RoundUps.applies(ruPriv, on: 11155111, pools: ruPools) && !RoundUps.applies(ruPriv, on: 8453, pools: ruPools),
      "moving privately, a send on a network with no pool still sets change aside")
check(RoundUps.applies(RoundUps.Setting(on: true), on: 8453, pools: ruPools) && !RoundUps.applies(RoundUps.Setting(), on: 8453, pools: ruPools)
      && RoundUps.applies(ruPriv, on: 8453, pools: []), "buying a token, round-ups run as they did")
check(RoundUps.privateRoute(on: 11155111, bySession: false, pools: ruPools) == .deposit, "a Face ID send does not carry the deposit")
check(RoundUps.privateRoute(on: 11155111, bySession: true, pools: ruPools) == .waits, "the session key carries a deposit (a contract call)")
check(RoundUps.privateRoute(on: 8453, bySession: false, pools: ruPools) == .notHere, "a deposit is routed to a network with no pool")
check(RoundUps.privateMove(saved: "120000000000000", at: "100000000000000") == "120000000000000", "the counted change does not move whole at the threshold")
check(RoundUps.privateMove(saved: "90000000000000", at: "100000000000000") == nil, "the change moves before the threshold (one deposit a send)")
check(RoundUps.privateMove(saved: "0", at: "0") == nil && RoundUps.privateMove(saved: "x", at: "1") == nil, "nothing moves nothing")
let ruKept = try! JSONDecoder().decode(RoundUps.Setting.self, from: JSONEncoder().encode(RoundUps.Setting(on: true, step: 5)))
check(ruKept.toPrivate == nil && !RoundUps.movesPrivately(ruKept, pools: ruPools), "a setting kept before moving privately decodes as private")

// ── Swaps and Buy round up too (prd §1561) ────────────────────────────────
// A swap rounds up the dollar value of what it sells; it carries the buy only
// when it sells the dollar (the buy spends the dollar); a Buy only counts.
check(RoundUps.carriesBuy(.send) && RoundUps.carriesBuy(.swap(sellsDollar: true)), "a send or a dollar swap does not carry the buy")
check(!RoundUps.carriesBuy(.swap(sellsDollar: false)), "a swap of ETH carries a buy that spends a dollar it may not hold")
check(!RoundUps.carriesBuy(.buy), "a Bitrefill purchase carries a call of ours")
check(RoundUps.soldUnits(usd: 3.40, wrap: false) == "3400000" && RoundUps.soldUnits(usd: 12.3456789, wrap: false) == "12345678",
      "what a swap sells is not its dollars in the dollar's units")
check(RoundUps.soldUnits(usd: 3.40, wrap: true) == nil, "WETH to ETH rounds up")
check(RoundUps.soldUnits(usd: nil, wrap: false) == nil && RoundUps.soldUnits(usd: 0, wrap: false) == nil
      && RoundUps.soldUnits(usd: .nan, wrap: false) == nil, "a token with no price rounds up")
let ruSwap = RoundUps.plan(dollarSent: RoundUps.soldUnits(usd: 41.38, wrap: false)!, saved: "0", step: 1)
check(ruSwap.change == "620000" && ruSwap.buy == nil && ruSwap.savedAfter == "620000", "a $41.38 swap does not set aside $0.62")

// ── WETH and ETH, one for one (prd §1559) ─────────────────────────────────
// Every vector written by the independent encoder and simulated from the
// account made a real SafeL2 proxy: deposit() wraps; the WETH's transfer to
// SwapRouter02 and its unwrapWETH9 unwrap, paying exactly the amount — and
// a direct withdraw from the same cold Safe reverts, which is why.
let wrapFixture = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/wrap.json"))) as! [String: Any]
let wrapAccount = wrapFixture["account"] as! String
func wcalls(_ list: Any?) -> [S.Call] {
    (list as! [[String: Any]]).map { S.Call(to: $0["to"] as! String, value: $0["value"] as! String, data: SafeABI.hexBytes($0["data"] as! String)!) }
}
for v in wrapFixture["vectors"] as! [[String: Any]] {
    let chain = v["chainId"] as! Int, amount = v["amount"] as! String
    let weth = YourAccountOp.Token(symbol: "WETH", decimals: 18, contract: S.book(chain)!.weth)
    check((v["statuses"] as! [String]).allSatisfy { $0 == "0x1" } && v["ethGained"] as? String == amount
          && v["wethGained"] as? String == amount && v["directWithdrawStatus"] as? String == "0x0",
          "the wrap vectors on \(chain) were not simulated as the fixture says")
    let unwrap = wcalls(v["unwrap"]), wrapped = wcalls(v["wrap"])
    check(S.wrap(sell: weth, buy: YourAccountOp.eth, chainId: chain) == .unwrap && S.wrap(sell: YourAccountOp.eth, buy: weth, chainId: chain) == .wrap,
          "WETH and ETH on \(chain) are not a wrap and an unwrap")
    check(S.wrapCalls(.unwrap, amount: amount, account: wrapAccount, chainId: chain) == unwrap,
          "the unwrap on \(chain) is not the independent encoder's bytes")
    check(S.wrapCalls(.wrap, amount: amount, account: wrapAccount, chainId: chain) == wrapped,
          "the wrap on \(chain) is not the independent encoder's bytes")
    let uq = S.wrapQuote(.unwrap, amount: amount, account: wrapAccount, chainId: chain)!
    check(uq.buyAmount == amount && uq.minimumBuy == amount && uq.route == nil && uq.wrap == .unwrap,
          "an unwrap is not exactly what is sold, one for one")
    check(S.checkedWrap(uq, sell: weth, buy: YourAccountOp.eth, amount: amount, account: wrapAccount, chainId: chain) == unwrap,
          "the check refuses the simulated unwrap on \(chain)")
    let wq = S.wrapQuote(.wrap, amount: amount, account: wrapAccount, chainId: chain)!
    check(S.checkedWrap(wq, sell: YourAccountOp.eth, buy: weth, amount: amount, account: wrapAccount, chainId: chain) == wrapped,
          "the check refuses the simulated wrap on \(chain)")
    // Tampered, each refused.
    func refused(_ q: S.Quote, _ sell: YourAccountOp.Token, _ buy: YourAccountOp.Token, _ what: String) {
        check(S.checkedWrap(q, sell: sell, buy: buy, amount: amount, account: wrapAccount, chainId: chain) == nil, "taken: \(what) on \(chain)")
    }
    var q = uq; q = S.Quote(sellAmount: amount, buyAmount: amount, minimumBuy: amount, route: nil,
                            calls: [unwrap[0], S.Call(to: unwrap[1].to, value: "0", data: Array(unwrap[1].data.prefix(36)) + YourAccount.w("0x1111111111111111111111111111111111111111"))], wrap: .unwrap)
    refused(q, weth, YourAccountOp.eth, "an unwrap paying someone else")
    q = S.Quote(sellAmount: amount, buyAmount: amount, minimumBuy: amount, route: nil,
                calls: [S.Call(to: unwrap[0].to, value: "0", data: Array(unwrap[0].data.prefix(16)) + Array(YourAccount.w("0x1111111111111111111111111111111111111111").suffix(20)) + Array(unwrap[0].data.suffix(32))), unwrap[1]], wrap: .unwrap)
    refused(q, weth, YourAccountOp.eth, "the WETH sent to an unpinned contract")
    q = S.Quote(sellAmount: amount, buyAmount: amount, minimumBuy: amount, route: nil, calls: [unwrap[1]], wrap: .unwrap)
    refused(q, weth, YourAccountOp.eth, "an unwrap of WETH never sent to the router")
    q = S.Quote(sellAmount: amount, buyAmount: amount, minimumBuy: amount, route: nil,
                calls: [unwrap[0], S.Call(to: unwrap[1].to, value: "1", data: unwrap[1].data)], wrap: .unwrap)
    refused(q, weth, YourAccountOp.eth, "ETH sent with an unwrap")
    q = S.Quote(sellAmount: amount, buyAmount: amount, minimumBuy: amount, route: nil,
                calls: [S.Call(to: wrapped[0].to, value: "1", data: wrapped[0].data)], wrap: .wrap)
    refused(q, YourAccountOp.eth, weth, "a wrap sending another amount")
    refused(wq, YourAccountOp.eth, YourAccountOp.dollar(on: S.book(chain)!.chainId == 1 ? YourAccountOp.ethereum : YourAccountOp.base), "a wrap for another token")
    refused(S.Quote(sellAmount: amount, buyAmount: "1", minimumBuy: "1", route: nil, calls: unwrap, wrap: .unwrap), weth, YourAccountOp.eth,
            "an unwrap promising less than is sold")
}
check(S.wrap(sell: YourAccountOp.dollar(on: YourAccountOp.base), buy: YourAccountOp.eth, chainId: 8453) == nil
      && S.wrap(sell: YourAccountOp.Token(symbol: "WETH", decimals: 18, contract: S.ethereum.weth), buy: YourAccountOp.eth, chainId: 8453) == nil,
      "a token other than this network's WETH is wrapped")
check(S.words(S.Wrap.unwrap) == "Unwraps WETH · no fee" && S.words(S.Wrap.wrap) == "Wraps ETH · no fee", "the wrap's words moved")
check(S.unwrapper(8453) == base.venues[0].router, "the unwrap does not go through Base's pinned SwapRouter02")
exit(bad == 0 ? 0 : 1)
SWIFT

SOURCES=("$ACROSS" "$ACCOUNT" "$OP" "$ADAPTER" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" "$TMP/demo-stub.swift")
echo "direct-swap-selftest: compiling YourAccountSwap.swift and OpenTokenList.swift AS SHIPPED…"
xcrun swiftc -Onone -o "$TMP/run" "Casberi/Shared/AddressTail.swift" "$SWAP" "$LIST" "${SOURCES[@]}" "$TMP/main.swift" 2>"$TMP/err" \
  || { cat "$TMP/err"; echo "✗ YourAccountSwap.swift does not compile alone (Foundation and the account's encoders only)"; exit 1; }
FIXTURES="$FIXTURES" "$TMP/run" || { echo "✗ the direct swap drifted — see above"; exit 1; }
echo "  ok   assertions pass"

# --- the mutation pass ------------------------------------------------------
# A check that cannot fail proves nothing. Each of these is a swap that looks
# normal and signs something it should not.
mutate() {
  local name="$1" file="$2" from="$3" to="$4"
  local target="$TMP/mut-$(basename "$file")"
  cp "$file" "$target"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  local swap="$SWAP" list="$LIST"
  local -a sources=("${SOURCES[@]}")
  [[ "$file" == "$SWAP" ]] && swap="$target"
  [[ "$file" == "$LIST" ]] && list="$target"
  [[ "$file" == "$ROUNDUPS" ]] && sources=("${SOURCES[@]/$ROUNDUPS/$target}")
  if ! xcrun swiftc -Onone -o "$TMP/mut" "Casberi/Shared/AddressTail.swift" "$swap" "$list" "${sources[@]}" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if FIXTURES="$FIXTURES" "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

echo ""
echo "Mutations — each is a swap that looks normal:"
mutate "a router address typo'd in the book" "$SWAP" \
  'router: "0x2626664c2603336e57b271c5c0b26f421741e481"' 'router: "0x2626664c2603336e57b271c5c0b26f421741e482"'
mutate "the check stops asking whether a call's contract is pinned" "$SWAP" \
  'guard pinned.contains(call.to.lowercased()) else { return nil }' 'guard !call.to.isEmpty else { return nil }'
mutate "the check takes an approval to any pinned router" "$SWAP" \
  'guard approvals.count == 1, approvals[0].1 == calls[0].to.lowercased() else { return nil }' 'guard approvals.count == 1 else { return nil }'
mutate "the check stops reading the approved amount" "$SWAP" \
  'SafeCalldata.decimal(Array(call.data[36..<68])) == amount else { return nil }' 'call.data.count > 0 else { return nil }'
mutate "ETH may leave with any value" "$SWAP" \
  'guard call.value == (sell.contract == nil ? amount : "0") else { return nil }' 'guard !call.value.isEmpty else { return nil }'
mutate "two swap calls pass as one" "$SWAP" \
  'guard calls.count == 1 else { return nil }' 'guard !calls.isEmpty else { return nil }'
mutate "the minimum keeps the whole quote" "$SWAP" \
  'return divided(times(quoted, 10_000 - bps), by: 10_000)' 'return divided(times(quoted, 10_000), by: 10_000)'
mutate "the minimum rounds up" "$SWAP" \
  'out.append(Character(String(cur / n)))' 'out.append(Character(String((cur + n - 1) / n)))'
mutate "ETH bought is paid to the account as WETH, never unwrapped" "$SWAP" \
  'let to = buysETH ? router02Itself : account' 'let to = account'
mutate "Slipstream's unwrap pays the router nothing" "$SWAP" \
  'let to = buysETH ? router : account' 'let to = account'
mutate "the deadline is dropped from Uniswap's call" "$SWAP" \
  'data = call("multicall(uint256,bytes[])", [.uint(deadline), .array(inner)])' 'data = call("multicall(uint256,bytes[])", [.uint(0), .array(inner)])'
mutate "the approval is written for the minimum, not the amount" "$SWAP" \
  'approveSelector + YourAccount.w(router) + SafeABI.word(uint256: amount)!' 'approveSelector + YourAccount.w(router) + SafeABI.word(uint256: minimum)!'
mutate "a multi-pool path loses its fee bytes' order" "$SWAP" \
  'out += [UInt8(step >> 16 & 0xFF), UInt8(step >> 8 & 0xFF), UInt8(step & 0xFF)]' 'out += [UInt8(step & 0xFF), UInt8(step >> 8 & 0xFF), UInt8(step >> 16 & 0xFF)]'
mutate "a dynamic value's offset counts from the wrong place" "$SWAP" \
  'head += YourAccount.w(headSize + tail.count)' 'head += YourAccount.w(tail.count)'
mutate "v2's stable flag is inverted" "$SWAP" \
  '.tuple([.address(h.from), .address(h.to), .uint(h.step == 1 ? 1 : 0), .address(venue.factory)])' '.tuple([.address(h.from), .address(h.to), .uint(h.step == 1 ? 0 : 1), .address(venue.factory)])'
mutate "the best route is the least paid" "$SWAP" \
  'if a.out != b.out { return !Op.atMost(a.out, b.out) }' 'if a.out != b.out { return Op.atMost(a.out, b.out) }'
mutate "a tie goes to two pools" "$SWAP" \
  'return a.route.hops.count < b.route.hops.count }' 'return a.route.hops.count > b.route.hops.count }'
mutate "the second round goes on from the worst pool into the hub" "$SWAP" \
  'if !Op.atMost(out, best[i].out) { best[i] = (ask.venue, ask.hop.to, ask, out) }' 'if Op.atMost(out, best[i].out) { best[i] = (ask.venue, ask.hop.to, ask, out) }'
mutate "the first round forgets the hubs" "$SWAP" \
  'let hubs = book.hubs.filter { $0 != s && $0 != b }' 'let hubs: [String] = []'
mutate "v2's answer is read as its first entry (what is sold)" "$SWAP" \
  'let last = word(data, at: offset + 32 * count) else { return nil }' 'let last = word(data, at: offset + 32) else { return nil }'
mutate "a cut multicall answer reads as whole" "$SWAP" \
  'bytesAt + 32 + length <= data.count else { return nil }' 'length >= 0 else { return nil }'
mutate "v2's fee is read as millionths" "$SWAP" \
  'let pips = venue.kind == .aerodromeV2 ? n * 100 : n' 'let pips = n'
mutate "the unwrap pays the router, not the account" "$SWAP" \
  'Call(to: router, value: "0", data: unwrapSelector + units + YourAccount.w(account))]' 'Call(to: router, value: "0", data: unwrapSelector + units + YourAccount.w(router))]'
mutate "the check takes an unwrap to anyone" "$SWAP" \
  'calls[1].data == unwrapSelector + units + YourAccount.w(account) else { return nil }' 'calls[1].data.starts(with: unwrapSelector) else { return nil }'
mutate "the unwrap is WETH's own withdraw (a Safe refuses its 2,300-gas transfer)" "$SWAP" \
  'return [Call(to: weth, value: "0", data: transferSelector + YourAccount.w(router) + units),' 'return [Call(to: weth, value: "0", data: [0x2e, 0x1a, 0x7d, 0x4d] + units),'
mutate "the wrap sends no ETH" "$SWAP" \
  'return [Call(to: weth, value: amount, data: depositSelector)]' 'return [Call(to: weth, value: "0", data: depositSelector)]'
mutate "the check takes a wrap promising less than is sold" "$SWAP" \
  'quote.buyAmount == amount, quote.minimumBuy == amount,' 'quote.buyAmount.count > 0,'
mutate "any token reads as this network's WETH" "$SWAP" \
  'if s == weth, b == nil { return .unwrap }' 'if s != nil, b == nil { return .unwrap }'
mutate "Details' swap row says the whole sentence again" "$SWAP" \
  'return name + " · " + fees.map { percent(pips: $0) }.joined(separator: " + ")' 'return words(route)'
mutate "Ethereum swaps with Base's looser slippage" "$SWAP" \
  '        slippageBps: 30)' '        slippageBps: 50)'
mutate "a pool fee said to four places again" "$SWAP" \
  'NSDecimalRound(&r, &d, 2, .plain)' 'NSDecimalRound(&r, &d, 4, .plain)'
mutate "a fee under 0.01% said as a rounded number" "$SWAP" \
  'guard pips >= 100 else { return String(localized: "under 0.01%") }' 'guard pips >= 0 else { return String(localized: "under 0.01%") }'
mutate "the session key buys on the exchanges" "$ROUNDUPS" \
  '        !target.onExchanges(from: chainId)' '        true'
mutate "a send that did not buy empties the count" "$ROUNDUPS" \
  'bought ? plan.savedAfter : (plan.buy ?? plan.savedAfter)' 'plan.savedAfter'
mutate "any send of the dollar reads as the buy" "$ROUNDUPS" \
  'abs(leg.value - want) < 0.000_000_5 else { return false }' 'leg.value > 0 else { return false }'
mutate "another wallet's send reads as the buy" "$ROUNDUPS" \
  'for buy in buys where buy.account == w && buy.network == network {' 'for buy in buys where buy.network == network {'
mutate "a buy's window never closes" "$ROUNDUPS" \
  'at <= buy.at.addingTimeInterval(swapBuyLate)' 'at <= .distantFuture'
mutate "any token that arrived is the buy's fill" "$ROUNDUPS" \
  'legs.filter { $0.received && $0.contract == buy.target.contract }' 'legs.filter { $0.received }'
mutate "a send the session key signs carries the private deposit" "$ROUNDUPS" \
  'return bySession ? .waits : .deposit' 'return .deposit'
mutate "the change moves into private per send" "$ROUNDUPS" \
  'have > 0, let need = Decimal(string: threshold), have >= need else' 'have > 0, let need = Decimal(string: threshold), need >= 0 else'
mutate "a mainnet send sets change aside for private" "$ROUNDUPS" \
  'setting.on && (!movesPrivately(setting, pools: pools) || pools.contains(chainId))' 'setting.on'
mutate "a shipped build offers private round-ups off Ethereum" "$ROUNDUPS" \
  $'#else\n        [ethereumPool]' $'#else\n        [ethereumPool, 8453]'
mutate "Ethereum's round-ups move under the pool's minimum" "$ROUNDUPS" \
  'return NSDecimalNumber(decimal: max(floor, five)).stringValue' 'return NSDecimalNumber(decimal: five).stringValue'
mutate "Ethereum's round-ups move per send" "$ROUNDUPS" \
  'if let threshold, YourAccountOp.atMost(threshold, total) {' 'if threshold != nil {'
mutate "a swap of ETH carries the buy" "$ROUNDUPS" \
  'case .swap(let sellsDollar): sellsDollar' 'case .swap: true'
mutate "a Bitrefill purchase carries the buy" "$ROUNDUPS" \
  $'        case .buy: false\n        }' $'        case .buy: true\n        }'
mutate "a wrap rounds up" "$ROUNDUPS" \
  'guard !wrap, let usd, usd.isFinite, usd > 0 else { return nil }' 'guard let usd, usd.isFinite, usd > 0 else { return nil }'
mutate "a swap's dollars are counted in cents" "$ROUNDUPS" \
  'let micro = (usd * 1_000_000).rounded(.down)' 'let micro = (usd * 100).rounded(.down)'
mutate "the list keeps a malformed address" "$LIST" \
  's.count == 42 && s.lowercased().hasPrefix("0x")' 's.lowercased().hasPrefix("0x")'
mutate "the list keeps any decimals" "$LIST" \
  '(0...36).contains(decimals) else { continue }' 'decimals >= 0 else { continue }'

echo ""
echo "direct-swap-selftest: OK — assertions pass and every mutation is caught."
