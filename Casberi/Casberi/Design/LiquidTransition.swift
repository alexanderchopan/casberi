import SwiftUI
import UIKit

/// The liquid page transition (2026-07-10) — the WHOLE screen turns to
/// liquid and resolves into the next page: both sides frozen around an
/// animation-less route change, then the `liquidOut`/`liquidIn` shaders
/// ripple the two frames as one surface. The system now runs BOTH ways
/// (open and pop), honors Reduce Motion, ends in a settle haptic, and the
/// pop can be SCRUBBED — a drag from the leading edge drives the liquid
/// under the finger.
enum LiquidTransition {

    /// Freezes BOTH sides of a route change in one pass: snapshot the
    /// outgoing page, cover the window with a UIKit hold (immediate — no
    /// SwiftUI commit latency), run the change, then snapshot the ROOT VIEW
    /// beneath the hold with afterScreenUpdates so the destination is laid
    /// out and drawn. The hold is window-level, the capture is root-level,
    /// so the hold can never photobomb the incoming frame.
    @MainActor
    static func capturePair(around change: () -> Void) -> (outgoing: UIImage, incoming: UIImage)? {
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

        change()

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

/// One reusable liquid door — a screen owns a pusher, hangs
/// `.liquidPushOverlay(_:)` on its NavigationStack, injects the pusher into
/// the environment, and both doors AND the pushed screens' way back ride it.
/// Durations live here so every ride breathes at the same pace
/// (0.95 "too fast" → 1.3 "a tiny bit slower" → 1.5, ruled 2026-07-10;
/// leaving is lighter than arriving, so the pop runs quicker).
@MainActor
@Observable
final class LiquidPusher {
    static let duration: Double = 1.5
    static let popDuration: Double = 1.1

    /// What drives the ride: a clock (tap) or the finger (scrub).
    enum Drive { case clock(start: Date, duration: Double), scrub }

    var outgoing: UIImage?
    var incoming: UIImage?
    var drive: Drive = .scrub
    /// Scrub position, 0…1 — the finger owns it while dragging; the release
    /// ramp finishes the ride (or unwinds it).
    var scrubProgress: Double = 0
    private(set) var isScrubbing = false

    /// The way back, remembered from the open — the pushed screen pops
    /// through the same liquid (and the scrub can cancel, re-pushing).
    private var popAction: (() -> Void)?
    private var pushAction: (() -> Void)?
    /// True while a completed pop is being cleaned up — blocks re-entry.
    private var ramping = false

    var active: Bool { outgoing != nil }
    /// The pushed screen may offer the liquid way back (custom chevron +
    /// edge scrub) only when this pusher did the opening.
    var canPop: Bool { popAction != nil && !active }

    /// Honesty toward the system: a person who asked for reduced motion
    /// gets plain, instant navigation — no snapshots, no shader, no ride.
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    // MARK: - Open (tap)

    /// Freezes both sides around the animation-less push. Falls back to the
    /// plain push if snapshotting fails (never block navigation on a shader).
    func open(push: @escaping () -> Void, pop: @escaping () -> Void) {
        guard !active, !ramping else { push(); return }
        pushAction = push
        popAction = pop
        guard !reduceMotion else { push(); return }
        DSHaptic.tap()
        let pair = LiquidTransition.capturePair {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { push() }
        }
        guard let pair else { push(); return }
        drive = .clock(start: .now, duration: Self.duration)
        outgoing = pair.outgoing
        incoming = pair.incoming
    }

    // MARK: - Pop (tap on the way back)

    func liquidPop() {
        guard let popAction, !active, !ramping else { return }
        guard !reduceMotion else {
            popAction()
            clearPop()
            return
        }
        DSHaptic.tap()
        let pair = LiquidTransition.capturePair {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { popAction() }
        }
        guard let pair else { popAction(); clearPop(); return }
        drive = .clock(start: .now, duration: Self.popDuration)
        outgoing = pair.outgoing
        incoming = pair.incoming
        self.popAction = nil
        self.pushAction = nil
    }

    // MARK: - Scrub (the finger owns the pop)

    /// Pops INSTANTLY beneath the veil, then the drag drives the liquid.
    /// A cancelled scrub re-pushes beneath the veil and unwinds — the
    /// person never sees either seam.
    func scrubBegin() {
        guard popAction != nil, !active, !ramping, !reduceMotion else { return }
        let pair = LiquidTransition.capturePair {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { self.popAction?() }
        }
        guard let pair else { return }
        drive = .scrub
        scrubProgress = 0
        isScrubbing = true
        outgoing = pair.outgoing
        incoming = pair.incoming
    }

    func scrubUpdate(_ progress: Double) {
        guard isScrubbing else { return }
        scrubProgress = min(1, max(0, progress))
    }

    /// Release: ramp to completion (stay popped) or back to zero (re-push
    /// beneath the veil, then lift it).
    func scrubEnd(complete: Bool) {
        guard isScrubbing else { return }
        isScrubbing = false
        ramping = true
        let from = scrubProgress
        let to: Double = complete ? 1 : 0
        Task { @MainActor in
            let steps = max(1, Int(abs(to - from) * 24))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                scrubProgress = from + (to - from) * (t * t * (3 - 2 * t))
                try? await Task.sleep(for: .milliseconds(12))
            }
            if complete {
                popAction = nil
                pushAction = nil
            } else if let pushAction {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { pushAction() }
                // One beat for the re-pushed page to lay out under the veil.
                try? await Task.sleep(for: .milliseconds(80))
            }
            ramping = false
            finish(settle: complete)
        }
    }

    // MARK: - Lifecycle

    func finish(settle: Bool = true) {
        outgoing = nil
        incoming = nil
        // The ripple stills — a soft touch says so (the app's motion-ends-
        // in-a-touch grammar: chart tick, refresh thud, this).
        if settle { DSHaptic.selection() }
    }

    /// The route emptied by some other hand (tab re-tap, deep link) — the
    /// remembered way back is stale.
    func clearPop() {
        popAction = nil
        pushAction = nil
    }
}

/// The ride itself — both frozen frames, full screen, above everything.
/// Clock rides ease in-out on a TimelineView; scrub rides the finger.
struct LiquidDissolveOverlay: View {
    let pusher: LiquidPusher
    let outgoing: UIImage
    let incoming: UIImage

    /// @State, NOT let: the parent re-renders mid-ride (live times, chip
    /// staggers) and recreates this struct — a plain let would reset the
    /// clock and visibly RESTART the liquid.
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let (progress, done): (Double, Bool) = {
                switch pusher.drive {
                case .clock(let start, let duration):
                    let raw = min(1, context.date.timeIntervalSince(start) / duration)
                    return (raw * raw * (3 - 2 * raw), raw >= 1)   // ease-in-out
                case .scrub:
                    return (pusher.scrubProgress, false)   // scrubEnd owns completion
                }
            }()
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
            .onChange(of: done) { _, isDone in
                if isDone { pusher.finish() }
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Hangs the dissolve overlay for a screen's LiquidPusher — put it on
    /// the NavigationStack so the veil covers nav chrome and pushed content.
    @ViewBuilder
    func liquidPushOverlay(_ pusher: LiquidPusher) -> some View {
        overlay {
            if let out = pusher.outgoing, let inc = pusher.incoming {
                LiquidDissolveOverlay(pusher: pusher, outgoing: out, incoming: inc)
            }
        }
    }

    /// A pushed screen's liquid way back: the system back button gives way
    /// to a chevron that pops through the dissolve, and the leading edge
    /// scrubs it under the finger. Only bites when the environment's pusher
    /// actually did the opening (a deep-linked or probe-pushed screen keeps
    /// the system back). Reduce Motion keeps the plain pop and no scrub.
    func liquidPoppable() -> some View {
        modifier(LiquidPoppable())
    }
}

private struct LiquidPoppable: ViewModifier {
    @Environment(LiquidPusher.self) private var liquid
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(liquid.canPop)
            .toolbar {
                if liquid.canPop {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            liquid.liquidPop()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .tint(DS.textPrimary)
                        .accessibilityLabel("Back")
                    }
                }
            }
            .overlay(alignment: .leading) {
                // The scrub strip — a narrow edge that hands the pop to the
                // finger. Hiding the system back button already disabled the
                // native edge swipe, so the edge is ours alone here.
                if liquid.canPop, !reduceMotion {
                    Color.clear
                        .frame(width: 24)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { v in
                                    if !liquid.isScrubbing { liquid.scrubBegin() }
                                    liquid.scrubUpdate(v.translation.width / 300)
                                }
                                .onEnded { v in
                                    let p = min(1, max(0, v.translation.width / 300))
                                    let flick = v.predictedEndTranslation.width
                                        > v.translation.width + 60
                                    liquid.scrubEnd(complete: p > 0.3 || flick)
                                }
                        )
                }
            }
    }
}
