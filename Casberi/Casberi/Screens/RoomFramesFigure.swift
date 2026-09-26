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
    let hue: (String) -> Color
    var onOpenStep: ((String, Int) -> Void)? = nil
    /// The scope: one account's name, or how many you follow — the crown's
    /// own caption (prd §925).
    var caption: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// **THE PRESSED NODE (prd §925)** — a node id; while set, its ribbons
    /// draw full and everything else goes quiet, and the reading says where
    /// those transactions went next. A tap toggles.
    @State private var lit: String?

    private var mix: RoomFrames.Mix? { RoomFrames.mix(runs) }
    private var flow: RoomFrames.Flow? { RoomFrames.flow(runs) }

    var body: some View {
        if let mix, let flow {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                reading(mix, flow)
                // **THE SHAPE OF THE TRANSACTIONS (prd §925).** Steps by
                // position, first to second to third: a node is a mode
                // sized by how many transactions ran it there, a ribbon by
                // how many went on, a failed step the alarm colour, a run
                // that ends simply ending. One strip per transaction — the
                // strip each row below already draws — is deleted from the
                // figure: that was the list restated (§922's rule).
                FrameFlowView(flow: flow, hue: hue, lit: lit) { picked in
                    DSHaptic.selection()
                    lit = lit == picked ? nil : picked
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    ForEach(0..<flow.positions, id: \.self) { position in
                        Text(RoomFrames.positionWord(position))
                        if position < flow.positions - 1 { Spacer(minLength: 0) }
                    }
                    if flow.beyond > 0 {
                        Spacer(minLength: 0)
                        Text(String(localized: "+\(String(flow.beyond)) more →"))
                    }
                }
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(1)
                legend(mix)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? nil : DS.Motion.standard, value: lit)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(RoomFrames.caption(mix)))
        }
    }

    /// **THE CROWN'S READING (prd §925)** — caption, "N steps" at `stat24`,
    /// and the sentence the caption used to carry ("5 transactions · UTXO
    /// and Verify, evenly", a failed count in the alarm colour). Under a
    /// press it is the node and where its transactions went next. Only the
    /// reading clears the gear (§920's rule).
    @ViewBuilder
    private func reading(_ mix: RoomFrames.Mix, _ flow: RoomFrames.Flow) -> some View {
        let pressed = lit.flatMap { id in flow.nodes.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 2) {
            Text(pressed.map { RoomFrames.positionWord($0.position) + " " + String(localized: "step") }
                 ?? caption ?? "")
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .lineLimit(1)
                .opacity((pressed != nil || caption != nil) ? 1 : 0)
            Text(pressed.map { "\($0.label) · \(String($0.count))" }
                 ?? RoomFrames.headline(mix) ?? String(localized: "What your transactions ran"))
                .dsText(.stat24)
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            line(mix, flow, pressed: pressed)
                .dsText(.body17)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, DSRoomChassis.gearColumn)
    }

    private func line(_ mix: RoomFrames.Mix, _ flow: RoomFrames.Flow,
                      pressed: RoomFrames.Flow.Node?) -> Text {
        if let pressed {
            var parts = flow.outgoing(pressed.id).map { link -> String in
                let to = flow.nodes.first { $0.id == link.to }
                return "\(to?.label ?? link.to) \(String(link.count))"
            }
            let ended = flow.ended(pressed.id)
            if ended > 0 {
                parts.append(ended == 1 ? String(localized: "1 ends here")
                                        : String(localized: "\(String(ended)) end here"))
            }
            return Text(parts.isEmpty ? String(localized: "nothing after")
                        : String(localized: "then \(parts.joined(separator: ", "))"))
                .foregroundStyle(DS.textSecondary)
        }
        let sentence = RoomFrames.caption(mix)
        // The failed or rolled-back clause wears the alarm colour, as the
        // strips' red segments did.
        if mix.failed > 0 || mix.rolledBack > 0, let dot = sentence.range(of: " · ") {
            return Text(String(sentence[..<dot.lowerBound])).foregroundStyle(DS.textSecondary)
                + Text(verbatim: " · ").foregroundStyle(DS.textTertiary)
                + Text(String(sentence[dot.upperBound...])).foregroundStyle(DS.destructive)
        }
        return Text(sentence).foregroundStyle(DS.textSecondary)
    }

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
            if mix.failed > 0 {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(DS.destructive.opacity(0.85))
                        .frame(width: 8, height: 8)
                    Text(String(localized: "Failed \(String(mix.failed))"))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The flow itself (prd §925): nodes down each position's column, ribbons
/// between consecutive positions, a stub where runs end. The ribbons are a
/// `Canvas`; the nodes are views over it so each is a button and a label.
struct FrameFlowView: View {
    let flow: RoomFrames.Flow
    let hue: (String) -> Color
    var lit: String? = nil
    var onPress: ((String) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A node's width at up to three columns; four columns narrow it so the
    /// ribbons keep enough run to read as ribbons (seen on the Frames room:
    /// 58pt × 4 left 25pt gaps and the ribbons were stubs).
    private static let nodeWidth: CGFloat = 58
    private func nodeWidth(for size: CGSize) -> CGFloat {
        let columns = CGFloat(max(1, flow.positions))
        return min(Self.nodeWidth, max(40, size.width / (columns * 1.8)))
    }
    private static let nodeGap: CGFloat = 6
    /// **A NODE IS AT LEAST TALL ENOUGH FOR ITS WORD** — two lines of
    /// `label12` — the same kind of convention as Activity's peak floor: it
    /// can only ever OVERSTATE a lone step, never understate a busy one, and
    /// the count inside the node is the exact figure either way. 10pt drew
    /// "Rolle…" on the Frames room.
    private static let minNode: CGFloat = 32
    private static let stub: CGFloat = 22

    private struct Placed {
        let node: RoomFrames.Flow.Node
        let frame: CGRect
    }

    private func fill(_ node: RoomFrames.Flow.Node) -> Color {
        switch node.kind {
        case .ran, .unread: return hue(node.modeName)
        case .failed:       return DS.destructive
        case .rolledBack:   return DS.attention
        case .skipped:      return DS.fillStrong
        }
    }

    private func place(in size: CGSize) -> [Placed] {
        let columns = max(1, flow.positions)
        let nodeWidth = nodeWidth(for: size)
        let gapX = columns > 1 ? (size.width - nodeWidth * CGFloat(columns)) / CGFloat(columns - 1) : 0
        let tallest = (0..<columns).map { p in
            let ns = flow.nodes(at: p)
            return ns.reduce(0) { $0 + $1.count }
        }.max() ?? 1
        let busiestCount = (0..<columns).map { flow.nodes(at: $0).count }.max() ?? 1
        let unit = min(18, (size.height - Self.nodeGap * CGFloat(busiestCount - 1)) / CGFloat(max(1, tallest)))
        var out: [Placed] = []
        for p in 0..<columns {
            var y: CGFloat = 0
            let x = CGFloat(p) * (nodeWidth + gapX)
            for node in flow.nodes(at: p) {
                let h = max(Self.minNode, unit * CGFloat(node.count))
                out.append(Placed(node: node, frame: CGRect(x: x, y: y, width: nodeWidth, height: h)))
                y += h + Self.nodeGap
            }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let placed = place(in: geo.size)
            let frames = Dictionary(uniqueKeysWithValues: placed.map { ($0.node.id, $0.frame) })
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    // Each node hands out its right edge to its outgoing
                    // ribbons and its ends in order, and its left edge to its
                    // incoming ones, so ribbons never cross inside a node.
                    var outY: [String: CGFloat] = [:]
                    var inY: [String: CGFloat] = [:]
                    // **RIBBONS LEAVE AND ARRIVE IN THE ORDER OF THE OTHER
                    // END'S HEIGHT**, so two ribbons out of one node never
                    // cross each other (seen on the first build: the smaller
                    // ribbon took the top slice and dived under the larger).
                    let byLanding = flow.links.sorted { a, b in
                        let ya = frames[a.to]?.minY ?? 0, yb = frames[b.to]?.minY ?? 0
                        return a.from != b.from ? (frames[a.from]?.minY ?? 0) < (frames[b.from]?.minY ?? 0) : ya < yb
                    }
                    var outStart: [String: CGFloat] = [:]
                    for link in byLanding {
                        guard let a = frames[link.from], let na = flow.nodes.first(where: { $0.id == link.from }) else { continue }
                        outStart[link.from + "→" + link.to] = a.minY + (outY[link.from] ?? 0)
                        outY[link.from, default: 0] += a.height * CGFloat(link.count) / CGFloat(max(1, na.count))
                    }
                    let byOrigin = flow.links.sorted { a, b in
                        let ya = frames[a.from]?.minY ?? 0, yb = frames[b.from]?.minY ?? 0
                        return a.to != b.to ? (frames[a.to]?.minY ?? 0) < (frames[b.to]?.minY ?? 0) : ya < yb
                    }
                    var inStart: [String: CGFloat] = [:]
                    for link in byOrigin {
                        guard let b = frames[link.to], let nb = flow.nodes.first(where: { $0.id == link.to }) else { continue }
                        inStart[link.from + "→" + link.to] = b.minY + (inY[link.to] ?? 0)
                        inY[link.to, default: 0] += b.height * CGFloat(link.count) / CGFloat(max(1, nb.count))
                    }
                    for link in flow.links {
                        guard let a = frames[link.from], let b = frames[link.to],
                              let na = flow.nodes.first(where: { $0.id == link.from }),
                              let nb = flow.nodes.first(where: { $0.id == link.to }) else { continue }
                        let ha = a.height * CGFloat(link.count) / CGFloat(max(1, na.count))
                        let hb = b.height * CGFloat(link.count) / CGFloat(max(1, nb.count))
                        let y0 = outStart[link.from + "→" + link.to] ?? a.minY
                        let y1 = inStart[link.from + "→" + link.to] ?? b.minY
                        let x0 = a.maxX, x1 = b.minX, midX = (x0 + x1) / 2
                        var path = Path()
                        path.move(to: CGPoint(x: x0, y: y0))
                        path.addCurve(to: CGPoint(x: x1, y: y1),
                                      control1: CGPoint(x: midX, y: y0), control2: CGPoint(x: midX, y: y1))
                        path.addLine(to: CGPoint(x: x1, y: y1 + hb))
                        path.addCurve(to: CGPoint(x: x0, y: y0 + ha),
                                      control1: CGPoint(x: midX, y: y1 + hb), control2: CGPoint(x: midX, y: y0 + ha))
                        path.closeSubpath()
                        let quiet = lit != nil && lit != link.from && lit != link.to
                        ctx.fill(path, with: .color(fill(na).opacity(quiet ? 0.1 : (lit == nil ? 0.35 : 0.6))))
                    }
                    for end in flow.ends {
                        guard let a = frames[end.node],
                              let na = flow.nodes.first(where: { $0.id == end.node }) else { continue }
                        let h = a.height * CGFloat(end.count) / CGFloat(max(1, na.count))
                        let y0 = a.minY + (outY[end.node] ?? 0)
                        outY[end.node, default: 0] += h
                        let rect = CGRect(x: a.maxX, y: y0, width: Self.stub, height: h)
                        let quiet = lit != nil && lit != end.node
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 3),
                                 with: .linearGradient(
                                    Gradient(colors: [fill(na).opacity(quiet ? 0.1 : 0.35), fill(na).opacity(0)]),
                                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
                    }
                }
                ForEach(placed, id: \.node.id) { item in
                    nodeView(item)
                        .frame(width: item.frame.width, height: item.frame.height)
                        .position(x: item.frame.midX, y: item.frame.midY)
                }
            }
        }
        .chartWipe(reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private func nodeView(_ item: Placed) -> some View {
        let node = item.node
        let quiet = lit != nil && lit != node.id
            && !flow.links.contains { ($0.from == lit && $0.to == node.id) || ($0.to == lit && $0.from == node.id) }
        let tall = item.frame.height >= 16
        let face = RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fill(node))
            .overlay(alignment: .leading) {
                if tall {
                    Text("\(node.label) \(String(node.count))")
                        .dsText(.label12)
                        .foregroundStyle(node.kind == .skipped ? DS.textSecondary
                                         : (node.kind == .ran || node.kind == .unread) ? Color.black.opacity(0.8) : Color.white)
                        // A tall node lets a long word wrap ("Rolled back 1"
                        // clipped at one line on the Frames room).
                        .lineLimit(item.frame.height >= 32 ? 2 : 1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                }
            }
            .opacity(quiet ? 0.3 : 1)
        Button {
            onPress?(node.id)
        } label: {
            face.contentShape(Rectangle())
        }
        .buttonStyle(PressSpring())
        .accessibilityLabel(Text("\(RoomFrames.positionWord(node.position)) \(node.label) \(String(node.count))"))
        .accessibilityAddTraits(lit == node.id ? .isSelected : [])
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
