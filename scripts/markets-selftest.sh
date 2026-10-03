#!/bin/zsh
# Casberi markets self-test — the rules behind Markets' watchlist and alerts
# (prd §1081):
#
#   Casberi/Casberi/Model/PriceAlert.swift  (compiled whole)
#   Casberi/Casberi/Model/WatchLine.swift   (compiled whole: the row's line, the heat map)
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
for f in "$ALERT" "$LINE" "$INDEX"; do
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
grep -q 'WatchHeat.frames(count:' Casberi/Casberi/Screens/MarketsViews.swift \
  || { echo "✗ the heat map no longer lays out through WatchHeat.frames"; exit 1; }
grep -q 'MarketsIndex.sections(' Casberi/Casberi/Screens/FeedScreen+Markets.swift \
  || { echo "✗ the index no longer splits into your apps, everything else and not traded"; exit 1; }
grep -q 'MarketsIndex.search(' Casberi/Casberi/Screens/WatchAddSheet.swift \
  || { echo "✗ Search no longer finds a company by an app it makes"; exit 1; }
grep -q 'PriceAlertStore.shared.removeAll(ref: ref)' Casberi/Casberi/Screens/FeedScreen+Markets.swift \
  || { echo "✗ unwatching no longer takes the row's alerts with it — they would fire for a row you cannot see"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$ALERT" "$LINE" "$INDEX" "$TMP/"
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

// ── The heat map ─────────────────────────────────────────────────────
let tiles = WatchHeat.tiles([("a", "A", 0.02), ("b", "B", -0.08), ("c", "C", 0.0001), ("d", "D", 0.04)])
check(tiles.map(\.id) == ["b", "d", "a", "c"], "tiles run by size of move (got \(tiles.map(\.id)))")
check(tiles[0].strength == 1, "the biggest move is the full colour")
check(abs(tiles[1].strength - 0.5) < 1e-9, "the rest by their move against the biggest")
check(tiles[3].flat && tiles[3].strength == 0, "a move that rounds to zero carries no colour")
let many = (0..<12).map { (id: "t\($0)", symbol: "T\($0)", change: Double($0) / 100) }
check(WatchHeat.tiles(many).count == WatchHeat.cap, "the board holds at most \(WatchHeat.cap)")

for n in 1...WatchHeat.cap {
    let frames = WatchHeat.frames(count: n)
    check(frames.count == n, "\(n) tiles get \(n) frames")
    let area = frames.reduce(0) { $0 + $1.width * $1.height }
    check(abs(area - 1) < 1e-9, "\(n) tiles fill the box (area \(area))")
    for f in frames {
        check(f.minX >= -1e-9 && f.minY >= -1e-9 && f.maxX <= 1 + 1e-9 && f.maxY <= 1 + 1e-9,
              "\(n) tiles stay inside the box")
    }
    for i in frames.indices {
        for j in frames.indices where j > i {
            let overlap = frames[i].intersection(frames[j])
            check(overlap.isNull || overlap.width * overlap.height < 1e-9, "\(n) tiles never overlap")
        }
    }
    if n > 1 {
        let lead = frames[0].width * frames[0].height
        check(frames.dropFirst().allSatisfy { $0.width * $0.height <= lead + 1e-9 }, "\(n): the lead is the biggest tile")
    }
}
check(WatchHeat.frames(count: 0).isEmpty, "no tiles, no frames")

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

if failures > 0 { print("✗ markets: \(failures) failing"); exit(1) }
print("✓ markets self-test passed")
SWIFT

swiftc -O -o "$TMP/markets" "$TMP/PriceAlert.swift" "$TMP/WatchLine.swift" "$TMP/MarketsIndex.swift" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/markets" ]] || { echo "✗ markets harness did not compile"; exit 1; }
"$TMP/markets"
