import SwiftUI
import UIKit

/// The liquid page transition (2026-07-10) — the WHOLE screen turns to
/// liquid and resolves into the next page. Mechanically: snapshot the
/// window, push the destination instantly beneath, then melt the snapshot
/// with the `liquidDissolve` displacement shader while it fades — one
/// continuous motion, no pop, no pre-push delay. The droplet blob died for
/// feeling fast and weird; this is the "entire screen becomes glass" ask.
enum LiquidTransition {

    /// A full-resolution snapshot of the key window — the outgoing frame
    /// the shader melts. Native scale on purpose: this is the crisp "before".
    @MainActor
    static func snapshot() -> UIImage? {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}

/// The melting snapshot itself — full screen, above everything. TimelineView
/// drives the shader's progress (shader uniforms don't ride withAnimation),
/// eased so the liquid builds gently and settles gently.
struct LiquidDissolveOverlay: View {
    let image: UIImage
    let duration: Double
    let onFinished: () -> Void

    private let start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let raw = min(1, context.date.timeIntervalSince(start) / duration)
            // Ease-in-out: the melt breathes instead of snapping.
            let progress = raw * raw * (3 - 2 * raw)
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .distortionEffect(
                        ShaderLibrary.liquidDissolve(
                            .float2(Float(geo.size.width), Float(geo.size.height)),
                            .float(Float(progress))
                        ),
                        maxSampleOffset: CGSize(width: 80, height: 80)
                    )
                    // The new page shows through as the liquid thins: fade
                    // begins once the melt is underway, ends with it.
                    .opacity(1 - smoothstep(0.35, 0.95, progress))
            }
            .ignoresSafeArea()
            .onChange(of: raw >= 1) { _, done in
                if done { onFinished() }
            }
        }
        .allowsHitTesting(false)
    }

    private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}
