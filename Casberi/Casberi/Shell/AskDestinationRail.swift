import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// THE DESTINATIONS, AS FACES (prd §577, 2026-09-02).
///
/// `AskDestinationCapsule` is the same choice at 32pt, in a row of pill
/// segments at the trailing end of the control row, and it stays exactly
/// that at rest and under a settled answer — nothing about §543's ruling is
/// reversed. This is what the same choice looks like while you are actually
/// composing, on the surface that turns blue for it: **the chosen destination
/// becomes an 88pt face and the others wait at 44.**
///
/// ## WHY THE SAME CHOICE GETS TWO SIZES
///
/// Chrome is priced by frequency of use (`AgentBar`'s rest ruling), and the
/// composing state inverts that price. At rest, who would answer is a fact you
/// glance at; while you are writing an instruction that may spend money, it is
/// the single most consequential thing on the screen — §563's inversion, on the
/// surface where getting it wrong is most expensive. So the control does not
/// move or change its meaning; it grows.
///
/// ## THE PICK WORKS BEFORE OR AFTER THE WORDS
///
/// The rail is mounted for the whole composing state, so Bankr can be chosen
/// with an empty field and then typed into, or chosen after the sentence is
/// already written. That is not a nicety — the two orders are genuinely
/// different intentions ("I want to ask Bankr something" and "who should get
/// this?") and a picker that only exists in one of them makes the other a
/// retype.
///
/// ## ORDERING IS `AskDestination.split`'s, NOT THIS VIEW'S
///
/// The same function the capsule calls, with the same slot budget, so the two
/// controls can never disagree about which agents are shown or in what order.
/// A rail that ranked its own faces would be a second ordering of one list —
/// the duplicated-parser class this repo keeps paying for, wearing a picker's
/// clothes.
struct AskDestinationRail: View {
    enum Size { case large, compact }

    let providers: [AgentProvider]
    /// The chosen destination. nil is the device.
    let active: AgentProvider?
    /// A live capture. Agents stand down for `AskDestinationCapsule`'s own
    /// stated reason: a voice note must never silently spend somebody's key.
    var recording: Bool = false
    var size: Size = .large
    /// Drawn on the tint (white on blue) or on ink (the app's own tokens).
    ///
    /// The rail began life tint-only, when the whole ask surface was blue.
    /// §577b kept the blue for the WAIT alone, so the same control now has to
    /// sit on both grounds — and it takes the parameter rather than reading
    /// the colour scheme because the ground here is a STATE of this surface,
    /// not the device's theme.
    var onTint: Bool = false
    /// Find as a face of its own. nil when there is nothing to find — no
    /// draft, or a live recording — so it can never be a segment that refuses
    /// (§83).
    var find: (() -> Void)?
    let onDevice: () -> Void
    let onAgent: (AgentProvider) -> Void

    private var chosenDiameter: CGFloat { size == .large ? 88 : 44 }
    private var restingDiameter: CGFloat { size == .large ? 44 : 36 }

    private var deviceLabel: String { AskDestination.deviceLabel(isMac: DS.isMac, isPad: DS.isPad) }
    private var deviceGlyph: String { AskDestination.deviceGlyph(isMac: DS.isMac, isPad: DS.isPad) }

    private var shown: [AgentProvider] {
        guard !recording else { return [] }
        let parts = AskDestination.split(configured: providers.map(\.rawValue),
                                         recent: AskDestination.recent(),
                                         active: active?.rawValue,
                                         slots: AskDestination.slots(findShown: find != nil))
        return parts.shown.compactMap { value in providers.first { $0.rawValue == value } }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: size == .large ? DS.Space.s4 : DS.Space.s3) {
            if let find {
                // FIND IS NEVER THE CHOSEN FACE, for the capsule's own reason
                // one control over: the chosen face says where the RETURN KEY
                // goes, and Find is tap-only. Drawing it large would claim
                // return searches.
                face(title: String(localized: "Find"), glyph: "magnifyingglass",
                     chosen: false, action: {
                         DSHaptic.selection()
                         find()
                     })
                .accessibilityLabel("Find in your things")
            }
            face(title: deviceLabel, glyph: deviceGlyph, chosen: active == nil, action: {
                DSHaptic.selection()
                onDevice()
            })
            .accessibilityLabel("Answer on \(deviceLabel)")
            .accessibilityAddTraits(active == nil ? [.isSelected] : [])

            ForEach(shown) { provider in
                face(title: provider.agent, mark: provider.agent,
                     chosen: provider == active, action: {
                         DSHaptic.selection()
                         onAgent(provider)
                     })
                .accessibilityLabel("Ask \(provider.agent)")
                .accessibilityAddTraits(provider == active ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        // The chosen face TRAVELS between destinations rather than one
        // shrinking as another grows in isolation — the source chips' own
        // 2026-07-14 ruling ("selection is an object traveling, not two states
        // blinking"), which is the whole legibility of the hand-off at the
        // moment it matters: the tap.
        .animation(DS.Motion.standard, value: active)
        .animation(DS.Motion.standard, value: recording)
        .animation(DS.Motion.standard, value: find != nil)
    }

    @ViewBuilder
    private func face(title: String, glyph: String? = nil, mark: String? = nil,
                      chosen: Bool, action: @escaping () -> Void) -> some View {
        let d = chosen ? chosenDiameter : restingDiameter
        Button(action: action) {
            VStack(spacing: DS.Space.s2) {
                ZStack {
                    // THE CHOSEN FACE IS WHITE, THE REST ARE WASHED WHITE —
                    // and neither carries a hue of its own. §570's ruling
                    // ("why not use blue since we do everywhere? changing
                    // different colors is going to make the language drift")
                    // is why an agent does not get to bring its own colour to
                    // this rail; the brand mark inside the disc is identity
                    // enough, and it is the same mark the capsule draws.
                    Circle().fill(chosen
                                  ? AnyShapeStyle(onTint ? Color.white : DS.tint)
                                  : AnyShapeStyle(onTint ? Color.white.opacity(0.18)
                                                         : DS.gray100))
                    // Two calls, not one with a ternary size: a face's rung is
                    // decided by what it sits beside (`face-ramp-audit`), and
                    // the chosen disc is a shelf-scale object while the rest
                    // are row-scale — two tiers, two call sites, so the audit
                    // can read each one.
                    if let mark, chosen {
                        BridgeIcon(name: mark, size: DS.Face.shelf, circular: true)
                    } else if let mark {
                        BridgeIcon(name: mark, size: DS.Face.row, circular: true)
                    } else if let glyph {
                        Image(systemName: glyph)
                            .dsGlyph(d * 0.42, weight: .regular)
                            .foregroundStyle(chosen ? (onTint ? DS.tint : Color.white)
                                                    : (onTint ? Color.white : DS.textSecondary))
                    }
                }
                .frame(width: d, height: d)
                // THE FACE THAT BECOMES THE SUBJECT FLIPS ONCE (prd §577a).
                // `coinFlip` is this app's own word for "this mark just became
                // what the screen is about" — a thing sheet's header, a source
                // chip on a room change — and picking who answers is the same
                // event. It fires on the CHOSEN flag rather than on every
                // render, so the face you tapped turns and the ones you did
                // not are still.
                //
                // The size change is already a spring; this rides on top of it
                // so the disc turns as it grows rather than simply inflating.
                // Reduce Motion is handled inside the modifier.
                .coinFlip(trigger: chosen, enabled: chosen)
                if size == .large {
                    Text(title)
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(chosen ? (onTint ? Color.white : DS.textPrimary)
                                                : (onTint ? Color.white.opacity(0.55) : DS.textTertiary))
                        .lineLimit(1)
                }
            }
            // The unchosen faces stand on the SAME baseline as the chosen
            // one's label rather than floating at their own height — the row
            // is bottom-aligned, so a 44pt face and an 88pt face share a
            // floor and the difference reads as size rather than as position.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .dsHover()
        }
        .buttonStyle(PressSpring())
    }
}
