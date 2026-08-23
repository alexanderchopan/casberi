import SwiftUI

/// The asset roster (prd §185) — the manager pattern's third dialect, after
/// the wallet's address roster (§182) and the social screens' people roster
/// (§184). A watched token or stock is an IDENTITY the same way a wallet or a
/// person is, so it wears the same shelf of circles: mark, name, and its one
/// live fact whispered underneath.
///
/// Ruling 2026-07-23 (user: "circles", then "why wouldn't we do the same
/// horizontal row treatment"): assets are round — a coin keeps its round art,
/// and a stock, which ships none, wears a round ticker disc rather than a
/// square tile or a faked logo. The mark grammar lands as **round is a person
/// or an asset, square is a topic** (a channel, a feed, a publication, a
/// contract glyph).
///
/// What the shelf costs, accepted with the ruling: the vertical price column
/// you could scan down, and the native list gestures. Comparison lives in the
/// feed's movers tile, which is the surface for reading; unwatching moves to
/// a long-press, which is the roster's own gesture everywhere else in the app.

/// The shelf itself — a horizontal band of slots with one quiet line under it
/// saying how many and how to work it. Matches the wallet/social rosters'
/// metrics so all three read as one shelf across the app.
struct AssetRosterShelf<Content: View>: View {
    /// "Watching 4 · tap for its chart, hold to unwatch" — the shelf states
    /// its own gestures, since a shelf can't show a swipe hint.
    let note: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s3) {
                    content()
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s1)
            }
            Text(note)
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .padding(.horizontal, DS.Space.s4)
        }
        .padding(.top, DS.Space.s1)
    }
}

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

/// The trailing slot — no cap on a watchlist, so this is an invitation rather
/// than the wallet's literal empty slot. It can't watch anything without a
/// query, so it focuses the omnibox above (the honest door).
struct AssetRosterAddSlot: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .strokeBorder(DS.textTertiary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .frame(width: AssetRosterSlot<EmptyView>.markSize,
                       height: AssetRosterSlot<EmptyView>.markSize)
                .overlay {
                    Image(systemName: "plus")
                        .dsGlyph(16)
                        .foregroundStyle(DS.textTertiary)
                }
            Text("Watch")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .frame(minHeight: 52, alignment: .top)
        }
        .frame(width: AssetRosterSlot<EmptyView>.slotWidth)
        .contentShape(Rectangle())
        .dsHover()
        .onTapGesture {
            DSHaptic.tap()
            action()
        }
        .dsTapCard()
    }
}

/// A stock's mark — the ticker itself, set in a round disc (prd §185). A
/// stock ships no logo, and inventing one (or borrowing a generic glyph that
/// says "stock") would be a mark that names nothing; the ticker IS the
/// symbol, so it stands as its own face. Long tickers ("BRK.B") shrink to
/// fit rather than truncate — a half-printed ticker names the wrong company.
struct TickerDisc: View {
    let ticker: String
    var size: CGFloat = 56

    /// The ".X" crypto suffix Stocktwits appends is spelling, not name — the
    /// disc shows "BTC", the way the row's title already says Bitcoin.
    private var shown: String {
        ticker.hasSuffix(".X") ? String(ticker.dropLast(2)) : ticker
    }

    var body: some View {
        Circle()
            .fill(DS.fillFaint)
            .frame(width: size, height: size)
            .overlay {
                Text(shown)
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, size * 0.12)
            }
    }
}
