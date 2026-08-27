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
            if pieces.isEmpty {
                emptyNote
            } else {
                strip
            }
        }
        // BARE ON THE PAGE (§483: *"we don't do cards"*), and NO HEADER: the
        // scope chip directly below already says "NFTs" and the rows below
        // that name every collection, so a title here is the third voice
        // §447 recorded — a card opening with two display lines and then a
        // drawing repeating the header word for word.
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
        let shown = Array(pieces.prefix(Self.quadCap))
        return HStack(spacing: DS.Space.s2) {
            ForEach(shown) { piece in
                quadCell(piece)
            }
        }
        // **PIECES, NOT COLLECTION COVERS (prd §493, correcting §483's own
        // quad).** This shelf has shown INDIVIDUAL NFTs since it existed —
        // `WalletNFTShelf.pieceCap` fetches 24 and the old strip drew them —
        // and grouping them by collection for the quad silently reduced the
        // room to one cover per contract. The demo made it look intentional:
        // `demoCollections` seeds exactly two, so a grouped quad could only
        // ever draw two cells, which read as "the demo is thin" rather than
        // "the drawing is wrong".
        //
        // The pick model is UNTOUCHED and needs no amendment: §387 picks a
        // CONTRACT ("show my Squiggles"), and what is DISPLAYED is the pieces
        // those picks bring back. Pick by collection, show the art.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSRoomChassis.inset)
    }

    /// Which chain a piece lives on, in a word — the one fact a row can add
    /// that neither its name nor its collection carries.
    static func chainWord(_ piece: WalletNFTShelf.NFTPiece) -> String {
        let raw = piece.chainPath.isEmpty ? piece.network : piece.chainPath
        return raw
            .replacingOccurrences(of: "-mainnet", with: "")
            .replacingOccurrences(of: "eth", with: "Ethereum")
            .capitalized
    }

    /// How many pieces the fixed slot draws.
    ///
    /// **A DISPLAY cap, so the list below must carry the rest** — the pick is
    /// unlimited and the fetch returns up to `WalletNFTShelf.pieceCap` (24), so
    /// a quad that simply stopped at four would drop twenty pieces with nothing
    /// saying so (§307's silent-truncation class). `WalletNFTCollectionRows`
    /// lists every piece that came back.
    private static let quadCap = 4

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

    /// One quarter of the quad. The door is the piece's own OpenSea page.
    @ViewBuilder
    private func quadCell(_ piece: WalletNFTShelf.NFTPiece) -> some View {
        // A piece on a chain OpenSea doesn't list (Robinhood) has no door, so
        // it draws as a picture and not as a control — §83, and §275
        // specifically: a verb that looks live and lands nowhere is worse than
        // no verb.
        if let url = piece.openSeaURL {
            Button { openURL(url) } label: { quadArt(piece) }
                // The photograph register (§384) — a picture lifts.
                .buttonStyle(PressLift())
        } else {
            quadArt(piece)
        }
    }

    /// The slot's height, spent on art. Spelled rather than measured for
    /// `walletVisualSlot`'s own reason: a measured height settles a frame late,
    /// which is the same jump arriving slower.
    private static let coverSide: CGFloat = 150

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
        .frame(maxWidth: .infinity)
        .frame(height: Self.coverSide)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .accessibilityLabel(Text(piece.collection))
    }

}

/// EVERY PIECE THE SHELF HOLDS (prd §493, was the collections behind the quad).
///
/// The scope's list half, and the reason the quad may cap at four: the pick is
/// unlimited and `WalletNFTShelf.pieceCap` fetches up to 24, so a drawing that
/// stopped at four would drop twenty pieces with nothing saying so — §307's
/// silent-truncation class. This lists every piece that came back.
///
/// **There is no price column and there will not be one.** §387 refused a floor
/// price and §481 refused it again, on the same ground — a floor is a bid on
/// the thinnest book in this app, it moves without you, and a number people
/// believe (§83) does not belong beside art somebody keeps for reasons that are
/// not the number. `WalletNFTShelf` stores no value anywhere, so there is
/// nothing here to round.
///
/// What a row CAN say is all real and already stored: the piece's own name, the
/// collection it belongs to, and the chain it lives on. A "1 of N" would need
/// the collection's total supply, which `NFTCollection.count` does NOT carry —
/// that field is how many of them THIS WALLET holds, and printing it as an
/// edition size would be a confident wrong answer about somebody's art.
struct WalletNFTCollectionRows: View {
    let wallet: String
    var onEdit: () -> Void

    @ObservedObject private var picks = WalletNFTStore.shared
    @Environment(\.openURL) private var openURL

    @State private var pieces: [WalletNFTShelf.NFTPiece] = []

    private var demo: Bool { DemoMode.isActive }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(pieces) { piece in
                row(piece)
            }
            // The way back into the picker. Under the list rather than in a
            // header, because the quad above already carries the scope's
            // heading and a second one here would be §447's two stacked
            // display lines.
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
    private func row(_ piece: WalletNFTShelf.NFTPiece) -> some View {
        let body = HStack(spacing: DS.Space.s3) {
            art(piece)
            VStack(alignment: .leading, spacing: 1) {
                Text(piece.name)
                    .dsText(.heading17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(piece.collection)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Text(WalletNFTShelfCard.chainWord(piece))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if piece.openSeaURL != nil {
                Image(systemName: "chevron.right")
                    .dsGlyph(11)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.vertical, DS.Space.s2)
        if let url = piece.openSeaURL {
            Button { openURL(url) } label: { body.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .dsHover()
        } else {
            body
        }
    }

    /// The piece at row scale — the same art the quad shows, so a row and the
    /// quarter above are visibly the same NFT.
    @ViewBuilder
    private func art(_ piece: WalletNFTShelf.NFTPiece) -> some View {
        Group {
            if let seed = piece.demoSeed {
                DemoNFTArt(seed: seed)
            } else {
                RemoteThumb(urlString: piece.imageURL, size: 56)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}
