#!/bin/zsh
# Casberi watchlist self-test (prd §1632) — the rules behind the Wallet's
# watchlist, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/WatchlistRules.swift
#
# The list's order, the ten-minute price window, the day's change in words
# (a change that rounds to zero has no sign, §83), a pasted contract asked of
# every chain, and the three keyless answers it reads. Plus the drift guards:
# the store's key is outside what the Markets sweep clears, the prices never
# ask Zerion, they are read only where the watchlist is on screen, and Home
# draws it on All and Yours only, as one door.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

RULES="Casberi/Casberi/Model/WatchlistRules.swift"
STORE="Casberi/Casberi/Model/Watchlist.swift"
SCREEN="Casberi/Casberi/Screens/FeedScreen+Watchlist.swift"
SWEEP="Casberi/Casberi/Model/SourceRename.swift"
for f in "$RULES" "$STORE" "$SCREEN" "$SWEEP"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# The key outlives the Markets sweep (§1529 clears `markets.` and `tokens.watch.`).
key="$(grep -oE 'storeKey = "[^"]+"' "$STORE" | head -1 | sed -E 's/.*"([^"]+)"/\1/')"
[[ -n "$key" ]] || { echo "✗ Watchlist.storeKey not found"; exit 1; }
for prefix in $(grep -oE '"(markets|tokens\.watch)\.[^"]*"' "$SWEEP" | tr -d '"'); do
  [[ "$key" != ${prefix}* ]] || { echo "✗ the watchlist's key $key is cleared by the sweep's $prefix"; exit 1; }
done
# Keyless: never the one Zerion budget every install shares (§1632 item 8).
if grep -vE '^[[:space:]]*(//|///)' "$STORE" "$RULES" | grep -qE 'zerion|ZerionAPI|ZerionLane'; then
  echo "✗ the watchlist reads through Zerion"; exit 1
fi
# Read only where it is on screen, never by a sweep.
callers="$(grep -rlE 'WatchlistPrices\.shared\.refreshIfStale' Casberi/Casberi | sort)"
[[ "$callers" == "$SCREEN" ]] || { echo "✗ refreshIfStale is called outside the watchlist's screens:"; print -r -- "$callers"; exit 1; }
# Home draws it on All and Yours only: never on Following, never on an app pick.
shows="$(awk '/var walletWatchlistShows: Bool/,/^    }/' "$SCREEN")"
print -r -- "$shows" | grep -qF 'guard !walletOnFollowing, selectedSeat == nil else { return false }' \
  || { echo "✗ Home's watchlist no longer stands down on Following and an app pick"; exit 1; }
grep -qF 'if walletWatchlistShows { walletWatchlistHomeSection }' Casberi/Casberi/Screens/FeedScreen+ShapedSections.swift \
  || { echo "✗ Home no longer draws the watchlist behind walletWatchlistShows"; exit 1; }
# A token watched by its contract charts too: when DeFiLlama has no window,
# the coin CoinGecko lists it as (AZTEC on Ethereum drew an empty box).
charts="$(awk '/static func charts\(ids:/,/^    }/' "$STORE")"
print -r -- "$charts" | grep -qF 'ContractCoins.shared.coin(forContract: id)' \
  || { echo "✗ a contract with no DeFiLlama window no longer falls back to its CoinGecko coin"; exit 1; }
# A token page with no chart says so, never an empty box (§769).
awk '/func walletWatchlistFigure/,/^    }/' "$SCREEN" | grep -qF 'WalletScopeEmptyFigure(section: .watchedToken)' \
  || { echo "✗ a token page with no chart draws an empty box"; exit 1; }
echo "watchlist-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
typealias R = WatchlistRules
let btc = WatchedToken(id: "coingecko:bitcoin", symbol: "BTC", name: "Bitcoin")
let eth = WatchedToken(id: "coingecko:ethereum", symbol: "ETH", name: "Ethereum")
let aero = WatchedToken(id: "base:0x940181a94a35a4569e4529a3cdfb74e38fd98631", symbol: "AERO", name: "AERO")

// The list
check(R.adding(eth, to: [btc]) == [btc, eth], "watching adds to the end")
check(R.adding(btc, to: [btc, eth]) == [btc, eth], "watching twice keeps one")
check(R.removing(btc.id, from: [btc, eth]) == [eth], "stop watching removes it")
check(R.movingToTop(eth.id, in: [btc, eth, aero]) == [eth, btc, aero], "move to top leads with it, the rest in order")
check(R.movingToTop(btc.id, in: [btc, eth]) == [btc, eth], "the first stays first")

// The window
let now = Date(timeIntervalSince1970: 1_800_000_000)
check(R.isStale(readAt: nil, now: now), "never read is stale")
check(!R.isStale(readAt: now.addingTimeInterval(-599), now: now), "under ten minutes stands")
check(R.isStale(readAt: now.addingTimeInterval(-600), now: now), "ten minutes is stale")

// The day's change
check(R.change(2.14) == ("+2.1%", .up), "a rise has its sign")
check(R.change(-4.56) == ("\u{2212}4.6%", .down), "a fall has a true minus")
check(R.change(0.04) == ("0.0%", .flat), "rounds to zero: no sign, no colour")
check(R.change(-0.04) == ("0.0%", .flat), "a fall that rounds to zero too")
check(R.change(.nan) == ("0.0%", .flat), "no number is flat, never a sign")

// Home's door: the biggest mover
let q: [String: R.Quote] = [btc.id: .init(price: 1, change: 0.9), eth.id: .init(price: 1, change: -4.6),
                            aero.id: .init(price: 1, change: 2.1)]
let m = R.biggestMover([btc, eth, aero], quotes: q)
check(m?.symbol == "ETH" && m?.change.words == "\u{2212}4.6%" && m?.change.tone == .down, "the biggest move either way, a fall included")
check(R.biggestMover([btc, eth], quotes: [btc.id: .init(price: 1, change: 0.04), eth.id: .init(price: 1, change: nil)]) == nil,
      "nothing moved, or no change answered: no mover, the count instead")
check(R.biggestMover([btc, eth], quotes: [btc.id: .init(price: 1, change: 2), eth.id: .init(price: 1, change: -2)])?.symbol == "BTC",
      "a tie goes to the earlier on the list")
check(R.biggestMover([], quotes: q) == nil, "an empty list has no mover")

// Where it lives
check(R.network(of: aero.id) == "Base", "a contract names its network")
check(R.network(of: btc.id) == nil, "a coin names none")
check(R.line(for: btc) == "Bitcoin" && R.line(for: aero) == "Base", "the line: the coin's name, or the network")

// A pasted contract
let evm = R.contractCandidates("  0x940181A94A35A4569E4529A3CDFB74E38FD98631 ")
check(evm.contains("base:0x940181a94a35a4569e4529a3cdfb74e38fd98631") && evm.contains("ethereum:0x940181a94a35a4569e4529a3cdfb74e38fd98631"),
      "an EVM address asks every EVM chain, lowercased")
check(!evm.contains { $0.hasPrefix("solana:") }, "an EVM address never asks Solana")
check(R.contractCandidates("JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN") == ["solana:JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"],
      "a Solana mint asks Solana, its case kept")
check(R.contractCandidates("hype").isEmpty, "words are not an address")
check(R.contractCandidates("0x123").isEmpty, "a short hex is not an address")

// The chart
check(R.chartQuery("1H")! == (13, "5m") && R.chartQuery("30D")! == (31, "1d"), "each range asks its span and period")
check(R.chartQuery("1Y") == nil, "a range DeFiLlama is not asked for is nil")

// The answers
let prices = #"{"coins":{"coingecko:bitcoin":{"price":77458.4,"symbol":"BTC","confidence":0.99},"coingecko:thin":{"price":1.0,"symbol":"THIN","confidence":0.5},"coingecko:zero":{"price":0,"symbol":"Z","confidence":0.99}}}"#
let p = R.parsePrices(Data(prices.utf8))
check(p["coingecko:bitcoin"]?.price == 77458.4 && p["coingecko:bitcoin"]?.symbol == "BTC", "a price and its symbol")
check(p["coingecko:thin"] == nil, "under the confidence floor is no price (§83)")
check(p["coingecko:zero"] == nil, "a zero is no price")
let pct = R.parsePercent(Data(#"{"coins":{"coingecko:bitcoin":0.31,"base:0xa":"-2.5"}}"#.utf8))
check(pct["coingecko:bitcoin"] == 0.31 && pct["base:0xa"] == -2.5, "the day's change, in percent")
let chart = #"{"coins":{"coingecko:x":{"prices":[{"timestamp":3,"price":3.0},{"timestamp":1,"price":1.0},{"timestamp":2,"price":2.0},{"timestamp":4,"price":0}]}}}"#
check(R.parseChart(Data(chart.utf8), id: "coingecko:x") == [1, 2, 3], "the closes, oldest first, a zero dropped")
check(R.parseChart(Data(chart.utf8), id: "coingecko:y").isEmpty, "another id's chart is nothing")
let search = #"{"coins":[{"id":"basedhype","symbol":"basedhype","name":"BasedHype","market_cap_rank":612},{"id":"fakehype","symbol":"hype","name":"Hype","market_cap_rank":null},{"id":"hyperliquid","symbol":"hype","name":"Hyperliquid","market_cap_rank":11}]}"#
let found = R.parseSearch(Data(search.utf8))
check(found.map(\.id) == ["coingecko:hyperliquid", "coingecko:basedhype"], "ranked by market cap, the unranked left out")
check(found.first?.symbol == "HYPE" && found.first?.name == "Hyperliquid", "the ticker in capitals, the name kept")
check(R.parseSearch(Data("not json".utf8)).isEmpty, "a broken answer is nothing")

// A holding of yours is watched as what you hold (2026-11-01): a ticker
// CoinGecko does not rank was never found, and its plus did nothing.
let cg = ["eth": "ethereum", "usdc": "usd-coin"]
let llama = ["eth-mainnet": "ethereum", "base-mainnet": "base", "solana-mainnet": "solana"]
check(R.holdingIDs(symbol: "ETH", contracts: ["base-mainnet:native", "eth-mainnet:native"], route: nil,
                   coingecko: cg, llamaChains: llama) == ["coingecko:ethereum"],
      "a known coin is its CoinGecko id, and a native coin has no contract")
check(R.holdingIDs(symbol: "USDC", contracts: ["base-mainnet:0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"], route: nil,
                   coingecko: cg, llamaChains: llama)
      == ["coingecko:usd-coin", "base:0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"],
      "the coin first, then the contract you hold it at")
check(R.holdingIDs(symbol: "MUSEGO", contracts: ["base-mainnet:0x940181a94a35a4569e4529a3cdfb74e38fd98631",
                                                "unknown-mainnet:0x940181a94a35a4569e4529a3cdfb74e38fd98631"],
                   route: nil, coingecko: cg, llamaChains: llama)
      == ["base:0x940181a94a35a4569e4529a3cdfb74e38fd98631"],
      "an unranked token is its contract, on a chain DeFiLlama reads only")
let mint = "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"
check(R.holdingIDs(symbol: "JUP", contracts: ["solana-mainnet:\(mint.lowercased())"], route: "solana:\(mint)",
                   coingecko: cg, llamaChains: llama) == ["solana:\(mint)"],
      "a Solana mint keeps its case, from the route")
check(R.holdingIDs(symbol: "JUP", contracts: ["solana-mainnet:\(mint.lowercased())"], route: nil,
                   coingecko: cg, llamaChains: llama).isEmpty,
      "a lowercased mint is never asked")
check(R.holdingIDs(symbol: "ZZZ", contracts: [], route: nil, coingecko: cg, llamaChains: llama).isEmpty,
      "nothing known: empty, and the tray asks the search")

// A contract DeFiLlama cannot price is asked which coin it is (2026-11-01,
// MUSEGOD on Robinhood read "No price").
check(R.coinByContractPath("robinhood:0x0379e228f6887c6f18bf394042ecaf81b308cb2e")
      == "coins/robinhood/contract/0x0379e228f6887c6f18bf394042ecaf81b308cb2e", "a Robinhood contract asks CoinGecko's robinhood")
check(R.coinByContractPath("arbitrum:0xa") == "coins/arbitrum-one/contract/0xa", "DeFiLlama's chain is CoinGecko's platform")
check(R.coinByContractPath("coingecko:bitcoin") == nil, "a coin is not a contract")
check(R.coinByContractPath("bsc:0xa") == nil, "a chain CoinGecko is not asked on is nil")
check(R.parseCoinByContract(Data(#"{"id":"musegod","symbol":"musegod"}"#.utf8)) == "coingecko:musegod", "the coin a contract is")
check(R.parseCoinByContract(Data(#"{"error":"coin not found"}"#.utf8)) == nil, "a contract CoinGecko lists none for is nil")
check(R.tickerKey(" $musegod ") == "MUSEGOD" && R.tickerKey("MuseGod") == R.tickerKey("MUSEGOD"), "a ticker compares by its letters")

// The box: every token side by side, the first five (2026-11-01)
let six = (1...6).map { WatchedToken(id: "coingecko:t\($0)", symbol: "T\($0)", name: "T\($0)") }
check(R.charted(six).map(\.id) == six.prefix(5).map(\.id), "the box draws the first five, in the list's order")
check(R.charted(Array(six.prefix(2))).count == 2, "two watched draw two")
check(R.lineHues.count == R.chartCap && Set(R.lineHues).count == R.chartCap, "one hue for each line the box draws")
check(zip(R.percentSeries([100, 102, 99]), [0.0, 2, -1]).allSatisfy { abs($0 - $1) < 1e-9 }, "each close as the percent from the first")
check(R.percentSeries([5]).isEmpty && R.percentSeries([0, 1]).isEmpty, "one close, or no first price, is no line")
let spread = R.labelCenters([10, 12, 13, 90], gap: 16, lo: 8, hi: 100)
check(spread[0] == 10 && spread[1] == 26 && spread[2] == 42 && spread[3] == 90, "labels that would touch are pushed apart, in order")
let floor = R.labelCenters([95, 99, 100], gap: 16, lo: 8, hi: 100)
check(floor == [68, 84, 100], "labels at the floor stack upward, inside the box")
check(R.labelCenters([50, 10], gap: 16, lo: 8, hi: 100) == [50, 10], "labels far apart stay at their lines, in the order given")
check(R.thinned(Array(stride(from: 0.0, through: 288, by: 1)), to: 49).count == 49, "a long series is thinned to the cap")
check(R.thinned([1, 2, 3, 4, 5], to: 3) == [1, 2.5, 4.5], "thinning takes each stretch's mean, so a bounce is not kept")
check(R.thinned([1, 9, 1, 9, 1, 9], to: 3) == [5, 5, 5], "a coin bouncing tick to tick draws flat")
check(R.coingeckoChartQuery("1D")! == (1, nil) && R.coingeckoChartQuery("1H")! == (1, 3600), "each range asks CoinGecko its days")
let cgc = #"{"prices":[[1000000,1.0],[2000000,2.0],[4600000,3.0],[4700000,0]]}"#
check(R.parseCoinGeckoChart(Data(cgc.utf8), keepsSeconds: nil) == [1, 2, 3], "CoinGecko's closes, oldest first, a zero dropped")
check(R.parseCoinGeckoChart(Data(cgc.utf8), keepsSeconds: 3000) == [2, 3], "the hour keeps only the tail")

print(failures == 0 ? "watchlist-selftest: all checks ✓" : "watchlist-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$RULES" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ watchlist-selftest: compile failed"; exit 1; }
"$TMP/run"
