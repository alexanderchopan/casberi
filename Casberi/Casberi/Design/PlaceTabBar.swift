import SwiftUI

/// **THE PLACES ARE TABS (prd §1327, user: "i feel like the solution is in
/// the tab bar that we have been avoiding … we need those 'places'
/// accessible and to make sense, so they need to be on the tab bar").**
/// Feed · Wallet · Library, in that order: the places you manage (prd §1343,
/// §1347, user: "tabs should be places you actually manage things"); Day and
/// Notes are Feed sections, and Notes' folders live in Library. Library
/// wears your face, the octopus until you choose one, and carries the face's
/// broken-app ring.
///
/// Each tab is the place's own `filter.source`, so the tab you are on is
/// derived from the one switch the shell already has, and the swipe walks the
/// same places in the same order (`HomeScope.phoneWalk`).
///
/// **THREE PLACES AND THE ACT (prd §1715, amends §1422's five and §1640's
/// Search circle; user, 2026-11-07: "feed wallet and library are all
/// places. and 'move' the the fab"; "i do think we can get rid of the
/// search").** Feed · Wallet · Library stand in the capsule and are the swipe;
/// Move, an act and a tray (§1442), is the circle at the trailing edge where
/// Search stood. Search is deleted from the bar: it is Library's field
/// (`LibrarySearch`), and ⌘F focuses that field on the Mac. The order holds
/// §1640's reading — the Feed first as the place you land, Library last as
/// the App Library is — and Move beside the Wallet buys nothing, because a
/// tray raised over wherever you are is not a place anyone walks to.
///
/// **Move is in every build** (prd §1435): no feature is hidden or dormant
/// in a release (App Review 2.3.1).
enum PlaceTab: String, Identifiable, CaseIterable {
    case feed, wallet, library, move

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feed:    String(localized: "Feed")
        case .wallet:  String(localized: "Wallet")
        case .library: String(localized: "Library")
        case .move:    String(localized: "Move")
        }
    }

    /// The place's `filter.source`; nil for Move, which is no place (prd
    /// §1442: a tray over wherever you are), so the swipe never lands on it.
    @MainActor var source: String? {
        switch self {
        case .feed:    "All"
        case .wallet:  CategoryFold.walletRoom
        case .library: HomeScope.Place.settings.source
        case .move:    nil
        }
    }

    /// The glyph the place has always worn on its tile; Library's is your
    /// face, drawn by the bar.
    @MainActor var glyph: String {
        switch self {
        case .feed:    ScopeTileGlyph.feed
        case .wallet:  ScopeTileGlyph.wallets
        case .library: ScopeTileGlyph.apps
        case .move:    ScopeTileGlyph.move
        }
    }

    /// The tab a source stands in: Markets is a Wallet tile (prd §1232), and
    /// a room off the five (Testnets) is nobody's tab.
    /// A tab pressed (prd §1327): the place's own door, the one its tile and
    /// the face took before. The Feed's, pressed on the Feed, returns to the
    /// top (§1280's face); Library is Sources' place (§1321). ONE door for
    /// the phone's bar, the rail (prd §1402) and the ⌘-digits.
    @MainActor static func open(_ tab: PlaceTab, chrome: ShellChrome, route: HomeRoute) {
        withAnimation(DS.Motion.standard) {
            switch tab {
            case .feed:
                chrome.goToFeed()
            case .wallet:
                chrome.openWallet()
            case .move:
                // Move is an act, not a place (prd §1442): its tab raises
                // the tray over wherever you are.
                chrome.moveTray = true
            case .library:
                chrome.settingsPick = .sources
                route.present(.casberi)
                // Library's tap is a pull (user, 2026-10-19): your apps are
                // asked, the tiles rain and your face turns. The shell runs
                // it, where the store and the context are.
                chrome.libraryPull &+= 1
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

/// The bar itself: three places in one glass capsule and Move a circle beside
/// it at the trailing edge (prd §1715, amending §1640's Search circle). Read
/// down, the places fold into Move's circle (`ShellChrome.minimized`, the
/// scroll fold the band already had; prd §1735); a scroll back up unfolds it.
struct PlaceTabBar: View {
    @Environment(ShellChrome.self) private var chrome
    let current: PlaceTab?
    let open: (PlaceTab) -> Void
    /// Each tab's presses, for the glyph's bounce (user, 2026-10-19: "they
    /// should" animate when touched). Library's face spins instead, on the
    /// shower its tap deals (`PlaceTab.open`).
    @State private var taps: [PlaceTab: Int] = [:]

    private var folded: Bool { chrome.minimized }
    /// **THE LABELS WIN OVER THE PAGE (user, 2026-10-15: "it is hard to see
    /// the icons and words especially when selected").** The glass takes the
    /// page's own ground as its tint, so a busy row under the bar sinks back
    /// instead of reading through the words; the pick stands on the strong
    /// fill, a lighter pill, as iOS 26's bar draws its selected tab.
    static var lens: Color { DS.page }
    private var size: CGFloat { DSDock.agentSize(fold: chrome.fold) }
    var body: some View {
        // THE BAR FOLDS INTO MOVE (prd §1735): read down, the places draw
        // into the act's circle at the trailing edge and Move stands alone,
        // one tap from anywhere on the page. A scroll back up brings the
        // places out again; no circle is left on the leading side.
        HStack(spacing: DS.Space.s2) {
            if folded {
                Spacer(minLength: 0)
            } else {
                tabs
                    .transition(.scale(scale: 0.2, anchor: .trailing).combined(with: .opacity))
            }
            moveCircle
                // Folded, the capture flight lands on the one thing left.
                .background { if folded { FeedTabFrame() } }
        }
        .animation(DS.Motion.standard, value: folded)
    }

    /// **THE ACT STANDS APART (prd §1715, amends §1640's Search circle; user,
    /// 2026-11-01, of the split: "ok we can split it then as long as it
    /// collapses").** The three places keep their order in the capsule
    /// (Library at the right as the App Library is) and Move is its own
    /// circle at the trailing edge, the shape iOS gives a search tab, here
    /// given to the one control that is an act. Read down, the places fold
    /// into Move's circle and Move stands alone (prd §1735).
    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(PlaceTab.allCases.filter { $0 != .move }) { tab in
                Button {
                    taps[tab, default: 0] &+= 1
                    DSHaptic.selection()
                    open(tab)
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
                .background { if tab == .feed { FeedTabFrame() } }
            }
        }
        .padding(.horizontal, DS.Space.s1)
        .frame(maxWidth: .infinity)
        .frame(height: size)
        .dsGlass(cornerRadius: size / 2, tint: Self.lens)
    }

    /// Move's own circle, the bar's height, at the trailing edge: it raises
    /// the Move tray over wherever you stand (prd §1442), through the one
    /// door every tab press takes.
    ///
    /// **THE ACT WEARS INK (prd §1735).** On the places' own glass, in the
    /// places' own ink and with no word, the circle read as a fourth place.
    /// It is a solid disc in the primary ink with the glyph in the page's:
    /// never the pick's pink, which on this bar means the tab you are on.
    private var moveCircle: some View {
        Button {
            taps[.move, default: 0] &+= 1
            DSHaptic.tap()
            open(.move)
        } label: {
            Image(systemName: PlaceTab.move.glyph)
                .dsGlyph(.body, weight: .semibold)
                .foregroundStyle(DS.page)
                .symbolEffect(.bounce, value: taps[.move] ?? 0)
                .frame(width: size, height: size)
                .background(DS.textPrimary, in: Circle())
                .dsTapTarget(Circle())
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text(verbatim: PlaceTab.move.label))
        .accessibilityHint(Text("Swap, send or receive money"))
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
