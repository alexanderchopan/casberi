import SwiftUI

/// THE NFT SHELF (2026-08-15, prd §387) — the picked collections, drawn.
///
/// Sits directly under the holdings treemap in the Wallet room, which is where
/// §124a put it and where it belongs: the treemap says what you hold that is
/// fungible, this says what you hold that isn't, and the two together are one
/// "what you hold" pair before the room changes the subject to risk, lending
/// and who can reach your money.
///
/// It was deliberately NOT placed just above the transactions, the other
/// candidate. Five cards deep, below the approvals card and the coming-up
/// deadlines, a picture strip reads as an afterthought — decorative content
/// filed after the needs-you cards — and sits where nobody scrolls.
///
/// ## Two states, and the first one is the common one
///
/// Most wallets will never pick anything, so the resting state is a single
/// quiet line rather than a card. It appears ONLY when the wallet actually
/// holds collections we could show (§83: no dead controls — an invitation to
/// show NFTs on a wallet holding none is a control that can't do anything), and
/// that test is free, since it reads the same cached bytes the wallet refresh
/// already fetched.
///
/// ## Liveness
///
/// Holds no `Thing`. An NFT is a door, not a corpus row (§72) — nothing here
/// lands, so none of the SwiftData liveness corollaries apply and there is no
/// CloudKit field behind any of it.
struct WalletNFTShelfCard: View {
    let wallet: String
    let label: String
    /// Opens the picker. Routed OUT rather than presented here: a `.sheet` on a
    /// view inside the feed's List resolves to the same presenting controller
    /// as the screen's own sheet, which is the half-open-then-close bug
    /// (ruling 2026-07-28). One screen, one presentation.
    var onEdit: () -> Void

    @ObservedObject private var picks = WalletNFTStore.shared
    @Environment(\.openURL) private var openURL

    @State private var pieces: [WalletNFTShelf.NFTPiece] = []
    @State private var loading = false

    private static let tile: CGFloat = 116

    /// The demo shows the shelf and NOT the picker (user's ruling, prd §387).
    ///
    /// A picker there would be a control over invented collections — it would
    /// work, and it would teach a decision that evaporates when the demo does.
    /// The tour's job is to show what the room looks like furnished; choosing
    /// what is in it is a thing you do with your own wallet.
    private var demo: Bool { DemoMode.isActive }

    /// The card is only MOUNTED when the room has already decided there is
    /// something to say (`FeedScreen.walletNFTSection`), so this chooses between
    /// the shelf and the invitation — never between something and nothing.
    var body: some View {
        Group {
            if demo || picks.hasPicks(wallet: wallet) {
                shelf
            } else {
                invitation
            }
        }
        // Re-reads when the picks change, so a tap in the picker paints here
        // rather than on the next room open.
        .task(id: taskKey) { await load() }
    }

    /// Both the wallet AND the pick signature, so picking a new collection
    /// re-runs this. Keyed on the picks themselves rather than a counter — a
    /// pick removed and another added in one sitting leaves a count unchanged.
    private var taskKey: String {
        "\(wallet)|\(picks.book.picks(wallet: wallet).sorted().joined(separator: ","))"
    }

    private func load() async {
        // The demo's shelf is independent of the pick book — it has no picker,
        // so `hasPicks` is false there and would otherwise skip the read.
        guard !demo else {
            pieces = await WalletNFTShelf.pieces(for: wallet, book: picks.book)
            return
        }
        // Nothing picked means nothing to fetch — the invitation needs no read,
        // and this is the case where the feature costs literally nothing.
        guard picks.hasPicks(wallet: wallet) else {
            pieces = []
            return
        }
        loading = pieces.isEmpty
        pieces = await WalletNFTShelf.pieces(for: wallet, book: picks.book)
        loading = false
    }

    // MARK: - The resting state

    /// One line, not a card. A wallet whose owner does not care about NFTs
    /// should not be handed a picture-shaped hole in the middle of its room.
    private var invitation: some View {
        Button(action: onEdit) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "square.grid.2x2")
                    .dsGlyph(15, weight: .medium)
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityHidden(true)
                Text(String(localized: "Show NFTs from \(label)"))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, DS.Space.s4)
        }
        .buttonStyle(PressSpring())
    }

    // MARK: - The shelf

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if pieces.isEmpty {
                emptyNote
            } else {
                strip
            }
        }
        .padding(.vertical, WalletCardStyle.pad)
        // Was the room's only opaque card, which made the NFT shelf the
        // brightest object on a screen where a liquidation axis sits two cards
        // above it (2026-08-22). One fill for every card in the room.
        .dsWidgetSurface(fillOpacity: WalletCardStyle.fill)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "NFTs"))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textTertiary)
                Text(headline)
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
            }
            Spacer(minLength: 0)
            // The way back into the picker — the shelf is the only place the
            // decision is visible, so it is the only honest place to change it.
            // Absent in the demo, which has no picks to edit.
            if !demo {
                Button(action: onEdit) {
                    Text(String(localized: "Edit"))
                        .dsText(.subhead13).fontWeight(.medium)
                        .foregroundStyle(DS.tint)
                }
                .buttonStyle(PressSpring())
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }

    /// States the COLLECTION count, never a valuation.
    ///
    /// No floor price anywhere on this card, deliberately: a floor is a bid on
    /// the thinnest book in this app, it moves without you, and printing one
    /// would put a number people believe (§83) beside art somebody keeps for
    /// reasons that aren't the number. The wallet's crown total is unchanged by
    /// this feature for the same reason — §240's ruling that the composition
    /// strip makes no claim about the total holds here too.
    private var headline: String {
        // The demo counts the collections actually on the shelf, since it has
        // no pick book to count.
        let n = demo
            ? Set(pieces.map(\.collection)).count
            : picks.book.picks(wallet: wallet).count
        return n == 1
            ? String(localized: "1 collection")
            : String(localized: "\(n) collections")
    }

    /// Picked, but nothing came back — a real state with three causes (the read
    /// failed, the pieces have no artwork we can draw, or they were moved out
    /// since the pick). Said plainly rather than left as a blank card, which
    /// would read as a broken shelf.
    private var emptyNote: some View {
        Text(loading
             ? String(localized: "Loading…")
             : String(localized: "Nothing to draw from these collections yet."))
            .dsText(.subhead13)
            .foregroundStyle(DS.textTertiary)
            .padding(.horizontal, DS.Space.s4)
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(pieces) { piece in
                    // A piece on a chain OpenSea doesn't list (Robinhood) has
                    // no door, so it draws as a picture and not as a control —
                    // §83, and §275 specifically: a verb that looks live and
                    // lands nowhere is worse than no verb.
                    if let url = piece.openSeaURL {
                        Button { openURL(url) } label: {
                            tile(piece)
                        }
                        // The photograph register (§384) — a picture lifts.
                        .buttonStyle(PressLift())
                    } else {
                        tile(piece)
                    }
                }
            }
            .padding(.horizontal, DS.Space.s4)
            // The lift overshoots the tile, so the strip needs room to grow
            // into or a pressed edge tile is clipped by its own scroll view.
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func tile(_ piece: WalletNFTShelf.NFTPiece) -> some View {
        if let seed = piece.demoSeed {
            // The demo's pieces are drawn, not loaded — generated art, never a
            // real collection's work (prd §387).
            DemoNFTArt(seed: seed)
                .frame(width: Self.tile, height: Self.tile)
                .accessibilityLabel(Text(piece.name))
        } else {
            RemoteThumb(urlString: piece.imageURL, size: Self.tile)
                .accessibilityLabel(Text(piece.name))
        }
    }
}
