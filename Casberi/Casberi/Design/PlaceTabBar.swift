import SwiftUI

/// **THE PLACES ARE TABS (prd §1327, user: "i feel like the solution is in
/// the tab bar that we have been avoiding … we need those 'places'
/// accessible and to make sense, so they need to be on the tab bar").**
/// Feed · Wallet · Library, in that order: the places you manage (prd §1343,
/// §1347, user: "tabs should be places you actually manage things"); Day and
/// Notes are Feed sections, and Notes' folders live in Library. Search
/// stands beside them. Library wears your face,
/// the octopus until you choose one, and carries the face's broken-app ring.
///
/// Each tab is the place's own `filter.source`, so the tab you are on is
/// derived from the one switch the shell already has, and the swipe walks the
/// same places in the same order (`HomeScope.phoneWalk`).
///
/// **FIVE EQUAL TABS IN ONE BAR (prd §1422, user: "feed wallet actions
/// library search"; of the label, "ok lets go w/ Move").** Feed · Wallet ·
/// Move · Library · Search, Search in the bar as Music and the App Store draw
/// it, not a circle of its own. Move is your account's page. Search is a tab
/// with no place: it raises the tray's search on the phone, Find elsewhere,
/// and it is never in the swipe.
///
/// **Move is in every build** (prd §1435): no feature is hidden or dormant
/// in a release (App Review 2.3.1), so the tab that was DEBUG-only while its
/// account learned to send and recover is simply one of the five.
enum PlaceTab: String, Identifiable, CaseIterable {
    case feed, wallet, move, library, search

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feed:    String(localized: "Feed")
        case .wallet:  String(localized: "Wallet")
        case .move:    String(localized: "Move")
        case .library: String(localized: "Library")
        case .search:  String(localized: "Search")
        }
    }

    /// The place's `filter.source`; nil for Search, which is no place.
    @MainActor var source: String? {
        switch self {
        case .feed:    "All"
        case .wallet:  CategoryFold.walletRoom
        case .move:    HomeScope.Place.move.source
        case .library: HomeScope.Place.settings.source
        case .search:  nil
        }
    }

    /// The glyph the place has always worn on its tile; Library's is your
    /// face, drawn by the bar.
    @MainActor var glyph: String {
        switch self {
        case .feed:    ScopeTileGlyph.feed
        case .wallet:  ScopeTileGlyph.wallets
        case .move:    ScopeTileGlyph.move
        case .library: ScopeTileGlyph.apps
        case .search:  "magnifyingglass"
        }
    }

    /// The tab a source stands in: Markets is a Wallet tile (prd §1232), and
    /// a room off the five (Testnets) is nobody's tab.
    /// A tab pressed (prd §1327): the place's own door, the one its tile and
    /// the face took before. The Feed's, pressed on the Feed, returns to the
    /// top (§1280's face); Library is Sources' place (§1321). ONE door for
    /// the phone's bar, the rail (prd §1402) and the ⌘-digits.
    @MainActor static func open(_ tab: PlaceTab, chrome: ShellChrome, route: HomeRoute) {
        // Search is no place: the tray's field on the phone (as the circle
        // was), Find where the shell has a rail (as ⌘F is).
        if tab == .search {
            withAnimation(DS.Motion.standard) {
                if UIDevice.current.userInterfaceIdiom == .phone { chrome.roomsTray = true } else { chrome.openFind() }
            }
            return
        }
        withAnimation(DS.Motion.standard) {
            chrome.roomsTray = false
            switch tab {
            case .feed:
                chrome.goToFeed()
            case .wallet:
                chrome.openWallet()
            case .move:
                // Move is an act, not a place (prd §1442): its tab raises
                // the tray over wherever you are, as Search raises its own.
                chrome.moveTray = true
            case .library:
                chrome.settingsPick = .sources
                route.present(.casberi)
                // Library's tap is a pull (user, 2026-10-19): your apps are
                // asked, the tiles rain and your face turns. The shell runs
                // it, where the store and the context are.
                chrome.libraryPull &+= 1
            case .search:
                break
            }
        }
    }

    @MainActor static func current(_ source: String) -> PlaceTab? {
        if HomeScope.isMarkets(source) { return .wallet }
        // Day is the Feed's section (prd §1343); the Notes page is Library's
        // (prd §1347).
        if source == RoomAccounts.dayRoom { return .feed }
        if Pinboard.isPinnedRoom(source) { return .library }
        return allCases.first { $0.source == source }
    }
}

/// The bar itself: every tab in one glass bar across the width, Search the
/// last (prd §1422, amending §1327's circle beside it and §1374's bar that
/// hugged three tabs). Read down, it folds into one circle for the tab you
/// are on (`ShellChrome.minimized`, the scroll fold the band already had);
/// that circle, or a scroll back up, unfolds it. While the tray is up the bar
/// is that one circle too, and it closes the tray: the tray's own field
/// stands where the bar was.
struct PlaceTabBar: View {
    @Environment(ShellChrome.self) private var chrome
    let current: PlaceTab?
    let open: (PlaceTab) -> Void
    let search: () -> Void
    /// Each tab's presses, for the glyph's bounce (user, 2026-10-19: "they
    /// should" animate when touched). Library's face spins instead, on the
    /// shower its tap deals (`PlaceTab.open`).
    @State private var taps: [PlaceTab: Int] = [:]

    private var folded: Bool { chrome.minimized || chrome.roomsTray }
    /// **THE LABELS WIN OVER THE PAGE (user, 2026-10-15: "it is hard to see
    /// the icons and words especially when selected").** The glass takes the
    /// page's own ground as its tint, so a busy row under the bar sinks back
    /// instead of reading through the words; the pick stands on the strong
    /// fill, a lighter pill, as iOS 26's bar draws its selected tab.
    static var lens: Color { DS.page }
    private var size: CGFloat { DSDock.agentSize(fold: chrome.fold) }
    var body: some View {
        HStack(spacing: DS.Space.s2) {
            if folded {
                foldedCircle
                Spacer(minLength: 0)
            } else {
                bar
            }
        }
        .animation(DS.Motion.standard, value: folded)
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(PlaceTab.allCases) { tab in
                Button {
                    taps[tab, default: 0] &+= 1
                    if tab == .search {
                        DSHaptic.tap()
                        search()
                    } else {
                        DSHaptic.selection()
                        open(tab)
                    }
                } label: {
                    VStack(spacing: 2) {
                        mark(tab, on: tab == current, glyphSize: .body, taps: taps[tab] ?? 0)
                            .frame(height: 26)
                        Text(verbatim: tab.label)
                            .dsText(.label12)
                            .foregroundStyle(tab == current ? DS.brandInk : DS.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if tab == current {
                            Capsule().fill(DS.fillStrong).padding(.vertical, DS.Space.s1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: tab.label))
                .accessibilityAddTraits(tab == current ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(tab == .search ? Text("Find anything, or make a page of it") : Text(verbatim: ""))
                .background { if tab == .feed { FeedTabFrame() } }
            }
        }
        .padding(.horizontal, DS.Space.s1)
        .frame(maxWidth: .infinity)
        .frame(height: size)
        .dsGlass(cornerRadius: size / 2, tint: Self.lens)
    }

    /// The tab you are on, alone: a tap unfolds the bar, or closes the tray.
    private var foldedCircle: some View {
        let tab = current ?? .feed
        return Button {
            DSHaptic.selection()
            if chrome.roomsTray {
                withAnimation(DS.Motion.standard) { chrome.roomsTray = false }
            } else {
                chrome.unfold()
            }
        } label: {
            mark(tab, on: true, glyphSize: .body)
                .frame(width: size, height: size)
                .dsGlass(cornerRadius: size / 2, tint: Self.lens)
                .dsTapTarget(Circle())
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(verbatim: tab.label))
        .accessibilityHint(chrome.roomsTray ? Text("Closes search") : Text("Shows every place"))
        .background { if tab == .feed { FeedTabFrame() } }
    }

    @ViewBuilder
    private func mark(_ tab: PlaceTab, on: Bool, glyphSize: DSGlyph, taps: Int = 0) -> some View {
        if tab == .library {
            LibraryFace()
        } else {
            Image(systemName: tab.glyph)
                .dsGlyph(glyphSize, weight: on ? .semibold : .regular)
                .foregroundStyle(on ? DS.brandInk : DS.textPrimary)
                .symbolEffect(.bounce, value: taps)
        }
    }
}

/// Where the capture flight lands (prd §930's seat, the Feed's door since):
/// the Feed's tab, as the face published it before.
struct FeedTabFrame: View {
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { chrome.feedTabFrame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in chrome.feedTabFrame = f }
        }
    }
}

/// Your face on Library's tab, and the pull-to-refresh spin it always did
/// (`DoorSpin`, prd §1327 item 10): the pull winds it, the refresh turns it
/// once. A leaf, so the pull's every frame redraws the face and not the bar.
private struct LibraryFace: View {
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        YouFace(size: 26)
            .modifier(DoorSpin(trigger: chrome.refreshPulse, tension: chrome.pullTension))
    }
}
