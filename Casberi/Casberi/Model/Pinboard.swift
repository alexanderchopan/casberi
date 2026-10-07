import Foundation
import SwiftData

/// THE NOTES ROOM — the notes you wrote (prd §969, 2026-09-28). It held
/// what you pinned too until prd §1175 deleted Pin (user: "why don't we just
/// get rid of pinning, seems superfluous … it just creates another list when
/// a person could go where the thing is"); the name `Pinboard` is history.
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
/// **Storage** is `source == "You"` with `kind == .note` (or `.voice`),
/// which is exactly what a note shared in from Apple Notes already lands as
/// (§230a), so the room reaches those too. `Thing.pinnedAt` is unread.
enum Pinboard {

    /// The door's label, and the sentinel `FeedFilter.source` takes when the
    /// room is showing. Spelled ONCE here and compared through `isPinnedRoom`
    /// everywhere else — a literal repeated across the tray, the pager, the
    /// query and the empty state is four chances to disagree, and the room
    /// silently renders the wrong page when they do (the `TabView`
    /// unmatched-selection trap `MainSurface` documents where `feedLabels`
    /// used to live). The name stays `isPinnedRoom` at every call site: the
    /// sentinel changed, the seventy tests of it did not.
    ///
    /// **NOT the word the door draws.** §969 spelled the sentinel `"Notes"`,
    /// and `"Notes"` is also a catalog CATEGORY (Apple Notes, Obsidian, Day
    /// One, Apple Journal) — and, through `BridgeCatalog`'s vendor-prefix
    /// alias, the SOURCE that resolves to the Apple Notes seat. So the tray's
    /// Notes door sent a string `go(to:)` read as a folded category chip and
    /// resolved to that category's venues (none present → nothing happened),
    /// and `CategoryFold.foldAll` swallowed the room's own page into the
    /// category's chip. The tray's You-row door and its Notes CATEGORY row
    /// sent the very same string, so no guard downstream could tell them
    /// apart; the sentinel had to change (2026-09-28, user: "the notes
    /// button doesn't activate when tapping it in the tray"). The label the
    /// door and the room draw is `String(localized: "Notes")`, spelled where
    /// it is drawn; this string reaches no screen. `category-fold-selftest.sh`
    /// holds it clear of every category name and every offer's alias.
    static let room = "Your notes"

    static func isPinnedRoom(_ source: String) -> Bool { source == room }

    // MARK: - Membership

    /// A note you wrote — or shared in, or dictated as text — or SPOKE (prd
    /// §971, a voice thing the note sheet recorded): your own source, the
    /// note or voice kind. The room's one membership since Pin went (§1175).
    static func isNote(_ thing: Thing) -> Bool {
        thing.source == "You" && (thing.kind == .note || thing.kind == .voice)
    }

    /// Whether the room holds this thing: a note of yours. The `@Query`
    /// fetches `source == "You"` (a kind cannot be predicated), and this is
    /// the half the predicate could not say.
    static func inRoom(_ thing: Thing) -> Bool { isNote(thing) }

    /// File a thing in a folder, or take it out with nil (prd §980). A model
    /// write and nothing else, so it is legal from the row's menu. One folder
    /// at most: filing again MOVES it.
    @MainActor
    static func file(_ thing: Thing, in folder: String?) {
        guard thing.isLive else { return }
        thing.folder = folder
    }
}

/// The Notes room's tiles (prd §969, §972, §980, §1099): All · Folders ·
/// New · Search. All is lit by default and first, as in every room; New and
/// Search are VERBS — they never light, and they stand last, A–Z among
/// themselves (§995, §1039). New raises the note page; Search raises the find
/// tray over your notes.
///
/// **Pinned left the row (prd §1099).** §983 put Pinned at the head of All
/// under its own name, so the tile showed a list All already led with — the
/// slot went to Search, the one verb a notes app is for that this room did
/// not have (Reading, Social and Markets got theirs in §1081–§1086).
///
/// **Folders is back, with folders behind it (prd §980).** §972 deleted the
/// tile because §969 drew it before the feature: it lit and showed the same
/// list as All, §83's dead control. Now it lights onto the folder list
/// (`NoteFolderName`), a folder opens in the room, and a row files from its
/// long press.
///
/// Foundation-only, like every scope enum, so a harness can compile it
/// whole; the glyphs are `ScopeTileGlyphs.swift`'s.
enum NotesScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Voice (prd §1127) took the title row's Notes · Voice notes pill when
    /// Home's You pill took the title row: the voice notes you spoke. Search
    /// is deleted (prd §1171): the tray's search finds your notes.
    case all, folders, voice, new

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:     return String(localized: "All")
        case .folders: return String(localized: "Folders")
        case .voice:   return String(localized: "Voice")
        case .new:     return String(localized: "New")
        }
    }

    /// Read by VoiceOver and the tooltip.
    var summary: String {
        switch self {
        case .all:     return String(localized: "Your notes")
        case .folders: return String(localized: "What you filed")
        case .voice:   return String(localized: "What you recorded")
        case .new:     return String(localized: "Write or record a note")
        }
    }

    /// The tiles that SCOPE the list; New is a verb and never stands.
    var isVerb: Bool { self == .new }
}
