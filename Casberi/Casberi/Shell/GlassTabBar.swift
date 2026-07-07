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
    /// One pulse when a capture lands (§1 choreography) — scale up then back.
    @State private var feedPulse = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                let active = tab == selection
                Button {
                    DSHaptic.selection()
                    withAnimation(DS.Motion.standard) { selection = tab }
                } label: {
                    VStack(spacing: DS.Space.s1) {
                        tabIcon(for: tab, active: active)
                        if !chrome.minimized {
                            Text(tab.label).dsText(.tab10)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                    // White (not accent blue) when active: the lozenge already
                    // marks the selection, and blue-on-a-colored-background was
                    // hard to read (ruling 2026-07-06).
                    .foregroundStyle(active ? DS.textPrimary : DS.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: chrome.minimized ? 40 : 48)
                    .background {
                        if active {
                            // The liquid selection: one bright capsule that
                            // slides between tabs rather than blinking.
                            Capsule(style: .continuous)
                                .fill(DS.fillStrong)
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
        Image(systemName: tab.symbol)
            .font(.system(size: 20, weight: active ? .semibold : .regular))
            .scaleEffect(tab == .feed && feedPulse ? 1.15 : 1.0)
            .modifier(FeedTabInstruments(isFeed: tab == .feed, chrome: chrome,
                                         pulse: $feedPulse))
    }
}

/// Instruments on the Feed tab only: reports its frame so the capture flight
/// knows where to land, and pulses the icon once when one does.
private struct FeedTabInstruments: ViewModifier {
    let isFeed: Bool
    let chrome: ShellChrome
    @Binding var pulse: Bool

    func body(content: Content) -> some View {
        if isFeed {
            content
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    chrome.feedTabFrame = frame
                }
                .onChange(of: chrome.landedPulse) {
                    withAnimation(.easeOut(duration: 0.125)) { pulse = true }
                    Task {
                        try? await Task.sleep(for: .milliseconds(125))
                        withAnimation(.easeIn(duration: 0.125)) { pulse = false }
                    }
                }
        } else {
            content
        }
    }
}
