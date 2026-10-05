#!/bin/zsh
# Casberi wallet makeover self-test (prd §1090):
#
#   Casberi/Casberi/Model/WalletFollowSuggest.swift   (compiled whole)
#   Casberi/Casberi/Model/HoldingMoves.swift          (compiled whole, DefaultsWrite stubbed)
#   Casberi/Casberi/Model/WalletRiskScale.swift       (compiled whole)
#
# WHY A HARNESS. Every failure here renders as a calm screen: Follow offering
# a router or a poisoning address as someone to follow, or the address you
# already follow; the Holdings box colouring a tile by a move read yesterday,
# or one token on two chains as two moves; Risk saying "ETH can fall 24%" of a
# pair that moves together. Only a case-by-case statement says each is right.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SUGGEST="Casberi/Casberi/Model/WalletFollowSuggest.swift"
MOVES="Casberi/Casberi/Model/HoldingMoves.swift"
RISK="Casberi/Casberi/Model/WalletRiskScale.swift"
SHEET="Casberi/Casberi/Screens/WalletFollowSheet.swift"
ROOM="Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift"
TREEMAP="Casberi/Casberi/Design/HoldingsTreemap.swift"
ZERION="Casberi/Casberi/Model/ZerionAPI.swift"
INGEST="Casberi/Casberi/Model/WalletIngest.swift"
for f in "$SUGGEST" "$MOVES" "$RISK" "$SHEET" "$ROOM" "$TREEMAP" "$ZERION" "$INGEST"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# ── Reachability: each piece is used where it is drawn ────────────────
grep -q 'WalletFollowSuggest.suggestions(' "$SHEET" \
  || { echo "✗ the Follow tray no longer reads WalletFollowSuggest.suggestions"; exit 1; }
grep -q 'WalletFollow.resolve(' "$SHEET" \
  || { echo "✗ the Follow tray no longer resolves through WalletFollow — two spellings of one follow"; exit 1; }
grep -q 'WalletFollow.resolve(' Casberi/Casberi/Screens/WalletWatchField.swift \
  || { echo "✗ the account page's field no longer resolves through WalletFollow"; exit 1; }
grep -q 'feedSheet = .walletFollow' "$ROOM" \
  || { echo "✗ Watch a wallet no longer raises the tray in the room"; exit 1; }
grep -q 'percent_1d' "$ZERION" \
  || { echo "✗ Zerion's day change is no longer read"; exit 1; }
grep -q 'HoldingMoves.note(' "$INGEST" \
  || { echo "✗ the holdings read no longer notes the day's moves"; exit 1; }
grep -q 'holdingsDayMoves' "$TREEMAP" \
  || { echo "✗ the treemap no longer reads the day's moves"; exit 1; }
grep -q 'environment(\\.holdingsDayMoves' "$ROOM" \
  || { echo "✗ the Holdings box no longer hands the treemap its moves"; exit 1; }
grep -q 'WalletRiskScale.shortFall' "$ROOM" \
  || { echo "✗ a borrow's Positions row no longer says what it can bear (prd §1107)"; exit 1; }
! awk '/func walletSetHoldingAlert/,/^    }$/' "$ROOM" | grep -q 'watchPriceUsd' \
  || { echo "✗ a holding's alert reads watchPriceUsd — the price the day you watched, not today's"; exit 1; }
grep -q 'PriceAlert.choices(ref: "", name: "", price: 1)' "$ROOM" \
  || { echo "✗ the holding alert menu no longer words Markets' own choices — a second list to drift"; exit 1; }
grep -q 'fell below the' Casberi/Casberi/Model/WalletDeFi.swift && grep -q 'fell below the' Casberi/Casberi/Model/MorphoDeFi.swift \
  || { echo "✗ a borrow under your line but over the app's says 'close to liquidation' again"; exit 1; }
grep -q 'HoldingMoves.note(owners:' "$INGEST" \
  || { echo "✗ the holdings read no longer notes moves per wallet — one wallet's read wipes another's"; exit 1; }
grep -q 'needsYouGroup' "$ROOM" \
  || { echo "✗ Home no longer leads with Needs you (prd §1111)"; exit 1; }
for f in Casberi/Casberi/Model/WalletDeFi.swift Casberi/Casberi/Model/MorphoDeFi.swift; do
  grep -q 'DeFiRisk.alertLine' "$f" \
    || { echo "✗ $f no longer notifies at your line (DeFiRisk.alertLine)"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$SUGGEST" "$MOVES" "$RISK" "$TMP/"
cat > "$TMP/stubs.swift" <<'SWIFT'
import Foundation
enum DefaultsWrite { static func set(_ v: Data, forKey: String) {} }
SWIFT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
let now = Date(timeIntervalSince1970: 2_000_000_000)
func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
typealias S = WalletFollowSuggest
func move(_ a: String, _ d: Double, excluded: Bool = false) -> S.Move {
    .init(counterparty: a, at: ago(d), excluded: excluded)
}
func entry(_ a: String, _ n: String, kind: String = "wallet", days: Double = 1,
           service: Bool = false) -> S.BookEntry {
    .init(address: a, name: n, kind: kind, provenance: nil, addedAt: ago(days), isService: service)
}
let sam = "0xAAAA000000000000000000000000000000000001"
let mia = "0xbbbb000000000000000000000000000000000002"
let router = "0xcccc000000000000000000000000000000000003"
let mine = "0xdddd000000000000000000000000000000000004"

// ── Follow suggestions ───────────────────────────────────────────────
var out = S.suggestions(moves: [move(sam, 1), move(sam.lowercased(), 3)], book: [],
                        following: [], now: now)
check(out.first?.why == .movedWith(2), "two moves with one address (any case) make a habit")
out = S.suggestions(moves: [move(sam, 1)], book: [], following: [], now: now)
check(out.isEmpty, "one move is not a habit")
out = S.suggestions(moves: [move(sam, 1), move(sam, 70)], book: [], following: [], now: now)
check(out.isEmpty, "a move outside sixty days does not count")
out = S.suggestions(moves: [move(router, 1, excluded: true), move(router, 2, excluded: true)],
                    book: [], following: [], now: now)
check(out.isEmpty, "a flagged or venue move is never a person")
out = S.suggestions(moves: [move(mine, 1), move(mine, 2)], book: [entry(mine, "Me")],
                    following: [mine.uppercased().replacingOccurrences(of: "0X", with: "0x")], now: now)
check(out.isEmpty, "an address you follow is never offered again")
out = S.suggestions(moves: [move(router, 1), move(router, 2)],
                    book: [entry(router, "Uniswap", kind: "contract")], following: [], now: now)
check(out.isEmpty, "a contract in your book is machinery, not someone")
out = S.suggestions(moves: [], book: [entry(mia, "Coinbase", service: true)], following: [], now: now)
check(out.isEmpty, "a service is never offered")
out = S.suggestions(moves: [], book: [entry(mia, "Key", kind: "key")], following: [], now: now)
check(out.isEmpty, "a signing key holds nothing to follow")
out = S.suggestions(moves: [move(sam, 1), move(sam, 2)],
                    book: [entry(sam, "Sam"), entry(mia, "Mia")], following: [], now: now)
check(out.map(\.name) == ["Sam", "Mia"], "habits lead, then the book, each once")
check(out.first?.why == .movedWith(2), "a habit in the book keeps its habit line")
let many = (0..<9).map { entry("0xeeee00000000000000000000000000000000000\($0)", "P\($0)", days: Double($0)) }
check(S.suggestions(moves: [], book: many, following: [], now: now).count == S.limit,
      "at most \(S.limit) suggestions")
check(S.key("So1anaCaseMatters") == "So1anaCaseMatters", "a non-hex address keeps its case")

// ── Holding moves ────────────────────────────────────────────────────
let merged = HoldingMoves.merge([.init(symbol: "eth", usd: 3000, change: 0.02),
                                 .init(symbol: "ETH ", usd: 1000, change: -0.02),
                                 .init(symbol: "USDC", usd: 0, change: 0.5),
                                 .init(symbol: "SOL", usd: 10, change: .nan)])
check(abs((merged["ETH"] ?? 9) - 0.01) < 1e-9, "one token in two places is one dollar-weighted move")
check(merged["USDC"] == nil, "a holding worth nothing carries no move")
check(merged["SOL"] == nil, "a non-finite move is dropped")
// Per wallet: a read of one wallet keeps what another wallet's read said.
typealias HM = HoldingMoves
var notes = HM.replacing([:], owners: ["0xA", "0xB"],
                         with: [(owner: "0xa", read: .init(symbol: "ETH", usd: 1000, change: 0.02)),
                                (owner: "0xB", read: .init(symbol: "SOL", usd: 500, change: -0.03))],
                         now: now.addingTimeInterval(-60))
notes = HM.replacing(notes, owners: ["0xb"],
                     with: [(owner: "0xb", read: .init(symbol: "SOL", usd: 500, change: 0.01))], now: now)
var combined = HM.combine(notes, now: now)
check(combined["ETH"] == 0.02, "one wallet's read keeps the other wallet's moves")
check(combined["SOL"] == 0.01, "a wallet's new read replaces its own moves")
notes = HM.replacing(notes, owners: ["0xA"], with: [], now: now)
check(HM.combine(notes, now: now)["ETH"] == nil, "a wallet that sold its token stops moving it")
notes["0xold"] = .init(at: now.addingTimeInterval(-8 * 3600), reads: [.init(symbol: "DOGE", usd: 9, change: 0.5)])
check(HM.combine(notes, now: now)["DOGE"] == nil, "a stale wallet's note is not drawn")
combined = HM.combine(HM.replacing([:], owners: ["0x1", "0x2"],
                                   with: [(owner: "0x1", read: .init(symbol: "ETH", usd: 3000, change: 0.02)),
                                          (owner: "0x2", read: .init(symbol: "ETH", usd: 1000, change: -0.02))],
                                   now: now), now: now)
check(abs((combined["ETH"] ?? 9) - 0.01) < 1e-9, "a token in two wallets is weighted by the combined dollars")
check(HoldingMoves.isFresh(at: now.addingTimeInterval(-3600), now: now), "an hour-old move is fresh")
check(!HoldingMoves.isFresh(at: now.addingTimeInterval(-7 * 3600), now: now), "a seven-hour-old move is stale")
check(!HoldingMoves.isFresh(at: now.addingTimeInterval(3600), now: now), "a move from the future is not fresh")
let t = HoldingMoves.tally([0.02, -0.01, 0.0001, 0])
check(t.up == 1 && t.down == 1, "a move that rounds to zero is neither up nor down")

// ── What a borrow can bear ───────────────────────────────────────────
typealias R = WalletRiskScale
let morpho = R.lendingEntry(id: "morpho:x", label: "Morpho · wstETH / WETH", hf: 1.32, riskFloor: 1.5)!
// Positions' rows carry it short since prd §1107: one line has room for the
// distance, so the pair's names are left to the row's title.
check(R.shortFall(morpho) == "can fall 24%",
      "a borrow says how far it can fall, rounded down: \(R.shortFall(morpho) ?? "nil")")
let aave = R.lendingEntry(id: "aave:x", label: "Aave", hf: 2.4, riskFloor: 1.5)!
check(R.shortFall(aave) == "can fall 58%",
      "a basket says the same, from its health: \(R.shortFall(aave) ?? "nil")")
let perp = R.perpEntry(id: "hl:a:ETH", label: "ETH long", proximity: 0.34, riskProximity: 0.15)!
check(R.shortFall(perp) == nil, "a perp states its own distance")
let edge = R.lendingEntry(id: "aave:y", label: "Aave", hf: 0.9, riskFloor: 1.5)!
check(R.shortFall(edge) == nil, "a position at the edge can bear nothing to state")

if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("✓ wallet makeover self-test")
SWIFT
swiftc -O -o "$TMP/t" "$TMP"/*.swift 2>&1 | grep -v "warning:" || true
[[ -x "$TMP/t" ]] || { echo "✗ the harness did not compile"; exit 1; }
"$TMP/t"
