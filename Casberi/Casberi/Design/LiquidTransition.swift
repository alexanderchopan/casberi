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

/// The wave itself — the frozen outgoing frame, full screen, above
/// everything. TimelineView drives the shader's progress (uniforms don't
/// ride withAnimation); ease-out so the wave lands softly. The shader owns
/// the reveal: everything behind the front is transparent, so the page
/// beneath arrives spatially — no whole-frame fade anywhere.
struct LiquidDissolveOverlay: View {
    let image: UIImage
    let duration: Double
    let onFinished: () -> Void

    private let start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let raw = min(1, context.date.timeIntervalSince(start) / duration)
            let progress = 1 - pow(1 - raw, 2)   // ease-out: fast rise, soft landing
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .layerEffect(
                        ShaderLibrary.liquidWave(
                            .float2(Float(geo.size.width), Float(geo.size.height)),
                            // The wave is born where the finger was — the
                            // avatar door, top-right of the nav bar.
                            .float2(Float(geo.size.width - 44), 84),
                            .float(Float(progress))
                        ),
                        maxSampleOffset: CGSize(width: 80, height: 80)
                    )
            }
            .ignoresSafeArea()
            .onChange(of: raw >= 1) { _, done in
                if done { onFinished() }
            }
        }
        .allowsHitTesting(false)
    }
}
