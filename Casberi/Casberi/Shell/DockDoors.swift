import SwiftUI

/// The dock's leading seat: your face (prd §700, 2026-09-11) — which opens
/// your ACCOUNTS since prd §796 (2026-09-17); Settings is a door in that
/// screen's head row.
///
/// **This seat held two doors for a few hours.** §697 deleted the octopus
/// and stood the face and the catalogue grid here as one glass cluster; the
/// same day the user asked for the grid to go (*"have the app icon not be
/// fixed on the tab bar. only make the avatar be fixed"*). The reasoning
/// holds on its own: the face is the one mark in the dock that is about YOU,
/// and it is the seat that has to survive into a pushed room, a bridge form
/// and Settings itself (§357's rule, from the other direction — none of
/// which the strip's `safeAreaInset` survives).
///
/// **And it holds ONE door again (prd §798, 2026-09-17).** §700 sent the
/// grid to the strip's tail rather than deleting it, and §793 gave it a word
/// ("Accounts") — by which point the face opened that same screen (§796) and
/// the dock carried two doors to it, one of them a tile among the places
/// that is not a place. The tail tile is deleted; this seat is the door.
///
/// **Hosted on `RootShell`'s own layer, not inside the strip** — the seat the
/// octopus held, for the reason above.
///
/// Named in the plural still: the file is the dock's fixed seat, whatever
/// stands in it, and every guard that reads it (`dock-selftest.sh`) reads it
/// by this name.
struct DockDoors: View {
    @Environment(ShellChrome.self) private var chrome
    /// Accounts — the avatar door (a toggle, §705).
    var onAccounts: () -> Void
    /// Pops one frame; set while anything is pushed (prd §767).
    var onBack: (() -> Void)? = nil

    private var markSize: CGFloat { DSDock.agentSize(fold: chrome.fold) }

    var body: some View {
        AvatarChip(onAccounts: onAccounts,
                   refreshSpin: chrome.refreshPulse,
                   pullTension: chrome.pullTension,
                   size: markSize,
                   onBack: onBack,
                   lit: chrome.roomsTray && onBack == nil)
            // The capture flight lands on THIS seat since prd §930 — the
            // door to Home, now that the "All" chip that used to publish the
            // target is a row of the tray. Same write the chip made.
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { chrome.feedTabFrame = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, f in chrome.feedTabFrame = f }
                }
            }
    }
}

/// ✎ in the bottom band (prd §1207 item 6): writes a note from any page.
/// The face's glass and size, so the band's two ends are one family.
struct NoteDoor: View {
    @Environment(ShellChrome.self) private var chrome
    let action: () -> Void

    var body: some View {
        let size = DSDock.agentSize(fold: chrome.fold)
        Button {
            DSHaptic.tap()
            action()
        } label: {
            Image(systemName: "square.and.pencil")
                .dsGlyph(.body, weight: .semibold)
                .foregroundStyle(DS.textPrimary)
                .frame(width: size, height: size)
                .dsGlassDoor(nil)
                .dsTapTarget(Circle())
                .dsHover()
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text("New note"))
    }
}

/// THE BAR IN THE BAND (prd §1207 item 7, built §1209a): always there, full
/// size, never shrinking while you read. A tap raises the tray with its
/// search focused, where the words become a page (§1209). The face's glass
/// and height, so the band reads as one row: face · bar · ✎.
struct BandSearchBar: View {
    @Environment(ShellChrome.self) private var chrome
    let action: () -> Void

    var body: some View {
        let size = DSDock.agentSize(fold: chrome.fold)
        Button {
            DSHaptic.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "magnifyingglass")
                    .dsGlyph(.body)
                    .foregroundStyle(DS.textSecondary)
                Text("Search")
                    .dsText(.body17)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.s4)
            .frame(maxWidth: .infinity, minHeight: size, maxHeight: size)
            .dsGlass(cornerRadius: size / 2)
            .dsTapTarget(Capsule())
            .dsHover()
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text("Search"))
        .accessibilityHint(Text("Find anything, or make a page of it"))
    }
}
