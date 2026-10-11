#!/bin/zsh
# Casberi markets self-test — the rules behind Markets' watchlist and alerts
# (prd §1081):
#
#   Casberi/Casberi/Model/PriceAlert.swift  (compiled whole)
#   Casberi/Casberi/Model/WatchLine.swift   (compiled whole: the row's line)
#   Casberi/Casberi/Model/CoinFollow.swift  (compiled whole, prd §1247: a coin
#     by its own price, CoinPaprika's answers and the launch sweep's plan)
#   Casberi/Casberi/Model/GasPrice.swift    (compiled whole, prd §1247: gas)
#
# Since §1247 the alerts also hold: a custom move, a day volume, gas below a
# level, and the iCloud merge in which a fired alert beats a copy still on.
#
# WHY A HARNESS. Every failure here renders calmly. An alert that fires every
# read buzzes a phone all day; one that never fires is a promise broken in
# silence; a level that stays on after firing repeats itself on every refresh.
# A row whose line prefers the cap over your alert hides the one thing you
# asked to see; a heat map whose frames overlap or leave the box draws a
# perfectly plausible wrong board.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ALERT="Casberi/Casberi/Model/PriceAlert.swift"
LINE="Casberi/Casberi/Model/WatchLine.swift"
INDEX="Casberi/Casberi/Model/MarketsIndex.swift"
COIN="Casberi/Casberi/Model/CoinFollow.swift"
GAS="Casberi/Casberi/Model/GasPrice.swift"
for f in "$ALERT" "$LINE" "$INDEX" "$COIN" "$GAS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# The app uses them: the sweep checks alerts before it plans, a fired alert
# stands alone, and the room's rows and box read the two rules.
grep -q 'await PriceAlertStore.shared.check(context: context)' Casberi/Casberi/Model/WalletBackgroundRefresh.swift \
  || { echo "✗ the notify sweep no longer checks price alerts first — a crossing would wait a whole sweep"; exit 1; }
grep -q 'safeSignatureNeeded, .priceAlert:' Casberi/Casberi/Model/NotifyPlan.swift \
  || { echo "✗ a price alert no longer stands alone — the digest would deliver it hours late"; exit 1; }
grep -q 'WatchLine.pick(' Casberi/Casberi/Screens/FeedScreen+Markets.swift \
  || { echo "✗ the watchlist rows no longer pick their line through WatchLine"; exit 1; }
grep -q 'MarketsIndex.sections(' Casberi/Casberi/Screens/FeedScreen+Markets.swift \
  || { echo "✗ the index no longer splits into your apps, everything else and not traded"; exit 1; }
grep -q 'MarketsIndex.search(' Casberi/Casberi/Screens/WatchAddSheet.swift \
  || { echo "✗ Search no longer finds a company by an app it makes"; exit 1; }
grep -q 'PriceAlertStore.shared.removeAll(ref: ref)' Casberi/Casberi/Screens/FeedScreen+Markets.swift \
  || { echo "✗ unwatching no longer takes the row's alerts with it — they would fire for a row you cannot see"; exit 1; }
# §1247: the sweep runs every launch, the coin's sheet charts it, the alerts
# ride the merge, a household coin is followed as the coin wherever it is
# followed, and the index follows a coin by its id.
grep -q 'CoinWatch.converge(context: modelContext)' Casberi/Casberi/Shell/RootShell.swift \
  || { echo "✗ the coin sweep no longer runs at launch — old WBTC/wSOL follows would never converge (§647)"; exit 1; }
grep -q 'case .coin(let id):' Casberi/Casberi/Screens/ThingContent.swift \
  || { echo "✗ a followed coin's page no longer draws its chart"; exit 1; }
grep -q 'PriceAlert.merged(incoming, standing)' Casberi/Casberi/Model/MarketsAlerts.swift \
  || { echo "✗ the alert mirror no longer merges through PriceAlert.merged — a sync could re-arm a fired alert"; exit 1; }
grep -q 'CoinFollow.wrappedCoin(chain: token.chain, address: token.address)' Casberi/Casberi/Model/TokenWatch.swift \
  || { echo "✗ following WETH/WBTC/wSOL no longer follows the coin — the next launch's sweep would undo it"; exit 1; }
grep -q 'CoinWatch.add(id: id' Casberi/Casberi/Model/MarketsWatch.swift \
  || { echo "✗ the index follows a coin by a DEX symbol match again"; exit 1; }
grep -q 'await MarketsGas.shared.load()' Casberi/Casberi/Model/MarketsAlerts.swift \
  || { echo "✗ the alert check no longer reads gas — a gas alert would never fire"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$ALERT" "$LINE" "$INDEX" "$COIN" "$GAS" "$TMP/"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let now = Date(timeIntervalSince1970: 1_800_000_000)

// ── Alerts ───────────────────────────────────────────────────────────
let above = PriceAlert(ref: "r", name: "Pepe", kind: .above, target: 15)
check(!above.fires(price: 14.9, change24h: 0.5, now: now, calendar: cal), "above: under the level does not fire")
check(above.fires(price: 15, change24h: nil, now: now, calendar: cal), "above: at the level fires")
check(above.fires(price: 16, change24h: nil, now: now, calendar: cal), "above: past the level fires")
let fired = above.afterFiring(at: now)
check(!fired.on && fired.firedAt == now, "a level turns itself off once it fires")
check(!fired.fires(price: 20, change24h: nil, now: now, calendar: cal), "a level that fired stays quiet")

let below = PriceAlert(ref: "r", name: "Pepe", kind: .below, target: 10)
check(!below.fires(price: 10.1, change24h: nil, now: now, calendar: cal), "below: above the level does not fire")
check(below.fires(price: 9.9, change24h: nil, now: now, calendar: cal), "below: under the level fires")
check(!below.fires(price: 0, change24h: nil, now: now, calendar: cal), "a missing price (0) never fires")

let move = PriceAlert(ref: "r", name: "Pepe", kind: .move, target: 0.10)
check(!move.fires(price: 1, change24h: 0.09, now: now, calendar: cal), "move: under the size does not fire")
check(move.fires(price: 1, change24h: -0.12, now: now, calendar: cal), "move: a fall the size fires")
check(!move.fires(price: 1, change24h: nil, now: now, calendar: cal), "move: no day change, no claim")
let moved = move.afterFiring(at: now)
check(moved.on, "a move alert stays on")
check(!moved.fires(price: 1, change24h: 0.2, now: now.addingTimeInterval(3600), calendar: cal),
      "a move alert fires at most once a day")
check(moved.fires(price: 1, change24h: 0.2, now: now.addingTimeInterval(86_400), calendar: cal),
      "and again the next day")
var off = above; off.on = false
check(!off.fires(price: 99, change24h: nil, now: now, calendar: cal), "an alert switched off never fires")

let choices = PriceAlert.choices(ref: "r", name: "Pepe", price: 100)
check(choices.count == 4, "four choices from a price")
check(abs(choices[0].target - 110) < 1e-9 && choices[0].kind == .above, "10% above")
check(abs(choices[1].target - 125) < 1e-9, "25% above")
check(abs(choices[2].target - 90) < 1e-9 && choices[2].kind == .below, "10% below")
check(choices[3].kind == .move && abs(choices[3].target - 0.10) < 1e-9, "a 10% day move")
check(PriceAlert.choices(ref: "r", name: "x", price: 0).isEmpty, "no price, no choices")
check(abs((choices[0].distance(from: 100) ?? 0) - 0.10) < 1e-9, "a level's distance from now")
check(choices[3].distance(from: 100) == nil, "a move has no distance")

let data = try! JSONEncoder().encode([above, move])
let back = try! JSONDecoder().decode([PriceAlert].self, from: data)
check(back == [above, move], "alerts survive being stored")

// ── The row's one line ───────────────────────────────────────────────
check(WatchLine.pick(alertTarget: "$45", holding: "$2.3K", sinceWatched: 0.4, facts: "SOL") == .alert("$45"),
      "an alert you set leads")
check(WatchLine.pick(alertTarget: nil, holding: "$2.3K", sinceWatched: 0.4, facts: "SOL") == .holding("$2.3K"),
      "then what you hold")
check(WatchLine.pick(alertTarget: nil, holding: nil, sinceWatched: 0.4, facts: "SOL") == .sinceWatched(0.4),
      "then since you watched")
check(WatchLine.pick(alertTarget: nil, holding: nil, sinceWatched: 0.004, facts: "SOL") == .facts("SOL"),
      "a since-watched move under 1% is noise")
check(WatchLine.pick(alertTarget: nil, holding: nil, sinceWatched: nil, facts: "") == nil, "nothing to say, no line")
check(abs((WatchLine.since(anchor: 100, price: 141) ?? 0) - 0.41) < 1e-9, "since you watched is price over anchor")
check(WatchLine.since(anchor: 0, price: 141) == nil, "no anchor, no claim")

// ── The index ────────────────────────────────────────────────────────
let msft = MarketsIndex.Entry(name: "Microsoft", ticker: "MSFT", apps: ["GitHub", "npm"])
let atl = MarketsIndex.Entry(name: "Atlassian", ticker: "TEAM", apps: ["Trello", "Jira"])
let linear = MarketsIndex.Entry(name: "Linear", ticker: nil, apps: ["Linear"])
let crm = MarketsIndex.Entry(name: "Salesforce", ticker: "CRM", apps: ["Slack"])
let split = MarketsIndex.sections([msft, linear, crm, atl], connected: ["GitHub", "Linear"])
check(split.yours == [msft], "a company you use an app of leads (got \(split.yours.map(\.name)))")
check(split.rest == [atl, crm], "the rest follow, A to Z")
check(split.untraded == [linear], "not traded closes the list, even when it is yours")
check(MarketsIndex.sections([msft, crm], connected: []).yours.isEmpty, "nothing connected, nothing is yours")
check(MarketsIndex.appsLine(atl, connected: ["Jira"]) == ["Jira", "Trello"], "your apps lead a company's line")
check(MarketsIndex.matches("slack", crm), "an app's name finds the company behind it")
check(MarketsIndex.matches("$msft", msft), "a ticker finds it, with or without the $")
check(MarketsIndex.matches("micro", msft), "a name finds it")
check(!MarketsIndex.matches("m", msft), "one letter finds nothing")
check(!MarketsIndex.matches("zzz", msft), "a stranger finds nothing")
let found = MarketsIndex.search("git", in: [MarketsIndex.Entry(name: "GitLab", ticker: "GTLB", apps: ["GitLab"]), msft])
check(found.map(\.name) == ["GitLab", "Microsoft"], "a direct match before one found through an app")
let merged = MarketsIndex.merged([[msft], [MarketsIndex.Entry(name: "Microsoft", ticker: "MSFT", apps: ["npm", "Teams"])]])
check(merged.count == 1 && merged[0].apps == ["GitHub", "npm", "Teams"], "All holds each company once, with all its apps")

// ── A custom move, a volume, gas (prd §1247) ─────────────────────────
check(PriceAlert.movePercent("7") == 0.07, "a typed 7 is a 7% move")
check(PriceAlert.movePercent("-7.5%") == 0.075, "a typed sign is the field's, not the alert's: a move listens both ways")
check(PriceAlert.movePercent("0") == nil && PriceAlert.movePercent("") == nil, "no move, no alert")
check(PriceAlert.movePercent("100") == nil, "a move of the whole price is not a day's move")
let seven = PriceAlert(ref: "r", name: "Pepe", kind: .move, target: PriceAlert.movePercent("7")!)
check(!seven.fires(price: 1, change24h: 0.069, now: now, calendar: cal), "a custom 7% move: 6.9% is quiet")
check(seven.fires(price: 1, change24h: -0.07, now: now, calendar: cal), "a custom 7% move: a 7% fall fires")
check(seven.afterFiring(at: now).on, "a custom move stays on")

check(PriceAlert.dollars("$5M") == 5_000_000, "5M is five million")
check(PriceAlert.dollars("250k") == 250_000, "250k")
check(PriceAlert.dollars("1,200,000") == 1_200_000, "commas are read")
check(PriceAlert.dollars("lots") == nil && PriceAlert.dollars("0") == nil, "nothing to read, no amount")
let vol = PriceAlert(ref: "r", name: "Pepe", kind: .volume, target: 5_000_000)
check(!vol.fires(price: 1, change24h: nil, volume24h: 4_900_000, now: now, calendar: cal), "volume under the amount is quiet")
check(!vol.fires(price: 1, change24h: nil, volume24h: nil, now: now, calendar: cal), "no volume read, no claim")
check(vol.fires(price: 1, change24h: nil, volume24h: 5_000_000, now: now, calendar: cal), "volume at the amount fires")
let volFired = vol.afterFiring(at: now)
check(volFired.on, "a volume alert stays on")
check(!volFired.fires(price: 1, change24h: nil, volume24h: 9e9, now: now.addingTimeInterval(3600), calendar: cal),
      "a volume alert fires at most once a day")
check(volFired.fires(price: 1, change24h: nil, volume24h: 9e9, now: now.addingTimeInterval(86_400), calendar: cal),
      "and again the next day")
check(vol.distance(from: 1) == nil, "a volume alert has no distance from a price")

let gasAlert = PriceAlert(ref: GasPrice.ref("eth-mainnet"), name: "Ethereum gas", kind: .gasBelow, target: 0.5)
check(!gasAlert.fires(price: 0.51, change24h: nil, now: now, calendar: cal), "gas above the level is quiet")
check(gasAlert.fires(price: 0.5, change24h: nil, now: now, calendar: cal), "gas at the level fires")
check(!gasAlert.afterFiring(at: now).on, "a gas alert fires once, then waits to be re-armed")
check(!gasAlert.fires(price: 0, change24h: nil, now: now, calendar: cal), "no gas read (0) never fires")
check(GasPrice.network(fromRef: gasAlert.ref) == "eth-mainnet", "a gas alert's ref names its chain")
check(GasPrice.network(fromRef: "gas:moon-mainnet") == nil, "a chain the head does not read is no gas ref")
check(GasPrice.network(fromRef: "tokens:base:0xabc") == nil, "a token ref is not a gas ref")

// ── Gas readings ─────────────────────────────────────────────────────
check(GasPrice.gwei(hex: "0x3b9aca00") == 1, "1e9 wei is one gwei")
check(GasPrice.gwei(hex: "0x0") == nil && GasPrice.gwei(hex: "nope") == nil, "zero or junk is no reading")
check(GasPrice.text(12.4) == "12 gwei", "big gas drops its places")
check(GasPrice.text(2.44) == "2.4 gwei", "one place over a gwei")
check(GasPrice.text(0.4212) == "0.42 gwei", "two under a gwei")
check(GasPrice.text(0.004123) == "0.00412 gwei", "Base's gas keeps three digits, never 0.00")
check(!GasPrice.stamped(at: now.addingTimeInterval(-600), now: now), "gas read ten minutes ago is not stamped")
check(GasPrice.stamped(at: now.addingTimeInterval(-1200), now: now), "gas read twenty minutes ago is stamped")
check(!GasPrice.drawable(at: now.addingTimeInterval(-7 * 3600), now: now), "gas from seven hours ago is not drawn")
check(GasPrice.choices(now: 0.8) == [0.6, 0.4], "the menu offers three quarters and half of now, as drawn")
check(GasPrice.choices(now: 0).isEmpty, "no gas, no choices")

// ── The iCloud merge: a fired alert beats a copy still on ────────────
let t0 = now, t1 = now.addingTimeInterval(3600), t2 = now.addingTimeInterval(7200)
var armed = PriceAlert(ref: "r", name: "Pepe", kind: .above, target: 15)
armed.createdAt = t0
let firedThere = armed.afterFiring(at: t1)
check(PriceAlert.merged(armed, firedThere) == firedThere, "a fired level beats the copy that never saw it")
check(PriceAlert.merged(firedThere, armed) == firedThere, "…whichever side it arrives from")
var rearmed = firedThere
rearmed.on = true; rearmed.firedAt = nil; rearmed.changedAt = t2
check(PriceAlert.merged(firedThere, rearmed) == rearmed, "re-armed by hand after it fired, it stays on")
var offByHand = armed
offByHand.on = false; offByHand.changedAt = t1
check(PriceAlert.merged(armed, offByHand) == offByHand, "switched off by hand beats a copy still on")
var movedHere = PriceAlert(ref: "r", name: "Pepe", kind: .move, target: 0.1)
movedHere.createdAt = t0
let movedThere = movedHere.afterFiring(at: t1)
check(PriceAlert.merged(movedHere, movedThere).firedAt == t1, "a move's day travels, so it fires once a day across devices")
check(PriceAlert.merged(movedThere, movedHere).firedAt == t1, "…from either side")
let legacy = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","ref":"r","name":"Pepe","kind":"above","target":15,"on":true,"createdAt":0}]"#
let oldStore = try? JSONDecoder().decode([PriceAlert].self, from: Data(legacy.utf8))
check(oldStore?.first?.changedAt == nil && oldStore?.count == 1, "alerts stored before §1247 still decode")

// ── A coin by its own price (prd §1247) ──────────────────────────────
let tickerJSON = try! JSONSerialization.jsonObject(with: Data(#"{"id":"btc-bitcoin","symbol":"BTC","quotes":{"USD":{"price":61234.5,"volume_24h":31000000000,"market_cap":1200000000000,"percent_change_24h":-2.5}}}"#.utf8))
let ticker = CoinFollow.ticker(from: tickerJSON)
check(ticker?.price == 61234.5, "the ticker's price")
check(abs((ticker?.change24h ?? 0) + 0.025) < 1e-12, "the day move is a fraction, as a pulse's")
check(ticker?.marketCap == 1.2e12 && ticker?.volume24h == 3.1e10, "cap and volume ride the same answer")
let zeroCap = try! JSONSerialization.jsonObject(with: Data(#"{"quotes":{"USD":{"price":2,"market_cap":0,"volume_24h":0}}}"#.utf8))
check(CoinFollow.ticker(from: zeroCap)?.marketCap == nil, "a zero cap is dropped, never drawn as $0")
check(CoinFollow.ticker(from: zeroCap)?.change24h == nil, "no day move stated, none claimed")
check(CoinFollow.ticker(from: ["error": "id not found"]) == nil, "an error is no ticker")
let ticks = try! JSONSerialization.jsonObject(with: Data(#"[{"timestamp":"2026-10-10T02:00:00Z","price":3},{"timestamp":"2026-10-10T00:00:00Z","price":1},{"timestamp":"2026-10-10T01:00:00Z","price":2},{"timestamp":"2026-10-10T03:00:00Z","price":null}]"#.utf8))
check(CoinFollow.closes(from: ticks) == [1, 2, 3], "ticks sort by their own stamp, and a null price drops")
check(CoinFollow.closes(from: ["error": "Getting historical ticks is not allowed"]).isEmpty,
      "a refusal is no closes")
check(CoinFollow.history(range: "1H") == nil, "the hour is not asked — absent, never drawn from coarser ticks")
check(CoinFollow.history(range: "1D")?.interval == "1h" && CoinFollow.history(range: "30D")?.interval == "1d",
      "a day in hours, a month in days")
check(CoinFollow.historyURL("btc-bitcoin", range: "1D", now: Date(timeIntervalSince1970: 1_000_086_400))
        == "https://api.coinpaprika.com/v1/tickers/btc-bitcoin/historical?start=1000000000&interval=1h",
      "the day's ticks start a day back")
check(CoinFollow.route(from: CoinFollow.page("sol-solana")) == "sol-solana", "a coin's page routes back to its id")
check(CoinFollow.route(from: "https://dexscreener.com/solana/So111") == nil, "a pair page is not a coin's")
check(CoinFollow.id(fromRef: CoinFollow.ref("eth-ethereum")) == "eth-ethereum", "a coin's ref carries its id")
check(CoinFollow.id(fromRef: "tokens:base:0xabc") == nil, "a token's ref is not a coin's")

// ── The launch sweep: WBTC becomes btc-bitcoin, keeping its place and alerts
let index = ["ETH": "eth-ethereum", "GNO": "gno-gnosis", "SAFE": "safe-safe"]
let before = CoinFollow.indexCutoff.addingTimeInterval(-86_400)
let after = CoinFollow.indexCutoff.addingTimeInterval(86_400)
let wbtc = "tokens:ethereum:0x2260fac5e5542a773aa44fbcfedf7c193bc2c599"
let wsol = "tokens:solana:so11111111111111111111111111111111111111112"
let pepe = "tokens:ethereum:0x6982508145454ce325ddbe47a25d4ec3d2311933"
let gno = "tokens:ethereum:0x6810e776880c02933d47db1b9fc05908e5386b96"
let safeLate = "tokens:gnosis:0x4d18815d14fe5c3304e87b3fa18318baa5c23820"
check(CoinFollow.convergence(tokenRef: wbtc, symbol: "BTC", capturedAt: after, indexCoins: index) == "btc-bitcoin",
      "WBTC is Bitcoin, whenever it was followed")
check(CoinFollow.convergence(tokenRef: wsol, symbol: "SOL", capturedAt: after, indexCoins: index) == "sol-solana",
      "wrapped SOL is Solana (its ref is case-folded)")
check(CoinFollow.convergence(tokenRef: gno, symbol: "GNO", capturedAt: before, indexCoins: index) == "gno-gnosis",
      "an index coin the index followed by symbol converges")
check(CoinFollow.convergence(tokenRef: safeLate, symbol: "SAFE", capturedAt: after, indexCoins: index) == nil,
      "a token picked by contract after the cutoff stays a token")
check(CoinFollow.convergence(tokenRef: pepe, symbol: "PEPE", capturedAt: before, indexCoins: index) == nil,
      "a token that is no index coin stays a token")
check(CoinFollow.convergence(tokenRef: CoinFollow.ref("btc-bitcoin"), symbol: "BTC", capturedAt: before,
                             indexCoins: index) == nil, "a coin is already a coin")
check(CoinFollow.convergence(tokenRef: "stocktwits:sym:AAPL", symbol: "AAPL", capturedAt: before,
                             indexCoins: index) == nil, "a stock is never a coin")

let rows = [CoinFollow.Row(ref: pepe, symbol: "PEPE", capturedAt: before),
            CoinFollow.Row(ref: wbtc, symbol: "BTC", capturedAt: before),
            CoinFollow.Row(ref: gno, symbol: "GNO", capturedAt: before)]
let plan = CoinFollow.plan(rows, indexCoins: index)
check(plan.steps == [.stay, .move(to: "coin:btc-bitcoin"), .move(to: "coin:gno-gnosis")],
      "the plan moves the coins in place and leaves the token (got \(plan.steps))")
let order = [gno, pepe, wbtc]
let newOrder = CoinFollow.rewrite(order: order, map: plan.map)
check(newOrder == ["coin:gno-gnosis", pepe, "coin:btc-bitcoin"], "My order keeps every place")
var wbtcAlert = PriceAlert(ref: wbtc, name: "Bitcoin", kind: .below, target: 50_000)
wbtcAlert.createdAt = t0
let keptAlert = PriceAlert(ref: pepe, name: "Pepe", kind: .above, target: 1)
let newAlerts = CoinFollow.rewrite(alerts: [wbtcAlert, keptAlert], map: plan.map, now: t2)
check(newAlerts[0].ref == "coin:btc-bitcoin" && newAlerts[0].id == wbtcAlert.id && newAlerts[0].target == 50_000,
      "the alert moves with its row, the same alert")
check(newAlerts[0].changedAt == t2, "a moved alert is stamped, so an unswept device cannot sync the old ref back")
check(newAlerts[1] == keptAlert, "a token's alert is left alone")
// Twice changes nothing.
let swept = [CoinFollow.Row(ref: pepe, symbol: "PEPE", capturedAt: before),
             CoinFollow.Row(ref: "coin:btc-bitcoin", symbol: "BTC", capturedAt: before),
             CoinFollow.Row(ref: "coin:gno-gnosis", symbol: "GNO", capturedAt: before)]
let again = CoinFollow.plan(swept, indexCoins: index)
check(again.map.isEmpty && again.steps == [.stay, .stay, .stay], "a second sweep plans nothing")
check(CoinFollow.rewrite(order: newOrder, map: again.map) == newOrder, "…and leaves the order as it was")
check(CoinFollow.rewrite(alerts: newAlerts, map: again.map, now: t2) == newAlerts, "…and the alerts")
// A WBTC follow beside a Bitcoin follow folds into it.
let both = CoinFollow.plan([CoinFollow.Row(ref: "coin:btc-bitcoin", symbol: "BTC", capturedAt: before),
                            CoinFollow.Row(ref: wbtc, symbol: "BTC", capturedAt: before)], indexCoins: index)
check(both.steps == [.stay, .fold(into: "coin:btc-bitcoin")], "a token whose coin is followed folds into it")
check(CoinFollow.rewrite(order: [wbtc, "coin:btc-bitcoin", pepe], map: both.map) == ["coin:btc-bitcoin", pepe],
      "the folded row's place is the coin's first place, once")

if failures > 0 { print("✗ markets: \(failures) failing"); exit(1) }
print("✓ markets self-test passed")
SWIFT

swiftc -O -o "$TMP/markets" "$TMP/PriceAlert.swift" "$TMP/WatchLine.swift" "$TMP/MarketsIndex.swift" \
  "$TMP/CoinFollow.swift" "$TMP/GasPrice.swift" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/markets" ]] || { echo "✗ markets harness did not compile"; exit 1; }
"$TMP/markets"
