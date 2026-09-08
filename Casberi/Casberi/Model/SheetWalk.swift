import Foundation

/// Which list a thing sheet was opened FROM, so the doors out of it can walk
/// that list and no other (prd §645 pass 3, 2026-09-08).
///
/// **A VALUE, and never a `[Thing]`.** CLAUDE.md corollary 4 is exactly this
/// shape — a held array handed onward is build 177 — so the array is never
/// carried and the predicate is rebuilt from this at the far end.
///
/// `docs/reading-spec.md` A.3 specified an `enum` of three cases (source, kind,
/// none). It is a STRUCT here because the feed has TWO independent filters that
/// compose: `FeedFilter.source` (the chip strip) and `FeedFilter.tag` (the
/// agent's kind filter, §269). A room can be both — "my links, in the RSS
/// room" — and an enum would need a fourth case to say so, then a fifth the
/// day a third filter lands. Two optionals say the same thing and cannot go
/// out of date.
struct WalkScope: Hashable {

    /// The room's source, or nil for the All room.
    let source: String?

    /// A kind's `typeTag`, or nil for every kind.
    let typeTag: String?

    /// Whether doors are drawn at all.
    ///
    /// **An absent door is honest; a door onto a row the list does not hold is
    /// not** (A.3 rule 4). False whenever the list's membership cannot be
    /// rebuilt from a source and a kind — a hero, a "that day" shelf, a search
    /// result, the pinned room (membership is `pinnedAt != nil`, not a source),
    /// and any of the feed's own extra narrowings.
    let walks: Bool

    static let none = WalkScope(source: nil, typeTag: nil, walks: false)

    /// The scope for a feed row, from the room's live filter state.
    ///
    /// `narrowed` is the caller's own answer to "is this list narrowed by
    /// something I cannot express here" — the pinned room, a wallet, vibenet or
    /// person scope. It is passed IN rather than read here so this stays pure
    /// and so the feed's own narrowings can grow without this file learning
    /// about them; a caller that forgets it gets doors that overshoot, which is
    /// why `feed-walk-selftest.sh` pins the call site.
    static func feed(source: String, tag: String, narrowed: Bool) -> WalkScope {
        guard !narrowed else { return .none }
        // An unrecognised tag is not expressible. `tag` only ever holds "All"
        // or a `ThingKind.typeTag` today (§269), and a scope that guessed at
        // an unknown one would walk rows the list is not showing.
        let kindTag = tag == "All" ? nil : tag
        return WalkScope(source: source == "All" ? nil : source,
                         typeTag: kindTag,
                         walks: true)
    }

    /// Folded into `FeedSheetRoute.id`, so the same thing opened from two
    /// different rooms is two identities to SwiftUI rather than one.
    var key: String {
        walks ? "\(source ?? "*")/\(typeTag ?? "*")" : "-"
    }
}

/// The rule that decides whether a fetched row may be offered as the next or
/// previous one — pure, and separated from the fetch so it can be tested.
///
/// **The fetch cannot express all of it.** Two of the three tests below are
/// about a row's SOURCE STRING against a set (`Corpus.bulkImportSources`,
/// `Corpus.searchOnlySources`), which a `#Predicate` cannot push down to SQL,
/// and the kind test rides `tags`, where a pushed-down `.contains` on an
/// array-typed attribute is a documented SIGSEGV (CLAUDE.md, 2026-07-21). So
/// the fetch is bounded and the decision is made here in Swift.
enum SheetWalk {

    /// One candidate, as VALUES — the caller reads these off a live model and
    /// hands them over, so nothing here can touch a tombstone.
    struct Row: Equatable {
        let id: String
        let source: String
        /// Every tag the row carries; a kind scope matches against these
        /// because that is what the feed's own filter does.
        let tags: [String]
        /// `Corpus.isImportReceipt`.
        let isReceipt: Bool
        /// `Corpus.showsInAll` — only consulted for the All room.
        let showsInAll: Bool
        /// `Corpus.searchOnlySources.contains(source)` — the corpus the feed
        /// never surfaces at all.
        let searchOnly: Bool
    }

    /// May this row be walked to?
    static func eligible(_ row: Row, scope: WalkScope, from selfID: String) -> Bool {
        guard scope.walks, row.id != selfID else { return false }
        // Never the app's own "you imported N things" row. §399 paid for this
        // one by hand: a door onto our own note about a sync, from inside
        // somebody's diary.
        guard !row.isReceipt else { return false }
        // The search-only corpus is not on any list, so it is not on this one.
        guard !row.searchOnly else { return false }
        if let source = scope.source {
            guard row.source == source else { return false }
        } else {
            // The All room hides a bulk import's dump — thousands of rows
            // dated across years — and a door that walked into one would leave
            // the list without saying so.
            guard row.showsInAll else { return false }
        }
        if let tag = scope.typeTag {
            guard row.tags.contains(tag) else { return false }
        }
        return true
    }

    /// How many rows a bounded neighbour fetch asks for.
    ///
    /// Two until this pass — enough when the only thing that could be rejected
    /// was one import receipt (§399). The tests above can now reject a run of
    /// rows (a bulk import's dump sitting between two All-room entries, a
    /// kind scope in a mixed room), so the window is wider. Still a hard
    /// bound: past this the door is simply absent, which is the honest
    /// outcome and cheaper than an unbounded walk.
    static let fetchWindow = 24
}
