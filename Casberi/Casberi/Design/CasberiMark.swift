import SwiftUI

/// The Casberi mark — one octopus arm curled into a lowercase c, in vectors,
/// scalable to any size (2026-11-01; the five-armed leaning octopus before it
/// stays as the website's illustration, `docs/brand.md`).
///
/// Geometry is `design/app-icon/tentacle.py`'s, ported line for line rather
/// than re-derived: the arm's centreline is a circle of radius 27 about
/// (50, 50) walked from −48° through 282°, its radius shrinking by 9 past 73%
/// of the walk so the tip turns in, its width tapering from root to tip, and
/// the whole arm leaning −9° about (50, 50) — the angle the octopus's head
/// leaned. Change one file, change the other.
///
/// Colors live here in the design layer (§8 — components hold zero raw hex).
/// The suckers are drawn in the GROUND color, not a dark ink, so they read as
/// holes punched through the arm the way the artwork intends.
struct CasberiMark: View {
    var size: CGFloat = 20

    /// Below this, the suckers are dropped and the tip blunts (the clean cut).
    ///
    /// The octopus's handoff put this boundary at 60 and it was followed
    /// literally at first, which took the small cut all the way down to the
    /// FAB. Wrong, and settled by evidence: the full mark was set as an avatar
    /// on a real device at roughly FAB size and read fine, because a detail
    /// punched in the ground colour against solid ink is the highest contrast
    /// a small detail can have, and @3x gives it the pixels. The arm's suckers
    /// are solid discs, larger than the octopus's rings were, so the same
    /// boundary holds for them with room to spare.
    static let smallCutBelow: CGFloat = 16

    private var full: Bool { size >= Self.smallCutBelow }

    /// The brand hue, and the only one. Lives in the token layer now
    /// (`DS.brand`) because the feed's day dividers took the same hue
    /// (prd §740) and two spellings of one hex is one hex too many.
    static let pink = DS.brand
    /// Whatever the mark is standing on — black in dark, white in light. The
    /// suckers are this, so they punch rather than print.
    private var ground: Color { Color.adaptive(dark: "#000000", light: "#ffffff") }

    var body: some View {
        Canvas { ctx, canvas in
            let s = min(canvas.width, canvas.height) / 100
            let scale = CGAffineTransform(scaleX: s, y: s)
            let arm = full ? Self.fullCut : Self.cleanCut
            ctx.fill(arm.body.applying(scale), with: .color(Self.pink))
            for k in arm.suckers {
                let r = CGRect(x: k.x - k.r, y: k.y - k.r, width: k.r * 2, height: k.r * 2)
                ctx.fill(Path(ellipseIn: r).applying(scale), with: .color(ground))
            }
        }
        .frame(width: size, height: size)
        // The app's own logo — decoration on every one of its call sites (the
        // agent bar, the launch chrome, the account tile), never a fact. This
        // is the class the 2026-08-13 sweep hid forty of; the mark itself was
        // missed because it draws in a `Canvas` rather than as an `Image`.
        .accessibilityHidden(true)
    }

    // MARK: - the artwork, in unit space

    struct Cut {
        /// One closed contour, round-capped at both ends, already leaned.
        let body: Path
        /// The bounding box of `body`, for callers that crop to the arm.
        let box: CGRect
        let suckers: [(x: CGFloat, y: CGFloat, r: CGFloat)]
    }

    /// Six suckers, graduated big→small toward the tip.
    static let fullCut = cut(w0: 17, w1: 4, power: 0.9,
                             suckers: [(10, 3.0), (22, 2.7), (34, 2.4), (46, 2.0), (56, 1.7), (65, 1.3)])
    /// No suckers and a blunter tip — under `smallCutBelow`, and the wordmark's c.
    static let cleanCut = cut(w0: 18, w1: 7, power: 1.0, suckers: [])

    private static func cut(w0: CGFloat, w1: CGFloat, power: CGFloat,
                            suckers: [(Int, CGFloat)]) -> Cut {
        let cx: CGFloat = 50, cy: CGFloat = 50, n = 80

        // the centreline, sampled finely, then resampled to n equal steps
        var fine: [CGPoint] = []
        for k in 0...400 {
            let u = CGFloat(k) / 400
            let th = (-48 - 282 * u) * .pi / 180
            let r: CGFloat = u < 0.73 ? 27 : 27 - 9 * pow((u - 0.73) / 0.27, 1.4)
            fine.append(CGPoint(x: cx + r * cos(th), y: cy + r * sin(th)))
        }
        var acc: [CGFloat] = [0]
        for i in 1..<fine.count { acc.append(acc[i - 1] + hypot(fine[i].x - fine[i - 1].x, fine[i].y - fine[i - 1].y)) }
        var c: [CGPoint] = []
        var j = 0
        for i in 0...n {
            let s = acc[acc.count - 1] * CGFloat(i) / CGFloat(n)
            while j < acc.count - 2 && acc[j + 1] < s { j += 1 }
            let span = acc[j + 1] - acc[j]
            let t = span > 0 ? (s - acc[j]) / span : 0
            c.append(CGPoint(x: fine[j].x + (fine[j + 1].x - fine[j].x) * t,
                             y: fine[j].y + (fine[j + 1].y - fine[j].y) * t))
        }

        func width(_ i: Int) -> CGFloat { w0 + (w1 - w0) * pow(CGFloat(i) / CGFloat(n), power) }
        var left: [CGPoint] = [], right: [CGPoint] = []
        var frames: [(t: CGVector, n: CGVector)] = []
        for i in 0...n {
            let a = c[max(i - 1, 0)], b = c[min(i + 1, n)]
            let d = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
            let t = CGVector(dx: (b.x - a.x) / d, dy: (b.y - a.y) / d)
            let nv = CGVector(dx: -t.dy, dy: t.dx)
            let w = width(i) / 2
            left.append(CGPoint(x: c[i].x + nv.dx * w, y: c[i].y + nv.dy * w))
            right.append(CGPoint(x: c[i].x - nv.dx * w, y: c[i].y - nv.dy * w))
            frames.append((t, nv))
        }
        // a half circle from one edge round the end to the other
        func cap(_ i: Int, forward: Bool) -> [CGPoint] {
            let sgn: CGFloat = forward ? 1 : -1, w = width(i) / 2, f = frames[i]
            return (1..<12).map { k in
                let phi = CGFloat.pi * CGFloat(k) / 12
                return CGPoint(x: c[i].x + (cos(phi) * f.n.dx + sin(phi) * f.t.dx) * sgn * w,
                               y: c[i].y + (cos(phi) * f.n.dy + sin(phi) * f.t.dy) * sgn * w)
            }
        }
        let contour = left + cap(n, forward: true) + right.reversed() + cap(0, forward: false)

        let lean = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: -9 * .pi / 180)
            .translatedBy(x: -cx, y: -cy)
        var body = Path()
        body.addLines(contour)
        body.closeSubpath()
        body = body.applying(lean)

        let holes = suckers.map { (i, r) -> (x: CGFloat, y: CGFloat, r: CGFloat) in
            let v = CGVector(dx: cx - c[i].x, dy: cy - c[i].y)
            let dv = hypot(v.dx, v.dy), off = width(i) * 0.26
            let p = CGPoint(x: c[i].x + v.dx / dv * off, y: c[i].y + v.dy / dv * off).applying(lean)
            return (p.x, p.y, r)
        }
        return Cut(body: body, box: body.boundingRect, suckers: holes)
    }
}

/// The mark's silhouette as one strokeable path, so it can be drawn on with
/// `.trim` (§5 polish). The suckers are left out on purpose: a trim animation
/// reads as one line being drawn, and discs appearing mid-stroke is not that.
/// They fill in on the settle, which reads as interior detail arriving rather
/// than the arm changing shape.
///
/// **IT TAKES THE FULL CUT, BECAUSE IT HAS TO END AS THE MARK IT DRAWS (prd
/// §866, 2026-09-21).** Its first real caller draws at `DS.Mark.tile` (44),
/// where `CasberiMark` is well past `smallCutBelow` and paints the full cut;
/// an outline of the clean cut would change the tip's shape at the crossfade.
struct CasberiMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        return CasberiMark.silhouette.applying(CGAffineTransform(scaleX: s, y: s))
    }
}

extension CasberiMark {
    fileprivate static var silhouette: Path { fullCut.body }
}

/// The wordmark: the clean cut standing in for the c, then "asberi" in Figtree
/// SemiBold (the app's own face since prd §532, so this IS the brand wordmark,
/// `docs/brand.md` §5) in the brand hue. The arm is sized against the type it
/// sits in and drops a hair under the baseline, the overshoot a round letter
/// takes.
struct CasberiWordmark: View {
    var style: DSTextStyle = .heading24

    /// The c's box as a share of the type's point size: the arm's own box,
    /// cropped, is a little taller than Figtree's x-height, as an overshooting
    /// c is.
    private static let cShare: CGFloat = 0.56
    /// Read so the arm re-sizes with the words when the text setting changes;
    /// the size itself comes from the same metrics `scaledFont` uses.
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        let _ = dynamicType
        let point = UIFontMetrics(forTextStyle: style.relative).scaledValue(for: style.platformSize)
        let c = point * Self.cShare
        HStack(alignment: .firstTextBaseline, spacing: point * 0.015) {
            Canvas { ctx, canvas in
                let cut = CasberiMark.cleanCut
                let side = max(cut.box.width, cut.box.height)
                let k = canvas.width / side
                let t = CGAffineTransform(translationX: -(cut.box.midX - side / 2), y: -(cut.box.midY - side / 2))
                    .concatenating(CGAffineTransform(scaleX: k, y: k))
                ctx.fill(cut.body.applying(t), with: .color(CasberiMark.pink))
            }
            .frame(width: c, height: c)
            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - point * 0.035 }
            Text(verbatim: "asberi")
                .dsText(style)
                .fontWeight(.semibold)
                .foregroundStyle(CasberiMark.pink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "casberi"))
    }
}

/// The mark on its own field, avatar-shaped — the app's face sitting where a
/// person's photo will. The field is the icon's: black in dark, white in light,
/// so the arm always reads and its suckers always punch.
struct CasberiSeal: View {
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(Color.adaptive(dark: "#000000", light: "#ffffff"))
            .frame(width: size, height: size)
            .overlay(CasberiMark(size: size * 0.74))
            .overlay(Circle().strokeBorder(DS.fillLine, lineWidth: 1))
    }
}
