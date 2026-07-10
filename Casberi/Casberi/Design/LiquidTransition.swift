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

    /// @State, NOT let: the parent re-renders mid-ride (live times, chip
    /// staggers) and recreates this struct — a plain let would reset the
    /// clock and visibly RESTART the liquid (the jank in every draft
    /// before the sixth was partly this).
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let raw = min(1, context.date.timeIntervalSince(start) / duration)
            let progress = raw * raw * (3 - 2 * raw)   // ease-in-out: it breathes
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    Image(uiImage: incoming)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .layerEffect(
                            ShaderLibrary.liquidIn(
                                .float2(Float(size.width), Float(size.height)),
                                .float(Float(progress))
                            ),
                            maxSampleOffset: CGSize(width: 60, height: 60)
                        )
                    Image(uiImage: outgoing)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .layerEffect(
                            ShaderLibrary.liquidOut(
                                .float2(Float(size.width), Float(size.height)),
                                .float(Float(progress))
                            ),
                            maxSampleOffset: CGSize(width: 60, height: 60)
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


/// One reusable liquid door (2026-07-10) — any screen can open any push
/// through the dissolve: hold state here, wire `.liquidPushOverlay(_:)` on
/// the screen's NavigationStack, and call `open { route.push = … }` from
/// the door. Duration lives here so every door breathes at the same pace
/// (0.95 "too fast" → 1.3 "a tiny bit slower" → 1.5, ruled 2026-07-10).
@MainActor
@Observable
final class LiquidPusher {
    static let duration: Double = 1.5

    var outgoing: UIImage?
    var incoming: UIImage?

    /// Freezes both sides around the animation-less push. Falls back to the
    /// plain push if snapshotting fails (never block navigation on a shader).
    func open(push: @escaping () -> Void) {
        guard outgoing == nil else { push(); return }
        DSHaptic.tap()
        let pair = LiquidTransition.capturePair {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { push() }
        }
        guard let pair else { push(); return }
        outgoing = pair.outgoing
        incoming = pair.incoming
    }

    func finish() {
        outgoing = nil
        incoming = nil
    }
}

extension View {
    /// Hangs the dissolve overlay for a screen's LiquidPusher — put it on
    /// the NavigationStack so the veil covers nav chrome and pushed content.
    @ViewBuilder
    func liquidPushOverlay(_ pusher: LiquidPusher) -> some View {
        overlay {
            if let out = pusher.outgoing, let inc = pusher.incoming {
                LiquidDissolveOverlay(outgoing: out, incoming: inc,
                                      duration: LiquidPusher.duration) {
                    pusher.finish()
                }
            }
        }
    }
}
