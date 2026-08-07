import SwiftUI

/// The agent's instrument panel (prd §334) — the rendering half of
/// `AgentPanel`.
///
/// A two-column grid of square tiles, each one a connected room's own hero
/// figure. Square because every figure here is a SHAPE and shapes read at a
/// glance; two columns because at one column this is the list it replaced, and
/// at three the treemap labels stop fitting.
///
/// Holds no `Thing` — every tile is drawn from value types and hands back a
/// source NAME on tap, which the composer turns into a room switch. So the
/// liveness rules have nothing here to reach, same as `AgentOpenBoard`.
struct AgentPanelGrid: View {
    let cards: [AgentPanel.Card]
    /// Fires with the card's source — the composer switches the feed to that
    /// room and lowers the agent.
    let onOpen: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.flexible(), spacing: DS.Space.s2),
                           GridItem(.flexible(), spacing: DS.Space.s2)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: DS.Space.s2) {
            ForEach(Array(cards.enumerated()), id: \.element.source) { i, card in
                Button {
                    DSHaptic.selection()
                    onOpen(card.source)
                } label: {
                    tile(card)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(card.source): \(card.title)")
                .modifier(TileEntrance(index: i, reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s3)
    }

    private func tile(_ card: AgentPanel.Card) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                BridgeIcon(name: card.source, size: 18, circular: false)
                Text(card.title)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            // The figure takes the tile. It is the content, not an accent —
            // the title above is how you know which room you're looking at.
            FigureView(figure: card.figure, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !card.caption.isEmpty {
                Text(card.caption)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(DS.Space.s3)
        .frame(height: 168)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .dsHover()
    }
}

// MARK: - The figures

/// Draws one `AgentPanel.Figure` into whatever space it's given.
///
/// Every figure animates IN from nothing on appear — bars grow, the curve
/// draws, cells fade up in rank order — and all of it collapses to the settled
/// state under Reduce Motion (`design-motion-audit.py`'s first check, which is
/// what makes this a rule rather than an intention).
private struct FigureView: View {
    let figure: AgentPanel.Figure
    let reduceMotion: Bool
    @State private var grown = false

    private var t: Double { grown || reduceMotion ? 1 : 0 }

    var body: some View {
        Group {
            switch figure {
            case .treemap(let cells): treemap(cells)
            case .bars(let bars):     barsView(bars)
            case .rail(let segs):     rail(segs)
            case .pulse(let counts):  pulse(counts)
            case .curve(let values):  curve(values)
            case .wall(let urls):     wall(urls)
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.standard.delay(0.08), value: grown)
        .onAppear { grown = true }
    }

    // Rank-ordered rows of proportional blocks — the `UnitTreemap` grammar at
    // tile scale. Rank-ordered rather than area-proportional for the reason
    // §300 already recorded: true squarified cells arrive as slivers too thin
    // to label, and a label is the only thing that makes a cell mean anything.
    private func treemap(_ cells: [AgentPanel.Cell]) -> some View {
        let total = max(1, cells.reduce(0) { $0 + $1.weight })
        return GeometryReader { geo in
            VStack(spacing: 3) {
                ForEach(Array(cells.prefix(4).enumerated()), id: \.offset) { i, cell in
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
        let shares = AgentPanel.normalized(bars)
        return GeometryReader { geo in
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(bars.prefix(4).enumerated()), id: \.offset) { i, bar in
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
                ForEach(Array(segments.prefix(3).enumerated()), id: \.offset) { _, seg in
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
    }

    /// The tone index stays an Int in the model (Foundation-only) and becomes
    /// a color exactly here — the one place that mapping belongs.
    private func tone(_ index: Int) -> Color {
        switch index {
        case 1:  return Color(hex: "#30d158")
        case 2:  return Color(hex: "#ff453a")
        default: return DS.tint
        }
    }

    /// A contribution wall, trimmed to the tile: the most recent weeks only.
    private func pulse(_ counts: [Int]) -> some View {
        let levels = AgentPanel.levels(counts)
        // Newest-last, so the wall reads left-to-right like every other one.
        let shown = Array(levels.suffix(7 * 12))
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
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let path = Path { p in
                for (i, v) in points.enumerated() {
                    let x = points.count == 1 ? w
                          : w * Double(i) / Double(points.count - 1)
                    // Inset so the extremes aren't clipped by the stroke.
                    let y = h - (h - 4) * v - 2
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            ZStack {
                path.trim(from: 0, to: t)
                    .stroke(rising ? Color(hex: "#30d158") : Color(hex: "#ff453a"),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
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
                .frame(height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .opacity(t)
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
