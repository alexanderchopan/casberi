import SwiftUI
import UIKit

/// The liquid page transition (2026-07-10) — the WHOLE screen turns to
/// liquid and resolves into the next page. Mechanically: snapshot the
/// window, push the destination instantly beneath, then melt the snapshot
/// with the `liquidDissolve` displacement shader while it fades — one
/// continuous motion, no pop, no pre-push delay. The droplet blob died for
/// feeling fast and weird; this is the "entire screen becomes glass" ask.
enum LiquidTransition {

    /// Freezes BOTH sides of the transition in one pass: snapshot the
    /// outgoing page, cover the window with a UIKit hold (immediate — no
    /// SwiftUI commit latency), run the push, then snapshot the ROOT VIEW
    /// beneath the hold with afterScreenUpdates so the destination is laid
    /// out and drawn. The hold is window-level, the capture is root-level,
    /// so the hold can never photobomb the incoming frame (the fifth-draft
    /// bug: the "incoming" snapshot was a picture of the hold itself, and
    /// the wave played Home-into-Home — invisible, then a pop).
    @MainActor
    static func capturePair(push: () -> Void) -> (outgoing: UIImage, incoming: UIImage)? {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.keyWindow else { return nil }
        let bounds = window.bounds
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let outgoing = renderer.image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }

        let hold = UIImageView(image: outgoing)
        hold.frame = bounds
        window.addSubview(hold)

        push()

        let root = window.rootViewController?.view ?? window
        let incoming = renderer.image { _ in
            root.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        // The SwiftUI overlay (progress 0 = the same outgoing pixels) takes
        // over on the next commit; the hold leaves a beat later so no naked
        // frame of the destination ever presents.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            hold.removeFromSuperview()
        }
        return (outgoing, incoming)
    }
}

/// The wave itself — the frozen outgoing frame, full screen, above
/// everything. TimelineView drives the shader's progress (uniforms don't
/// ride withAnimation); ease-out so the wave lands softly. The shader owns
/// the reveal: everything behind the front is transparent, so the page
/// beneath arrives spatially — no whole-frame fade anywhere.
struct LiquidDissolveOverlay: View {
    /// The frozen outgoing page — melts away at the front.
    let outgoing: UIImage
    /// The frozen INCOMING page — rides the same wave: liquid right behind
    /// the front, settling to crisp. Without it the destination read as "a
    /// sheet that was already there" (fifth-draft correction).
    let incoming: UIImage
    let duration: Double
    let onFinished: () -> Void

    private let start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let raw = min(1, context.date.timeIntervalSince(start) / duration)
            let progress = 1 - pow(1 - raw, 2)   // ease-out: fast rise, soft landing
            GeometryReader { geo in
                let size = geo.size
                let origin = SIMD2<Float>(Float(size.width - 44), 84)
                ZStack {
                    Image(uiImage: incoming)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .layerEffect(
                            ShaderLibrary.liquidSettle(
                                .float2(Float(size.width), Float(size.height)),
                                .float2(origin.x, origin.y),
                                .float(Float(progress))
                            ),
                            maxSampleOffset: CGSize(width: 60, height: 60)
                        )
                    Image(uiImage: outgoing)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .layerEffect(
                            ShaderLibrary.liquidWave(
                                .float2(Float(size.width), Float(size.height)),
                                .float2(origin.x, origin.y),
                                .float(Float(progress))
                            ),
                            maxSampleOffset: CGSize(width: 80, height: 80)
                        )
                }
            }
            .ignoresSafeArea()
            .onChange(of: raw >= 1) { _, done in
                if done { onFinished() }
            }
        }
        .allowsHitTesting(false)
    }
}
