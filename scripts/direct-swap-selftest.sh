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
#
# Pure, local, deterministic — no network, no simulator, no key. Then every
# guard is proven to catch something: each mutation below breaks the shipped
# source one way, and the harness must fail.
set -euo pipefail
cd "$(dirname "$0")/.."

SWAP="Casberi/Casberi/Model/YourAccountSwap.swift"
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
      && S.percent(pips: 10000) == "1%" && S.percent(pips: 80) == "0.008%" && S.percent(pips: 675) == "0.0675%",
      "a pool fee is not said as its percentage")
check(S.words(tokenRoute) == "On Uniswap · 0.3% pool fee", "one Uniswap pool is not said with its tier: \(S.words(tokenRoute))")
var aeroRoute = S.Route(venue: base.venues[1], hops: [S.Hop(from: "a", to: "b", step: 100)])
check(S.words(aeroRoute) == "On Aerodrome", "a Slipstream pool whose fee was not read is not the exchange alone")
aeroRoute.fees = [150]
check(S.words(aeroRoute) == "On Aerodrome · 0.015% pool fee", "a Slipstream pool's own fee is not said, rather than its spacing")
let two = S.Route(venue: base.venues[0], hops: [S.Hop(from: "a", to: "b", step: 100), S.Hop(from: "b", to: "c", step: 3000)])
check(S.words(two) == "On Uniswap · 0.01% and 0.3% pool fees", "two pools are not both named: \(S.words(two))")
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
exit(bad == 0 ? 0 : 1)
SWIFT

SOURCES=("$ACCOUNT" "$OP" "$ADAPTER" "$TX" "$KECCAK" "$CLEARSIGN" "$WEBAUTHN" "$TYPED" "$ROUNDUPS" "$TMP/demo-stub.swift")
echo "direct-swap-selftest: compiling YourAccountSwap.swift and OpenTokenList.swift AS SHIPPED…"
xcrun swiftc -Onone -o "$TMP/run" "$SWAP" "$LIST" "${SOURCES[@]}" "$TMP/main.swift" 2>"$TMP/err" \
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
  [[ "$file" == "$SWAP" ]] && swap="$target"
  [[ "$file" == "$LIST" ]] && list="$target"
  if ! xcrun swiftc -Onone -o "$TMP/mut" "$swap" "$list" "${SOURCES[@]}" "$TMP/main.swift" 2>/dev/null; then
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
mutate "Ethereum swaps with Base's looser slippage" "$SWAP" \
  '        slippageBps: 30)' '        slippageBps: 50)'
mutate "the list keeps a malformed address" "$LIST" \
  's.count == 42 && s.lowercased().hasPrefix("0x")' 's.lowercased().hasPrefix("0x")'
mutate "the list keeps any decimals" "$LIST" \
  '(0...36).contains(decimals) else { continue }' 'decimals >= 0 else { continue }'

echo ""
echo "direct-swap-selftest: OK — assertions pass and every mutation is caught."
