import SwiftUI

/// The agent's instrument panel (prd §334/§336/§337) — the bento.
///
/// The top-ranked card takes a full-width double-height hero, band-only figures
/// take full-width rows of their own, and the rest fall into a tall cell beside
/// two smalls and then pairs. The pattern is FIXED, never derived from content
/// measurements: a layout that re-derives itself re-shuffles when a figure
/// changes shape, and a panel that rearranges between opens reads as broken
/// long before it reads as fresh.
///
/// **Bento means slots differ in SHAPE, not scale** (§337). A figure routed to
/// a slot it can't hold doesn't shrink gracefully — it clips, collides or turns
/// to mush, and all three render as a perfectly good-looking tile. So
/// `AgentPanel.fit` is a constraint, and every figure below draws DIFFERENTLY
/// per slot rather than being scaled into one.
///
/// Holds no `Thing` — value types in, a source name back on tap.
struct AgentPanelGrid: View {
    let cards: [AgentPanel.Card]
    /// Fires with the card's source — the composer switches the feed to that
    /// room and lowers the agent.
    let onOpen: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let unit: CGFloat = 118
    private static let gutter: CGFloat = DS.Space.s2
    private static var double: CGFloat { unit * 2 + gutter }
    private static let bandHeight: CGFloat = 150

    /// The room's hue, made safe to FILL with against a near-black well.
    ///
    /// `signalColor` solves the inverse problem — a near-black brand mark
    /// needs a lighter glyph — and it hands back a near-WHITE colour for the
    /// brands whose mark is white (ChatGPT, Claude, X). White is fine on an
    /// 18pt glyph and glaring as the fill of a whole figure: ChatGPT's pulse
    /// rendered as a wall of white cells on the sim, brighter than every real
    /// signal on the screen. Above the luminance bar the tint stands in, which
    /// keeps the figure readable and costs only that one room its hue.
    static func panelHue(for source: String) -> Color {
        let brand = BridgeGlyph.signalColor(for: source)
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(brand).getRed(&r, green: &g, blue: &b, alpha: &a) {
            // Rec. 601 luma — the same weighting the contrast pass used.
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            if luma > 0.78 { return DS.tint }
        }
        #endif
        return brand
    }

    var body: some View {
        let bands = cards.filter { AgentPanel.fit($0.figure) == .bandOnly }
        let tiles = cards.filter { AgentPanel.fit($0.figure) != .bandOnly }
        VStack(spacing: Self.gutter) {
            if let hero = tiles.first {
                tile(hero, slot: .hero, index: 0).frame(height: Self.double)
            }
            ForEach(Array(bands.enumerated()), id: \.element.key) { i, band in
                tile(band, slot: .band, index: 1 + i).frame(height: Self.bandHeight)
            }
            let rest = Array(tiles.dropFirst())
            // A `.large` figure can't sit in a small cell — it takes the tall
            // column rather than being crushed into one.
            let tall = rest.first { AgentPanel.fit($0.figure) == .large } ?? rest.first
            let smalls = rest.filter { $0.key != tall?.key }
            if let tall, smalls.count >= 2 {
                HStack(alignment: .top, spacing: Self.gutter) {
                    tile(tall, slot: .tall, index: 1).frame(height: Self.double)
                    VStack(spacing: Self.gutter) {
                        tile(smalls[0], slot: .small, index: 2).frame(height: Self.unit)
                        tile(smalls[1], slot: .small, index: 3).frame(height: Self.unit)
                    }
                }
                pairRows(Array(smalls.dropFirst(2)), startIndex: 4)
            } else {
                pairRows(rest, startIndex: 1)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s3)
    }

    @ViewBuilder
    private func pairRows(_ cards: [AgentPanel.Card], startIndex: Int) -> some View {
        ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { i in
            HStack(alignment: .top, spacing: Self.gutter) {
                tile(cards[i], slot: .small, index: startIndex + i).frame(height: Self.unit)
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
        // HUE IS IDENTITY (§336) — the brand colour the source strip and the
        // seat chips already paint, so a figure says whose room it is before a
        // word is read. Design law permits colour for identity; `signalColor`
        // is the variant that survives a near-black tile hue.
        let hue = Self.panelHue(for: card.source)
        return Button {
            DSHaptic.selection()
            onOpen(card.source)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // The hero carries ONE reading — the room's own sentence about
                // itself, in the largest type on the tile. Every other slot is
                // wordless: the figure is the content and the corner glyph says
                // whose it is, which is what buys a small cell back the quarter
                // of its height the old header row ate (§336).
                if slot == .hero, let reading = card.reading {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text(reading)
                            .dsText(.heading22)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if !card.caption.isEmpty {
                            Text(card.caption)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 2)
                } else if slot == .hero || slot == .band {
                    HStack(spacing: DS.Space.s2) {
                        Text(card.title)
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 2)
                }

                // The figure sits in a WELL — the elevation ladder's recess, a
                // tonal step below the card, so charts read as instruments set
                // INTO the panel rather than shapes floating on it. That is the
                // job a border would do in a system that allowed them; §8
                // forbids lines, so tone does it.
                ZStack(alignment: .topTrailing) {
                    FigureView(figure: card.figure, slot: slot, hue: hue,
                               rising: card.rising, reduceMotion: reduceMotion)
                        .padding(DS.Space.s2)
                    Image(systemName: BridgeGlyph.symbol(for: card.source))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(hue, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(6)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.surfaceWell,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .padding(DS.Space.s2 + 1)
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

/// Draws one `AgentPanel.Figure`, sized AND shaped to its slot.
///
/// Each shape enters with its own physics (§336) rather than one shared fade:
/// treemap rows wipe, bars grow, the curve draws tip-first and its fill blooms
/// after, dial marks sweep in clockwise, the river fills left to right, scatter
/// dots drift home from the centre. All appear-triggered, all collapsing to the
/// settled state under Reduce Motion — and none of them loop: `repeatForever`
/// is what the motion audit flagged on `GenTagMap`, so these settle and go still.
private struct FigureView: View {
    let figure: AgentPanel.Figure
    let slot: AgentPanel.Slot
    let hue: Color
    let rising: Bool?
    let reduceMotion: Bool
    @State private var grown = false

    private var t: Double { grown || reduceMotion ? 1 : 0 }
    /// How many entries a slot has room for — measured against the 118pt small
    /// cell, not guessed: three bar rows at their own spacing overflow it, and
    /// an overflowing figure clips silently.
    private var rows: Int {
        switch slot {
        case .small: return 2
        // The tall cell is HALF width — four named rows there crush the names
        // even with the label freed from the bar. Three fit.
        case .tall:  return 3
        default:     return 4
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
            case .flow(let i, let o): FlowFigure(inLanes: i, outLanes: o, hue: hue, t: t)
            case .dial(let marks):    DialFigure(marks: marks, slot: slot, t: t)
            case .river(let bands):   RiverFigure(bands: bands, t: t)
            case .scatter(let d, let c): ScatterFigure(dots: d, clusters: c, t: t)
            }
        }
        .animation(reduceMotion ? nil : DS.Motion.standard.delay(0.08), value: grown)
        .onAppear { grown = true }
    }

    /// Rank-ordered proportional rows. The LEADER wears real type with its
    /// count beside it and the tail stays quiet (§336) — bar length alone was
    /// throwing away the strongest channel type has.
    private func treemap(_ cells: [AgentPanel.Cell]) -> some View {
        let shown = Array(cells.prefix(rows))
        let total = max(1, shown.reduce(0) { $0 + $1.weight })
        return GeometryReader { geo in
            VStack(spacing: 3) {
                ForEach(Array(shown.enumerated()), id: \.offset) { i, cell in
                    let share = Double(cell.weight) / Double(total)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(hue.opacity(0.44 - 0.09 * Double(i)))
                            .frame(width: max(26, geo.size.width * (0.30 + 0.70 * share) * t))
                        HStack(spacing: 5) {
                            Text(cell.label)
                                .dsText(i == 0 ? .callout15 : .subhead13)
                                .fontWeight(i == 0 ? .semibold : .regular)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if i == 0 {
                                Text("\(cell.weight)")
                                    .dsText(.subhead13)
                                    .foregroundStyle(DS.textPrimary.opacity(0.7))
                                    .monospacedDigit()
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 7)
                    }
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
                Spacer(minLength: 0)
                ForEach(Array(shown.enumerated()), id: \.offset) { i, bar in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(bar.label)
                                .dsText(.subhead13)
                                .fontWeight(i == 0 ? .semibold : .regular)
                                .foregroundStyle(i == 0 ? DS.textPrimary : DS.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(bar.detail)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                                .monospacedDigit()
                        }
                        Capsule()
                            .fill(hue.opacity(i == 0 ? 0.95 : 0.45))
                            .frame(width: max(3, geo.size.width * shares[i] * t), height: 4)
                    }
                }
                Spacer(minLength: 0)
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

    /// Tone is STATE, so it keeps its own colours rather than the room's hue —
    /// the one place identity yields to meaning.
    private func tone(_ index: Int) -> Color {
        switch index {
        case 1:  return Color(hex: "#30d158")
        case 2:  return Color(hex: "#ff453a")
        default: return hue
        }
    }

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
                            .fill(level == 0 ? DS.fillLine : hue.opacity(0.25 + 0.19 * Double(level)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .opacity(t)
    }

    private func curve(_ values: [Double]) -> some View {
        let points = AgentPanel.normalized(values)
        // Direction is STATE — green/red — and a flat series gets neither
        // (§83: a change that rounds to zero has no direction).
        let stroke: Color = {
            guard let rising else { return hue }
            return rising ? Color(hex: "#30d158") : Color(hex: "#ff453a")
        }()
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
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
                if slot != .small, let first = points.first {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h))
                        p.addLine(to: at(0, first))
                        for (i, v) in points.enumerated().dropFirst() { p.addLine(to: at(i, v)) }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [stroke.opacity(0.24), stroke.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(t)
                }
                line.trim(from: 0, to: t)
                    .stroke(stroke, style: StrokeStyle(lineWidth: slot == .small ? 2 : 2.5,
                                                       lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func wall(_ urls: [String]) -> some View {
        let shown = Array(urls.prefix(4))
        return GeometryReader { geo in
            let gap: CGFloat = 3
            let cellH = max(18, (geo.size.height - gap) / 2)
            let cellW = max(18, (geo.size.width - gap) / 2)
            VStack(spacing: gap) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<2, id: \.self) { col in
                            let i = row * 2 + col
                            Group {
                                if i < shown.count {
                                    AsyncImage(url: URL(string: shown[i])) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(DS.fillLine)
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(DS.fillLine)
                                }
                            }
                            .frame(width: cellW, height: cellH)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                }
            }
        }
        .opacity(t)
    }
}

// MARK: - 1 · The day dial

/// A week of things on a 24-hour clock (prd §337).
///
/// The one new figure that holds at EVERY slot: radially symmetric, no labels
/// to clip, hue carrying identity, and the shape itself is the reading. At the
/// small cell it drops the hour anchors and keeps the marks — a bare
/// constellation still says "evenings" at a glance.
private struct DialFigure: View {
    let marks: [AgentPanel.DialMark]
    let slot: AgentPanel.Slot
    let t: Double

    private var showsHours: Bool { slot != .small }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cx = geo.size.width / 2, cy = geo.size.height / 2
            let rMax = side / 2 - (showsHours ? 14 : 3)
            let rMin = rMax * 0.34
            ZStack {
                Circle()
                    .stroke(DS.fillLine, lineWidth: 1)
                    .frame(width: rMax * 2, height: rMax * 2)
                    .position(x: cx, y: cy)
                if showsHours {
                    // Six-hour anchors only — 24 ticks at tile scale is a
                    // dotted ring that reads as texture, not as a clock.
                    ForEach([0, 6, 12, 18], id: \.self) { h in
                        let a = Self.angle(Double(h))
                        Text(Self.hourLabel(h))
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                            .position(x: cx + cos(a) * (rMax + 10),
                                      y: cy + sin(a) * (rMax + 10))
                    }
                }
                ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                    let a = Self.angle(mark.hour)
                    let r = rMin + (rMax - rMin) * pow(mark.recency, 0.8)
                    Circle()
                        .fill(AgentPanelGrid.panelHue(for: mark.source))
                        .frame(width: 3.4, height: 3.4)
                        // The radar sweep: a mark appears once the hand has
                        // passed its hour, so the figure fills clockwise.
                        .opacity(t >= mark.hour / 24 ? 0.42 + mark.recency * 0.5 : 0)
                        .position(x: cx + cos(a) * r, y: cy + sin(a) * r)
                }
            }
        }
    }

    /// Midnight at the top, clockwise — a clock face, which is the mental model
    /// the figure is borrowing.
    private static func angle(_ hour: Double) -> Double {
        (hour / 24) * 2 * .pi - .pi / 2
    }

    private static func hourLabel(_ h: Int) -> String {
        switch h {
        case 0:  return "12a"
        case 6:  return "6a"
        case 12: return "12p"
        default: return "6p"
        }
    }
}

// MARK: - 2 · The theme river

/// Themes as flowing bands over the weeks (prd §337) — attention as movement.
/// Band-only: ten weeks need horizontal run, and at half width the stream
/// collapses into a smear.
private struct RiverFigure: View {
    let bands: [AgentPanel.RiverBand]
    let t: Double

    /// Fixed hues assigned by RANK, not by room — a theme spans rooms by
    /// definition. Stable across opens because `river` returns a totally
    /// ordered list.
    private static let palette = ["#4a9eff", "#b06bff", "#33c48d", "#f2a33c", "#ff7a9c"]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let weeks = bands.first?.weeks.count ?? 0
            if weeks >= 2 {
                let totals = (0..<weeks).map { i in bands.reduce(0) { $0 + $1.weeks[i] } }
                let peak = max(1, totals.max() ?? 1)
                let scale = (h * 0.80) / Double(peak)
                let x: (Int) -> Double = { w * Double($0) / Double(weeks - 1) }
                ZStack {
                    ForEach(Array(bands.enumerated()), id: \.offset) { bi, band in
                        Path { p in
                            var tops: [Double] = [], bots: [Double] = []
                            for i in 0..<weeks {
                                var below = 0
                                for j in 0..<bi { below += bands[j].weeks[i] }
                                let top = h / 2 - Double(totals[i]) * scale / 2
                                    + Double(below) * scale
                                tops.append(top)
                                bots.append(top + Double(band.weeks[i]) * scale)
                            }
                            p.move(to: CGPoint(x: x(0), y: tops[0]))
                            for i in 1..<weeks {
                                let xm = (x(i - 1) + x(i)) / 2
                                p.addCurve(to: CGPoint(x: x(i), y: tops[i]),
                                           control1: CGPoint(x: xm, y: tops[i - 1]),
                                           control2: CGPoint(x: xm, y: tops[i]))
                            }
                            p.addLine(to: CGPoint(x: x(weeks - 1), y: bots[weeks - 1]))
                            for i in stride(from: weeks - 2, through: 0, by: -1) {
                                let xm = (x(i + 1) + x(i)) / 2
                                p.addCurve(to: CGPoint(x: x(i), y: bots[i]),
                                           control1: CGPoint(x: xm, y: bots[i + 1]),
                                           control2: CGPoint(x: xm, y: bots[i]))
                            }
                            p.closeSubpath()
                        }
                        .fill(Color(hex: Self.palette[bi % Self.palette.count]).opacity(0.8))
                    }
                }
                // Fills left to right — a MASK, so the bands keep their shape
                // instead of stretching into it.
                .mask(alignment: .leading) { Rectangle().frame(width: w * t) }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 9) {
                        ForEach(Array(bands.prefix(3).enumerated()), id: \.offset) { i, band in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: Self.palette[i % Self.palette.count]))
                                    .frame(width: 6, height: 6)
                                Text(band.label)
                                    .dsText(.subhead13)
                                    .foregroundStyle(DS.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .opacity(t)
                }
            }
        }
    }
}

// MARK: - 3 · The semantic map

/// The corpus arranged by meaning (prd §337).
///
/// Every dot is a real thing at its projected position; every label is a term
/// the neighbourhood actually shares. **The map asserts nothing** — which is
/// what separates it from the connection card §333 deleted, where a shared word
/// became a sentence. Here the reader draws the conclusion, and a cluster
/// holding several hues is a cross-source theme made visible.
private struct ScatterFigure: View {
    let dots: [AgentPanel.Dot]
    let clusters: [AgentPanel.DotCluster]
    let t: Double

    /// A cluster's halo radius, precomputed — see the inline note above.
    private static func halo(_ radius: Double, _ extent: CGFloat) -> CGFloat {
        let scaled = CGFloat(radius) * extent * 2.2
        return scaled < 38 ? 38 : scaled
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let inset: CGFloat = 16
            let px: (Double) -> CGFloat = { inset + CGFloat($0) * max(1, w - inset * 2) }
            let py: (Double) -> CGFloat = { inset + CGFloat($0) * max(1, h - inset * 2) }
            ZStack {
                ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                    let cw: CGFloat = Self.halo(cluster.radius, w - inset * 2)
                    let ch: CGFloat = Self.halo(cluster.radius, h - inset * 2)
                    Circle()
                        .fill(Color.white.opacity(0.028))
                        .frame(width: cw, height: ch)
                        .position(x: px(cluster.x), y: py(cluster.y))
                }
                ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                    Circle()
                        .fill(AgentPanelGrid.panelHue(for: dot.source))
                        .frame(width: 4, height: 4)
                        .opacity(0.85 * t)
                        // Dots drift home from the centre — the picture
                        // assembling itself out of a single point.
                        .position(x: px(dot.x) * t + (w / 2) * (1 - t),
                                  y: py(dot.y) * t + (h / 2) * (1 - t))
                }
                ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                    Text(cluster.label)
                        .dsText(.subhead13)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                        .opacity(t)
                        .position(x: px(cluster.x),
                                  y: min(h - 8, py(cluster.y) + 22))
                }
            }
        }
    }
}

// MARK: - The sankey

/// The panel's flow band — a REDUCTION of `WalletFlowBand`, not a copy: same
/// one-scale rule (both sides share `max(in, out)`, or a $200 outflow week
/// draws as wide as a $20,000 inflow week), three lanes a side, no chips.
/// Direction is state, so the ribbons take green/red while the spine keeps the
/// room's hue.
private struct FlowFigure: View {
    let inLanes: [AgentPanel.FlowLane]
    let outLanes: [AgentPanel.FlowLane]
    let hue: Color
    let t: Double

    private var shownIn: [AgentPanel.FlowLane] { Array(inLanes.prefix(3)) }
    private var shownOut: [AgentPanel.FlowLane] { Array(outLanes.prefix(3)) }
    private var scale: Double {
        max(shownIn.reduce(0) { $0 + $1.usd }, shownOut.reduce(0) { $0 + $1.usd })
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let labelW = w * 0.29
            let spineX = w / 2
            ZStack {
                ribbons(spineEdge: spineX - 5, labelEdge: labelW, lanes: shownIn,
                        height: h, color: Color(hex: "#30d158"))
                ribbons(spineEdge: spineX + 5, labelEdge: w - labelW, lanes: shownOut,
                        height: h, color: Color(hex: "#ff453a"))
                Capsule().fill(hue)
                    .frame(width: 4, height: h * 0.84)
                    .position(x: spineX, y: h / 2)
                labels(shownIn, x: 0, width: labelW - 8, height: h, alignment: .leading)
                labels(shownOut, x: w - labelW + 8, width: labelW - 8, height: h,
                       alignment: .trailing)
            }
        }
    }

    private func ribbons(spineEdge: CGFloat, labelEdge: CGFloat,
                         lanes: [AgentPanel.FlowLane], height: CGFloat,
                         color: Color) -> some View {
        let slots = max(1, lanes.count)
        return ForEach(Array(lanes.enumerated()), id: \.offset) { i, lane in
            let share = scale > 0 ? lane.usd / scale : 0
            let thickness = max(3, height * 0.42 * share)
            let laneY = height * (Double(i) + 0.5) / Double(slots)
            let midX = (spineEdge + labelEdge) / 2
            Path { p in
                p.move(to: CGPoint(x: labelEdge, y: laneY))
                p.addCurve(to: CGPoint(x: spineEdge, y: height / 2),
                           control1: CGPoint(x: midX, y: laneY),
                           control2: CGPoint(x: midX, y: height / 2))
            }
            .trim(from: 0, to: t)
            .stroke(color.opacity(0.42), style: StrokeStyle(lineWidth: thickness, lineCap: .round))
        }
    }

    private func labels(_ lanes: [AgentPanel.FlowLane], x: CGFloat, width: CGFloat,
                        height: CGFloat, alignment: Alignment) -> some View {
        let slots = max(1, lanes.count)
        return ForEach(Array(lanes.enumerated()), id: \.offset) { i, lane in
            VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 0) {
                Text(lane.count > 1 ? "\(lane.name) ×\(lane.count)" : lane.name)
                    .dsText(.subhead13)
                    .fontWeight(i == 0 ? .semibold : .regular)
                    .foregroundStyle(i == 0 ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
                Text(compactUSD(lane.usd))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
            }
            .frame(width: width, alignment: alignment)
            .position(x: x + width / 2, y: height * (Double(i) + 0.5) / Double(slots))
            .opacity(t)
        }
    }

    private func compactUSD(_ usd: Double) -> String {
        usd >= 1000 ? String(format: "$%.1fk", usd / 1000) : String(format: "$%.0f", usd)
    }
}

/// One tile's staggered rise. Honours Reduce Motion — the audit's first check,
/// and appear-triggered by construction.
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
