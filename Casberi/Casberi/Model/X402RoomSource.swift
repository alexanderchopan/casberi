import Foundation

/// Feeds `X402Room` from stored bridge state (2026-08-06).
///
/// The thinnest of the room sources, and deliberately so: unlike Stripe's or
/// PostHog's, this head reads NOTHING out of the corpus. Everything it draws —
/// who sells, how many services, what a call costs — is what the last walk saw,
/// and none of it is a property of any single landed row.
///
/// It still takes `things`, for one reason: the head must not draw over a room
/// whose rows aren't there. A person who connected, walked, and then removed
/// the landed rows would otherwise keep a card describing a marketplace their
/// feed no longer shows.
enum X402RoomSource {

    @MainActor
    static func compose(things: [Thing]) -> X402Room? {
        // Filtered live at the BOUNDARY before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot.
        let landed = things.live.contains { $0.source == X402Ingest.source }
        guard landed else { return nil }
        return X402Room.compose(sellers: X402State.sellers, listings: X402State.listings)
    }
}
