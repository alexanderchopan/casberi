import SwiftUI

/// **AN EMPTY PLACE DRAWS WHAT WOULD FILL IT, EMPTY (prd §769, 2026-09-15,
/// user: "we need to do a better job on empty states for wallet screens in
/// the slot and in the list", then "i would expect to see empty skeleton
/// charts").**
///
/// §611 made an empty scope say what it would hold in a paragraph, and on a
/// device that was a heading and three lines at the top of a 300pt box with
/// the rest black, over a list that drew nothing. The box now draws the
/// scope's own figure as a still grey skeleton with its short state centred
/// on it, and the list under the tiles draws skeleton rows.
///
/// **Static, always.** No shimmer and no pulse: a moving skeleton is the
/// platform's "loading", and these say "empty" (§83). The paragraph is not
/// deleted — it is the VoiceOver value, so the scope still explains itself to
/// someone who cannot see the drawing.
///
/// **ONE FIGURE PER SCOPE NAME**, keyed on `ScopeTileGlyph` for that table's
/// reason: a scope called Holdings is the same drawing in every room.
enum DSSkeleton {
    enum Figure: Equatable {
        /// A balance, its line and the range chips — Home's crown.
        case line
        /// Bars over days — the family's activity chart.
        case bars
        /// The holdings treemap.
        case treemap
        /// The connections map.
        case graph
        /// The composition strip and its legend.
        case strip
        /// The NFT quad.
        case quad
        /// Ranked bars against a threshold.
        case ranked
        /// Holders ranked by reach.
        case holders
        /// Framed transactions, a row of steps each.
        case steps
        /// The UTXO grid.
        case grid
        /// The snapshot rings.
        case ring

        init(glyph: String) {
            switch glyph {
            case ScopeTileGlyph.home:        self = .line
            case ScopeTileGlyph.activity:    self = .bars
            case ScopeTileGlyph.holdings:    self = .treemap
            case ScopeTileGlyph.accounts:    self = .graph
            case ScopeTileGlyph.positions:   self = .strip
            case ScopeTileGlyph.nfts:        self = .quad
            case ScopeTileGlyph.permissions: self = .holders
            case ScopeTileGlyph.frames:      self = .steps
            case ScopeTileGlyph.utxos:       self = .grid
            case ScopeTileGlyph.snapshots:   self = .ring
            default:                         self = .ranked
            }
        }
    }

    /// The shape's fill, its track, and its one accent — three existing fill
    /// tokens, so light and dark both come from the ramp.
    static let shape = DS.fillLine
    static let track = DS.fillFaint
    static let accent = DS.fillStrong
}

extension DSTileScope {
    /// The drawing this scope's empty state stands on.
    var skeleton: DSSkeleton.Figure { DSSkeleton.Figure(glyph: glyph) }
}

/// A scope's figure, drawn empty. One `Canvas`, no layout of its own: it
/// fills what it is offered, in a 300×264 design space scaled to fit.
struct DSSkeletonFigure: View {
    let figure: DSSkeleton.Figure

    var body: some View {
        Canvas { ctx, size in
            Self.draw(figure, in: &ctx, size: size)
        }
        .accessibilityHidden(true)
    }

    private static let design = CGSize(width: 300, height: 264)

    private static func draw(_ figure: DSSkeleton.Figure, in ctx: inout GraphicsContext, size: CGSize) {
        let sx = size.width / design.width, sy = size.height / design.height
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy)
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                 radius: CGFloat = 8, _ color: Color = DSSkeleton.shape) {
            ctx.fill(Path(roundedRect: rect(x, y, w, h), cornerRadius: radius, style: .continuous),
                     with: .color(color))
        }
        func pill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 8,
                  _ color: Color = DSSkeleton.shape) {
            let r = rect(x, y, w, h)
            ctx.fill(Path(roundedRect: r, cornerRadius: r.height / 2, style: .continuous),
                     with: .color(color))
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: Color = DSSkeleton.shape) {
            let r = radius * min(sx, sy)
            ctx.fill(Path(ellipseIn: CGRect(x: x * sx - r, y: y * sy - r, width: 2 * r, height: 2 * r)),
                     with: .color(color))
        }
        func dashed(_ points: [(CGFloat, CGFloat)]) {
            var path = Path()
            for pair in stride(from: 0, to: points.count - 1, by: 2) {
                path.move(to: CGPoint(x: points[pair].0 * sx, y: points[pair].1 * sy))
                path.addLine(to: CGPoint(x: points[pair + 1].0 * sx, y: points[pair + 1].1 * sy))
            }
            ctx.stroke(path, with: .color(DSSkeleton.accent),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }

        switch figure {
        case .line:
            pill(0, 4, 110, 22)
            pill(0, 36, 70)
            var curve = Path()
            curve.move(to: CGPoint(x: 0, y: 200 * sy))
            curve.addCurve(to: CGPoint(x: 95 * sx, y: 175 * sy),
                           control1: CGPoint(x: 40 * sx, y: 190 * sy),
                           control2: CGPoint(x: 60 * sx, y: 165 * sy))
            curve.addCurve(to: CGPoint(x: 185 * sx, y: 145 * sy),
                           control1: CGPoint(x: 130 * sx, y: 185 * sy),
                           control2: CGPoint(x: 150 * sx, y: 135 * sy))
            curve.addCurve(to: CGPoint(x: 300 * sx, y: 106 * sy),
                           control1: CGPoint(x: 220 * sx, y: 155 * sy),
                           control2: CGPoint(x: 245 * sx, y: 100 * sy))
            var area = curve
            area.addLine(to: CGPoint(x: 300 * sx, y: 220 * sy))
            area.addLine(to: CGPoint(x: 0, y: 220 * sy))
            area.closeSubpath()
            ctx.fill(area, with: .color(DSSkeleton.track))
            ctx.stroke(curve, with: .color(DSSkeleton.accent),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            for i in 0..<6 { pill(CGFloat(i) * 52, 240, 44, 22) }
        case .bars:
            let heights: [CGFloat] = [40, 70, 55, 95, 60, 120, 85, 45, 105, 75, 130, 90, 60, 110]
            for (i, h) in heights.enumerated() {
                box(CGFloat(i) * 21.6 + 3, 230 - h * 1.2, 15, h * 1.2, radius: 4)
            }
            for i in 0..<7 { pill(CGFloat(i) * 43 + 6, 248, 24, 6) }
        case .treemap:
            box(0, 0, 172, 264)
            box(180, 0, 120, 150)
            box(180, 158, 58, 106)
            box(246, 158, 54, 106)
        case .graph:
            dashed([(60, 132), (240, 132), (60, 132), (150, 40), (240, 132), (150, 40),
                    (60, 132), (150, 224), (240, 132), (150, 224)])
            // The discs sit ON the lines, so the lines are cut out under them
            // rather than showing through a translucent fill.
            for (x, y, r) in [(60.0, 132.0, 30.0), (240, 132, 30), (150, 40, 22), (150, 224, 22)] {
                let rr = CGFloat(r) * min(sx, sy)
                let disc = Path(ellipseIn: CGRect(x: CGFloat(x) * sx - rr, y: CGFloat(y) * sy - rr,
                                                  width: 2 * rr, height: 2 * rr))
                ctx.blendMode = .clear
                ctx.fill(disc, with: .color(.black))
                ctx.blendMode = .normal
                ctx.fill(disc, with: .color(DSSkeleton.shape))
            }
        case .strip:
            pill(0, 60, 90, 18)
            pill(0, 100, 150, 28, DSSkeleton.accent)
            pill(154, 100, 90, 28)
            pill(248, 100, 52, 28, DSSkeleton.track)
            for i in 0..<3 {
                dot(6 + CGFloat(i) * 90, 156, 4, DSSkeleton.accent)
                pill(16 + CGFloat(i) * 90, 152, 54)
            }
        case .quad:
            box(0, 0, 146, 128, radius: 12)
            box(154, 0, 146, 128, radius: 12)
            box(0, 136, 146, 128, radius: 12)
            box(154, 136, 146, 128, radius: 12)
        case .ranked:
            for (i, w) in [210.0, 150, 260, 110].enumerated() {
                let y = CGFloat(i) * 62
                pill(0, 14 + y, 80)
                pill(0, 30 + y, 300, 14, DSSkeleton.track)
                pill(0, 30 + y, CGFloat(w), 14)
            }
            dashed([(225, 8), (225, 250)])
        case .holders:
            for (i, w) in [262.0, 190, 120, 70, 30].enumerated() {
                let y = CGFloat(i) * 52
                dot(14, 26 + y, 13)
                pill(38, 16 + y, 120)
                pill(38, 34 + y, 262, 10, DSSkeleton.track)
                pill(38, 34 + y, CGFloat(w), 10)
            }
        case .steps:
            let rows: [[CGFloat]] = [[70, 110, 60], [140, 50, 45, 30], [90, 90], [60, 60, 60, 80]]
            for (i, widths) in rows.enumerated() {
                var x: CGFloat = 0
                for w in widths {
                    box(x, 10 + CGFloat(i) * 64, w, 44, radius: 10)
                    x += w + 8
                }
            }
        case .grid:
            for row in 0..<5 {
                for col in 0..<6 {
                    dot(25 + CGFloat(col) * 50, 26 + CGFloat(row) * 53, 16)
                }
            }
        case .ring:
            for (radius, trim) in [(100.0, 0.72), (64, 0.45)] {
                let r = CGFloat(radius) * min(sx, sy)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                var track = Path()
                track.addArc(center: center, radius: r, startAngle: .degrees(0),
                             endAngle: .degrees(360), clockwise: false)
                ctx.stroke(track, with: .color(DSSkeleton.track), lineWidth: 14 * min(sx, sy))
                var arc = Path()
                arc.addArc(center: center, radius: r, startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * trim), clockwise: false)
                ctx.stroke(arc, with: .color(DSSkeleton.shape),
                           style: StrokeStyle(lineWidth: 14 * min(sx, sy), lineCap: .round))
            }
        }
    }
}

/// The list under an empty scope: rows in the feed row's anatomy — the 26pt
/// lead, a title, its line, the trailing fact — with nothing in them.
struct DSSkeletonRows: View {
    var count: Int = 3
    /// What VoiceOver reads for the empty list. Nil where the lead above
    /// already says it, so the state is announced once.
    var label: Text? = nil

    private static let widths: [(CGFloat, CGFloat)] = [(120, 80), (90, 110), (140, 70)]

    var body: some View {
        if let label {
            rows.accessibilityElement(children: .ignore).accessibilityLabel(label)
        } else {
            rows.accessibilityHidden(true)
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let w = Self.widths[i % Self.widths.count]
                HStack(spacing: DS.Space.s3) {
                    Circle()
                        .fill(DSSkeleton.shape)
                        .frame(width: DS.Face.row, height: DS.Face.row)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(DSSkeleton.shape).frame(width: w.0, height: 10)
                        Capsule().fill(DSSkeleton.track).frame(width: w.1, height: 7)
                    }
                    Spacer(minLength: 0)
                    Capsule().fill(DSSkeleton.shape).frame(width: 34, height: 10)
                }
                .padding(.vertical, DS.Space.s2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}
