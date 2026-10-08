import SwiftUI
import Accessibility


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
    /// What the ring punches out — the surface BEHIND the disc, so the
    /// faces separate without a line. `DS.inkGround` since §542, when every
    /// paper became ink; a caller drawing this on some other surface passes
    /// that surface, and passing a colour the ground is not draws a halo.
    var ring: Color = DS.inkGround
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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: commentary.headline)
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let sub = subline {
                Text(verbatim: sub)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            evidence
        }
        // FLAT (prd §887): no tinted plate and no indent — it stands in the
        // receipt's own column under the dial, the words above the evidence.
        .padding(.horizontal, DS.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .dsText(.body17)
                            .foregroundStyle(mark == 0 ? DS.textTertiary : DS.textPrimary)
                        if let detail = step.2 {
                            Text(verbatim: detail)
                                .dsText(.subhead12).foregroundStyle(DS.textTertiary)
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

// MARK: - The receipt in the room's frame (prd §1181)

/// One cell of the receipt's grid: a value over its label, as Settings'
/// counts stand.
struct MoneyReceiptCell: Identifiable, Equatable {
    let value: String
    let label: String
    var wants = false
    var id: String { label }
}

/// The receipt's box (prd §1181, user: "shouldn't this be IN the card?", then
/// "on the rooms they have a title … but they don't have a logo"): the party's
/// NAME is the sheet's title above the box, as a room's is, and its FACE leads
/// inside the box with what happened and when — Today's card anatomy, each
/// fact said once. Then the statement (the amount, number and token
/// together), one quiet line (what it was worth), then one row of facts, a
/// value over its label as Settings' counts stand. The sentence that restated
/// the party is gone, and the stamp is the Status cell. The face and the name
/// open the address card, where a name is given; an unnamed address says so.
struct MoneyReceiptBox: View {
    let receipt: MoneyReceipt
    let landed: Date
    /// A transfer between your wallet and someone (prd §1181): the box draws
    /// the two faces with the arrow between them — the thing itself — the
    /// amount, its worth and day, and the status and network as stamps.
    var transfer: Transfer? = nil
    /// A card spend (prd §1182): the card that paid, drawn beside the amount
    /// — Apple Wallet's own picture of a transaction.
    var card: Card? = nil
    struct Card: Equatable {
        let name: String
        let last4: String?
        let source: String
        /// Apple Card is titanium; every other card draws on the raised fill.
        var light: Bool { name.localizedCaseInsensitiveContains("Apple Card") }
    }
    struct Transfer: Equatable {
        let mineAddress: String
        let mineLabel: String
        let theirAddress: String
        let theirName: String
        let sent: Bool
        let usd: Double?
        let network: String?
    }
    /// The app it came from, the eyebrow's word, as Today's card names its
    /// app (user, of "Spent at · Card": "we can make all this text look better").
    let source: String
    let cells: [MoneyReceiptCell]
    var unnamed = false
    var onSubject: ((String) -> Void)?

    var body: some View {
        if let transfer { transferBody(transfer) }
        else if let card { cardBody(card) }
        else { receiptBody }
    }

    /// Apple Wallet's transaction detail, centred: who to whom, how much,
    /// worth and when, then the state (prd §1181, the design canvas
    /// "Thing sheets, the Apple pass").
    private func transferBody(_ t: Transfer) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s2) {
                party(address: t.sent ? t.mineAddress : t.theirAddress,
                      name: t.sent ? t.mineLabel : t.theirName)
                HStack(spacing: 0) {
                    Capsule().fill(DS.textTertiary).frame(width: 40, height: 2)
                    Image(systemName: "chevron.right")
                        .dsGlyph(.caption, weight: .bold)
                        .foregroundStyle(DS.textTertiary)
                }
                .padding(.bottom, DS.Space.s4)
                .accessibilityHidden(true)
                party(address: t.sent ? t.theirAddress : t.mineAddress,
                      name: t.sent ? t.theirName : t.mineLabel)
            }
            Text(verbatim: unsignedStatement)
                .dsText(.heading34)
                .monospacedDigit()
                .contentTransition(roll)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.top, DS.Space.s3)
            Text(verbatim: worthLine(t))
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.top, 2)
            Spacer(minLength: DS.Space.s2)
            if receipt.finality == .open {
                // LIVE STATE WHERE IT CHANGES (prd §1182): a record still in
                // the machine shows where it is — sent, confirming, settled —
                // and re-composes in place as the bridge reads it again.
                steps
            } else {
                HStack(spacing: DS.Space.s2) {
                    DSStamp(word: statusWord, weight: statusWeight)
                    if let network = t.network, !network.isEmpty {
                        DSStamp(word: network, weight: .quiet)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken(t)))
    }

    /// The card that paid beside what it paid (prd §1182): the card, then its
    /// name, the amount, the day and time, the state.
    private func cardBody(_ c: Card) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            cardArt(c)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: c.name)
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Text(verbatim: cardStatement)
                    .dsText(.heading34)
                    .monospacedDigit()
                    .foregroundStyle(receipt.amount?.tone == .gain ? DS.confirmInk : DS.textPrimary)
                    .contentTransition(roll)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, DS.Space.s3)
                Text(verbatim: landed.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .padding(.top, 2)
                Spacer(minLength: DS.Space.s2)
                DSStamp(word: statusWord, weight: statusWeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(receipt.spokenLabel))
        .accessibilityValue(Text(verbatim: [receipt.spokenValue, c.name].joined(separator: ", ")))
    }

    /// A card, portrait as Wallet stacks it: the issuer's mark, the last four.
    private func cardArt(_ c: Card) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
            .fill(c.light ? Color(white: 0.91) : DS.surfaceRaised)
            .frame(width: 112, height: 176)
            .overlay(alignment: .topLeading) {
                BridgeIcon(name: c.source, size: DS.Mark.row)
                    .padding(DS.Space.s3)
            }
            .overlay(alignment: .bottomLeading) {
                if let last4 = c.last4 {
                    Text(verbatim: "••\(last4)")
                        .dsText(.label12)
                        .monospacedDigit()
                        .foregroundStyle(c.light ? Color(white: 0.45) : DS.textSecondary)
                        .padding(DS.Space.s3)
                }
            }
            .accessibilityHidden(true)
    }

    /// A spend reads unsigned; a refund keeps its plus.
    private var cardStatement: String {
        guard let amount = receipt.amount else { return statement }
        let number = amount.number.hasPrefix("+") ? amount.number : unsignedStatement
        return number
    }

    /// Sent → Confirming → Settled, the middle lit while the record is open.
    private var steps: some View {
        let words = [String(localized: "Sent"), statusWord, String(localized: "Settled")]
        return VStack(spacing: DS.Space.s1) {
            HStack(spacing: 0) {
                Circle().fill(DS.textPrimary).frame(width: 10, height: 10)
                Capsule().fill(DS.textPrimary).frame(height: 2)
                Circle().fill(DS.attention).frame(width: 12, height: 12)
                Capsule().fill(DS.fillFaint).frame(height: 2)
                Circle().fill(DS.fillFaint).frame(width: 10, height: 10)
            }
            HStack {
                Text(verbatim: words[0]).foregroundStyle(DS.textSecondary)
                Spacer()
                Text(verbatim: words[1]).foregroundStyle(DS.attentionInk)
                Spacer()
                Text(verbatim: words[2]).foregroundStyle(DS.textTertiary)
            }
            .dsText(.label12)
        }
        .padding(.horizontal, DS.Space.s2)
        .animation(DS.Motion.standard, value: receipt.finality)
    }

    /// One face and its name, a door to the address card.
    private func party(address: String, name: String) -> some View {
        Button { onSubject?(address) } label: {
            VStack(spacing: DS.Space.s1) {
                WalletFace(address: address, size: DS.Face.shelf, circular: true)
                Text(verbatim: name)
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(width: 72)
        }
        .buttonStyle(PressSpring())
        .disabled(onSubject == nil)
    }

    /// The amount rolls to a re-read figure rather than cutting (prd §1181,
    /// item 7 of the design pass: "the amount rolls in digit by digit").
    private var roll: ContentTransition {
        guard let amount = receipt.amount else { return .numericText() }
        return amount.numeric.map { .numericText(value: $0) } ?? .numericText()
    }

    /// The amount without its sign: the arrow says which way it went.
    private var unsignedStatement: String {
        guard let amount = receipt.amount else { return statement }
        let number = amount.number.trimmingCharacters(in: CharacterSet(charactersIn: "+-−"))
        return [number, amount.unit].compactMap { $0 }.joined(separator: " ")
    }

    private func worthLine(_ t: Transfer) -> String {
        let day = landed.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        guard let usd = t.usd, usd > 0 else { return day }
        return "\(usd.formatted(.currency(code: "USD"))) · \(day)"
    }

    private var statusWord: String {
        receipt.stamp?.word ?? (receipt.finality == .open ? String(localized: "Waiting") : String(localized: "Settled"))
    }

    private var statusWeight: DSStamp.Weight {
        receipt.stamp?.weight.stampWeight ?? (receipt.finality == .open ? .waiting : .good)
    }

    private func spoken(_ t: Transfer) -> String {
        let who = t.sent ? String(localized: "You sent \(t.theirName) \(unsignedStatement)")
                         : String(localized: "\(t.theirName) sent you \(unsignedStatement)")
        return [who, t.network, statusWord, landed.formatted(.dateTime.weekday(.wide))]
            .compactMap { $0 }.joined(separator: ". ")
    }

    private var receiptBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: statement)
                    .dsText(.heading34)
                    .monospacedDigit()
                    .contentTransition(roll)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let secondary = receipt.secondary {
                    Text(verbatim: secondary)
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                HStack(alignment: .top, spacing: DS.Space.s2) {
                    ForEach(cells.prefix(3)) { cell in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: cell.value)
                                .dsText(.heading20)
                                .monospacedDigit()
                                .foregroundStyle(cell.wants ? DS.attentionInk : DS.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(verbatim: cell.label)
                                .dsText(.label12)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, DS.Space.s4)
            }
            .padding(.top, DS.Space.s4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(receipt.spokenLabel))
            .accessibilityValue(Text(verbatim: [receipt.spokenValue, cellsSpoken]
                .filter { !$0.isEmpty }.joined(separator: ", ")))
        }
    }

    /// Who and when, Today's eyebrow at its rungs: the face, the name, what
    /// happened, the day in the time's place. A door when there is an address.
    @ViewBuilder private var eyebrow: some View {
        let row = HStack(spacing: DS.Space.s2) {
            MoneySubjectDisc(subject: receipt.subject, mine: receipt.mine, size: DS.Face.list, onOpen: nil)
            Text(verbatim: unnamed ? String(localized: "Tap to name") : source)
                .dsText(.label12)
                .foregroundStyle(unnamed ? DS.tint : DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Text(FeedScreen.dayWord(landed))
                .dsText(.label12)
                .foregroundStyle(DS.brandInk)
                .lineLimit(1)
        }
        if let address = openable, let onSubject {
            Button { onSubject(address) } label: { row.contentShape(Rectangle()) }
                .buttonStyle(RowPress())
                .accessibilityHint(Text("Opens what you know about this address"))
        } else {
            row
        }
    }

    private var openable: String? {
        if case .address(let address) = receipt.subject, !address.isEmpty { return address }
        return nil
    }

    /// The facts, spoken after the receipt's finality.
    private var cellsSpoken: String {
        cells.map { "\($0.label) \($0.value)" }.joined(separator: ", ")
    }

    /// The sheet's title: the party, else the receipt's lead.
    static func title(_ receipt: MoneyReceipt) -> String {
        if let party = receipt.party, !party.isEmpty { return party }
        return receipt.lead
    }

    private var statement: String {
        if let amount = receipt.amount {
            // A typographic minus, never the hyphen the amount was written with.
            let number = amount.number.hasPrefix("-") ? "−" + amount.number.dropFirst() : amount.number
            return [number, amount.unit].compactMap { $0 }.joined(separator: " ")
        }
        return receipt.titleFallback ?? receipt.lead
    }
}

extension NumberFormatter {
    /// "2nd", "3rd" in the reader's language.
    static func localizedOrdinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

