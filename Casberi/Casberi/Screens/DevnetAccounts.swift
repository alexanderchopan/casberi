import SwiftUI

/// **THE DEVNET PAGE'S WAY OUT.** This file held the devnet setup screens'
/// shared watch control (user, 2026-09-04: "i think they should share common
/// framework and also be better") — the watch-list protocol, the peek, the
/// read after a watch, the roster's facts and the row. Its one conformer was
/// the Frames devnet, deleted with the seat (prd §1206, §723); what Logos
/// still draws is the explorer row below.

// MARK: - The explorer

/// The way off this screen and onto the chain's own explorer.
///
/// **A centred card row, the shape `BridgeDisconnectSection` already uses**
/// (user, 2026-09-04: *"the 'open the explorer' doesn't really seem like rest
/// of the style"*). It shipped as a `DSSlabDoor` — a full-width filled slab
/// with a leading title, a trailing host and a chevron — which is the grammar
/// of a door onto ANOTHER SCREEN IN THIS APP, sitting between an inset-grouped
/// card and a centred destructive row and matching neither.
///
/// It is also not that kind of door: it leaves the app entirely. The two rows
/// at the foot of these screens are both exits now, one neutral and one
/// destructive, in one shape.
///
/// The host is stated under the verb rather than beside it, because a door out
/// of the app must be checkable against the address bar it lands on — the
/// honesty rule §315's own door budget exists to keep.
struct DevnetExplorerRow: View {
    /// The chain's explorer. A browser door, never a fetch — every one of
    /// these hosts sits in `network-reach-audit.sh`'s denylist for exactly
    /// that reason, and the day one is fetched it belongs in `NetworkReach`
    /// instead.
    let url: String
    /// PLAIN on the account page (prd §639), the way `BridgeDisconnectSection`
    /// is: the same verb and the same host line, left-aligned on the page's own
    /// ground instead of centred in a card, because the page has no cards.
    var plain = false

    private var host: String {
        URL(string: url)?.host() ?? url
    }

    var body: some View {
        Section {
            Button {
                DSHaptic.selection()
                if let target = URL(string: url) {
                    UIApplication.shared.open(target)
                }
            } label: {
                VStack(alignment: plain ? .leading : .center, spacing: 1) {
                    Text("Open the explorer")
                        .dsText(.body17)
                        .foregroundStyle(DS.tint)
                    Text(host)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: plain ? .leading : .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .modifier(ExplorerGround(plain: plain))
        }
    }
}

/// The card row everywhere but the account page, where the row is the page.
private struct ExplorerGround: ViewModifier {
    let plain: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if plain {
            content
                .frame(minHeight: 56)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            content.dsListRow()
        }
    }
}
