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
        /// `watching` leads the narrowing chips (2026-08-29, prd §511) because
        /// it REPLACES a pinned section: the five addresses this app reads used
        /// to sit in a block above the book, and they are ordinary rows in it
        /// now. Declaration order is strip order, so it sits where that block
        /// did.
        case all, watching, wallets, keys, contacts, social

        /// The capsule's word.
        var label: String {
            switch self {
            case .all:      return String(localized: "All")
            case .watching: return String(localized: "Watching")
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
        /// **`watched` is passed APART from `kind`, and that separation is
        /// §461's ruling in the type system.** Watching is not a kind — it is
        /// membership of a capped roster — so there is deliberately no
        /// `Kind.watched` case for a row to carry, no attribute for a row to
        /// toggle, and nothing here that any screen showing people could turn
        /// into a second address book. A filter is a property of the LIST; a
        /// star would be a control on the ROW, and only the second is what §461
        /// deleted.
        func matches(kind: String, watched: Bool = false) -> Bool {
            switch self {
            case .all:      return true
            case .watching: return watched
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
    static func availableFilters(kinds: [String], watching: Int = 0) -> [BookFilter] {
        BookFilter.allCases.filter { filter in
            if filter == .watching { return watching > 0 }
            return !filter.narrows || kinds.contains(where: { filter.matches(kind: $0) })
        }
    }

    /// The Watching chip's own word, which carries the CAP (2026-08-29, prd
    /// §511) — "Watching 3/5", never a bare "Watching".
    ///
    /// The cap had one home and it was the pinned section's header ("3 of 5").
    /// Deleting that section deletes the only place the app said how many of
    /// the five are spent, and a limit nobody is told about is discovered by
    /// being refused. This chip is where it goes, because it is the one control
    /// on the screen that is about exactly that population.
    ///
    /// **The chip is not the place the limit is ENFORCED** — it narrows a list
    /// and nothing else — so this is a fact printed on a control, never a
    /// disabled one.
    static func watchingLabel(_ count: Int, limit: Int) -> String {
        String(localized: "Watching \(count)/\(limit)")
    }

    /// The filter that should stand, given the one selected and what the book
    /// can currently offer — `all` whenever the selection has stopped being
    /// available.
    ///
    /// This exists for ONE transition and it is the only way this control can
    /// strand the screen: remove the last key while `keys` is selected and the
    /// chip disappears from the strip while still filtering the list, so the
    /// book reads as empty with nothing on screen explaining why.
    static func settledFilter(_ selected: BookFilter, kinds: [String],
                              watching: Int = 0) -> BookFilter {
        availableFilters(kinds: kinds, watching: watching).contains(selected) ? selected : .all
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

    // MARK: - Unwatching

    /// Whether stopping a watch KEEPS the address in the book, or takes it out
    /// with the watch (2026-08-29, prd §511).
    ///
    /// **The problem it answers.** Watching and naming are two facts and §461
    /// is right to split them — a name you gave a counterparty must survive you
    /// no longer reading their wallet. But `WalletStore.add` files EVERY
    /// watched wallet in the book, and for a bare pasted address it files it
    /// under a placeholder it minted itself (`…44b1`). For that wallet the book
    /// entry is not a second fact at all: it is the residue of the watch. So
    /// removing it took two gestures spelled with the same word — a swipe on
    /// the roster, then a long-press in the list it silently reappeared in —
    /// which reads as a delete that failed rather than as a demotion.
    ///
    /// **The rule is AUTHORSHIP, not attribute.** A name somebody typed, a
    /// group they filed it in, a note they wrote, a provenance the app verified
    /// through a door (§169), or a network tag saying it was met somewhere else
    /// are all things this app cannot recreate, and every one of them keeps the
    /// row. A placeholder name and nothing else is ours, and leaves with the
    /// watch.
    ///
    /// **It errs toward KEEPING in every uncertain direction**, because the two
    /// mistakes are not equal: a row that stays is one long-press from gone,
    /// and a row that goes takes with it a name nobody can retype.
    ///
    /// `isPlaceholderName` is passed IN rather than derived here on purpose —
    /// the test is `WalletStore.isAutoName`, which carries two dead spellings
    /// for books already on disk and belongs beside the function that mints
    /// them. Taking the answer as a parameter is what keeps this file
    /// Foundation-only, and what makes every fixture below mean something.
    static func unwatchKeepsEntry(isPlaceholderName: Bool,
                                  groups: [String]? = nil,
                                  note: String? = nil,
                                  provenance: String? = nil,
                                  networks: [String]? = nil) -> Bool {
        // A name somebody typed is the whole reason the book outlives the
        // roster. Asked first because it is the common keep.
        if !isPlaceholderName { return true }
        // Blank strings are not authorship. A group list holding one empty
        // name, or a note that is whitespace, would otherwise pin an unnamed
        // address in the book forever with nothing on screen to explain why.
        if (groups ?? []).contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let provenance, !provenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        // Met somewhere that is not this roster — a vibenet watch, an import.
        // Dropping the entry would drop that tag, and nothing would ever put
        // it back: the tag records a meeting, and meetings do not repeat.
        if (networks ?? []).contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        return false
    }
}

/// THE DECK A PASTED LIST MAKES (2026-08-27, prd §502) — the words and the fan.
///
/// Foundation-only and separate from `AddressBookShape` for the same reason
/// that file gives about itself: it decides ORDER, SECTIONS and WORDS about a
/// book, and this decides how a paste is PREVIEWED, which is not a property of
/// the book at all. Both compile whole in `address-book-selftest.sh`.
enum AddressDeck {
    /// How many faces are drawn. A fan of forty is a smear, and the deck's job
    /// is to say "a list, understood", which five says as well as forty does.
    static let shown = 5

    /// The fan, from a FIXED table rather than arithmetic on the index.
    ///
    /// The same instinct `WalletFace`'s twelve grounds are built on: a computed
    /// angle can land two neighbours a hair apart (which reads as a rendering
    /// fault rather than as a fan) or swing far enough to clip the face above.
    /// Five stated angles cannot do either. Small on purpose — a deck of cards
    /// thrown down, not a hand held up.
    private static let tilts: [Double] = [-6, 3, -2, 5, -4]

    static func tilt(_ index: Int) -> Double {
        guard !tilts.isEmpty else { return 0 }
        // Cycles rather than clamping, so a deck drawn beyond `shown` by some
        // future caller keeps fanning instead of stacking flat.
        return tilts[((index % tilts.count) + tilts.count) % tilts.count]
    }

    /// What the deck says beside itself.
    ///
    /// **"read", never "named" or "landed".** Nothing has been written when
    /// this is on screen — the paste is still in the field, and the verb that
    /// writes is `Add all`. The whisper underneath says "12 named." AFTER the
    /// write, and the two words being different is the whole point: one is a
    /// reading of what you pasted, the other is a report of what happened.
    ///
    /// **The total, not the drawn count.** Five faces beside "12 addresses
    /// read" accounts for the seven not drawn; five beside "5" would be a
    /// silent truncation wearing a number, which is the one thing a folded tail
    /// may never be.
    static func line(count: Int) -> String {
        String(localized: "\(count) addresses read")
    }
}
