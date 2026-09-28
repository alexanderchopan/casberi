import Foundation
import SwiftData

/// THE NOTES ROOM — the pinned list, and the notes you wrote (prd §969,
/// 2026-09-28).
///
/// **Why this exists.** Every other room in the app is assembled FOR you: a
/// source lands rows, the feed shapes them, and your only say is which room
/// you stand in. This is the one room you build: the place you say "this one"
/// (a pin), and the place a note you jotted lands. It is the one thing a
/// native app can't do for you — X can bookmark an X post and Obsidian can
/// star a note, but nothing outside Casberi can hold a Farcaster cast, a
/// screenshot, a Stripe dispute and a line you typed in the same short list.
/// That cross-source span is the whole feature; a per-source pin would just be
/// a second, worse bookmark.
///
/// **What it was.** Pinned — a flat list, newest pin first, behind a door
/// drawn only once something was pinned (2026-08-10, then §961). The
/// user folded it into Notes (§969: "pinning could pin things to notes
/// instead of a separate pinned icon and area"): one always-drawn door in
/// You, and Pin is how anything in the app gets in. The 2026-08-10 deferral
/// — "grouping later means one more field on these same rows, not a
/// different shape" — is paid by `Thing.folder`, which serves a pin and a
/// note alike.
///
/// **What it is not.** No ordering you maintain (reorder declined, §969:
/// "this one on top" is Pin, and folders are the other hand-order), and no
/// editor — a note is captured, never edited (§26: content is the record).
///
/// **Storage** is `Thing.pinnedAt` for a pin — see that property for why
/// `Mark.saved`, which looks free, is a trap — and `source == "You"` with
/// `kind == .note` for a note, which is exactly what a note shared in from
/// Apple Notes already lands as (§230a), so the room reaches those too.
enum Pinboard {

    /// The door's label, and the sentinel `FeedFilter.source` takes when the
    /// room is showing. Spelled ONCE here and compared through `isPinnedRoom`
    /// everywhere else — a literal repeated across the tray, the pager, the
    /// query and the empty state is four chances to disagree, and the room
    /// silently renders the wrong page when they do (the `TabView`
    /// unmatched-selection trap `MainSurface` documents where `feedLabels`
    /// used to live). The name stays `isPinnedRoom` at every call site: the
    /// sentinel changed, the seventy tests of it did not.
    static let room = "Notes"

    static func isPinnedRoom(_ source: String) -> Bool { source == room }

    // MARK: - Membership

    /// A note you wrote — or shared in, or dictated as text: your own source,
    /// the note kind. The room's second membership, beside the pin.
    static func isNote(_ thing: Thing) -> Bool {
        thing.source == "You" && thing.kind == .note
    }

    /// Whether the room holds this thing: pinned, or a note of yours. The
    /// `@Query` fetches `pinnedAt != nil || source == "You"` (a kind cannot be
    /// predicated), and this is the half the predicate could not say.
    static func inRoom(_ thing: Thing) -> Bool {
        thing.pinnedAt != nil || isNote(thing)
    }

    /// The room's one order: newest first, by when YOU acted — the pin's
    /// time for a pin, the note's capture for a note. A pin you made this
    /// morning on a two-year-old screenshot belongs at the top; so does a
    /// note you pinned, which is what "this one on top" means here.
    static func stamp(_ thing: Thing) -> Date {
        thing.pinnedAt ?? thing.capturedAt
    }

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
}

/// The Notes room's tiles (prd §969): All · Pinned · Folders · New. All is
/// lit by default and first, as in every room; New is LAST and never lights —
/// it is a verb in the row, drawn in tint, and it raises the note sheet (the
/// user weighed New first and All first: "notes should be default", and the
/// default is whichever tile is lit, not whichever is first).
///
/// Foundation-only, like every scope enum, so a harness can compile it
/// whole; the glyphs are `ScopeTileGlyphs.swift`'s.
enum NotesScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, pinned, folders, new

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:     return String(localized: "All")
        case .pinned:  return String(localized: "Pinned")
        case .folders: return String(localized: "Folders")
        case .new:     return String(localized: "New")
        }
    }

    /// Read by VoiceOver and the tooltip.
    var summary: String {
        switch self {
        case .all:     return String(localized: "Your notes and everything you pinned")
        case .pinned:  return String(localized: "What you pinned")
        case .folders: return String(localized: "Your folders")
        case .new:     return String(localized: "Write a note")
        }
    }

    /// The tiles that SCOPE the list; New is a verb and never stands.
    var isVerb: Bool { self == .new }
}
