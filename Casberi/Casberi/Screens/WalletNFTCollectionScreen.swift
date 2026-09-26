import SwiftUI

/// **ONE PICKED COLLECTION, ITS PIECES THREE ACROSS (prd §943).**
///
/// The door on each collection row under the NFTs crown. The list names what
/// you chose — the collection — and this is where its art has room: the
/// Photos grid's size, square cells, and a piece opens its own OpenSea page.
/// A piece on a chain OpenSea does not list draws as a picture and not as a
/// control (§83, §275).
///
/// Holds no `Thing`: an NFT is a door, not a corpus row (§72), so the
/// SwiftData liveness corollaries do not apply. It re-reads the shelf's own
/// cached pieces and keeps the ones from this contract.
struct WalletNFTCollectionScreen: View {
    let wallet: String
    /// The collection's key, `WalletNFTCollectionRows.key`.
    let collection: String
    let name: String

    @ObservedObject private var picks = WalletNFTStore.shared
    @Environment(\.openURL) private var openURL
    @State private var pieces: [WalletNFTShelf.NFTPiece] = []

    private static let gap: CGFloat = 2
    private static let columns = 3

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap),
                                         count: Self.columns),
                          spacing: Self.gap) {
                    ForEach(pieces) { piece in
                        cell(piece)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
                .listRowInsets(EdgeInsets(top: DS.Space.s3, leading: DSRoomChassis.inset,
                                          bottom: DS.Space.s3, trailing: DSRoomChassis.inset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle(name)
        .task(id: wallet + collection) { await load() }
    }

    private func load() async {
        let all = await WalletNFTShelf.pieces(for: wallet, book: picks.book)
        pieces = all.filter { WalletNFTCollectionRows.key($0) == collection }
    }

    @ViewBuilder
    private func cell(_ piece: WalletNFTShelf.NFTPiece) -> some View {
        // A square that takes its column's width; the art fills it.
        let art = Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { WalletNFTArt(piece: piece, side: nil) }
            .clipped()
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(Text(piece.name))
        if let url = piece.openSeaURL {
            Button { openURL(url) } label: { art }
                .buttonStyle(PressLift())
        } else {
            art
        }
    }
}
