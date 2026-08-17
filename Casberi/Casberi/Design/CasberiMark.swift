import SwiftUI

/// The Casberi mark — the leaning octopus, in vectors, scalable to any size.
///
/// Geometry is the handoff's own 100×100 unit space (see `docs/brand.md`), kept
/// verbatim rather than re-derived: the head group is rotated −9° about (50,46)
/// and the arms are drawn ALREADY SWEPT, never rotated. Rotating the arms with
/// the head is the one change that quietly destroys this mark — the sweep is
/// what makes the lean read as a lean instead of a tilted picture.
///
/// Colors live here in the design layer (§8 — components hold zero raw hex).
/// The eyes and suckers are drawn in the GROUND color, not a dark ink, so they
/// read as holes punched through the creature the way the artwork intends.
struct CasberiMark: View {
    var size: CGFloat = 20

    /// Below this, the suckers and the two inner arms are dropped and the
    /// remaining strokes thicken. The rings are 1.4 units wide — at 20pt that
    /// is a quarter of a point, which renders as grey haze rather than a ring,
    /// and eight arms at 20pt close into a single skirt. The handoff sets the
    /// boundary at 60; the FAB (20), the shell (18) and the surface (44) all
    /// take the small cut, which is the point of having one.
    static let smallCutBelow: CGFloat = 60

    private var full: Bool { size >= Self.smallCutBelow }

    /// The brand hue, and the only one. `#FF2D87`.
    static let pink = Color(hex: "#FF2D87")
    /// Whatever the mark is standing on — black in dark, white in light. The
    /// eyes and suckers are this, so they punch rather than print.
    private var ground: Color { Color.adaptive(dark: "#000000", light: "#ffffff") }

    var body: some View {
        Canvas { ctx, canvas in
            let s = min(canvas.width, canvas.height) / 100
            let scale = CGAffineTransform(scaleX: s, y: s)
            // the head and its eyes lean; nothing else does
            let lean = CGAffineTransform(translationX: 50, y: 46)
                .rotated(by: -9 * .pi / 180)
                .translatedBy(x: -50, y: -46)
                .concatenating(scale)

            ctx.fill(Self.head.applying(lean), with: .color(Self.pink))

            let eyeR: CGFloat = full ? 3.7 : 5
            for c in Self.eyes {
                let r = CGRect(x: c.x - eyeR, y: c.y - eyeR, width: eyeR * 2, height: eyeR * 2)
                ctx.fill(Path(ellipseIn: r).applying(lean), with: .color(ground))
            }

            let arms = full ? Self.armsFull : Self.armsSmall
            let width: CGFloat = (full ? 8 : 9) * s
            for arm in arms {
                ctx.stroke(arm.applying(scale), with: .color(Self.pink),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            guard full else { return }
            for k in Self.suckers {
                let r = CGRect(x: k.x - k.r, y: k.y - k.r, width: k.r * 2, height: k.r * 2)
                ctx.stroke(Path(ellipseIn: r).applying(scale), with: .color(ground),
                           style: StrokeStyle(lineWidth: 1.4 * s))
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - the artwork, in unit space

    private static let head: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 33, y: 46))
        p.addCurve(to: CGPoint(x: 31, y: 26), control1: CGPoint(x: 29, y: 42), control2: CGPoint(x: 28, y: 34))
        p.addCurve(to: CGPoint(x: 59, y: 13), control1: CGPoint(x: 35, y: 14), control2: CGPoint(x: 48, y: 8))
        p.addCurve(to: CGPoint(x: 68, y: 40), control1: CGPoint(x: 70, y: 18), control2: CGPoint(x: 73, y: 31))
        p.addCurve(to: CGPoint(x: 68, y: 46), control1: CGPoint(x: 66, y: 43), control2: CGPoint(x: 68, y: 45))
        p.closeSubpath()
        return p
    }()

    private static let eyes: [CGPoint] = [CGPoint(x: 44, y: 33), CGPoint(x: 58.5, y: 36.5)]

    /// Outer arms end in a back-curl (the second curve); the inner three taper
    /// straight. Five arms, deliberately — see `docs/brand.md`.
    private static let armsFull: [Path] = {
        func arm(_ build: (inout Path) -> Void) -> Path { var p = Path(); build(&p); return p }
        return [
            arm { p in
                p.move(to: CGPoint(x: 30, y: 42))
                p.addCurve(to: CGPoint(x: 11, y: 46), control1: CGPoint(x: 25, y: 51), control2: CGPoint(x: 17, y: 53))
                p.addCurve(to: CGPoint(x: 16, y: 40), control1: CGPoint(x: 8, y: 42), control2: CGPoint(x: 12, y: 37))
            },
            arm { p in
                p.move(to: CGPoint(x: 38, y: 46))
                p.addCurve(to: CGPoint(x: 16, y: 66), control1: CGPoint(x: 34, y: 62), control2: CGPoint(x: 24, y: 71))
            },
            arm { p in
                p.move(to: CGPoint(x: 47, y: 48))
                p.addCurve(to: CGPoint(x: 30, y: 80), control1: CGPoint(x: 46, y: 68), control2: CGPoint(x: 39, y: 82))
            },
            arm { p in
                p.move(to: CGPoint(x: 57, y: 47))
                p.addCurve(to: CGPoint(x: 79, y: 70), control1: CGPoint(x: 60, y: 64), control2: CGPoint(x: 70, y: 74))
                p.addCurve(to: CGPoint(x: 76, y: 63.5), control1: CGPoint(x: 84, y: 67.5), control2: CGPoint(x: 81, y: 61))
            },
            arm { p in
                p.move(to: CGPoint(x: 66, y: 43))
                p.addCurve(to: CGPoint(x: 86, y: 46), control1: CGPoint(x: 72, y: 52), control2: CGPoint(x: 81, y: 54))
            },
        ]
    }()

    /// The small cut: arms 1, 3 and 5, the outer one shorn of its back-curl.
    private static let armsSmall: [Path] = {
        func arm(_ build: (inout Path) -> Void) -> Path { var p = Path(); build(&p); return p }
        return [
            arm { p in
                p.move(to: CGPoint(x: 30, y: 42))
                p.addCurve(to: CGPoint(x: 11, y: 46), control1: CGPoint(x: 25, y: 51), control2: CGPoint(x: 17, y: 53))
            },
            arm { p in
                p.move(to: CGPoint(x: 47, y: 48))
                p.addCurve(to: CGPoint(x: 30, y: 80), control1: CGPoint(x: 46, y: 68), control2: CGPoint(x: 39, y: 82))
            },
            arm { p in
                p.move(to: CGPoint(x: 66, y: 43))
                p.addCurve(to: CGPoint(x: 86, y: 46), control1: CGPoint(x: 72, y: 52), control2: CGPoint(x: 81, y: 54))
            },
        ]
    }()

    /// Graduated big→small along each arm: 2.6, 1.9, 1.3.
    private static let suckers: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (28.5, 47.5, 2.6), (23.5, 51.5, 1.9),
        (36.5, 53.5, 2.6), (33, 61, 1.9), (26.5, 66.5, 1.3),
        (47, 57, 2.6), (45.5, 66, 1.9), (42, 74.5, 1.3),
        (58.8, 55, 2.6), (62.5, 62.5, 1.9), (68.5, 68.5, 1.3),
        (68.5, 48.5, 2.6), (74, 51.5, 1.9),
    ]
}

/// The mark's silhouette as one strokeable path — head plus the small cut's
/// three arms, so it can be drawn on with `.trim` (§5 polish). The suckers and
/// the inner arms are left out on purpose: a trim animation reads as one line
/// being drawn, and thirteen rings appearing mid-stroke is not that.
struct CasberiMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        let scale = CGAffineTransform(scaleX: s, y: s)
        let lean = CGAffineTransform(translationX: 50, y: 46)
            .rotated(by: -9 * .pi / 180)
            .translatedBy(x: -50, y: -46)
            .concatenating(scale)

        var p = Path()
        p.addPath(CasberiMark.silhouetteHead.applying(lean))
        for arm in CasberiMark.silhouetteArms { p.addPath(arm.applying(scale)) }
        return p
    }
}

extension CasberiMark {
    fileprivate static var silhouetteHead: Path { head }
    fileprivate static var silhouetteArms: [Path] { armsSmall }
}

/// The mark on its own field, avatar-shaped — the app's face sitting where a
/// person's photo will. The field is the icon's: black in dark, white in light,
/// so the creature always reads and its eyes always punch.
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
