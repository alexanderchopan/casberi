import Foundation

/// THE ADDRESS CARD AS ONE DATED SPINE (2026-08-22, prd §446).
///
/// ## Why the card had to collapse
///
/// `AddressCard` drew six blocks — the identity, the look-alike condition, the
/// lede, the wallets it reached, the record, and a details list — and five of
/// them were **the same shape wearing five treatments**: a dated fact about one
/// address. Three consequences, each visible only once you say it out loud:
///
///  1. **The lede RANKED by choosing, not by demoting.** It showed the standing
///     approval exposure *or* the relationship count. An address that can move
///     your tokens right now *and* has twelve transactions with you showed only
///     the first; the second became a bare section header far down the page.
///     On a spine there is nothing to rank — the standing permission is simply
///     the newest event in a list both belong to.
///  2. **"Which of your wallets" made you hold two lists in your head.** Which
///     wallet dealt with this address is a PER-EVENT fact, so a chip strip
///     above the record asked you to join it to the rows yourself. It rides
///     each event's own caption now ("Aug 18 · Main").
///  3. **The naming date sat in a settings-shaped row** at the foot, drawn at
///     the weight the security notice above it wears. It is the ROOT of the
///     relationship and belongs at the bottom of the spine, which is where a
///     timeline puts its oldest entry.
///
/// ## What lives here and what deliberately does not
///
/// This type decides **which events exist, in what order, and what each one
/// says**. It draws nothing, formats no money and reads no store. Every failure
/// it exists to catch renders as a perfectly ordinary card:
///
///   · a fold row saying "9 more" over a list that hid eight, so "See all 12"
///     leads to a screen with a different number on it
///   · the fold's span read off the SHOWN rows rather than the hidden ones,
///     which prints the two dates already on screen and says nothing
///   · a root event dating an address to the day you opened its card, because
///     the entry was invented for the trip and was never in your book
///   · an unnamed address whose root claims you named it
///   · a month rendered in the system zone while the year that chose it was
///     compared in the calendar's — last year's month printed as this one
///     (`AddressBookShape.lastPhrase`'s own bug, one file over)
///   · a grant that could not be priced folded into the figure as a zero
///
/// Foundation-only BY DESIGN, so `scripts/address-spine-selftest.sh` compiles
/// it WHOLE and unmodified. Two things are therefore PARAMETERS rather than
/// reads: the clock (`now`), and the money formatter — which must stay at the
/// call site so `hide-balances-audit.py` can see the §374 gate, exactly the
/// reason `AddressHistoryRow` takes `hidden`/`mask` rather than reading
/// `BalancePrivacy.shared`.
enum AddressSpine {

    // MARK: - Input

    /// One landed row, already reduced to what a spine event draws.
    ///
    /// `walletName` is which of YOUR wallets was on the other side, resolved
    /// per row rather than aggregated into a strip. nil when the row is not a
    /// `Wallet` transfer (a Peer fill and a Privacy Pools deposit stamp
    /// `walletAddress` with the SUBJECT's own address — see
    /// `AddressActivity.key`), when the owner is the subject itself (a
    /// self-transfer, which `walletLegs` has always dropped), or when the
    /// owner is not a wallet you watch.
    struct Transfer: Equatable, Identifiable {
        var id: String
        var date: Date
        /// `AddressHistoryRow.Parts.lead` — the verb, or a whole title for a
        /// row that could not be split.
        var lead: String
        /// `AddressHistoryRow.Parts.amount` — nil for a row with no stamped
        /// transfer, which states nothing on the right but its date.
        var amount: String?
        var walletName: String?
        /// This row's position in the WHOLE history, so the rename cascade
        /// still sweeps in corpus order after the preview has been sliced off
        /// the front. Taken from the source array rather than from the event
        /// index, because the fold and the root are not renamed by anything
        /// and must not consume a beat of the sweep.
        var cascadeStep: Int

        init(id: String, date: Date, lead: String,
             amount: String? = nil, walletName: String? = nil,
             cascadeStep: Int = 0) {
            self.id = id; self.date = date; self.lead = lead
            self.amount = amount; self.walletName = walletName
            self.cascadeStep = cascadeStep
        }
    }

    /// What the standing permission at the head of the spine says.
    struct Standing: Equatable {
        /// The exact dollar figure, ALREADY gated. nil when nothing in the
        /// exposure could be priced — a `$0` over unpriceable grants is the
        /// "never 0 standing in for unknown" rule §292 already keeps.
        var figure: String?
        /// Every grant in one sentence, priced and unpriced alike.
        var caption: String
    }

    /// How the oldest event reads. Three cases and the distinction is load
    /// bearing: an address reached through a door (the connections card's
    /// nodes became doors, §295 follow-up) is not in your book at all, and its
    /// `addedAt` would print "named today" about an address nobody ever named.
    enum Root: Equatable {
        /// In your book, under a name somebody chose.
        case named(at: Date, provenance: String?)
        /// In your book under a placeholder the app minted, or not in it at
        /// all — so the oldest thing we honestly know is that it turned up.
        case appeared(at: Date, walletName: String?)
        /// In your book, never named, and with no history to point at — so
        /// the only honest root is that it is here and unnamed. Distinct from
        /// `.appeared`, which claims a transfer happened.
        case unnamed(at: Date)
        /// Nothing to say: no history, and not in your book.
        case none
    }

    // MARK: - Output

    enum Event: Equatable, Identifiable {
        case standing(Standing)
        case transfer(Transfer)
        /// The rows the preview does not show, and the door to all of them.
        case fold(line: String, total: Int)
        case root(eyebrow: String, sentence: String)

        var id: String {
            switch self {
            case .standing:                  return "standing"
            case .transfer(let t):           return "t:" + t.id
            case .fold:                      return "fold"
            case .root:                      return "root"
            }
        }

        /// Whether this event ends the spine — the rail draws a dot and no
        /// trailing line. Asked of the ARRAY rather than of the case, because
        /// which event is last depends on what was assembled.
        var isRoot: Bool { if case .root = self { return true }; return false }
    }

    /// How many transfers stand above the fold.
    ///
    /// Three, and it is a measured fit rather than a round number: with a
    /// standing event present, three transfers plus the fold plus the root is
    /// what clears 844pt under the 76pt face. It is deliberately NOT raised
    /// when the standing event is absent — a preview whose length changes with
    /// an unrelated condition makes "See all 12" mean two different amounts of
    /// hidden history on two cards.
    static let preview = 3

    /// The whole spine, newest first.
    ///
    /// `transfers` must already be newest-first and already sliced to nothing
    /// (the caller passes the WHOLE history; this takes the preview off the
    /// front so the fold can describe what it left behind). `total` is the
    /// complete count, which is what the door promises to show.
    static func events(standing: Standing?,
                       transfers: [Transfer],
                       total: Int,
                       root: Root,
                       now: Date = .now,
                       calendar: Calendar = .current) -> [Event] {
        var events: [Event] = []
        if let standing { events.append(.standing(standing)) }

        let shown = Array(transfers.prefix(preview))
        events.append(contentsOf: shown.map(Event.transfer))

        // The fold describes THE ROWS IT HID, never the rows above it. Read
        // off the shown ones it would print the two dates already on screen,
        // which is a line that costs a row and says nothing.
        let hidden = transfers.dropFirst(preview)
        if !hidden.isEmpty {
            events.append(.fold(line: foldLine(hidden: Array(hidden), now: now,
                                               calendar: calendar),
                                total: total))
        }

        switch root {
        case .named(let at, let provenance):
            events.append(.root(eyebrow: eyebrow(at, now: now, calendar: calendar),
                                sentence: namedSentence(provenance: provenance)))
        case .appeared(let at, let walletName):
            let mark = eyebrow(at, now: now, calendar: calendar)
            events.append(.root(eyebrow: mark + " · " + String(localized: "First"),
                                sentence: appearedSentence(walletName: walletName)))
        case .unnamed(let at):
            events.append(.root(eyebrow: eyebrow(at, now: now, calendar: calendar),
                                sentence: String(localized: "You have not named this address")))
        case .none:
            break
        }
        return events
    }

    // MARK: - The standing permission

    /// Every live grant in one sentence.
    ///
    /// Priced and unpriced alike, because an unpriceable grant is still a
    /// permission and omitting it would leave the figure looking complete —
    /// §292's own `unpricedNote` rule, said inline instead of as a footnote.
    ///
    /// `stateLine` is the grant's own (never re-derived here), so this card and
    /// the approvals card can never state the same grant two ways.
    ///
    /// The chain is NOT named. `WalletApprovalExposure.Grant` does not carry
    /// one, and "on Base" invented from nothing is the fake status §83 bans on
    /// the screen where believing it is most expensive.
    static func standingCaption(_ grants: [(stateLine: String, granted: Date?, priced: Bool)],
                                now: Date = .now,
                                calendar: Calendar = .current) -> String {
        let shown = grants.prefix(captionCap)
        var clauses = shown.map { grant -> String in
            if !grant.priced { return grant.stateLine + ", " + String(localized: "not priced") }
            guard let granted = grant.granted else { return grant.stateLine }
            let day = dayText(granted, now: now, calendar: calendar)
            return grant.stateLine + ", " + String(localized: "granted \(day)")
        }
        let rest = grants.count - shown.count
        if rest > 0 { clauses.append(String(localized: "^[\(rest) more grant](inflect: true)")) }
        return clauses.joined(separator: ". ") + "."
    }

    /// How many grants the sentence names before it starts counting. A spender
    /// holding nine approvals would otherwise write a paragraph at
    /// `callout15` under the figure it is explaining.
    static let captionCap = 3

    // MARK: - The fold

    /// "9 more, Jul – Mar" — how much history the preview hid, and how far
    /// back it runs.
    ///
    /// The span carries YEARS only when the two ends fall in different ones.
    /// Inside one year "Jul – Mar" is unambiguous and the year is noise; across
    /// two, "Jul – Mar" reads as seven months when it is nineteen.
    static func foldLine(hidden: [Transfer], now: Date = .now,
                         calendar: Calendar = .current) -> String {
        let count = hidden.count
        let more = String(localized: "\(count) more")
        let dates = hidden.map(\.date)
        guard let newest = dates.max(), let oldest = dates.min() else { return more }
        let sameYear = calendar.component(.year, from: newest)
            == calendar.component(.year, from: oldest)
        let a = monthText(newest, withYear: !sameYear, calendar: calendar)
        let b = monthText(oldest, withYear: !sameYear, calendar: calendar)
        // One month for the whole hidden run is one fact, not a range: "Jul –
        // Jul" reads as a rendering fault.
        return a == b ? "\(more), \(a)" : "\(more), \(a) – \(b)"
    }

    // MARK: - The root

    private static func namedSentence(provenance: String?) -> String {
        guard let provenance, !provenance.isEmpty else {
            return String(localized: "You named this address")
        }
        return String(localized: "You added this from \(provenance) and named it")
    }

    private static func appearedSentence(walletName: String?) -> String {
        guard let walletName, !walletName.isEmpty else {
            return String(localized: "They appeared in a transfer. You have not named them.")
        }
        return String(localized: "They appeared in a transfer to \(walletName). You have not named them.")
    }

    // MARK: - The address, in chunks

    /// Forty-two characters, in groups of four (prd §446).
    ///
    /// **The `0x` rides the first group** rather than standing alone: it is not
    /// part of the address's information, and a two-character orphan at the
    /// head throws every subsequent group out of alignment with the same
    /// address printed anywhere else. So an EVM address chunks as
    /// `0x9a2E 4c81 … 44b1` — ten groups, the first six characters wide.
    ///
    /// Base58 (Solana, Bitcoin) has no prefix and no fixed length, so it
    /// chunks straight through and its last group may be short. That is
    /// correct and must not be padded: a padded group is characters the
    /// address does not have, on the one screen where a wrong character is a
    /// different address.
    static func chunks(_ address: String, size: Int = 4) -> [String] {
        guard size > 0 else { return [address] }
        var rest = Substring(address)
        var out: [String] = []
        if rest.hasPrefix("0x") || rest.hasPrefix("0X") {
            let head = rest.prefix(2 + size)
            out.append(String(head))
            rest = rest.dropFirst(head.count)
        }
        while !rest.isEmpty {
            let piece = rest.prefix(size)
            out.append(String(piece))
            rest = rest.dropFirst(piece.count)
        }
        return out.isEmpty ? [address] : out
    }

    /// How far into the reveal a chunk sits — 0 for the two ENDS, rising
    /// toward the middle.
    ///
    /// `AddressEndsFirst`'s reading, as an ordering rather than a mask: the
    /// ends are the part every short form already shows, and the middle is the
    /// part every wallet app hides, which is exactly the part the look-alike
    /// warning exists to make you look at. A horizontal mask cannot express
    /// that over a WRAPPING layout — it would uncover the left and right of
    /// each LINE, so on two lines it reveals the middle of the address first.
    static func revealRank(index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(0, index), max(0, count - 1 - index))
    }

    // MARK: - Dates

    /// The meta under an event's verb — "Aug 18 · Main", or "Aug 18" when we
    /// cannot honestly name a wallet on your side.
    static func meta(_ date: Date, walletName: String?,
                     now: Date = .now, calendar: Calendar = .current) -> String {
        let day = dayText(date, now: now, calendar: calendar)
        guard let walletName, !walletName.isEmpty else { return day }
        return day + " · " + walletName
    }

    /// An event's own eyebrow — the day, in the case it was written in.
    ///
    /// **It used to upper-case, and the carve-out that allowed it was wrong**
    /// (prd §453).
    /// The old doc argued §8's ban is on setting a WORD in caps and that this
    /// was merely "a date stamp, three characters of month and a number" —
    /// but `dayText` answers "Today" and "Yesterday" for the two commonest
    /// cases on any live spine, so the exemption failed for exactly the
    /// inputs it saw most, and it printed TODAY. Worse, it set the house
    /// style for its neighbours: `FIRST` and `STANDING · NOW` were both
    /// written in caps to match a stamp that should never have been in caps
    /// either. §8 has no ALL-CAPS eyebrow, and there is no third form of one.
    static func eyebrow(_ date: Date, now: Date = .now,
                        calendar: Calendar = .current) -> String {
        dayText(date, now: now, calendar: calendar)
    }

    /// "Today" / "Yesterday" / "Aug 18" / "Aug 18, 2024".
    ///
    /// A future date is NOT given a relative phrase — a landed thing stamped
    /// ahead of the clock is a bridge's bad timestamp (`lastPhrase`'s ruling),
    /// and it still has to print something, so it prints its day.
    static func dayText(_ date: Date, now: Date = .now,
                        calendar: Calendar = .current) -> String {
        // Measured against the INJECTED `now`, never `isDateInToday` (2026-08-23).
        // Those two read the SYSTEM clock, so this function took a `now`,
        // honoured it for the guard above and for the year comparison below,
        // and then abandoned it for the only two branches anyone reads. In the
        // app the two agree and nothing was ever wrong on screen — which is
        // exactly why it went unseen: the only thing that could tell was the
        // harness, and it passed on the one calendar day it was written and
        // went red at the next midnight. A gate that can only be green on the
        // day it was authored is a gate that gets switched off.
        //
        // **THIRD INSTANCE of one class.** `MoneyReceipt.dayPhrase` carries
        // this fix from 2026-08-12 and `AddressBookShape.lastPhrase` from
        // 2026-08-22 — the same day this file was written, in the same
        // session, which is how it was missed. Any function taking a `now`
        // must never reach for `isDateInToday`/`isDateInYesterday`: they
        // answer from the system clock and silently ignore the argument.
        if date <= now {
            if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
               calendar.isDate(date, inSameDayAs: yesterday) {
                return String(localized: "Yesterday")
            }
        }
        let sameYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: now)
        return formatted(date, template: sameYear ? "MMMd" : "yMMMd", calendar: calendar)
    }

    private static func monthText(_ date: Date, withYear: Bool,
                                  calendar: Calendar) -> String {
        formatted(date, template: withYear ? "yMMM" : "MMM", calendar: calendar)
    }

    /// **The zone is set BEFORE the template, and both halves are load
    /// bearing** — `AddressBookShape.lastPhrase`'s own comment, which its
    /// harness earned at exactly this boundary. A `DateFormatter` defaults to
    /// the SYSTEM zone, so it would render a date in one zone while the year
    /// that CHOSE the template was compared in the calendar's: an instant at
    /// midnight UTC on January 1st is still December where the device is, so
    /// the comparison says "this year, name the month" and the formatter
    /// answers with last year's. And the template is read against the locale,
    /// so setting either after `setLocalizedDateFormatFromTemplate` leaves the
    /// format string that was already derived.
    private static func formatted(_ date: Date, template: String,
                                  calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
