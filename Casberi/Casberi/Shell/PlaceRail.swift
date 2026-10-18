import SwiftUI

/// **THE RAIL IS THE TAB BAR (prd §1397, step 1 of the Mac shell pass).**
///
/// Where the shell draws a rail (`MainSurface.showsRail`: the Mac and a
/// regular iPad) it lists what the phone's bar lists (`PlaceTabBar`, prd
/// §1327, §1343, §1347): Feed · Wallet · Library, and Search. The rail of
/// nine categories it replaces (§273) was the phone's dock turned 90°, and
/// the phone no longer has that dock: Day is a Feed section, every other
/// category is a section of the Feed's one scroll, and the places you
/// manage are three. A Mac that listed Day twice over (the rail and the
/// Feed's first section) was a shell one generation behind its phone.
///
/// Your face stands at the head of the rail, as it has since 2026-07-20, and
/// it is Library's tile: Library wears your face on the phone's bar too, so
/// the rail has one door to it, not a face above a Library tile. The rooms
/// tray no longer opens from here (§1133f): its Search is ⌘F
/// (`ShellChrome.openFind`), and the three places are ⌘1–⌘3
/// (`CasberiApp.commands`; a key may not outlive its control, §360).
///
/// Each tile is the bar's own mark over its word, in the bar's inks: the
/// pick on `DS.fillStrong` in `DS.brandInk`, the rest `DS.textPrimary`.
struct PlaceRail: View {
    @Environment(ShellChrome.self) private var chrome
    let current: PlaceTab?
    let open: (PlaceTab) -> Void
    let search: () -> Void

    /// A tile's size: the rail's column less the air either side.
    static let tileWidth: CGFloat = PadLayout.railWidth - 2 * DS.Space.s3
    static let tileHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            tile(.library)
            tile(.feed)
            tile(.wallet)
            searchTile
            Spacer(minLength: 0)
        }
        .padding(.top, DS.Space.s2)
        .frame(width: PadLayout.railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tile(_ tab: PlaceTab) -> some View {
        let on = tab == current
        return Button {
            DSHaptic.selection()
            open(tab)
        } label: {
            VStack(spacing: 2) {
                mark(tab, on: on)
                    .frame(height: 26)
                Text(verbatim: tab.label)
                    .dsText(.label12)
                    .foregroundStyle(on ? DS.brandInk : DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: Self.tileWidth, height: Self.tileHeight)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                        .fill(DS.fillStrong)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .dsTooltip(tab.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tab.label))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .modifier(LibraryAlarm(active: tab == .library))
        // The capture flight lands on the Feed's tile, as it lands on the
        // phone's Feed tab.
        .background { if tab == .feed { FeedTabFrame() } }
    }

    private var searchTile: some View {
        Button {
            DSHaptic.tap()
            search()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "magnifyingglass")
                    .dsGlyph(.body, weight: .regular)
                    .foregroundStyle(DS.textPrimary)
                    .frame(height: 26)
                Text("Search")
                    .dsText(.label12)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: Self.tileWidth, height: Self.tileHeight)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .dsTooltip(String(localized: "Search"))
        .accessibilityLabel(Text("Search"))
        .accessibilityHint(Text("Find anything, or make a page of it"))
    }

    @ViewBuilder
    private func mark(_ tab: PlaceTab, on: Bool) -> some View {
        if tab == .library {
            YouFace(size: 26)
                .modifier(DoorSpin(trigger: chrome.refreshPulse, tension: chrome.pullTension))
        } else {
            Image(systemName: tab.glyph)
                .dsGlyph(.body, weight: on ? .semibold : .regular)
                .foregroundStyle(on ? DS.brandInk : DS.textPrimary)
        }
    }
}
