import SwiftUI
import Accessibility

/// The receipt, drawn (prd §369, 2026-08-12) — the hero every money thing gets,
/// replacing `ThingStage`'s three source-gated stages.
///
/// **One object, not a stack.** The first cut of this pass drew nine blocks:
/// eyebrow, subject row, verb, amount, second reading, stamps, a chart card,
/// a four-row spec slab, and the dial. Three of those blocks were labels for
/// other blocks. This is a piece of paper carrying the whole moment, one card
/// where the app says something about it, and the dial.
///
/// **The tear carries state.** `ReceiptPaper`'s bottom edge is scalloped when
/// the record is final and flat when it isn't — a pending authorization whose
/// amount can still change, an unsigned Safe transaction, a deposit in
/// screening. One glance, before a word is read, says whether this is history
/// or something still happening. It is a silhouette, never a line, so the
/// no-hairlines law holds with no exception.
///
/// **And it is spoken, and it happens** (prd §369 amendment, 2026-08-16). Two
/// things were true of that tear until this pass and both undid it: VoiceOver
/// could not reach it at all (the card read out as eight loose fragments, none
/// of which mentioned finality — see `MoneyReceipt.spokenLabel`), and when a
/// record became final while somebody was looking at it, the paper simply
/// swapped. A receipt settling is the one moment this card exists for, so the
/// teeth now CUT IN, on `DS.Motion.tear`, with the success haptic on the same
/// frame.
///
/// Every view here takes VALUES, never a `Thing` — so none of them can hold a
/// tombstoned model across a re-render (the build-188 leaf rule). The one place
/// a `Thing` is read is `MoneyReceiptSource`, on the main actor, behind
/// `isLive`.
struct MoneyReceiptCard: View {
    let receipt: MoneyReceipt
    /// Opening the address behind the subject face (prd §369 amendment).
    ///
    /// A closure over a plain `String`, never a `Thing` — the liveness rule at
    /// the top of this file is a harness guard, not a preference. nil leaves
    /// the disc inert, which is the honesty rule doing its job: a face with
    /// nowhere to go is not a door, and must not look like one.
    var onSubject: ((String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the teeth have cut: 0 flat, 1 fully torn.
    ///
    /// Held rather than derived from `receipt.finality` so the transition can
    /// be animated. `settled` is what keeps it a TRANSITION and not an
    /// entrance: a receipt that opens already final is history, and history
    /// must not perform its own tearing every time the sheet is opened.
    @State private var tear: CGFloat = 0
    @State private var settled = false

    private var torn: Bool { receipt.finality == .torn }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                MoneySubjectDisc(subject: receipt.subject, mine: receipt.mine,
                                 ring: DS.surfaceRaised, onOpen: onSubject)
                Spacer(minLength: DS.Space.s3)
                if let stamp = receipt.stamp {
                    DSStamp(word: stamp.word, weight: stamp.weight.stampWeight)
                        // Spoken in the composed value below, so hearing it
                        // here as well would say the state twice.
                        .accessibilityHidden(true)
                }
            }

            // ONE element for the words (prd §369 amendment). Deliberately not
            // wrapped around the whole card: the subject disc is a door now,
            // and `children: .ignore` on the outer stack would swallow it.
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: receipt.lead)
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    if let party = receipt.party, !party.isEmpty {
                        Text(verbatim: party)
                            .dsText(.heading22).foregroundStyle(DS.textPrimary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .padding(.top, DS.Space.s3)

                amountBlock
                    .padding(.top, DS.Space.s3)

                if let secondary = receipt.secondary {
                    Text(verbatim: secondary)
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                Text(verbatim: receipt.sentence)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(receipt.spokenLabel))
            .accessibilityValue(Text(receipt.spokenValue))
        }
        // THE PAPER IS THE SHARED ONE (2026-08-28). This card is where the
        // silhouette, the pour, the raised ground and the shadow were settled
        // (§363), `DSReceiptPaper` was lifted out of it (§498) so "the two
        // rooms cannot drift into two papers" — and this card then went on
        // spelling the whole stack inline, which is two papers. The only thing
        // that kept it here was the Bool: the tear ANIMATES on a receipt, so
        // the shared modifier had to learn a fraction before its own origin
        // could call it.
        .dsReceiptPaper(hue: DS.receiptPour(receipt.hue), tear: tear)
        .onAppear {
            tear = torn ? 1 : 0
            settled = true
        }
        .onChange(of: receipt.finality) { _, now in
            let target: CGFloat = now == .torn ? 1 : 0
            if settled && !reduceMotion {
                withAnimation(DS.Motion.tear) { tear = target }
            } else {
                tear = target
            }
            // Reduce Motion silences the animation, never the feedback — it is
            // a motion preference, and the haptic is the half of this moment
            // that does not move. Firing `DSHaptic` directly rather than
            // through `ShellChrome.flash` is the documented exception rather
            // than a shortcut: that rule exists so a felt outcome always has
            // words on screen explaining it, and here the paper tearing and
            // the stamp turning over ARE those words. A toast would be a
            // second announcement of something the card just said better.
            if settled && now == .torn { DSHaptic.success() }
        }
    }

    /// The number leads and its unit sits a rung down, so the figure reads
    /// first. A receipt with no stamped figure leads with its title instead —
    /// a common, correct outcome (see `MoneyReceipt.titleFallback`), not a
    /// degraded one.
    @ViewBuilder private var amountBlock: some View {
        if let amount = receipt.amount {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2 - 2) {
                Text(verbatim: amount.number)
                    .dsText(.price40)
                    .monospacedDigit()
                    // A pending authorization that settles at a different
                    // amount COUNTS to it (prd §369 amendment) — the one place
                    // on this card where a change is worth watching, and until
                    // now the one place it blinked. `value:` gives the roll a
                    // direction and is present only when a real Double was
                    // stamped; without it the digits still transition, they
                    // just don't know which way they are going.
                    .contentTransition(amount.numeric.map {
                        .numericText(value: $0)
                    } ?? .numericText())
                    .foregroundStyle(tone(amount.tone))
                    // Clamped to one line: a spoofed token's "name" is
                    // attacker-controlled text, and rendering it huge across two
                    // wrapped lines amplifies exactly the lie the security
                    // warning below the receipt is calling out (2026-07-23).
                    .lineLimit(1).minimumScaleFactor(0.6).truncationMode(.tail)
                if let unit = amount.unit {
                    Text(verbatim: unit)
                        .dsText(.heading22).foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
        } else if let title = receipt.titleFallback {
            Text(verbatim: title)
                .dsText(.heading22).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tone(_ tone: MoneyReceipt.Tone) -> Color {
        switch tone {
        // Green on a gain is colour as STATE. A send stays primary: spending
        // isn't a loss state, and red would editorialize.
        case .gain:  return DS.confirm
        case .warn:  return DS.attention
        case .plain: return DS.textPrimary
        }
    }
}

/// The paper's silhouette. Scalloped along the bottom when the record is final.
///
/// Quadratic curves rather than `addArc`: an arc's sweep direction in a
/// y-down coordinate space is the kind of detail that renders inverted on the
/// first try and looks deliberate, and a quad curve with a control point above
/// the baseline is unambiguous. Teeth are fitted to the width (never clipped
/// mid-tooth) so the last scallop always lands flush with the right edge.
///
/// **`tear` is a fraction, not a Bool** (prd §369 amendment). It is the shape's
/// `animatableData`, which is what lets the teeth cut in over a real duration
/// rather than appearing between two frames. The bottom CORNER RADIUS is
/// interpolated with it for the same reason: the flat state is a fully rounded
/// rect and the torn state has square bottom corners, so animating the teeth
/// alone would snap those corners square on the first frame of the cut.
/// At `tear == 1` this is byte-for-byte the geometry that shipped.
struct ReceiptPaper: Shape {
    /// 0 = flat (still in the machine), 1 = fully torn (final).
    var tear: CGFloat
    static let tooth: CGFloat = 10

    var animatableData: CGFloat {
        get { tear }
        set { tear = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = DS.Radius.card + 4
        let cut = max(0, min(1, tear))
        guard cut > 0 else {
            return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        }
        let tooth = Self.tooth
        let baseY = rect.maxY - tooth * cut
        // Rounded at rest, square once the teeth are fully out.
        let br = r * (1 - cut)
        let left = rect.minX + br
        let right = rect.maxX - br
        let span = max(right - left, 1)
        let count = max(1, Int((span / (tooth * 2)).rounded()))
        let step = span / CGFloat(count)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: baseY - br))
        if br > 0 {
            path.addQuadCurve(to: CGPoint(x: right, y: baseY),
                              control: CGPoint(x: rect.maxX, y: baseY))
        }
        for i in 0..<count {
            let toX = right - step * CGFloat(i + 1)
            let midX = toX + step / 2
            path.addQuadCurve(to: CGPoint(x: toX, y: baseY),
                              control: CGPoint(x: midX, y: baseY - tooth * 1.5 * cut))
        }
        if br > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: baseY - br),
                              control: CGPoint(x: rect.minX, y: baseY))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.closeSubpath()
        return path
    }
}

/// Slot 0 — four species of disc, four grades of knowing.
///
/// The ordering is the point: an identicon is derived from a real address, a
/// bundled mark is real artwork, a monogram admits we have neither, and a void
/// says the absence is the protocol's own doing. A void must never be mistaken
/// for a face that failed to load, which is why it is a recessed well and not a
/// grey circle with a glyph in it.
///
/// **The face is a door when it has somewhere to go** (prd §369 amendment).
/// In Apple Wallet you tap the merchant and get your history with them; this
/// sheet HAS that history — `MoneyCommentaryCard` draws it a few points below —
/// and the disc above it was inert, with naming buried at the bottom of the
/// dial. Only `.address` opens, because only an address resolves to a real
/// destination (`AddressCard`); a bundled asset mark and a monogram have
/// nowhere to lead, and a door that opens onto nothing is the fake status §83
/// bans. The `mine` pip is deliberately NOT a second door: at 26pt it is well
/// under the 44pt target, and the watched wallet it names is one tap away in
/// the Wallet manager anyway.
struct MoneySubjectDisc: View {
    let subject: MoneyReceipt.Subject
    var mine: String?
    var ring: Color = DS.surfaceRaised
    var size: CGFloat = DS.Face.shelf
    var onOpen: ((String) -> Void)?

    var body: some View {
        if let onOpen, let address = openable {
            Button { onOpen(address) } label: { disc }
                .buttonStyle(PressSpring())
                .dsHover()
                .accessibilityLabel(Text("Address"))
                .accessibilityHint(Text("Opens what you know about this address"))
                // The disc carries no word saying it is a door, and on a
                // pointer surface a cursor is the only thing that can ask.
                .dsTooltip(String(localized: "Opens what you know about this address"))
        } else {
            disc.accessibilityHidden(true)
        }
    }

    /// The address behind the face, when there is one.
    private var openable: String? {
        if case .address(let address) = subject, !address.isEmpty { return address }
        return nil
    }

    private var disc: some View {
        face
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) { minePip }
    }

    @ViewBuilder private var face: some View {
        switch subject {
        case .address(let address):
            WalletFace(address: address, size: size, circular: true)
        case .asset(let symbol):
            AssetMark(name: symbol, size: size)
        case .named(let name):
            AssetMark(name: name, size: size)
        case .absent:
            // A hole in the paper, not a placeholder. The inner shadow is what
            // makes it read as recessed — the `surfaceWell` rung's own job.
            Circle()
                .fill(DS.surfaceWell)
                .overlay {
                    Circle().stroke(DS.scrim, lineWidth: 6).blur(radius: 5)
                        .mask(Circle())
                }
        }
    }

    /// The watched wallet this touched, tucked into the corner — so "from her,
    /// into Main" is one object rather than two facts. Ringed in the card's own
    /// colour so it reads as sitting on the paper.
    @ViewBuilder private var minePip: some View {
        if let mine, !mine.isEmpty {
            WalletFace(address: mine, size: size * 0.46, circular: true)
                .overlay(Circle().strokeBorder(ring, lineWidth: 3))
                .offset(x: 3, y: 3)
        }
    }
}

/// How a receipt's own stamp weight reads as a `DSStamp` weight.
///
/// The mapping lives here, in the screen, rather than in `Design/`: the model
/// knows about refunds and proofs, the component knows about ink, and the one
/// place allowed to know both is the view that draws one from the other.
/// `private_` and `shielded` are the same case wearing each layer's own word.
extension MoneyReceipt.Stamp.Weight {
    var stampWeight: DSStamp.Weight {
        switch self {
        case .good:     return .good
        case .waiting:  return .waiting
        case .urgent:   return .urgent
        case .quiet:    return .quiet
        case .private_: return .shielded
        }
    }
}

/// What the app says about the receipt — a sentence that has already read the
/// chart, with the chart under it as evidence.
///
/// The inversion is deliberate and is the whole reason this view isn't a
/// labelled chart card: "Your history with maria.eth" over a bar strip makes
/// the reader do the reading.
struct MoneyCommentaryCard: View {
    let commentary: MoneyCommentary

    /// How far the note is inset from the paper's leading edge (prd §417).
    /// Enough that the step is unmistakable at a glance; short enough that a
    /// two-line sentence doesn't start wrapping to buy it.
    private static let indent: CGFloat = DS.Space.s6

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: commentary.headline)
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let sub = subline {
                Text(verbatim: sub)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            evidence
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A NOTE ON THE RECORD, NOT A SECOND RECORD (2026-08-20, prd §417).
        // This drew as `DS.fillFaint` at the paper's own width and the paper's
        // own corner radius, so the sheet showed two slabs of equal authority —
        // and they are not equal: the receipt is EVIDENCE, stamped from what a
        // bridge landed, while this is the app's own reading of it. Same words,
        // same evidence strip; what changed is who is visibly speaking.
        //
        // Three things carry that, and each is a grammar the app already owns.
        // The INDENT is the margin — a note sits beside the thing it annotates,
        // never squarely on top of it. The TINT is Casberi's own voice, the
        // same `DS.tint` wash `AddressCard` pours for machinery because "a
        // contract has no identity of its own to borrow"; the app talking about
        // somebody else's transaction is exactly that case. And the top-leading
        // corner is SQUARED — a speech corner, pointing back up at the paper it
        // is about. No hairline, no arrow, no glyph: the §8 no-lines law holds
        // with no exception, and the shape does the pointing.
        .background(DS.tint.opacity(0.08),
                    in: .rect(topLeadingRadius: 0,
                              bottomLeadingRadius: DS.Radius.card,
                              bottomTrailingRadius: DS.Radius.card,
                              topTrailingRadius: DS.Radius.card,
                              style: .continuous))
        // The indent is OUTSIDE the background, so the note's own corners stay
        // put and only the whole note steps in from the paper's edge.
        .padding(.leading, Self.indent)
    }

    private var subline: String? {
        switch commentary {
        case .history(_, let s, _), .merchant(_, let s, _),
             .ladder(_, let s, _, _), .rate(_, let s), .note(_, let s):
            return s
        }
    }

    @ViewBuilder private var evidence: some View {
        switch commentary {
        case .history(let head, _, let series):
            ReceiptFlowStrip(series: series, title: head)
                .padding(.top, DS.Space.s3)
        case .merchant(let head, _, let values):
            ReceiptBars(values: values, title: head)
                .padding(.top, DS.Space.s3)
        case .ladder(_, _, let rung, let since):
            ReceiptLadder(rung: rung, since: since).padding(.top, DS.Space.s3)
        case .rate, .note:
            EmptyView()
        }
    }
}

/// A signed series with one counterparty — received above the line, sent below,
/// oldest first, this row last and ringed.
///
/// Only ever handed a SINGLE-token series (`MoneyCommentary.history` refuses to
/// build one otherwise): bar height means quantity, and ETH bars beside USDC
/// bars on one axis mean nothing.
///
/// **Playable** (prd §369 amendment): the strip carries an `AXChartDescriptor`,
/// so somebody using VoiceOver gets the series as an Audio Graph rather than a
/// silhouette they are told nothing about. The descriptor is built from the
/// same `series` the bars are drawn from, so the two cannot describe different
/// histories.
struct ReceiptFlowStrip: View {
    let series: [Double]
    /// The commentary's own headline, reused as the chart's title so the graph
    /// announces itself with the sentence the card already made.
    var title: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    private var peak: Double { max(series.map(abs).max() ?? 1, .leastNonzeroMagnitude) }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(series.enumerated()), id: \.offset) { index, value in
                let height = CGFloat(abs(value) / peak) * 24 + 3
                VStack(spacing: 0) {
                    if value >= 0 {
                        bar(height: height, fill: DS.confirm, last: index == series.count - 1)
                        Color.clear.frame(height: 26)
                    } else {
                        Color.clear.frame(height: 26)
                        // The ring marks THIS row, and this row is as often a
                        // send as a receipt — it used to be hardcoded off for
                        // every negative bar, so on the commonest history in
                        // the app the emphasis never drew (2026-08-16). It
                        // wears the bar's own colour rather than `confirm`,
                        // which on a grey outgoing bar would have read as a
                        // gain.
                        bar(height: height, fill: DS.fillStrong,
                            last: index == series.count - 1)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54, alignment: value >= 0 ? .bottom : .top)
            }
        }
        .frame(height: 54)
        .accessibilityElement()
        .accessibilityLabel(Text(title.isEmpty
                                 ? String(localized: "Your history together")
                                 : title))
        .accessibilityChartDescriptor(self)
        // Sized from data, so it has an entrance (prd §299) — and Reduce Motion
        // lands it drawn rather than animating faster.
        .onAppear {
            guard !reduceMotion else { drawn = true; return }
            withAnimation(DS.Motion.standard.delay(0.08)) { drawn = true }
        }
    }

    private func bar(height: CGFloat, fill: Color, last: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .frame(height: drawn ? height : 2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .overlay {
                if last {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(fill.opacity(0.35), lineWidth: 3)
                        .frame(height: drawn ? height : 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
    }
}

extension ReceiptFlowStrip: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let values = series
        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Order"),
            range: 0...Double(max(values.count - 1, 1)),
            gridlinePositions: []) { position in
                String(localized: "number \(Int(position) + 1)")
            }
        let low = min(values.min() ?? 0, 0)
        let high = max(values.max() ?? 0, 0)
        let y = AXNumericDataAxisDescriptor(
            title: String(localized: "Amount"),
            // Never a zero-width range: a history of one flat value would give
            // the audio graph nothing to sweep and it reads as broken.
            range: low...max(high, low + .leastNonzeroMagnitude),
            gridlinePositions: []) { value in
                value < 0 ? String(localized: "\(abs(value).formatted()) out")
                          : String(localized: "\(value.formatted()) in")
            }
        let points = values.enumerated().map { index, value in
            AXDataPoint(x: Double(index), y: value)
        }
        return AXChartDescriptor(
            title: title.isEmpty ? String(localized: "Your history together") : title,
            summary: nil,
            xAxis: x,
            yAxis: y,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: "", isContinuous: false,
                                            dataPoints: points)])
    }
}

/// Prior spends at one merchant, oldest first, this one last and lit.
struct ReceiptBars: View {
    let values: [Double]
    var title: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    private var shown: [Double] { Array(values.suffix(14)) }
    private var peak: Double { max(values.max() ?? 1, .leastNonzeroMagnitude) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index == shown.count - 1 ? DS.textPrimary : DS.fillStrong)
                    .frame(height: drawn ? CGFloat(value / peak) * 44 + 4 : 3)
            }
        }
        .frame(height: 48, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel(Text(title.isEmpty
                                 ? String(localized: "What you've spent here")
                                 : title))
        .accessibilityChartDescriptor(self)
        .onAppear {
            guard !reduceMotion else { drawn = true; return }
            withAnimation(DS.Motion.standard.delay(0.08)) { drawn = true }
        }
    }
}

extension ReceiptBars: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        // The DRAWN window, not the whole history — a graph that plays
        // fourteen bars while announcing forty is describing a different
        // chart from the one on screen.
        let values = shown
        let x = AXNumericDataAxisDescriptor(
            title: String(localized: "Order"),
            range: 0...Double(max(values.count - 1, 1)),
            gridlinePositions: []) { position in
                String(localized: "number \(Int(position) + 1)")
            }
        let high = max(values.max() ?? 0, .leastNonzeroMagnitude)
        let y = AXNumericDataAxisDescriptor(
            title: String(localized: "Amount"),
            range: 0...high,
            gridlinePositions: []) { $0.formatted() }
        let points = values.enumerated().map { index, value in
            AXDataPoint(x: Double(index), y: value)
        }
        return AXChartDescriptor(
            title: title.isEmpty ? String(localized: "What you've spent here") : title,
            summary: nil,
            xAxis: x,
            yAxis: y,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: "", isContinuous: false,
                                            dataPoints: points)])
    }
}

/// Privacy Pools' screening ladder — the reason that seat exists, and a status
/// the sheet showed nowhere before this pass.
struct ReceiptLadder: View {
    let rung: MoneyCommentary.Rung
    let since: Date

    private var steps: [(MoneyCommentary.Rung, String, String?)] {
        [(.deposited, String(localized: "You deposited"),
          since.formatted(.dateTime.weekday(.wide).hour().minute())),
         (rung == .needsProof ? .needsProof : .screening,
          rung == .needsProof ? String(localized: "Proof asked for")
                              : String(localized: "Being screened"),
          rung == .cleared ? nil : String(localized: "since then")),
         (.cleared, String(localized: "Clear to withdraw"),
          rung == .cleared ? String(localized: "now") : String(localized: "not yet"))]
    }

    private func state(_ step: MoneyCommentary.Rung) -> Int {
        // 2 = done, 1 = where it stands, 0 = ahead of it.
        switch (step, rung) {
        case (.deposited, _):                    return 2
        case (.screening, .cleared),
             (.needsProof, .cleared):            return 2
        case (.screening, _), (.needsProof, _):  return 1
        case (.cleared, .cleared):               return 2
        default:                                 return 0
        }
    }

    /// The ladder said out loud. Its whole meaning is WHICH rung is lit, and a
    /// dot's colour is exactly the sort of thing that reaches nobody listening
    /// — so each step names its own standing rather than being read as three
    /// unrelated labels.
    private var spoken: String {
        steps.map { step in
            let mark = state(step.0)
            let standing = mark == 2 ? String(localized: "done")
                : mark == 1 ? String(localized: "where it stands now")
                : String(localized: "not yet")
            return "\(step.1), \(standing)"
        }.joined(separator: ". ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let mark = state(step.0)
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(mark == 2 ? DS.confirm
                                  : mark == 1 ? DS.attention : DS.fillStrong)
                            .frame(width: 14, height: 14)
                            .padding(.top, 5)
                        if index < steps.count - 1 {
                            Capsule()
                                .fill(mark == 2 ? DS.confirm.opacity(0.45) : DS.fillLine)
                                .frame(width: 3)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: step.1)
                            .dsText(.callout15)
                            .foregroundStyle(mark == 0 ? DS.textTertiary : DS.textPrimary)
                        if let detail = step.2 {
                            Text(verbatim: detail)
                                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        }
                    }
                    .padding(.bottom, index < steps.count - 1 ? DS.Space.s3 : 0)
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }
}
