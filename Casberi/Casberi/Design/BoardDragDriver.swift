import SwiftUI
import UIKit

/// The board's input layer, in UIKit on purpose (2026-07-13). The SwiftUI
/// version — an `onLongPressGesture` plus an always-attached `DragGesture` on
/// EVERY card, coexisting with the ScrollView's pan via `simultaneousGesture`
/// — went through four repair commits (9ab40ac, 7cb10a9, 9dc5ead, 7932d0c)
/// and still shipped two failures SwiftUI cannot express a fix for:
///
///  • the scroll pan stays live DURING a drag, so the board scrolls under the
///    finger and eats the lifted card's vertical motion ("hard to move"); and
///  • a cancelled drag fires no `.onEnded`, so drag state leaks and the board
///    locks ("Home gets stuck / can't scroll") — the @GestureState dead-man
///    switch narrowed the race, never closed it.
///
/// One long-press-drag recognizer on the enclosing UIScrollView closes both
/// for good: UIKit ALWAYS delivers `touchesCancelled` (nothing can leak), and
/// on lift we disable the scroll pan outright — the drag owns the touch, the
/// way Apple's own Home Screen does it. Auto-scroll writes `contentOffset`
/// directly on a CADisplayLink (smooth), replacing the 50ms `scrollTo` hops.
///
/// The recognizer is a CUSTOM UIGestureRecognizer subclass that invokes its
/// callback directly from its own touch handlers and lift timer — NOT a
/// UILongPressGestureRecognizer with target-action. Diagnosed on-device
/// (2026-07-13): a stock recognizer added to SwiftUI's UIScrollView
/// transitions state correctly, but its target-action fires only
/// intermittently — SwiftUI's gesture environment eats the dispatch. Setting
/// `state` from a subclass still feeds UIKit's exclusivity machinery (other
/// recognizers get cancelled when we begin), so we keep every UIKit
/// guarantee while owning the delivery path ourselves.
struct BoardDragDriver<ID: Hashable>: UIViewRepresentable {
    /// Edit mode — a light press (0.12s) grabs a tile; from rest it takes the
    /// full hold (0.35s). Same thresholds the SwiftUI version tuned.
    var editing: Bool
    /// Hit-test a point in board space to the card under it (nil = a gap).
    var cardAt: (CGPoint) -> ID?
    /// A card lifted — the board sets draggingID, linearizes, arms edit mode.
    var onLift: (ID) -> Void
    /// The finger moved (or auto-scroll slid the content under a stationary
    /// finger). `translation`/`autoScrollDelta` position the lifted card's
    /// rendered offset; `fingerInBoard` is the touch in BOARD space — scroll
    /// and linearization already baked in, so the reorder math needs no
    /// captured frames or timing assumptions.
    var onMove: (_ translation: CGSize, _ autoScrollDelta: CGFloat,
                 _ fingerInBoard: CGPoint) -> Void
    /// The touch ended OR was cancelled — the recognizer's own touch handlers
    /// deliver exactly one of these per lift, so the board can never be left
    /// holding a drag.
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> DriverView {
        let view = DriverView()
        view.coordinator = context.coordinator
        context.coordinator.hostView = view
        return view
    }

    func updateUIView(_ view: DriverView, context: Context) {
        let c = context.coordinator
        c.press.minimumPressDuration = editing ? 0.12 : 0.35
        c.cardAt = cardAt
        c.onLift = onLift
        c.onMove = onMove
        c.onEnd = onEnd
    }

    static func dismantleUIView(_ view: DriverView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Transparent to touches; exists to anchor the coordinator in the view
    /// hierarchy so it can walk up to the UIScrollView once mounted, and to
    /// define the board's coordinate space for card hit-testing.
    final class DriverView: UIView {
        weak var coordinator: Coordinator?
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { coordinator?.attachIfNeeded() }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var cardAt: ((CGPoint) -> ID?)?
        var onLift: ((ID) -> Void)?
        var onMove: ((CGSize, CGFloat, CGPoint) -> Void)?
        var onEnd: (() -> Void)?

        weak var hostView: UIView?
        private weak var scrollView: UIScrollView?
        let press = LongPressDragRecognizer()

        private var dragging = false
        private var startWindowPoint: CGPoint = .zero
        private var lastWindowPoint: CGPoint = .zero
        private var offsetAtLift: CGFloat = 0
        private var displayLink: CADisplayLink?
        private var scrollDir: CGFloat = 0

        override init() {
            super.init()
            press.delegate = self
            press.onPhase = { [weak self] phase in self?.handle(phase) }
        }

        func attachIfNeeded() {
            guard press.view == nil, let host = hostView else { return }
            var walker = host.superview
            while let v = walker, !(v is UIScrollView) { walker = v.superview }
            guard let sv = walker as? UIScrollView else {
                return
            }
            scrollView = sv
            sv.addGestureRecognizer(press)
        }

        func detach() {
            // A board torn down mid-drag never sends finger-up — settle
            // through the normal path so the reorder persists and the
            // board's drag state can't leak.
            if dragging {
                finish()
            } else {
                endAutoScroll()
                scrollView?.panGestureRecognizer.isEnabled = true
            }
            press.view?.removeGestureRecognizer(press)
        }

        // Simultaneous with the scroll pan ONLY (so the press can track a
        // touch the pan is also watching; on lift we disable the pan anyway).
        // Everything else — including the content rows' own long-press menus
        // (Open / Open in app) — stays mutually exclusive: when the lift
        // begins first, UIKit cancels theirs, so a board drag never also
        // pops a row menu over the lifted card.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other === scrollView?.panGestureRecognizer
        }

        // Every content recognizer must WAIT for the press to fail before it
        // can recognize (diagnosed 2026-07-13: SwiftUI buttons carry a
        // touch-down recognizer that otherwise recognizes ~40ms into the
        // hold and force-fails this recognizer — the lift timer dies and a
        // press on any button-backed tile could never lift). With the
        // failure requirement, a quick tap still lands (the press fails on
        // touch-up and the tap proceeds), a drift still scrolls (the press
        // fails past 24pt and the pan — exempt below — was never gated),
        // and a genuine hold reaches 0.35s, lifts, and permanently blocks
        // the gated recognizers for that touch. Exactly the Home Screen
        // arrangement. Pans (the scroll, the nav stack's edge back-swipe,
        // sheet dismissals) are exempt: they begin on movement, movement
        // fails this press anyway, so gating them buys nothing but lag.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            !(other is UIPanGestureRecognizer)
        }

        private func handle(_ phase: LongPressDragRecognizer.Phase) {
            switch phase {
            case .began:
                guard let host = hostView,
                      let id = cardAt?(press.location(in: host)) else {
                    // The hold landed on a gap, not a card — abandon this
                    // press so the touch stays an ordinary scroll/tap.
                    press.abandon()
                    return
                }
                dragging = true
                startWindowPoint = press.location(in: nil)
                lastWindowPoint = startWindowPoint
                offsetAtLift = scrollView?.contentOffset.y ?? 0
                // The drag owns this touch now: killing the pan cancels any
                // scroll in flight and keeps one from starting mid-drag —
                // THE fix for "the board scrolls while I'm dragging".
                scrollView?.panGestureRecognizer.isEnabled = false
                onLift?(id)
            case .moved:
                guard dragging else { return }
                lastWindowPoint = press.location(in: nil)
                updateAutoScroll()
                emitMove()
            case .ended:
                guard dragging else { return }
                finish()
            }
        }

        private func emitMove() {
            guard let host = hostView else { return }
            let t = CGSize(width: lastWindowPoint.x - startWindowPoint.x,
                           height: lastWindowPoint.y - startWindowPoint.y)
            let delta = (scrollView?.contentOffset.y ?? 0) - offsetAtLift
            onMove?(t, delta, press.location(in: host))
        }

        private func finish() {
            dragging = false
            endAutoScroll()
            scrollView?.panGestureRecognizer.isEnabled = true
            onEnd?()
        }

        // MARK: - Edge auto-scroll (a board taller than the screen)

        /// The finger entered/left an edge band of the scroll viewport —
        /// start/stop the per-frame nudge accordingly.
        private func updateAutoScroll() {
            guard let sv = scrollView, let window = sv.window else { return }
            let viewport = sv.convert(sv.bounds, to: window)
            let band: CGFloat = 110
            let top = viewport.minY + sv.adjustedContentInset.top
            let bottom = viewport.maxY - sv.adjustedContentInset.bottom
            let y = lastWindowPoint.y
            let dir: CGFloat = y < top + band ? -1 : (y > bottom - band ? 1 : 0)
            guard dir != scrollDir else { return }
            scrollDir = dir
            if dir == 0 {
                displayLink?.invalidate()
                displayLink = nil
            } else if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(step))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        }

        @objc private func step(_ link: CADisplayLink) {
            guard dragging, let sv = scrollView else {
                scrollDir = 0
                link.invalidate()
                displayLink = nil
                return
            }
            let dt = CGFloat(link.targetTimestamp - link.timestamp)
            let speed: CGFloat = 440   // pt/s — brisk but trackable
            let minY = -sv.adjustedContentInset.top
            let maxY = max(minY, sv.contentSize.height - sv.bounds.height
                                 + sv.adjustedContentInset.bottom)
            let y = min(max(sv.contentOffset.y + scrollDir * speed * dt, minY), maxY)
            // Clamped at the content edge: nothing moved, nothing to re-run —
            // don't spin reorder passes while a finger sits parked in a band.
            guard y != sv.contentOffset.y else { return }
            sv.contentOffset.y = y
            // The content slid under a (possibly stationary) finger — the
            // board must re-render the lifted card and re-run reorder.
            emitMove()
        }

        private func endAutoScroll() {
            scrollDir = 0
            displayLink?.invalidate()
            displayLink = nil
        }
    }
}

/// Long-press-then-drag as ONE continuous recognizer, self-delivered.
///
/// Semantics: a touch that stays within `allowableMovement` for
/// `minimumPressDuration` begins the gesture (the lift); after that every
/// move is `.moved` and the touch ending or being cancelled is `.ended`.
/// Moving too far BEFORE the duration elapses fails the recognizer, so the
/// scroll pan keeps the touch — a flick still scrolls, only a settled finger
/// grabs a card.
///
/// It reports through `onPhase` from its own touch handlers, never through
/// target-action (see BoardDragDriver's header: action dispatch from
/// SwiftUI's scroll view is intermittent). It still sets `state` at every
/// step, so UIKit's exclusivity rules apply — when this begins, the content
/// rows' own long-press menus are cancelled, and vice versa.
final class LongPressDragRecognizer: UIGestureRecognizer {
    enum Phase { case began, moved, ended }

    var minimumPressDuration: TimeInterval = 0.35
    var allowableMovement: CGFloat = 24
    var onPhase: ((Phase) -> Void)?

    private var liftTimer: Timer?
    private var lifted = false
    private var startPoint: CGPoint = .zero
    private weak var trackedTouch: UITouch?

    override func location(in view: UIView?) -> CGPoint {
        trackedTouch?.location(in: view) ?? super.location(in: view)
    }

    /// The coordinator found no card under the press — cancel this
    /// recognition and re-arm for the next touch.
    func abandon() {
        stopTimer()
        lifted = false
        state = .cancelled
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // Track the FIRST touch only; later fingers are ignored outright so
        // a stray second finger can't warp the drag. A stale reference from a
        // touch UIKit ended without telling us (touch objects are reused) is
        // treated as free.
        if let t = trackedTouch, t.phase != .ended, t.phase != .cancelled {
            for extra in touches where extra !== t { ignore(extra, for: event) }
            return
        }
        guard let touch = touches.first else { return }
        // A previous touch's timer may still be pending if UIKit ended it
        // without telling us — kill it so it can't fire an early lift for
        // THIS touch.
        stopTimer()
        trackedTouch = touch
        // Two fingers landing together: track the first, ignore the rest.
        for extra in touches where extra !== touch { ignore(extra, for: event) }
        startPoint = touch.location(in: nil)
        lifted = false
        // .common so the timer still fires while the run loop is in the
        // scroll's tracking mode — the whole point is lifting mid-scroll-idle.
        let timer = Timer(timeInterval: minimumPressDuration, repeats: false) { [weak self] _ in
            self?.lift()
        }
        RunLoop.main.add(timer, forMode: .common)
        liftTimer = timer
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        if lifted {
            state = .changed
            onPhase?(.moved)
            return
        }
        // Not lifted yet: drifting past the allowance means this is a scroll
        // or a swipe, not a press — fail and let the pan keep the touch.
        let p = touch.location(in: nil)
        if hypot(p.x - startPoint.x, p.y - startPoint.y) > allowableMovement {
            stopTimer()
            state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        stopTimer()
        if lifted {
            state = .ended
            onPhase?(.ended)
        } else {
            state = .failed
        }
        trackedTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        stopTimer()
        if lifted {
            state = .cancelled
            onPhase?(.ended)
        } else {
            state = .cancelled
        }
        trackedTouch = nil
    }

    override func reset() {
        super.reset()
        stopTimer()
        lifted = false
        trackedTouch = nil
    }

    private func lift() {
        guard trackedTouch != nil, !lifted else { return }
        lifted = true
        state = .began
        onPhase?(.began)
    }

    private func stopTimer() {
        liftTimer?.invalidate()
        liftTimer = nil
    }
}
