import SwiftUI

/// THE PRIVY ROOM'S HEAD (prd §803c) — what your app wallets hold, and which
/// apps hold it.
///
/// Leads with the total across every wallet read so far, then the funded apps
/// by value. Before any balance has been read it leads with how many apps made
/// a wallet, which is true from the first sync. An app with nothing in it gets
/// no row here; it is a row in the feed below, dated when it was made.
///
/// ## Liveness
///
/// Stores no `Thing` — only `PrivyHomeFeed.Room` values out of
/// `PrivyHomeStore`. A tap hands back the app's `sourceRef` and the section
/// that owns the sheet does the lookup (corollary 5).
struct PrivyRoomCard: View {
    let room: PrivyHomeFeed.Room
    var onOpen: (String) -> Void

    private var mask: String? { BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil }

    private var lead: DSRoomChassis.Lead {
        guard room.readCount > 0 else { return .sentence(PrivyHomeFeed.headline(room)) }
        let figure = mask ?? PrivyHomeFeed.usd(room.totalUSD)
        return .lede(RoomLede(figure: figure,
                              caption: PrivyHomeFeed.caption(room),
                              numeric: mask == nil ? room.totalUSD : nil),
                     spoken: "\(figure), \(PrivyHomeFeed.caption(room))")
    }

    var body: some View {
        DSRoomChassis.Head(
            lead: lead,
            footnotes: [.quiet(PrivyHomeFeed.footnote(room))]) {
            if !room.funded.isEmpty {
                DSRoomChassis.Block {
                    DSRoomChassis.Rows(items: room.funded) { index, entry in
                        DSRoomChassis.Row(
                            title: entry.name,
                            glyph: "square.stack.3d.up",
                            line: mask ?? PrivyHomeFeed.usd(entry.usd),
                            detail: entry.line,
                            index: index,
                            action: { onOpen(entry.ref) }) {
                            EmptyView()
                        }
                    }
                }
            }
        }
    }
}
