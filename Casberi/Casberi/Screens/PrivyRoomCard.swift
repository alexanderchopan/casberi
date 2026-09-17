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
        let store = PrivyHomeStore.shared
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
        } scopes: {
            // The mockup's tiles (prd §803f), under the well as every scoped
            // room's are. Activity appears once something has moved.
            DSScopeTiles(sections: PrivyHomeFeed.Section.present(hasActivity: store.activityCount > 0),
                         active: store.section) { picked in
                store.section = picked
            }
        }
    }
}

/// An app's own logo on the row's 26pt lead, from the `logo_url` Privy
/// returns. Until it loads, or when there is none, the stack glyph every
/// Privy row wears.
///
/// Through `RemoteThumb` — the app's own loader — rather than `AsyncImage`
/// (prd §803g). Three reasons, and the first two are why every other remote
/// mark in the app already goes this way: the loader downsamples off main and
/// caches to disk, so a room of app logos is not a row body's worth of
/// full-size decodes on every pass (§626), and it remembers a dead URL instead
/// of re-asking for it. The third is the demo: `RemoteImageLoader` resolves a
/// bundled `sample:` ref in DEBUG, so the furnished demo draws real app marks
/// with no request, and `AsyncImage` could only ever draw the glyph.
/// `bare` keeps the stack glyph below showing until the logo arrives.
struct PrivyAppMark: View {
    let logoURL: String?

    var body: some View {
        DSGlyphLead(glyph: "square.stack.3d.up")
            .overlay {
                if let logoURL, !logoURL.isEmpty {
                    RemoteThumb(urlString: logoURL, size: DS.Mark.row, bare: true)
                }
            }
            .frame(width: DS.Mark.row, height: DS.Mark.row)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.appIcon(DS.Mark.row),
                                        style: .continuous))
            .accessibilityHidden(true)
    }
}
