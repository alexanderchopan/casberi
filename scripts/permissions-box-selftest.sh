#!/bin/zsh
# Casberi Permissions/Threats box self-test — what each page's box says
# (prd §1633):
#
#   Casberi/Casberi/Model/PermissionsLead.swift        (compiled whole)
#   Casberi/Casberi/Model/ThreatTrend.swift            (compiled whole)
#   Casberi/Casberi/Model/WalletApprovalExposure.swift (compiled whole: the grant)
#   Casberi/Shared/AddressTail.swift                   (compiled whole: the unknown delegate's line)
#
# WHY A HARNESS. Both failures render as a calm box. Pick the wrong lead and
# the sentence names an ordinary grant while an unknown delegate sits in the
# list; bucket a week wrong and the bars say threats are falling while they
# rise. Neither shows on a screenshot of one wallet.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

LEAD="Casberi/Casberi/Model/PermissionsLead.swift"
TREND="Casberi/Casberi/Model/ThreatTrend.swift"
EXPO="Casberi/Casberi/Model/WalletApprovalExposure.swift"
TAIL="Casberi/Shared/AddressTail.swift"
for f in "$LEAD" "$TREND" "$EXPO" "$TAIL"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
grep -q 'WalletPermissionsFigure(lead: walletPermissionsLead' Casberi/Casberi/Screens/FeedScreen+WalletPages.swift \
  || { echo "✗ Permissions' box no longer leads with the worst one"; exit 1; }
grep -q 'ThreatTrend.read(' Casberi/Casberi/Screens/FeedScreen+WalletPages.swift \
  || { echo "✗ Threats' box no longer reads the trend"; exit 1; }
grep -q 'exposure(walletLive.exposure, leaving: lead)' Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift \
  || { echo "✗ the box's lead is listed twice — Approvals no longer leaves it out"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$LEAD" "$TREND" "$EXPO" "$TAIL" "$TMP/"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
typealias Grant = WalletApprovalExposure.Grant
func grant(_ spender: String, usd: Double?, unlimited: Bool = true, forAll: Bool = false,
           granted: Date? = nil) -> Grant {
    Grant(thingID: UUID(), spender: spender, spenderAddress: "0x", named: true, symbol: "USDC",
          forAll: forAll, unlimited: unlimited, usd: usd, capTokens: unlimited ? nil : 500, grantedAt: granted)
}
let uni = grant("Uniswap", usd: 1820)
let permit = grant("Permit2", usd: 412)
let inch = grant("1inch", usd: 50, unlimited: false)
let sea = grant("OpenSea", usd: nil, unlimited: false, forAll: true)
let known = PermissionsLead.Delegate(key: "0xmm", name: "MetaMask", accounts: ["Main"])
let unknown = PermissionsLead.Delegate(key: "0xbad", name: nil, accounts: ["Main"])

// ── What leads ───────────────────────────────────────────────────────
check(PermissionsLead.pick(grants: [inch, permit, uni, sea], delegates: [known]) == .grant(uni),
      "the most dollars at stake leads, over your own wallet's delegate")
check(PermissionsLead.pick(grants: [uni], delegates: [known, unknown]).map { $0.isUnknownDelegate } == true,
      "a delegate nobody can name leads over every grant")
check(PermissionsLead.pick(grants: [], delegates: [known]) == .delegate(key: "0xmm", name: "MetaMask", accounts: ["Main"]),
      "your own wallet's delegate leads only when it is all there is")
check(PermissionsLead.pick(grants: [], delegates: []) == nil, "nothing leads an empty page")
let capped = grant("Big", usd: 2000, unlimited: false)
check(PermissionsLead.pick(grants: [uni, capped], delegates: []) == .grant(capped),
      "a capped grant reaching more dollars leads an unlimited one reaching less")
let tieCapped = grant("Capped", usd: 100, unlimited: false), tieOpen = grant("Open", usd: 100)
check(PermissionsLead.worstGrant([tieCapped, tieOpen]) == tieOpen, "no limit wins a tie")
let old = Date(timeIntervalSince1970: 1_600_000_000), new = Date(timeIntervalSince1970: 1_700_000_000)
let unpricedOld = grant("Old", usd: nil, granted: old), unpricedNew = grant("New", usd: nil, granted: new)
check(PermissionsLead.worstGrant([sea, unpricedNew, unpricedOld]) == unpricedOld,
      "nothing priced: the oldest grant with no limit leads, before a collection")
check(PermissionsLead.worstGrant([grant("Zero", usd: 0), inch]) == inch,
      "an unlimited grant on an emptied token reaches nothing and does not lead")

// ── The words ────────────────────────────────────────────────────────
check(PermissionsLead.grant(uni).title == "Unlimited approval", "an unlimited grant is named by its kind, nothing more")
check(PermissionsLead.grant(inch).title == "Capped approval", "a capped grant")
check(PermissionsLead.grant(sea).title == "Collection approval", "a whole-collection grant")
check(PermissionsLead.grant(uni).line == "Uniswap · USDC", "the line is whose and on what")
check(PermissionsLead.delegate(key: "0x", name: nil, accounts: ["Main"]).title == "Unknown delegate",
      "an unknown delegate says so, no more")
check(PermissionsLead.delegate(key: "0x4b19aa00000000000000000000000000c0dee07a", name: nil, accounts: ["Main"]).line == "...e07a · Main",
      "an unknown delegate's line is its address tail and the account")
check(PermissionsLead.delegate(key: "0x", name: "MetaMask", accounts: ["Main"]).line == "MetaMask · Main",
      "a delegate's line names it and the account")

// ── Safe modules ─────────────────────────────────────────────────────
let module = PermissionsLead.Delegate(key: "0xmod", name: "Allowance module", accounts: ["Safe"], module: true)
check(PermissionsLead.pick(grants: [], delegates: [module]) == .module(key: "0xmod", name: "Allowance module", accounts: ["Safe"]),
      "a module alone leads — the box never says no app can spend over a listed module")
check(PermissionsLead.pick(grants: [uni], delegates: [module]) == .grant(uni), "a module never pushes a grant out")
check(PermissionsLead.pick(grants: [], delegates: [module, known]) == .delegate(key: "0xmm", name: "MetaMask", accounts: ["Main"]),
      "your wallet's delegate leads before a module")

// ── The strip's widths ───────────────────────────────────────────────
let fit = PermissionsLead.widths([1820, 2, 2, 2, 2, 2], in: 340, floor: 10, gap: 2)
check(abs(fit.reduce(0, +) + 10 - 340) < 0.001, "pieces and gaps fill the width exactly, never past it")
check(fit.dropFirst().allSatisfy { abs($0 - 10) < 0.001 }, "a sliver takes the floor")
let crowd = PermissionsLead.widths(Array(repeating: 1, count: 40), in: 100, floor: 10, gap: 2)
check(crowd.allSatisfy { $0 >= 0 } && crowd.reduce(0, +) + 78 <= 100.001, "too many for their floors still fit")

// ── The strip ────────────────────────────────────────────────────────
let strip = PermissionsLead.strip([inch, sea, uni, permit], lead: uni.thingID)
check(strip.map(\.name) == ["Uniswap", "Permit2", "1inch"], "the strip is the priced grants, largest first")
check(strip.filter(\.lit).map(\.name) == ["Uniswap"], "only the lead is lit")
let many = (1...9).map { grant("G\($0)", usd: Double(100 - $0)) }
let folded = PermissionsLead.strip(many, lead: many[8].thingID)
check(folded.count == 7 && folded.last?.id == "rest", "past six, the rest are one piece")
check(folded.last?.lit == true, "a lead folded into the rest still lights it")

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
