import Foundation

/// THE POLAR ROOM'S HEAD (2026-08-30) — what your recurring revenue is doing,
/// and what needs you by when. `StripeRoom`'s exact shape, adapted for a
/// subscription-first Merchant of Record rather than a cash-balance one.
///
/// ## It spends nothing
///
/// Every fact here is already on the device: rows the bridge landed, their own
/// `dueAt`, and the reading snapshot `PolarState` keeps behind §216's
/// ten-minute window. No request, no new `Thing` field, no CloudKit deploy —
/// `StripeRoom`'s own contract, for the same reason.
///
/// ## MRR in place of a balance
///
/// Stripe reads a cash balance because Stripe settles cash. Polar is
/// subscription-first, so the figure that answers "how is this doing right
/// now" is Monthly Recurring Revenue, not a bank balance Polar pays out on
/// its own schedule — the same substitution `StripeState`'s doc makes
/// explicit is a choice, not an oversight.
///
/// ## What it may NOT draw
///
/// `StripeRoom`'s ban on a revenue curve applies here for a stronger reason:
/// this bridge doesn't even buy a payment-timestamp pulse the way Stripe's
/// `chargePulse` does, so there is no series to discard, only ever a single
/// point-in-time reading. A curve would have to be invented from the landed
/// rows, which are a biased sample of exactly what went WRONG — Stripe's own
/// reasoning, unchanged.
///
/// Foundation-only by design so `scripts/polar-selftest.sh` can compile it
/// WHOLE and unmodified.
struct PolarRoom: Equatable {

    /// One dispute with an evidence deadline — the only shape this bridge
    /// stamps a `dueAt` on (Polar's `RefundDispute.evidence_due_by`, nested on
    /// a refund; see `PolarBridge`'s type doc).
    struct Item: Identifiable, Equatable {
        let id: String
        let name: String
        let due: Date
        /// Whole calendar days from today. Negative is overdue.
        let days: Int
    }

    /// "$482.00" — nil when never read, which must never render as zero
    /// (Stripe's `availableText` rule).
    let mrr: String?
    let activeSubscriptions: Int?
    let asOf: Date?
    /// Soonest first, overdue leading — CAPPED to what the card draws.
    let items: [Item]
    /// How many deadlines are in the window IN TOTAL, drawn or not —
    /// `StripeRoom.total`'s exact reason: the headline needs the uncapped
    /// count so it can't disagree with the coverage note beneath it.
    let total: Int

    var readingRead: Bool { asOf != nil }

    /// Nothing to say at all. Keyed on `readingRead`, not on `mrr`, for
    /// `StripeRoom.isEmpty`'s exact reason: a genuinely zero MRR (no active
    /// subscribers, only one-time sales) is a real fact, not an absence.
    var isEmpty: Bool { !readingRead && items.isEmpty }

    var lead: Item? { items.first }
    var overdue: Item? { items.first { $0.days < 0 } }

    // MARK: - Days (Stripe's exact arithmetic)

    static func days(from now: Date, to due: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: due)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - The rail

    static func span(days: [Int]) -> Int {
        RoomRunway.span(days: days)
    }

    static func position(days: Int, span: Int) -> Double {
        RoomRunway.position(days: days, span: span)
    }

    static func spanLabel(span: Int) -> String {
        RoomRunway.spanLabel(span: span)
    }

    // MARK: - Words

    static func value(days: Int) -> String {
        if days < 0 { return String(localized: "overdue") }
        if days == 0 { return String(localized: "today") }
        if days == 1 { return String(localized: "tomorrow") }
        return String(localized: "\(days) days")
    }

    /// The chip, for the one fact that changes what you'd do today.
    static func chip(_ item: Item) -> String {
        item.days < 0 ? String(localized: "Missed") : String(localized: "Needs you")
    }

    /// The card's one sentence. Ranking: an OVERDUE evidence window leads
    /// everything (it is actively costing money); then an upcoming deadline;
    /// then MRR, the everyday case and the reason most people open the room.
    static func headline(_ room: PolarRoom) -> String {
        if let overdue = room.overdue {
            return overdue.days == -1
                ? String(localized: "Evidence was due yesterday")
                : String(localized: "Evidence was due \(-overdue.days) days ago")
        }
        if let lead = room.lead {
            if room.total > 1 {
                return String(localized: "\(room.total) deadlines ahead")
            }
            return String(localized: "Evidence due \(value(days: lead.days))")
        }
        if let mrr = room.mrr {
            return String(localized: "\(mrr)/mo recurring")
        }
        if room.readingRead { return String(localized: "No recurring revenue right now") }
        return String(localized: "Nothing needs you")
    }

    /// The line under it — never a restatement of the headline: when a
    /// deadline leads, this carries the revenue figure, so one glance always
    /// gets both.
    static func note(_ room: PolarRoom) -> String {
        if room.lead != nil {
            guard room.readingRead else { return String(localized: "Recurring revenue not read yet") }
            return mrrClause(room) ?? String(localized: "No recurring revenue right now")
        }
        // MRR already leads the headline here, so the note gives a
        // DIFFERENT fact — active subscribers — the same "never a
        // restatement" rule Stripe's balance/in-flight split follows.
        return subscriberClause(room) ?? String(localized: "Nothing needs you")
    }

    /// "$482.00/mo" — or nil. Used only when a DEADLINE already leads the
    /// headline, so the note's money figure is never the same fact twice.
    private static func mrrClause(_ room: PolarRoom) -> String? {
        guard let mrr = room.mrr else { return nil }
        return String(localized: "\(mrr)/mo recurring")
    }

    /// "1,204 active subscribers" — or nil.
    private static func subscriberClause(_ room: PolarRoom) -> String? {
        guard let active = room.activeSubscriptions, active > 0 else { return nil }
        return String(localized: "\(active) active \(active == 1 ? "subscriber" : "subscribers")")
    }

    static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }

    /// "Read 3h ago" — stated only once the snapshot is old enough that
    /// someone might act on a number that has moved (Stripe's exact rule).
    static func staleNote(asOf: Date?, now: Date = .now) -> String? {
        guard let asOf else { return nil }
        let elapsed = now.timeIntervalSince(asOf)
        guard elapsed >= 3600 else { return nil }
        let hours = Int(elapsed / 3600)
        if hours >= 24 {
            let days = hours / 24
            return days == 1
                ? String(localized: "Read yesterday")
                : String(localized: "Read \(days) days ago")
        }
        return String(localized: "Read \(hours)h ago")
    }

    static func coverageNote(_ room: PolarRoom) -> String? {
        guard room.total > room.items.count else { return nil }
        return String(localized: "\(room.total - room.items.count) more further out — not drawn")
    }
}
