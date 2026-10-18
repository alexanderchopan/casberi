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
            // An app the catalogue carries wears its own mark (Lightning's
            // bolt drew as an "LI" disc, prd §1341); a merchant or a rail
            // keeps the asset rule.
            if BridgeIcon.hasMark(name) {
                BridgeIcon(name: name, size: size, circular: true)
            } else {
                AssetMark(name: name, size: size)
            }
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
          // The one day word (prd §1359).
          FeedScreen.dayWord(since)),
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

// MARK: - The money sheet's head (prd §1394)

/// One fact of the receipt: a value and its label, a Details row.
struct MoneyReceiptCell: Identifiable, Equatable {
    let value: String
    let label: String
    var wants = false
    var id: String { label }
}

/// **ONE ANATOMY FOR EVERY MONEY SHEET (prd §1394, user: "they are just
/// lackluster and don't look like what apple would do").** Seven sheets drew
/// five shapes — a card picture on the left, a coin pair centred, a Safe box,
/// a Lightning head, a notice box — with Share standing alone and the status
/// as a lone row under the tiles. The subscription sheet already had Apple's
/// shape (a head, a figure, Details, More), and Apple Wallet's own transaction
/// detail is that shape: merchant, amount, then a list of facts. So every
/// money sheet is now the sentence as its title, this head, the tiles, then
/// Details as rows:
///
/// - the party row: a face, who or what, and when (the day in the divider's
///   ink, the clock beside it) — said once, never again as a row;
/// - the figure: the amount at `price40`, its unit beside it;
/// - one line under it: the other side of the move (what went out, what it was
///   worth, which wallet);
/// - the state, only where there is one to say: the receipt's own stamp in its
///   ink (`Needs you`, `Screening`, `Clear to withdraw`), the settling ladder
///   while a chain is confirming, and nothing at all once it settled — a
///   settled charge says so by saying nothing, as Apple's does.
///
/// Content-sized, in the lead's column: the sheet is a page of facts, not a
/// room with a box, and the air the fixed box held under a three-line receipt
/// was the complaint.
struct MoneySheetHead: View {
    let receipt: MoneyReceipt
    let landed: Date
    /// A transfer between your wallet and someone (prd §1181): the other side
    /// is the face, the figure is signed, the line names your wallet.
    var transfer: Transfer? = nil
    /// A card spend (prd §1182): the card's app is the face, the card its name.
    var card: Card? = nil
    /// A swap's two legs (prd §1351): both marks as the face, what came in as
    /// the figure, what went out under it.
    var swap: Swap? = nil
    struct Card: Equatable {
        let name: String
        let last4: String?
        let source: String
    }
    struct Swap: Equatable {
        let outAmount: String
        let inAmount: String
        let usd: Double?
        /// A leg that is an app, not a token (Peer's Venmo, prd §1356).
        var outApp = false
        var inApp = false
        /// "1 MAG7 = 12,177 MUSEGOD", the wallet that traded and its chain
        /// (prd §1373): Details rows now.
        var rate: String? = nil
        var wallet: String? = nil
        var network: String? = nil
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
    /// The app it came from, the party row's word for a plain receipt.
    let source: String
    var unnamed = false
    /// A bill's day is a Details row ("Due", "Charged"), not the row's.
    var hidesDay = false
    var onSubject: ((String) -> Void)?

    var body: some View {
        // CENTRED, THREE THINGS (prd §1396, user: "still looks janky and
        // messy and convoluted"): the face, the name, the amount, then one
        // grey line — Apple Wallet's transaction head. The sentence title
        // and the party row that stood over it said the figure twice.
        VStack(spacing: 0) {
            head
            VStack(spacing: 0) {
                figure
                    .padding(.top, DS.Space.s2)
                line
                    .padding(.top, DS.Space.s1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(receipt.spokenLabel))
            .accessibilityValue(Text(verbatim: receipt.spokenValue))
            // LIVE STATE WHERE IT CHANGES (prd §1182): a record still
            // confirming on its chain shows where it is, and re-composes in
            // place as the bridge reads it again.
            if receipt.finality == .open, receipt.stamp == .settling {
                steps.padding(.top, DS.Space.s3)
            } else if let note {
                Text(verbatim: note.word)
                    .dsText(.heading17)
                    .foregroundStyle(note.ink)
                    .lineLimit(1)
                    .padding(.top, DS.Space.s2)
            }
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .frame(maxWidth: .infinity)
        .animation(DS.Motion.standard, value: receipt.finality)
    }

    // MARK: The head

    /// The face over the name, a door when there is an address behind it.
    @ViewBuilder private var head: some View {
        let stack = VStack(spacing: DS.Space.s3) {
            face
            Text(verbatim: partyName)
                .dsText(.heading17)
                .foregroundStyle(unnamed && transfer == nil ? DS.pickInk : DS.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let address = door, let onSubject {
            Button { onSubject(address) } label: { stack.contentShape(Rectangle()) }
                .buttonStyle(PressSpring())
                .accessibilityHint(Text("Opens what you know about this address"))
        } else {
            stack
        }
    }

    @ViewBuilder private var face: some View {
        if let t = transfer {
            // A wallet you watch wears the wallet's mark, never a stranger's
            // person (prd §1349).
            if WalletStore.shared.watches(t.theirAddress) {
                BridgeIcon(name: "Wallet", size: DS.Face.sheet, circular: true)
            } else {
                WalletFace(address: t.theirAddress, size: DS.Face.sheet, circular: true)
            }
        } else if let s = swap {
            swapFaces(s)
        } else if let c = card {
            BridgeIcon(name: c.source, size: DS.Face.sheet, circular: true)
        } else {
            MoneySubjectDisc(subject: receipt.subject, mine: receipt.mine, size: DS.Face.sheet, onOpen: nil)
        }
    }

    /// Who or what: the other side, the pair a swap traded, the card, else
    /// the receipt's party (the row's own sentence, §1357.1).
    private var partyName: String {
        if let t = transfer { return t.theirName }
        if let s = swap {
            let out = MoneyReceipt.split(s.outAmount), into = MoneyReceipt.split(s.inAmount)
            let outName = s.outApp ? s.outAmount : (out.unit ?? s.outAmount)
            let inName = s.inApp ? s.inAmount : (into.unit ?? s.inAmount)
            return String(localized: "\(outName) for \(inName)")
        }
        if let c = card { return c.last4.map { "\(c.name) ••\($0)" } ?? c.name }
        if unnamed { return String(localized: "Tap to name") }
        return Self.title(receipt)
    }

    /// The address the head opens, where there is one.
    private var door: String? {
        if let t = transfer { return t.theirAddress }
        if swap == nil, card == nil, case .address(let a) = receipt.subject, !a.isEmpty { return a }
        return nil
    }

    /// The two marks overlapped, the front one punching its own ring out of
    /// the back one, so the two separate on any fill without a line.
    private func swapFaces(_ s: Swap) -> some View {
        let out = MoneyReceipt.split(s.outAmount), into = MoneyReceipt.split(s.inAmount)
        let size = DS.Face.sheet
        return ZStack(alignment: .leading) {
            swapMark(s.outApp ? s.outAmount : (out.unit ?? ""), app: s.outApp, size: size)
                .mask(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Rectangle()
                        Circle().frame(width: size + 6, height: size + 6)
                            .offset(x: size * 0.55 - 3)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
            swapMark(s.inApp ? s.inAmount : (into.unit ?? ""), app: s.inApp, size: size)
                .offset(x: size * 0.55)
        }
        .frame(width: size * 1.55, height: size, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// One leg's mark: a token's, or an app's for a Peer fill (prd §1356).
    @ViewBuilder
    private func swapMark(_ name: String, app: Bool, size: CGFloat) -> some View {
        if app {
            BridgeIcon(name: name, size: size, circular: true)
        } else {
            AssetMark(name: name, size: size)
        }
    }

    // MARK: The line

    /// One grey line under the figure: what it was worth or the other leg,
    /// then when — the day in the divider's ink (§882), the clock beside it.
    @ViewBuilder private var line: some View {
        let lead = lineLead.flatMap { $0.isEmpty ? nil : $0 }
        // A figure's worth joins the clock on one line; a SENTENCE (a Safe's
        // "Waiting on one more signature, yours", a Lightning payment's
        // "worth about $18.90 when it landed") stands on its own line over
        // it, wrapping, never cut beside the clock.
        let sentence = lead.map { $0.count > Self.leadOnLineCap } ?? false
        VStack(spacing: DS.Space.s1) {
            if sentence, let lead {
                Text(verbatim: lead)
                    .dsText(.body17)
                    .monospacedDigit()
                    .foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                if !sentence, let lead {
                    Text(verbatim: lead + (hidesDay ? "" : " ·"))
                        .dsText(.body17)
                        .monospacedDigit()
                        .foregroundStyle(DS.textSecondary)
                }
                if !hidesDay {
                    Text(FeedScreen.dayWord(landed))
                        .dsText(.body17)
                        .foregroundStyle(DS.headInk)
                    Text(verbatim: landed.formatted(date: .omitted, time: .shortened))
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    /// A lead longer than this is a sentence, not a figure (prd §1396).
    static let leadOnLineCap = 22

    /// What the line says before the day: a swap's other leg and its worth,
    /// a transfer's worth, a card's or a receipt's own second line.
    private var lineLead: String? {
        if let s = swap {
            let gave: String
            if s.outApp {
                gave = String(localized: "Paid with \(s.outAmount)")
            } else if s.inApp {
                gave = String(localized: "Paid out to \(s.inAmount)")
            } else {
                gave = "−" + s.outAmount
            }
            var parts = [gave]
            if let usd = s.usd, usd > 0 { parts.append(usd.formatted(.currency(code: "USD"))) }
            return parts.joined(separator: " · ")
        }
        if let t = transfer {
            guard let usd = t.usd, usd > 0 else { return nil }
            return usd.formatted(.currency(code: "USD"))
        }
        return receipt.secondary
    }

    // MARK: The figure

    /// The amount at the price rung, its unit beside it; the two stack when
    /// they do not fit one line, and a long figure steps down a size rather
    /// than truncating.
    private var figure: some View {
        let parts = figureParts
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                figureNumber(parts.number)
                if let unit = parts.unit { figureUnit(unit) }
            }
            VStack(spacing: 0) {
                figureNumber(parts.number)
                if let unit = parts.unit { figureUnit(unit) }
            }
        }
    }

    /// A figure is a number at the price rung; a receipt with no amount to
    /// state (a Safe proposal's "to payroll.eth") leads with words, at the
    /// words' rung.
    private func figureNumber(_ number: String) -> some View {
        Text(verbatim: number)
            .dsText(receipt.amount == nil && swap == nil ? .heading24 : .price40)
            .monospacedDigit()
            .contentTransition(roll)
            .foregroundStyle(figureInk)
            .lineLimit(1).minimumScaleFactor(0.5)
    }

    private func figureUnit(_ unit: String) -> some View {
        Text(verbatim: unit)
            .dsText(.heading17)
            .foregroundStyle(DS.textSecondary)
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    /// A refund or money in reads in the confirm ink; everything else plain.
    private var figureInk: Color {
        card != nil && receipt.amount?.tone == .gain ? DS.confirmInk : DS.textPrimary
    }

    /// The number and its unit for each kind: a transfer signed by its
    /// direction, a swap's leg that came in, a card's unsigned spend (a refund
    /// keeps its plus), a receipt's own statement.
    private var figureParts: (number: String, unit: String?) {
        if let s = swap {
            let out = MoneyReceipt.split(s.outAmount), into = MoneyReceipt.split(s.inAmount)
            let gain = !s.inApp
            let leg = gain ? into : out
            let number = (gain ? "+" : "−") + (leg.number.isEmpty ? (gain ? s.inAmount : s.outAmount) : leg.number)
            return (number, leg.unit.flatMap { $0.isEmpty ? nil : $0 })
        }
        if let t = transfer, let amount = receipt.amount {
            let bare = amount.number.trimmingCharacters(in: CharacterSet(charactersIn: "+-−"))
            return ((t.sent ? "−" : "+") + bare, amount.unit)
        }
        if card != nil, let amount = receipt.amount {
            let bare = amount.number.trimmingCharacters(in: CharacterSet(charactersIn: "+-−"))
            return (amount.number.hasPrefix("+") ? amount.number : bare, amount.unit)
        }
        if let amount = receipt.amount {
            // A typographic minus, never the hyphen the amount was written with.
            let number = amount.number.hasPrefix("-") ? "−" + amount.number.dropFirst() : amount.number
            if number.isEmpty, let unit = amount.unit { return (unit, nil) }
            return (number, amount.unit)
        }
        // Never the lead or the title the row above already says.
        guard let fallback = receipt.titleFallback, fallback != Self.title(receipt) else { return ("", nil) }
        return (fallback, nil)
    }

    /// The amount rolls to a re-read figure rather than cutting (prd §1181).
    private var roll: ContentTransition {
        guard let amount = receipt.amount else { return .numericText() }
        return amount.numeric.map { .numericText(value: $0) } ?? .numericText()
    }

    // MARK: The state

    /// The receipt's own stamp, in its ink — and NEVER a default "Settled"
    /// (prd §83): a settled or filled record says nothing here, an open one
    /// with no stamp says it is waiting.
    private var note: (word: String, ink: Color)? {
        if let stamp = receipt.stamp {
            switch stamp {
            case .settled, .filled: return nil
            default: return (stamp.word, stamp.weight.stampWeight.ink)
            }
        }
        return receipt.finality == .open ? (String(localized: "Waiting"), DS.attentionInk) : nil
    }

    /// Sent → Confirming → Settled, the middle lit while the record is open.
    private var steps: some View {
        let words = [String(localized: "Sent"), receipt.stamp?.word ?? String(localized: "Waiting"),
                     String(localized: "Settled")]
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
    }

    /// The sheet's title: the party, else the receipt's lead.
    static func title(_ receipt: MoneyReceipt) -> String {
        if let party = receipt.party, !party.isEmpty { return party }
        return receipt.lead
    }
}

extension DSStamp.Weight {
    /// The ink a state word takes outside a stamp (prd §1004, §1394).
    var ink: Color {
        switch self {
        case .good:     return DS.confirmInk
        case .waiting:  return DS.attentionInk
        case .urgent:   return DS.attentionInk
        case .quiet:    return DS.textTertiary
        case .shielded: return DS.receiptPour(.shield)
        }
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

