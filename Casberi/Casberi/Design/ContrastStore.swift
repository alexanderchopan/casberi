import SwiftUI
import Observation

/// Increase Contrast (Settings › Accessibility › Display & Text Size), mirrored
/// into the token layer so `DS`'s text ramp can answer it.
///
/// Why a store and not `@Environment(\.colorSchemeContrast)`: the ramp lives on
/// `DS`, a plain enum of static vars, which has no environment to read. It
/// already tracks appearance the same way — through an `@Observable` singleton
/// (`ThemeStore.shared`) — so reading `ContrastStore.shared.increased` inside a
/// view body registers the same dependency and repaints every token consumer
/// when the person flips the switch mid-session.
@Observable
final class ContrastStore {
    static let shared = ContrastStore()

    /// True when the person has asked the system for higher contrast.
    private(set) var increased: Bool = UIAccessibility.isDarkerSystemColorsEnabled

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                // Assigning through the @Observable property is what invalidates
                // the views; the value is read off the accessibility API rather
                // than toggled, so a redundant notification can't desync it.
                self?.increased = UIAccessibility.isDarkerSystemColorsEnabled
            }
    }
}
