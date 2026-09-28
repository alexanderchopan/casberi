import SwiftUI

/// THE FRAMES SCOPE'S DRAWING — one component, three rooms (prd §698, drawn
/// as columns since §952): the transactions over one column each, a block per
/// frame. The column area is read off its `GeometryReader`, so the figure
/// fills the slot it is given and clips nothing (§665).
struct RoomFramesFigure: View {
    let runs: [RoomFrames.Run]
    @State private var lit: String?

    /// The newest this many transactions; older ones are counted, not drawn.
    static let shown = 12

    /// Oldest on the left, newest on the right — the callers hand moves
    /// newest first, the way their lists read.
    private var drawn: [RoomFrames.Run] {
        Array(RoomFrames.runs(runs).prefix(Self.shown).reversed())
    }

    var body: some View {
        let all = RoomFrames.runs(runs)
        if !all.isEmpty {
            // **ONE COLUMN PER TRANSACTION, A BLOCK PER FRAME (prd §952).**
            // One number over one noun — the transactions — and under it what
            // each one was made of, oldest to newest, in the one accent. A
            // transaction with a step that failed or rolled back is grey. §936's
            // bars are deleted here: one bar per kind of step said "Step 12" on
            // Privacy (its frames carry no mode), and "Failed" was an outcome
            // drawn as a kind. The rows below name the steps.
            VStack(alignment: .leading, spacing: 0) {
                reading(all)
                Spacer(minLength: DS.Space.s3)
                GeometryReader { geo in
                    columns(height: geo.size.height)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(RoomFrames.mix(all).map(RoomFrames.caption) ?? ""))
        }
    }

    private static func troubled(_ run: RoomFrames.Run) -> Bool {
        run.steps.contains { $0.outcome == .failed || $0.outcome == .rolledBack }
    }

    private func columns(height: CGFloat) -> some View {
        let tallest = CGFloat(drawn.map(\.steps.count).max() ?? 1)
        let gap: CGFloat = 3
        let block = max(4, min(16, (height - gap * (tallest - 1)) / tallest))
        return HStack(alignment: .bottom, spacing: DS.Space.s2) {
            ForEach(drawn) { run in
                let dim = lit != nil && lit != run.id
                Button {
                    DSHaptic.selection()
                    lit = lit == run.id ? nil : run.id
                } label: {
                    VStack(spacing: gap) {
                        ForEach(run.steps.reversed()) { _ in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Self.troubled(run) ? DS.textTertiary.opacity(0.45) : DS.tint)
                                .frame(height: block)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressSpring())
                .opacity(dim ? 0.35 : 1)
                .frame(maxWidth: 44)
                .accessibilityLabel(Text(run.steps.count == 1 ? String(localized: "1 frame")
                                         : String(localized: "\(String(run.steps.count)) frames")))
            }
            // Fewer than the cap stand where the cap would: a lone transaction
            // is not stretched across the width.
            ForEach(0..<max(0, 6 - drawn.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: 44, maxHeight: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    @ViewBuilder
    private func reading(_ all: [RoomFrames.Run]) -> some View {
        if let lit, let run = all.first(where: { $0.id == lit }) {
            // A pressed column reads its own transaction: its frames, and the
            // trouble word when there is one.
            let n = run.steps.count
            DSFigureReading(number: String(n),
                            caption: n == 1 ? String(localized: "frame") : String(localized: "frames"),
                            alarm: Self.troubled(run) ? String(localized: "didn't finish") : nil)
        } else {
            DSFigureReading(number: String(all.count),
                            caption: all.count == 1 ? String(localized: "transaction")
                                                    : String(localized: "transactions"))
        }
    }
}

/// THE FAMILY'S ONE COLOUR PER STEP (prd §698).
///
/// Hegotá UTXO's table, lifted out of `HegotaModeStyle` so three rooms draw one
/// encoding. Keyed by the mode's NAME rather than its number, because the name
/// is what the legend prints and a legend whose swatch disagrees with its strip
/// is worse than no legend.
///
/// `HegotaModeStyle.hue` stays and now reads this, or the pour, the vault
/// segment and the strips drift into three nearly-identical cyans — the drift
/// nobody sees in a screenshot of one of them.
enum RoomFrameStyle {
    /// The vault's cyan — `HegotaModeStyle.room` is this.
    static let vault = DS.stepVault

    static func hue(_ modeName: String) -> Color {
        switch modeName {
        case String(localized: "Verify"): return DS.stepVerify
        case String(localized: "Send"):   return DS.confirm
        case String(localized: "Call"):   return DS.tint
        case String(localized: "Check"):  return DS.attention
        case String(localized: "UTXO"):   return vault
        // The spec's own subclassifications (prd §728e): an expiry check is a
        // VERIFY frame and a deploy is a DEFAULT frame, so each keeps its
        // mode's hue — the name is what separates them.
        case String(localized: "Expiry"): return DS.stepVerify
        case String(localized: "Deploy"): return DS.tint
        // An unnamed mode is drawn as a step rather than given a hue of its
        // own: a colour is a claim about what the step DID, and we do not know.
        default: return DS.textTertiary
        }
    }
}

/// ONE TRANSACTION'S STEPS, IN ORDER — widths by what each cost, fill by what
/// each did (prd §698).
///
/// **The transaction RUNS on open** (prd §503, moment 01). A frame transaction
/// is a SEQUENCE and this draws it as one, so it fills step by step rather than
/// being suddenly present, each segment starting when the ones before it have
/// finished. The delays come off the same weights the WIDTHS do, so a step that
/// burned most of the gas visibly takes most of the time: the drawing and its
/// timing are the same fact told twice.
///
/// Off under Reduce Motion — this is an appear-triggered animation and
/// `design-motion-audit` requires the honour — and off in a ROW's strip, which
/// is a texture rather than a document.
struct RoomFrameStrip: View {
    let steps: [RoomFrames.Step]
    var height: CGFloat = 5
    let hue: (String) -> Color
    var runs = false
    var onTap: ((Int) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ran = false

    private static let runDuration: Double = 0.62

    private func widths(_ width: CGFloat) -> [CGFloat] {
        let gaps = CGFloat(max(0, steps.count - 1)) * 1.5
        let usable = max(0, width - gaps)
        return RoomFrames.shares(steps).map { usable * CGFloat($0) }
    }

    /// When each segment starts, as a fraction of the run — the same weights
    /// the widths use, so the two cannot disagree.
    private var starts: [Double] {
        var running = 0.0
        return RoomFrames.shares(steps).map { share in
            defer { running += share }
            return running
        }
    }

    var body: some View {
        let offsets = starts
        GeometryReader { geo in
            let w = widths(geo.size.width)
            HStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    segment(step)
                        .frame(width: w.indices.contains(index) ? w[index] : 0)
                        .scaleEffect(x: drawn(index) ? 1 : 0, anchor: .leading)
                        .opacity(drawn(index) ? 1 : 0)
                        .animation(reduceMotion ? nil
                                   : .easeOut(duration: Self.runDuration * 0.34)
                                        .delay(Self.runDuration * offsets[index]),
                                   value: ran)
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
                        .accessibilityLabel(spoken(step))
                        .onTapGesture { onTap?(index) }
                    if index < steps.count - 1 {
                        Rectangle().fill(DS.page).frame(width: 1.5)
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: min(5, height / 2), style: .continuous))
        .accessibilityLabel(steps.map(spoken).joined(separator: ", "))
        .onAppear { ran = true }
    }

    private func drawn(_ index: Int) -> Bool {
        guard runs, !reduceMotion else { return true }
        return ran
    }

    private func spoken(_ step: RoomFrames.Step) -> String {
        switch step.outcome {
        case .ran:        return step.modeName
        case .failed:     return String(localized: "\(step.modeName), failed")
        case .rolledBack: return String(localized: "\(step.modeName), rolled back")
        case .unread:     return String(localized: "\(step.modeName), outcome unread")
        case .skipped:    return String(localized: "\(step.modeName), skipped")
        }
    }

    /// **MODE IS THE FILL; OUTCOME OVERRIDES IT** (prd §698). A failure takes
    /// the alarm colour because it is the one thing a reader must not miss; a
    /// rollback is an OUTLINE, because it ran and was undone, which is a
    /// different fact; an unread step is hollow, because a receipt we could not
    /// pair is not a step that went wrong.
    @ViewBuilder private func segment(_ step: RoomFrames.Step) -> some View {
        switch step.outcome {
        case .failed:
            Rectangle().fill(DS.destructive)
        case .rolledBack:
            Rectangle().fill(hue(step.modeName).opacity(0.18))
                .overlay {
                    Rectangle().strokeBorder(hue(step.modeName),
                                             style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                }
        case .unread:
            Rectangle().fill(Color.clear)
                .overlay { Rectangle().strokeBorder(DS.fillLine, lineWidth: 1) }
        // **SKIPPED IS DASHED AND NEUTRAL (prd §728)** — it never ran, so it
        // takes no mode fill and no alarm, and the dash keeps it from reading
        // as an unread receipt.
        case .skipped:
            Rectangle().fill(Color.clear)
                .overlay {
                    Rectangle().strokeBorder(DS.textTertiary,
                                             style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
        case .ran:
            Rectangle().fill(hue(step.modeName).opacity(0.85))
        }
    }
}
