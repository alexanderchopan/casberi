import SwiftUI

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
    /// Opens a collection's pieces (prd §943) — routed out, one screen one
    /// presentation. Handed the collection's key and its name.
    var onOpen: ((String, String) -> Void)? = nil

    @ObservedObject private var picks = WalletNFTStore.shared

    @State private var pieces: [WalletNFTShelf.NFTPiece] = []

    private var demo: Bool { DemoMode.isActive }

    /// **ONE ROW PER COLLECTION, THE UNIT YOU PICKED (prd §943, amending
    /// §493).** The list under the crown named every piece — the crown's own
    /// art again, three lines each. It names what you chose instead: the
    /// collection, its first piece as the mark, and nothing under the name
    /// (user: "collection name is fine"). The pieces are one tap in.
    struct Collection: Identifiable {
        let id: String
        let name: String
        let first: WalletNFTShelf.NFTPiece
    }

    /// In the order the pieces came back, first sighting of each collection.
    /// Keyed on the contract AND the name: the demo's pieces share one
    /// placeholder contract, and one contract can mint under two names.
    static func collections(_ pieces: [WalletNFTShelf.NFTPiece]) -> [Collection] {
        var seen = Set<String>()
        var out: [Collection] = []
        for piece in pieces where seen.insert(key(piece)).inserted {
            out.append(Collection(id: key(piece), name: piece.collection, first: piece))
        }
        return out
    }

    static func key(_ piece: WalletNFTShelf.NFTPiece) -> String {
        "\(piece.contract.lowercased())|\(piece.collection)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.collections(pieces)) { collection in
                row(collection)
            }
            // The way back into the picker. Under the list rather than in a
            // header, because the quad above already carries the scope's
            // heading and a second one here would be §447's two stacked
            // display lines.
            if !demo {
                Button(action: onEdit) {
                    Text(String(localized: "Choose collections"))
                        .dsText(.subhead12)
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
    private func row(_ collection: Collection) -> some View {
        let body = HStack(spacing: DS.Space.s3) {
            WalletNFTArt(piece: collection.first, side: DS.Face.list)
                .clipShape(Circle())
                .accessibilityHidden(true)
            Text(collection.name)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if onOpen != nil { DSChevron() }
        }
        .padding(.vertical, DS.Space.s2)
        if let onOpen {
            Button {
                DSHaptic.selection()
                onOpen(collection.id, collection.name)
            } label: { body.contentShape(Rectangle()) }
                .buttonStyle(RowPress())
                .dsHover()
        } else {
            body
        }
    }
}

/// One piece's art at a given side — the demo's drawn art, or the piece's own
/// picture. Shared by the collection rows and the collection screen so the
/// mark and the grid are visibly the same NFT.
struct WalletNFTArt: View {
    let piece: WalletNFTShelf.NFTPiece
    /// A fixed side, or nil to fill whatever the container gives it.
    let side: CGFloat?

    var body: some View {
        Group {
            if let seed = piece.demoSeed {
                DemoNFTArt(seed: seed)
            } else {
                RemoteThumb(urlString: piece.imageURL, size: side ?? 240)
            }
        }
        .scaledToFill()
        .frame(width: side, height: side)
        .frame(maxWidth: side == nil ? .infinity : nil, maxHeight: side == nil ? .infinity : nil)
        .clipped()
    }
}
