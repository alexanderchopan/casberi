import Foundation

/// How the address book LAYS OUT — the pure half of the manager's list
/// (2026-08-22, prd §440).
///
/// Foundation-only by design, so `scripts/address-book-selftest.sh` can compile
/// it whole and unmodified. Every decision here renders as a perfectly ordinary
/// list whether it is right or wrong — a letter heading over the wrong rows, a
/// scrubber offering a letter that scrolls nowhere, a book that looks sorted
/// and isn't — so nothing in a build, a screen sweep or any static audit can
/// see a fault in it. The harness is the only proof.
///
/// **What lives here and what deliberately does not.** This file decides
/// ORDER, SECTIONS and WORDS. It never decides membership: which entries reach
/// it is `AddressBook.search`'s answer, and which of them are watched is
/// `WalletStore`'s. Handing it a filtered array keeps it a pure function of its
/// input, which is what makes the fixtures below mean anything.
enum AddressBookShape {

    // MARK: - Sectioning

    /// The heading a name files under — its first letter, or `#`.
    ///
    /// **`#` is not a fallback, it is a real bucket**, and the book needs it
    /// more than a contacts app does: `WalletStore.add` files a bare address
    /// under its own short form, so an unnamed wallet is literally called
    /// `…44b1` and a book of forty pasted addresses is forty rows starting
    /// with a digit or an ellipsis. Filing those under `0`, `…` and `4` would
    /// give the scrubber a dozen headings nobody can aim at.
    ///
    /// Diacritics fold (`Ångström` files under A, not past Z) via
    /// `folding(options:)`, which is also what `localizedStandardCompare`
    /// does when it orders them — the two must agree or a row sits under a
    /// heading it sorts away from.
    static func sectionLetter(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                          locale: .current).first
        else { return "#" }
        // `isLetter` rather than an A–Z range: this app ships in five
        // languages, and penning あ or Я into `#` would put a Japanese book
        // entirely under one heading.
        return first.isLetter ? String(first).uppercased() : "#"
    }

    /// One lettered block of the list.
    struct Section: Identifiable, Equatable {
        /// nil for an UNLETTERED list — the recency and activity orders, where
        /// a letter heading would be a lie about how the rows are arranged.
        let letter: String?
        let ids: [String]
        var id: String { letter ?? "\u{0}all" }
    }

    /// How the list is ordered. The cases are the sort menu's, and the
    /// distinction that matters is that only ONE of them sections.
    enum Order: String, CaseIterable, Sendable {
        /// A–Z, in sections. **The default since §440**, reversing §433's
        /// recent-with-watched-first. That ruling existed because "a bulk
        /// paste of forty names could push all five of your watched wallets
        /// off the bottom of the screen"; the watched shelf at the top of the
        /// screen now holds those five unconditionally, so the reason is
        /// spent — and A–Z with headings and a scrubber is how somebody finds
        /// one row out of twenty-seven, which is what this list is for.
        case name
        /// Newest-named first, watched hoisted. Kept, not default.
        case recent
        /// Most dealt-with first.
        case activity

        var label: String {
            switch self {
            case .name:     return String(localized: "Name")
            case .recent:   return String(localized: "Recent")
            case .activity: return String(localized: "Most active")
            }
        }

        /// Whether this order draws letter headings and a scrubber. Asked
        /// rather than tested against `.name` at three call sites, so adding a
        /// second sectioning order later can never leave one of them behind.
        var sections: Bool { self == .name }
    }

    /// One row's sortable facts, lifted out of `AddressBook.Entry` so this
    /// file stays Foundation-only and the harness can pose a book without a
    /// store behind it.
    struct Row: Equatable {
        let id: String
        let name: String
        /// When the address was first named — `recent`'s key.
        let addedAt: Date
        let watched: Bool
        let activity: Int

        init(id: String, name: String, addedAt: Date,
             watched: Bool = false, activity: Int = 0) {
            self.id = id; self.name = name; self.addedAt = addedAt
            self.watched = watched; self.activity = activity
        }
    }

    /// The whole list, ordered and cut into sections.
    ///
    /// **Every order is TOTAL** — each one falls through to the name and then
    /// to the id. Not fussiness: a list that reshuffles two equal rows between
    /// body passes reads as broken, which is the lesson `agent-panel-selftest`
    /// paid for with its tile sort and `AddressSky` paid for again with its
    /// bearings. Two addresses pasted in one bulk import share a timestamp to
    /// the millisecond, and forty un-dealt-with addresses all have an activity
    /// of zero, so the ties here are the common case rather than a corner.
    static func sections(_ rows: [Row], order: Order) -> [Section] {
        let sorted = ordered(rows, order: order)
        guard order.sections else {
            return sorted.isEmpty ? [] : [Section(letter: nil, ids: sorted.map(\.id))]
        }
        var out: [Section] = []
        for row in sorted {
            let letter = sectionLetter(for: row.name)
            if out.last?.letter == letter {
                out[out.count - 1] = Section(letter: letter, ids: out[out.count - 1].ids + [row.id])
            } else {
                out.append(Section(letter: letter, ids: [row.id]))
            }
        }
        return out
    }

    /// The ordering itself, without the cutting — separate because the sort
    /// menu's own preview and the harness both want the sequence rather than
    /// the blocks.
    static func ordered(_ rows: [Row], order: Order) -> [Row] {
        switch order {
        case .name:
            return rows.sorted(by: byName)
        case .recent:
            // Watched first (§433's surviving half — a star is the person's
            // own statement that a row matters more), then newest-named.
            return rows.sorted {
                if $0.watched != $1.watched { return $0.watched }
                if $0.addedAt != $1.addedAt { return $0.addedAt > $1.addedAt }
                return byName($0, $1)
            }
        case .activity:
            return rows.sorted {
                if $0.activity != $1.activity { return $0.activity > $1.activity }
                return byName($0, $1)
            }
        }
    }

    /// The name comparison every order falls through to. `#` names sort AFTER
    /// letters, matching where their heading sits — without this an address
    /// called `…44b1` leads the list under a `#` heading printed at the
    /// bottom, which is the one arrangement that is visibly wrong.
    private static func byName(_ a: Row, _ b: Row) -> Bool {
        let la = sectionLetter(for: a.name), lb = sectionLetter(for: b.name)
        if la != lb {
            if la == "#" { return false }
            if lb == "#" { return true }
        }
        let cmp = a.name.localizedStandardCompare(b.name)
        if cmp != .orderedSame { return cmp == .orderedAscending }
        return a.id < b.id
    }

    /// The scrubber's letters — the headings that EXIST, in list order.
    ///
    /// Present-only, never a full A–Z with inert letters: a scrubber offering
    /// `Q` on a book with no Q is a control that does nothing, which is §83's
    /// ban wearing 26 tiny copies. It also means the strip is short on a small
    /// book, which is honest about how big the book is.
    static func index(of sections: [Section]) -> [String] {
        sections.compactMap(\.letter)
    }

    // MARK: - Group matching (prd §440)

    /// Whether a query names a group. **The one spelling of that test**, so
    /// the search field, the group results and `AddressBook.search`'s row
    /// filter can never disagree about what "fam" finds.
    ///
    /// Whole-name matches fold through the book's own case rule; anything
    /// shorter falls back to substring, since somebody typing "fam" has not
    /// named a group yet. Lifted here from `AddressBook.search`, which had it
    /// inline and is now the caller.
    static func groupMatches(_ group: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return false }
        let g = group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return g == q || g.contains(q)
    }

    /// The groups a query names, in the order given.
    static func matchingGroups(_ groups: [String], query: String) -> [String] {
        groups.filter { groupMatches($0, query: query) }
    }

    // MARK: - The filter chips (prd §498)

    /// Which population the book is showing — one quiet capsule row, single
    /// select, above the list (user, 2026-08-27: *"we need filter chips
    /// somehow"*).
    ///
    /// **Why they exist.** §496 made this one book over two rooms and §498
    /// widened it past crypto, so a list that was one population is now five.
    /// The chips are what keeps §169's promise — "scannable at fifty rows" —
    /// now that exclusion no longer does it: the answer to a mixed book is a
    /// control, not a membership rule.
    ///
    /// **There is deliberately no CONTRACTS chip**, and no ONCHAIN one.
    /// Contracts and Contacts are one letter apart, and two capsules that
    /// differ by a letter in a horizontal row is a misread waiting to happen —
    /// so the machinery population has no chip of its own and `wallets` is the
    /// "hide the machinery" filter people actually reach for. An `onchain`
    /// chip was refused for the older reason: before §498 every entry was
    /// on-chain, so it selected everything; it becomes sayable now, and is
    /// still not worth a sixth capsule while `contacts` and `social` name the
    /// off-chain half directly.
    ///
    /// **There is no VIBENET chip either** (user ruling, same day) — where an
    /// address was met is a per-ROW fact, answered by the badge `AddressMark`
    /// draws on the face, and a filter answers a different question than the
    /// one you have while scanning.
    ///
    /// Kinds are matched by RAW STRING, not by `AddressBook.Kind`: this file
    /// is Foundation-only so the harness can compile it whole and unmodified,
    /// and importing the book's enum would drag `@Observable` in behind it.
    /// A drift guard ties these literals to the enum's own cases.
    enum BookFilter: String, CaseIterable, Sendable {
        case all, wallets, keys, contacts, social

        /// The capsule's word.
        var label: String {
            switch self {
            case .all:      return String(localized: "All")
            case .wallets:  return String(localized: "Wallets")
            case .keys:     return String(localized: "Keys")
            case .contacts: return String(localized: "Contacts")
            case .social:   return String(localized: "Social")
            }
        }

        /// Whether a row of this kind belongs under this chip.
        ///
        /// `wallets` deliberately takes `unknown` and `smartAccount` as well
        /// as `wallet`: the unmarked "who" population is what somebody means
        /// by the word, `smartAccount` is somebody's own wallet made of code
        /// (§294 — the whole point of that case), and `unknown` is the resting
        /// state EVERY vibenet entry sits in for life, since detection is
        /// gated off for devnets (§496). Dropping either would file real
        /// wallets outside the wallet chip, which reads as rows going missing.
        func matches(kind: String) -> Bool {
            switch self {
            case .all:      return true
            case .wallets:  return kind == "wallet" || kind == "smartAccount" || kind == "unknown"
            case .keys:     return kind == "key"
            case .contacts: return kind == "contact"
            case .social:   return kind == "social"
            }
        }

        /// Whether this chip is a real filter at all — `all` narrows nothing,
        /// so the strip draws it without ever needing members to justify it.
        var narrows: Bool { self != .all }
    }

    /// The chips worth drawing over these kinds — `all` always leads, then any
    /// filter with at least one member, in declaration order.
    ///
    /// A chip with no members is never offered: a control whose only possible
    /// outcome is an empty list is §83's dead control, and on a fresh book
    /// four of the five would be exactly that.
    static func availableFilters(kinds: [String]) -> [BookFilter] {
        BookFilter.allCases.filter { filter in
            !filter.narrows || kinds.contains(where: { filter.matches(kind: $0) })
        }
    }

    /// The filter that should stand, given the one selected and what the book
    /// can currently offer — `all` whenever the selection has stopped being
    /// available.
    ///
    /// This exists for ONE transition and it is the only way this control can
    /// strand the screen: remove the last key while `keys` is selected and the
    /// chip disappears from the strip while still filtering the list, so the
    /// book reads as empty with nothing on screen explaining why.
    static func settledFilter(_ selected: BookFilter, kinds: [String]) -> BookFilter {
        availableFilters(kinds: kinds).contains(selected) ? selected : .all
    }

    // MARK: - The recency phrase (prd §440)

    /// When you last dealt with an address, in as few words as the fact needs.
    ///
    /// It is a FACT and never a judgement: no "recently", no "a long time ago",
    /// no colour, no rate. §295's ruling on this screen is that it states what
    /// the corpus holds and never interprets it, and "May" interprets nothing
    /// while "quiet lately" would.
    ///
    /// The rungs get COARSER as they get older on purpose. "3 days ago" is
    /// worth saying and "241 days ago" is arithmetic nobody wanted — at that
    /// distance the month is the fact, and past a year only the year is.
    ///
    /// Bare `nil` for a future date rather than "in 0 days": a landed thing
    /// stamped ahead of the clock is a bridge's bad timestamp, and inventing a
    /// phrase for it prints nonsense on a row.
    static func lastPhrase(_ date: Date, now: Date = .now,
                           calendar: Calendar = .current) -> String? {
        guard date <= now else { return nil }
        // EVERY RUNG IS MEASURED AGAINST `now` (2026-08-22, prd §448).
        //
        // The first two used to be `calendar.isDateInToday(date)` and
        // `isDateInYesterday(date)`, and **those two methods ignore `now`
        // entirely** — they compare against the real system clock. So this
        // function's own injected clock was a lie for two of its five
        // branches, and the harness's coverage of them was an accident of
        // what time of day it ran: the fixtures pin `now` to noon UTC on
        // 2026-08-22, which agrees with the real clock until 17:00 Pacific
        // and disagrees after it, at which point three assertions fail on
        // code nobody touched. Caught exactly that way, twelve hours after
        // the harness was written and green.
        //
        // The day count below already answers all three rungs, so the fix is
        // a deletion rather than a second clock: 0 is today, 1 is yesterday,
        // and the same subtraction carries the week.
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days == 0 { return String(localized: "today") }
        if days == 1 { return String(localized: "yesterday") }
        if days < 7 { return String(localized: "\(days) days ago") }
        // Inside the same calendar year the month names itself; older than
        // that it would be ambiguous ("May" of which May?), so the year takes
        // over. Tested at the boundary, which is where an off-by-one prints a
        // month from two years ago as though it were this spring.
        //
        // **The formatter is given the calendar's own zone BEFORE the
        // template, and both halves of that are load-bearing.** A
        // `DateFormatter` defaults to the SYSTEM zone, so it would render a
        // date in one zone while the year comparison above compared it in
        // another: an instant at midnight UTC on January 1st is still
        // December where the device is, so the comparison says "this year,
        // name the month" and the formatter answers "December" — last year's
        // month, printed as though it were this one. Found by this file's own
        // harness at exactly that boundary, on its first run.
        //
        // And the template is read against `locale`, so setting either after
        // `setLocalizedDateFormatFromTemplate` leaves the format string that
        // was already derived.
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.setLocalizedDateFormatFromTemplate("MMMM")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("yyyy")
        }
        return formatter.string(from: date)
    }
}
