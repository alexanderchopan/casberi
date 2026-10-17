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
/// same five in the same order (`HomeScope.phoneWalk`).
enum PlaceTab: String, CaseIterable, Identifiable {
    case feed, wallet, library

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feed:    String(localized: "Feed")
        case .wallet:  String(localized: "Wallet")
        case .library: String(localized: "Library")
        }
    }

    /// The place's `filter.source`.
    @MainActor var source: String {
        switch self {
        case .feed:    "All"
        case .wallet:  CategoryFold.walletRoom
        case .library: HomeScope.Place.settings.source
        }
    }

    /// The glyph the place has always worn on its tile; Library's is your
    /// face, drawn by the bar.
    @MainActor var glyph: String {
        switch self {
        case .feed:    ScopeTileGlyph.feed
        case .wallet:  ScopeTileGlyph.wallets
        case .library: ScopeTileGlyph.apps
        }
    }

    /// The tab a source stands in: Markets is a Wallet tile (prd §1232), and
    /// a room off the five (Testnets) is nobody's tab.
    @MainActor static func current(_ source: String) -> PlaceTab? {
        if HomeScope.isMarkets(source) { return .wallet }
        // Day is the Feed's section (prd §1343); the Notes page is Library's
        // (prd §1347).
        if source == RoomAccounts.dayRoom { return .feed }
        if Pinboard.isPinnedRoom(source) { return .library }
        return allCases.first { $0.source == source }
    }
}

/// The bar itself, with Search beside it (prd §1327 items 1, 4 and 7). Read
/// down, it folds into one circle for the tab you are on, Search's beside it
/// (`ShellChrome.minimized`, the scroll fold the band already had); that
/// circle, or a scroll back up, unfolds it. While the tray is up the bar is
/// that one circle too, and it closes the tray: the tray's own field stands
/// where Search was.
struct PlaceTabBar: View {
    @Environment(ShellChrome.self) private var chrome
    let current: PlaceTab?
    let open: (PlaceTab) -> Void
    let search: () -> Void

    private var folded: Bool { chrome.minimized || chrome.roomsTray }
    /// **THE LABELS WIN OVER THE PAGE (user, 2026-10-15: "it is hard to see
    /// the icons and words especially when selected").** The glass takes the
    /// page's own ground as its tint, so a busy row under the bar sinks back
    /// instead of reading through the words; the pick stands on the strong
    /// fill, a lighter pill, as iOS 26's bar draws its selected tab.
    static var lens: Color { DS.page }
    private var size: CGFloat { DSDock.agentSize(fold: chrome.fold) }
    /// **THE BAR HUGS ITS TABS (prd §1374, user: "does it have to [span the
    /// bottom]? … i like the way C looks").** Each tab is one width, the bar
    /// stands at the leading edge and Search at the trailing one, which is
    /// where the fold already puts the tab's circle and Search's: the bar
    /// folds and unfolds in place, never sliding sideways.
    static let tabWidth: CGFloat = 74

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            if folded {
                foldedCircle
                Spacer(minLength: 0)
                if !chrome.roomsTray { searchCircle }
            } else {
                bar
                Spacer(minLength: 0)
                searchCircle
            }
        }
        .animation(DS.Motion.standard, value: folded)
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(PlaceTab.allCases) { tab in
                Button {
                    DSHaptic.selection()
                    open(tab)
                } label: {
                    VStack(spacing: 2) {
                        mark(tab, on: tab == current, glyphSize: .body)
                            .frame(height: 26)
                        Text(verbatim: tab.label)
                            .dsText(.label12)
                            .foregroundStyle(tab == current ? DS.brandInk : DS.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: Self.tabWidth)
                    .frame(maxHeight: .infinity)
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
                .modifier(LibraryAlarm(active: tab == .library))
                .background { if tab == .feed { FeedTabFrame() } }
            }
        }
        .padding(.horizontal, DS.Space.s1)
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
        .accessibilityHint(chrome.roomsTray ? Text("Closes the apps") : Text("Shows every place"))
        .background { if tab == .feed { FeedTabFrame() } }
    }

    private var searchCircle: some View {
        Button {
            DSHaptic.tap()
            search()
        } label: {
            Image(systemName: "magnifyingglass")
                .dsGlyph(.body, weight: .semibold)
                .foregroundStyle(DS.textPrimary)
                .frame(width: size, height: size)
                .dsGlass(cornerRadius: size / 2, tint: Self.lens)
                .dsTapTarget(Circle())
                .dsHover()
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text("Search"))
        .accessibilityHint(Text("Find anything, or make a page of it"))
    }

    @ViewBuilder
    private func mark(_ tab: PlaceTab, on: Bool, glyphSize: DSGlyph) -> some View {
        if tab == .library {
            LibraryFace()
        } else {
            Image(systemName: tab.glyph)
                .dsGlyph(glyphSize, weight: on ? .semibold : .regular)
                .foregroundStyle(on ? DS.brandInk : DS.textPrimary)
        }
    }
}

/// Where the capture flight lands (prd §930's seat, the Feed's door since):
/// the Feed's tab, as the face published it before.
private struct FeedTabFrame: View {
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { chrome.feedTabFrame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in chrome.feedTabFrame = f }
        }
    }
}

/// A broken app rings your face, as it rang the face's seat (`DoorAlarm`,
/// prd §798): Library is where the apps are mended. A leaf, so a landing
/// sweep's writes to `bridges` rebuild this and not the bar.
private struct LibraryAlarm: ViewModifier {
    let active: Bool
    @Environment(BridgeStore.self) private var bridges
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let broken = active && bridges.attentionCount > 0
        content
            .overlay(alignment: .top) {
                if broken {
                    Circle()
                        .strokeBorder(DS.attention, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                        .frame(width: 32, height: 32)
                        .offset(y: 3)
                        .transition(.scale(scale: 1.25).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .animation(reduceMotion ? nil : DS.Motion.press, value: broken)
            .accessibilityValue(broken ? Text("needs attention") : Text(verbatim: ""))
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
