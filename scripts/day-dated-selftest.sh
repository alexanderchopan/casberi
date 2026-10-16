#!/bin/zsh
# Casberi day-dated self-test — Day's Coming up carries what the app COMPUTES
# as well as what it stores (prd §1327 item 3):
#
#   Casberi/Casberi/Model/DayDated.swift       (compiled whole: the window,
#                                               the entries, the merge by day)
#   Casberi/Casberi/Model/Subscriptions.swift  (compiled whole, with the
#                                               AppleWalletRoom.swift, RoomLede.swift
#                                               and SubscriptionPlans.swift it reads)
#   Casberi/Casberi/Model/WalletCardRoll.swift (compiled whole)
#
# WHY A HARNESS. Every failure here renders as a calm week. A window that
# starts at "now" drops the plan renewing this morning; one that ends a day
# late lists next week's bill; a renewal Day dates itself drifts from the
# Wallet's (§837: two places, two dates); a Rocket Money bill whose cadence no
# one said is called a renewal; a fresh price rise the Wallet flags is
# silent here; a day only a renewal stands on vanishes. None of that fails a
# build or a screen sweep. The drift guards say Day reads each place's own
# reading, one bill stands once, and the figures honour Hide balances.
#
# Pure, local, deterministic. Exit non-zero on failure. `--self-test` (and
# every plain run) also proves each check can fail: plausible mutations of
# DayDated.swift must be CAUGHT.
set -euo pipefail
cd "$(dirname "$0")/.."

DAY="Casberi/Casberi/Model/DayDated.swift"
SUBS="Casberi/Casberi/Model/Subscriptions.swift"
AWR="Casberi/Casberi/Model/AppleWalletRoom.swift"
LEDE="Casberi/Casberi/Model/RoomLede.swift"
PLANS="Casberi/Casberi/Model/SubscriptionPlans.swift"
ROLL="Casberi/Casberi/Model/WalletCardRoll.swift"
COMING="Casberi/Casberi/Screens/FeedScreen+ComingUp.swift"
ROWS="Casberi/Casberi/Screens/FeedScreen+DayDated.swift"
SECTIONS="Casberi/Casberi/Screens/FeedScreen+DaySections.swift"
ROOM="Casberi/Casberi/Screens/FeedScreen+MergedRoom.swift"
SCOPE="Casberi/Casberi/Model/DayScope.swift"
for f in "$DAY" "$SUBS" "$AWR" "$LEDE" "$PLANS" "$ROLL" "$COMING" "$ROWS" "$SECTIONS" "$ROOM" "$SCOPE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring the compiled functions cannot prove about themselves.
grep -q 'DayDated.renewals(plans.items' "$COMING" \
  || { echo "✗ Coming up no longer dates renewals off the Wallet's own reading (SubscriptionsReading)"; exit 1; }
grep -q 'DayDated.cardDues(SpendingReading.shared.cards' "$COMING" \
  || { echo "✗ Coming up no longer dates card payments off Home's own reading (SpendingReading)"; exit 1; }
grep -q '.task(id: dayComingUpKey) { await loadDayComingUp() }' "$COMING" \
  || { echo "✗ Coming up is no longer read in a task (prd §628)"; exit 1; }
grep -q 'SubscriptionsSource.isBill(' "$COMING" \
  || { echo "✗ a Rocket Money bill stands twice in Coming up: its stored row and its plan (§1105)"; exit 1; }
grep -q 'groupedSections(groups, nextEventID: nextEventID, entries: entries)' "$COMING" \
  || { echo "✗ Coming up no longer hands its computed entries to the days"; exit 1; }
grep -q 'ForEach(entries) { entry in dayDatedRow(entry) }' "$SECTIONS" \
  || { echo "✗ a day no longer draws its computed entries"; exit 1; }
grep -q 'BalancePrivacy.shared.withheld' "$ROWS" \
  || { echo "✗ Coming up's figures no longer honour Hide balances"; exit 1; }
grep -q 'feedSheet = .subscription(id)' "$ROWS" \
  || { echo "✗ a renewal no longer opens the plan's own sheet"; exit 1; }
grep -q 'case .subscription: return SubscriptionWords.track' "$SCOPE" \
  || { echo "✗ Day's New lost Track a subscription, or its verb is not SubscriptionWords.track"; exit 1; }
grep -q 'feedSheet = .subscriptionAdd' "$ROOM" \
  || { echo "✗ Day's Track a subscription no longer raises the Wallet's own tray"; exit 1; }
# Day never dates a thing itself: no arithmetic on a date in the model's code.
if grep -v '^[[:space:]]*//' "$DAY" | grep -Eq 'addingTimeInterval|date\(byAdding|nextExpected|nextRenewal|cadenceDays \*'; then
  echo "✗ DayDated computes a date — read it off the place's own reading instead"; exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
// Thursday 15 October 2026, 15:00.
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 15))!
let today = cal.startOfDay(for: now)
let end = cal.date(byAdding: .day, value: 7, to: today)!          // Coming up's week
func day(_ d: Int, hour: Int = 9) -> Date { cal.date(byAdding: .hour, value: d * 24 + hour, to: today)! }

func plan(_ name: String, next: Date?, cadence: Int? = 30, amount: Double? = 10,
          was: Double? = nil, pays: String? = "Apple Card") -> Subscriptions.Item {
    .init(id: Subscriptions.key(name), name: name, amount: amount, currency: "USD", cadenceDays: cadence,
          next: next, paysWith: pays, since: nil, paid: nil, was: was, site: nil, manualID: nil,
          foundIn: ["Apple Wallet"])
}

// ── Renewals, as the Wallet dates them ───────────────────────────────
let netflix = plan("Netflix", next: day(1), amount: 15.49, was: 13.99)
let r = DayDated.renewals([netflix], now: now, end: end, calendar: cal)
check(r.count == 1, "a renewal tomorrow is in Coming up")
check(r.first?.when == netflix.next, "on the Wallet's own day, never re-dated")
check(r.first?.id == "plan:\(netflix.id)" && r.first?.opens == .plan(netflix.id),
      "it opens the plan's own sheet, by its key")
check(r.first?.place == .subscription && r.first?.word == .renews, "a plan with a cadence renews")
check(r.first?.amount == 15.49 && r.first?.currency == "USD", "with its price")
check(r.first?.was == 13.99, "and the price rise the Wallet flags")
check(r.first?.paysWith == "Apple Card", "and what pays it")
check(DayDated.renewals([plan("RM", next: day(2), cadence: nil)], now: now, end: end, calendar: cal)
        .first?.word == .nextCharge, "a bill whose cadence nobody said is a next charge, not a renewal")
check(DayDated.renewals([plan("None", next: nil)], now: now, end: end, calendar: cal).isEmpty,
      "a plan with no next date is not dated, and none is invented")

// ── The window ───────────────────────────────────────────────────────
func inWeek(_ d: Date) -> Bool {
    !DayDated.renewals([plan("X", next: d)], now: now, end: end, calendar: cal).isEmpty
}
check(inWeek(day(0, hour: 8)), "a renewal due this morning is still today's (a plan has no time of day)")
check(!inWeek(day(-1, hour: 23)), "yesterday's is not coming up")
check(inWeek(end.addingTimeInterval(-1)), "the week's last day is in")
check(!inWeek(end), "the midnight after it is not")
check(inWeek(day(6)), "six days ahead is in")

// ── Cards, as their issuer dates them ────────────────────────────────
var apple = WalletCardRoll.Card(name: "Apple Card", app: "Apple Wallet")
apple.owed = 412.30; apple.due = day(3)
var amex = WalletCardRoll.Card(name: "Amex", app: "Apple Wallet")
amex.due = day(12); amex.owed = 50
let quiet = WalletCardRoll.Card(name: "Quiet", app: "Apple Wallet")
let c = DayDated.cardDues([apple, amex, quiet], now: now, end: end, calendar: cal)
check(c.map(\.name) == ["Apple Card"], "a card's payment date this week is in; next month's and none are not")
check(c.first?.when == apple.due && c.first?.word == .due && c.first?.place == .card,
      "on its issuer's own date, as a payment due")
check(c.first?.amount == 412.30, "with what it owes")
check(c.first?.opens == .card(app: "Apple Wallet"), "it opens the app that reads the card, as the Wallet's row does")

// ── One list, soonest first ──────────────────────────────────────────
let a = DayDated.renewals([plan("Zed", next: day(2)), plan("Abe", next: day(2)), plan("Soon", next: day(1))],
                          now: now, end: end, calendar: cal)
let merged = DayDated.entries([a, c])
check(merged.map(\.name) == ["Soon", "Abe", "Zed", "Apple Card"],
      "soonest first, a tie by name, every place in one list")
check(DayDated.entries([c, a]).map(\.id) == merged.map(\.id), "the order never depends on the order handed in")
check(DayDated.entries([a, a]).count == a.count, "an entry handed twice stands once")

// ── The days ─────────────────────────────────────────────────────────
let u1 = UUID(), u2 = UUID(), u3 = UUID()
let days = DayDated.days(stored: [(id: u1, when: day(1, hour: 10)), (id: u2, when: day(1, hour: 11)),
                                  (id: u3, when: day(4))],
                         dated: merged, calendar: cal)
check(days.map(\.start) == [day(1, hour: 0), day(2, hour: 0), day(3, hour: 0), day(4, hour: 0)],
      "days soonest first, a day only an entry stands on included")
check(days.first?.stored == [u1, u2] && days.first?.dated.map(\.name) == ["Soon"],
      "a day keeps its stored rows in order and holds its entries")
check(days[1].stored.isEmpty && days[1].dated.map(\.name) == ["Abe", "Zed"], "an entry-only day is a day")
check(DayDated.days(stored: [(id: u1, when: day(1))], dated: [], calendar: cal).count == 1,
      "with nothing computed, the stored week is unchanged")

// ── Through the Wallet's own compose ─────────────────────────────────
// Three charges a month apart on a card, a Rocket Money bill, a plan tracked
// by hand: Day's day is whatever `Subscriptions.compose` said.
typealias Spend = AppleWalletRoom.Spend
let charges = [70.0, 40.0, 10.0].map { Spend(merchant: "Claude", amount: 20, currency: "USD",
                                             date: now.addingTimeInterval(-$0 * 86_400)) }
let series = AppleWalletRoom.recurringSeries(charges, now: now)
let found = series.map { Subscriptions.Found(series: $0, paysWith: "Apple Card", source: "Apple Wallet", was: nil) }
let bill = Subscriptions.Bill(name: "Gym", amount: 45, currency: "USD", due: day(5), source: "Rocket Money")
let manual = Subscriptions.Manual(id: "m1", name: "Paper", amount: 4, currency: "USD", yearly: false,
                                  anchor: cal.date(byAdding: .month, value: -2, to: day(2))!, paysWith: nil,
                                  site: nil, at: now)
let items = Subscriptions.compose(found: found, bills: [bill], manual: [manual], now: now, calendar: cal)
let fromWallet = DayDated.renewals(items, now: now, end: end, calendar: cal)
for item in items {
    let entry = fromWallet.first { $0.id == "plan:\(item.id)" }
    if let next = item.next, next >= today, next < end {
        check(entry?.when == next, "\(item.name): Day's day is the Wallet's (\(next))")
    } else {
        check(entry == nil, "\(item.name): outside the week, not in Coming up")
    }
}
check(fromWallet.first { $0.name == "Gym" }?.word == .nextCharge, "the Rocket Money bill reads as a next charge")
check(fromWallet.contains { $0.name == "Paper" }, "a plan tracked by hand renews on its anchor's day")

if failures > 0 { print("✗ day dated: \(failures) failing"); exit(1) }
print("✓ day dated self-test passed")
SWIFT

build() { # $1 DayDated.swift, $2 binary
  swiftc -Onone -o "$2" "$1" "$SUBS" "$AWR" "$LEDE" "$PLANS" "$ROLL" "$TMP/main.swift" 2>&1 | grep -v '^ *$' || true
}

build "$DAY" "$TMP/run"
[[ -x "$TMP/run" ]] || { echo "✗ day dated harness did not compile — DayDated no longer builds Foundation-only"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Each mutation is a plausible edit that must be CAUGHT. A check that cannot
# fail proves nothing (the `--self-test` doctrine used by every audit here).
mutate() {
  local label="$1" expr="$2"
  python3 - "$DAY" "$TMP/mutated.swift" "$expr" <<'PY' || { echo "  ✗ STALE MUTATION: the applier exited non-zero (anchor not found — nothing was tested)"; exit 1; }
import sys
src = open(sys.argv[1]).read()
old, new = sys.argv[3].split("|||")
if old not in src:
    sys.exit(f"✗ mutation anchor not found: {old!r} — this harness is testing stale code")
open(sys.argv[2], "w").write(src.replace(old, new, 1))
PY
  rm -f "$TMP/mrun"
  build "$TMP/mutated.swift" "$TMP/mrun" >/dev/null
  # A mutation that does not compile tests nothing: it must run, and fail.
  [[ -x "$TMP/mrun" ]] || { echo "  ✗ mutation did not compile: $label"; return 1; }
  if "$TMP/mrun" >/dev/null 2>&1; then
    echo "  ✗ mutation SURVIVED: $label"
    return 1
  fi
  echo "  ✓ mutation caught: $label"
}

echo "day-dated-selftest: mutation pass…"
mfail=0
mutate "the window starts now, dropping this morning's renewal" \
  'when >= calendar.startOfDay(for: now) && when < end|||when > now && when < end' || mfail=1
mutate "the window runs a day late" \
  'when >= calendar.startOfDay(for: now) && when < end|||when >= calendar.startOfDay(for: now) && when <= end' || mfail=1
mutate "a bill with no cadence is called a renewal" \
  'word: item.cadenceDays == nil ? .nextCharge : .renews|||word: .renews' || mfail=1
mutate "the price rise is dropped" \
  'was: item.was, paysWith|||was: nil, paysWith' || mfail=1
mutate "a renewal is dated a cadence after the Wallet's day" \
  'when: next, place: .subscription|||when: next.addingTimeInterval(Double(item.cadenceDays ?? 0) * 86_400), place: .subscription' || mfail=1
mutate "a card's due date outside the week is listed" \
  'guard let due = card.due, inWindow(due, now: now, end: end, calendar: calendar)|||guard let due = card.due' || mfail=1
mutate "a card's figure is dropped" \
  'word: .due, amount: card.owed|||word: .due, amount: nil' || mfail=1
mutate "the list runs latest first" \
  'if a.when != b.when { return a.when < b.when }|||if a.when != b.when { return a.when > b.when }' || mfail=1
mutate "a tie loses its name order" \
  'return byName == .orderedAscending|||return byName == .orderedDescending' || mfail=1
mutate "an entry handed twice stands twice" \
  '.filter { seen.insert($0.id).inserted }|||.filter { _ in true }' || mfail=1
mutate "the days run latest first" \
  'return byDay.values.sorted { $0.start < $1.start }|||return byDay.values.sorted { $0.start > $1.start }' || mfail=1
mutate "an entry-only day vanishes" \
  'byDay[day, default: Day(start: day, stored: [], dated: [])].dated.append(entry)|||byDay[day]?.dated.append(entry)' || mfail=1

[[ $mfail -eq 0 ]] || { echo "day-dated-selftest: a mutation SURVIVED — a check above proves nothing"; exit 1; }
echo "day-dated-selftest: OK — the window, each place's own day, the order and the days all pinned."
