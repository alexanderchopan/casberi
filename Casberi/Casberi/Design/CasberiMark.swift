import SwiftUI

/// The Casberi mark — the logo berry in vectors, scalable to any size.
/// The colors are the icon's own ramps (the dark and light icon variants);
/// like the brand table, they live here in the design layer (§8 — components
/// hold zero raw hex).
struct CasberiMark: View {
    var size: CGFloat = 20

    /// Berry centers in unit space, with the dark-variant and light-variant
    /// color per berry. Painted in this order so the bright berry lands on
    /// top of its neighbors, exactly as on the icon.
    private static let berries: [(x: CGFloat, y: CGFloat, dark: String, light: String)] = [
        (0.654, 0.812, "#021a33", "#cee6ff"),
        (0.812, 0.469, "#032a52", "#b1d8ff"),
        (0.337, 0.794, "#032a52", "#b1d8ff"),
        (0.513, 0.487, "#053b73", "#91c8ff"),
        (0.188, 0.487, "#064f99", "#6cb5ff"),
        (0.654, 0.188, "#064f99", "#6cb5ff"),
        (0.329, 0.188, "#0a84ff", "#0a84ff"),
    ]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, canvas in
            let side = min(canvas.width, canvas.height)
            let r = 0.188 * side
            for berry in Self.berries {
                let rect = CGRect(x: berry.x * side - r, y: berry.y * side - r,
                                  width: r * 2, height: r * 2)
                let hex = scheme == .light ? berry.light : berry.dark
                context.fill(Path(ellipseIn: rect), with: .color(Color(hex: hex)))
            }
        }
        .frame(width: size, height: size)
    }
}

/// The berry as one strokeable path (all seven circles), so the mark can be
/// drawn on with `.trim` — quiet states use it (§5 polish).
struct CasberiBerryShape: Shape {
    private static let centers: [(CGFloat, CGFloat)] = [
        (0.329, 0.188), (0.654, 0.188), (0.188, 0.487), (0.513, 0.487),
        (0.812, 0.469), (0.337, 0.794), (0.654, 0.812),
    ]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let side = min(rect.width, rect.height)
        let r = 0.188 * side
        for c in Self.centers {
            p.addEllipse(in: CGRect(x: c.0 * side - r, y: c.1 * side - r,
                                    width: r * 2, height: r * 2))
        }
        return p
    }
}

/// The mark drawing itself: a 900ms trim-path stroke in tertiary, settling
/// into the full-color mark. Plays once per appearance.
struct CasberiMarkDrawOn: View {
    var size: CGFloat = 44
    @State private var progress: CGFloat = 0
    @State private var filled = false

    var body: some View {
        ZStack {
            CasberiBerryShape()
                .trim(from: 0, to: progress)
                .stroke(DS.textTertiary, lineWidth: 1.5)
                .opacity(filled ? 0 : 1)
            CasberiMark(size: size)
                .opacity(filled ? 1 : 0)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.9)) {
                progress = 1
            }
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(DS.Motion.standard) { filled = true }
            }
        }
    }
}

/// The mark on its own field, avatar-shaped — the app's face sitting where
/// a person's photo will. The field is the icon's: black in dark, white in
/// light, so the berry always reads.
struct CasberiSeal: View {
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(Color.adaptive(dark: "#000000", light: "#ffffff"))
            .frame(width: size, height: size)
            .overlay(CasberiMark(size: size * 0.62))
            .overlay(Circle().strokeBorder(DS.fillLine, lineWidth: 1))
    }
}
