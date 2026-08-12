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
    private static func bandHeight(for figure: AgentPanel.Figure) -> CGFloat {
        if case .scatter = figure { return 236 }
        return bandHeight
    }

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
                // A map needs vertical room the rails don't — its whole claim
                // is spatial, and at rail height the clusters stack into one
                // stripe.
                tile(band, slot: .band, index: 1 + i)
                    .frame(height: Self.bandHeight(for: band.figure))
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
                        // On a BAND the glyph rides the title, not the well
                        // (§339). Both band figures label their left AND right
                        // edges, top and bottom — there is no free corner, and
                        // moving the badge merely traded a clipped "Uniswap"
                        // for a covered "$600". Beside the heading it has
                        // space of its own and reads as a heading mark.
                        if slot == .band {
                            TileBadge(card: card, hue: hue, size: 16, cornerRadius: 4)
                        }
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
                ZStack {
                    FigureView(figure: card.figure, slot: slot, hue: hue,
                               rising: card.rising, reduceMotion: reduceMotion)
                        .padding(DS.Space.s2)
                    // The glyph sits BOTTOM-trailing on a band (§339): the
                    // sankey and the runway both label their right edge at the
                    // top, and a badge in that corner clipped "Uniswap" to
                    // "Uniswap …" on a real corpus. Corner tiles keep it top —
                    // their figures start below the fold of the well.
                    TileBadge(card: card, hue: hue, size: 18, cornerRadius: 5)
                        .padding(6)
                        .opacity(slot == .band ? 0 : 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topTrailing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.surfaceWell,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                // A caption under a wordless figure is its READING — what the
                // shape means — not chrome. Only where the figure earns one
                // (§339: the dial's busiest window); every other small tile
                // stays wordless.
                if slot != .hero, !card.caption.isEmpty {
                    Text(card.caption)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                }
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

/// The one mark every source tile wears — never the generic "app" grid glyph
/// (spec "Agent panel tiles" item 1, user: "we need to make sure icons are
/// always present when its for a source"). Three layers, checked in order:
///
/// 1. A CROSS-SOURCE card (`card.source == "All"` — the Day Dial, Theme
///    River, Semantic Map) wears a FIGURE glyph on the person's own accent
///    rather than a brand mark, since the corpus these draw is theirs, not
///    any one room's.
/// 2. A real source with a `BridgeGlyph` case wears its symbol on its hue,
///    exactly as before.
/// 3. Anything still falling through to `BridgeGlyph`'s generic `"app"`
///    default wears its own first letter instead — a monogram is a mark,
///    a grid icon is an apology. Precedent: App Store Connect's own glyph is
///    deliberately a letter (`KindGlyph.swift`'s `"character"` case) because
///    the App Store's mark is Apple's trademark and can't be borrowed.
///
/// `BridgeGlyph`'s own default is left untouched — settings' seat chips also
/// read it, and this fallback belongs to the panel alone.
private struct TileBadge: View {
    let card: AgentPanel.Card
    let hue: Color
    let size: CGFloat
    let cornerRadius: CGFloat

    private static func crossSourceSymbol(for figure: AgentPanel.Figure) -> String {
        switch figure {
        case .dial:    return "clock"
        case .river:   return "water.waves"
        case .scatter: return "sparkles"
        case .treemap: return "square.grid.2x2"
        default:       return "circle.grid.2x2"
        }
    }

    var body: some View {
        Group {
            if card.source == "All" {
                // Cross-source, not brand-less — but "all of them at once"
                // has no single identity either, so it takes the same
                // neutral badge an unbranded source would (2026-08-10, was
                // DS.tint).
                IconChip(tone: DS.neutralBadge, size: size, radius: cornerRadius) {
                    Image(systemName: Self.crossSourceSymbol(for: card.figure))
                        .dsGlyph(9, weight: .bold)
                }
            } else {
                let symbol = BridgeGlyph.symbol(for: card.source)
                IconChip(tone: hue, size: size, radius: cornerRadius) {
                    if symbol == "app" {
                        Text(card.source.prefix(1).uppercased())
                            // A letter standing in for a missing brand mark IS
                            // a glyph — same rung as the two symbols either
                            // side of it, so the chip never changes size with
                            // which fallback it drew.
                            .dsGlyph(9, weight: .bold)
                    } else {
                        Image(systemName: symbol)
                            .dsGlyph(9, weight: .bold)
                    }
                }
            }
        }
        .accessibilityHidden(true)
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

    /// The tile's ONE clock, 0 → 1 over the whole entrance (prd §342).
    ///
    /// Replaces the old `grown` Bool. A monotonic Double driven once from
    /// `onAppear` — deliberately NOT `PhaseAnimator`/`KeyframeAnimator`, which
    /// re-run on state-identity changes and both replay on view recycling
    /// inside `List`/`LazyVGrid`. That replay is what got the row sparkline's
    /// draw-on reverted (see `Sparkline`'s own doc); a value that only ever
    /// counts up cannot replay.
    @State private var paint: Double = 0

    /// Maps the master clock onto a sub-interval, clamped 0…1.
    ///
    /// The phase grammar every figure shares — STRUCTURE (0…0.25), DATA
    /// (0.15…0.80), MEANING (0.70…1.0) — because that is the order a hand
    /// draws a chart: the axis, then the data, then the words. The overlap
    /// between structure and data is deliberate; a strict sequence reads
    /// mechanical.
    private func phase(_ from: Double, _ to: Double) -> Double {
        min(1, max(0, (paint - from) / max(0.001, to - from)))
    }

    /// The settled clock, for anything that only cares "is it done".
    private var t: Double { paint }
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
            case .flow(let i, let o):
                FlowFigure(inLanes: i, outLanes: o, hue: hue,
                           spine: phase(0, 0.2), inflow: phase(0.2, 0.6),
                           outflow: phase(0.35, 0.75), words: phase(0.7, 1.0))
            case .dial(let marks):
                DialFigure(marks: marks, slot: slot, ring: phase(0, 0.25),
                           sweep: phase(0.2, 0.85), words: phase(0.85, 1.0),
                           reduceMotion: reduceMotion)
            case .river(let bands):
                RiverFigure(bands: bands, fill: phase(0.05, 0.8), words: phase(0.75, 1.0))
            case .scatter(let d, let c):
                ScatterFigure(dots: d, clusters: c, halos: phase(0, 0.2),
                              drift: phase(0.1, 0.7), words: phase(0.75, 1.0))
            case .runway(let m, let span):
                RunwayFigure(marks: m, span: span, slot: slot,
                             axis: phase(0, 0.25), drop: phase(0.25, 0.75),
                             words: phase(0.8, 1.0))
            case .worth(let values, let cells):
                worth(values, cells)
            }
        }
        .onAppear {
            // A LazyVGrid recycle re-fires `onAppear`; the tiles sit in a plain
            // VStack today, so this is latent rather than live — guarded anyway,
            // because the whole reason `paint` is monotonic is that a replayed
            // entrance is the one failure this design cannot show.
            guard paint == 0 else { return }
            guard !reduceMotion else { paint = 1; return }
            withAnimation(.easeOut(duration: 1.1)) { paint = 1 }
        }
    }

    /// Rank-ordered proportional rows. The LEADER wears real type with its
    /// count beside it and the tail stays quiet (§336) — bar length alone was
    /// throwing away the strongest channel type has.
    private func treemap(_ cells: [AgentPanel.Cell]) -> some View {
        let shown = Array(cells.prefix(rows))
        let total = max(1, shown.reduce(0) { $0 + $1.weight })
        return GeometryReader { geo in
            VStack(spacing: 3) {
                // Symmetric margin reads designed; the old top-align left
                // dead space below a short cell count (spec item 8).
                Spacer(minLength: 0)
                ForEach(Array(shown.enumerated()), id: \.offset) { i, cell in
                    let share = Double(cell.weight) / Double(total)
                    let pillWidth = max(26, geo.size.width * (0.30 + 0.70 * share)
                                          * phase(0.10 + 0.10 * Double(i),
                                                  0.45 + 0.10 * Double(i)))
                    HStack(spacing: 6) {
                        // Saturated fills + bold white text read as tappable
                        // buttons — honesty: they're not, the TILE is the
                        // button (spec item 3). A step down keeps rank
                        // legible without the button read.
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(hue.opacity(0.32 - 0.07 * Double(i)))
                            Text(cell.label)
                                .dsText(i == 0 ? .callout15 : .subhead13)
                                .fontWeight(i == 0 ? .semibold : .regular)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 7)
                        }
                        .frame(width: pillWidth, alignment: .leading)
                        // The count moves OUTSIDE the pill, on every row —
                        // inside, "Orthogonal 310" read as one token and a
                        // tail row with no count looked countless.
                        Text("\(cell.weight)")
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
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
                                // The FIRST row sits under the corner badge —
                                // "4,820" clipped there on the demo corpus
                                // (spec item 7). Shapes survive overlap;
                                // text doesn't, so only text gets the inset.
                                .padding(.trailing, i == 0 && slot != .band ? 22 : 0)
                        }
                        ZStack(alignment: .leading) {
                            // The empty TRACK is structure and lands first, so
                            // the fill reads as filling a track rather than as
                            // a line simply getting longer.
                            Capsule()
                                .fill(DS.fillLine)
                                .frame(width: geo.size.width, height: 4)
                                .opacity(phase(0, 0.25))
                            Capsule()
                                .fill(hue.opacity(i == 0 ? 0.95 : 0.45))
                                .frame(width: max(3, geo.size.width * shares[i]
                                                     * phase(0.15 + 0.08 * Double(i),
                                                             0.55 + 0.08 * Double(i))),
                                       height: 4)
                        }
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
                            .frame(width: max(2, geo.size.width * seg.share * phase(0.15, 0.7)))
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
                        // The word alone hid the number (spec item 5):
                        // "• Pending" with no count beside it.
                        Text("\(seg.count)")
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                            .monospacedDigit()
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
        let reach = Double(weeksShown + 6)
        return HStack(spacing: 2) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { w, week in
                VStack(spacing: 2) {
                    ForEach(Array(week.enumerated()), id: \.offset) { d, level in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(DS.fillLine)
                            .overlay {
                                if level > 0 {
                                    // Live cells take their hue in a DIAGONAL
                                    // sweep, the way a hand shades a grid.
                                    // Deterministic on (week, day): a seeded
                                    // scatter re-rolls identically but reads as
                                    // noise, where a diagonal reads as intent.
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(hue.opacity(0.25 + 0.19 * Double(level)))
                                        .opacity(phase(0.2 + 0.5 * Double(w + d) / reach,
                                                       0.32 + 0.5 * Double(w + d) / reach))
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .opacity(phase(0, 0.3))
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
                    // The fill blooms AFTER the line lands: a stroke that then
                    // gains weight, not a shape that fades up.
                    .opacity(phase(0.72, 1.0))
                }
                line.trim(from: 0, to: phase(0.10, 0.75))
                    .stroke(stroke, style: StrokeStyle(lineWidth: slot == .small ? 2 : 2.5,
                                                       lineCap: .round, lineJoin: .round))
                // THE PEN TIP — a bright nib at the head of the stroke while it
                // draws, gone the instant it settles, so the settled frame is
                // byte-identical to before this change (§342's own rule).
                if paint < 1 {
                    let head = phase(0.10, 0.75)
                    line.trim(from: max(0, head - 0.03), to: head)
                        .stroke(stroke,
                                style: StrokeStyle(lineWidth: (slot == .small ? 2 : 2.5) + 1.5,
                                                   lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    /// Worth beside what it's made of (spec item 2) — the wallet hero's
    /// composite. Reuses `curve()` and `treemap()` untouched: both already
    /// read `phase()`, so the pair choreographs itself with no new clock and
    /// no new struct. A GeometryReader splits the width 58/42 rather than an
    /// even half, since the curve needs more run than four holding rows do.
    private func worth(_ values: [Double], _ cells: [AgentPanel.Cell]) -> some View {
        GeometryReader { geo in
            let gap: CGFloat = DS.Space.s2
            let curveWidth = (geo.size.width - gap) * 0.58
            let mapWidth = (geo.size.width - gap) * 0.42
            HStack(spacing: gap) {
                curve(values).frame(width: curveWidth)
                treemap(cells).frame(width: mapWidth)
            }
        }
    }

    private func wall(_ tiles: [AgentPanel.WallTile]) -> some View {
        let shown = Array(tiles.prefix(4))
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
                                    WallTileImage(tile: shown[i], side: cellW)
                                } else {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(DS.fillLine)
                                }
                            }
                            .frame(width: cellW, height: cellH)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .opacity(phase(0.1 + 0.12 * Double(i), 0.4 + 0.12 * Double(i)))
                            .offset(y: 6 * (1 - phase(0.1 + 0.12 * Double(i),
                                                      0.4 + 0.12 * Double(i))))
                        }
                    }
                }
            }
        }
    }

}

/// One wall cell — real image when it loads, the tile's own LABEL while it
/// doesn't (spec item 4: "a wall is never four gray boxes"). Rides the same
/// `RemoteImageLoader` every other image view in this app uses, NOT a bare
/// `AsyncImage(url:)` — that was the actual bug a real screenshot caught:
/// the demo corpus addresses its bundled photos through a `sample:demo-
/// shot-N` scheme (`DemoSeedAll`, `Design/DemoSampleImage.swift`), which
/// `RemoteImageLoader.load` special-cases in DEBUG to resolve a bundled
/// asset with no network — a plain `AsyncImage` only knows `http(s)`, so it
/// silently sat on the placeholder forever for EVERY demo wall (OpenSea,
/// Pinterest), never a bug in the image, always the loader. `RemoteThumb`
/// (`ShapedRows.swift`) is the pattern this mirrors — same loader, same
/// `.task(id:)` shape — so a wall tile can never disagree with every other
/// thumbnail in the app about whether a URL is reachable.
private struct WallTileImage: View {
    let tile: AgentPanel.WallTile
    let side: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DS.fillLine)
                    .overlay {
                        if !tile.label.isEmpty {
                            Text(tile.label)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(4)
                        }
                    }
            }
        }
        .task(id: tile.url) { await load() }
    }

    private func load() async {
        guard !tile.url.isEmpty else { return }
        if let hit = RemoteImageLoader.cachedImage(urlString: tile.url, targetSide: side * 3) {
            image = hit
            return
        }
        switch await RemoteImageLoader.load(urlString: tile.url, targetSide: side * 3) {
        case .image(let thumb, let fresh):
            if fresh { withAnimation(DS.Motion.standard) { image = thumb } }
            else { image = thumb }
        case .transientFailure, .dead:
            break
        }
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
    /// STRUCTURE — the ring strokes itself from 12 o'clock.
    let ring: Double
    /// DATA — the radar sweep gating each mark by its own hour.
    let sweep: Double
    /// MEANING — the busiest-window caption.
    let words: Double
    let reduceMotion: Bool

    private var showsHours: Bool { slot != .small }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cx = geo.size.width / 2, cy = geo.size.height / 2
            let rMax = side / 2 - (showsHours ? 14 : 3)
            let rMin = rMax * 0.34
            ZStack {
                // The ring DRAWS ITSELF from 12 o'clock — structure before
                // data, the way a hand starts a clock face.
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(DS.fillLine, lineWidth: 1)
                    .rotationEffect(.degrees(-90))
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
                            .opacity(ring)
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
                        // passed its hour, so the figure fills clockwise — and
                        // it FADES rather than pops, which is the difference
                        // between a sweep and a stutter.
                        .opacity(sweep >= mark.hour / 24 ? 0.42 + mark.recency * 0.5 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15),
                                   value: sweep >= mark.hour / 24)
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
    /// DATA — the leading edge sweeping right.
    let fill: Double
    /// MEANING — the legend.
    let words: Double

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
                // A WET EDGE, not a guillotine: the mask's leading front
                // fades over 24pt so the river reads as flowing rather than as
                // a rectangle being dragged across a picture.
                .mask(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().frame(width: max(0, w * fill - 24))
                        LinearGradient(colors: [.black, .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: min(24, w * fill))
                    }
                }
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
                    .opacity(words)
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
    /// STRUCTURE — the neighbourhoods exist before their members arrive.
    let halos: Double
    /// DATA — dots drifting home from the centre.
    let drift: Double
    /// MEANING — the cluster labels.
    let words: Double

    /// Cluster labels with their collisions RESOLVED (§339).
    ///
    /// The first cut positioned each label at a fixed offset below its own
    /// centre and hoped. Two clusters at similar heights printed on top of each
    /// other and the map read as gibberish — "techchstartupsdisrupt" on a real
    /// corpus. Two clusters genuinely CAN sit at the same height, so a fixed
    /// offset can only ever be luck.
    ///
    /// Sorted top-down, then each label is pushed below the previous one until
    /// it clears by `gap`. A label that would leave the figure is DROPPED
    /// rather than drawn overlapping: an unlabelled neighbourhood still shows
    /// its shape, where two labels on top of each other destroy both.
    private static func placed(_ clusters: [AgentPanel.DotCluster],
                               height: CGFloat, py: (Double) -> CGFloat)
        -> [(cluster: AgentPanel.DotCluster, y: CGFloat)] {
        let gap: CGFloat = 17
        var out: [(AgentPanel.DotCluster, CGFloat)] = []
        var lastY: CGFloat = -.greatestFiniteMagnitude
        for cluster in clusters.sorted(by: { $0.y < $1.y }) {
            var y = py(cluster.y) + 20
            if y - lastY < gap { y = lastY + gap }
            guard y <= height - 6 else { continue }
            out.append((cluster, y))
            lastY = y
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let inset: CGFloat = 16
            let px: (Double) -> CGFloat = { inset + CGFloat($0) * max(1, w - inset * 2) }
            let py: (Double) -> CGFloat = { inset + CGFloat($0) * max(1, h - inset * 2) }
            ZStack {
                ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                    let cw = Self.halo(cluster.radius, w - inset * 2)
                    let ch = Self.halo(cluster.radius, h - inset * 2)
                    Circle()
                        .fill(Color.white.opacity(0.028))
                        .frame(width: cw, height: ch)
                        .opacity(halos)
                        .position(x: px(cluster.x), y: py(cluster.y))
                }
                ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                    Circle()
                        .fill(AgentPanelGrid.panelHue(for: dot.source))
                        .frame(width: 4, height: 4)
                        .opacity(0.85 * drift)
                        // Dots drift home from the centre — the picture
                        // assembling itself out of a single point.
                        .position(x: px(dot.x) * drift + (w / 2) * (1 - drift),
                                  y: py(dot.y) * drift + (h / 2) * (1 - drift))
                }
                // Labels ride their own GROUND (§339): white text at 58% over a
                // field of coloured dots is the worst case for legibility, and
                // it read as neither label nor background. An ink pill gives it
                // a floor — the same job the elevation ladder does everywhere
                // else, no line involved.
                ForEach(Array(Self.placed(clusters, height: h, py: py).enumerated()),
                        id: \.offset) { _, placement in
                    Text(placement.cluster.label)
                        .dsText(.subhead13)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.surfaceWell.opacity(0.92),
                                    in: Capsule())
                        .opacity(words)
                        .offset(y: 4 * (1 - words))
                        .position(x: min(w - 30, max(30, px(placement.cluster.x))),
                                  y: placement.y)
                }
            }
        }
    }

    /// A cluster's halo radius, precomputed — an inline `max()` over CGFloat
    /// arithmetic inside a `.frame` inside a `ForEach` inside a GeometryReader
    /// blows up the type-checker, and its error names the whole body.
    private static func halo(_ radius: Double, _ extent: CGFloat) -> CGFloat {
        let scaled = CGFloat(radius) * extent * 2.2
        return scaled < 38 ? 38 : scaled
    }
}

/// A time rail with deadlines on it (prd §338) — Stripe's disputes and dunning,
/// Cloudflare's certificates.
///
/// The one figure that GAINS from a small cell: an axis and some dots need no
/// labels, so at 118pt it says "three things due, one of them nearly here"
/// without a word. `now` is pinned at the left with a tick, and the dots ramp
/// toward the warn colour as they approach it — urgency is state, and state is
/// allowed colour. Overdue pins to the very edge rather than running off it.
private struct RunwayFigure: View {
    let marks: [AgentPanel.RunwayMark]
    let span: String
    let slot: AgentPanel.Slot
    /// STRUCTURE — the axis drawing left to right, then the "now" tick.
    let axis: Double
    /// DATA — deadlines LANDING on the axis.
    let drop: Double
    /// MEANING — the span label.
    let words: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let axisY = h / 2
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(DS.fillLine)
                    .frame(width: w * axis, height: 2)
                    .position(x: w * axis / 2, y: axisY)
                // "Now" — the tick every mark is measured from. Pops at the
                // END of the structure phase, once the axis it sits on exists.
                Capsule()
                    .fill(DS.textTertiary)
                    .frame(width: 2, height: 10)
                    .scaleEffect(axis >= 1 ? 1 : 0)
                    .animation(DS.Motion.bubble, value: axis >= 1)
                    .position(x: 1, y: axisY)
                ForEach(Array(marks.enumerated()), id: \.offset) { i, mark in
                    // Deadlines LAND — scaling down onto the axis rather than
                    // rising out of it. A deadline arrives; it does not grow.
                    let landed = min(1, max(0, (drop - Double(i) * 0.14) / 0.5))
                    Circle()
                        .fill(colour(mark))
                        .frame(width: mark.overdue ? 9 : 7, height: mark.overdue ? 9 : 7)
                        .scaleEffect(1.6 - 0.6 * landed)
                        .opacity(landed)
                        .position(x: max(4, w * mark.position), y: axisY)
                }
                if slot != .small {
                    Text(span)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .position(x: w - 22, y: axisY + 20)
                        .opacity(words)
                }
            }
        }
    }

    private func colour(_ mark: AgentPanel.RunwayMark) -> Color {
        if mark.overdue { return Color(hex: "#ff453a") }
        if mark.urgent  { return Color(hex: "#ffd60a") }
        return DS.tint
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
    /// STRUCTURE — the spine growing from its centre.
    let spine: Double
    /// DATA — inflows, then outflows. Money in before money out, always,
    /// because that is the story a flow tells.
    let inflow: Double
    let outflow: Double
    /// MEANING — the lane labels.
    let words: Double

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
                        height: h, color: Color(hex: "#30d158"), grown: inflow)
                ribbons(spineEdge: spineX + 5, labelEdge: w - labelW, lanes: shownOut,
                        height: h, color: Color(hex: "#ff453a"), grown: outflow)
                Capsule().fill(hue)
                    .frame(width: 4, height: h * 0.84)
                    .scaleEffect(y: spine, anchor: .center)
                    .position(x: spineX, y: h / 2)
                labels(shownIn, x: 0, width: labelW - 8, height: h, alignment: .leading)
                labels(shownOut, x: w - labelW + 8, width: labelW - 8, height: h,
                       alignment: .trailing)
            }
        }
    }

    private func ribbons(spineEdge: CGFloat, labelEdge: CGFloat,
                         lanes: [AgentPanel.FlowLane], height: CGFloat,
                         color: Color, grown: Double) -> some View {
        let slots = max(1, lanes.count)
        return ForEach(Array(lanes.enumerated()), id: \.offset) { i, lane in
            let share = scale > 0 ? lane.usd / scale : 0
            // Capped against the LANE's own share of the height, not the
            // whole band: at three lanes a side, `height * 0.42` let the top
            // ribbon alone cover more than its slot and the three merged into
            // one blob at the spine (seen on the sim). The band's claim is
            // that the sides differ in size — a blob makes exactly that
            // unreadable.
            let slotHeight = height / Double(slots)
            let thickness = max(3, min(slotHeight * 0.72, height * 0.34 * share))
            let laneY = height * (Double(i) + 0.5) / Double(slots)
            // Each lane meets the spine at its OWN y, fanned around the middle
            // (§339). Converging every lane on one midpoint made the ribbons
            // overlap near the centre at any real thickness, and the two green
            // lanes merged into a single mass — the band's one claim is that
            // the sides differ in size, and a blob makes exactly that
            // unreadable. Separation is structural now, not a thickness tune.
            let fan = height * 0.16
            let spineY = height / 2 + (Double(i) - Double(slots - 1) / 2) * fan
            let midX = (spineEdge + labelEdge) / 2
            // Drawn FROM the spine outward, so `trim` grows away from it —
            // the ribbons flow out of the wallet rather than reaching into it.
            Path { p in
                p.move(to: CGPoint(x: spineEdge, y: spineY))
                p.addCurve(to: CGPoint(x: labelEdge, y: laneY),
                           control1: CGPoint(x: midX, y: spineY),
                           control2: CGPoint(x: midX, y: laneY))
            }
            .trim(from: 0, to: grown)
            .stroke(color.opacity(0.42), style: StrokeStyle(lineWidth: thickness, lineCap: .round))
        }
    }

    /// A counterparty label that fits a tile (2026-08-10).
    ///
    /// These lanes name WHO the money moved between — not your own watched
    /// wallets. `WalletFlowSource` resolves a name where it can ("Peer",
    /// "Coinbase", "Uniswap") and falls back to `WalletStore.shortAddress`,
    /// which is already an abbreviation: `0xd889…8de1`. In this figure the
    /// label column is 29% of a tile, so that 13-character form was then
    /// truncated a SECOND time by `lineLimit(1)` into `0xd889…de…` — an
    /// ellipsis inside an ellipsis, naming nobody (reported on-device).
    ///
    /// A real name is left exactly as it is and only ever elided by the
    /// system. A hex fallback drops to its TAIL alone, which is the half that
    /// distinguishes one address from another — a head is `0x` plus whatever
    /// the vanity generator produced, and at this width you can fit one or the
    /// other, not both. Ambiguity is acceptable here and only here: the tile is
    /// a glance, and tapping it opens the Wallet room where the band carries
    /// full addresses.
    private func laneLabel(_ name: String) -> String {
        guard name.hasPrefix("0x"), let tail = name.split(separator: "…").last,
              tail.count <= 8 else { return name }
        return "…\(tail)"
    }

    private func labels(_ lanes: [AgentPanel.FlowLane], x: CGFloat, width: CGFloat,
                        height: CGFloat, alignment: Alignment) -> some View {
        let slots = max(1, lanes.count)
        let slotHeight = height / Double(slots)
        return ForEach(Array(lanes.enumerated()), id: \.offset) { i, lane in
            VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 0) {
                Text(lane.count > 1 ? "\(laneLabel(lane.name)) ×\(lane.count)"
                                    : laneLabel(lane.name))
                    .dsText(.subhead13)
                    .fontWeight(i == 0 ? .semibold : .regular)
                    .foregroundStyle(i == 0 ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Text(compactUSD(lane.usd))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            // BOUNDED to its own slot (2026-08-10). Each block was free to be
            // as tall as its text wanted while `position` only ever fixed its
            // CENTRE, so three two-line blocks in a tile-height figure grew
            // into each other and the name of one lane rendered on top of the
            // amount of the one above it — the reported "numbers are all
            // jumbled". A slot-height frame makes the overlap impossible by
            // construction rather than by choosing type sizes that happen to
            // fit, which is one Dynamic Type step from breaking again.
            .frame(width: width, height: slotHeight, alignment: alignment)
            .position(x: x + width / 2, y: slotHeight * (Double(i) + 0.5))
            .opacity(words)
        }
    }

    private func compactUSD(_ usd: Double) -> String { AgentPanel.compactUSD(usd) }
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
