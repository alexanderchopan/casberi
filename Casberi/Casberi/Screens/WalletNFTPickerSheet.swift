import SwiftUI

/// THE NFT PICKER (2026-08-15, prd §387) — which collections this wallet shows.
///
/// The whole feature's consent step: nothing is on the shelf until somebody
/// names it here, which is what bounds the recurring read (see
/// `WalletNFTShelf`'s header) and what keeps forty airdropped collections from
/// being the first thing you see in your own wallet.
///
/// ## What this screen deliberately does NOT do
///
/// **No junk fold.** Every collection the wallet holds is listed and every one
/// is pickable — the user's ruling ("i'd rather let user pick which nfts to
/// show than hide a bunch in 'junk'"). Alchemy's `isSpam` flag survives as
/// ORDER ALONE, never as a label and never as a filter: it is a third party's
/// guess, and printing it beside somebody's collection states a guess as a fact
/// (§83) on the one screen where they are deciding what they care about.
///
/// **Nothing preselected.** The follow-import ruling (§87): when the honest
/// alternative is a firehose, the person's taps decide, and a preselected list
/// is a mirror wearing a picker's clothes.
///
/// **No per-piece picking.** The collection is the unit (§240) — "show my
/// Squiggles" is a sentence someone means, and picking individual token ids is
/// the filing §178/§229 retired.
///
/// ## Liveness
///
/// Holds no `Thing` — an NFT is a door, not a corpus row (§72), so nothing here
/// touches SwiftData and none of the six liveness corollaries apply.
struct WalletNFTPickerSheet: View {
    /// The watched entry's own address string, exactly as the watch list stores
    /// it — the key picks are filed under. Never the resolved hex: an entry
    /// watched as an ENS name must keep its picks when the name resolves
    /// differently, and `WalletNFTShelf` does the resolving internally.
    let wallet: String
    let label: String

    @ObservedObject private var picks = WalletNFTStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var collections: [NFTCollection] = []
    @State private var loaded = false

    private static let cell: CGFloat = 104

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Self.cell), spacing: DS.Space.s3)]
    }

    var body: some View {
        DSTray(title: String(localized: "Show which NFTs?"),
               height: 520,
               detents: [.height(520), .large]) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(intro)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !loaded {
                    loading
                } else if collections.isEmpty {
                    empty
                } else {
                    grid
                }
            }
        }
        .task {
            // Served from the same cached bytes the wallet refresh already
            // fetched, so opening this costs no request in the common case.
            collections = await WalletNFTShelf.collections(for: wallet)
            loaded = true
        }
    }

    /// One sentence, and it states the thing worth knowing before the first tap:
    /// picking is what causes anything to be fetched at all.
    private var intro: String {
        String(localized: "Only the collections you pick are shown, and only those are loaded.")
    }

    private var loading: some View {
        HStack(spacing: DS.Space.s2) {
            ProgressView()
            Text(String(localized: "Reading \(label)…"))
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DS.Space.s4)
    }

    /// Two different nothings, said differently — an empty grid with one
    /// sentence for both would read as a broken screen for the Solana case,
    /// which is not a failure but a fact about whose API exists.
    private var empty: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(String(localized: "Nothing to show yet"))
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
            Text(String(localized: "No collections were found on Ethereum, Base, Arbitrum, Optimism, Polygon or Robinhood. Solana NFTs can't be read yet."))
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DS.Space.s4)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DS.Space.s3) {
                ForEach(collections) { collection in
                    Button {
                        picks.toggle(wallet: wallet, collection: collection.id)
                    } label: {
                        cellView(collection)
                    }
                    // A picture LIFTS under the finger where a control dips
                    // (§384) — these cells are photographs, so they take the
                    // photograph register.
                    .buttonStyle(PressLift())
                    .accessibilityAddTraits(
                        picks.isPicked(wallet: wallet, collection: collection.id)
                            ? [.isButton, .isSelected] : [.isButton])
                }
            }
            .padding(.bottom, DS.Space.s4)
        }
    }

    private func cellView(_ collection: NFTCollection) -> some View {
        let on = picks.isPicked(wallet: wallet, collection: collection.id)
        return VStack(alignment: .leading, spacing: DS.Space.s1) {
            ZStack(alignment: .topTrailing) {
                artwork(collection)
                // Selection is a MARK on the object, not a second state drawn
                // beside it — and it is a fill, never a border: the design law
                // draws no lines (brief §8, no hairlines, zero exceptions).
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, DS.tint)
                        .padding(DS.Space.s1)
                        .accessibilityHidden(true)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : DS.Motion.standard, value: on)

            Text(collection.name)
                .dsText(.subhead13)
                .fontWeight(on ? .semibold : .regular)
                .foregroundStyle(on ? DS.textPrimary : DS.textSecondary)
                .lineLimit(1)
            Text(collection.count == 1
                 ? String(localized: "1 piece")
                 : String(localized: "\(collection.count) pieces"))
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .lineLimit(1)
        }
    }

    private func artwork(_ collection: NFTCollection) -> some View {
        Group {
            if let url = collection.imageURL, !url.isEmpty {
                RemoteThumb(urlString: url, size: Self.cell)
            } else {
                // A collection with no artwork is still listed and still
                // pickable — dropping it would make the picker quietly disagree
                // with the wallet. It gets a neutral mark, never an invented
                // hue (`AssetMark`'s rule).
                ZStack {
                    DS.gray200
                    Image(systemName: "square.on.square")
                        .font(.system(size: Self.cell * 0.28, weight: .medium))
                        .foregroundStyle(DS.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(width: Self.cell, height: Self.cell)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            }
        }
        .opacity(pickedDim(collection))
    }

    /// An unpicked cell sits back a little so the picked ones read as a set at a
    /// glance. Never below legibility — this is emphasis, not a disabled state,
    /// and every cell here is live (§83: no control that looks inert and isn't,
    /// and none that looks live and isn't).
    private func pickedDim(_ collection: NFTCollection) -> Double {
        picks.isPicked(wallet: wallet, collection: collection.id) ? 1 : 0.72
    }
}
