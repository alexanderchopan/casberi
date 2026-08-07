import Foundation

/// Feeds `X402Room` from stored bridge state (2026-08-06).
///
/// The thinnest of the room sources, and deliberately so: unlike Stripe's or
/// PostHog's, this head reads NOTHING out of the corpus. Everything it draws —
/// who sells, how many services, what a call costs — is what the last walk saw,
/// and none of it is a property of any single landed row.
///
/// It still takes `things`, for two reasons. The head must not draw over a room
/// whose rows aren't there; and when the lane strip narrows the room, the head
/// has to narrow with it — a card saying "22 companies" above two filtered rows
/// is two surfaces disagreeing on one screen.
enum X402RoomSource {

    @MainActor
    static func compose(things: [Thing], lane: String? = nil) -> X402Room? {
        // Filtered live at the BOUNDARY before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot.
        let live = things.live.filter { $0.source == X402Ingest.source }
        guard !live.isEmpty else { return nil }

        let all = X402State.sellers
        guard let lane else {
            // Unscoped: the walk's own totals. `listings` is the marketplace
            // size and `medianPrice` a true median over every priced listing.
            return X402Room.compose(sellers: all, listings: X402State.listings,
                                    typical: X402State.medianPrice)
        }

        // Scoped: only the sellers actually on screen, matched by the ref the
        // rows carry rather than by re-reading their lanes — so the head can
        // never disagree with the rows about who is in this lane.
        let refs = Set(live.compactMap(\.sourceRef))
        let shown = all.filter { refs.contains("x402:" + $0.slug) }
        // A MEDIAN OF SELLER MEDIANS, and it is worth being plain about that:
        // the true median for a lane would need every listing's price, and
        // storing 310 of them per seller to answer one line is not a trade
        // worth making. Each seller's own median is a real central value, so
        // the middle of those is a fair "what a typical seller here typically
        // charges" — which is exactly the softness the word "typically" claims,
        // and no more.
        let typical = X402Ingest.median(shown.compactMap(\.median))
        return X402Room.compose(sellers: shown,
                                listings: shown.reduce(0) { $0 + $1.services },
                                typical: typical, lane: lane)
    }
}
