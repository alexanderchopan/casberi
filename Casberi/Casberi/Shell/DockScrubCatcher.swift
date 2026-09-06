import SwiftUI
import UIKit

/// The dock's press-and-slide input (2026-09-05): hold a chip for a beat, then
/// drag along the strip and the chip under the finger lifts and names itself;
/// let go to choose it. The one dock behaviour worth borrowing on a phone, and
/// the answer to thumb occlusion — the finger covers exactly the mark it is
/// choosing, so the name floats above the slab instead (`DockScrubCaption`).
///
/// **UIKit, on the strip's own scroll view, for the arbitration.** A SwiftUI
/// `LongPressGesture().sequenced(before: DragGesture())` on content inside a
/// `ScrollView` has three parties to settle with — the scroll's pan, the chip
/// buttons' presses, and the drag — and this codebase has measured twice that
/// a SwiftUI drag in scroll content beats the scroll outright
/// (`PageSwipeCatcher`'s doc, `DeckPanCatcher`'s). A `UILongPressGestureRecognizer`
/// gets all three for free from UIKit's exclusivity: it recognises only after
/// the finger has held still for `minimumPressDuration`, so a quick tap is the
/// button's and a quick swipe is the scroll's; and the moment it begins, the
/// pan (still `.possible`, since the finger has not moved) fails and the
/// button's touch is cancelled (`cancelsTouchesInView`), so a scrub can never
/// also scroll the strip or fire the chip it started on.
///
/// **Attached to the scroll view, found by walking UP from the content** — the
/// marker sits in the content `HStack`'s background, so its superview chain
/// reaches the `UIScrollView` that hosts it. That is the deck's own pattern,
/// and the reason it was wrong for the PAGER (the recognizer died with the
/// transitioning room) does not apply here: the strip never transitions.
///
/// **Delivered from the recognizer's own handlers, never target-action** — a
/// stock recognizer on SwiftUI-owned views transitions state correctly but its
/// target-action fires only intermittently (the Home board's lesson, CLAUDE.md
/// gotchas). `state`'s own setter is the one place every transition passes.
///
/// Locations are in the scroll view's bounds space, which for a `UIScrollView`
/// is CONTENT space — the same frame the strip records its chips in — and the
/// catcher hands back a converter to window space for the caption.
struct DockScrubCatcher: UIViewRepresentable {
    /// Checked at begin time — false and the press never begins.
    let enabled: () -> Bool
    /// The press landed: the finger's content-space point, and a converter
    /// from a content-space x to window space.
    let began: (_ at: CGPoint, _ toWindowX: @escaping (CGFloat) -> CGFloat) -> Void
    let moved: (_ at: CGPoint) -> Void
    /// `true` = the finger lifted (choose); `false` = cancelled (let go).
    let ended: (_ commit: Bool) -> Void
    /// ANY finger over the strip, content space, nil when it lifts (2026-09-05,
    /// user: "as user drags fingers over the chips and scrolls on them they
    /// should enlarge like a dock does") — the magnification wave rides this,
    /// so it plays under a scroll, a tap and a scrub alike. Delivered by a
    /// recognizer that never recognises (`Track`), so it takes nothing from
    /// the pan or the buttons.
    var finger: (_ at: CGPoint?) -> Void = { _ in }

    func makeUIView(context: Context) -> Marker {
        let v = Marker()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.enabled = enabled
        v.began = began
        v.moved = moved
        v.ended = ended
        v.finger = finger
        return v
    }

    func updateUIView(_ v: Marker, context: Context) {
        v.enabled = enabled
        v.began = began
        v.moved = moved
        v.ended = ended
        v.finger = finger
    }

    /// A recognizer that only WATCHES: it reports every touch's location and
    /// never leaves `.possible`, so UIKit's arbitration ignores it entirely —
    /// the scroll's pan, the chips' buttons and the scrub's press all see the
    /// same touches they always did.
    final class Track: UIGestureRecognizer {
        var onFinger: ((CGPoint?) -> Void)?
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            onFinger?(location(in: view))
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            onFinger?(location(in: view))
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            onFinger?(nil)
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            onFinger?(nil)
        }
    }

    final class Press: UILongPressGestureRecognizer {
        var onBegan: ((CGPoint) -> Void)?
        var onMoved: ((CGPoint) -> Void)?
        var onEnded: ((Bool) -> Void)?

        override var state: UIGestureRecognizer.State {
            didSet {
                switch state {
                case .began:
                    onBegan?(location(in: view))
                case .ended:
                    onEnded?(true)
                case .cancelled, .failed:
                    if oldValue == .began || oldValue == .changed { onEnded?(false) }
                default:
                    break
                }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesMoved(touches, with: event)
            if state == .began || state == .changed { onMoved?(location(in: view)) }
        }
    }

    final class Marker: UIView, UIGestureRecognizerDelegate {
        var enabled: (() -> Bool)?
        var began: ((CGPoint, @escaping (CGFloat) -> CGFloat) -> Void)?
        var moved: ((CGPoint) -> Void)?
        var ended: ((Bool) -> Void)?
        var finger: ((CGPoint?) -> Void)?
        private var press: Press?
        private var track: Track?
        private weak var host: UIScrollView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfNeeded()
        }

        private func attachIfNeeded() {
            if window == nil {
                if let g = press { host?.removeGestureRecognizer(g) }
                if let t = track { host?.removeGestureRecognizer(t) }
                press = nil
                track = nil
                host = nil
                return
            }
            guard press == nil else { return }
            var walk: UIView? = superview
            while let cur = walk, !(cur is UIScrollView) { walk = cur.superview }
            guard let scroll = walk as? UIScrollView else { return }
            let g = Press()
            // 0.4s, not 0.22 (2026-09-06, user: "the dock sometimes becomes
            // unresponsive"): a finger that RESTS a quarter second before
            // scrolling became a scrub, and the strip stopped moving under
            // it. A scrub is a deliberate hold; a scroll that starts slowly
            // is not. The 10pt allowance still fails the press the moment
            // the finger moves before the hold is up.
            g.minimumPressDuration = 0.4
            g.allowableMovement = 10
            g.delegate = self
            g.onBegan = { [weak self, weak scroll] p in
                guard let scroll else { return }
                // A press does NOT cancel the scroll's pan on its own
                // (measured 2026-09-05: recognizers on one view have no
                // exclusivity between them, so a scrub rubber-banded the
                // strip under the finger). Disabling scrolling cancels the
                // pan at once; it comes back when the finger lifts.
                scroll.isScrollEnabled = false
                self?.began?(p) { x in scroll.convert(CGPoint(x: x, y: 0), to: nil).x }
            }
            g.onMoved = { [weak self] p in self?.moved?(p) }
            g.onEnded = { [weak self, weak scroll] commit in
                scroll?.isScrollEnabled = true
                self?.ended?(commit)
            }
            scroll.addGestureRecognizer(g)
            press = g
            let t = Track()
            t.cancelsTouchesInView = false
            t.delaysTouchesBegan = false
            t.delaysTouchesEnded = false
            t.delegate = self
            t.onFinger = { [weak self] p in self?.finger?(p) }
            scroll.addGestureRecognizer(t)
            track = t
            host = scroll
        }

        override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g === press else { return true }
            return enabled?() ?? false
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            g === track
        }
    }
}
