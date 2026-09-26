import SwiftUI

/// THE FRAMES SCOPE'S DRAWING — one component, three rooms (prd §698).
///
/// A caption, a stack of per-transaction strips, a legend naming the modes, and
/// a census note where the stack is capped. It is Hegotá UTXO's figure
/// generalised: that room had reasoned the whole shape out (§510, §566) and the
/// other two each drew something else, one of which — Privacy's gas budget bar
/// — was not a frames reading at all.
///
/// **Every dimension derives from `DSRoomChassis.figureSlot`** (§665), so the
/// figure grows with the slot instead of clipping into the rail beneath it.
struct RoomFramesFigure: View {
    let runs: [RoomFrames.Run]
    /// Kept for the callers' signature; the bars wear the one accent (prd §936).
    let hue: (String) -> Color
    var onOpenStep: ((String, Int) -> Void)? = nil
    var caption: String? = nil
    @State private var lit: String?

    private var mix: RoomFrames.Mix? { RoomFrames.mix(runs) }

    var body: some View {
        if let mix {
            // **WHAT RAN, AS BARS (prd §936).** The flow (§925) — nodes by
            // position, ribbons between them, a stub where runs ended — is
            // deleted: one bar per kind of step, as long as its count, in the
            // one accent; the failed steps are the one red bar. The rows
            // below still draw each transaction's strip.
            DSBarFigure(reading: { reading(mix) },
                        bars: DSBarList(bars: Self.bars(mix), lit: lit) { picked in
                            lit = lit == picked ? nil : picked
                        })
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(RoomFrames.caption(mix)))
        }
    }

    static let failedID = "·failed"

    static func bars(_ mix: RoomFrames.Mix) -> [DSBarList.Bar] {
        let peak = Double(max(mix.slices.map(\.count).max() ?? 1, mix.failed, 1))
        var out = mix.slices.map {
            DSBarList.Bar(id: $0.id, label: $0.modeName, value: String($0.count),
                          share: Double($0.count) / peak)
        }
        if mix.failed > 0 {
            out.append(DSBarList.Bar(id: failedID, label: String(localized: "Failed"),
                                     value: String(mix.failed),
                                     share: Double(mix.failed) / peak, alarm: true))
        }
        return out
    }

    @ViewBuilder
    private func reading(_ mix: RoomFrames.Mix) -> some View {
        if let lit, let slice = mix.slices.first(where: { $0.id == lit }) {
            DSFigureReading(number: String(slice.count),
                            caption: slice.count == 1 ? String(localized: "\(slice.modeName) step")
                                                      : String(localized: "\(slice.modeName) steps"))
        } else if lit == Self.failedID {
            DSFigureReading(number: String(mix.failed),
                            caption: mix.failed == 1 ? String(localized: "step failed")
                                                     : String(localized: "steps failed"))
        } else {
            let noun = mix.transactions == 1 ? String(localized: "transaction")
                                             : String(localized: "transactions")
            DSFigureReading(number: String(mix.transactions),
                            caption: [noun, caption].compactMap { $0 }.joined(separator: " · "),
                            alarm: mix.failed > 0 ? String(localized: "\(String(mix.failed)) failed") : nil)
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
