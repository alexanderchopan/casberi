import SwiftUI
import UIKit

/// The edge swipe back, on a screen whose system back button is hidden
/// (prd §767).
///
/// SwiftUI's `navigationBarBackButtonHidden(true)` also disables UIKit's
/// interactive pop, and §767 hides that button on every pushed screen because
/// the dock's leading seat is the back door. This probe hands the pop gesture a
/// delegate that allows it whenever there is a frame to pop.
///
/// **One shared delegate, never one per screen.** A gesture's `delegate` is
/// weak: a delegate owned by the probe would die with the popped screen, and a
/// pop gesture with no delegate at the ROOT of a stack starts a pop with
/// nothing under it, which freezes the stack. The shared object lives for the
/// process and says no at the root.
///
/// Not an extension on `UINavigationController`: UIKit implements the gesture
/// delegate privately, and an `@objc` method added in a Swift extension would
/// replace its implementation for every recognizer it owns.
struct DSSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ controller: Probe, context: Context) {}

    final class Probe: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let pop = navigationController?.interactivePopGestureRecognizer else { return }
            pop.delegate = SwipeBackDelegate.shared
            pop.isEnabled = true
        }
    }
}

@MainActor
private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        var responder: UIResponder? = gestureRecognizer.view
        while let next = responder {
            if let nav = next as? UINavigationController {
                // A swipe during a push or pop is the other freeze.
                return nav.viewControllers.count > 1 && nav.transitionCoordinator == nil
            }
            responder = next.next
        }
        return false
    }
}
