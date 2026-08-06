import Foundation

/// THE APPLE WALLET ROOM'S JUDGEMENT (2026-08-06, prd §313) — who you actually
/// pay, and what changed since last time.
///
/// FinanceKit is the only source in this app that sees a MERCHANT NAME. The
/// chain never carries one (`GnosisPayBridge`'s standing ceiling: "rows say
/// what was spent, never where"), a Privacy.com row carries a card descriptor,
/// and a wallet transfer carries an address. So this room leads with WHO, and
/// every card here is built on the one field nothing else can supply.
///
/// ## The room's whole thesis: your bank already told you what happened
///
/// A card charge fails the "did you already know?" test that every other seat
/// in this app is measured against — you made it, minutes ago, and your bank
/// pushed you a notification about it. Landing charges is still right (they
/// make the corpus searchable, and they sit beside the onchain cards where
/// nothing else can put them), but a room that LEADS with them is a worse
/// statement of your own bank's app.
///
/// So the head states what changed:
///   • `creep` — a recurring charge that went UP. Nothing else in a person's
///     day says this. The bank shows a charge; it never shows the delta.
///   • `silence` — a recurring charge that STOPPED. The PostHog silence idea
///     (prd §223) pointed at money: the most useful thing a subscription can
///     tell you is that it quietly isn't happening any more.
///   • `upcoming` — the next expected date per recurring merchant, plus the
///     one real deadline FinanceKit hands over, `nextPaymentDueDate`.
///   • `merchants` — the leaderboard, which is the room's identity even when
///     nothing changed. `FeedInsight.leaderboard` can't build it, because that
///     registry ranks by ROW COUNT and money ranks by AMOUNT.
///
/// ## Currencies are NEVER summed
///
/// `StripeRoom`'s standing rule, inherited whole. A foreign-currency charge
/// carries its own `currencyCode`, and a single total across codes is an
/// exchange rate this app does not have and a claim it cannot make. Every
/// total here is per-currency, and the card names the currency it's showing.
/// `Spend.currency` is therefore part of every grouping key.
///
/// ## Pending is never counted
///
/// An authorization is not a purchase — it can settle at a different amount or
/// vanish. `Spend.isSettled` gates every arithmetic path. A pending row still
/// LANDS in the feed (it happened, and you want to see it), but the moment it
/// enters a total the room starts stating numbers that change under it, which
/// is the §83 fake-status ban wearing a dollar sign.
///
/// ## Refunds subtract, they don't rank
///
/// A refund is a credit against a merchant you paid. It reduces that
/// merchant's total (so "who you actually pay" stays true) but never creates a
/// merchant entry of its own — a store that only ever refunded you is not
/// somewhere you spend. Hence `net` rather than a sum over debits.
///
/// ## Everything here is pure
///
/// Foundation only, no `Thing`, no `UserDefaults`, no FinanceKit. That is what
/// lets `scripts/applewallet-selftest.sh` compile this file WHOLE and prove the
/// numbers, which matters more here than anywhere else in the app: **no
/// simulator has FinanceKit data**, so this room can never be exercised by a
/// sim sweep, and the only place it will ever run is a real device with a real
/// Apple Card. The harness is the only proof these numbers are right — the
/// `StripeRoom`/`PostHogRoom` argument, one degree stronger, because those two
/// could at least be measured by anyone willing to mint a key.
enum AppleWalletRoom {

    // MARK: - Inputs

    /// One settled or pending card movement, stripped to what judgement needs.
    /// `AppleWalletRoomSource` builds these from landed rows so this file never
    /// touches `Thing`.
    struct Spend: Equatable {
        var merchant: String
        var amount: Double
        var currency: String
        var date: Date
        /// `false` for an authorization that hasn't posted. Excluded from every
        /// total, still shown as a row.
        var isSettled: Bool
        /// A credit back from a merchant. Subtracts from their net, never ranks.
        var isRefund: Bool

        init(merchant: String, amount: Double, currency: String, date: Date,
             isSettled: Bool = true, isRefund: Bool = false) {
            self.merchant = merchant
            self.amount = amount
            self.currency = currency
            self.date = date
            self.isSettled = isSettled
            self.isRefund = isRefund
        }
    }

    /// A deadline the source hands over rather than one we infer —
    /// FinanceKit's own `nextPaymentDueDate` on a credit account.
    struct Due: Equatable {
        var account: String
        var date: Date
        var amount: Double?
        var currency: String
        var isOverdue: Bool

        init(account: String, date: Date, amount: Double? = nil,
             currency: String, isOverdue: Bool = false) {
            self.account = account
            self.date = date
            self.amount = amount
            self.currency = currency
            self.isOverdue = isOverdue
        }
    }

    // MARK: - Outputs

    struct MerchantRow: Equatable {
        var name: String
        var count: Int
        var total: Double
        var currency: String
        /// Fraction of the window's settled spend, 0…1 — the bar's width.
        var share: Double
    }

    /// A recurring charge whose amount moved. The room's flagship.
    struct Creep: Equatable {
        var merchant: String
        var was: Double
        var now: Double
        var currency: String
        var at: Date
        var delta: Double { now - was }
        /// Fractional change, e.g. 0.16 for a 16% rise. `was` is never 0 here
        /// (`creep` requires two settled charges above `minAmount`).
        var fraction: Double { was == 0 ? 0 : (now - was) / was }
    }

    /// A recurring charge that stopped arriving.
    struct Silence: Equatable {
        var merchant: String
        var lastSeen: Date
        var expectedEvery: Int      // days
        var overdueDays: Int
    }

    /// Something with a clock on it — an expected recurring charge, or the
    /// card's own payment due date.
    struct Upcoming: Equatable {
        enum Kind: Equatable { case payment, recurring }
        var kind: Kind
        var label: String
        var date: Date
        var amount: Double?
        var currency: String
        var isOverdue: Bool
    }

    struct Card: Equatable {
        var headline: String
        var subline: String?
        var merchants: [MerchantRow]
        /// Merchants beyond `merchantCap`, folded rather than dropped.
        var moreMerchants: Int
        var creep: Creep?
        var silences: [Silence]
        var upcoming: [Upcoming]
        var currency: String
        var note: String?
    }

    // MARK: - Tuning
    //
    // Every constant here is a judgement, and each one is mutation-tested in
    // `scripts/applewallet-selftest.sh` — a threshold nothing depends on is a
    // threshold that can drift silently.

    /// How far back the leaderboard looks. A calendar month is the unit people
    /// already think in for a card, and it's the unit the statement uses.
    static let windowDays = 30
    /// Rows drawn before the tail folds. Five names is a leaderboard; ten is a
    /// list, and the room already has rows underneath it.
    static let merchantCap = 5
    /// A merchant needs this many settled charges in the window to rank. One
    /// charge is a purchase, not a pattern — and without this the card is
    /// dominated by whatever single large thing you bought.
    static let minChargesToRank = 1
    /// Charges below this never rank or trigger creep. A $0.99 rounding
    /// difference is not a price rise, and sub-dollar noise crowds the board.
    static let minAmount = 1.0

    /// How many settled charges make a series RECURRING. Two points is a line
    /// through any two purchases; three is the smallest number that can carry
    /// a cadence.
    static let minChargesToRecur = 3
    /// A cadence is believed when every gap sits within this fraction of the
    /// median gap. Subscriptions land on calendar days, so a 28/31-day month
    /// varies ~10% by itself — the tolerance has to clear that or monthly
    /// billing reads as irregular.
    static let cadenceTolerance = 0.28
    /// Cadences outside this range aren't subscriptions. Below it is a daily
    /// habit (coffee), above it is a memory.
    static let minCadenceDays = 6
    static let maxCadenceDays = 400

    /// A recurring amount must move by MORE than this fraction to be creep.
    /// Card networks round foreign conversions and some merchants vary by
    /// cents; 2% clears that without hiding a real price rise.
    static let creepTolerance = 0.02
    /// …and by at least this much in absolute terms, so a $1.20 subscription
    /// ticking to $1.25 doesn't headline the room.
    static let creepMinDelta = 0.50
    /// How long a creep stays newsworthy. After this it's just the price.
    static let creepFreshDays = 45

    /// A recurring charge is SILENT once it's this many multiples of its own
    /// cadence late. 1.5 means a monthly charge speaks up at ~45 days —
    /// late enough that a weekend or a billing-date shift can't trigger it.
    static let silenceFactor = 1.5
    /// …and never before this many days, so a weekly charge doesn't alarm
    /// after ten days of nothing.
    static let silenceFloorDays = 10
    /// Past this, a stopped subscription is a cancellation you remember, not
    /// news. Without it the room accumulates every service you ever quit.
    static let silenceCeilingDays = 120

    /// How far ahead the clock rail draws.
    static let horizonDays = 45
    /// Rows on the rail before it caps.
    static let upcomingCap = 4

    /// The month-over-month line's no-direction band (§83: a change that
    /// rounds to zero has no direction). A few percent is calendar noise — a
    /// 30-day window slides across billing days — and giving it an arrow
    /// invents a trend.
    static let comparisonFlatBand = 0.05

    // MARK: - Composition

    /// The room's whole head. `nil` when there is nothing true to say — an
    /// empty card is worse than no card, because it reads as a broken one.
    ///
    /// `now` is injected rather than read so the harness can place a fixture
    /// anywhere on the calendar (and because `Date.now` inside a pure function
    /// makes every test time-dependent).
    static func compose(spends: [Spend], dues: [Due] = [], now: Date) -> Card? {
        let settled = spends.filter { $0.isSettled }
        // The DOMINANT currency owns the card. Picked by settled charge COUNT,
        // not by total: one large foreign purchase should not re-denominate a
        // room whose every other row is in the home currency.
        guard let currency = dominantCurrency(settled) else { return nil }
        let scoped = settled.filter { $0.currency == currency }

        let windowStart = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let inWindow = scoped.filter { $0.date >= windowStart && $0.date <= now }
        // The PRIOR window — same length, ending where this one starts — for
        // the month-over-month line. Bounded on BOTH sides: without the lower
        // bound, "last month" silently means "all history before this month",
        // and the comparison states a delta against a number nobody would
        // recognize as last month.
        let prevStart = now.addingTimeInterval(-Double(windowDays * 2) * 86_400)
        let prevWindow = scoped.filter { $0.date >= prevStart && $0.date < windowStart }

        let merchants = leaderboard(inWindow)
        let series = recurringSeries(scoped, now: now)
        let creepRow = creep(series, now: now)
        let silenceRows = silences(series, now: now)
        let rail = upcoming(series: series, dues: dues.filter { $0.currency == currency }, now: now)

        // Nothing to draw at all — no ranked merchant, no clock, no change.
        if merchants.isEmpty && rail.isEmpty && creepRow == nil && silenceRows.isEmpty {
            return nil
        }

        let spentTotal = inWindow.reduce(0.0) { $0 + ($1.isRefund ? -$1.amount : $1.amount) }
        let prevTotal = prevWindow.reduce(0.0) { $0 + ($1.isRefund ? -$1.amount : $1.amount) }
        let prevCount = prevWindow.filter { !$0.isRefund }.count
        let headline = headlineText(merchants: merchants, total: spentTotal,
                                    currency: currency)
        return Card(headline: headline,
                    subline: sublineText(creep: creepRow, silences: silenceRows,
                                         upcoming: rail,
                                         total: spentTotal, prevTotal: prevTotal,
                                         prevCount: prevCount, currency: currency),
                    merchants: Array(merchants.prefix(merchantCap)),
                    moreMerchants: max(0, merchants.count - merchantCap),
                    creep: creepRow,
                    silences: silenceRows,
                    upcoming: rail,
                    currency: currency,
                    note: noteText(pending: spends.filter { !$0.isSettled }.count,
                                   otherCurrencies: settled.contains { $0.currency != currency }))
    }

    /// The currency most charges are denominated in. Ties break on the
    /// alphabetically-first code so the answer is stable across runs — an
    /// unstable pick would re-denominate the card between two refreshes with
    /// no data change.
    static func dominantCurrency(_ spends: [Spend]) -> String? {
        var counts: [String: Int] = [:]
        for s in spends { counts[s.currency, default: 0] += 1 }
        guard !counts.isEmpty else { return nil }
        return counts.sorted { a, b in
            a.value == b.value ? a.key < b.key : a.value > b.value
        }.first?.key
    }

    // MARK: - One merchant, one row

    /// The grouping identity for a merchant name: case-folded and trimmed.
    ///
    /// **Case matters here and nowhere else in this app.** FinanceKit hands
    /// over `merchantName` when it has one and we fall back to
    /// `transactionDescription` when it doesn't (`AppleWalletBridge.merchantLabel`),
    /// and those two fields do not agree about capitalisation — the same coffee
    /// shop arrives as "Blue Bottle Coffee" from one and "BLUE BOTTLE COFFEE"
    /// from the other. Grouping on the raw string files them as two merchants,
    /// which splits a total in half and can drop both halves below the ranking
    /// floor: the board then quietly omits the place you spend most.
    static func merchantKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The full grouping identity: the merchant AND the currency they charged
    /// in. **The file header says `Spend.currency` is part of every grouping
    /// key, and this is what makes that true.**
    ///
    /// It was not true until 2026-08-06. `compose` scopes to one currency
    /// before it groups, so the merchant alone was a safe key THERE and
    /// nowhere else — and `landChanges` then began calling `recurringSeries`
    /// over the unscoped corpus. One merchant billing €10, €10, $12 would have
    /// produced a series whose "rise" is a 20% price increase that never
    /// happened, landed as a row and announced as an alarm. Keying here rather
    /// than re-scoping at each call site puts the guarantee where it cannot be
    /// forgotten by the next caller.
    static func spendKey(_ s: Spend) -> String {
        merchantKey(s.merchant) + "\u{1}" + s.currency
    }

    /// Which spelling to SHOW when several land under one key. Prefers a form
    /// that isn't shouting: a card descriptor arrives ALL CAPS and a real
    /// merchant name arrives cased, so the cased one is the better label.
    ///
    /// Never re-cases anything itself — title-casing would turn IKEA into Ikea
    /// and CVS into Cvs, and a name we invented is not the merchant's name.
    /// Ties break alphabetically so the board can't reshuffle between refreshes.
    static func preferredSpelling(_ names: [String]) -> String {
        guard let first = names.first else { return "" }
        func shouts(_ s: String) -> Bool {
            let letters = s.filter(\.isLetter)
            return !letters.isEmpty && letters.allSatisfy { $0.isUppercase }
        }
        let cased = names.filter { !shouts($0) }
        let pool = cased.isEmpty ? names : cased
        return pool.sorted().first ?? first
    }

    /// Processor prefixes a card descriptor wears instead of the merchant's
    /// name. Square writes `SQ *BLUE BOTTLE`, Toast writes `TST* BLUE BOTTLE`,
    /// PayPal writes `PAYPAL *BLUE BOTTLE` — same shop, three names, three rows
    /// on a board that ranks by total.
    ///
    /// **UNMEASURED against real FinanceKit data**, like everything else in
    /// this seat. Each entry is a documented, widely-published descriptor form,
    /// and the whole table fails SAFE: an entry that never matches costs
    /// nothing, because `normalizeMerchant` returns its input unchanged unless
    /// a prefix really leads the string. Re-check against a real Apple Card
    /// before adding to it — a prefix that matches something it shouldn't
    /// merges two real merchants into one row, which is the only failure here
    /// that states something false.
    static let processorPrefixes = [
        "SQ *", "SQ*", "TST* ", "TST*", "PAYPAL *", "PAYPAL*", "PY *", "PP*",
        "SP *", "SP* ", "CLOVER *", "IN *", "GOOGLE *", "TOAST* ", "EB *",
        "WPY*", "SQU*",
    ]

    /// The merchant's own name, dug out of a payment descriptor.
    ///
    /// Two conservative rules and no third:
    ///  1. Strip ONE known leading processor token (the table above).
    ///  2. Strip a trailing reference code — a `*` followed by a run with no
    ///     spaces that CONTAINS A DIGIT, which is what `AMZN Mktp US*2H4KJ8`
    ///     is and what a merchant name never is. The digit requirement is the
    ///     guard: without it `AMZN Mktp US*PRIME` loses a real word.
    ///
    /// Anything else is returned untouched. It deliberately does NOT re-case,
    /// strip store numbers, or trim trailing city/state — each of those can
    /// merge two genuinely different merchants, and a board that silently
    /// combines two shops states a total nobody spent.
    ///
    /// A strip that would leave nothing meaningful behind is refused: the raw
    /// string is a worse label than the merchant's name and a better one than
    /// an empty row.
    static func normalizeMerchant(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespaces)
        for prefix in processorPrefixes where name.count > prefix.count {
            if name.uppercased().hasPrefix(prefix.uppercased()) {
                let stripped = String(name.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                if isMeaningfulName(stripped) { name = stripped }
                break
            }
        }
        if let star = name.lastIndex(of: "*") {
            let tail = name[name.index(after: star)...]
            let head = String(name[..<star]).trimmingCharacters(in: .whitespaces)
            // The head must look like a NAME, not like another processor tag.
            // `isMeaningfulName` alone accepts three letters, which turns an
            // unlisted processor into a merchant: `CKO*NORDVPN1` becomes "CKO",
            // and every Checkout.com purchase you ever made then ranks as one
            // merchant called CKO. Real names that reach this rule are long or
            // multi-word ("Amazon.com", "AMZN Mktp US"); a bare three-letter
            // head is the tag, not the shop.
            let headIsName = head.count >= minHeadForCodeStrip || head.contains(" ")
            if !tail.isEmpty, !tail.contains(" "), tail.contains(where: \.isNumber),
               isMeaningfulName(head), headIsName {
                name = head
            }
        }
        return name.isEmpty ? raw : name
    }

    /// Enough left to be somebody's name: three characters and a letter in it.
    static func isMeaningfulName(_ s: String) -> Bool {
        s.count >= 3 && s.contains(where: \.isLetter)
    }

    /// How long a single-word head must be before a trailing `*CODE` is taken
    /// off it. Guards against reading an unlisted processor tag as the shop —
    /// see `normalizeMerchant` rule 2.
    static let minHeadForCodeStrip = 6

    // MARK: - Who you actually pay

    /// Merchants ranked by NET settled spend. Refunds subtract; a merchant
    /// whose refunds exceed their charges drops off rather than ranking
    /// negative (they aren't somewhere you spend).
    static func leaderboard(_ spends: [Spend]) -> [MerchantRow] {
        var totals: [String: (net: Double, count: Int, currency: String,
                              names: [String])] = [:]
        for s in spends where s.amount >= minAmount || s.isRefund {
            let key = spendKey(s)
            var entry = totals[key] ?? (0, 0, s.currency, [])
            if !entry.names.contains(s.merchant) { entry.names.append(s.merchant) }
            if s.isRefund {
                entry.net -= s.amount
            } else {
                entry.net += s.amount
                entry.count += 1
            }
            totals[key] = entry
        }
        // Built with an explicit loop rather than filter/map/sorted chained
        // together: the chained form takes the Swift type-checker past its
        // budget on this tuple-valued dictionary ("unable to type-check this
        // expression in reasonable time"), which fails the build with an error
        // that names no cause. Same shape, same result, one statement each.
        var ranked: [MerchantRow] = []
        for (_, entry) in totals where entry.net > 0 && entry.count >= minChargesToRank {
            ranked.append(MerchantRow(name: preferredSpelling(entry.names),
                                      count: entry.count,
                                      total: entry.net, currency: entry.currency,
                                      share: 0))
        }
        // Ties break on name so the board is stable between refreshes.
        ranked.sort { a, b in a.total == b.total ? a.name < b.name : a.total > b.total }
        var sum = 0.0
        for row in ranked { sum += row.total }
        guard sum > 0 else { return ranked }
        for i in ranked.indices { ranked[i].share = ranked[i].total / sum }
        return ranked
    }

    // MARK: - Recurring detection

    /// A merchant charging on a believable cadence.
    struct Series: Equatable {
        var merchant: String
        var currency: String
        /// Settled charges, oldest first.
        var charges: [Spend]
        /// Median gap in days.
        var cadenceDays: Int
        var last: Spend { charges[charges.count - 1] }
        var nextExpected: Date {
            last.date.addingTimeInterval(Double(cadenceDays) * 86_400)
        }
    }

    /// Group by merchant and keep only those whose gaps hold a cadence.
    ///
    /// Deterministic on purpose — no model, no heuristic beyond arithmetic the
    /// harness can check. A wrong "recurring" verdict propagates into three
    /// other cards (creep, silence, the rail), so this is the one function here
    /// worth being conservative in.
    static func recurringSeries(_ spends: [Spend], now: Date) -> [Series] {
        // Keyed the leaderboard's way: a subscription that arrives cased one
        // month and shouting the next is one subscription, and splitting it
        // makes both halves too short to carry a cadence — so the room would
        // silently stop seeing the price rise it exists to report.
        var byMerchant: [String: [Spend]] = [:]
        for s in spends where s.isSettled && !s.isRefund && s.amount >= minAmount {
            byMerchant[spendKey(s), default: []].append(s)
        }
        var out: [Series] = []
        for (_, raw) in byMerchant {
            let charges = raw.sorted { $0.date < $1.date }
            let merchant = preferredSpelling(charges.map(\.merchant))
            guard charges.count >= minChargesToRecur else { continue }
            var gaps: [Double] = []
            for i in 1..<charges.count {
                gaps.append(charges[i].date.timeIntervalSince(charges[i - 1].date) / 86_400)
            }
            guard let cadence = median(gaps), cadence >= Double(minCadenceDays),
                  cadence <= Double(maxCadenceDays) else { continue }
            // EVERY gap must sit inside the tolerance — not the average, which
            // a pair of wildly wrong gaps can cancel out into looking regular.
            let regular = gaps.allSatisfy { abs($0 - cadence) <= cadence * cadenceTolerance }
            guard regular else { continue }
            out.append(Series(merchant: merchant, currency: charges[0].currency,
                              charges: charges, cadenceDays: Int(cadence.rounded())))
        }
        return out.sorted { $0.merchant < $1.merchant }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    // MARK: - Price creep

    /// EVERY recurring charge whose amount rose past both floors, fresh only.
    /// The card's subline takes the largest (`creep` below); the bridge lands
    /// each one as its own row — a month where Netflix and iCloud both went up
    /// is two facts, and the card showing one must not mean the corpus kept
    /// one.
    static func creeps(_ series: [Series], now: Date) -> [Creep] {
        var out: [Creep] = []
        for s in series {
            guard s.charges.count >= 2 else { continue }
            let latest = s.charges[s.charges.count - 1]
            let prior = s.charges[s.charges.count - 2]
            guard latest.amount >= minAmount, prior.amount >= minAmount else { continue }
            let delta = latest.amount - prior.amount
            guard delta >= creepMinDelta,
                  delta >= prior.amount * creepTolerance else { continue }
            let age = now.timeIntervalSince(latest.date) / 86_400
            guard age >= 0, age <= Double(creepFreshDays) else { continue }
            out.append(Creep(merchant: s.merchant, was: prior.amount,
                             now: latest.amount, currency: s.currency, at: latest.date))
        }
        return out
    }

    /// The single most useful thing this room can say. Only the LARGEST recent
    /// rise headlines — a card that lists every price change is a bill, and
    /// the point is to name the one worth looking at. Ranked by the SIZE of
    /// the rise, not the fraction: a $40 jump matters more than a 30% jump on
    /// a $3 subscription.
    static func creep(_ series: [Series], now: Date) -> Creep? {
        creeps(series, now: now).max { $0.delta < $1.delta }
    }

    // MARK: - Silence

    /// Recurring charges that stopped. Sorted most-overdue first, because the
    /// longest-silent is the one most likely to be a real cancellation.
    static func silences(_ series: [Series], now: Date) -> [Silence] {
        var out: [Silence] = []
        for s in series {
            let due = s.nextExpected
            let lateDays = now.timeIntervalSince(due) / 86_400
            guard lateDays > 0 else { continue }
            let threshold = max(Double(silenceFloorDays),
                                Double(s.cadenceDays) * (silenceFactor - 1))
            guard lateDays >= threshold else { continue }
            let sinceLast = now.timeIntervalSince(s.last.date) / 86_400
            guard sinceLast <= Double(silenceCeilingDays) else { continue }
            out.append(Silence(merchant: s.merchant, lastSeen: s.last.date,
                               expectedEvery: s.cadenceDays,
                               overdueDays: Int(lateDays.rounded())))
        }
        return out.sorted { $0.overdueDays > $1.overdueDays }
    }

    // MARK: - The clock rail

    /// What's coming, soonest first. A real payment deadline always outranks an
    /// inferred recurring date at the same distance — one is the source's own
    /// fact, the other is our arithmetic, and a card that mixes them without
    /// ordering them would let a guess sit above a bill.
    static func upcoming(series: [Series], dues: [Due], now: Date) -> [Upcoming] {
        var rows: [Upcoming] = dues.compactMap { due in
            let days = due.date.timeIntervalSince(now) / 86_400
            guard due.isOverdue || (days >= 0 && days <= Double(horizonDays)) else { return nil }
            return Upcoming(kind: .payment, label: due.account, date: due.date,
                            amount: due.amount, currency: due.currency,
                            isOverdue: due.isOverdue || days < 0)
        }
        for s in series {
            let next = s.nextExpected
            let days = next.timeIntervalSince(now) / 86_400
            guard days >= 0, days <= Double(horizonDays) else { continue }
            rows.append(Upcoming(kind: .recurring, label: s.merchant, date: next,
                                 amount: s.last.amount, currency: s.currency,
                                 isOverdue: false))
        }
        return rows.sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue }
            if a.date != b.date { return a.date < b.date }
            if a.kind != b.kind { return a.kind == .payment }
            return a.label < b.label
        }.prefix(upcomingCap).map { $0 }
    }

    // MARK: - Copy

    static func headlineText(merchants: [MerchantRow], total: Double,
                             currency: String) -> String {
        guard let top = merchants.first else {
            return String(localized: "Your card, this month")
        }
        let money = money(total, currency)
        if merchants.count == 1 {
            return String(localized: "\(money) this month, all at \(top.name)")
        }
        return String(localized: "\(money) this month · most of it at \(top.name)")
    }

    /// The subline states the CHANGE, which is the room's reason to exist.
    /// Ordered by how much it costs you to miss it: a price rise you didn't
    /// agree to, then a charge that stopped, then a date — and when none of
    /// those exists, the month-over-month comparison, so a quiet month still
    /// says something true instead of nothing.
    static func sublineText(creep: Creep?, silences: [Silence],
                            upcoming: [Upcoming],
                            total: Double, prevTotal: Double, prevCount: Int,
                            currency: String) -> String? {
        if let c = creep { return creepLine(c) }
        if let s = silences.first {
            return String(localized: "\(s.merchant) hasn't charged you in \(s.overdueDays) days")
        }
        if let u = upcoming.first(where: { $0.kind == .payment }) {
            return u.isOverdue
                ? String(localized: "\(u.label) payment is overdue")
                : String(localized: "\(u.label) payment due \(dayLabel(u.date))")
        }
        return comparisonText(total: total, prevTotal: prevTotal,
                              prevCount: prevCount, currency: currency)
    }

    /// The month-over-month line. Nil without a real prior window — a first
    /// month has nothing to compare against, and "up from $0" would be the
    /// app congratulating you on existing. Inside `comparisonFlatBand` the
    /// line carries NO direction (§83): "about the same" is the honest
    /// reading of a few percent of calendar wobble.
    static func comparisonText(total: Double, prevTotal: Double, prevCount: Int,
                               currency: String) -> String? {
        guard prevCount > 0, prevTotal > 0, total > 0 else { return nil }
        let fraction = (total - prevTotal) / prevTotal
        if abs(fraction) < comparisonFlatBand {
            return String(localized: "About the same as last month (\(money(prevTotal, currency)))")
        }
        let pct = Int((abs(fraction) * 100).rounded())
        return fraction > 0
            ? String(localized: "Up \(pct)% from \(money(prevTotal, currency)) last month")
            : String(localized: "Down \(pct)% from \(money(prevTotal, currency)) last month")
    }

    /// What the card is NOT counting. A total that silently excludes pending
    /// authorizations and foreign charges reads as wrong to anyone who checks
    /// it against their statement, so the card says so.
    static func noteText(pending: Int, otherCurrencies: Bool) -> String? {
        var parts: [String] = []
        if pending > 0 {
            parts.append(pending == 1
                ? String(localized: "1 pending charge isn't counted")
                : String(localized: "\(pending) pending charges aren't counted"))
        }
        if otherCurrencies {
            parts.append(String(localized: "other currencies shown separately"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The price-rise sentence, in one place so the card's subline and the
    /// landed row's title can never say different things about one rise.
    static func creepLine(_ c: Creep) -> String {
        let pct = Int((c.fraction * 100).rounded())
        return String(localized: "\(c.merchant) went up \(pct)% — \(money(c.was, c.currency)) to \(money(c.now, c.currency))")
    }

    // MARK: - What leaves the room
    //
    // A card that only speaks while you're standing in it can't tell you
    // anything you didn't go looking for — and "Netflix went up 16%" is
    // precisely the fact nobody goes looking for, because nobody knows to. So
    // the two judgements this room makes that are NEWS rather than state get
    // landed as rows by `AppleWalletBridge`, which puts them in the feed, in
    // reach of the notify sweep, and in the corpus a year from now.
    //
    // The refs below are the dedupe identity, and each is keyed so that ONE
    // event lands ONCE while a genuinely new one still lands.

    /// A price rise, keyed by merchant, BOTH amounts in minor units, and the
    /// DAY the raised charge posted.
    ///
    /// The amounts alone would be enough for a subscription that only ever
    /// climbs (15.49 → 17.99 → 19.99, three distinct pairs) and wrong for one
    /// that cycles: promotional pricing runs $15.99 → $9.99 → $15.99, and a
    /// year later the identical promo ends again. Keyed on amounts alone the
    /// second rise dedupes against the first and never lands — a real, current
    /// price increase silently reported to nobody. The day makes each rise its
    /// own event while keeping the pass idempotent, since re-reading the same
    /// charge yields the same day.
    static func creepRef(_ c: Creep) -> String {
        let was = Int((c.was * 100).rounded())
        let now = Int((c.now * 100).rounded())
        let day = Int(c.at.timeIntervalSince1970 / 86_400)
        return "applewallet:creep:\(merchantKey(c.merchant)):\(was):\(now):\(day)"
    }

    /// A stopped subscription, keyed by merchant and the day it last charged.
    /// One outage lands one row; a subscription that resumes and later stops
    /// again has a new last-charge day, so that outage lands too.
    static func silenceRef(_ s: Silence) -> String {
        "applewallet:silence:\(merchantKey(s.merchant)):\(Int(s.lastSeen.timeIntervalSince1970))"
    }

    /// The stopped-subscription sentence, stated so it CANNOT GO STALE.
    ///
    /// The card's subline says "hasn't charged you in 29 days", which is true
    /// of the moment it's drawn and false a week later. A landed row is read
    /// months afterwards, so it names the last charge DATE instead — a fact
    /// that stays true forever and needs no heal pass to keep honest.
    static func silenceTitle(_ s: Silence) -> String {
        String(localized: "\(s.merchant) stopped charging you — last was \(dayLabel(s.lastSeen))")
    }

    /// The last-charge date encoded in a landed silence row's ref, so a later
    /// pass can ask whether that subscription has since resumed. Nil for any
    /// ref this build didn't write.
    static func silenceLastSeen(fromRef ref: String) -> Date? {
        guard ref.hasPrefix("applewallet:silence:"),
              let stamp = ref.split(separator: ":").last,
              let seconds = Double(stamp) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// When a stopped subscription HAPPENED, which is the date it missed
    /// rather than the date we noticed. Stamping a row with "now" would sort
    /// a months-old cancellation into today and let it wear an urgency it
    /// doesn't have — the news-only rule every bridge here follows.
    static func silenceOccurredAt(_ s: Silence) -> Date {
        s.lastSeen.addingTimeInterval(Double(s.expectedEvery) * 86_400)
    }

    /// Formatted money. Falls back to a plain 2-decimal rendering with the code
    /// rather than dropping the currency — an unlabelled number in a room that
    /// refuses to sum currencies would be the exact ambiguity the rule exists
    /// to prevent.
    static func money(_ value: Double, _ currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = value >= 100 ? 0 : 2
        if let s = f.string(from: NSNumber(value: value)) { return s }
        return String(format: "%.2f %@", value, currency)
    }

    static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }
}
