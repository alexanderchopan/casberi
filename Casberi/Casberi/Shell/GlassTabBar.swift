import SwiftUI

/// Two tabs (amendment 2026-07-06, late — the shell settles: Casberi has exactly
/// two workspaces, Home and Feed; everything else is management and hangs off
/// Home's nav bar): Home, Feed. Landing is Home (set by `RootShell`). Apps and
/// Settings are pushed from Home's toolbar (grid glyph → Apps, avatar → Settings)
/// — a tab is a destination you live in, not a drawer you visit. A tab carries
/// no indicator (ruling); breakage shows as an attention dot on Home's Apps
/// button, which is a nav button, not a tab.
enum Tab: String, CaseIterable, Identifiable {
    case home, feed
    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .feed: return "Feed"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .feed: return "waveform.path.ecg"
        }
    }
}

/// The glass capsule tab bar. Active = tint; inactive = tertiary text.
/// One accent only (principle 2).
struct GlassTabBar: View {
    @Binding var selection: Tab
    /// The shell's glass namespace — the capsule joins the composer's morph.
    var glassNamespace: Namespace.ID? = nil
    /// The selection lozenge slides between tabs like liquid (iOS 26 grammar).
    @Namespace private var lozengeNS
    @Environment(ShellChrome.self) private var chrome
    /// A tap bounces ITS tab's icon (Telegram grammar) — select and re-tap
    /// both; the other tab never moves.
    @State private var bounces: [Tab: Int] = [:]

    /// A management screen (Apps/Settings) is covering the current tab — read
    /// from the two route singletons. While one is up NO tab lights: the bar
    /// reads "you're off Home and Feed", and a tab tap jumps straight there
    /// (2026-07-10, replacing the earlier hide-the-whole-bar treatment).
    private var managementOpen: Bool {
        HomeRoute.shared.push != nil || FeedRoute.shared.push != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                // In a management screen NO tab is active — the bar stops
                // pretending you're on the tab you entered it from.
                let active = !managementOpen && tab == selection
                Button {
                    DSHaptic.selection()
                    bounces[tab, default: 0] += 1
                    if selection == tab {
                        // Tapping the current tab pops to its root. When a
                        // management screen is up, that pop (popHome/popFeed
                        // clears the tab's route push) is what leaves it.
                        switch tab {
                        case .home: chrome.popHome += 1
                        case .feed: chrome.popFeed += 1
                        }
                    } else {
                        // A deliberate tab tap supersedes a stale jump AND
                        // leaves any management screen — clear both route pushes
                        // so the origin tab returns to root and this tab lights
                        // cleanly. All in one animation, so the lozenge lands on
                        // the destination instead of flashing the origin first.
                        withAnimation(DS.Motion.standard) {
                            HomeRoute.shared.push = nil
                            FeedRoute.shared.push = nil
                            chrome.jumpedFromHome = false
                            selection = tab
                        }
                    }
                } label: {
                    VStack(spacing: DS.Space.s1) {
                        tabIcon(for: tab, active: active)
                        if !chrome.minimized {
                            Text(tab.label).dsText(.tab10)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                    // White mark on the blue field — the active tab echoes the
                    // app icon itself (re-ruling 2026-07-08; the earlier
                    // blue-ICON idea stays dead — this is the inverse).
                    .foregroundStyle(active ? .white : DS.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: chrome.minimized ? 40 : 48)
                    .background {
                        if active {
                            // The liquid selection: one Casberi-blue capsule
                            // that slides between tabs rather than blinking.
                            Capsule(style: .continuous)
                                .fill(DS.tint)
                                .padding(.vertical, 2)
                                .matchedGeometryEffect(id: "lozenge", in: lozengeNS)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
            }
        }
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, DS.Space.s1)
        .dsGlass(cornerRadius: DS.Radius.pill, glassID: "tabbar", in: glassNamespace)
    }

    @ViewBuilder
    private func tabIcon(for tab: Tab, active: Bool) -> some View {
        // One native symbol bounce carries both moments: a tap bounces ITS
        // tab, and a capture landing (§1 choreography) bounces Feed — both
        // counters only ever increment, so the sum changes whenever either
        // does. The hand-rolled scale pulse retired for the system's own
        // move (motion pass 2026-07-11; Reduce Motion handled for free).
        Image(systemName: tab.symbol)
            .font(.system(size: 20, weight: active ? .semibold : .regular))
            .symbolEffect(.bounce, value: bounces[tab, default: 0]
                + (tab == .feed ? chrome.landedPulse : 0))
            // The capture flight lands on the Feed tab — report its frame.
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                if tab == .feed { chrome.feedTabFrame = frame }
            }
    }
}
