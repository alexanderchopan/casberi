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
