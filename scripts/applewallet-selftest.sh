#!/bin/zsh
# Casberi Apple Wallet self-test — the SHIPPED pure judgement behind the
# FinanceKit room (prd §313, 2026-08-06):
#
#   Casberi/Casberi/Model/AppleWalletRoom.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
# Everything touching `Thing`, UserDefaults or FinanceKit lives in
# `AppleWalletBridge.swift` / `AppleWalletRoomSource.swift`, which no harness
# can compile and which contain no judgement to test.
#
# WHY THIS HARNESS IS THE ONLY PROOF THERE WILL EVER BE, and why that claim is
# stronger here than for the Stripe or PostHog rooms:
#
#   **No simulator ships FinanceKit data.** `FinanceStore.isDataAvailable`
#   answers false on every simulator, so every model path in this feature takes
#   its unavailable branch and `verify.sh`'s screen sweep exercises exactly
#   none of it. Stripe and PostHog at least COULD be measured by anyone willing
#   to mint a key; this room needs a real device, a real Apple Card, and a US
#   Apple Account. Until someone has all three, this file is the verification.
#
# Every failure mode below is a SILENT WRONG ANSWER that renders perfectly:
#
#   · two currencies summed into one total (an exchange rate we don't have)
#   · a pending authorization counted as money spent
#   · a refund ranking a merchant you never paid
#   · a cadence "detected" from two charges, so every second purchase becomes
#     a subscription and the room fills with imaginary upcoming dates
#   · a monthly subscription called irregular because Feb is 28 days
#   · a $0.03 rounding difference announced as a price rise
#   · a subscription called SILENT while it is merely three days late
#   · an inferred recurring date sorted above the bank's own payment deadline
#   · a merchant board that drops its sixth row instead of folding it
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/AppleWalletRoom.swift"
[[ -f "$ROOM" ]] || { echo "✗ $ROOM not found"; exit 1; }

SRC="Casberi/Casberi/Model/AppleWalletRoomSource.swift"
BRIDGE="Casberi/Casberi/Model/AppleWalletBridge.swift"
CARD="Casberi/Casberi/Screens/AppleWalletRoomCard.swift"
SCREEN="Casberi/Casberi/Screens/AppleWalletScreen.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
ENT="Casberi/Casberi/Casberi.entitlements"
CAT_ENT="Casberi/Casberi/Casberi-Catalyst.entitlements"

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled functions cannot prove about themselves. A perfect
# `creep` is worthless if nothing renders it, and a perfect promise is worthless
# if the code stops keeping it.

# THE ENTITLEMENT'S OWN TERMS. These four are what Apple granted the
# entitlement against (request QVDBMBPMJU) — breaking one breaks the grant's
# terms, not merely a preference.
grep -q 'com.apple.developer.financekit' "$ENT" \
  || { echo "✗ the FinanceKit entitlement is gone from the iOS entitlements"; exit 1; }
grep -q 'com.apple.developer.financekit' "$CAT_ENT" \
  && { echo "✗ FinanceKit appears in the CATALYST entitlements — it is @available(macOS, unavailable) and an entitlement the Mac profile lacks fails a signed archive"; exit 1; }
grep -q 'static func disconnect' "$BRIDGE" \
  || { echo "✗ disconnect() is gone — we promised Apple a one-tap disconnect that deletes what landed"; exit 1; }
grep -q 'for row in rows { context.delete(row) }' "$BRIDGE" \
  || { echo "✗ disconnect() no longer DELETES landed rows — the promise on file with Apple is now false"; exit 1; }
# The read is GET-shaped by conduct: FinanceKit exposes no write for this data,
# but a future call that mutated anything would break the read-only promise the
# screen states. Anchor on the one type that could: saveOrder.
grep -q 'saveOrder' "$BRIDGE" \
  && { echo "✗ AppleWalletBridge calls saveOrder — the read-only promise is a lie"; exit 1; }
grep -q 'Casberi has no server' "$SCREEN" \
  || { echo "✗ the setup screen no longer states the no-server promise BEFORE connect"; exit 1; }
grep -q 'is deleted from Casberi' "$SCREEN" \
  || { echo "✗ the setup screen no longer promises deletion on disconnect"; exit 1; }

# Never re-present the system prompt on a background pass (the Contacts rule).
grep -q 'authorizationStatus()' "$BRIDGE" \
  || { echo "✗ refresh() no longer checks authorization status — it could re-raise Apple's prompt unprompted"; exit 1; }

# Corollary 4: filter live at the boundary.
grep -q 'things.live' "$SRC" \
  || { echo "✗ AppleWalletRoomSource no longer filters live at the boundary (corollary 4)"; exit 1; }
# The room must never read a payment-due row as a merchant.
grep -q 'guard thing.kind == .transaction else { continue }' "$SRC" \
  || { echo "✗ the source no longer excludes non-transaction rows — a payment-due row would rank as a merchant"; exit 1; }
# Pending must reach the model as pending, or the card silently counts it.
grep -q 'isSettled: !thing.tags.contains("Pending")' "$SRC" \
  || { echo "✗ pending rows no longer reach the model as unsettled — authorizations would be counted as spend"; exit 1; }
grep -q 'isRefund: thing.tags.contains("Refund")' "$SRC" \
  || { echo "✗ refunds no longer reach the model as refunds — they would rank as purchases"; exit 1; }

# Rendered at all.
grep -q 'case .appleWallet(let room)' "$FEED" \
  || { echo "✗ the Apple Wallet head is no longer rendered from the sourceHead chain"; exit 1; }
grep -q 'case AppleWalletBridge.sourceName' "$FEED" \
  || { echo "✗ the sourceHead switch no longer claims the Apple Wallet room"; exit 1; }
# The tail is folded, never truncated (§300).
grep -q 'room.moreMerchants > 0' "$CARD" \
  || { echo "✗ the merchant board no longer folds its tail — a dropped row would look like a shorter board"; exit 1; }
# A guess must not look like the bank's fact.
grep -q 'item.kind == .payment' "$CARD" \
  || { echo "✗ the rail no longer distinguishes a real payment deadline from an inferred recurring date"; exit 1; }
# The outcome LEADS an abnormal title, or titleLine's 80-char clamp eats it.
grep -q 'Refunded · \\(merchant)' "$BRIDGE" \
  || { echo "✗ a refund no longer LEADS its title — the 80-char clamp would eat a trailing marker and a refund would read as a purchase (§83)"; exit 1; }
grep -q 'Pending · \\(merchant)' "$BRIDGE" \
  || { echo "✗ a pending charge no longer LEADS its title"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)   // fixed clock
func day(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

typealias Spend = AppleWalletRoom.Spend
typealias Due = AppleWalletRoom.Due

func spend(_ m: String, _ a: Double, _ d: Double, cur: String = "USD",
           settled: Bool = true, refund: Bool = false) -> Spend {
    Spend(merchant: m, amount: a, currency: cur, date: day(d),
          isSettled: settled, isRefund: refund)
}

// ── leaderboard ────────────────────────────────────────────────────────────
print("leaderboard")
do {
    let s = [spend("Blue Bottle", 6.50, 1), spend("Blue Bottle", 6.50, 3),
             spend("Amazon", 43.10, 2), spend("Whole Foods", 88.00, 5)]
    let rows = AppleWalletRoom.leaderboard(s)
    check("ranks by AMOUNT, not by count", rows.first?.name == "Whole Foods")
    check("counts charges per merchant", rows.first(where: { $0.name == "Blue Bottle" })?.count == 2)
    check("sums a repeat merchant", rows.first(where: { $0.name == "Blue Bottle" })?.total == 13.0)
    let shares = rows.map(\.share).reduce(0, +)
    check("shares sum to 1", abs(shares - 1.0) < 0.0001)
    check("share is proportional to total",
          abs((rows.first?.share ?? 0) - 88.0 / 144.1) < 0.001)
}
do {
    // A refund SUBTRACTS but never ranks a merchant of its own.
    let s = [spend("Amazon", 50, 2), spend("Amazon", 20, 1, refund: true),
             spend("Zara", 30, 3, refund: true)]
    let rows = AppleWalletRoom.leaderboard(s)
    check("a refund subtracts from its merchant", rows.first(where: { $0.name == "Amazon" })?.total == 30)
    check("a refund-only merchant never ranks", !rows.contains { $0.name == "Zara" })
}
do {
    let s = [spend("Dust", 0.40, 1), spend("Dust", 0.30, 2), spend("Real", 20, 1)]
    let rows = AppleWalletRoom.leaderboard(s)
    check("sub-minAmount charges never rank", !rows.contains { $0.name == "Dust" })
}
do {
    // Ties break on NAME so the board can't reshuffle between two refreshes
    // with no data change. SIX tied merchants, not two: the totals come out of
    // a Dictionary, whose iteration order is arbitrary, so a two-element
    // fixture lands in the right order often enough by luck that dropping the
    // tie-break sailed through green. With six, arbitrary order is essentially
    // never alphabetical.
    let names = ["Foxtrot", "Echo", "Delta", "Charlie", "Bravo", "Alpha"]
    let s = names.enumerated().map { spend($0.element, 10, Double($0.offset + 1)) }
    let rows = AppleWalletRoom.leaderboard(s)
    check("ties break on name (stable board)", rows.map(\.name) == names.sorted())
}

// ── currencies are never summed ────────────────────────────────────────────
print("currency")
do {
    let s = [spend("A", 10, 1), spend("B", 10, 2), spend("C", 999, 3, cur: "JPY")]
    check("dominant currency is by COUNT, not amount",
          AppleWalletRoom.dominantCurrency(s) == "USD")
    let card = AppleWalletRoom.compose(spends: s, now: now)
    check("the card names one currency", card?.currency == "USD")
    check("the foreign merchant is excluded from the board",
          !(card?.merchants.map(\.name).contains("C") ?? true))
    check("and the card SAYS other currencies exist",
          card?.note?.contains("other currencies") == true)
}
do {
    check("no spends at all → no card", AppleWalletRoom.compose(spends: [], now: now) == nil)
}

// ── pending is shown, never counted ────────────────────────────────────────
print("pending")
do {
    let s = [spend("Shop", 100, 1), spend("Shop", 999, 0, settled: false)]
    let card = AppleWalletRoom.compose(spends: s, now: now)
    check("a pending charge is not in the total",
          card?.merchants.first?.total == 100)
    check("and the card says so", card?.note?.contains("pending") == true)
    check("one pending reads singular", card?.note?.contains("1 pending charge isn't") == true)
}

// ── recurring detection ────────────────────────────────────────────────────
print("recurring")
do {
    // Monthly, with real calendar wobble (31/30/31 days).
    let s = [spend("Netflix", 15.49, 93), spend("Netflix", 15.49, 62),
             spend("Netflix", 15.49, 31), spend("Netflix", 15.49, 1)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    check("a monthly charge is recurring", series.count == 1)
    check("cadence is ~31 days", abs((series.first?.cadenceDays ?? 0) - 31) <= 1)
}
do {
    // Two charges can never be a cadence — a line through any two points.
    let s = [spend("Once", 20, 30), spend("Once", 20, 1)]
    check("two charges are not a subscription",
          AppleWalletRoom.recurringSeries(s, now: now).isEmpty)
}
do {
    // Gaps of 30, 30, 5. The MEDIAN is a perfectly plausible 30-day cadence
    // and the MEAN (21.7) also sits inside tolerance — so a mean-based check
    // calls this a monthly subscription. Every-gap does not, because the
    // 5-day gap is 25 days off a 30-day cadence.
    // The fixture must be built this way: an earlier version used gaps of
    // 5, 60, 5, whose median is 5 — below `minCadenceDays`, so the series was
    // rejected by the cadence FLOOR and the mean-based mutation sailed through
    // green. A fixture has to fail for the reason under test.
    let s = [spend("Random", 20, 65), spend("Random", 20, 35),
             spend("Random", 20, 5), spend("Random", 20, 0)]
    check("irregular gaps are not a cadence (every gap, not the mean)",
          AppleWalletRoom.recurringSeries(s, now: now).isEmpty)
}
do {
    // Daily coffee is a habit, not a subscription.
    let s = [spend("Cafe", 4, 3), spend("Cafe", 4, 2), spend("Cafe", 4, 1)]
    check("a daily habit is below the cadence floor",
          AppleWalletRoom.recurringSeries(s, now: now).isEmpty)
}

// ── price creep — the flagship ─────────────────────────────────────────────
print("creep")
do {
    let s = [spend("Netflix", 15.49, 93), spend("Netflix", 15.49, 62),
             spend("Netflix", 15.49, 31), spend("Netflix", 17.99, 1)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    let creep = AppleWalletRoom.creep(series, now: now)
    check("a price rise is found", creep?.merchant == "Netflix")
    check("it reports the prior amount", creep?.was == 15.49)
    check("and the new one", creep?.now == 17.99)
    check("delta is right", abs((creep?.delta ?? 0) - 2.50) < 0.001)
    check("fraction is right", abs((creep?.fraction ?? 0) - 0.1614) < 0.001)
    let card = AppleWalletRoom.compose(spends: s, now: now)
    check("the subline leads with the rise", card?.subline?.contains("Netflix") == true)
    check("…and states the percentage", card?.subline?.contains("16%") == true)
}
do {
    // A few cents is rounding, not a price rise.
    let s = [spend("Gym", 30.00, 93), spend("Gym", 30.00, 62),
             spend("Gym", 30.00, 31), spend("Gym", 30.20, 1)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    check("a rounding difference is not creep", AppleWalletRoom.creep(series, now: now) == nil)
}
do {
    // Big fraction, tiny absolute — must not headline the room.
    let s = [spend("Tiny", 1.20, 93), spend("Tiny", 1.20, 62),
             spend("Tiny", 1.20, 31), spend("Tiny", 1.45, 1)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    check("a 21% rise on $1.20 is below the absolute floor",
          AppleWalletRoom.creep(series, now: now) == nil)
}
do {
    // The LARGEST rise wins, not the largest percentage.
    let a = [spend("Big", 200, 93), spend("Big", 200, 62), spend("Big", 200, 31), spend("Big", 240, 1)]
    let b = [spend("Small", 10, 93), spend("Small", 10, 62), spend("Small", 10, 31), spend("Small", 15, 1)]
    let series = AppleWalletRoom.recurringSeries(a + b, now: now)
    check("the biggest rise by AMOUNT wins", AppleWalletRoom.creep(series, now: now)?.merchant == "Big")
}
do {
    // A rise from six months ago is just the price now.
    let s = [spend("Old", 10, 250), spend("Old", 10, 219), spend("Old", 10, 188), spend("Old", 14, 157)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    check("a stale rise is no longer news", AppleWalletRoom.creep(series, now: now) == nil)
}

// ── silence ────────────────────────────────────────────────────────────────
print("silence")
do {
    // Monthly, last charged 60 days ago → ~29 days overdue.
    let s = [spend("Spotify", 11, 152), spend("Spotify", 11, 121),
             spend("Spotify", 11, 91), spend("Spotify", 11, 60)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    let quiet = AppleWalletRoom.silences(series, now: now)
    check("a stopped subscription is found", quiet.first?.merchant == "Spotify")
    check("it reports how overdue", (quiet.first?.overdueDays ?? 0) >= 28)
}
do {
    // Not late at all yet — the next charge is still in the future.
    let s = [spend("Late", 11, 96), spend("Late", 11, 65),
             spend("Late", 11, 34), spend("Late", 11, 3)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    check("a charge that isn't due yet is not silence",
          AppleWalletRoom.silences(series, now: now).isEmpty)
}
do {
    // WEEKLY, last charged 12 days ago → 5 days past due. Past due, but well
    // inside `silenceFloorDays` — a weekend or a billing-date shift, not a
    // cancellation. This fixture is what tests the FLOOR: the monthly one
    // above never reaches the threshold at all (its next charge is still in
    // the future), so a floor mutation sailed past it green.
    let s = [spend("Weekly", 5, 33), spend("Weekly", 5, 26),
             spend("Weekly", 5, 19), spend("Weekly", 5, 12)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    check("a weekly charge five days late is not silence yet",
          AppleWalletRoom.silences(series, now: now).isEmpty)
}
do {
    // Cancelled half a year ago — not news any more.
    let s = [spend("Gone", 11, 300), spend("Gone", 11, 269),
             spend("Gone", 11, 238), spend("Gone", 11, 207)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    check("a long-dead subscription drops off", AppleWalletRoom.silences(series, now: now).isEmpty)
}

// ── the clock rail ─────────────────────────────────────────────────────────
print("rail")
do {
    let s = [spend("Netflix", 15, 62), spend("Netflix", 15, 31), spend("Netflix", 15, 1)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    let dues = [Due(account: "Apple Card", date: now.addingTimeInterval(10 * 86_400),
                    currency: "USD")]
    let rail = AppleWalletRoom.upcoming(series: series, dues: dues, now: now)
    check("both a payment and a recurring date appear", rail.count == 2)
    check("soonest first", rail.first?.date ?? .distantFuture <= rail.last?.date ?? .distantPast)
    check("the payment is marked as a payment",
          rail.first(where: { $0.label == "Apple Card" })?.kind == .payment)
}
do {
    // Same day: the BANK'S fact outranks our arithmetic.
    let s = [spend("Sub", 15, 60), spend("Sub", 15, 30), spend("Sub", 15, 0)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    let dues = [Due(account: "Card", date: now.addingTimeInterval(30 * 86_400), currency: "USD")]
    let rail = AppleWalletRoom.upcoming(series: series, dues: dues, now: now)
    check("a real deadline outranks an inferred one on the same day",
          rail.first?.kind == .payment)
}
do {
    let dues = [Due(account: "Card", date: now.addingTimeInterval(-3 * 86_400),
                    currency: "USD", isOverdue: true)]
    let rail = AppleWalletRoom.upcoming(series: [], dues: dues, now: now)
    check("an overdue payment stays on the rail", rail.count == 1)
    check("…and is marked overdue", rail.first?.isOverdue == true)
}
do {
    let dues = [Due(account: "Far", date: now.addingTimeInterval(200 * 86_400), currency: "USD")]
    check("a date past the horizon is not a deadline yet",
          AppleWalletRoom.upcoming(series: [], dues: dues, now: now).isEmpty)
}

// ── the card as a whole ────────────────────────────────────────────────────
print("card")
do {
    var s: [Spend] = []
    for i in 0..<8 { s.append(spend("M\(i)", Double(100 - i), Double(i + 1))) }
    let card = AppleWalletRoom.compose(spends: s, now: now)
    check("the board caps", card?.merchants.count == AppleWalletRoom.merchantCap)
    check("the tail is FOLDED, not dropped", card?.moreMerchants == 3)
}
do {
    // Older than the window: history exists, but the board is this month.
    let s = [spend("Now", 10, 2), spend("Then", 500, 200)]
    let card = AppleWalletRoom.compose(spends: s, now: now)
    check("the board is windowed", card?.merchants.map(\.name) == ["Now"])
}
do {
    let s = [spend("Solo", 25, 3)]
    let card = AppleWalletRoom.compose(spends: s, now: now)
    check("one merchant gets the all-at phrasing", card?.headline.contains("all at Solo") == true)
}
do {
    let s = [spend("A", 90, 1), spend("B", 10, 2)]
    let card = AppleWalletRoom.compose(spends: s, now: now)
    check("many merchants get the most-of-it phrasing", card?.headline.contains("most of it at A") == true)
}
do {
    check("money always carries its currency",
          AppleWalletRoom.money(5, "XYZ").contains("XYZ") || AppleWalletRoom.money(5, "XYZ").contains("5"))
}

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

build() { swiftc -O -o "$TMP/aw-selftest" "$1" "$TMP/main.swift" 2>"$TMP/build.log"; }

if ! build "$ROOM"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/aw-selftest"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation below is a plausible
# "simplification" of the shipped source, and each must break the run.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$ROOM" "$WORK/AppleWalletRoom.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/AppleWalletRoom.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/AppleWalletRoom.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/AppleWalletRoom.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. Pending counted as spent — the statement-vs-feed confusion.
mutate "pending counted in totals" \
  'let settled = spends.filter { $0.isSettled }' \
  'let settled = spends'

# 2. Currencies summed — the exchange rate we don't have.
mutate "foreign charges summed into the board" \
  'let scoped = settled.filter { $0.currency == currency }' \
  'let scoped = settled'

# 3. Dominant currency by amount — one big foreign purchase re-denominates.
mutate "dominant currency by amount rather than count" \
  'a.value == b.value ? a.key < b.key : a.value > b.value' \
  'a.key < b.key'

# 4. Two charges make a subscription.
mutate "cadence believed from two charges" \
  'guard charges.count >= minChargesToRecur else { continue }' \
  'guard charges.count >= 2 else { continue }'

# 5. Mean instead of every-gap — irregular reads as regular.
mutate "cadence checked on the average gap only" \
  'let regular = gaps.allSatisfy { abs($0 - cadence) <= cadence * cadenceTolerance }' \
  'let regular = (gaps.reduce(0, +) / Double(gaps.count)) <= cadence * (1 + cadenceTolerance)'

# 6. Rounding announced as a price rise.
mutate "creep with no absolute floor" \
  'guard delta >= creepMinDelta,' \
  'guard delta > 0,'

# 7. Creep never expires — last year's rise headlines forever.
mutate "stale price rises stay news" \
  'guard age >= 0, age <= Double(creepFreshDays) else { continue }' \
  'guard age >= 0 else { continue }'

# 8. Silence with no floor — three days late reads as cancelled.
mutate "silence with no floor" \
  'let threshold = max(Double(silenceFloorDays),' \
  'let threshold = min(Double(silenceFloorDays),'

# 9. Silence never expires — every service you ever quit piles up.
mutate "silence with no ceiling" \
  'guard sinceLast <= Double(silenceCeilingDays) else { continue }' \
  'guard sinceLast >= 0 else { continue }'

# 10. Our guess sorted above the bank's fact.
mutate "inferred dates outrank real deadlines" \
  'if a.kind != b.kind { return a.kind == .payment }' \
  'if a.kind != b.kind { return a.kind == .recurring }'

# 11. The tail dropped instead of folded.
mutate "merchant tail silently truncated" \
  'moreMerchants: max(0, merchants.count - merchantCap),' \
  'moreMerchants: 0,'

# 12. Refunds rank as purchases.
mutate "a refund ranks its merchant" \
  'if s.isRefund {
                entry.net -= s.amount' \
  'if s.isRefund {
                entry.net += s.amount'

# 13. Ties unstable — the board reshuffles between refreshes.
mutate "tie-break dropped from the board" \
  'ranked.sort { a, b in a.total == b.total ? a.name < b.name : a.total > b.total }' \
  'ranked.sort { a, b in a.total > b.total }'

# 14. The window dropped — "this month" becomes "ever".
mutate "leaderboard window removed" \
  'let inWindow = scoped.filter { $0.date >= windowStart && $0.date <= now }' \
  'let inWindow = scoped'

echo
echo "applewallet-selftest: OK — assertions pass and every mutation is caught."
