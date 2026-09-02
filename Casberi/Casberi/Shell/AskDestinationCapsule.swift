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
/// **THE FILL MARKS WHERE THE ASK IS GOING, NOT WHERE IT USUALLY GOES**
/// (2026-09-01, user: "when you tap 'ask bankr' the phone button stays blue so
/// you can't tell the bankr thing is activated"). The device segment wore the
/// fill unconditionally, which was true only until the first keyed ask: from
/// the tap onwards Bankr is answering, and a plain typed follow-up STAYS on it
/// (`conversationIsKeyed`, 2026-07-21) — so the blue pill was naming a
/// destination the return key no longer used, on the one control whose whole
/// job is to say who answers. It is `active` that decides now: nil means the
/// device, and only then does the device pill fill.
///
/// It is a fill and not a badge because there is exactly one destination at a
/// time — two lit segments would be the fake status §83 bans — and because the
/// device pill has meant "this is where it goes" since the capsule shipped;
/// moving that meaning to a second visual language would leave the fill saying
/// something else at the same time.
///
/// Agent segments exist only for configured keys, so with none the capsule is
/// the device pill alone and nothing claims a capability that isn't there.
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
    /// The agent the CURRENT ask is going to — the one in flight, or the one a
    /// plain send would still reach because the conversation is keyed to it.
    /// nil is the device, which is the resting state and the state after every
    /// free answer. Never `AgentKey.active` on its own: that is which key a
    /// keyed answer would SPEND, which is a different question from whether
    /// this conversation is keyed at all, and reading it here would light an
    /// agent segment for somebody who has only ever asked the phone.
    let active: AgentProvider?
    /// FIND, as the capsule's first segment (prd §575, 2026-09-02). nil when
    /// there is nothing to find — no draft, or a live recording.
    ///
    /// It joined the capsule because it was the second saturated block on the
    /// draft surface: a solid `DS.tint` capsule 40pt tall sitting a thumb-width
    /// from this row's own filled segment, so the screen carried two blue
    /// blocks and neither read as the act (§563's tint budget, which
    /// `hero-tint-audit.py` now enforces for hero TILES and cannot see here).
    /// One control naming every destination the text can go to is also the
    /// whole argument §543 made for this component; Find is a destination.
    ///
    /// **IT NEVER WEARS THE FILL, and that is not an omission.** The fill says
    /// where the RETURN KEY goes, which is the device and only the device
    /// (2026-08-31, unchanged). Find is a tap-only verb, and its result is its
    /// own mark: the count lockup that replaces the surface the moment it runs.
    /// Filling it would claim return searches, which it does not.
    let find: (() -> Void)?
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
        let parts = AskDestination.split(configured: raw, recent: AskDestination.recent(),
                                         active: active?.rawValue,
                                         slots: AskDestination.slots(findShown: find != nil))
        let byRaw = { (values: [String]) in
            values.compactMap { value in providers.first { $0.rawValue == value } }
        }
        return (byRaw(parts.shown), byRaw(parts.overflow))
    }

    var body: some View {
        let parts = split
        HStack(spacing: 2) {
            // FIND LEADS. It is the one verb here that keeps you inside the
            // app and writes nothing (§215), and it is the leftmost thing the
            // thumb reaches on a row that is right-aligned — but the ordering
            // reason that matters is that the segments read left to right as
            // "search this / ask this phone / ask an agent", cheapest first.
            if let find {
                Button {
                    DSHaptic.selection()
                    find()
                } label: {
                    segment(glyph: "magnifyingglass",
                            title: String(localized: "Find"), filled: false)
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel("Find in your things")
            }
            Button {
                DSHaptic.selection()
                onDevice()
            } label: {
                segment(glyph: deviceGlyph, title: deviceLabel, filled: active == nil)
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(hasDraft ? "Ask \(deviceLabel)" : "Ask \(deviceLabel) — answered on this device")
            // The fill is a colour, so it says nothing to VoiceOver on its own
            // — the same fact has to be spoken, or the control that names the
            // destination is the one control a screen reader cannot read it
            // from.
            .accessibilityAddTraits(active == nil ? [.isSelected] : [])

            ForEach(parts.shown) { provider in
                Button {
                    DSHaptic.selection()
                    onAgent(provider)
                } label: {
                    segment(mark: provider.agent, title: provider.agent,
                            filled: provider == active)
                }
                .buttonStyle(PressSpring())
                .accessibilityLabel("Ask \(provider.agent) with your key")
                .accessibilityAddTraits(provider == active ? [.isSelected] : [])
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
        // The Find segment arrives with the first character and leaves with
        // the last, and the row re-lays out around it — an agent segment folds
        // into the overflow as it comes. One motion, the same curve the fill
        // travels on, so the two never read as two separate events.
        .animation(DS.Motion.standard, value: find != nil)
        // The fill MOVES between segments rather than blinking off one and on
        // at another — the source chips' own 2026-07-14 ruling ("selection is
        // an object traveling, not two states blinking"), which is what makes
        // the hand-off legible at the moment it matters: the tap.
        .animation(DS.Motion.standard, value: active)
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
