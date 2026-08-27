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

    /// **A QUAD OF FOUR COLLECTIONS, one cover each** (2026-08-26, prd §483 —
    /// user: *"the chart is four large NFTs in a quad b/c they can pick four
    /// to show"*, then *"it can be a quad of the collections"*).
    ///
    /// Four COLLECTIONS rather than four pieces, which is what keeps §387's
    /// pick unit intact: a pick names a contract, never a token id, because
    /// *"show my Squiggles" is a sentence someone means* and picking three
    /// specific tokens out of a collection is filing. So the quad shows the
    /// picks themselves, and the cover is simply the first piece that came
    /// back for each — the shelf's own read, grouped, with no second fetch and
    /// no new stored state.
    ///
    /// **Four, and the fifth is a count, never a scroll.** The strip this
    /// replaces scrolled horizontally inside a room that already scrolls
    /// vertically, so the pieces past the third were reachable only by a
    /// gesture nothing announced. A quad is the whole reading at once; if
    /// there are more collections than fit, the slot says so in words and the
    /// list directly below carries every one of them.
    private var strip: some View {
        let groups = coverGroups
        return VStack(spacing: DS.Space.s2) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: DS.Space.s2) {
                    ForEach(0..<2, id: \.self) { col in
                        let i = row * 2 + col
                        if i < groups.count {
                            quadCell(groups[i])
                        } else {
                            // An absent quarter is EMPTY, never a placeholder
                            // tile: a grey square where art goes reads as a
                            // picture that failed to load, which is the one
                            // thing a shelf must not say about somebody's own
                            // collection.
                            Color.clear
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, DS.Space.s4)
    }

    /// One cover per PICKED COLLECTION, in the order the pieces came back, up
    /// to four. Grouped rather than fetched: `pieces` is already the shelf's
    /// cached read for exactly this pick book.
    private var coverGroups: [(collection: String, cover: WalletNFTShelf.NFTPiece, count: Int)] {
        var order: [String] = []
        var byCollection: [String: [WalletNFTShelf.NFTPiece]] = [:]
        for piece in pieces {
            if byCollection[piece.collection] == nil { order.append(piece.collection) }
            byCollection[piece.collection, default: []].append(piece)
        }
        return order.compactMap { name in
            guard let held = byCollection[name], let cover = held.first else { return nil }
            return (name, cover, held.count)
        }
    }

    /// One quarter of the quad. The door is the COVER's OpenSea page — the
    /// nearest honest destination, since a collection's own page is a market
    /// listing and this app has never claimed to price these (§387).
    @ViewBuilder
    private func quadCell(_ group: (collection: String, cover: WalletNFTShelf.NFTPiece, count: Int)) -> some View {
        // A piece on a chain OpenSea doesn't list (Robinhood) has no door, so
        // it draws as a picture and not as a control — §83, and §275
        // specifically: a verb that looks live and lands nowhere is worse than
        // no verb.
        if let url = group.cover.openSeaURL {
            Button { openURL(url) } label: { quadArt(group.cover) }
                // The photograph register (§384) — a picture lifts.
                .buttonStyle(PressLift())
        } else {
            quadArt(group.cover)
        }
    }

    @ViewBuilder
    private func quadArt(_ piece: WalletNFTShelf.NFTPiece) -> some View {
        Group {
            if let seed = piece.demoSeed {
                // The demo's pieces are drawn, not loaded — generated art,
                // never a real collection's work (prd §387).
                DemoNFTArt(seed: seed)
            } else {
                RemoteThumb(urlString: piece.imageURL, size: Self.tile)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .accessibilityLabel(Text(piece.collection))
    }

}

/// THE COLLECTIONS BEHIND THE QUAD, one row each (2026-08-26, prd §483).
///
/// The scope's list half. Its sibling above draws four covers; this names
/// every picked collection, including the ones the quad had no room for —
/// which is what lets the quad cap at four without hiding anything.
///
/// **There is no price column and there will not be one.** §387 refused a
/// floor price and §481 refused it again, both for the same reason: a floor is
/// a bid on the thinnest book in this app, it moves without you, and a number
/// people believe (§83) does not belong beside art somebody keeps for reasons
/// that are not the number. `WalletNFTShelf` stores no value anywhere, so
/// there is nothing here to round — the row says what it is, how many of it
/// this wallet holds, and where to go.
struct WalletNFTCollectionRows: View {
    let wallet: String
    var onEdit: () -> Void

    @ObservedObject private var picks = WalletNFTStore.shared
    @Environment(\.openURL) private var openURL

    @State private var pieces: [WalletNFTShelf.NFTPiece] = []

    private var demo: Bool { DemoMode.isActive }

    /// Every picked collection with something to show, held-count first seen
    /// order — the same grouping the quad makes, so the two halves can never
    /// list a different set.
    private var groups: [(collection: String, cover: WalletNFTShelf.NFTPiece, count: Int)] {
        var order: [String] = []
        var byCollection: [String: [WalletNFTShelf.NFTPiece]] = [:]
        for piece in pieces {
            if byCollection[piece.collection] == nil { order.append(piece.collection) }
            byCollection[piece.collection, default: []].append(piece)
        }
        return order.compactMap { name in
            guard let held = byCollection[name], let cover = held.first else { return nil }
            return (name, cover, held.count)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.collection) { group in
                row(group)
            }
            // The way back into the picker. It sits UNDER the list rather than
            // in a header, because the quad above already carries the scope's
            // heading and a second one here would be the two-display-lines
            // failure §447 recorded.
            if !demo {
                Button(action: onEdit) {
                    Text(String(localized: "Choose collections"))
                        .dsText(.subhead13).fontWeight(.medium)
                        .foregroundStyle(DS.tint)
                        .padding(.vertical, DS.Space.s3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
            }
        }
        .task(id: taskKey) { await load() }
    }

    /// Both the wallet AND the pick signature — the sibling card's own reason:
    /// a pick removed and another added in one sitting leaves a count
    /// unchanged.
    private var taskKey: String {
        "\(wallet)|\(picks.book.picks(wallet: wallet).sorted().joined(separator: ","))"
    }

    private func load() async {
        guard demo || picks.hasPicks(wallet: wallet) else {
            pieces = []
            return
        }
        pieces = await WalletNFTShelf.pieces(for: wallet, book: picks.book)
    }

    @ViewBuilder
    private func row(_ group: (collection: String, cover: WalletNFTShelf.NFTPiece, count: Int)) -> some View {
        let body = HStack(spacing: DS.Space.s3) {
            mark(group.cover)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.collection)
                    .dsText(.heading17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(group.count == 1
                     ? String(localized: "1 piece")
                     : String(localized: "\(group.count) pieces"))
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            }
            Spacer(minLength: 0)
            if group.cover.openSeaURL != nil {
                Image(systemName: "chevron.right")
                    .dsGlyph(11)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.vertical, DS.Space.s2)
        if let url = group.cover.openSeaURL {
            Button { openURL(url) } label: { body.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .dsHover()
        } else {
            body
        }
    }

    /// The collection's cover at row scale — the same art the quad shows, so
    /// the row and the quarter above are visibly the same collection.
    @ViewBuilder
    private func mark(_ piece: WalletNFTShelf.NFTPiece) -> some View {
        Group {
            if let seed = piece.demoSeed {
                DemoNFTArt(seed: seed)
            } else {
                RemoteThumb(urlString: piece.imageURL, size: DS.Face.list)
            }
        }
        .frame(width: DS.Face.list, height: DS.Face.list)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}
