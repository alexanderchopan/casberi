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
    /// This chain's colour for a mode NAME. The one thing the three rooms may
    /// legitimately differ on, since the vocabularies differ.
    let hue: (String) -> Color
    /// Raised with a run's id and a step index — the frame sheet, where a room
    /// has one.
    var onOpenStep: ((String, Int) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// **HOW MANY RUNS FIT, DERIVED RATHER THAN GUESSED.** The slot is a hard,
    /// clipped box; the caption, the legend and the note are all inside the
    /// figure's own budget, and what is left divides between the strips. Five
    /// was Hegotá's measured number at this slot height and falls out of the
    /// arithmetic rather than being written down again.
    private static let captionRow: CGFloat = 16
    private static let legendRow: CGFloat = 16
    private static let noteRow: CGFloat = 16
    private static let stripGap: CGFloat = 5
    /// The floor a strip stays readable at, and the ceiling past which it stops
    /// looking like a sequence and starts looking like a chart.
    private static let stripRange: ClosedRange<CGFloat> = 9...22

    private var mix: RoomFrames.Mix? { RoomFrames.mix(runs) }

    private var framed: [RoomFrames.Run] { RoomFrames.runs(runs) }

    private var budget: CGFloat {
        DSRoomChassis.figureSlot
            - Self.captionRow - Self.legendRow
            - DS.Space.s1 * 2
    }

    /// The most runs that fit at the strip's floor, leaving room for the note
    /// when there is one to leave room for.
    private var rowsShown: Int {
        let note = framed.count > 0 ? Self.noteRow : 0
        let room = budget - note
        let each = Self.stripRange.lowerBound + Self.stripGap
        return max(1, min(framed.count, Int(floor(room / each))))
    }

    private var stripHeight: CGFloat {
        let drawn = CGFloat(rowsShown)
        let note = framed.count > rowsShown ? Self.noteRow : 0
        let room = budget - note - Self.stripGap * max(0, drawn - 1)
        let each = room / max(1, drawn)
        return min(Self.stripRange.upperBound, max(Self.stripRange.lowerBound, each))
    }

    var body: some View {
        if let mix {
            let drawn = Array(framed.prefix(rowsShown))
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(RoomFrames.caption(mix))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .padding(.trailing, DSRoomChassis.gearColumn)
                VStack(spacing: Self.stripGap) {
                    ForEach(drawn) { run in
                        RoomFrameStrip(steps: run.steps, height: stripHeight, hue: hue,
                                       onTap: onOpenStep.map { open in { index in open(run.id, index) } })
                    }
                }
                legend(mix)
                if let note = RoomFrames.censusNote(drawn: drawn.count, of: framed.count) {
                    Text(note)
                        .dsText(.label11).foregroundStyle(DS.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(RoomFrames.caption(mix)))
        }
    }

    /// The modes present, with their counts — a census over every framed
    /// transaction, which is what the "N steps" headline is made of.
    @ViewBuilder private func legend(_ mix: RoomFrames.Mix) -> some View {
        HStack(spacing: DS.Space.s3) {
            ForEach(mix.slices.prefix(4)) { slice in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(hue(slice.modeName).opacity(0.85))
                        .frame(width: 8, height: 8)
                    Text("\(slice.modeName) \(String(slice.count))")
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
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
    static let vault = Color(red: 0.30, green: 0.78, blue: 0.92)

    static func hue(_ modeName: String) -> Color {
        switch modeName {
        case String(localized: "Verify"): return Color(red: 0.55, green: 0.47, blue: 0.93)
        case String(localized: "Send"):   return DS.confirm
        case String(localized: "Call"):   return DS.tint
        case String(localized: "Check"):  return DS.attention
        case String(localized: "UTXO"):   return vault
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
        case .ran:
            Rectangle().fill(hue(step.modeName).opacity(0.85))
        }
    }
}
