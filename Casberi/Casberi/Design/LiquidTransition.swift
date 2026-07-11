import SwiftUI
import UIKit

/// The liquid page transition (2026-07-10) — the WHOLE screen turns to
/// liquid and resolves into the next page: both sides frozen around an
/// animation-less route change, then the `liquidOut`/`liquidIn` shaders
/// ripple the two frames as one surface.
///
/// Why snapshots on BOTH sides: SwiftUI shader effects cannot run on
/// UIKit-backed views (a NavigationStack is one — trying paints the yellow
/// no-entry placeholder), so the live destination can never wear the
/// shader; only a frozen frame can ripple. The two hazards of frozen
/// frames are handled explicitly:
/// - the incoming capture waits for the DESTINATION to report .onAppear
///   (deterministic — snapshotting in the same turn raced SwiftUI's commit
///   and sometimes photographed the OLD page: the ride played into itself
///   and ended in a hard cut);
/// - the ride ends through a LIFT (the crisp final frame fades ~0.25s), so
///   whatever moved on the live page under the veil — entrances, pulsing
///   dots, ticking times — is handed off softly, never snapped.
enum LiquidTransition {

    @MainActor
    static func window() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.keyWindow
    }

    /// Freezes the current screen and covers the window with a UIKit hold
    /// (immediate — no SwiftUI commit latency). The caller owns removing
    /// the hold once the overlay is up.
    @MainActor
    static func freeze() -> (frame: UIImage, hold: UIImageView)? {
        guard let window = window() else { return nil }
        let bounds = window.bounds
        let frame = UIGraphicsImageRenderer(bounds: bounds).image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        let hold = UIImageView(image: frame)
        hold.frame = bounds
        window.addSubview(hold)
        return (frame, hold)
    }

    /// The destination's frame, captured from the ROOT VIEW beneath the
    /// window-level hold (the hold can't photobomb it) once the pushed
    /// screen has actually appeared.
    @MainActor
    static func captureRoot() -> UIImage? {
        guard let window = window() else { return nil }
        let root = window.rootViewController?.view ?? window
        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            root.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
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
    static let duration: Double = 0.65
    static let popDuration: Double = 0.5
    /// The lift: when the liquid stills, the overlay holds the crisp final
    /// image and FADES over this window instead of unmounting in one frame.
    static let lift: Double = 0.2

    /// What drives the ride: a clock (tap), the finger (scrub), or the
    /// final fade (lift — `at` is the frozen progress: 1 done, 0 cancelled).
    enum Drive { case clock(start: Date, duration: Double), scrub, lift(start: Date, at: Double) }

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
    /// A ride waiting for its destination to appear: the frozen outgoing
    /// frame, the UIKit hold covering the switch, and how to ride once the
    /// incoming frame exists (nil duration = scrub).
    private var pending: (frame: UIImage, hold: UIImageView, duration: Double?)?
    private var settling = false

    var active: Bool { outgoing != nil || pending != nil }
    /// The pushed screen may offer the liquid way back (custom chevron +
    /// edge scrub) only when this pusher did the opening.
    var canPop: Bool { popAction != nil && !active }

    /// Honesty toward the system: a person who asked for reduced motion
    /// gets plain, instant navigation — no snapshots, no shader, no ride.
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    // MARK: - Open / pop (tap)

    /// Freezes the outgoing page, runs the animation-less push beneath the
    /// hold, then WAITS for the destination's .onAppear to capture the
    /// incoming frame and start the clock. Falls back to the plain push if
    /// freezing fails — never block navigation on a shader.
    func open(push: @escaping () -> Void, pop: @escaping () -> Void) {
        guard !active, !settling else { push(); return }
        pushAction = push
        popAction = pop
        guard !reduceMotion else { push(); return }
        DSHaptic.tap()
        begin(duration: Self.duration) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { push() }
        }
    }

    func liquidPop() {
        guard let popAction, !active, !settling else { return }
        guard !reduceMotion else {
            popAction()
            clearPop()
            return
        }
        DSHaptic.tap()
        self.popAction = nil
        self.pushAction = nil
        begin(duration: Self.popDuration) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { popAction() }
        }
    }

    private func begin(duration: Double?, change: () -> Void) {
        guard let frozen = LiquidTransition.freeze() else {
            change()
            return
        }
        change()
        pending = (frozen.frame, frozen.hold, duration)
        // Fallback: if no destination ever reports in (a pop to an already-
        // mounted root can miss .onAppear), complete after a beat anyway.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            destinationAppeared()
        }
    }

    /// The destination is on screen — capture it and ride. Called from the
    /// pushed screens' .onAppear (liquidPoppable) and the tab roots'
    /// .onAppear (liquidPushOverlay); idempotent, a no-op with no pending
    /// ride.
    func destinationAppeared() {
        guard let pending else { return }
        self.pending = nil
        let incoming = LiquidTransition.captureRoot()
        guard let incoming else {
            pending.hold.removeFromSuperview()
            return
        }
        if let duration = pending.duration {
            drive = .clock(start: .now, duration: duration)
        } else {
            drive = .scrub
            scrubProgress = 0
            isScrubbing = true
        }
        outgoing = pending.frame
        self.incoming = incoming
        // The SwiftUI overlay (progress 0 = the hold's exact pixels) takes
        // over on the next commit; the hold leaves a beat later so no naked
        // frame of the destination ever presents.
        let hold = pending.hold
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            hold.removeFromSuperview()
        }
    }

    // MARK: - Scrub (the finger owns the pop)

    /// Pops INSTANTLY beneath the hold, then the drag drives the liquid.
    /// A cancelled scrub re-pushes beneath the veil and unwinds — the
    /// person never sees either seam.
    func scrubBegin() {
        guard popAction != nil, !active, !settling, !reduceMotion else { return }
        let pop = popAction
        begin(duration: nil) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { pop?() }
        }
    }

    func scrubUpdate(_ progress: Double) {
        guard isScrubbing else { return }
        scrubProgress = min(1, max(0, progress))
    }

    /// Release: ramp to completion (stay popped) or back to zero (re-push
    /// beneath the veil), then hand off through the lift.
    func scrubEnd(complete: Bool) {
        guard isScrubbing else { return }
        isScrubbing = false
        settling = true
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
                DSHaptic.selection()
            } else if let pushAction {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { pushAction() }
                // One beat for the re-pushed page to lay out under the veil.
                try? await Task.sleep(for: .milliseconds(80))
            }
            settling = false
            // Hand off through the lift — never a hard unmount.
            drive = .lift(start: .now, at: complete ? 1 : 0)
        }
    }

    // MARK: - Lifecycle

    func finish() {
        outgoing = nil
        incoming = nil
    }

    /// The ripple stills — a soft touch says so (the app's motion-ends-in-
    /// a-touch grammar: chart tick, refresh thud, this). Fired as the lift
    /// begins, exactly when the liquid stops moving.
    func settleHaptic() { DSHaptic.selection() }

    /// The route emptied by some other hand (tab re-tap, deep link) — the
    /// remembered way back is stale.
    func clearPop() {
        popAction = nil
        pushAction = nil
    }
}

/// The ride itself — both frozen frames, full screen, above everything.
/// Clock rides ease in-out and exit through the lift; scrub rides the
/// finger and exits through scrubEnd's ramp + lift.
struct LiquidDissolveOverlay: View {
    let pusher: LiquidPusher
    let outgoing: UIImage
    let incoming: UIImage

    /// @State, NOT let: the parent re-renders mid-ride (live times, chip
    /// staggers) and recreates this struct — a plain let would reset the
    /// clock and visibly RESTART the liquid.
    @State private var settled = false

    var body: some View {
        TimelineView(.animation) { context in
            let (progress, alpha, done): (Double, Double, Bool) = {
                switch pusher.drive {
                case .clock(let start, let duration):
                    let t = context.date.timeIntervalSince(start)
                    if t < duration {
                        let raw = t / duration
                        return (raw * raw * (3 - 2 * raw), 1, false)   // ease-in-out
                    }
                    // The lift: liquid still, image crisp, fading to live.
                    let lt = min(1, (t - duration) / LiquidPusher.lift)
                    return (1, 1 - lt, lt >= 1)
                case .scrub:
                    return (pusher.scrubProgress, 1, false)   // scrubEnd owns completion
                case .lift(let start, let at):
                    let lt = min(1, context.date.timeIntervalSince(start) / LiquidPusher.lift)
                    return (at, 1 - lt, lt >= 1)
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
                            maxSampleOffset: CGSize(width: 40, height: 40)
                        )
                    Image(uiImage: outgoing)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .layerEffect(
                            ShaderLibrary.liquidOut(
                                .float2(Float(size.width), Float(size.height)),
                                .float(Float(progress))
                            ),
                            maxSampleOffset: CGSize(width: 40, height: 40)
                        )
                }
            }
            .ignoresSafeArea()
            .opacity(alpha)
            .onChange(of: alpha < 1 && progress >= 1) { _, lifting in
                // The liquid just stilled (clock rides) — say so once.
                if lifting, !settled {
                    settled = true
                    pusher.settleHaptic()
                }
            }
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
    /// Also reports the ROOT's appearance so a POP ride (back to this
    /// screen) can capture its incoming frame deterministically.
    @ViewBuilder
    func liquidPushOverlay(_ pusher: LiquidPusher) -> some View {
        self
            .onAppear { pusher.destinationAppeared() }
            .overlay {
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
    /// Also reports .onAppear — the moment an OPEN ride's destination is
    /// real, its incoming frame is captured and the liquid starts.
    func liquidPoppable() -> some View {
        modifier(LiquidPoppable())
    }
}

private struct LiquidPoppable: ViewModifier {
    @Environment(LiquidPusher.self) private var liquid
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear { liquid.destinationAppeared() }
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
