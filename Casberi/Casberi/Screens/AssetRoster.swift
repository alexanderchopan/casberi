import SwiftUI

// THE SHELF IS GONE, THE SLOT SURVIVES (prd §639, 2026-09-06).
//
// `AssetRosterShelf`, `AssetRosterAddSlot` and `TickerDisc` were the horizontal
// roster four watch-list screens drew — Tokens, Stocktwits, PostHog, L2BEAT,
// Walletbeat — under a caption that coached its own gestures ("Watching 5 ·
// hold to unwatch"). Every one of those seats is an account page now, and the
// page has ONE roster: a vertical list with a swipe, a Mac-mirroring
// right-click, and one verb. Two roster shapes for one job is what §639 was
// called for.
//
// The SLOT stays because `PostHogRoomCard` draws it in the ROOM, which is a
// different surface with a different job: a horizontal strip of metric discs
// above the rows they summarise.

/// One asset on the shelf: its round mark, its short name, and — when the
/// price is known — the live figure over a signed delta. Purely visual; the
/// screen attaches the tap and the long-press menu, so Tokens and Stocktwits
/// can offer different verbs over one anatomy.
///
/// A missing price renders NOTHING rather than a placeholder: an unreachable
/// quote is a fact we don't have, and a dash in the price slot reads like a
/// number (the honesty rule). Flat changes carry no direction — that's
/// `TokenDeltaPill`'s own rule, inherited here.
struct AssetRosterSlot<Mark: View>: View {
    let label: String
    var price: Double? = nil
    var change: Double? = nil
    @ViewBuilder var mark: () -> Mark

    static var markSize: CGFloat { 56 }
    static var slotWidth: CGFloat { 76 }

    var body: some View {
        VStack(spacing: 6) {
            mark()
                .frame(width: Self.markSize, height: Self.markSize)
            VStack(spacing: 2) {
                Text(label)
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if let price {
                    Text(TokenChartStyle.priceText(price))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                if let change {
                    TokenDeltaPill(change: change, label: "", compact: true)
                }
            }
            .frame(minHeight: 52, alignment: .top)
        }
        .frame(width: Self.slotWidth)
        .contentShape(Rectangle())
        // The slot IS the tap target (the screen attaches the gesture), so the
        // hover belongs here rather than on the mark inside it — one lift for
        // whichever verb the host hangs on it.
        .dsHover()
    }
}


