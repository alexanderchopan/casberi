import Foundation
import SwiftData

/// The `Thing` and store half of `SocialRoom` (prd §489, 2026-08-26) —
/// everything the judgement half deliberately cannot see.
///
/// The house split (`StripeRoom`/`StripeRoomSource`, `PeerRoom`/`PeerRoomSource`
/// and every room head since): the rules are Foundation-only so a harness can
/// compile them whole and mutation-prove each source, and the lookups that touch
/// SwiftData and the network stores live here, where there is no judgement to
/// test — only reads.
enum SocialRoomSource {

    // MARK: - The rail's accounts

    /// The watched accounts behind a social room, dispatched ONCE.
    ///
    /// **This function is the fix, not a tidy-up.** Before it there were three
    /// dispatches and they disagreed: `FeedScreen.rosterAccounts` was a
    /// `source == "Farcaster" ? FarcasterStore : BlueskyStore` ternary — so any
    /// third network would have been handed BLUESKY's watched accounts, a rail
    /// of the wrong faces, ringed by the wrong freshness, filtering to handles
    /// that match nothing — `MainSurface.socialAccounts` was a two-case switch
    /// that failed closed (so Nostr's rail simply never drew), and
    /// `HandleSetupScreen` had the complete three-case version all along. The
    /// setup screen knew about Nostr; the room did not.
    ///
    /// Read straight off the network's own store — no corpus walk, because
    /// `MainSurface.topInset` evaluates this on every body pass and is already
    /// that surface's most expensive property.
    ///
    /// A source with no roster answers EMPTY rather than trapping: the rail
    /// gates on `SocialRoom.hasRoster` first, and a second answer here that
    /// disagreed would be the same drift one level down.
    @MainActor
    static func accounts(for source: String) -> [SocialAccount] {
        guard SocialRoom.hasRoster(source) else { return [] }
        switch source {
        case "Farcaster": return FarcasterStore.shared.socialAccounts
        case "Bluesky":   return BlueskyStore.shared.socialAccounts
        case "Nostr":     return NostrStore.shared.socialAccounts
        default:          return []
        }
    }

    // MARK: - A row, as the rules see it

    /// A `Thing` reduced to the facts `SocialRoom.rowKind` decides from.
    ///
    /// Liveness: reads stored properties, so every caller must already hold a
    /// live model — which `shapedRow` and `standsAlone` both do, each guarding
    /// before it reaches here (see the SwiftData corollaries in CLAUDE.md).
    ///
    /// `previewImageData != nil` is the one heavy column touched, and it is
    /// touched because the anatomy genuinely turns on it: an Instagram picture
    /// post whose thumbnail never landed must draw the band rather than a post
    /// card whose entire body is the placeholder word "Photo". Every other
    /// field here is light or already faulted by the room's own query.
    static func rowFacts(_ thing: Thing) -> SocialRoom.RowFacts {
        SocialRoom.RowFacts(
            source: thing.source,
            kind: thing.kind.rawValue,
            tags: thing.tags,
            isImportReceipt: Corpus.isImportReceipt(thing),
            arrivedLive: Corpus.arrivedLive(thing),
            hasPostText: (thing.postText?.isEmpty == false),
            hasPreviewImage: thing.previewImageData != nil,
            socialContext: thing.socialContext)
    }

    /// What anatomy this row wears. The one entry point the feed calls.
    static func rowKind(_ thing: Thing, hasReplies: Bool = false) -> SocialRoom.RowKind {
        SocialRoom.rowKind(rowFacts(thing), hasReplies: hasReplies)
    }

    /// Whether this row draws on a card of its own.
    ///
    /// `hasReplies: false` deliberately: a thread head is a card with or
    /// without its continuations folded in, so the answer cannot turn on it,
    /// and asking would mean threading the fold's dictionary through a function
    /// the run layout calls for every row on every scroll.
    static func standsAlone(_ thing: Thing) -> Bool {
        rowKind(thing).standsAlone
    }

    /// Whether a day's rows may be called POSTS — see `SocialRoom.groupIsPosts`.
    static func groupIsPosts(_ things: [Thing]) -> Bool {
        SocialRoom.groupIsPosts(things.map(rowFacts))
    }
}
