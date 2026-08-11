import Foundation

/// THE GNOSIS PAY ROOM'S HEAD (2026-08-10, prd §348) — what the card actually
/// costs you.
///
/// §222 landed every card settlement as its own row and the room led with a
/// list of them, which for a spending card is the §247 gap at its widest: a
/// list of purchases is a statement, and nobody opens a statement to read it
/// line by line. The standing question is **how much have I put through this
/// card lately, and is that more or less than usual?**
///
/// ## It spends nothing, and unlike its neighbours it can state money
///
/// `GnosisPayBridge` stamps `priceValue` and `priceCurrency` on every spend —
/// deliberately, per its own note, "without these an amount can never be
/// re-formatted or compared". So this head sums real numbers off real fields,
/// where `PeerRoom` and `PrivacyPoolsRoom` must refuse to (their bridges keep
/// the amount only as prose in a title). No request, no new `Thing` property,
/// no CloudKit deploy.
///
/// ## Currencies are never summed
///
/// A Gnosis Pay account can settle in EURe, GBPe and USDCe, and adding them
/// needs an exchange rate this app does not have and will not invent — the
/// standing rule `StripeScreen` set and `StripeRoom` keeps. Every total here is
/// per currency, the rows are ranked by SPEND COUNT rather than by amount (the
/// only ordering that does not require comparing magnitudes across
/// currencies), and the headline states one currency's money and says so.
///
/// ## What it may NOT draw: where you spent it
///
/// The obvious card for a payment card is a merchant board, and this bridge
/// structurally cannot have one. §222's measured ceiling: merchant names never
/// reach the chain — the settlement is an ERC-20 transfer from your Safe to
/// Gnosis Pay's, and that is all there is. `AppleWalletRoom` ranks merchants
/// because FinanceKit hands them over; drawing the same card here would mean
/// inventing them. Refunds are equally out of reach (they settle off-chain,
/// measured as zero outbound from the settlement Safe across 40k blocks), so
/// no total here is a NET and none of them claims to be.
///
/// ## The comparison is refused rather than estimated
///
/// A window's spend means nothing without a previous one to read it against,
/// and a previous window is only knowable if the room's history actually
/// reaches back that far. A first sync backfills about six days, so on a fresh
/// connection the prior window is not quiet — it is unobserved, and reporting
/// "up 400%" against it would be a confident fabrication on the screen where
/// money is the subject. `delta` returns nil unless the room has seen a spend
/// old enough to cover the comparison window (the `PostHogRoom` week-over-week
/// rule, in a currency).
///
/// Foundation-only by design so `scripts/wallet-rooms-selftest.sh` can compile
/// it WHOLE and unmodified.
struct GnosisPayRoom: Equatable {

    // MARK: - Values

    /// One landed spend, reduced to what this card reads.
    struct Sighting: Equatable {
        /// `Thing.priceValue` — the real number, in whole currency units. Nil
        /// on a row landed before the field, or where the token's decimals
        /// could not be read; such a row is EXCLUDED and counted, never
        /// treated as zero (a zero is a spend of nothing, which is a different
        /// and false claim).
        let amount: Double?
        /// `Thing.priceCurrency` — "EUR", "GBP", "USD".
        let currency: String?
        let at: Date
    }

    /// One currency's spending inside the window.
    struct Currency: Identifiable, Equatable {
        var id: String { code }
        let code: String
        /// Summed inside the window. Never across codes.
        let total: Double
        let spends: Int
        /// The same currency's total in the window BEFORE this one — nil when
        /// the room's history cannot cover it. See the type note.
        let prior: Double?
        let newest: Date
    }

    /// One calendar month of the LEAD currency's spending, for the history
    /// strip. See `months`.
    struct Month: Identifiable, Equatable {
        /// Sortable and stable: year × 12 + month.
        var id: Int { key }
        let key: Int
        /// The first instant of the month, for labelling.
        let start: Date
        let total: Double
        let spends: Int
    }

    /// How far back the card reads, in days. Thirty rather than a calendar
    /// month on purpose: month boundaries make the first week of any month
    /// read as a collapse in spending, every month, forever.
    static let windowDays = 30

    /// How many months of history the strip draws. Twelve, matching the
    /// `FeedInsight.cardMonths` leaderboard this head supersedes — the strip
    /// exists so that superseding costs nothing: a head outranks the generic
    /// registries, so a head that showed less than the card it displaced would
    /// be a regression wearing a new feature.
    static let monthCap = 12

    /// Ranked — see `ordered`. Every currency with a spend in the window.
    let currencies: [Currency]
    /// Spends inside the window that carried no usable amount. Counted, never
    /// folded into a total as zero.
    let unpriced: Int
    /// Every spend the room holds, window or not — so the card can say when a
    /// quiet window sits on top of real history rather than on an empty room.
    let allTime: Int
    /// The oldest spend the room has seen, which is what decides whether a
    /// prior window is knowable at all.
    let oldest: Date?
    /// The newest spend anywhere in the room, for the idle clause.
    let newest: Date?
    /// The LEAD currency's trailing calendar months that had spending, OLDEST
    /// FIRST so the strip reads left to right as time. Empty below two months,
    /// because a one-column history is not a history.
    ///
    /// One currency, named on the card. `FeedInsight.cardMonths` — the
    /// leaderboard this head displaces — picked a currency by whichever row it
    /// happened to meet first and then silently skipped every spend in another,
    /// so its total was a subset presented as the total. This strip states
    /// which currency it is drawing, and `monthsOtherCurrency` counts what that
    /// choice leaves out.
    let months: [Month]
    /// Months with spending that fall outside `monthCap`. Counted, never
    /// silently truncated — a dropped month looks exactly like a quiet one.
    let monthsHidden: Int
    /// Spends inside the strip's span that are in a DIFFERENT currency, and so
    /// contribute to no column. Counted for the same reason.
    let monthsOtherCurrency: Int

    var lead: Currency? { currencies.first }
    var spends: Int { currencies.reduce(0) { $0 + $1.spends } }

    /// Nothing worth a card. Keyed on the ROOM, not on the window: a card that
    /// was busy last quarter and quiet this month has a real thing to say
    /// ("nothing in 30 days"), and hiding the head would leave the room
    /// looking like it had never been used.
    var isEmpty: Bool { allTime == 0 }

    // MARK: - Composing

    /// The whole card, off landed rows and nothing else.
    ///
    /// `now` is taken rather than read, so the harness and the probe compose
    /// against a fixed clock.
    static func compose(spends sightings: [Sighting], now: Date = .now,
                        calendar: Calendar = .current) -> GnosisPayRoom {
        let start = windowStart(now, back: 1, calendar: calendar)
        let priorStart = windowStart(now, back: 2, calendar: calendar)

        var unpriced = 0
        var oldest: Date?, newest: Date?
        // Keyed by the currency's own code — grouping cannot invent a bucket.
        var buckets: [String: (total: Double, spends: Int, newest: Date)] = [:]
        var priors: [String: Double] = [:]
        // code → month key → that month's spending. Filled across the WHOLE
        // room, since the strip is a history and the two windows are not.
        var monthly: [String: [Int: (total: Double, spends: Int)]] = [:]

        for sighting in sightings {
            // Over EVERY spend, priced or not, windowed or not: these two
            // bound what the card is allowed to claim, and a spend we could
            // not price still proves the card was used.
            if oldest == nil || sighting.at < oldest! { oldest = sighting.at }
            if newest == nil || sighting.at > newest! { newest = sighting.at }

            // The strip's buckets are filled BEFORE the window guard below,
            // which drops everything older than two windows.
            if let amount = sighting.amount,
               let monthCode = sighting.currency?.trimmingCharacters(in: .whitespacesAndNewlines),
               !monthCode.isEmpty,
               let key = monthKey(sighting.at, calendar: calendar) {
                var cells = monthly[monthCode] ?? [:]
                var cell = cells[key] ?? (total: 0, spends: 0)
                cell.total += amount
                cell.spends += 1
                cells[key] = cell
                monthly[monthCode] = cells
            }

            // Anything older than the comparison window contributes nothing to
            // either total. `start` is inside `priorStart`, so this one test
            // bounds both.
            guard sighting.at >= priorStart else { continue }
            let code = sighting.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let amount = sighting.amount, let code, !code.isEmpty else {
                if sighting.at >= start { unpriced += 1 }
                continue
            }
            if sighting.at >= start {
                var bucket = buckets[code] ?? (total: 0, spends: 0, newest: sighting.at)
                bucket.total += amount
                bucket.spends += 1
                if sighting.at > bucket.newest { bucket.newest = sighting.at }
                buckets[code] = bucket
            } else {
                priors[code, default: 0] += amount
            }
        }

        // A prior total is only reported when the room's own history reaches
        // back far enough to have observed that window — see the type note.
        let covered = knowsPriorWindow(oldest: oldest, now: now, calendar: calendar)
        let currencies = buckets.map { code, bucket in
            Currency(code: code, total: bucket.total, spends: bucket.spends,
                     prior: covered ? (priors[code] ?? 0) : nil,
                     newest: bucket.newest)
        }
        let ranked = ordered(currencies)
        // The strip follows whichever currency the HEADLINE states, so the two
        // can never be about different money on one card.
        let strip = history(monthly: monthly, code: ranked.first?.code, calendar: calendar)
        return GnosisPayRoom(currencies: ranked, unpriced: unpriced,
                             allTime: sightings.count, oldest: oldest, newest: newest,
                             months: strip.months, monthsHidden: strip.hidden,
                             monthsOtherCurrency: strip.otherCurrency)
    }

    /// The lead currency's trailing months, oldest first, plus what the cap and
    /// the single-currency choice left out.
    ///
    /// Below two months it returns nothing at all: a one-column history is not
    /// a history, and drawing one lone bar invites reading its height as a
    /// level rather than as a comparison.
    static func history(monthly: [String: [Int: (total: Double, spends: Int)]],
                        code: String?,
                        calendar: Calendar = .current)
        -> (months: [Month], hidden: Int, otherCurrency: Int) {
        guard let code, let cells = monthly[code], cells.count >= 2 else {
            return ([], 0, 0)
        }
        let keys = cells.keys.sorted()
        // The NEWEST `monthCap`, kept in ascending order so the strip reads
        // left to right as time.
        let drawn = Array(keys.suffix(monthCap))
        let months: [Month] = drawn.compactMap { key in
            guard let cell = cells[key], let start = monthStart(key: key, calendar: calendar)
            else { return nil }
            return Month(key: key, start: start, total: cell.total, spends: cell.spends)
        }
        guard let first = drawn.first, let last = drawn.last else { return ([], 0, 0) }
        // Spends in another currency that fall inside the drawn span — the ones
        // this card's single-currency choice cannot show. Counted, not hidden.
        var other = 0
        for (otherCode, otherCells) in monthly where otherCode != code {
            for (key, cell) in otherCells where key >= first && key <= last {
                other += cell.spends
            }
        }
        return (months, keys.count - drawn.count, other)
    }

    /// A month as one sortable integer — year × 12 + (month − 1). Stable across
    /// year boundaries, which a bare month number is not.
    static func monthKey(_ date: Date, calendar: Calendar = .current) -> Int? {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return nil }
        return year * 12 + (month - 1)
    }

    /// The first instant of the month a key names.
    static func monthStart(key: Int, calendar: Calendar = .current) -> Date? {
        var parts = DateComponents()
        parts.year = key / 12
        parts.month = key % 12 + 1
        parts.day = 1
        return calendar.date(from: parts)
    }

    /// A month's column height as a share of the biggest month drawn, 0…1.
    ///
    /// Against the biggest DRAWN month rather than against any all-time high:
    /// the strip is a comparison among the months it shows, and scaling to a
    /// month that is off the end of it would flatten every visible column
    /// against something nobody can see.
    static func monthShare(total: Double, of top: Double) -> Double {
        guard top > 0 else { return 0 }
        return min(max(total / top, 0), 1)
    }

    /// "Mar" — the strip's tick. Abbreviated because twelve of them share a
    /// card's width; the year is carried by the strip's own caption, not
    /// repeated on every column.
    static func monthLabel(_ start: Date, locale: Locale = .current) -> String {
        start.formatted(.dateTime.month(.abbreviated).locale(locale))
    }

    /// What the strip is: which currency, how many months, and what that choice
    /// left out. Nil when there is no strip to caption.
    static func historyNote(_ room: GnosisPayRoom) -> String? {
        guard !room.months.isEmpty, let code = room.lead?.code else { return nil }
        var line = String(localized: "\(code) · \(room.months.count) months")
        if room.monthsHidden > 0 {
            line += " · " + String(localized: "\(room.monthsHidden) earlier not drawn")
        }
        if room.monthsOtherCurrency > 0 {
            line += " · " + String(localized: "\(room.monthsOtherCurrency) in other currencies")
        }
        return line
    }

    /// The start of the window `back` windows ago — 1 is the current one.
    static func windowStart(_ now: Date, back: Int, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -windowDays * back, to: day) ?? day
    }

    /// Whether the room has been watching long enough for "the previous 30
    /// days" to be an observation rather than an absence of data.
    ///
    /// The bar is that the oldest spend we hold predates the prior window's
    /// START. A spend landed inside the prior window proves only that the card
    /// existed by then; it says nothing about the days before it, and the
    /// backfill boundary is exactly where a first sync stops.
    static func knowsPriorWindow(oldest: Date?, now: Date,
                                 calendar: Calendar = .current) -> Bool {
        guard let oldest else { return false }
        return oldest <= windowStart(now, back: 2, calendar: calendar)
    }

    // MARK: - Ranking

    /// Spend COUNT, then recency, then code — TOTAL, so two composes over the
    /// same data can never disagree.
    ///
    /// Never by amount. Ranking currencies by total would compare 400 EUR
    /// against 380 GBP as if the numbers were on one scale, which is the
    /// cross-currency sum this file refuses, wearing a sort instead of a plus.
    static func ordered(_ currencies: [Currency]) -> [Currency] {
        currencies.sorted { a, b in
            if a.spends != b.spends { return a.spends > b.spends }
            if a.newest != b.newest { return a.newest > b.newest }
            return a.code < b.code
        }
    }

    // MARK: - The change

    /// This window against the one before it, as a fraction — +0.25 is a
    /// quarter more. Nil when the prior window is unknown OR was zero.
    ///
    /// A zero prior does not divide, and it does not become 1 either: coming
    /// back from nothing has no percentage, and printing "+100%" for it is the
    /// arithmetic accident `PostHogRoom` guards against in its own week.
    static func delta(_ currency: Currency) -> Double? {
        guard let prior = currency.prior, prior > 0 else { return nil }
        return (currency.total - prior) / prior
    }

    /// Whether a change is big enough to be worth a word. Card spending is
    /// lumpy — one weekly shop lands differently in two windows — so a small
    /// move is noise, and a card that announces noise is one people stop
    /// believing.
    static let deltaFloor = 0.10

    static func deltaLabel(_ currency: Currency) -> String? {
        guard let delta = delta(currency), abs(delta) >= deltaFloor else { return nil }
        let percent = Int((abs(delta) * 100).rounded())
        return delta > 0 ? String(localized: "\(percent)% more than the 30 days before")
                         : String(localized: "\(percent)% less than the 30 days before")
    }

    // MARK: - The bar

    /// A currency's share of the window's spends BY COUNT, 0…1 — the only
    /// drawing on this card. By count, not by amount, for `ordered`'s reason:
    /// the amounts are in different currencies and drawing them on one axis
    /// would state a conversion nobody made.
    static func share(spends: Int, of top: Int) -> Double {
        guard top > 0 else { return 0 }
        return min(max(Double(spends) / Double(top), 0), 1)
    }

    // MARK: - Days

    static func days(from now: Date, to later: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - Words

    /// The locale is a PARAMETER so the harness can pin one; nothing in the app
    /// passes it. A currency string built against the device locale is right
    /// for a person and untestable without this.
    static func money(_ amount: Double, code: String, locale: Locale = .current) -> String {
        amount.formatted(.currency(code: code).locale(locale))
    }

    static func spendsLabel(_ count: Int) -> String {
        count == 1 ? String(localized: "1 spend") : String(localized: "\(count) spends")
    }

    /// The line beside a currency row: the money, then how many times.
    static func currencyLine(_ currency: Currency, locale: Locale = .current) -> String {
        money(currency.total, code: currency.code, locale: locale)
            + " · " + spendsLabel(currency.spends)
    }

    /// The one line at the top of the card — the lead currency's money for the
    /// window, which is the everyday reading and the reason to open the room.
    ///
    /// There is no trouble rung here, unlike `StripeRoom` and `CursorRoom`: a
    /// card spend cannot go wrong in a way this bridge can see. It settled or
    /// it is not on chain.
    static func headline(_ room: GnosisPayRoom, locale: Locale = .current) -> String {
        guard let lead = room.lead else {
            // A quiet window on a room with real history — the honest reading,
            // and the one a list of old rows never states.
            guard room.allTime > 0 else { return String(localized: "Nothing on your card yet") }
            return String(localized: "Nothing spent in the last \(windowDays) days")
        }
        if room.currencies.count > 1 {
            let others = room.currencies.count - 1
            let money = money(lead.total, code: lead.code, locale: locale)
            return others == 1
                ? String(localized: "\(money) in \(lead.code), plus another currency")
                : String(localized: "\(money) in \(lead.code), plus \(others) other currencies")
        }
        return String(localized: "\(money(lead.total, code: lead.code, locale: locale)) on your card in \(windowDays) days")
    }

    /// The line under it. Never a restatement: the headline carries the money,
    /// so this carries how it MOVED — against the window before, when that is
    /// knowable, and otherwise how often the card was used.
    static func note(_ room: GnosisPayRoom) -> String {
        guard let lead = room.lead else {
            guard room.allTime > 0 else { return String(localized: "No settlements have landed") }
            return String(localized: "\(spendsLabel(room.allTime)) before that")
        }
        if let change = deltaLabel(lead) { return change }
        if lead.prior == nil {
            // Said out loud rather than left blank: "no comparison" and "no
            // change" look identical on a card, and only one of them is a
            // measurement.
            return String(localized: "\(spendsLabel(lead.spends)) · not watching long enough to compare")
        }
        return String(localized: "\(spendsLabel(lead.spends)) · about the same as the 30 days before")
    }

    /// The quiet line at the foot: spends we could not price, and how long the
    /// card has been unused. The unpriced clause is not politeness — such a
    /// spend is money missing from the total directly above it.
    static func footnote(_ room: GnosisPayRoom, now: Date = .now) -> String? {
        var parts: [String] = []
        if room.unpriced > 0 {
            parts.append(room.unpriced == 1
                         ? String(localized: "1 spend has no readable amount")
                         : String(localized: "\(room.unpriced) spends have no readable amount"))
        }
        if let idle = idleNote(newest: room.newest, now: now) { parts.append(idle) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "unused for 40 days" — only once the gap outruns the window itself, so
    /// it can never contradict a headline that just reported spending inside
    /// it.
    static func idleNote(newest: Date?, now: Date = .now) -> String? {
        guard let newest else { return nil }
        let days = days(from: newest, to: now)
        guard days > windowDays else { return nil }
        return String(localized: "unused for \(days) days")
    }
}
