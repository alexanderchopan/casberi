import SwiftUI

/// A forward 3D coin-flip for an icon — one full rotation about the horizontal
/// (X) axis, so the top tips away and rolls back around like a flipped coin,
/// never a flat clock/counter-clock z-spin. Played once when the view appears
/// and again whenever `trigger` changes: switching a feed's source flips that
/// source's icon; opening a thing sheet flips its header icon. A little
/// perspective gives it real depth. Off under Reduce Motion (the icon just
/// sits, no rotation) — motion is delight, never load-bearing.
private struct CoinFlipEffect<T: Equatable>: ViewModifier {
    let trigger: T
    @State private var angle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func flip() {
        guard !reduceMotion else { return }
        // 360 ≡ 0 visually, so snapping the reset is invisible; the animation
        // then carries one clean forward turn. easeOut-ish spring decelerates
        // into rest, the way a coin settles — high damping keeps it from
        // wobbling past the full turn.
        angle = 0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { angle = 360 }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .onAppear(perform: flip)
            .onChange(of: trigger) { _, _ in flip() }
    }
}

extension View {
    /// One forward coin-flip on appear, and again whenever `trigger` changes.
    func coinFlip<T: Equatable>(trigger: T) -> some View {
        modifier(CoinFlipEffect(trigger: trigger))
    }
}
