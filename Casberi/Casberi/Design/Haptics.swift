import SwiftUI
import Observation

/// The haptic layer — feel routed through tokens like every other value.
/// Grammar: selection ticks for choosing (tabs, filters, chips); light impact
/// for toggles (pin); success/failure for a write's outcome, fired ONLY by
/// `ShellChrome.flash(tone:)` so the buzz and the words naming it can never
/// drift apart (no felt outcome with nothing on screen to explain it, no
/// silent failure); a firmer impact for picking up a board card, distinct
/// from the ticks a drag makes crossing slots. Sparingly — one animation per
/// moment applies to the fingers too.
///
/// Feel rides SwiftUI's `.sensoryFeedback` (§16): each call bumps a counter
/// on the bus, and `dsSensoryFeedback()` declares the counter → feedback
/// mapping. `DSHaptic` stays as the call-site grammar, so a moment still reads
/// `DSHaptic.success()` where it happens.
///
/// **Attach it once PER PRESENTATION, not once per app** (2026-08-01). The
/// counter is global but the mapping is a view modifier, so it plays only where
/// it is attached — and a `.sheet` covers the view the root attached it to.
/// For a year it was on `RootShell`'s body alone, which meant every haptic
/// fired from inside a raised tray bumped its counter into silence: the sources
/// tray's cells ticked nothing, while the hold that opened it (fired from the
/// root, before any sheet existed) felt correct. That asymmetry is the tell.
/// `DSTray` now carries its own, which covers every tray in the app by design
/// law. A new full-screen presentation that is NOT a tray needs its own too.
///
/// Doubling is not the risk it looks like: the root's copy is exactly the one
/// that goes quiet under a presentation, so the two can't both fire.
@Observable
final class HapticBus {
    static let shared = HapticBus()
    var selection = 0
    var tap = 0
    var success = 0
    var failure = 0
    var lift = 0
    private init() {}
}

enum DSHaptic {
    /// Choosing among peers: tab switch, filter cell, chip.
    static func selection() { HapticBus.shared.selection += 1 }

    /// A state toggle landing: pin, theme swatch.
    static func tap() { HapticBus.shared.tap += 1 }

    /// A write completed. Called by `ShellChrome.flash(tone: .success)` —
    /// reach for that at the call site instead of this directly, so the
    /// buzz always rides with the toast that explains it.
    static func success() { HapticBus.shared.success += 1 }

    /// A write failed, honestly. Called by `ShellChrome.flash(tone: .failure)`.
    static func failure() { HapticBus.shared.failure += 1 }

    /// Picking up a board card — heavier than the selection ticks the same
    /// drag makes crossing slots, so the pickup itself is felt.
    static func lift() { HapticBus.shared.lift += 1 }
}

extension View {
    /// Attach once at the shell root — the app's whole haptic grammar,
    /// declared in one place.
    func dsSensoryFeedback() -> some View {
        self
            .sensoryFeedback(.selection, trigger: HapticBus.shared.selection)
            .sensoryFeedback(.impact(weight: .light), trigger: HapticBus.shared.tap)
            .sensoryFeedback(.success, trigger: HapticBus.shared.success)
            .sensoryFeedback(.error, trigger: HapticBus.shared.failure)
            .sensoryFeedback(.impact(weight: .medium), trigger: HapticBus.shared.lift)
    }
}
