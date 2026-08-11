import Foundation
import SwiftData

/// The pinned list — the app's one editorial verb over its own corpus.
///
/// **Why this exists.** Every other room in the app is assembled FOR you: a
/// source lands rows, the feed shapes them, and your only say is which room
/// you stand in. The pinned list is the one place you say "this one", and it
/// is the one thing a native app can't do for you — X can bookmark an X post
/// and Obsidian can star a note, but nothing outside Casberi can hold a
/// Farcaster cast, a screenshot and a Stripe dispute in the same short list.
/// That cross-source span is the whole feature; a per-source pin would just be
/// a second, worse bookmark.
///
/// **What it is not.** No folders, no groups, no ordering you maintain — a
/// flat list, newest pin first (user ruling 2026-08-10: "a list alone tho
/// would be good", grouping deferred as a power-user feature). That deferral
/// stays cheap on purpose: grouping later means one more field on these same
/// rows, not a different shape.
///
/// **Storage** is `Thing.pinnedAt` — see that property for why `Mark.saved`,
/// which looks free, is a trap.
enum Pinboard {

    /// The chip's label, and the sentinel `FeedFilter.source` takes when the
    /// pinned room is showing. Spelled ONCE here and compared through
    /// `isPinnedRoom` everywhere else — a literal repeated across the chip
    /// strip, the pager, the query and the empty state is four chances to
    /// disagree, and the room silently renders the wrong page when they do
    /// (the `TabView` unmatched-selection trap `MainSurface` documents where
    /// `feedLabels` used to live).
    static let room = "Pinned"

    static func isPinnedRoom(_ source: String) -> Bool { source == room }

    // MARK: - The verb

    static func isPinned(_ thing: Thing) -> Bool { thing.pinnedAt != nil }

    /// Pin or unpin, and report the new state so the caller can word its own
    /// confirmation without re-reading the model.
    ///
    /// Writes the model and nothing else: no network, no consent, no external
    /// side effect. That is what makes it legal from the row's context menu,
    /// which is otherwise reads-only — the menu's rule exists to keep a
    /// one-slip yes from reaching something irreversible, and this reaches
    /// nothing and undoes itself with the same gesture.
    @discardableResult
    @MainActor
    static func toggle(_ thing: Thing) -> Bool {
        guard thing.isLive else { return false }
        let nowPinned = thing.pinnedAt == nil
        thing.pinnedAt = nowPinned ? .now : nil
        return nowPinned
    }

    // MARK: - Reading the room

    /// Is anything pinned? Answered with a bounded, indexed read — never by
    /// walking the corpus.
    ///
    /// This is asked from the chip strip's refresh, which runs on mount,
    /// foreground and arrival, so it must not be the thing that re-introduces
    /// the cost `MainSurface.newestPerSource` was written to remove (a quarter
    /// of the main thread spent materialising every row the person owns, prd
    /// §—, measured 2026-08-06). `fetchLimit = 1` plus a single fetched
    /// property means one row, one column, whatever the corpus size.
    @MainActor
    static func hasAny(in context: ModelContext) -> Bool {
        var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.pinnedAt != nil })
        d.fetchLimit = 1
        d.propertiesToFetch = [\.pinnedAt]
        return ((try? context.fetch(d))?.first?.isLive) ?? false
    }
}
