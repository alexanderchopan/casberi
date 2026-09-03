import SwiftUI

// MARK: - The foot (prd §581)

/// Who answers, as round keys, in the foot beside the verb.
///
/// This replaces `AskDestinationRail` on the risen surface and the reasoning is
/// the user's own: §578's 158pt deck and §580's 64pt strip were the same
/// control drawn twice at two sizes, and both of them sat ABOVE the words,
/// which meant the head of the screen was a picker for a decision most people
/// make once. "I like the switcher at the footer" (2026-09-03) — so it is one
/// control, in one place, in every state.
///
/// **A ROW OF CIRCLES, and the circle is the point.** §578 lost the round face
/// because at 88pt with a caption under it a circle read as somebody's avatar.
/// Here there is no caption: the key is 88pt of pressable ink with a mark in
/// it, sitting beside a capsule verb of exactly the same height, so it reads as
/// hardware rather than as a portrait. The name it lost is not missed, because
/// the paper above says whose answer you are looking at.
///
/// **Selection is the fill, and it is white rather than tint.** §563 allows one
/// saturated block per surface and the verb has it: an armed Send is the only
/// blue thing on the screen, so a lit destination must be the other extreme
/// rather than a second blue (§580's own inverted-strip ruling, kept).
struct AgentDestinationKeys: View {

    /// Every configured agent, in declared order. No slot cap and no overflow
    /// menu: `AskDestination.split` chose which agents may show when the
    /// control was a fixed-width row sharing a line with a mic and a send, and
    /// a scroller has no such budget — nothing here is reachable only through
    /// a menu (§578's ruling, carried).
    let providers: [AgentProvider]
    /// nil is the device.
    let active: AgentProvider?
    /// Drawn in place of the second key when no agent is configured at all.
    /// A destination-shaped hole rather than a banner: the offer lives exactly
    /// where the choice is made, so it needs no dismissal and can never be the
    /// dead control §83 bans.
    var onAddAgent: (() -> Void)? = nil
    /// The chosen destination is working. Its mark BREATHES — a slow scale on
    /// the one thing already saying who answers — which replaces the 64pt
    /// stopwatch §580 put on the paper (user, 2026-09-03: "i don't know we
    /// want that to be a large number. maybe have the icon there breathing
    /// while it is thinkign inside the selector"). A number that large is the
    /// biggest thing on the screen for the one moment there is nothing to
    /// read, and it pushed the answer out of view when it arrived.
    var thinking: Bool = false
    let onDevice: () -> Void
    let onAgent: (AgentProvider) -> Void

    /// 88pt, which is what makes this a key you press without looking. It is
    /// also the wide verb's height, so the foot is one row of one size.
    static let side: CGFloat = 88

    /// The widest the key row may grow before it starts scrolling.
    ///
    /// EXACTLY TWO KEYS, and the number is a whole one on purpose: at 214 the
    /// third key was cut down its middle by the verb beside it, which reads as
    /// a rendering fault rather than as "there are more" (seen on the
    /// simulator, 2026-09-03). A partial circle is only a peek when there is
    /// air after it; against a capsule it is a broken one.
    static let keysCeiling: CGFloat = side * 2 + DS.Space.s2

    /// What the keys would take if nothing constrained them.
    private var intrinsicWidth: CGFloat {
        let count = CGFloat(providers.count + 1 + (providers.isEmpty && onAddAgent != nil ? 1 : 0))
        return count * Self.side + max(0, count - 1) * DS.Space.s2
    }

    private var deviceGlyph: String { AskDestination.deviceGlyph(isMac: DS.isMac, isPad: DS.isPad) }
    private var deviceLabel: String { AskDestination.deviceLabel(isMac: DS.isMac, isPad: DS.isPad) }

    var body: some View {
        // A ScrollView even at two keys, so the fourth destination shows past
        // the edge rather than folding into a control nobody finds. It never
        // scrolls when everything fits.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                key(chosen: active == nil, action: onDevice) {
                    Image(systemName: deviceGlyph)
                        .dsGlyph(38, weight: .regular)
                        .foregroundStyle(active == nil ? Color.white : DS.textTertiary)
                        .agentBreath(thinking && active == nil)
                }
                .accessibilityLabel("Answer on \(deviceLabel)")
                .accessibilityAddTraits(active == nil ? [.isSelected] : [])

                ForEach(providers) { provider in
                    key(chosen: provider == active, action: { onAgent(provider) }) {
                        // A BRAND MARK IS OPAQUE AND FULL-BLEED, so the key's
                        // own fill survives only as a ring around it — which
                        // is why the first cut of this control was reported as
                        // "you can't tell when you selected which agent"
                        // (2026-09-03). The selection cannot be carried by the
                        // fill on these keys, so it is carried by the MARK:
                        // the chosen agent is the only one at full strength
                        // and the rest stand down. Legible whatever the
                        // artwork happens to look like, which a ring is not.
                        BridgeIcon(name: provider.agent, size: DS.Face.shelf, circular: true)
                            .opacity(provider == active ? 1 : 0.38)
                            .saturation(provider == active ? 1 : 0)
                            .agentBreath(thinking && provider == active)
                    }
                    .accessibilityLabel("Ask \(provider.agent)")
                    .accessibilityAddTraits(provider == active ? [.isSelected] : [])
                }

                if providers.isEmpty, let onAddAgent {
                    key(chosen: false, action: onAddAgent) {
                        Image(systemName: "plus")
                            .dsGlyph(34, weight: .regular)
                            .foregroundStyle(DS.textTertiary)
                    }
                    .accessibilityLabel("Set up an agent")
                }
            }
            .padding(.horizontal, 1)
        }
        // THE KEYS TAKE THEIR OWN WIDTH AND NO MORE. A `ScrollView` is
        // greedy and so is a `maxWidth: .infinity` verb beside it, and the
        // verb won: the keys collapsed to ZERO and the foot rendered as a
        // lone capsule with no destinations at all (seen on the simulator,
        // 2026-09-03). A layout priority cannot settle a fight between two
        // views that both want everything — a width can.
        //
        // The cap leaves the verb at least `verbFloor`, so past three
        // destinations the row scrolls and the next key shows past the edge,
        // which is what a scroller is for.
        // A HARD WIDTH, not a ceiling. `maxWidth` is only an upper bound and
        // SwiftUI is free to hand this view ZERO — which is exactly what a
        // `maxWidth: .infinity` verb beside it caused: the whole key row
        // rendered as nothing and the foot was a lone capsule with no
        // destinations on it (seen on the simulator twice, 2026-09-03).
        .frame(width: min(intrinsicWidth, Self.keysCeiling))
        // A FADE WHEN THERE IS MORE. Two keys fit; a third scrolls, and
        // SwiftUI draws no indicator for it — so without this a configured
        // agent is simply absent with nothing saying to look for it, which is
        // a destination you cannot reach by any means you can see (§83). A cut
        // circle said it and read as a rendering fault; a fade says it and
        // reads as an edge.
        .mask(alignment: .leading) {
            LinearGradient(stops: intrinsicWidth > Self.keysCeiling
                           ? [.init(color: .black, location: 0),
                              .init(color: .black, location: 0.86),
                              .init(color: .clear, location: 1)]
                           : [.init(color: .black, location: 0),
                              .init(color: .black, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(DS.Motion.standard, value: active)
        .animation(DS.Motion.standard, value: thinking)
    }

    @ViewBuilder
    private func key<Mark: View>(chosen: Bool, action: @escaping () -> Void,
                                 @ViewBuilder mark: () -> Mark) -> some View {
        Button(action: { DSHaptic.selection(); action() }) {
            ZStack {
                // THE LIT KEY IS BLUE (2026-09-03, user: "we should make the
                // white around the active icon blue"). §581a made it white on
                // the §580 reasoning that the armed verb owns the one
                // saturated block — but the verb is only armed once there are
                // words, and at rest the foot had no colour at all while the
                // one thing worth pointing at was the destination. Tint says
                // "this is the live one" in the app's own voice, and the two
                // never compete for the same meaning: the ring says WHO, the
                // verb says WHAT HAPPENS NEXT.
                Circle().fill(chosen ? AnyShapeStyle(DS.tint)
                                     : AnyShapeStyle(DS.fillFaint))
                mark()
            }
            .frame(width: Self.side, height: Self.side)
            .contentShape(Circle())
            .dsHover()
        }
        .buttonStyle(PressSpring())
        // NO FLIP. §578 gave the chosen key a `coinFlip` — this app's word for
        // "this mark just became what the screen is about" — and on a row you
        // tap to switch back and forth it was reported as "too much"
        // (2026-09-03). That gesture is right for a mark that becomes the
        // SUBJECT of a screen once; here it fires on an ordinary toggle, every
        // time, twice if you change your mind. The state change is carried by
        // the mark's own opacity and colour, crossfaded by the row's
        // animation, and by the line above it. The press already has
        // `PressSpring` and a selection haptic; a flip on top is a third
        // answer to a question already answered twice.
    }
}

/// A slow scale that says "still going" without claiming to know how long.
///
/// The motion law's rule for a loop: it may run only while something real is
/// pending, and it must stand down for Reduce Motion — where it holds the
/// mark at full size, which is a legible resting state rather than a frozen
/// half-breath.
private struct AgentBreath: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inhaled = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && inhaled && !reduceMotion ? 1.08 : 1)
            .opacity(active && inhaled && !reduceMotion ? 0.72 : 1)
            .animation(active && !reduceMotion
                       ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                       : DS.Motion.standard,
                       value: inhaled)
            .onChange(of: active, initial: true) { _, now in
                inhaled = now
            }
    }
}

extension View {
    func agentBreath(_ active: Bool) -> some View {
        modifier(AgentBreath(active: active))
    }
}

/// The one wide slot in the foot, wearing whatever verb is available.
///
/// **The slot never moves and never changes shape** — it is the §577c rule
/// applied to the verb rather than to the field: Record, Find, Ask, Send, Stop
/// and a failure's own fix are one capsule at one height in one position, so
/// the thing under your thumb is always the thing that acts.
///
/// A dim Send with nothing to send was a dead control; at rest the slot carries
/// the verb that IS available, which is Record — the voice-note capture path,
/// a real thing that enters the corpus rather than dictation. That is how the
/// mic keeps its door without taking a key.
struct AgentWideKey: View {
    enum Tone { case tint, ink, quiet }

    var title: String?
    var glyph: String?
    var tone: Tone = .ink
    /// Icon-only keys are round, so Find beside Ask reads as a sibling of the
    /// destination keys rather than as a squashed button.
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                if let glyph {
                    Image(systemName: glyph)
                        .dsGlyph(compact ? 30 : 26, weight: .regular)
                }
                if let title {
                    Text(title)
                        .dsText(.heading22)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(ink)
            // A MINIMUM, not just a maximum. The keys beside this sit in a
            // greedy `ScrollView`, so without a floor of its own the verb is
            // the thing that gets squeezed — and the verb is the one control
            // on the surface that must always be pressable.
            .frame(minWidth: compact ? nil : AgentDestinationKeys.side,
                   maxWidth: compact ? nil : .infinity)
            .frame(width: compact ? AgentDestinationKeys.side : nil,
                   height: AgentDestinationKeys.side)
            .background(wash, in: shape)
            .contentShape(shape)
            .dsHover()
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(title ?? (glyph.map { _ in "Record a voice note" } ?? ""))
    }

    private var shape: AnyShape {
        compact ? AnyShape(Circle()) : AnyShape(Capsule(style: .continuous))
    }

    private var ink: Color {
        switch tone {
        case .tint:  return .white
        case .ink:   return DS.textPrimary
        case .quiet: return DS.textTertiary
        }
    }

    private var wash: Color {
        switch tone {
        case .tint:         return DS.tint
        case .ink, .quiet:  return DS.surfaceRaised
        }
    }
}

// MARK: - The paper

/// YOUR QUESTION, AS A BUBBLE.
///
/// §581 folded it to a 12pt "You asked" caption on the reasoning that you
/// wrote it and already know what it says. True, and beside the point: what a
/// caption cannot do is say WHOSE WORDS THESE ARE. Reported 2026-09-03 — "it is
/// confusing what text is what" — over a screen holding a grey question, a
/// grey destination line and a grey reply, none of which announced its author.
///
/// A bubble is the one convention every person on a phone already reads
/// without being taught, and using it HERE costs nothing that §581 was
/// protecting: the surface is still not a chat, because there is exactly one
/// bubble and it is always yours. The agent's words never take one — they are
/// set on the paper, at the display rung, which is what keeps the answer the
/// subject and the question the label.
///
/// Trailing-aligned and raised, so authorship reads from the SHAPE before a
/// word is read.
struct AgentAskedCaption: View {
    let question: String

    var body: some View {
        HStack {
            Spacer(minLength: DS.Space.s6)
            Text(question)
                .dsText(.callout15)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Space.s3)
                .padding(.vertical, DS.Space.s2)
                .background(DS.surfaceRaised, in: RoundedRectangle(cornerRadius: DS.Radius.sheet,
                                                                   style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You asked: \(question)")
    }
}

/// The agent's written reply, in a bubble of its own.
///
/// §581 set a reply as the SCREEN — first sentence at the display rung, the
/// rest below it — and the device verdict was that the question, the
/// destination line and the reply were three greys with nothing saying whose
/// words were whose ("it is confusing what text is what", 2026-09-03). The
/// answer is the same one the question got: **a bubble**, the one convention
/// every person on a phone already reads without being taught.
///
/// LEADING, where the question's is trailing. That single mirror is what makes
/// authorship legible before a word is read, and it is why both sides needed
/// one — a lone bubble says "somebody said this" and not who.
///
/// The lead/rest split survives INSIDE it and still earns its harness: the
/// first sentence is white and heavier, what follows is secondary and a rung
/// down. What changed is the scale — a 40pt headline inside a bubble is a
/// poster in an envelope, and the bubble is now what separates the voices, so
/// the type no longer has to do that job alone.
struct AgentProseAnswer: View {
    let text: String
    /// A failure is an answer and wears this same anatomy, with one colour
    /// swapped. Amber, never red: a refused key and an unreachable host are
    /// things to fix, not damage that has been done.
    var attention = false

    var body: some View {
        let parts = AgentReply.split(text)
        HStack {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if !parts.lead.isEmpty {
                    Text(parts.lead)
                        .dsText(.heading22)
                        .foregroundStyle(attention ? DS.attention : DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !parts.rest.isEmpty {
                    Text(parts.rest)
                        .dsText(.reading20)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s3)
            .background(DS.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
            .textSelection(.enabled)
            Spacer(minLength: DS.Space.s8)
        }
    }
}
