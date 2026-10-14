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
    /// The band's left pill (prd §1295): the face and Search, one glass.
    var union: DSGlassUnion? = nil

    private var markSize: CGFloat { DSDock.agentSize(fold: chrome.fold) }

    var body: some View {
        AvatarChip(onAccounts: onAccounts,
                   refreshSpin: chrome.refreshPulse,
                   pullTension: chrome.pullTension,
                   doorUnion: union,
                   size: markSize,
                   onBack: onBack,
                   lit: chrome.roomsTray && onBack == nil,
                   name: String(localized: "Feed"))
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

/// The Wallet in the bottom band (prd §1278, was ✎ since §1207 item 6):
/// opens the Wallet on Home from any page, the Wallet included. When your own
/// account ships it opens the Wallet with the account sheet on top
/// (`docs/safe-wallet-spec.md`). The face's glass and size, so the band's
/// two ends are one family.
struct WalletDoor: View {
    @Environment(ShellChrome.self) private var chrome
    let action: () -> Void

    var body: some View {
        let size = DSDock.agentSize(fold: chrome.fold)
        Button {
            DSHaptic.tap()
            action()
        } label: {
            Image(systemName: "wallet.bifold")
                .dsGlyph(.body, weight: .semibold)
                .foregroundStyle(DS.textPrimary)
                .frame(width: size, height: size)
                .dsGlassDoor(nil)
                .dsTapTarget(Circle())
                .dsHover()
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text("Wallet"))
    }
}

/// SEARCH IN THE BAND (prd §1207 item 7, built §1209a; a disc since prd
/// §1294, beside the face in one glass pill since §1295, user: "i'm wondering if the search bar should just be a search
/// icon, still behave the same way but take up less real estate", then "do
/// A"): always there, the face's glass and size, beside the Wallet at the
/// band's trailing end, as iOS 26 stands search beside its tabs. A tap raises
/// the tray with its search, as the bar did; the middle of the band is the
/// page's again.
struct BandSearchBar: View {
    @Environment(ShellChrome.self) private var chrome
    /// One glass with the face (prd §1295): the two ways around the app are
    /// one pill at the band's leading end, as iOS 26 groups its tabs.
    var union: DSGlassUnion? = nil
    let action: () -> Void

    var body: some View {
        let size = DSDock.agentSize(fold: chrome.fold)
        Button {
            DSHaptic.tap()
            action()
        } label: {
            Image(systemName: "magnifyingglass")
                .dsGlyph(.body, weight: .semibold)
                .foregroundStyle(DS.textPrimary)
                .frame(width: size, height: size)
                .dsGlassDoor(union)
                .dsTapTarget(Circle())
                .dsHover()
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text("Search"))
        .accessibilityHint(Text("Find anything, or make a page of it"))
    }
}
