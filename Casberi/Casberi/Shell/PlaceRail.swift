import SwiftUI

/// **THE RAIL IS THE TAB BAR (prd §1402, step 1 of the Mac shell pass).**
///
/// Where the shell draws a rail (`MainSurface.showsRail`: the Mac and a
/// regular iPad) it lists what the phone's bar lists (`PlaceTabBar`, prd
/// §1327, §1343, §1347): Feed · Wallet · Library, and Move. The rail of
/// nine categories it replaces (§273) was the phone's dock turned 90°, and
/// the phone no longer has that dock: Day is a Feed section, every other
/// category is a section of the Feed's one scroll, and the places you
/// manage are three. A Mac that listed Day twice over (the rail and the
/// Feed's first section) was a shell one generation behind its phone.
///
/// Your face stands at the head of the rail, as it has since 2026-07-20, and
/// it is Library's tile: Library wears your face on the phone's bar too, so
/// the rail has one door to it, not a face above a Library tile. The face no
/// longer opens the rooms tray (§1133f); the Search tile and ⌘F do, as the
/// phone's Search does (§1664), and the places are ⌘1–⌘5
/// (`CasberiApp.commands`; a key may not outlive its control, §360).
///
/// Each tile is the bar's own mark over its word, in the bar's inks: the
/// pick on `DS.fillStrong` in `DS.brandInk`, the rest `DS.textPrimary`.
struct PlaceRail: View {
    @Environment(ShellChrome.self) private var chrome
    let current: PlaceTab?
    let open: (PlaceTab) -> Void
    /// Each tile's presses, for the glyph's bounce — the bar's (`PlaceTabBar`).
    @State private var taps: [PlaceTab: Int] = [:]

    /// A tile's size: the rail's column less the air either side.
    static let tileWidth: CGFloat = PadLayout.railWidth - 2 * DS.Space.s3
    static let tileHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            tile(.library)
            tile(.feed)
            tile(.wallet)
            // Move stands apart at the end, as the phone's circle does
            // beside its three places (prd §1715).
            tile(.move)
                .padding(.top, DS.Space.s3)
            Spacer(minLength: 0)
            demoFoot
        }
        .padding(.top, DS.Space.s2)
        .frame(width: PadLayout.railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tile(_ tab: PlaceTab) -> some View {
        let on = tab == current
        return Button {
            taps[tab, default: 0] &+= 1
            DSHaptic.selection()
            open(tab)
        } label: {
            VStack(spacing: 2) {
                mark(tab, on: on, taps: taps[tab] ?? 0)
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
        // The key with the word (prd §1407): the ⌘-digit in the bar's order (§1402, §1422).
        .dsTooltip("\(tab.label)  ⌘\((PlaceTab.allCases.firstIndex(of: tab) ?? 0) + 1)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tab.label))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        // The capture flight lands on the Feed's tile, as it lands on the
        // phone's Feed tab.
        .background { if tab == .feed { FeedTabFrame() } }
    }

    /// THE DEMO'S MARK ON THE MAC (prd §1407): the rail's foot says Demo and
    /// offers Exit, in the pick's ink; the window title says it too. No pill
    /// over the list, no band at the top, nothing the pane's column has to
    /// paint around.
    @ViewBuilder
    private var demoFoot: some View {
        if DSDemoMark.inWindowTitle, DSDemoMark.marking {
            VStack(spacing: 2) {
                Text("Demo")
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                Button {
                    DSHaptic.tap()
                    chrome.demoExitRequest += 1
                } label: {
                    Text("Exit")
                        .dsText(.label12)
                        .foregroundStyle(DS.pickInk)
                        .frame(width: Self.tileWidth, height: 28)
                        // DRAWN 28, TARGETED 44.
                        .dsTapTarget(Rectangle())
                }
                .buttonStyle(RowPress())
                .dsHover()
                .dsTooltip(String(localized: "Exit demo"))
                .accessibilityLabel(Text("Exit demo"))
            }
            .padding(.bottom, DS.Space.s4)
            .opacity(chrome.demoLeaving ? 0 : 1)
            .animation(DS.Motion.standard, value: chrome.demoLeaving)
        }
    }

    @ViewBuilder
    private func mark(_ tab: PlaceTab, on: Bool, taps: Int) -> some View {
        if tab == .library {
            YouFace(size: 26)
                .modifier(DoorSpin(trigger: chrome.refreshPulse, tension: chrome.pullTension))
        } else {
            Image(systemName: tab.glyph)
                .dsGlyph(.body, weight: on ? .semibold : .regular)
                .foregroundStyle(on ? DS.brandInk : DS.textPrimary)
                .symbolEffect(.bounce, value: taps)
        }
    }
}
