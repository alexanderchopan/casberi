import SwiftUI

/// HOLD TO PEEK (2026-08-27, prd §501) — press and hold a withheld figure and
/// it reads for as long as you hold it.
///
/// The reasoning for the reveal being global rather than per-figure, and for it
/// never being written down, lives on `BalancePrivacy.peeking`. This file is
/// only the gesture.
///
/// **A `LongPressGesture` with `minimumDuration: 0`, not `onLongPressGesture`.**
/// The convenience modifier fires its action once the press LANDS and gives no
/// callback on release, so a peek built on it would reveal and never re-mask.
/// What is wanted is the pressing STATE, which is `updating` on a continuous
/// gesture, and its `onEnded`/cancel path resets automatically — including when
/// the finger slides off or the view is torn down mid-press, which is the case
/// a hand-rolled `@State` flag gets wrong.
///
/// **It never blocks the scroll.** `minimumDuration` is 0 and the gesture
/// carries no drag, so a scroll that begins on the figure cancels it and the
/// figure re-masks — which is correct, and is why this is not `simultaneous`.
///
/// **It is a no-op when nothing is hidden**: the gesture is not attached at
/// all, so a wallet with the setting off keeps exactly the hit-testing it had.
/// That is also the §83 rail — a hold that does nothing on most installs is a
/// dead control, and this one simply is not there.
private struct HoldToPeek: ViewModifier {
    @State private var privacy = BalancePrivacy.shared
    @GestureState private var pressing = false

    func body(content: Content) -> some View {
        content
            .gesture(privacy.hidden
                     ? LongPressGesture(minimumDuration: 0, maximumDistance: 12)
                         .updating($pressing) { _, state, _ in state = true }
                     : nil)
            .onChange(of: pressing) { _, now in
                // Written to the store rather than kept locally: the whole
                // screen's figures answer to it, and `@GestureState` resets
                // itself on cancel, so this can never latch on.
                privacy.peeking = now
                if now { DSHaptic.tap() }
            }
            // The mask swapping for a figure is a VALUE change, not an
            // entrance, so `MicroMotion`'s environment-reading rule applies and
            // the fade is short enough to read as the number being uncovered
            // rather than as an animation of its own.
            .animation(.easeOut(duration: 0.15), value: privacy.peeking)
    }
}

extension View {
    /// Press and hold this figure to read it while balances are hidden.
    /// Nothing at all when the setting is off.
    func holdToPeek() -> some View { modifier(HoldToPeek()) }
}
