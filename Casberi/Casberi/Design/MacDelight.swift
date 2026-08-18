import SwiftUI

/// The Mac delight kit (2026-08-03) — the cursor half of the app's motion
/// grammar. The phone's juice is gesture-triggered (pull-to-refresh rain,
/// sheet physics, haptics), and none of those triggers exist under a pointer,
/// so the Mac build read as utile-but-flat while carrying the same delight
/// code. These are the pointer-native equivalents: the cursor gets an answer
/// everywhere it rests. Everything here compiles to `self` off Catalyst —
/// the phone pays nothing, not even a `Bool`.
///
/// Two laws carried over unchanged: motion answers something REAL (a cursor
/// arriving is real; nothing loops for decoration), and Reduce Motion stills
/// all of it.
///
/// ## The vocabulary (2026-08-17)
///
/// Until this date the kit was two modifiers applied at FOUR sites total, and
/// the gap that left was not "too little juice" — it was that hover said the
/// same thing everywhere. `dsHover` rides ~70 surfaces and renders one system
/// highlight on all of them, so a picture, a tappable card and a plain row all
/// answered the cursor identically. On a pointer machine that identity is the
/// bug: hover is the only channel a Mac has for "what IS this thing" before
/// you commit to a click, and spending it uniformly wastes it.
///
/// So the treatments are a closed set, one per surface CLASS, and a surface
/// wears exactly one:
///
///     row      → dsHover() alone            the system highlight, nothing more
///     card     → dsHover() + macHoverLift() a tappable tile rises to meet you
///     media    → dsHover() + macHoverBloom() a picture notices you
///     icon     → dsTooltip("…")             an unlabelled control says its name
///
/// **A fifth row was attempted and MEASURED AWAY (2026-08-17): there is no
/// cursor SHAPE available to this app.** The obvious answer to "this control
/// leaves the app" is the pointing-hand cursor, and SwiftUI does have
/// `pointerStyle(.link)` — on macOS 15 and visionOS only. It does not exist in
/// the iOS SwiftUI interface, which is what Mac Catalyst compiles against, so
/// the call is `cannot find 'pointerStyle' in scope` rather than a graceful
/// no-op (measured: zero occurrences in
/// `iPhoneOS.sdk/…/SwiftUI.swiftinterface`). Written down so the next person
/// reaching for it spends a doc-read rather than a build: reaching a real
/// cursor from Catalyst means `UIPointerInteraction`, whose iPad shapes do not
/// include a pointing hand either. Until something changes, "this leaves the
/// app" is carried by the tooltip's own words, which is why several of them
/// begin "Open in …".
///
/// **Never two motion treatments on one element.** Lift and bloom both animate
/// on the same trigger, so an element wearing both scales AND rises against a
/// doubled shadow — which reads as a bug rather than as emphasis. `dsHover` is
/// the one thing that composes with everything, because it is the system's
/// highlight rather than motion of ours.
///
/// The distinction between card and media is what the element IS, never how
/// big it is: a room-head figure is a card (you click it to go somewhere), a
/// contact-sheet thumbnail is media (the picture is the point). When a tile is
/// genuinely both — a media row you also click — it is a CARD, because lift
/// answers the click affordance and bloom answers the picture, and the click
/// is the thing the cursor is deciding about.
///
/// Enforced by `scripts/mac-pointer-audit.py`, which fails the build on a
/// doubled treatment and on an icon-only control with no tooltip inside a file
/// that tooltips its other ones — the "completeness within an opted-in file"
/// shape, chosen over a whole-tree sweep because a lint that cries wolf gets
/// turned off within a week.

extension View {
    /// A row lifting toward the cursor: a 1pt rise plus a deepened ambient
    /// shadow, layered over the system hover highlight (`dsHover`) the
    /// surface already wears. The shadow rides the composited view — the
    /// path `Glass.swift` deliberately avoids for card surfaces because it
    /// rasterizes content offscreen — affordable HERE because at most one
    /// row hovers at a time and at rest the color is `.clear`, so the render
    /// server has nothing to cast.
    func macHoverLift() -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(MacHoverLift())
        #else
        self
        #endif
    }

    /// A thumbnail blooming gently under the cursor — the whisper of a peek,
    /// not the peek itself (the tap still opens the thing; this only says
    /// the picture noticed you).
    func macHoverBloom() -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(MacHoverBloom())
        #else
        self
        #endif
    }

}

#if targetEnvironment(macCatalyst)
private struct MacHoverLift: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: hovering ? -1 : 0)
            .shadow(color: .black.opacity(hovering ? 0.35 : 0),
                    radius: hovering ? 12 : 0, y: hovering ? 5 : 0)
            .onHover { over in
                guard !reduceMotion else { return }
                withAnimation(DS.Motion.standard) { hovering = over }
            }
    }
}

private struct MacHoverBloom: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.05 : 1)
            .shadow(color: .black.opacity(hovering ? 0.4 : 0),
                    radius: hovering ? 10 : 0, y: hovering ? 4 : 0)
            // The bloomed thumb rises over its row neighbours instead of
            // sliding under the next row's text.
            .zIndex(hovering ? 1 : 0)
            .onHover { over in
                guard !reduceMotion else { return }
                withAnimation(DS.Motion.standard) { hovering = over }
            }
    }
}
#endif

/// The window answering a drag (capture: drop) — a soft tint glow breathing
/// in from the edges while a drop would land, gone the frame it wouldn't.
/// State feedback, never decoration (the color rule: this is the tint
/// carrying "release lands here"), and a glow, not a hairline — the stroke
/// exists only to be blurred into a field.
///
/// Cross-platform on purpose: `dropDestination`'s `isTargeted` fires for an
/// iPad inter-app drag and an in-app drag too, and the promise is the same
/// everywhere. It simply happens that only a Mac/iPad ever sees it.
struct DropGlow: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if active {
                // The faint field — the page acknowledging the drag at all.
                DS.tint.opacity(0.05)
                // The edge glow — a wide blurred band hugging the window
                // bounds, where "into this window" reads strongest.
                Rectangle()
                    .strokeBorder(DS.tint.opacity(0.45), lineWidth: 3)
                    .blur(radius: 8)
                Rectangle()
                    .strokeBorder(DS.tint.opacity(0.25), lineWidth: 1.5)
                    .blur(radius: 2)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : DS.Motion.standard, value: active)
    }
}
