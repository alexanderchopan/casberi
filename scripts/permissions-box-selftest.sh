#!/bin/zsh
# Casberi Permissions/Threats box self-test — what each page's box draws
# (prd §1654, §1710, §1633):
#
#   Casberi/Casberi/Model/PermissionsPack.swift        (compiled whole)
#   Casberi/Casberi/Design/CirclePack.swift            (compiled whole: the disc's inside)
#   Casberi/Casberi/Model/ThreatTrend.swift            (compiled whole)
#   Casberi/Casberi/Model/WalletApprovalExposure.swift (compiled whole: the grant)
#
# WHY A HARNESS. Both failures render as a calm box. Split one app into two
# circles, or ring a capped app, and the pack draws a reading nobody can
# check against the list; bucket a week wrong and the bars say threats are
# falling while they rise. Neither shows on a screenshot of one wallet.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PACK="Casberi/Casberi/Model/PermissionsPack.swift"
TREND="Casberi/Casberi/Model/ThreatTrend.swift"
EXPO="Casberi/Casberi/Model/WalletApprovalExposure.swift"
CPACK="Casberi/Casberi/Design/CirclePack.swift"
for f in "$PACK" "$TREND" "$EXPO" "$CPACK"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
grep -q 'WalletPermissionsFigure(grants: walletLive.exposure.all,' Casberi/Casberi/Screens/FeedScreen+WalletPages.swift \
  || { echo "✗ Permissions' box no longer packs every grant"; exit 1; }
grep -q 'acting: walletPermissionsActing,' Casberi/Casberi/Screens/FeedScreen+WalletPages.swift \
  || { echo "✗ Permissions' box no longer packs the delegates and modules (§1677)"; exit 1; }
grep -q 'held: walletPermissionsHeld,' Casberi/Casberi/Screens/FeedScreen+WalletPages.swift \
  || { echo "✗ Permissions' disc no longer reads what the wallets hold (§1710)"; exit 1; }
grep -q 'isVenue: WalletPortfolio.isVenue)' Casberi/Casberi/Screens/FeedScreen+WalletSecurity.swift \
  || { echo "✗ Permissions' disc counts a place an approval cannot reach (§1710)"; exit 1; }
grep -q 'accounts: \$0.accounts)' Casberi/Casberi/Screens/FeedScreen+WalletSecurity.swift \
  || { echo "✗ a delegate's reach is no longer its accounts' (§1710)"; exit 1; }
grep -q 'PermissionsPack.inside(inner.map(\\.usd), scale: disc.scale' Casberi/Casberi/Screens/WalletPermissionsFigure.swift \
  || { echo "✗ the grants no longer sit inside the disc at their dollars (§1710)"; exit 1; }
! grep -q 'AssetMark(' Casberi/Casberi/Screens/WalletPermissionsFigure.swift \
  || { echo "✗ the box draws AssetMark again: a hex name is the \"..\" disc (§1710)"; exit 1; }
grep -q 'WalletPermissions.actingHolders(holders).map' Casberi/Casberi/Screens/FeedScreen+WalletSecurity.swift \
  || { echo "✗ the pack's delegates are not the Delegations list's read (§1677)"; exit 1; }
grep -q 'PermissionsPack.pieces(grants, acting: acting, held: held)' Casberi/Casberi/Screens/WalletPermissionsFigure.swift \
  || { echo "✗ the pack no longer draws PermissionsPack's pieces"; exit 1; }
grep -q 'WalletScopeEmptyFigure(section: .permissions' Casberi/Casberi/Screens/WalletPermissionsFigure.swift \
  || { echo "✗ an empty pack no longer draws its skeleton and short state (§1677)"; exit 1; }
grep -q 'case ScopeTileGlyph.permissions: self = .pack' Casberi/Casberi/Design/DSSkeleton.swift \
  || { echo "✗ Permissions' skeleton is no longer the pack (§1677)"; exit 1; }
grep -q 'ThreatTrend.read(' Casberi/Casberi/Screens/FeedScreen+WalletPages.swift \
  || { echo "✗ Threats' box no longer reads the trend"; exit 1; }
grep -q 'let exposure = walletLive.exposure$' Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift \
  || { echo "✗ Approvals no longer lists every grant under the pack"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$PACK" "$TREND" "$EXPO" "$CPACK" "$TMP/"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
import CoreGraphics

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
typealias Grant = WalletApprovalExposure.Grant
func grant(_ spender: String, usd: Double?, symbol: String = "USDC", unlimited: Bool = true,
           forAll: Bool = false) -> Grant {
    Grant(thingID: UUID(), spender: spender, spenderAddress: "0x", named: true, symbol: symbol,
          forAll: forAll, unlimited: unlimited, usd: usd, capTokens: unlimited ? nil : 500, grantedAt: nil)
}
let uni = grant("Uniswap", usd: 1820)
let uniWeth = grant("Uniswap", usd: 30, symbol: "WETH", unlimited: false)
let permit = grant("Permit2", usd: 412, symbol: "WETH")
let inch = grant("1inch", usd: 50, unlimited: false)
let sea = grant("OpenSea", usd: nil, symbol: "PPG", unlimited: false, forAll: true)
let free = grant("Freebie", usd: nil)

// ── One circle per app ───────────────────────────────────────────────
let p = PermissionsPack.pieces([inch, sea, uniWeth, permit, uni, free])
check(p.map(\.name) == ["Uniswap", "Permit2", "1inch", "Freebie", "OpenSea"],
      "largest first, then the unpriced: no limit before a collection")
check(p[0].usd == 1850 && p[0].grantIDs.count == 2, "an app's grants are one circle, its dollars added")
check(p[0].symbols == ["USDC", "WETH"], "what it reaches, most dollars first")
check(p[0].unlimited, "an app is ringed when any grant has no limit")
check(!p[2].unlimited, "a capped app is not ringed")
check(!p[4].unlimited && p[4].forAll, "a collection is not ringed as no limit")
check(PermissionsPack.total(p) == 2312, "the total is every priced dollar")
check(PermissionsPack.total(PermissionsPack.pieces([sea, free])) == nil, "nothing priced states no total")
check(PermissionsPack.pieces([]).isEmpty, "no grants, no circles")
let tie = PermissionsPack.pieces([grant("Capped", usd: 100, unlimited: false), grant("Open", usd: 100)])
check(tie.map(\.name) == ["Open", "Capped"], "no limit wins a tie")
check(PermissionsPack.pieces([grant("Zero", usd: 0), inch]).first?.name == "1inch",
      "an emptied token reaches nothing and sorts with the unpriced")

// ── Eight, then one More ─────────────────────────────────────────────
let nine = (1...9).map { grant("G\($0)", usd: Double(100 - $0)) }
check(PermissionsPack.pieces(nine).count == 9 && !PermissionsPack.pieces(nine).contains(where: \.isMore),
      "one app past eight is drawn, never folded alone")
let twelve = (1...12).map { grant("G\($0)", usd: Double(100 - $0)) }
let folded = PermissionsPack.pieces(twelve)
check(folded.count == 9 && folded.last?.isMore == true, "past eight, the rest are one More")
check(folded.last?.apps == 4 && folded.last?.grantIDs.count == 4, "More holds the four it folds")
check(folded.last?.usd == (9...12).map { Double(100 - $0) }.reduce(0, +), "More's dollars are theirs")
check(folded.last?.unlimited == false, "More is grey")

// ── Delegates and modules are circles (§1677) ────────────────────────
let module = PermissionsPack.Acting(key: "0xmod", name: "Allowance module", module: true)
let delegate = PermissionsPack.Acting(key: "0xdel", name: "MetaMask", module: false)
let onlyModule = PermissionsPack.pieces([], acting: [module])
check(onlyModule.count == 1 && onlyModule[0].isActing && onlyModule[0].module,
      "a module alone is a circle, so the box never says empty over a Delegations row")
check(onlyModule[0].unlimited && !onlyModule[0].priced, "a module is no limit and unpriced")
check(onlyModule[0].symbols == ["Safe module"], "a module says what it is")
let mixed = PermissionsPack.pieces([sea, uni, free], acting: [module, delegate])
check(mixed.map(\.name) == ["Uniswap", "Allowance module", "MetaMask", "Freebie", "OpenSea"],
      "priced first, then delegates and modules, then the unpriced grants")
check(PermissionsPack.pieces([], acting: [delegate, delegate]).count == 1, "one circle per delegate contract")
let twin = PermissionsPack.Acting(key: "0xother", name: "MetaMask", module: false)
check(PermissionsPack.pieces([], acting: [delegate, twin]).count == 2,
      "two contracts with one name stay two circles")
check(PermissionsPack.total(mixed) == 1820, "a delegate adds no dollars")

// ── The disc: your balance, reached (§1710) ─────────────────────────
let held = PermissionsPack.heldByAccount([(holder: "0xAAA", usd: 8000), (holder: "0xaaa", usd: 2000),
                                          (holder: "0xBBB", usd: 2480), (holder: "kraken", usd: 9000)],
                                         isVenue: { $0 == "kraken" })
check(held == ["0xaaa": 10000, "0xbbb": 2480], "held is per wallet, lowercased, places left out")
let modA = PermissionsPack.Acting(key: "0xmod", name: "...0002", module: true, accounts: ["0xAAA"])
let delA = PermissionsPack.Acting(key: "0xdel", name: "...51d3", module: false, accounts: ["0xaaa"])
let delB = PermissionsPack.Acting(key: "0xdel2", name: "...77e1", module: false, accounts: ["0xbbb"])
let reached = PermissionsPack.pieces([], acting: [modA, delA], held: held)
check(reached.allSatisfy { $0.usd == 10000 }, "a delegate's dollars are its account's")
let partial = PermissionsPack.disc(reached, acting: [modA, delA], held: held)
check(partial.acting == 10000, "two on one wallet count it once")
check(!partial.whole && partial.reach == 10000, "a wallet nothing acts for stays out of reach")
check(PermissionsPack.inner(reached, disc: partial).count == 2, "a partial delegate is a circle inside")
let all = PermissionsPack.disc(PermissionsPack.pieces([], acting: [modA, delB], held: held),
                               acting: [modA, delB], held: held)
check(all.whole && all.reach == 12480, "every wallet acted for: the whole disc, the balance")
let allPieces = PermissionsPack.pieces([uni], acting: [modA, delB], held: held)
check(PermissionsPack.inner(allPieces, disc: all).map(\.name) == ["Uniswap"],
      "the whole disc's delegates are the disc, the grants still inside")
let unread = PermissionsPack.disc(PermissionsPack.pieces([], acting: [modA], held: [:]), acting: [modA], held: [:])
check(unread.whole && unread.reach == nil, "a delegate with no balance read reaches everything, unpriced")
let grantsOnly = PermissionsPack.disc(PermissionsPack.pieces([uni, inch], held: held), acting: [], held: held)
check(!grantsOnly.whole && grantsOnly.reach == 1870 && grantsOnly.scale == 12480,
      "grants alone: their dollars of the balance")
let over = PermissionsPack.disc(PermissionsPack.pieces([grant("Big", usd: 20000)], held: held), acting: [], held: held)
check(over.reach == 12480 && over.scale == 20000, "reach never states more than you hold")
check(PermissionsPack.total(allPieces) == 1820, "a delegate's dollars stay out of the grants' total")

let d: CGFloat = 200
let ins = PermissionsPack.inside([3200, 900, 150], scale: 12480, diameter: d)
check(abs(ins[0].radius - 100 * CGFloat((3200.0 / 12480).squareRoot())) < 0.5, "a circle's area is its share of the disc")
check(abs(ins[1].radius / ins[0].radius - CGFloat((900.0 / 3200).squareRoot())) < 0.03, "the ratios are the dollars'")
check(ins.allSatisfy { hypot($0.center.x - d / 2, $0.center.y - d / 2) + $0.radius <= d / 2 + 0.5 },
      "every circle inside the disc")
var apart = true
for i in ins.indices { for j in ins.indices where j > i {
    if hypot(ins[i].center.x - ins[j].center.x, ins[i].center.y - ins[j].center.y) < ins[i].radius + ins[j].radius - 0.5 { apart = false }
} }
check(apart, "no two circles overlap")
let full = PermissionsPack.inside([6000, 6000], scale: 12000, diameter: d)
check(full.allSatisfy { hypot($0.center.x - d / 2, $0.center.y - d / 2) + $0.radius <= d / 2 + 0.5 },
      "a pack too big for true area shrinks to fit")
check(PermissionsPack.inside([], scale: 1, diameter: d).isEmpty, "nothing priced, nothing inside")

// ── The trend ────────────────────────────────────────────────────────
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
cal.firstWeekday = 1
func day(_ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))! }
let now = day(10, 31)
let dates = [day(10, 20), day(10, 24), day(10, 26), day(10, 26), day(10, 27), day(9, 10), day(9, 22), day(8, 15), day(5, 1)]
let t = ThreatTrend.read(dates, now: now, calendar: cal)
check(t.weeks.count == 12 && t.starts.count == 12, "twelve weeks")
check(t.thisMonth == 5 && t.lastMonth == 2, "October 5, September 2")
check(t.compare == .up(from: 2), "more than last month is up")
check(t.thisWeek == 3, "this week holds Oct 26, 26 and 27")
check(t.weeks.reduce(0, +) == 8, "a threat older than twelve weeks draws no bar")
check(ThreatTrend.read([day(11, 2)], now: now, calendar: cal).thisMonth == 0, "a date after now is not counted")
check(ThreatTrend.read([day(9, 2)], now: now, calendar: cal).compare == .down(from: 1), "none this month after one is down")
check(ThreatTrend.read([], now: now, calendar: cal).compare == .quiet, "none either month is quiet")
check(ThreatTrend.read([day(10, 2)], now: now, calendar: cal).compare == .firstSince, "the first after a quiet month")
let labels = t.monthLabels(calendar: cal)
check(labels.count >= 2, "the axis names the months")
let keys = labels.keys.sorted()
check(zip(keys, keys.dropFirst()).allSatisfy { $1 - $0 > 2 }, "two month names stand three bars apart")
// First week starts Aug 30 (a Sunday), the next Sep 6: September turns at bar 1.
let turn = ThreatTrend.read([], now: day(11, 18), calendar: cal)
let turnLabels = turn.monthLabels(calendar: cal)
check(cal.component(.day, from: turn.starts[0]) == 30 && turnLabels[0] == nil && turnLabels[1] != nil,
      "a month turning at bar 1 is named there, not hidden behind the month before")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
print("✓ permissions and threats boxes")
SWIFT
swiftc -O -o "$TMP/run" "$TMP"/*.swift 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ did not compile"; exit 1; }
"$TMP/run"
