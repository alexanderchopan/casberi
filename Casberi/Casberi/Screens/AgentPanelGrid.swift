import SwiftUI

/// The agent's instrument panel (prd §334, layout B — "the bento").
///
/// The top-ranked room takes a full-width hero cell, the next takes a tall
/// column beside two smalls, and the rest pair off — so the hierarchy says
/// "this is YOUR panel" rather than a settings grid, and it costs no new
/// signal: the hero is simply `rank`'s first card, which is already the room
/// you open most. The pattern is FIXED (`AgentPanel.Slot.at`), never derived
/// from content measurements, because a layout that re-derives itself
/// re-shuffles when a figure changes shape, and a panel that rearranges
/// between opens reads as broken.
///
/// Holds no `Thing` — every tile is drawn from value types and hands back a
/// source NAME on tap, so the liveness rules have nothing here to reach.
struct AgentPanelGrid: View {
    let cards: [AgentPanel.Card]
    /// Fires with the card's source — the composer switches the feed to that
    /// room and lowers the agent.
    let onOpen: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One small tile's height; the hero and the tall cell span two rows plus
    /// the gutter between them.
    private static let unit: CGFloat = 118
    private static let gutter: CGFloat = DS.Space.s2
    private static var double: CGFloat { unit * 2 + gutter }
    /// The flow band's row — taller than a small, shorter than the hero:
    /// enough for three lanes a side plus their labels, measured against the
    /// real band's 38pt lane rhythm.
    private static let bandHeight: CGFloat = 150

    /// A figure that only reads at full width — the flow band's three labelled
    /// columns cannot survive a half-width cell (the sizing inventory's "No"
    /// list), so it takes a band row of its own regardless of rank.
    private static func demandsFullWidth(_ figure: AgentPanel.Figure) -> Bool {
        if case .flow = figure { return true }
        return false
    }

    var body: some View {
        // Full-width figures come out of the bento flow entirely: the hero is
        // the top-ranked TILE, and the bands stack beneath it in rank order.
        let bands = cards.filter { Self.demandsFullWidth($0.figure) }
        let tiles = cards.filter { !Self.demandsFullWidth($0.figure) }
        VStack(spacing: Self.gutter) {
            if let hero = tiles.first {
                tile(hero, slot: .hero, index: 0)
                    .frame(height: Self.double)
            }
            ForEach(Array(bands.enumerated()), id: \.element.key) { i, band in
                tile(band, slot: .band, index: 1 + i)
                    .frame(height: Self.bandHeight)
            }
            // The tall cell and its two stacked smalls — only when there are
            // enough cards to fill the shape; a tall beside one small and a
            // hole reads as a broken layout, so three cards short of the
            // pattern fall through to plain pairs instead.
            let rest = Array(tiles.dropFirst())
            if rest.count >= 3 {
                HStack(alignment: .top, spacing: Self.gutter) {
                    tile(rest[0], slot: .tall, index: 1)
                        .frame(height: Self.double)
                    VStack(spacing: Self.gutter) {
                        tile(rest[1], slot: .small, index: 2)
                            .frame(height: Self.unit)
                        tile(rest[2], slot: .small, index: 3)
                            .frame(height: Self.unit)
                    }
                }
                pairRows(Array(rest.dropFirst(3)), startIndex: 4)
            } else {
                pairRows(rest, startIndex: 1)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s3)
    }

    /// The remaining cards, two to a row. An odd last card keeps its column
    /// width rather than stretching — a lone full-width small tile would read
    /// as a second hero.
    @ViewBuilder
    private func pairRows(_ cards: [AgentPanel.Card], startIndex: Int) -> some View {
        ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { i in
            HStack(alignment: .top, spacing: Self.gutter) {
                tile(cards[i], slot: .small, index: startIndex + i)
                    .frame(height: Self.unit)
                if i + 1 < cards.count {
                    tile(cards[i + 1], slot: .small, index: startIndex + i + 1)
                        .frame(height: Self.unit)
                } else {
                    Color.clear.frame(height: Self.unit)
                }
            }
        }
    }

    private func tile(_ card: AgentPanel.Card, slot: AgentPanel.Slot, index: Int) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(card.source)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    BridgeIcon(name: card.source, size: 17, circular: false)
                    Text(card.title)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                FigureView(figure: card.figure, slot: slot, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Only the hero says anything under its figure — its one line
                // is the room's own subtitle, a label rather than synthesis.
                // Small tiles stay wordless; their title is their caption.
                if slot == .hero, !card.caption.isEmpty {
                    Text(card.caption)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(DS.surfaceSheet,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .dsHover()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.source): \(card.title)")
        .modifier(TileEntrance(index: index, reduceMotion: reduceMotion))
    }
}

// MARK: - The figures

/// Draws one `AgentPanel.Figure` into whatever space it's given, sized to its
/// slot: a hero curve fills with a gradient, a small tile's bars drop to two
/// rows so nothing clips.
///
/// Every figure animates IN from nothing on appear — bars grow, the curve
/// draws, cells fade up — and all of it collapses to the settled state under
/// Reduce Motion (`design-motion-audit.py`'s first check).
private struct FigureView: View {
    let figure: AgentPanel.Figure
    let slot: AgentPanel.Slot
    let reduceMotion: Bool
    @State private var grown = false

    private var t: Double { grown || reduceMotion ? 1 : 0 }
    /// How many entries a slot has room for — measured against the 118pt
    /// small cell, not guessed: three bar rows at their own spacing overflow
    /// it, and an overflowing figure clips silently.
    private var rows: Int {
        switch slot {
        case .hero, .tall, .band: return 4
        case .small:              return 2
        }
    }

    var body: some View {
        Group {
            switch figure {
            case .treemap(let cells): treemap(cells)
            case .bars(let bars):     barsView(bars)
            case .rail(let segs):     rail(segs)
            case .pulse(let counts):  pulse(counts)
            case .curve(let values):  curve(values)
            case .wall(let urls):     wall(urls)
            case .flow(let inLanes, let outLanes):
                FlowFigure(inLanes: inLanes, outLanes: outLanes, t: t)
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.standard.delay(0.08), value: grown)
        .onAppear { grown = true }
    }

    // Rank-ordered rows of proportional blocks — the `UnitTreemap` grammar at
    // tile scale, rank-ordered rather than area-proportional for §300's
    // reason: true squarified cells arrive as slivers too thin to label.
    private func treemap(_ cells: [AgentPanel.Cell]) -> some View {
        let shown = Array(cells.prefix(rows))
        let total = max(1, shown.reduce(0) { $0 + $1.weight })
        return GeometryReader { geo in
            VStack(spacing: 3) {
                ForEach(Array(shown.enumerated()), id: \.offset) { i, cell in
                    let share = Double(cell.weight) / Double(total)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(DS.tint.opacity(0.16 + 0.13 * (1 - Double(i) / 4)))
                        Text(cell.label)
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                    }
                    .frame(width: max(28, geo.size.width * (0.35 + 0.65 * share) * t),
                           alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func barsView(_ bars: [AgentPanel.Bar]) -> some View {
        let shown = Array(bars.prefix(rows))
        let shares = AgentPanel.normalized(shown)
        return GeometryReader { geo in
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(shown.enumerated()), id: \.offset) { i, bar in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(bar.label)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(bar.detail)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                                .monospacedDigit()
                        }
                        Capsule()
                            .fill(DS.tint.opacity(i == 0 ? 0.85 : 0.4))
                            .frame(width: max(3, geo.size.width * shares[i] * t), height: 4)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func rail(_ segments: [AgentPanel.Segment]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(segments.prefix(4).enumerated()), id: \.offset) { _, seg in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tone(seg.tone))
                            .frame(width: max(2, geo.size.width * seg.share * t))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 10)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(segments.prefix(max(1, rows - 1)).enumerated()), id: \.offset) { _, seg in
                    HStack(spacing: 5) {
                        Circle().fill(tone(seg.tone)).frame(width: 6, height: 6)
                        Text(seg.label)
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    /// The tone index stays an Int in the model (Foundation-only) and becomes
    /// a color exactly here.
    private func tone(_ index: Int) -> Color {
        switch index {
        case 1:  return Color(hex: "#30d158")
        case 2:  return Color(hex: "#ff453a")
        default: return DS.tint
        }
    }

    /// A contribution wall, windowed to the slot: the hero and tall cells show
    /// the full twelve weeks the composer hands over, a small cell the last
    /// eight — measured, since twelve columns of 2px gaps in a half-width tile
    /// leave cells under 6pt, where the levels stop being distinguishable.
    private func pulse(_ counts: [Int]) -> some View {
        let levels = AgentPanel.levels(counts)
        let weeksShown = slot == .small ? 8 : 12
        let shown = Array(levels.suffix(7 * weeksShown))
        let weeks = stride(from: 0, to: shown.count, by: 7).map {
            Array(shown[$0..<min($0 + 7, shown.count)])
        }
        return HStack(spacing: 2) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 2) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, level in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(level == 0 ? DS.fillLine
                                             : DS.tint.opacity(0.25 + 0.2 * Double(level)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .opacity(t)
    }

    private func curve(_ values: [Double]) -> some View {
        let points = AgentPanel.normalized(values)
        let rising = (values.last ?? 0) >= (values.first ?? 0)
        let stroke = rising ? Color(hex: "#30d158") : Color(hex: "#ff453a")
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            // A closure, not a nested func — a `func` declaration is a
            // statement the ViewBuilder result builder refuses, and the
            // error it produces ("Content could not be inferred") points
            // nowhere near the cause.
            let at: (Int, Double) -> CGPoint = { i, v in
                let x = points.count == 1 ? w : w * Double(i) / Double(points.count - 1)
                return CGPoint(x: x, y: h - (h - 4) * v - 2)
            }
            let line = Path { p in
                for (i, v) in points.enumerated() {
                    if i == 0 { p.move(to: at(i, v)) } else { p.addLine(to: at(i, v)) }
                }
            }
            ZStack {
                // The hero earns the gradient fill under its line — at small
                // scale the fill muddies against the sheet, so smalls stay a
                // bare stroke.
                if slot == .hero, let first = points.first, let last = points.last {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h))
                        p.addLine(to: at(0, first))
                        for (i, v) in points.enumerated().dropFirst() { p.addLine(to: at(i, v)) }
                        p.addLine(to: CGPoint(x: w, y: h))
                        _ = last
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [stroke.opacity(0.22), stroke.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(t)
                }
                line.trim(from: 0, to: t)
                    .stroke(stroke,
                            style: StrokeStyle(lineWidth: slot == .hero ? 2.5 : 2,
                                               lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func wall(_ urls: [String]) -> some View {
        let grid = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]
        return LazyVGrid(columns: grid, spacing: 3) {
            ForEach(Array(urls.prefix(4).enumerated()), id: \.offset) { _, url in
                AsyncImage(url: URL(string: url)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(DS.fillLine)
                }
                .frame(height: slot == .small ? 30 : 42)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .opacity(t)
    }
}

/// The panel's sankey — inflow lanes, the spine, outflow lanes, at band
/// scale. A REDUCTION of `WalletFlowBand`, not a copy: same one-scale rule
/// (both sides share `max(inUSD, outUSD)`, or a $200 week of outflow draws as
/// wide as a $20,000 week of inflow), same equal-information ribbons, but
/// three lanes a side and no window chips — the tap lands in the Wallet room,
/// where the full band carries its controls.
private struct FlowFigure: View {
    let inLanes: [AgentPanel.FlowLane]
    let outLanes: [AgentPanel.FlowLane]
    /// The entrance's progress, handed down from `FigureView` so the ribbons
    /// draw on the same clock as every other figure.
    let t: Double

    private var shownIn: [AgentPanel.FlowLane] { Array(inLanes.prefix(3)) }
    private var shownOut: [AgentPanel.FlowLane] { Array(outLanes.prefix(3)) }
    /// ONE scale across both sides — the band's whole claim is that the two
    /// sides are not the same size.
    private var scale: Double {
        max(shownIn.reduce(0) { $0 + $1.usd }, shownOut.reduce(0) { $0 + $1.usd })
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let labelW = w * 0.30
            let spineX = w / 2
            ZStack {
                ribbons(from: spineX - 6, to: labelW, lanes: shownIn,
                        height: h, leftward: true)
                ribbons(from: spineX + 6, to: w - labelW, lanes: shownOut,
                        height: h, leftward: false)
                // The spine — the wallet itself.
                Capsule()
                    .fill(DS.tint)
                    .frame(width: 4, height: h * 0.82)
                    .position(x: spineX, y: h / 2)
                laneLabels(shownIn, x: 0, width: labelW - 8, height: h,
                           alignment: .leading)
                laneLabels(shownOut, x: w - labelW + 8, width: labelW - 8, height: h,
                           alignment: .trailing)
            }
        }
        .opacity(t)
    }

    /// The ribbons for one side — each lane a bezier band from its label row
    /// to the spine, thickness by its share of the shared scale. Every ribbon
    /// the same hue at the same opacity: magnitude is the WIDTH, and hue
    /// carrying nothing is what keeps the drawing factual.
    private func ribbons(from spineEdge: CGFloat, to labelEdge: CGFloat,
                         lanes: [AgentPanel.FlowLane], height: CGFloat,
                         leftward: Bool) -> some View {
        let slots = max(1, lanes.count)
        return ForEach(Array(lanes.enumerated()), id: \.offset) { i, lane in
            let share = scale > 0 ? lane.usd / scale : 0
            let thickness = max(3, height * 0.5 * share)
            let laneY = height * (Double(i) + 0.5) / Double(slots)
            let midX = (spineEdge + labelEdge) / 2
            Path { p in
                p.move(to: CGPoint(x: labelEdge, y: laneY))
                p.addCurve(to: CGPoint(x: spineEdge, y: height / 2),
                           control1: CGPoint(x: midX, y: laneY),
                           control2: CGPoint(x: midX, y: height / 2))
            }
            .stroke(DS.tint.opacity(0.38), style: StrokeStyle(lineWidth: thickness,
                                                              lineCap: .round))
        }
    }

    private func laneLabels(_ lanes: [AgentPanel.FlowLane], x: CGFloat,
                            width: CGFloat, height: CGFloat,
                            alignment: Alignment) -> some View {
        let slots = max(1, lanes.count)
        return ForEach(Array(lanes.enumerated()), id: \.offset) { i, lane in
            VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 0) {
                Text(lane.count > 1 ? "\(lane.name) ×\(lane.count)" : lane.name)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Text(compactUSD(lane.usd))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
            }
            .frame(width: width, alignment: alignment)
            .position(x: x + width / 2,
                      y: height * (Double(i) + 0.5) / Double(slots))
        }
    }

    private func compactUSD(_ usd: Double) -> String {
        if usd >= 1000 { return String(format: "$%.1fk", usd / 1000) }
        return String(format: "$%.0f", usd)
    }
}

/// One tile's staggered rise. Honours Reduce Motion — the audit's first check,
/// and this modifier is appear-triggered by construction.
private struct TileEntrance: ViewModifier {
    let index: Int
    let reduceMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil
                       : DS.Motion.standard.delay(Double(min(index, 7)) * 0.04),
                       value: shown)
            .onAppear { shown = true }
    }
}
