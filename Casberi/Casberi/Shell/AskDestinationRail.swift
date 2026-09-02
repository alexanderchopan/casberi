import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// THE DECK — who answers, as keys on a device (prd §578, 2026-09-02, user:
/// "ink, extreme, large logo for bankr, large buttons to touch to select,
/// large text kinda stuff", then "less like a phone chat and more like a
/// device interface").
///
/// This began as a rail of round faces (§577), and the round face was the
/// problem: a circle is a PORTRAIT, so at 88pt it read as somebody's avatar
/// with a caption, and the caption had to shrink to fit under it. A rounded
/// SQUARE with a mark in one corner and a name across the bottom is a BUTTON —
/// the same object `DSActVerb` already is one tier down — and it has the room
/// to say what the destination actually reads from.
///
/// ## TWO SIZES, AND THE SWITCH IS A FACT ABOUT THE CONVERSATION
///
/// `.deck` is a 158pt key while nothing has been answered; `.strip` is 64pt
/// once a turn exists, because then the subject of the room is the answer and
/// this is the control you follow up with.
///
/// **The caller must never size this from `hasDraft` or `fieldFocused`.** The
/// deck sits directly above the composer's text field in one `VStack`, so a
/// head that changes height on a keystroke moves the field — and SwiftUI
/// answers a moved `TextField` by rebuilding its `UITextView`, which is the
/// §577c watchdog hang. `Composer.showsRail` is the gate and it reads the
/// conversation only.
///
/// ## ONE TINT, ON THE PRESSED KEY
///
/// The chosen key is filled `DS.tint` with everything on it white; the rest
/// are `surfaceRaised`. §570 stands — an agent brings no colour of its own —
/// and §563's budget is kept, because the pressed key and the verb below it
/// are the only saturated blocks on an otherwise ink screen.
///
/// ## ORDERING IS `AskDestination.split`'s, NOT THIS VIEW'S
///
/// The same function the capsule calls, with the same slot budget, so two
/// controls for one choice can never disagree about which agents are shown.
struct AskDestinationRail: View {
    enum Size { case deck, strip }

    let providers: [AgentProvider]
    /// The chosen destination. nil is the device.
    let active: AgentProvider?
    /// A live capture. Agents stand down for `AskDestinationCapsule`'s own
    /// stated reason: a voice note must never silently spend somebody's key.
    var recording: Bool = false
    var size: Size = .deck
    let onDevice: () -> Void
    let onAgent: (AgentProvider) -> Void

    private var keySide: CGFloat { size == .deck ? 158 : 64 }
    /// The mark's own tier off the ramp (`face-ramp-audit`): `shelf` on a
    /// deck key, which is the tier for "a horizontal face shelf, a profile
    /// head, a sheet's stage", and `list` on a strip key, the tier for a row
    /// you tap through. The WELL around it is larger than the mark by design —
    /// that is a button's target, not a face.
    private var markTier: CGFloat { size == .deck ? DS.Face.shelf : DS.Face.list }
    private var markSide: CGFloat { size == .deck ? 64 : 34 }
    private var radius: CGFloat { size == .deck ? 28 : 20 }

    private var deviceLabel: String { AskDestination.deviceLabel(isMac: DS.isMac, isPad: DS.isPad) }
    private var deviceGlyph: String { AskDestination.deviceGlyph(isMac: DS.isMac, isPad: DS.isPad) }

    /// What each destination answers FROM, in three words — the line the round
    /// rail had no room for. Drawn from `AskSubject` rather than written here,
    /// so the key and the draft note below it can never disagree about whose
    /// account Bankr uses.
    private func ground(for provider: AgentProvider?) -> String {
        switch AskSubject.ground(forAgent: provider?.rawValue) {
        case .ownAccount: return String(localized: "its own account")
        case .corpus, .search: return String(localized: "on your things")
        }
    }

    /// EVERY configured agent gets a key — there is no overflow here.
    ///
    /// The capsule caps its segments because it is a fixed-width row sharing
    /// one line with the mic and the send, so a fourth agent had to fold into
    /// a `+N` menu. A deck SCROLLS, so the budget that forced the menu does
    /// not exist: somebody with five keys pushed sideways sees five keys, and
    /// nothing is reachable only through a menu.
    ///
    /// `split` still decides the ORDER — most-recently-used first, the chosen
    /// one pulled forward — because two controls for one choice must not rank
    /// differently; only its slot cap is ignored, by putting the overflow back
    /// on the end.
    private var shown: [AgentProvider] {
        guard !recording else { return [] }
        let parts = AskDestination.split(configured: providers.map(\.rawValue),
                                         recent: AskDestination.recent(),
                                         active: active?.rawValue,
                                         slots: AskDestination.slots(findShown: false))
        return (parts.shown + parts.overflow)
            .compactMap { value in providers.first { $0.rawValue == value } }
    }

    var body: some View {
        // A ROW THAT SCROLLS, never a grid. Two keys fill a phone's width and a
        // third has to go somewhere; a second grid row would double the head's
        // height, and height is the one dimension the field below cannot
        // afford to have move.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s3) {
                key(title: deviceLabel, glyph: deviceGlyph,
                    ground: ground(for: nil), chosen: active == nil) {
                    DSHaptic.selection()
                    onDevice()
                }
                .accessibilityLabel("Answer on \(deviceLabel)")
                .accessibilityAddTraits(active == nil ? [.isSelected] : [])

                ForEach(shown) { provider in
                    key(title: provider.agent, mark: provider.agent,
                        ground: ground(for: provider), chosen: provider == active) {
                        DSHaptic.selection()
                        onAgent(provider)
                    }
                    .accessibilityLabel("Ask \(provider.agent)")
                    .accessibilityAddTraits(provider == active ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, DS.Space.s1)
        }
        // The fill TRAVELS between keys rather than one going dark as another
        // lights — the source chips' 2026-07-14 ruling ("selection is an
        // object traveling, not two states blinking").
        .animation(DS.Motion.standard, value: active)
        .animation(DS.Motion.standard, value: recording)
    }

    @ViewBuilder
    private func key(title: String, glyph: String? = nil, mark: String? = nil,
                     ground: String, chosen: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle().fill(chosen ? AnyShapeStyle(Color.white)
                                         : AnyShapeStyle(Color.white.opacity(0.14)))
                    if let mark {
                        BridgeIcon(name: mark, size: markTier, circular: true)
                    } else if let glyph {
                        Image(systemName: glyph)
                            .dsGlyph(markSide * 0.5, weight: .regular)
                            .foregroundStyle(chosen ? DS.tint : Color.white)
                    }
                }
                .frame(width: markSide, height: markSide)
                if size == .deck {
                    Spacer(minLength: DS.Space.s2)
                    Text(title)
                        .dsText(.heading22)
                        .foregroundStyle(chosen ? Color.white : DS.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(ground)
                        .dsText(.label12)
                        .foregroundStyle(chosen ? Color.white.opacity(0.75) : DS.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 2)
                }
            }
            .padding(size == .deck ? DS.Space.s4 : 0)
            .frame(width: keySide, height: keySide,
                   alignment: size == .deck ? .topLeading : .center)
            .background(chosen ? AnyShapeStyle(DS.tint) : AnyShapeStyle(DS.surfaceRaised),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .dsHover()
        }
        .buttonStyle(PressSpring())
        // The key that becomes the subject flips once — `coinFlip` is this
        // app's word for "this mark just became what the screen is about", and
        // choosing who answers is that event. Gated on CHOSEN, so the key you
        // pressed turns and the ones you did not are still.
        .coinFlip(trigger: chosen, enabled: chosen)
    }
}
