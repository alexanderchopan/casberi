import Foundation

/// THE DODO PAYMENTS ROOM'S HEAD (2026-09-01, prd §558) — what came in, what
/// went back out, and what needs you.
///
/// Until this date Dodo was the one payments seat in the catalog with no head
/// of any kind: no `SourceHead` case, no `FeedScreen.Shape` case, no entry in
/// any `FeedInsight` registry, not even a `FeedHeatmap` label — so a room
/// holding every payment the account took drew a bare band of rows, which for
/// money is the §247 gap at its widest. `DemoSeedAll` recorded the absence in
/// as many words and seeded the plain rows to match.
///
/// ## Why this room may state a revenue figure when `StripeRoom` may not
///
/// `StripeRoom` refuses one twice over, and BOTH of its reasons are absent
/// here rather than merely overlooked:
///
///   1. **Stripe's amounts cannot do arithmetic.** They survive only as
///      formatted substrings inside row titles, so any total would mean
///      re-parsing prose. `DodoPaymentsIngest` stamps `priceValue` AND
///      `priceCurrency` on every payment and refund it lands — the same data
///      test `Corpus.cardSpendSources` is built on.
///   2. **Stripe's landed rows are a BIASED SAMPLE.** It lands disputes,
///      dunning and payouts and never an individual charge, so a figure built
///      from them "would read as 'your revenue' while plotting your problems".
///      `DodoPaymentsBridge` lands EVERY succeeded payment inside its window,
///      by the deliberate divergence its own type doc records and defends.
///      Here the sample IS the population.
///
/// So the figure is a sum of what landed, over exactly the window the bridge
/// reads. That is honest only while both halves of that sentence hold, which
/// is why `windowDays` here is pinned equal to `DodoPaymentsAccount.windowDays`
/// by the harness rather than trusted: were the two to drift, this card would
/// state a 30-day total over 14 days of rows and look perfectly correct doing
/// it — the silent wrong answer this whole file exists to avoid.
///
/// ## What it may NOT draw
///
///   · **No cross-currency total.** `GnosisPayRoom`'s rule, and Stripe's, and
///     Polar's: three currencies are three readings and never one sum. They
///     rank by payment COUNT, the only ordering that does not compare
///     magnitudes across codes.
///   · **No revenue CURVE.** `StripeRoom`'s ban survives the two paragraphs
///     above for a different reason: this bridge targets accounts that take a
///     payment occasionally rather than constantly, so a window is a handful
///     of points and a line drawn through them states a trend the data cannot
///     support.
///   · **No comparison against an unobserved window.** `GnosisPayRoom`'s
///     refusal, biting harder here — the bridge reads a rolling window every
///     pass and keeps no cursor, so on a first connect the previous window is
///     UNOBSERVED rather than quiet, and "up 400%" against it is a confident
///     fabrication on the screen where money is the subject.
///   · **An unsettled refund never subtracts.** `DodoPaymentsShape.refund`
///     lands a refund at EVERY status and facets the ones that are not
///     `succeeded`. A pending or failed refund has moved no money, so counting
///     it against revenue understates a total nobody can check —
///     `AppleWalletRoom`'s `isSettled` rule, the §83 fake-status ban wearing a
///     dollar sign.
///   · **A refund never CREATES a currency.** `AppleWalletRoom`'s rule that a
///     store which only ever refunded you is not somewhere you spend, read the
///     other way round: a code you have only ever refunded in is not revenue,
///     and admitting it would put a NEGATIVE total on a revenue card. Such
///     refunds are counted in `unmatchedRefunds` and said out loud rather than
///     dropped in silence.
///
/// Foundation-only by design so `scripts/dodo-payments-selftest.sh` can compile
/// it WHOLE and unmodified.
struct DodoPaymentsRoom: Equatable {

    // MARK: - Values

    /// One landed money row, reduced to what this card reads.
    struct Sighting: Equatable {
        /// `Thing.priceValue` — whole currency units. Nil where the bridge
        /// could not read one; such a row is EXCLUDED and counted, never
        /// treated as zero (a zero is a payment of nothing, a different and
        /// false claim).
        let amount: Double?
        /// `Thing.priceCurrency` — "USD", "EUR".
        let currency: String?
        let at: Date
        /// A refund rather than a payment.
        let isRefund: Bool
        /// A refund Dodo reported as `succeeded` — money that really went back.
        /// False for pending/failed/review. Meaningless for a payment, which
        /// this bridge only ever lands in the succeeded state, so a payment
        /// passes it true.
        let settled: Bool
    }

    /// One currency's window.
    struct Currency: Identifiable, Equatable {
        var id: String { code }
        let code: String
        /// Payments in, summed. Never across codes.
        let gross: Double
        let payments: Int
        /// Settled refunds out, summed — subtracted from `gross`, never
        /// allowed to create this entry on its own.
        let refunded: Double
        let refunds: Int
        /// The same currency's NET in the window BEFORE this one — nil when the
        /// room's history cannot cover it. See the type note.
        let prior: Double?
        let newest: Date

        /// What the account actually kept.
        var net: Double { gross - refunded }
    }

    /// A dispute this room has seen opened and never seen closed.
    struct Dispute: Identifiable, Equatable {
        let id: String
        let amount: Double?
        let currency: String?
        let at: Date
    }

    /// A subscription whose next attempt carries a date. The bridge stamps
    /// `dueAt` from `next_billing_date` and ONLY while the status is still
    /// recoverable, so every one of these is a subscription that can still be
    /// saved.
    struct Retry: Identifiable, Equatable {
        let id: String
        let name: String
        let due: Date
        /// Whole calendar days from today. Negative means the date has passed.
        let days: Int
    }

    /// How far back the card reads. Pinned equal to
    /// `DodoPaymentsAccount.windowDays` by the harness — see the type note.
    static let windowDays = 30

    /// Currencies drawn. Unlike Gnosis Pay's closed three-stablecoin set, a
    /// payment processor can bill in anything, so the tail is folded and NAMED
    /// by `coverageNote` rather than silently cut.
    static let rowCap = 3

    /// Retries drawn on the rail.
    static let retryCap = 3

    /// Ranked — see `ordered`. Every currency with a payment in the window.
    let currencies: [Currency]
    /// Payments inside the window that carried no usable amount. Counted, never
    /// folded into a total as zero.
    let unpriced: Int
    /// Settled refunds inside the window in a currency that took no payments —
    /// see the type note on why they subtract from nothing.
    let unmatchedRefunds: Int
    /// Every money row the room holds, window or not, so the card can tell a
    /// quiet window on real history apart from an empty room.
    let allTime: Int
    /// The oldest money row seen, which is what decides whether a prior window
    /// is knowable at all.
    let oldest: Date?
    /// The newest money row anywhere in the room, for the idle clause.
    let newest: Date?
    /// Open disputes, newest first.
    let disputes: [Dispute]
    /// Soonest first — CAPPED to what the rail draws.
    let retries: [Retry]
    /// How many retries exist in total, drawn or not — `StripeRoom.total`'s
    /// reason: the headline needs the uncapped count so it can never disagree
    /// with the coverage note beneath it.
    let retryTotal: Int
    /// Currencies with a payment in the window that the `rowCap` left out.
    let currenciesHidden: Int

    var lead: Currency? { currencies.first }
    var payments: Int { currencies.reduce(0) { $0 + $1.payments } }

    /// Whether the headline is about trouble rather than about money — which
    /// is what tells `note` to carry the money instead.
    var leadsWithTrouble: Bool { !disputes.isEmpty || retryTotal > 0 }

    /// Nothing worth a card. Keyed on the ROOM rather than on the window
    /// (`GnosisPayRoom`'s rule): an account that was busy last quarter and
    /// quiet this month has a real thing to say, and hiding the head would
    /// leave the room looking as though it had never been used.
    var isEmpty: Bool { allTime == 0 && disputes.isEmpty && retryTotal == 0 }

    // MARK: - Composing

    /// The whole card, off landed rows and nothing else.
    ///
    /// `now` is taken rather than read, so the harness and the probe compose
    /// against a fixed clock.
    static func compose(sightings: [Sighting],
                        disputes: [Dispute],
                        retries: [Retry],
                        now: Date = .now,
                        calendar: Calendar = .current) -> DodoPaymentsRoom {
        let start = windowStart(now, back: 1, calendar: calendar)
        let priorStart = windowStart(now, back: 2, calendar: calendar)

        var unpriced = 0
        var unmatchedRefunds = 0
        var oldest: Date?, newest: Date?
        // Keyed by the currency's own code — grouping cannot invent a bucket.
        var gross: [String: (total: Double, count: Int, newest: Date)] = [:]
        var refunded: [String: (total: Double, count: Int)] = [:]
        var priorGross: [String: Double] = [:]
        var priorRefunded: [String: Double] = [:]

        for sighting in sightings {
            // Over EVERY row, priced or not, windowed or not: these two bound
            // what the card may claim, and a row we could not price still
            // proves the account was used.
            if oldest == nil || sighting.at < oldest! { oldest = sighting.at }
            if newest == nil || sighting.at > newest! { newest = sighting.at }

            // Anything older than the comparison window contributes to neither
            // total. `start` is inside `priorStart`, so this one test bounds
            // both.
            guard sighting.at >= priorStart else { continue }
            let code = sighting.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let amount = sighting.amount, let code, !code.isEmpty else {
                // Only a PAYMENT counts as revenue missing from the figure
                // above it. An unreadable refund is money we simply fail to
                // subtract, which overstates nothing the reader is shown.
                if sighting.at >= start, !sighting.isRefund { unpriced += 1 }
                continue
            }
            // An unsettled refund has moved no money — see the type note.
            if sighting.isRefund, !sighting.settled { continue }

            guard sighting.at >= start else {
                if sighting.isRefund { priorRefunded[code, default: 0] += amount }
                else { priorGross[code, default: 0] += amount }
                continue
            }
            if sighting.isRefund {
                var cell = refunded[code] ?? (total: 0, count: 0)
                cell.total += amount
                cell.count += 1
                refunded[code] = cell
            } else {
                var cell = gross[code] ?? (total: 0, count: 0, newest: sighting.at)
                cell.total += amount
                cell.count += 1
                if sighting.at > cell.newest { cell.newest = sighting.at }
                gross[code] = cell
            }
        }

        // A prior total is reported only when the room's own history reaches
        // back far enough to have observed that window — see the type note.
        let covered = knowsPriorWindow(oldest: oldest, now: now, calendar: calendar)
        // Keyed on GROSS alone: a refund never creates a currency entry, so a
        // code that only ever refunded contributes its subtraction to nothing
        // and is counted here instead of drawn as a negative.
        for (code, cell) in refunded where gross[code] == nil {
            unmatchedRefunds += cell.count
        }
        let built = gross.map { code, cell in
            Currency(code: code,
                     gross: cell.total, payments: cell.count,
                     refunded: refunded[code]?.total ?? 0,
                     refunds: refunded[code]?.count ?? 0,
                     prior: covered
                        ? (priorGross[code] ?? 0) - (priorRefunded[code] ?? 0)
                        : nil,
                     newest: cell.newest)
        }
        let ranked = ordered(built)
        let sortedDisputes = disputes.sorted { a, b in
            a.at != b.at ? a.at > b.at : a.id < b.id
        }
        let sortedRetries = retries.sorted { a, b in
            a.days != b.days ? a.days < b.days : a.id < b.id
        }
        return DodoPaymentsRoom(
            currencies: Array(ranked.prefix(rowCap)),
            unpriced: unpriced,
            unmatchedRefunds: unmatchedRefunds,
            allTime: sightings.count,
            oldest: oldest, newest: newest,
            disputes: sortedDisputes,
            retries: Array(sortedRetries.prefix(retryCap)),
            retryTotal: sortedRetries.count,
            currenciesHidden: max(0, ranked.count - rowCap))
    }

    /// The start of the window `back` windows ago — 1 is the current one.
    static func windowStart(_ now: Date, back: Int, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -windowDays * back, to: day) ?? day
    }

    /// Whether the room has been watching long enough for "the previous window"
    /// to be an observation rather than an absence of data.
    ///
    /// The bar is that the oldest row we hold predates the prior window's
    /// START. A row landed inside the prior window proves only that the account
    /// existed by then; it says nothing about the days before it, and the
    /// bridge's own rolling window is exactly where a first read stops.
    static func knowsPriorWindow(oldest: Date?, now: Date,
                                 calendar: Calendar = .current) -> Bool {
        guard let oldest else { return false }
        return oldest <= windowStart(now, back: 2, calendar: calendar)
    }

    // MARK: - Ranking

    /// Payment COUNT, then recency, then code — TOTAL, so two composes over the
    /// same data can never disagree and the card cannot reshuffle between
    /// opens.
    ///
    /// Never by amount. Ranking currencies by total would compare 400 EUR
    /// against 380 GBP as if the numbers sat on one scale, which is the
    /// cross-currency sum this file refuses, wearing a sort instead of a plus.
    static func ordered(_ currencies: [Currency]) -> [Currency] {
        currencies.sorted { a, b in
            if a.payments != b.payments { return a.payments > b.payments }
            if a.newest != b.newest { return a.newest > b.newest }
            return a.code < b.code
        }
    }

    // MARK: - The change

    /// This window's NET against the one before it, as a fraction — +0.25 is a
    /// quarter more. Nil when the prior window is unknown, or was zero or
    /// negative.
    ///
    /// A zero prior does not divide, and it does not become 1 either: coming
    /// back from nothing has no percentage. A NEGATIVE prior (a window where
    /// refunds outran payments) has no percentage either — dividing by it flips
    /// the sign, so growth would print as a fall.
    static func delta(_ currency: Currency) -> Double? {
        guard let prior = currency.prior, prior > 0 else { return nil }
        return (currency.net - prior) / prior
    }

    /// Whether a change is big enough to be worth a word. Revenue at this scale
    /// is lumpy — one annual plan lands differently in two windows — so a small
    /// move is noise, and a card that announces noise is one people stop
    /// believing.
    static let deltaFloor = 0.10

    static func deltaLabel(_ currency: Currency) -> String? {
        guard let delta = delta(currency), abs(delta) >= deltaFloor else { return nil }
        let percent = Int((abs(delta) * 100).rounded())
        return delta > 0
            ? String(localized: "\(percent)% more than the \(windowDays) days before")
            : String(localized: "\(percent)% less than the \(windowDays) days before")
    }

    // MARK: - The bar

    /// A currency's share of the window's payments BY COUNT, 0…1 — the only
    /// magnitude drawn on a currency row. By count, not by amount, for
    /// `ordered`'s reason: the amounts are in different currencies and drawing
    /// them on one axis would state a conversion nobody made.
    static func share(payments: Int, of top: Int) -> Double {
        guard top > 0 else { return 0 }
        return min(max(Double(payments) / Double(top), 0), 1)
    }

    // MARK: - The retry rail

    static func days(from now: Date, to later: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    static func span(days: [Int]) -> Int {
        RoomRunway.span(days: days)
    }

    static func position(days: Int, span: Int) -> Double {
        RoomRunway.position(days: days, span: span)
    }

    static func spanLabel(span: Int) -> String {
        RoomRunway.spanLabel(span: span)
    }

    static func value(days: Int) -> String {
        if days < 0 { return String(localized: "due") }
        if days == 0 { return String(localized: "today") }
        if days == 1 { return String(localized: "tomorrow") }
        return String(localized: "\(days) days")
    }

    /// The chip on a retry row.
    ///
    /// NEVER "Missed", which is what `PolarRoom` says for a passed date and
    /// what this card must not: Polar's deadline is an evidence window that
    /// really can be missed, while this date is Dodo's own
    /// `next_billing_date` — the moment the next attempt was DUE. This bridge
    /// has no signal for whether that attempt has since happened, so calling it
    /// missed states an outcome nobody measured (§83, on the card whose subject
    /// is money).
    static func retryChip(_ retry: Retry) -> String {
        retry.days < 0 ? String(localized: "Retrying") : String(localized: "Next attempt")
    }

    // MARK: - Words

    /// The locale is a PARAMETER so the harness can pin one; nothing in the app
    /// passes it. A currency string built against the device locale is right for
    /// a person and untestable without this.
    static func money(_ amount: Double, code: String, locale: Locale = .current) -> String {
        amount.formatted(.currency(code: code).locale(locale))
    }

    static func paymentsLabel(_ count: Int) -> String {
        count == 1 ? String(localized: "1 payment") : String(localized: "\(count) payments")
    }

    /// The line beside a currency row: what was kept, then how many payments.
    ///
    /// `mask` is the §374 hide-balances string, PASSED IN rather than read —
    /// this file is Foundation-only and is compiled WHOLE and unmodified by
    /// `scripts/dodo-payments-selftest.sh`, so it cannot reach `BalancePrivacy`
    /// without breaking the only proof these numbers are right. The parameter
    /// also lets the harness test both states, which reading a singleton would
    /// not.
    ///
    /// The PAYMENT COUNT survives the mask on purpose: how many times you were
    /// paid is not a balance, and it is what is left to say once the amount is
    /// gone.
    static func currencyLine(_ currency: Currency, locale: Locale = .current,
                             mask: String? = nil) -> String {
        (mask ?? money(currency.net, code: currency.code, locale: locale))
            + " · " + paymentsLabel(currency.payments)
    }

    /// The one line at the top of the card. Ranked TROUBLE FIRST (§349): an
    /// open dispute is money actively at stake and outranks everything; then a
    /// subscription that can still be saved; then the window's revenue, the
    /// everyday reading and the reason most people open the room.
    ///
    /// `mask` — see `currencyLine`. The trouble rungs carry no money of their
    /// own except a disputed amount, which is masked with the rest.
    static func headline(_ room: DodoPaymentsRoom, locale: Locale = .current,
                         mask: String? = nil) -> String {
        if room.disputes.count > 1 {
            return String(localized: "\(room.disputes.count) disputes are open")
        }
        if let dispute = room.disputes.first {
            if let amount = dispute.amount, let code = dispute.currency, !code.isEmpty {
                let text = mask ?? money(amount, code: code, locale: locale)
                return String(localized: "A dispute is open · \(text)")
            }
            return String(localized: "A dispute is open")
        }
        if room.retryTotal > 0 {
            return room.retryTotal == 1
                ? String(localized: "A subscription needs you")
                : String(localized: "\(room.retryTotal) subscriptions need you")
        }
        guard let lead = room.lead else {
            // A quiet window on a room with real history — the honest reading,
            // and the one a list of old rows never states.
            guard room.allTime > 0 else { return String(localized: "Nothing has come in yet") }
            return String(localized: "Nothing came in over \(windowDays) days")
        }
        let amount = mask ?? money(lead.net, code: lead.code, locale: locale)
        if room.currencies.count > 1 {
            let others = room.currencies.count - 1
            return others == 1
                ? String(localized: "\(amount) in \(lead.code), plus another currency")
                : String(localized: "\(amount) in \(lead.code), plus \(others) other currencies")
        }
        return String(localized: "\(amount) in \(windowDays) days")
    }

    /// The line under it — NEVER a restatement (`PolarRoom`'s rule). When
    /// trouble leads the headline this carries the money, so one glance always
    /// gets both; when the money leads, this carries how it MOVED.
    static func note(_ room: DodoPaymentsRoom, locale: Locale = .current,
                     mask: String? = nil) -> String {
        if room.leadsWithTrouble {
            guard let lead = room.lead else {
                return room.allTime > 0
                    ? String(localized: "Nothing came in over \(windowDays) days")
                    : String(localized: "Nothing has come in yet")
            }
            let amount = mask ?? money(lead.net, code: lead.code, locale: locale)
            return String(localized: "\(amount) in \(windowDays) days")
        }
        guard let lead = room.lead else {
            guard room.allTime > 0 else { return String(localized: "No payments have landed") }
            return String(localized: "\(paymentsLabel(room.allTime)) before that")
        }
        if let change = deltaLabel(lead) { return change }
        if lead.prior == nil {
            // Said out loud rather than left blank: "no comparison" and "no
            // change" look identical on a card, and only one is a measurement.
            return String(localized: "\(paymentsLabel(lead.payments)) · not watching long enough to compare")
        }
        return String(localized: "\(paymentsLabel(lead.payments)) · about the same as the \(windowDays) days before")
    }

    /// What the lead currency gave back, stated apart from the net above it —
    /// a net alone cannot show whether a quiet window was quiet or busy and
    /// refunded. Nil when nothing came back.
    static func refundNote(_ room: DodoPaymentsRoom, locale: Locale = .current,
                           mask: String? = nil) -> String? {
        guard let lead = room.lead, lead.refunds > 0 else { return nil }
        let amount = mask ?? money(lead.refunded, code: lead.code, locale: locale)
        return lead.refunds == 1
            ? String(localized: "\(amount) refunded on 1 payment")
            : String(localized: "\(amount) refunded across \(lead.refunds) payments")
    }

    /// What the caps left out. Never truncated in silence — a dropped currency
    /// or a dropped retry looks exactly like one that was never there.
    static func coverageNote(_ room: DodoPaymentsRoom) -> String? {
        var parts: [String] = []
        if room.currenciesHidden > 0 {
            parts.append(room.currenciesHidden == 1
                         ? String(localized: "1 more currency — not drawn")
                         : String(localized: "\(room.currenciesHidden) more currencies — not drawn"))
        }
        if room.retryTotal > room.retries.count {
            parts.append(String(localized: "\(room.retryTotal - room.retries.count) more further out — not drawn"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The quiet line at the foot: money missing from the figure above, and how
    /// long the account has been silent. The unpriced clause is not politeness —
    /// such a payment is revenue absent from the total directly above it.
    static func footnote(_ room: DodoPaymentsRoom, now: Date = .now) -> String? {
        var parts: [String] = []
        if room.unpriced > 0 {
            parts.append(room.unpriced == 1
                         ? String(localized: "1 payment has no readable amount")
                         : String(localized: "\(room.unpriced) payments have no readable amount"))
        }
        if room.unmatchedRefunds > 0 {
            parts.append(room.unmatchedRefunds == 1
                         ? String(localized: "1 refund in another currency")
                         : String(localized: "\(room.unmatchedRefunds) refunds in other currencies"))
        }
        if let idle = idleNote(newest: room.newest, now: now) { parts.append(idle) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "quiet for 40 days" — only once the gap outruns the window itself, so it
    /// can never contradict a headline that just reported money inside it.
    static func idleNote(newest: Date?, now: Date = .now) -> String? {
        guard let newest else { return nil }
        let days = days(from: newest, to: now)
        guard days > windowDays else { return nil }
        return String(localized: "quiet for \(days) days")
    }
}
