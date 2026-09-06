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
    /// The dock's own four (2026-09-06, the haptic grammar pass) — see
    /// `DSHaptic.snap/spring/fly/pour`.
    var snap = 0
    var spring = 0
    var fly = 0
    var pour = 0
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

    // MARK: - The dock's grammar (2026-09-06)
    //
    // The dock is the signature interaction (prd §620/§621), and until this
    // pass its four moments all felt the same `selection` tick or nothing:
    // the fold settling, a folder springing up, a room card flying off, the
    // pull-to-refresh rain. Four moments, four feels, each lighter or softer
    // in proportion to what the eye sees — a snap is small and crisp, a
    // spring is soft, a fly is the heaviest thing the dock does, a pour is
    // soft and a beat long. None of them replaces a tick that names a
    // CHOICE (a chip, a venue): those stay `selection`.

    /// The fold reached an end — the dock is down, or up again.
    static func snap() { HapticBus.shared.snap += 1 }
    /// A folder sprang out of its chip.
    static func spring() { HapticBus.shared.spring += 1 }
    /// A room card left the screen — the swipe committed.
    static func fly() { HapticBus.shared.fly += 1 }
    /// The refresh rain dealt.
    static func pour() { HapticBus.shared.pour += 1 }
}

/// `dsSensoryFeedback()` behind a condition, for a view that is sometimes the
/// presentation and sometimes rendered inside somebody else's (2026-08-16).
///
/// It exists because the choice cannot be made with an `if` around the
/// modifier: two branches of a `ViewBuilder` are two different view types, so
/// SwiftUI tears down and rebuilds the whole subtree when the flag changes —
/// on `ThingSheetView` that would drop every `@State` on the sheet. A
/// `ViewModifier` keeps one identity and turns the listener off inside it.
struct SheetHaptics: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(trigger: HapticBus.shared.selection) { _, _ in
                active ? .selection : nil
            }
            .sensoryFeedback(trigger: HapticBus.shared.tap) { _, _ in
                active ? .impact(weight: .light) : nil
            }
            .sensoryFeedback(trigger: HapticBus.shared.success) { _, _ in
                active ? .success : nil
            }
            .sensoryFeedback(trigger: HapticBus.shared.failure) { _, _ in
                active ? .error : nil
            }
            .sensoryFeedback(trigger: HapticBus.shared.lift) { _, _ in
                active ? .impact(weight: .medium) : nil
            }
            .sensoryFeedback(trigger: HapticBus.shared.snap) { _, _ in
                active ? .impact(weight: .light, intensity: 0.55) : nil
            }
            .sensoryFeedback(trigger: HapticBus.shared.spring) { _, _ in
                active ? .impact(flexibility: .soft, intensity: 0.7) : nil
            }
            .sensoryFeedback(trigger: HapticBus.shared.fly) { _, _ in
                active ? .impact(weight: .medium, intensity: 0.85) : nil
            }
            .sensoryFeedback(trigger: HapticBus.shared.pour) { _, _ in
                active ? .impact(flexibility: .soft, intensity: 0.5) : nil
            }
    }
}

/// THE HAPTIC LISTENER, AS ITS OWN LEAF (2026-09-06, the dock's perf pass).
///
/// `.sensoryFeedback(trigger:)` READS its counter when the body carrying it is
/// evaluated, so attaching the whole grammar to `RootShell`'s body made the
/// shell observe all nine counters — and every tick then invalidated the root.
/// That is not a rare path: a scrub fires `DSHaptic.selection()` for each chip
/// the finger crosses, so sliding across eight chips rebuilt the entire shell
/// eight times in the middle of the gesture it was meant to make feel good.
///
/// A zero-size leaf hears the same counters and is the only thing that
/// re-renders. It must still sit INSIDE the presentation it serves — the
/// per-presentation rule below is unchanged, and this is what `RootShell`
/// mounts instead of carrying the modifiers itself.
struct DSHapticSink: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .dsSensoryFeedback()
    }
}

extension View {
    /// Attach once at the shell root — the app's whole haptic grammar,
    /// declared in one place. Prefer mounting `DSHapticSink` over putting this
    /// on a big body: see that view's note.
    func dsSensoryFeedback() -> some View {
        self
            .sensoryFeedback(.selection, trigger: HapticBus.shared.selection)
            .sensoryFeedback(.impact(weight: .light), trigger: HapticBus.shared.tap)
            .sensoryFeedback(.success, trigger: HapticBus.shared.success)
            .sensoryFeedback(.error, trigger: HapticBus.shared.failure)
            .sensoryFeedback(.impact(weight: .medium), trigger: HapticBus.shared.lift)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.55),
                             trigger: HapticBus.shared.snap)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7),
                             trigger: HapticBus.shared.spring)
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.85),
                             trigger: HapticBus.shared.fly)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5),
                             trigger: HapticBus.shared.pour)
    }
}
