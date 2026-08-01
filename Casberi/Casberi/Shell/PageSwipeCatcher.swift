import SwiftUI
import UIKit

/// The feed pager's swipe input (prd §265) — ONE UIKit pan on the WINDOW,
/// mounted once by the shell.
///
/// Two designs died before this one, both measured:
/// - A SwiftUI `DragGesture` — plain OR simultaneous, any minimumDistance —
///   beats the `List`'s vertical pan entirely (the deck measured it
///   2026-07-16; `DeckPanCatcher`'s doc). A gesture cannot do this job.
/// - A per-room recognizer on each List's own scroll view (the deck's pattern)
///   attaches into the page-transition subtree: while a switch animates, the
///   outgoing and incoming rooms coexist, and the new room's walk kept finding
///   the DYING room's scroller — the recognizer died with it and the next
///   swipe hit nothing. An attach that races every transition is the §261
///   class of bug wearing UIKit clothes.
///
/// The window dies with the scene and never transitions, so this attaches
/// exactly once. A window-level recognizer sees every touch; UIKit's
/// exclusivity machinery still applies, so when this begins it cancels the
/// scroll pan underneath — a page turn and a scroll can't share one finger.
///
/// Three gates keep it honest, all checked at begin time:
/// - Clearly horizontal (the deck's velocity test), or the scroll keeps it.
/// - `enabled()` — the shell's own modal/sheet/pushed-room flags — because a
///   window recognizer would otherwise turn pages UNDER a sheet or a pushed
///   settings form.
/// - Not inside a nested horizontal scroller (a cover strip, a media shelf):
///   that strip owns its own axis.
struct PageSwipeCatcher: UIViewRepresentable {
    /// Checked at begin time — false means the pager is covered.
    let enabled: () -> Bool
    /// +1 = the next room (leftward pull), -1 = the previous.
    let step: (Int) -> Void

    func makeUIView(context: Context) -> Marker {
        let v = Marker()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.enabled = enabled
        v.step = step
        return v
    }

    func updateUIView(_ v: Marker, context: Context) {
        v.enabled = enabled
        v.step = step
    }

    /// Delivers from its OWN touch handlers, never target-action — a stock
    /// recognizer on SwiftUI-owned views transitions state correctly but its
    /// target-action fires only intermittently (the Home board's
    /// drag-to-reorder lesson, 2026-07-13; CLAUDE.md gotchas).
    final class Pan: UIPanGestureRecognizer {
        var onEnded: ((_ translation: CGFloat, _ predicted: CGFloat) -> Void)?

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            let wasActive = state == .began || state == .changed
            let t = translation(in: view).x
            // A quarter second of release velocity — the deck's number — so a
            // short fast flick still turns the page.
            let predicted = t + velocity(in: view).x * 0.25
            super.touchesEnded(touches, with: event)
            if wasActive { onEnded?(t, predicted) }
        }
    }

    final class Marker: UIView, UIGestureRecognizerDelegate {
        var enabled: (() -> Bool)?
        var step: ((Int) -> Void)?
        private var pan: Pan?
        private weak var host: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let w = window, pan == nil {
                let g = Pan()
                g.delegate = self
                g.onEnded = { [weak self] t, predicted in
                    // Far enough to be meant — by distance, or by a flick's
                    // predicted distance.
                    guard abs(t) > 60 || abs(predicted) > 140 else { return }
                    self?.step?((abs(predicted) > abs(t) ? predicted : t) < 0 ? 1 : -1)
                }
                w.addGestureRecognizer(g)
                pan = g
                host = w
            } else if window == nil, let g = pan {
                host?.removeGestureRecognizer(g)
                pan = nil
            }
        }

        override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g === pan, let p = pan else { return true }
            guard enabled?() ?? false else { return false }
            // Clearly horizontal, or the scroll keeps it (the deck's gate).
            let v = p.velocity(in: p.view)
            guard abs(v.x) > abs(v.y) * 1.4 else { return false }
            // Inside a nested horizontal scroller, that strip owns the pull.
            if let w = host, let hit = w.hitTest(g.location(in: w), with: nil) {
                var walk: UIView? = hit
                while let cur = walk, cur !== w {
                    if let s = cur as? UIScrollView,
                       s.contentSize.width > s.bounds.width + 1 { return false }
                    walk = cur.superview
                }
            }
            return true
        }
    }
}
