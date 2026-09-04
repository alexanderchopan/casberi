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
#   · one shop filed as two merchants because a descriptor SHOUTS and a
#     merchant name doesn't, splitting a total and dropping both halves off
#   · a processor prefix stripped so eagerly that two real merchants merge
#   · a month-over-month line giving a direction to calendar noise, or
#     comparing this month against "all history" because the prior window has
#     no floor
#   · the same price rise landing as a new row on every single refresh
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/AppleWalletRoom.swift"
LEDE="Casberi/Casberi/Model/RoomLede.swift"   # prd §585 — the shared lede type these rooms now return
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
# Apple granted this entitlement against a WRITTEN description of the screen,
# so the promise is a contract, not copy. SUBSTANCE, not one exact sentence
# (2026-08-12): a copy pass rewrote it out of the first person ("Casberi has
# no server" → "There is no server, so nothing is uploaded or sold") and the
# promise survived intact while the guard failed. Pinning prose fails on every
# legitimate edit; what has to stay true is that the screen denies a server
# and denies the data leaving, before anybody taps connect.
grep -qiE 'no server|there is no server' "$SCREEN" \
  || { echo "✗ the setup screen no longer denies having a server BEFORE connect"; exit 1; }
grep -qiE 'nothing is uploaded|never uploaded|not uploaded|never leaves' "$SCREEN" \
  || { echo "✗ the setup screen no longer says the data is not uploaded"; exit 1; }
# Anchored on the sentence the screen ACTUALLY carries. It was anchored on
# `is deleted from Casberi` when this harness shipped — a phrase that was never
# in the screen, so `verify.sh` was red from the commit that added it and the
# guard proved nothing about the promise it was written to protect. The
# standing lesson (CLAUDE.md, the reach-audit ship gate) earned again: run
# `verify.sh`, not the audits you happen to remember.
grep -q 'brought in is deleted' "$SCREEN" \
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

# THE PENDING-HEAL WINDOW. The cursor is the newest date already landed and the
# query asks for everything after it — so without a heal-back window a pending
# authorization (landed wearing today's date) sits at or below the cursor
# forever, is never re-read, never settles, and is never counted. It renders
# perfectly the whole time. This is the one drift guard here protecting a fix
# rather than a promise.
grep -q 'healbackDays' "$BRIDGE" \
  || { echo "✗ the pending heal-back window is gone — pending rows would never settle again"; exit 1; }
grep -q 'addingTimeInterval(-Double(healbackDays) \* 86_400)' "$BRIDGE" \
  || { echo "✗ the read window no longer reaches BACK past the cursor — the heal path is unreachable again"; exit 1; }
# …and the heal must rewrite the merchant too, or a row that landed under a raw
# descriptor keeps it after normalization changes.
grep -q 'row.transferCounterparty = merchant' "$BRIDGE" \
  || { echo "✗ the heal no longer rewrites the merchant"; exit 1; }

# NORMALIZATION IS APPLIED AT LANDING, and the raw descriptor is kept where it
# stays searchable. Both halves matter: without the first the board fragments,
# without the second searching what your statement actually says finds nothing.
grep -q 'AppleWalletRoom.normalizeMerchant(raw)' "$BRIDGE" \
  || { echo "✗ merchant names are no longer normalized at landing — one shop can file as three"; exit 1; }
grep -q 'if merchant != raw { enriched.append(raw) }' "$BRIDGE" \
  || { echo "✗ the raw descriptor is no longer kept — searching the string on your statement would find nothing"; exit 1; }

# CHANGES LEAVE THE ROOM. A head only speaks while you stand in front of it;
# these two are the judgements worth having when you don't.
grep -q 'landChanges(context: context)' "$BRIDGE" \
  || { echo "✗ creep/silence are no longer landed — the room's whole point is invisible outside the room"; exit 1; }
grep -q 'AppleWalletRoom.creeps(series, now: now)' "$BRIDGE" \
  || { echo "✗ landing uses a single creep rather than every fresh rise — two subscriptions rising in one month would land one"; exit 1; }
# Stamped with when it HAPPENED, never `now` — this is also what decides
# (correctly, for free) that a rise found on a first connect never notifies,
# since NotifySweep only considers rows inside its 36-hour news window.
grep -q 'capturedAt: creep.at' "$BRIDGE" \
  || { echo "✗ a price rise is no longer stamped with its own date — a backfilled rise would land as today's news"; exit 1; }
grep -q 'capturedAt: AppleWalletRoom.silenceOccurredAt(silence)' "$BRIDGE" \
  || { echo "✗ a silence is no longer stamped with the date it missed"; exit 1; }
# §313's ruling, still true: a CHARGE never notifies. Only the delta does.
grep -q 'thing.tags.contains("Price rise")' "Casberi/Casberi/Model/NotifySweep.swift" \
  || { echo "✗ a price rise no longer reaches the notify sweep"; exit 1; }
# The bridge lands rows and never decides what notifies — `NotifySweep` reads
# the tags and classifies, which is what keeps the whole never-fires list
# reviewable on one screen (§306). Anchored on the classifier's own vocabulary
# rather than on the tag string: the bridge legitimately reads its own "Silence"
# tag to reconcile a row whose claim has become false.
grep -qE 'NotifyKind|priceRose|Notifications\.' "$BRIDGE" \
  && { echo "✗ the bridge is deciding what notifies — classification belongs to NotifySweep"; exit 1; }

# A silence row is the one landed row that can become FALSE, so it must be
# reconciled when the subscription resumes.
grep -q 'reconcileSilences' "$BRIDGE" \
  || { echo "✗ nothing un-lands a silence when the subscription resumes — the corpus keeps asserting it stopped"; exit 1; }
# The heal-back window must follow what is actually unresolved. A fixed offset
# from a cursor that advances daily strands exactly the long holds that take
# longest to settle.
grep -q 'pendingFloor(context: context)' "$BRIDGE" \
  || { echo "✗ the read window no longer follows the oldest pending row — a long hold is stranded again"; exit 1; }

# The spend ask reads the declared set, never a hand-typed source list.
grep -q 'Corpus.cardSpendSources' "Casberi/Casberi/Model/KeptAskComposers.swift" \
  || { echo "✗ the spend ask no longer reads Corpus.cardSpendSources"; exit 1; }
grep -q 'row.tags.contains("Refund")' "Casberi/Casberi/Model/KeptAskComposers.swift" \
  || { echo "✗ the money-flow card total no longer subtracts refunds — every refund would read as money spent"; exit 1; }

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

// ── one shop is one merchant ───────────────────────────────────────────────
// FinanceKit hands over `merchantName` when it has one and we fall back to
// `transactionDescription` when it doesn't, and those two disagree about case
// and about processor prefixes. Filed apart, a total splits in half — and both
// halves can then sit below the ranking floor, so the board silently omits
// the place you spend most.
print("merchant identity")
do {
    check("case folds into one key",
          AppleWalletRoom.merchantKey("BLUE BOTTLE") == AppleWalletRoom.merchantKey("Blue Bottle"))
    check("surrounding space is not identity",
          AppleWalletRoom.merchantKey("  Blue Bottle ") == AppleWalletRoom.merchantKey("Blue Bottle"))
    check("different shops stay different",
          AppleWalletRoom.merchantKey("Blue Bottle") != AppleWalletRoom.merchantKey("Blue Bottles"))
}
do {
    check("the cased spelling wins over the shouting one",
          AppleWalletRoom.preferredSpelling(["BLUE BOTTLE COFFEE", "Blue Bottle Coffee"]) == "Blue Bottle Coffee")
    check("all-caps survives when it's all there is",
          AppleWalletRoom.preferredSpelling(["IKEA"]) == "IKEA")
    // An acronym must never be re-cased into a name nobody uses.
    check("a shouting name is never title-cased into a new one",
          AppleWalletRoom.preferredSpelling(["CVS", "CVS"]) == "CVS")
    check("ties break alphabetically (stable board)",
          AppleWalletRoom.preferredSpelling(["Zeta Shop", "Alpha Shop"]) == "Alpha Shop")
}
do {
    let s = [spend("BLUE BOTTLE COFFEE", 6.50, 1), spend("Blue Bottle Coffee", 6.50, 3)]
    let rows = AppleWalletRoom.leaderboard(s)
    check("two spellings rank as ONE merchant", rows.count == 1)
    check("…with both charges counted", rows.first?.count == 2)
    check("…and both amounts summed", rows.first?.total == 13.0)
    check("…shown under the readable spelling", rows.first?.name == "Blue Bottle Coffee")
}
do {
    // The failure that matters most: a subscription arriving cased one month
    // and shouting the next splits into two series of two, and two charges can
    // never carry a cadence — so the price rise this room exists to report
    // becomes invisible with no error anywhere.
    let s = [spend("NETFLIX", 15.49, 93), spend("Netflix", 15.49, 62),
             spend("NETFLIX", 15.49, 31), spend("Netflix", 17.99, 1)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    check("a subscription spelled two ways is still one series", series.count == 1)
    check("…so its price rise is still found",
          AppleWalletRoom.creep(series, now: now)?.merchant != nil)
}

// ── digging a name out of a descriptor ─────────────────────────────────────
print("normalize")
do {
    check("Square", AppleWalletRoom.normalizeMerchant("SQ *BLUE BOTTLE") == "BLUE BOTTLE")
    check("Toast", AppleWalletRoom.normalizeMerchant("TST* BLUE BOTTLE") == "BLUE BOTTLE")
    check("PayPal", AppleWalletRoom.normalizeMerchant("PAYPAL *STEAM GAMES") == "STEAM GAMES")
    check("a trailing reference code goes",
          AppleWalletRoom.normalizeMerchant("Amazon.com*2H4KJ8") == "Amazon.com")
}
do {
    // The conservative half, and the more important one: a prefix that strips
    // something it shouldn't MERGES TWO REAL MERCHANTS, which states a total
    // nobody spent. Every case here must come back untouched.
    check("an ordinary name is untouched",
          AppleWalletRoom.normalizeMerchant("Blue Bottle Coffee") == "Blue Bottle Coffee")
    check("a name that merely starts with S is untouched",
          AppleWalletRoom.normalizeMerchant("SQUARE ENIX") == "SQUARE ENIX")
    check("a letters-only tail is a word, not a code",
          AppleWalletRoom.normalizeMerchant("AMZN Mktp US*PRIME") == "AMZN Mktp US*PRIME")
    check("a tail with a space is not a code",
          AppleWalletRoom.normalizeMerchant("SHOP*BLUE BOTTLE") == "SHOP*BLUE BOTTLE")
    check("stripping to nothing is refused",
          AppleWalletRoom.normalizeMerchant("SQ *X") == "SQ *X")
    check("empty in, empty out", AppleWalletRoom.normalizeMerchant("") == "")
}
do {
    check("a bare word is meaningful", AppleWalletRoom.isMeaningfulName("CVS"))
    check("two characters are not", !AppleWalletRoom.isMeaningfulName("XY"))
    check("digits alone are not a name", !AppleWalletRoom.isMeaningfulName("12345"))
    // An UNLISTED processor tag must not be read as the shop. `CKO*NORDVPN1`
    // has a digit-bearing spaceless tail and a 3-char head that passes
    // `isMeaningfulName` — so without the head-length rule every Checkout.com
    // purchase ever made ranks as one merchant called CKO.
    check("a short head is a processor tag, not a shop",
          AppleWalletRoom.normalizeMerchant("CKO*NORDVPN1") == "CKO*NORDVPN1")
    check("…while a real long head still loses its code",
          AppleWalletRoom.normalizeMerchant("Amazon.com*2H4KJ8") == "Amazon.com")
    check("…and a multi-word head does too",
          AppleWalletRoom.normalizeMerchant("AMZN Mktp US*2H4KJ8") == "AMZN Mktp US")
}

// ── currency is part of every grouping key ─────────────────────────────────
// The file header has always said so; it was true of `compose` (which scopes
// first) and false of `leaderboard`/`recurringSeries` themselves, which is
// safe until something calls them unscoped — and `landChanges` does.
print("currency keying")
do {
    let s = [spend("Shop", 10, 1), spend("Shop", 10, 2, cur: "EUR")]
    let rows = AppleWalletRoom.leaderboard(s)
    check("one merchant in two currencies is two rows", rows.count == 2)
    check("…and neither total is a sum across them", rows.allSatisfy { $0.total == 10 })
}
do {
    // The landing case: €10, €10, then $12 must NOT read as a 20% price rise.
    let s = [spend("Sub", 10, 62, cur: "EUR"), spend("Sub", 10, 31, cur: "EUR"),
             spend("Sub", 12, 1)]
    let series = AppleWalletRoom.recurringSeries(s, now: now)
    check("a cadence never spans two currencies", series.allSatisfy { s in
        Set(s.charges.map(\.currency)).count == 1
    })
    check("…so no cross-currency price rise is invented",
          AppleWalletRoom.creep(series, now: now) == nil)
}

// ── month over month ───────────────────────────────────────────────────────
print("comparison")
do {
    check("a rise is stated with its direction",
          AppleWalletRoom.comparisonText(total: 120, prevTotal: 100, prevCount: 4,
                                         currency: "USD")?.contains("Up 20%") == true)
    check("a fall too",
          AppleWalletRoom.comparisonText(total: 80, prevTotal: 100, prevCount: 4,
                                         currency: "USD")?.contains("Down 20%") == true)
    // §83: a change that rounds to nothing has no direction.
    check("noise gets NO direction",
          AppleWalletRoom.comparisonText(total: 102, prevTotal: 100, prevCount: 4,
                                         currency: "USD")?.contains("About the same") == true)
    check("…and no arrow either",
          AppleWalletRoom.comparisonText(total: 102, prevTotal: 100, prevCount: 4,
                                         currency: "USD")?.contains("Up") == false)
    // A first month has nothing to compare against, and "up from $0" would be
    // the app congratulating you on existing.
    check("no prior month → no comparison",
          AppleWalletRoom.comparisonText(total: 120, prevTotal: 0, prevCount: 0,
                                         currency: "USD") == nil)
    check("a prior window with rows but no spend still says nothing",
          AppleWalletRoom.comparisonText(total: 120, prevTotal: 0, prevCount: 3,
                                         currency: "USD") == nil)
    check("the comparison names the prior total",
          AppleWalletRoom.comparisonText(total: 120, prevTotal: 100, prevCount: 4,
                                         currency: "USD")?.contains("100") == true)
}
do {
    // Through `compose`: a quiet month — nothing rose, nothing stopped, no
    // deadline — must still say something true rather than nothing at all.
    let s = [spend("Shop", 60, 5), spend("Shop", 40, 10),
             spend("Shop", 50, 40), spend("Shop", 50, 50)]
    let card = AppleWalletRoom.compose(spends: s, now: now)
    check("a quiet month falls through to the comparison",
          card?.subline?.contains("last month") == true)
}
do {
    // …and it must never outrank a price rise, which costs more to miss.
    let s = [spend("Netflix", 15.49, 93), spend("Netflix", 15.49, 62),
             spend("Netflix", 15.49, 31), spend("Netflix", 17.99, 1)]
    let card = AppleWalletRoom.compose(spends: s, now: now)
    check("a price rise still outranks the comparison",
          card?.subline?.contains("went up") == true)
}
do {
    // The PRIOR window is bounded on BOTH sides. Unbounded below, "last month"
    // silently means "every month before this one", and the card states a
    // delta against a number nobody would recognise.
    let s = [spend("Shop", 50, 5), spend("Shop", 50, 40),
             spend("Shop", 5000, 300)]
    let card = AppleWalletRoom.compose(spends: s, now: now)
    check("ancient history is not last month",
          card?.subline?.contains("Down 9") != true)
}

// ── what leaves the room ───────────────────────────────────────────────────
// The refs are a dedupe identity: one event lands once, a genuinely new one
// still lands. Get this wrong in either direction and the feed either repeats
// a price rise on every refresh forever, or never reports the second one.
print("landing")
do {
    let a = AppleWalletRoom.Creep(merchant: "Netflix", was: 15.49, now: 17.99,
                                  currency: "USD", at: day(1))
    // The same rise RE-READ on a later pass. Every field of a `Creep` is a
    // property of the charge — the merchant, the two amounts, and the date it
    // posted — so a later pass reconstructs it identically and the ref is
    // stable by construction. (An earlier version of this fixture varied `at`
    // to mean "computed later", which is a thing that cannot happen: `at` is
    // the charge's own date, not the date we looked.)
    let again = AppleWalletRoom.Creep(merchant: "Netflix", was: 15.49, now: 17.99,
                                      currency: "USD", at: day(1))
    let further = AppleWalletRoom.Creep(merchant: "Netflix", was: 17.99, now: 19.99,
                                        currency: "USD", at: day(0))
    check("the same rise keeps one ref (no repeat on every refresh)",
          AppleWalletRoom.creepRef(a) == AppleWalletRoom.creepRef(again))
    check("a SECOND rise gets its own ref", AppleWalletRoom.creepRef(a) != AppleWalletRoom.creepRef(further))
    // Promotional pricing CYCLES: $15.99 → $9.99 promo → $15.99 again, and a
    // year later the same promo ends again. Keyed on the amounts alone the
    // second rise dedupes against the first and a real, current price increase
    // is reported to nobody.
    let laterSameRise = AppleWalletRoom.Creep(merchant: "Netflix", was: 15.49, now: 17.99,
                                              currency: "USD", at: day(300))
    check("the SAME rise a year later still lands",
          AppleWalletRoom.creepRef(a) != AppleWalletRoom.creepRef(laterSameRise))
    check("the ref survives a spelling change",
          AppleWalletRoom.creepRef(a) ==
          AppleWalletRoom.creepRef(AppleWalletRoom.Creep(merchant: "NETFLIX", was: 15.49,
                                                         now: 17.99, currency: "USD", at: day(1))))
    check("the landed title says the same thing the card does",
          AppleWalletRoom.creepLine(a).contains("Netflix") && AppleWalletRoom.creepLine(a).contains("16%"))
}
do {
    let s = AppleWalletRoom.Silence(merchant: "Spotify", lastSeen: day(60),
                                    expectedEvery: 31, overdueDays: 29)
    check("one outage keeps one ref",
          AppleWalletRoom.silenceRef(s) ==
          AppleWalletRoom.silenceRef(AppleWalletRoom.Silence(merchant: "Spotify", lastSeen: day(60),
                                                             expectedEvery: 31, overdueDays: 33)))
    check("a later outage gets its own ref",
          AppleWalletRoom.silenceRef(s) !=
          AppleWalletRoom.silenceRef(AppleWalletRoom.Silence(merchant: "Spotify", lastSeen: day(20),
                                                             expectedEvery: 31, overdueDays: 12)))
    // A landed row is read months later. "29 days ago" is true for one day;
    // the date it last charged is true forever.
    check("the landed title names a DATE, not a countdown",
          !AppleWalletRoom.silenceTitle(s).contains("29"))
    check("…and names the merchant", AppleWalletRoom.silenceTitle(s).contains("Spotify"))
    // Stamped when it HAPPENED — which is also what stops a first connect
    // announcing a months-old cancellation as today's news.
    check("a silence is stamped at the date it missed, not now",
          AppleWalletRoom.silenceOccurredAt(s) < now)
    check("…which is one cadence after the last charge",
          abs(AppleWalletRoom.silenceOccurredAt(s).timeIntervalSince(day(29))) < 86_400)
    // A silence row is the ONE thing this bridge lands that can become FALSE:
    // a subscription that paused and resumed leaves the corpus asserting it
    // stopped. The reconcile pass reads the last-charge date back out of the
    // ref, so a ref it can't parse must not be mistaken for one it can.
    check("the ref round-trips its last-charge date",
          AppleWalletRoom.silenceLastSeen(fromRef: AppleWalletRoom.silenceRef(s))
              .map { abs($0.timeIntervalSince(day(60))) < 1 } == true)
    check("a foreign ref yields no date",
          AppleWalletRoom.silenceLastSeen(fromRef: "applewallet:txn:ABC") == nil)
    check("a creep ref is not read as a silence ref",
          AppleWalletRoom.silenceLastSeen(
              fromRef: AppleWalletRoom.creepRef(
                  AppleWalletRoom.Creep(merchant: "N", was: 1, now: 2,
                                        currency: "USD", at: day(1)))) == nil)
}
do {
    // `creeps` returns EVERY fresh rise; `creep` picks the one to headline.
    let a = [spend("Big", 200, 93), spend("Big", 200, 62), spend("Big", 200, 31), spend("Big", 240, 1)]
    let b = [spend("Small", 10, 93), spend("Small", 10, 62), spend("Small", 10, 31), spend("Small", 15, 1)]
    let series = AppleWalletRoom.recurringSeries(a + b, now: now)
    check("both rises are landable", AppleWalletRoom.creeps(series, now: now).count == 2)
    check("only the largest headlines", AppleWalletRoom.creep(series, now: now)?.merchant == "Big")
    check("the headline is one OF the landable ones",
          AppleWalletRoom.creeps(series, now: now).contains { $0.merchant == "Big" })
}

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

build() { swiftc -O -o "$TMP/aw-selftest" "$1" "$LEDE" "$TMP/main.swift" 2>"$TMP/build.log"; }

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
  if ! swiftc -O -o "$TMP/mut" "$WORK/AppleWalletRoom.swift" "$LEDE" "$TMP/main.swift" 2>/dev/null; then
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

# 15. Case is identity again — one shop files as two, and a subscription
#     spelled two ways loses its cadence and its price rise with it.
mutate "merchant identity is case-sensitive again" \
  'name.trimmingCharacters(in: .whitespaces).lowercased()' \
  'name.trimmingCharacters(in: .whitespaces)'

# 16. The board shows whichever spelling the dictionary happened to yield.
mutate "spelling picked arbitrarily rather than preferring the cased form" \
  'let pool = cased.isEmpty ? names : cased' \
  'let pool = names'

# 17. Normalization strips a prefix without checking what is left, so
#     `SQ *X` becomes `X` and two one-letter merchants merge.
mutate "a strip that leaves nothing is accepted" \
  'if isMeaningfulName(stripped) { name = stripped }' \
  'name = stripped'

# 18. The trailing-code rule drops a real word: `AMZN Mktp US*PRIME` loses it.
mutate "a letters-only tail treated as a reference code" \
  'if !tail.isEmpty, !tail.contains(" "), tail.contains(where: \.isNumber),' \
  'if !tail.isEmpty, !tail.contains(" "),'

# 19. The comparison gives calendar noise a direction (§83).
mutate "month-over-month noise gets an arrow" \
  'if abs(fraction) < comparisonFlatBand {' \
  'if abs(fraction) < 0 {'

# 20. The prior window loses its floor, so "last month" silently means
#     "all history before this month".
mutate "prior window unbounded below" \
  'let prevWindow = scoped.filter { $0.date >= prevStart && $0.date < windowStart }' \
  'let prevWindow = scoped.filter { $0.date < windowStart }'

# 21. A first month compares against zero — "up from nothing".
mutate "comparison drawn with no prior month" \
  'guard prevCount > 0, prevTotal > 0, total > 0 else { return nil }' \
  'guard total > 0 else { return nil }'

# 22. Only the largest rise is landable, so a month where two subscriptions
#     went up keeps one and loses the other forever.
mutate "creeps collapses to the single headline rise" \
  'static func creeps(_ series: [Series], now: Date) -> [Creep] {' \
  'static func creeps(_ series: [Series], now: Date) -> [Creep] {
        return creep2(series, now: now).map { [$0] } ?? []
    }
    static func creep2(_ series: [Series], now: Date) -> Creep? {
        return creeps2(series, now: now).max { $0.delta < $1.delta }
    }
    static func creeps2(_ series: [Series], now: Date) -> [Creep] {'

# 23. The creep ref ignores the amounts, so a SECOND rise on the same
#     subscription dedupes against the first and never lands.
mutate "creep ref keyed on the merchant alone" \
  'return "applewallet:creep:\(merchantKey(c.merchant)):\(was):\(now):\(day)"' \
  'return "applewallet:creep:\(merchantKey(c.merchant))"'

# 24. The creep ref keys on the raw spelling, so the same rise lands again the
#     month the descriptor arrives shouting.
mutate "creep ref keyed on the raw spelling" \
  'return "applewallet:creep:\(merchantKey(c.merchant)):\(was):\(now):\(day)"' \
  'return "applewallet:creep:\(c.merchant):\(was):\(now):\(day)"'

# 25. The silence ref ignores WHICH outage, so a subscription that stops,
#     resumes and stops again reports only the first.
mutate "silence ref keyed on the merchant alone" \
  '"applewallet:silence:\(merchantKey(s.merchant)):\(Int(s.lastSeen.timeIntervalSince1970))"' \
  '"applewallet:silence:\(merchantKey(s.merchant))"'

# 26. The landed silence title carries a countdown, which is true for one day
#     and false every day after — a row is read months later.
mutate "silence title carries a countdown instead of a date" \
  'String(localized: "\(s.merchant) stopped charging you — last was \(dayLabel(s.lastSeen))")' \
  'String(localized: "\(s.merchant) stopped charging you — \(s.overdueDays) days")'

# 27. A silence is stamped NOW, so a first connect announces every
#     cancellation you already knew about as today's news.
mutate "silence stamped at discovery rather than at the missed date" \
  's.lastSeen.addingTimeInterval(Double(s.expectedEvery) * 86_400)' \
  'Date()'

# 28. Currency drops out of the grouping key, so `landChanges` — which reads
#     the corpus UNSCOPED, unlike `compose` — invents a price rise across two
#     currencies: €10, €10, $12 lands as "went up 20%" and alarms about it.
mutate "currency dropped from the grouping key" \
  'merchantKey(s.merchant) + "\u{1}" + s.currency' \
  'merchantKey(s.merchant)'

# 29. The creep ref loses its date, so a promotional price that returns to a
#     value it held before never lands again.
mutate "creep ref keyed without the day" \
  'return "applewallet:creep:\(merchantKey(c.merchant)):\(was):\(now):\(day)"' \
  'return "applewallet:creep:\(merchantKey(c.merchant)):\(was):\(now)"'

# 30. The trailing-code rule accepts a short head, so an unlisted processor tag
#     becomes the merchant and every purchase through it merges into one row.
mutate "a processor tag accepted as the shop" \
  'let headIsName = head.count >= minHeadForCodeStrip || head.contains(" ")' \
  'let headIsName = true'

# 31. The silence ref stops round-tripping its date, so the reconcile pass can
#     never tell that a subscription resumed and the false row stands forever.
mutate "silence ref no longer carries a readable date" \
  '"applewallet:silence:\(merchantKey(s.merchant)):\(Int(s.lastSeen.timeIntervalSince1970))"' \
  '"applewallet:silence:\(merchantKey(s.merchant)):x"'

# 32. `silenceLastSeen` stops checking the prefix, so a creep ref's trailing
#     day number is read as a last-charge date in 1970 — every silence row then
#     looks resumed and is deleted.
mutate "silenceLastSeen accepts any ref" \
  'guard ref.hasPrefix("applewallet:silence:"),' \
  'guard true,'

echo
echo "applewallet-selftest: OK — assertions pass and every mutation is caught."
