import Foundation

/// THE STRIPE ROOM'S HEAD (2026-08-04, prd §298) — what your money is doing,
/// and what needs you by when.
///
/// The room landed five real shapes (disputes, payouts, churn, dunning,
/// silence) and led with a plain list of them, which is the §247 gap in its
/// purest form: a room holding money facts, drawing nothing. This is the head
/// it was missing.
///
/// ## It spends nothing
///
/// Every fact here is already on the device: rows the bridge landed, their own
/// `dueAt`, and the balance snapshot `StripeState` keeps behind §216's
/// ten-minute window. No request, no new `Thing` field, no CloudKit deploy —
/// the `CloudflareRunwaySource` contract, and for the same reason: a head that
/// costs a call is a head that can fail, and a room's lede must not be able to
/// fail differently from the rows beneath it.
///
/// ## What it may NOT draw, and why the list matters
///
/// The obvious card here is a revenue curve, and it cannot be built honestly.
/// `StripeFetch.chargePulse` buys the last hundred `charge.succeeded`
/// timestamps every balance window, `StripeSilence` reduces them to a verdict,
/// and **the array is then discarded** — nothing persists it, and neither
/// `typicalGap` nor `since` survives. So there is no payment-rate sparkline
/// available at zero cost, and inventing one from the landed rows would be
/// worse than none: an individual charge is never a row here by §250's ruling,
/// so the rows are a biased sample of exactly the events that went WRONG.
/// A curve drawn off disputes and failures would read as "your revenue" while
/// plotting your problems.
///
/// Amounts are equally out of reach: they exist only as formatted substrings
/// inside each row's title (`Thing` carries no numeric field for them —
/// `transferAmount` is Wallet's), and re-parsing prose back into arithmetic is
/// the thing `Thing`'s own doc argues against. So this card states money it
/// reads from a structured source and counts events it can see, and never
/// crosses between the two.
///
/// ## Currencies are never summed
///
/// `StripeState.availableText()` joins per-currency with " · " and this card
/// prints what it hands over. A single total across currencies is an exchange
/// rate this app doesn't have and a claim it can't make (`StripeScreen`'s own
/// standing rule).
///
/// Foundation-only by design so `scripts/stripe-room-selftest.sh` can compile
/// it WHOLE and unmodified — the strongest form of "the harness ran the shipped
/// logic". The scale arithmetic below is deliberately NOT shared with
/// `CloudflareRunway`'s: that file is compiled whole by its own harness too,
/// and a shared dependency would break both. Twenty lines of duplicated
/// interpolation is the price of two independently provable files, which this
/// codebase has chosen before.
struct StripeRoom: Equatable {

    /// One thing with a clock on it — a dispute's evidence deadline or an
    /// invoice's next retry. These are the ONLY two shapes Stripe stamps a
    /// `dueAt` on, and both are dates Stripe itself published rather than
    /// dates we computed.
    struct Item: Identifiable, Equatable {
        /// The row's `sourceRef`, so the card can hand back something the
        /// section can look up without the card ever holding a `Thing`.
        let id: String
        let name: String
        let due: Date
        /// Whole calendar days from today. Negative is overdue.
        let days: Int
        /// A dispute's evidence window, versus a payment that will retry.
        /// The two carry different consequences and so read differently.
        let dispute: Bool
    }

    /// Per-currency, pre-joined, never summed. nil when nothing has been read
    /// yet — which is NOT zero, and must never render as zero.
    let available: String?
    let pending: String?
    /// Stripe's own `arrival_date` for money already in flight. Never computed.
    let arrivesAt: Date?
    /// When the balance snapshot was taken, for the staleness clause.
    let asOf: Date?
    /// Soonest first, overdue leading — CAPPED to what the card draws.
    let items: [Item]
    /// How many deadlines are in the window IN TOTAL, drawn or not.
    ///
    /// Carried on the room rather than passed beside it because the HEADLINE
    /// needs it: "4 deadlines ahead" over a note reading "5 more further out"
    /// is a card disagreeing with itself, which is what counting `items` gave.
    /// `CloudflareRunway.headline` counts its own items safely only because
    /// that source has no row cap.
    let total: Int
    /// The account is currently in a reported payment outage
    /// (`StripeState.Balance.silent`, cleared the moment payments resume).
    let stopped: Bool

    /// Whether a balance has ever been read on this device. NOT the same as
    /// having money: a swept account really does hold zero available, and
    /// `StripeState.availableText()` returns nil for that too (it filters zero
    /// buckets). Read-and-zero and never-read are different facts and only one
    /// of them is an apology.
    var balanceRead: Bool { asOf != nil }

    /// Nothing to say at all — no balance read, no deadline, no outage. The
    /// caller draws no card rather than an empty one.
    ///
    /// Keyed on `balanceRead`, not on `available`: an account that sweeps its
    /// payouts daily sits at zero available every day, and the card's own
    /// promise is that a quiet account gets the same body rather than
    /// disappearing.
    var isEmpty: Bool { !balanceRead && items.isEmpty && !stopped }

    /// The deadline that leads, if any.
    var lead: Item? { items.first }
    var overdue: Item? { items.first { $0.days < 0 } }

    // MARK: - Days

    /// Whole CALENDAR days from today — not `timeIntervalSince / 86400`.
    /// "Evidence due Aug 12" means the day, so an 11pm read on Aug 11 is one
    /// day out, not zero-point-oh-four. Negative is overdue.
    static func days(from now: Date, to due: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: due)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - The rail

    /// How far ahead the axis reaches. Rounded UP to a familiar horizon so the
    /// axis label reads as a period rather than as whatever the furthest
    /// deadline happens to be — and floored at a week, because a rail spanning
    /// two days puts a "3 days" mark off its own end.
    static func span(days: [Int]) -> Int {
        let furthest = days.max() ?? 0
        for bound in [7, 14, 30, 60, 90] where furthest <= bound { return bound }
        return furthest
    }

    /// Where a deadline sits on the axis, 0…1.
    ///
    /// Overdue pins to zero rather than running off the left edge, where it
    /// would simply vanish — the one deadline you most need to see is the one
    /// you have already missed.
    static func position(days: Int, span: Int) -> Double {
        guard span > 0 else { return 0 }
        return min(max(Double(days) / Double(span), 0), 1)
    }

    static func spanLabel(span: Int) -> String {
        span % 30 == 0 && span >= 30
            ? String(localized: "\(span / 30) mo")
            : String(localized: "\(span) days")
    }

    // MARK: - Words

    /// The row's own value — what a glance down the right edge reads.
    static func value(days: Int) -> String {
        if days < 0 { return String(localized: "overdue") }
        if days == 0 { return String(localized: "today") }
        if days == 1 { return String(localized: "tomorrow") }
        return String(localized: "\(days) days")
    }

    /// "Evidence" / "Retry" — what KIND of clock this is, since the two have
    /// opposite consequences: evidence is a window you can lose by missing,
    /// a retry is something Stripe will do for you.
    static func kindLine(_ item: Item) -> String {
        item.dispute ? String(localized: "Evidence window")
                     : String(localized: "Stripe retries automatically")
    }

    /// The chip, and only for the one fact that changes what you'd do today.
    /// A retry needs nothing from you and so wears nothing.
    static func chip(_ item: Item) -> String? {
        guard item.dispute else { return nil }
        return item.days < 0 ? String(localized: "MISSED") : String(localized: "NEEDS YOU")
    }

    /// The card's one sentence.
    ///
    /// The ranking is a judgement and worth stating: an OVERDUE evidence
    /// window leads everything, because it is the only state on this card that
    /// is actively costing money; a STOPPED account comes next, because the
    /// business having quietly halted outranks any single dispute; then
    /// upcoming deadlines; then the balance, which is the everyday case and the
    /// reason most people open the room at all.
    static func headline(_ room: StripeRoom) -> String {
        if let overdue = room.overdue {
            return overdue.days == -1
                ? String(localized: "Evidence was due yesterday")
                : String(localized: "Evidence was due \(-overdue.days) days ago")
        }
        if room.stopped { return String(localized: "Payments have stopped") }
        if let lead = room.lead {
            // The TOTAL in the window, never the drawn count — see `total`.
            if room.total > 1 {
                return String(localized: "\(room.total) deadlines ahead")
            }
            return lead.dispute
                ? String(localized: "Evidence due \(value(days: lead.days))")
                : String(localized: "A payment retries \(value(days: lead.days))")
        }
        if let available = room.available {
            return String(localized: "\(available) available")
        }
        // Read, and genuinely zero — a swept account, which is a normal way to
        // run a business and not an absence of information.
        if room.balanceRead { return String(localized: "Nothing available right now") }
        return String(localized: "Nothing needs you")
    }

    /// The line under it. Never a restatement of the headline: when money
    /// leads, this carries what's in flight; when a deadline leads, it carries
    /// the money, so one glance always gets both.
    static func note(_ room: StripeRoom, now: Date = .now) -> String {
        if room.lead != nil || room.stopped {
            if let available = room.available {
                return String(localized: "\(available) available")
            }
            // Only an unread balance apologises. A read balance of zero is a
            // fact, and says what's still moving instead.
            guard room.balanceRead else { return String(localized: "Balance not read yet") }
            return inFlight(room) ?? String(localized: "Nothing available right now")
        }
        // Money leads — say what's still moving.
        return inFlight(room) ?? String(localized: "Nothing needs you")
    }

    /// "$310.00 pending · arrives Aug 12" — what hasn't landed yet, or nil.
    private static func inFlight(_ room: StripeRoom) -> String? {
        var parts: [String] = []
        if let pending = room.pending {
            parts.append(String(localized: "\(pending) pending"))
        }
        if let arrivesAt = room.arrivesAt {
            parts.append(String(localized: "arrives \(dayLabel(arrivesAt))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Month and day, never a bare weekday — the Aerodrome date-format bug
    /// (2026-07-30): a weekday alone is ambiguous for a date days out.
    static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }

    /// "Balance as of 3h ago" — stated only once the snapshot is old enough
    /// that someone might act on a number that has moved. Under the refresh
    /// window it says nothing, because a fresh number needs no apology.
    static func staleNote(asOf: Date?, now: Date = .now) -> String? {
        guard let asOf else { return nil }
        let elapsed = now.timeIntervalSince(asOf)
        guard elapsed >= 3600 else { return nil }
        let hours = Int(elapsed / 3600)
        if hours >= 24 {
            let days = hours / 24
            return days == 1
                ? String(localized: "Balance as of yesterday")
                : String(localized: "Balance as of \(days) days ago")
        }
        return String(localized: "Balance as of \(hours)h ago")
    }

    /// What the card can't see. An outage is stated in the body, not here —
    /// this is only about coverage.
    static func coverageNote(_ room: StripeRoom) -> String? {
        guard room.total > room.items.count else { return nil }
        return String(localized: "\(room.total - room.items.count) more further out — not drawn")
    }
}
