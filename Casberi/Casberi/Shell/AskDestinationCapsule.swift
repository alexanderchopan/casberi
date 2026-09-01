import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// THE ASK CAPSULE — one component, every destination (prd §543, 2026-08-31).
///
/// Sits at the trailing end of the composer's control row, in every state:
/// at rest, with a draft, and under a settled answer. One anatomy, one place,
/// so it is learnable — typing changes nothing about it except what a tap
/// does.
///
/// **There is no send button anywhere.** Tapping a segment IS the send to
/// that destination. The arrow this replaced meant "ask", which on a surface
/// where the other controls were named "Ask Claude" and "Ask Bankr" made the
/// device the one unnamed destination — the reported confusion, and the
/// reason a selector-plus-send row was rejected before it: choosing and
/// sending as two controls leaves nothing on screen saying which one the
/// arrow would use.
///
/// The device segment wears the fill because it is what the return key does
/// (free, on-device, nothing leaves). Agent segments exist only for
/// configured keys, so with none the capsule is the device pill alone and
/// nothing claims a capability that isn't there.
struct AskDestinationCapsule: View {
    /// Configured providers in `AgentProvider.allCases` order — the canonical
    /// order `AskDestination.split` falls back to.
    let providers: [AgentProvider]
    /// Whether there is something to send. At rest a tap ARMS the field at
    /// that destination; with a draft the same tap sends. Same control, same
    /// place — the difference is only whether a question exists yet.
    let hasDraft: Bool
    /// A live voice capture. Agents stand down: a voice note must never
    /// silently spend somebody's key, and stopping the mic is a commit, not a
    /// choice of who answers.
    let recording: Bool
    let onDevice: () -> Void
    let onAgent: (AgentProvider) -> Void

    private var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    private var isPad: Bool {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    private var deviceLabel: String { AskDestination.deviceLabel(isMac: isMac, isPad: isPad) }
    private var deviceGlyph: String { AskDestination.deviceGlyph(isMac: isMac, isPad: isPad) }

    /// Agents stand down entirely while recording, so the split runs over an
    /// empty set and the capsule collapses to the device pill — the one
    /// destination a voice note can have.
    private var split: (shown: [AgentProvider], overflow: [AgentProvider]) {
        guard !recording else { return ([], []) }
        let raw = providers.map(\.rawValue)
        let parts = AskDestination.split(configured: raw, recent: AskDestination.recent())
        let byRaw = { (values: [String]) in
            values.compactMap { value in providers.first { $0.rawValue == value } }
        }
        return (byRaw(parts.shown), byRaw(parts.overflow))
    }

    var body: some View {
        let parts = split
        HStack(spacing: 2) {
            Button {
                DSHaptic.selection()
                onDevice()
            } label: {
                segment(glyph: deviceGlyph, title: deviceLabel, filled: true)
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(hasDraft ? "Ask \(deviceLabel)" : "Ask \(deviceLabel) — answered on this device")

            ForEach(parts.shown) { provider in
                Button {
                    DSHaptic.selection()
                    onAgent(provider)
                } label: {
                    segment(mark: provider.agent, title: provider.agent, filled: false)
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel("Ask \(provider.agent) with your key")
            }

            if !parts.overflow.isEmpty {
                // A MENU, not an inline expansion: the row has a fixed width
                // beside the mic and lower buttons, so expanding in place
                // would push the earlier segments off their own edge. The
                // menu's items send exactly as a segment does — one tap,
                // same outcome — so nothing is reachable only by segment.
                Menu {
                    ForEach(parts.overflow) { provider in
                        Button {
                            onAgent(provider)
                        } label: {
                            Label("Ask \(provider.agent)", systemImage: "sparkles")
                        }
                    }
                } label: {
                    Text("+\(parts.overflow.count)")
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, DS.Space.s3)
                        .frame(minHeight: 32)
                        .dsHover()
                }
                .accessibilityLabel("\(parts.overflow.count) more agents")
            }
        }
        .padding(2)
        .background(DS.fillFaint, in: Capsule(style: .continuous))
        .animation(DS.Motion.standard, value: recording)
    }

    @ViewBuilder
    private func segment(glyph: String? = nil, mark: String? = nil,
                         title: String, filled: Bool) -> some View {
        HStack(spacing: DS.Space.s1 + 1) {
            if let glyph {
                Image(systemName: glyph)
                    .dsGlyph(13)
                    .accessibilityHidden(true)
            } else if let mark {
                // The agent's own brand mark, never a key glyph (user,
                // 2026-08-31) — every provider seat bundles one.
                BridgeIcon(name: mark, size: DS.Face.badge, circular: true)
                    .accessibilityHidden(true)
            }
            Text(title)
                .dsText(.label12).fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundStyle(filled ? Color.white : DS.textPrimary)
        .padding(.horizontal, DS.Space.s2)
        .frame(minHeight: 32)
        .background(filled ? AnyShapeStyle(DS.tint) : AnyShapeStyle(Color.clear),
                    in: Capsule(style: .continuous))
        .dsHover()
    }
}
