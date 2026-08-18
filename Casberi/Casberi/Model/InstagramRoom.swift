import Foundation

/// THE INSTAGRAM ROOM'S HEAD (2026-08-18, prd §395) — the library, not the day.
///
/// ## What this room actually is
///
/// Every other import room in this app is mostly the person's own writing. This
/// one is not, and that is the fact its head has to state: an Instagram export
/// is overwhelmingly a record of what you TAPPED — thousands of posts other
/// people made, kept over years, from a set of accounts nobody could name from
/// memory — with your own captions and comments as a small seam running through
/// it. Nothing the room drew before said so. `FeedInsight.leaderboard` ranked
/// the accounts and could not say how big the pile was or how far back it went;
/// the topic treemap describes the seam and not the library; `FeedHeatmap`'s
/// "Your Instagram year" charts twelve months over a decade of saving.
///
/// ## §349's rule, and how this meets it
///
/// `sourceHead` outranks `FeedInsight.leaderboard`, so this card takes the slot
/// "Who you save most" held — and **a head must never draw less than what it
/// displaces**. So it draws the same board, ranked the same way, capped at the
/// same `rowCap` that `FeedInsight.ranked` uses, and adds the three things that
/// board could not carry: how much there is, how long it took, and how much of
/// it Instagram has since deleted.
///
/// ## Saves and likes are never summed
///
/// §247's ruling, kept exactly: a save is a deliberate keep and a like is a
/// reaction in passing, and one ranking over both is a number with no meaning.
/// So the card is about ONE act — saves when there are enough of them, likes
/// otherwise — and says which in its own headline rather than quietly changing
/// what the bars mean. What you MADE is a separate clause with its own verb; it
/// is never added to the total.
///
/// ## What it costs: nothing
///
/// `sourceRef`, `authorHandle`, `capturedAt`, `tags`, `kind` — all of them
/// light columns already pre-fetched by `FeedScreen.lightColumns`. No request,
/// no new `Thing` property, no CloudKit deploy, no `UserDefaults`. The
/// `XRoom`/`PeerRoom` contract, for its reason: a head that can fail is a head
/// that can fail differently from the rows beneath it.
///
/// One reading was left OUT for exactly that rule, and it is worth recording
/// because it is the one somebody will try to add back: how many kept posts
/// have their words yet (`InstagramCaptions` walks the library slowly in the
/// background, and there is no surface anywhere saying how far it has got).
/// That test is `enrichedText != nil`, and `enrichedText` is deliberately
/// absent from the pre-fetch — asking it would fault every row of a room that
/// holds thousands, on every re-draw, to answer a question about a background
/// pass. It lives in `-instagramRoomProbe` instead, where it is asked once.
///
/// Foundation-only by design so `scripts/instagram-selftest.sh` can compile it
/// WHOLE and unmodified — the only proof these numbers are right, since no real
/// Instagram export has ever been imported on this host. Everything touching
/// `Thing` lives in `InstagramRoomSource`.
struct InstagramRoom: Equatable {

    // MARK: - What a row is

    /// Which act the card is about. Never both at once — see the type note.
    enum Act: String, Equatable {
        case saved, liked
    }

    /// One kept post, reduced to the four facts the head reads.
    struct Keep: Equatable {
        /// `Thing.sourceRef` — how a tap lands on the real row.
        let ref: String?
        /// The account that made it, from `Thing.authorHandle`. NEVER the
        /// title: that is display text ("@handle", or a bare URL for the rare
        /// entry Meta named nobody for), so grouping on it would rank the "@"
        /// and file every anonymous save under its own permalink.
        let handle: String?
        /// The calendar year, resolved by the caller against ONE calendar.
        let year: Int
        /// Instagram no longer serves this post — stamped by
        /// `InstagramCaptions` when the page answers 404 or 410 (prd §309).
        let gone: Bool
    }

    // MARK: - The shape

    /// One account, and how much of the library it fills.
    struct Account: Identifiable, Equatable {
        let handle: String
        let kept: Int
        /// The newest kept post from this account — where a tap lands, since an
        /// account owns many rows and the card can name only one.
        let newestRef: String?

        var id: String { handle }
    }

    let act: Act
    /// Biggest first, capped at `rowCap`.
    let accounts: [Account]
    /// Rows of `act` counted — the library's size.
    let kept: Int
    /// Distinct accounts across all of them, not just the ones drawn. The
    /// headline states this, so a card showing six rows still says four hundred.
    let accountCount: Int
    /// Your own posts and comments. A separate clause, never added to `kept`.
    let made: Int
    /// Kept posts Instagram has since deleted or made private.
    let gone: Int
    let firstYear: Int
    let lastYear: Int

    /// Inclusive, so a library entirely inside one year spans 1.
    var span: Int { max(1, lastYear - firstYear + 1) }
    var isEmpty: Bool { accounts.isEmpty }

    // MARK: - Composition

    /// A library needs this many kept posts before it is a library rather than
    /// a handful of taps. Below it the leaderboard leads exactly as it did.
    static let minimumKept = 12
    /// …and this many accounts, or "from N accounts" is a sentence about one
    /// person's feed and the bars underneath it are a formality.
    static let minimumAccounts = 3
    /// The board's own cap, matched to `FeedInsight.ranked`'s `prefix(6)` on
    /// purpose: this card displaces that board, and §349 says it may not draw
    /// less than what it displaces. Changing one without the other breaks that
    /// promise silently — the card would simply look a little shorter.
    static let rowCap = 6

    /// The head, or nil when this room has no library to show.
    ///
    /// SAVES LEAD. An export with too few of them falls back to likes, the way
    /// `FeedInsight.savedAuthors` already does, and the headline says which —
    /// rather than quietly re-labelling the same bars.
    static func compose(saved: [Keep], liked: [Keep], made: Int) -> InstagramRoom? {
        build(.saved, saved, made: made) ?? build(.liked, liked, made: made)
    }

    private static func build(_ act: Act, _ keeps: [Keep], made: Int) -> InstagramRoom? {
        guard keeps.count >= minimumKept else { return nil }

        var counts: [String: Int] = [:]
        var newest: [String: (ref: String?, year: Int)] = [:]
        var order: [String] = []
        var first = Int.max
        var last = Int.min
        var gone = 0
        for keep in keeps {
            if keep.year < first { first = keep.year }
            if keep.year > last { last = keep.year }
            if keep.gone { gone += 1 }
            let handle = (keep.handle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !handle.isEmpty else { continue }
            if counts[handle] == nil { order.append(handle) }
            counts[handle, default: 0] += 1
            // STRICTLY greater, so the first row seen in a year keeps the tap
            // target and two rows from the same year can never swap it between
            // opens.
            if keep.year > (newest[handle]?.year ?? Int.min) {
                newest[handle] = (keep.ref, keep.year)
            }
        }
        guard counts.count >= minimumAccounts, first <= last else { return nil }

        // Value desc, then handle ASC — a total order, so the board cannot
        // reshuffle between two opens over the same rows.
        let accounts = order
            .sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
            .prefix(rowCap)
            .map { Account(handle: $0, kept: counts[$0]!, newestRef: newest[$0]?.ref) }
        guard !accounts.isEmpty else { return nil }

        return InstagramRoom(act: act,
                             accounts: Array(accounts),
                             kept: keeps.count,
                             accountCount: counts.count,
                             made: made,
                             gone: gone,
                             firstYear: first,
                             lastYear: last)
    }

    // MARK: - Words

    /// The whole finding as one sentence: how much you kept, and from how many
    /// people. Nobody knows either number about their own account.
    ///
    /// The counts ARE quantities and are formatted as such; the years below are
    /// not, and are interpolated as strings for `XRoom.headline`'s reason — a
    /// localized `Int` picks up the locale's grouping separator, so 2019 renders
    /// as "2,019", a year printed as an amount in the largest type on the card.
    static func headline(_ room: InstagramRoom) -> String {
        let accounts = room.accountCount.formatted()
        let kept = room.kept.formatted()
        switch room.act {
        case .saved:
            return String(localized: "You saved \(kept) posts from \(accounts) accounts")
        case .liked:
            return String(localized: "You liked \(kept) posts from \(accounts) accounts")
        }
    }

    /// How long it took, and what you made yourself.
    ///
    /// The two clauses are deliberately separate verbs. Adding "96 of your own"
    /// to the kept total would sum a keep and a post, which is the same mistake
    /// §247 refuses when it declines to sum saves and likes.
    static func note(_ room: InstagramRoom) -> String {
        let span = room.span == 1
            ? String(localized: "All from \(String(room.lastYear))")
            : String(localized: "Over \(room.span) years")
        guard room.made > 0 else { return span }
        return String(localized: "\(span) · \(room.made.formatted()) of your own")
    }

    /// One account's line: what it holds, in the act's own noun.
    static func accountLine(_ account: Account, act: Act) -> String {
        switch act {
        case .saved:
            return String(localized: "\(account.kept.formatted()) saves")
        case .liked:
            return String(localized: "\(account.kept.formatted()) likes")
        }
    }

    /// The reading no service can make about your own library — or nil.
    ///
    /// It is stated as a FLOOR, not a total, and the wording carries that: only
    /// rows `InstagramCaptions` has actually asked about can be known gone, and
    /// that pass walks the library slowly in the background. "N are gone" would
    /// be a claim about the whole library made from the part we have checked.
    static func footnote(_ room: InstagramRoom) -> String? {
        guard room.gone > 0 else { return nil }
        return String(localized: "\(room.gone.formatted()) of these are gone from Instagram. Your record of them isn't.")
    }

    /// A bar's share of the biggest account's. Zero-safe: a room whose leader is
    /// somehow empty draws flat bars rather than dividing by nothing — the NaN
    /// a SwiftUI frame draws as no bar at all.
    static func share(kept: Int, of top: Int) -> Double {
        guard top > 0 else { return 0 }
        return min(1, Double(kept) / Double(top))
    }

    /// The biggest account's count — every bar's full width, so the card is on
    /// ONE scale.
    static func top(_ room: InstagramRoom) -> Int {
        room.accounts.map(\.kept).max() ?? 0
    }
}
