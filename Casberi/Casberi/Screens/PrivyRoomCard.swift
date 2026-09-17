import SwiftUI

/// THE PRIVY ROOM'S HEAD (prd §803c, §803e) — what your app wallets hold, and
/// which apps you use.
///
/// The mockup's order (user, 2026-09-17): the total across every wallet read
/// so far, the apps holding money by value, then the apps used recently, then
/// ONE line for the rest — never a row each for eighty empty wallets. Before
/// any balance is read it leads with how many apps made a wallet.
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

    private var listed: [PrivyHomeFeed.Room.Entry] { room.funded + room.recent }

    var body: some View {
        DSRoomChassis.Head(
            lead: lead,
            footnotes: [.quiet(PrivyHomeFeed.footnote(room))]) {
            if !listed.isEmpty {
                DSRoomChassis.Block {
                    DSRoomChassis.Rows(items: listed) { index, entry in
                        DSRoomChassis.MarkedRow(
                            name: entry.name, flag: nil, line: entry.line,
                            index: index, action: { onOpen(entry.ref) }) {
                            PrivyAppMark(logoURL: entry.logoURL)
                        } trailing: {
                            if let usd = entry.usd, usd >= PrivyHomeFeed.fundedFloor {
                                Text(verbatim: mask ?? PrivyHomeFeed.usd(usd))
                                    .dsText(.price17)
                                    .monospacedDigit()
                                    .foregroundStyle(DS.textPrimary)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// An app's own logo on the row's 26pt lead, from the `logo_url` Privy
/// returns. Until it loads, or when there is none, the stack glyph every
/// Privy row wears.
struct PrivyAppMark: View {
    let logoURL: String?

    var body: some View {
        DSGlyphLead(glyph: "square.stack.3d.up")
            .overlay {
                if let url = logoURL.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .transition(.opacity)
                        }
                    }
                }
            }
            .frame(width: DS.Mark.row, height: DS.Mark.row)
            .clipShape(RoundedRectangle(cornerRadius: DS.Mark.row * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}
