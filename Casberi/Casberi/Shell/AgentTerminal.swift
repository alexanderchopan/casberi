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
    let onDevice: () -> Void
    let onAgent: (AgentProvider) -> Void

    /// 88pt, which is what makes this a key you press without looking. It is
    /// also the wide verb's height, so the foot is one row of one size.
    static let side: CGFloat = 88

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
                        .foregroundStyle(active == nil ? DS.inkGround : DS.textSecondary)
                }
                .accessibilityLabel("Answer on \(deviceLabel)")
                .accessibilityAddTraits(active == nil ? [.isSelected] : [])

                ForEach(providers) { provider in
                    key(chosen: provider == active, action: { onAgent(provider) }) {
                        BridgeIcon(name: provider.agent, size: DS.Face.shelf, circular: true)
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
        .scrollBounceBehavior(.basedOnSize)
        .animation(DS.Motion.standard, value: active)
    }

    @ViewBuilder
    private func key<Mark: View>(chosen: Bool, action: @escaping () -> Void,
                                 @ViewBuilder mark: () -> Mark) -> some View {
        Button(action: { DSHaptic.selection(); action() }) {
            ZStack {
                Circle().fill(chosen ? AnyShapeStyle(DS.textPrimary)
                                     : AnyShapeStyle(DS.surfaceRaised))
                mark()
            }
            .frame(width: Self.side, height: Self.side)
            .contentShape(Circle())
            .dsHover()
        }
        .buttonStyle(PressSpring())
        // The key that becomes the subject flips once — `coinFlip` is this
        // app's word for "this mark just became what the screen is about"
        // (§578's rule, unchanged).
        .coinFlip(trigger: chosen, enabled: chosen)
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

/// "You asked" plus the question, on one line.
///
/// The question is a CAPTION and never a heading: you wrote it, so the surface
/// spends nothing restating it, and the reply below is left as the only large
/// thing on the paper. This is what §575's turn header stopped being when it
/// grew a 56pt destination disc above the words.
struct AgentAskedCaption: View {
    let question: String

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            DSStamp(word: String(localized: "You asked"))
            Text(question)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You asked: \(question)")
    }
}

/// A written reply, set as the screen (prd §581).
///
/// The first sentence takes the display rung in white; the rest steps down to
/// `heading22` in secondary ink. `AgentReply.split` owns which is which and is
/// harnessed — see its own header for why the rule is a function.
struct AgentProseAnswer: View {
    let text: String
    /// A failure is an answer and wears this same anatomy, with one colour
    /// swapped. Amber, never red: a refused key and an unreachable host are
    /// things to fix, not damage that has been done.
    var attention = false

    var body: some View {
        let parts = AgentReply.split(text)
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !parts.lead.isEmpty {
                Text(parts.lead)
                    .dsText(.price40)
                    .foregroundStyle(attention ? DS.attention : DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !parts.rest.isEmpty {
                Text(parts.rest)
                    .dsText(.heading22)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

/// The rule between one answer and the next on the roll.
///
/// The paper is a ROLL, not a thread (2026-09-03): answers sit on it in order,
/// the newest at the bottom where the foot is, and scrolling up reaches last
/// week's question. There are no bubbles and no alternating sides — one column
/// of full-size answers separated by dated rules, which is how a printed roll
/// reads and is exactly what a chat does not look like.
///
/// The divider carries the DATE, so paging back through a month is legible
/// without a list to open. It is also the only thing that says there is
/// anything above: a count stamp saying so would be chrome for a fact the
/// scroll already tells.
struct AgentTurnDivider: View {
    let landed: Date

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            line
            Text(Self.phrase(landed))
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .lineLimit(1)
            line
        }
        .padding(.vertical, DS.Space.s3)
        .accessibilityHidden(true)
    }

    private var line: some View {
        Rectangle()
            .fill(DS.fillFaint)
            .frame(height: 1)
    }

    /// Relative while it is minutes, a weekday inside the week, a date beyond.
    static func phrase(_ date: Date, now: Date = .now) -> String {
        let gap = now.timeIntervalSince(date)
        if gap < 60 { return String(localized: "just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        if gap < 60 * 60 * 24 * 7 { return formatter.localizedString(for: date, relativeTo: now) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// The wait, as a stopwatch (prd §580's clock, on §581's paper).
///
/// The receipt paper §580 gave this state is gone with the tiles: on a roll
/// the wait is simply the newest thing on the paper, so it takes the paper's
/// own anatomy — the question as a caption, one figure, one sentence — and the
/// Stop verb lives in the foot like every other verb.
///
/// The track is Bankr's OWN published typical (`BankrAgent`'s poll note: most
/// jobs land inside a minute), so you can see whether this one is ordinary. It
/// never claims to be a progress bar for work we cannot see: it fills against
/// the clock and stops at full rather than pretending to know more.
struct AgentWaitPaper: View {
    let question: String
    let elapsed: Int
    /// nil where no typical is published — then no track is drawn at all,
    /// rather than a bar against a number we invented (§83).
    var typical: Int?
    var subject: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s2) {
                DSStamp(word: String(localized: "Working"), weight: .waiting)
                if let subject {
                    Text(subject)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Text(question)
                .dsText(.heading22)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s3)
            HStack(alignment: .lastTextBaseline, spacing: DS.Space.s1) {
                Text("\(elapsed)")
                    .dsText(.price48)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("s")
                    .dsText(.heading22)
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.top, DS.Space.s4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(elapsed) seconds so far")
            if let typical, typical > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.fillFaint)
                        Capsule().fill(DS.textPrimary)
                            .frame(width: geo.size.width *
                                   min(1, Double(elapsed) / Double(typical)))
                    }
                }
                .frame(height: 6)
                .padding(.top, DS.Space.s3)
                .animation(DS.Motion.standard, value: elapsed)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
