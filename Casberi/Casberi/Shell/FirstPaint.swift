import SwiftUI
import UIKit

/// The first PAINTED frame, as a signal launch work can wait for (2026-09-06).
///
/// **Why "ready" was the wrong gate.** `launchTimer init→ready` fires at
/// ~1.2s, and the first pixel arrived at ~2.9s (measured on a recording,
/// identical on the pre-change baseline) — because the activation sweeps
/// start at "ready" ON THE MAIN ACTOR and the first commit queues behind
/// them: a SwiftData fetch decoding transformable attributes under
/// `performAndWait` was 61% of the main thread in that window (sampled).
/// Nothing in that work is visible. So it waits for the first frame instead:
/// `mark()` is called one run-loop turn after the shell's root view has laid
/// out in a window — the turn after layout is the turn after the commit that
/// carried it — and every deferred sweep `await`s `painted()`.
///
/// **What this does not do:** it does not make the sweeps cheaper, and it
/// does not touch anything the first frame itself needs (the store, the
/// feed's first query). It moves work that was in FRONT of the paint to
/// behind it. Measured before and after in prd §621's third amendment.
@MainActor
enum FirstPaint {
    private(set) static var isPainted = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    /// The shell's root has been laid out and the commit displayed.
    static func mark() {
        guard !isPainted else { return }
        isPainted = true
        #if DEBUG
        if LaunchClock.reports {
            let ms = Int(Date().timeIntervalSince(LaunchClock.start) * 1000)
            NSLog("[Casberi] launchTimer init→firstPaint %dms", ms)
        }
        #endif
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    /// Suspends until the first frame has been painted; returns at once after.
    static func painted() async {
        if isPainted { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Mounted once in `RootShell.shellBase`'s background: reports the first
/// layout in a window, then marks the paint one run-loop turn later.
struct FirstPaintMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> Marker { Marker() }
    func updateUIView(_ uiView: Marker, context: Context) {}

    final class Marker: UIView {
        private var armed = false
        override func layoutSubviews() {
            super.layoutSubviews()
            guard !armed, window != nil, bounds.width > 0 else { return }
            armed = true
            // The next turn of the run loop is after this transaction's
            // commit — the frame that carried this layout is on screen.
            DispatchQueue.main.async {
                Task { @MainActor in FirstPaint.mark() }
            }
        }
    }
}
