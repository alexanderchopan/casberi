import SwiftUI

/// The receipt, drawn (prd §363, 2026-08-12) — the hero every money thing gets,
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
/// Every view here takes VALUES, never a `Thing` — so none of them can hold a
/// tombstoned model across a re-render (the build-188 leaf rule). The one place
/// a `Thing` is read is `MoneyReceiptSource`, on the main actor, behind
/// `isLive`.
struct MoneyReceiptCard: View {
    let receipt: MoneyReceipt
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                MoneySubjectDisc(subject: receipt.subject, mine: receipt.mine,
                                 ring: DS.surfaceRaised)
                Spacer(minLength: DS.Space.s3)
                if let stamp = receipt.stamp { ReceiptStampPill(stamp: stamp) }
            }
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
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s6)
        // Room under the last line for the teeth to bite into.
        .padding(.bottom, receipt.finality == .torn
                 ? DS.Space.s6 + ReceiptPaper.tooth + 2 : DS.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            // The pour, clipped to the paper's own silhouette so the hue can
            // never bleed past a tooth.
            LinearGradient(
                colors: [DS.receiptPour(receipt.hue)
                            .opacity(DS.receiptPourOpacity(scheme)),
                         DS.receiptPour(receipt.hue).opacity(0)],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(DS.surfaceRaised)
        .clipShape(ReceiptPaper(torn: receipt.finality == .torn))
        .shadow(color: DS.raisedShadow, radius: 10, y: 2)
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
struct ReceiptPaper: Shape {
    var torn: Bool
    static let tooth: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let r = DS.Radius.card + 4
        guard torn else {
            return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        }
        let tooth = Self.tooth
        let baseY = rect.maxY - tooth
        let count = max(1, Int((rect.width / (tooth * 2)).rounded()))
        let step = rect.width / CGFloat(count)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: baseY))
        for i in 0..<count {
            let toX = rect.maxX - step * CGFloat(i + 1)
            let midX = toX + step / 2
            path.addQuadCurve(to: CGPoint(x: toX, y: baseY),
                              control: CGPoint(x: midX, y: baseY - tooth * 1.5))
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
struct MoneySubjectDisc: View {
    let subject: MoneyReceipt.Subject
    var mine: String?
    var ring: Color = DS.surfaceRaised
    var size: CGFloat = DS.Face.shelf

    var body: some View {
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

/// The pill on the paper. State in form as well as words.
struct ReceiptStampPill: View {
    let stamp: MoneyReceipt.Stamp

    var body: some View {
        Text(verbatim: stamp.word)
            .dsText(.label12)
            .foregroundStyle(ink)
            .padding(.horizontal, DS.Space.s2)
            .frame(height: 24)
            .background(wash, in: Capsule(style: .continuous))
    }

    private var ink: Color {
        switch stamp.weight {
        case .good:     return DS.confirm
        case .waiting:  return DS.attention
        case .urgent:   return DS.attention
        case .quiet:    return DS.textTertiary
        case .private_: return DS.receiptPour(.shield)
        }
    }

    private var wash: Color {
        switch stamp.weight {
        case .quiet: return DS.fillFaint
        default:     return ink.opacity(0.16)
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
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card + 4,
                                         style: .continuous))
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
        case .history(_, _, let series):
            ReceiptFlowStrip(series: series).padding(.top, DS.Space.s3)
        case .merchant(_, _, let values):
            ReceiptBars(values: values).padding(.top, DS.Space.s3)
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
struct ReceiptFlowStrip: View {
    let series: [Double]
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
                        bar(height: height, fill: DS.fillStrong, last: false)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54, alignment: value >= 0 ? .bottom : .top)
            }
        }
        .frame(height: 54)
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
                        .strokeBorder(DS.confirm.opacity(0.35), lineWidth: 3)
                        .frame(height: drawn ? height : 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
    }
}

/// Prior spends at one merchant, oldest first, this one last and lit.
struct ReceiptBars: View {
    let values: [Double]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    private var peak: Double { max(values.max() ?? 1, .leastNonzeroMagnitude) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.suffix(14).enumerated()), id: \.offset) { index, value in
                let shown = Array(values.suffix(14))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index == shown.count - 1 ? DS.textPrimary : DS.fillStrong)
                    .frame(height: drawn ? CGFloat(value / peak) * 44 + 4 : 3)
            }
        }
        .frame(height: 48, alignment: .bottom)
        .onAppear {
            guard !reduceMotion else { drawn = true; return }
            withAnimation(DS.Motion.standard.delay(0.08)) { drawn = true }
        }
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
    }
}
