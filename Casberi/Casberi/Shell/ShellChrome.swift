import SwiftUI
import Observation

/// Shell chrome state — scrolling down minimizes the bottom bar (labels fold,
/// the glass tightens); scrolling up blooms it back. Chrome yields to content;
/// the glass visibly reforms (iOS 26 grammar).
@Observable
final class ShellChrome {
    var minimized = false

    /// The one transient message surface — the glass toast above the bar.
    /// Any screen can flash an outcome ("On your list", "Copied", a denial);
    /// the shell renders it, so feedback looks the same everywhere.
    var toast: String?
    /// An optional action riding the toast ("Undo" on a drop-capture). Cleared
    /// with the toast.
    var toastAction: ToastAction?

    struct ToastAction {
        let label: String
        let run: () -> Void
    }

    /// The capture flight (§1 polish): a proxy card flies from the capture
    /// point to the Feed tab. RootShell renders it; saves set it.
    struct Flight: Identifiable {
        let id = UUID()
        let kind: ThingKind
        let title: String
    }
    var flight: Flight?

    /// Bumped when a flight lands — the target chip pulses once on change.
    var landedPulse = 0

    /// The "All" chip's frame in global space, reported by SourceChips so the
    /// flight knows where to land.
    var feedTabFrame: CGRect = .zero

    /// Bumped when the active chip is tapped again — the surface pops
    /// everything (pushed screens, sheets) back to its root (the tab era's
    /// "re-tap to pop" habit, now the "re-tap the active chip" habit).
    var popHome = 0

    /// A surface asked the composer to run an ask (the weekend cover's week
    /// synthesis, prd 54) — RootShell opens the bubble on set; the composer
    /// consumes the query and sends it through the real answer path.
    var askRequest: String?
    func ask(_ query: String) { askRequest = query }

    func flash(_ text: String, action: ToastAction? = nil, seconds: Double = 2) {
        // Replacing an in-flight toast crossfades (id change), never stacks.
        withAnimation(DS.Motion.standard) {
            toast = text
            toastAction = action
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation(DS.Motion.standard) {
                if toast == text {
                    toast = nil
                    toastAction = nil
                }
            }
        }
    }
}

extension View {
    /// Attach to a screen's ScrollView: reports scroll direction to the shell.
    func minimizesChrome(_ chrome: ShellChrome) -> some View {
        onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y
        } action: { old, new in
            guard abs(new - old) > 4 else { return }   // ignore jitter
            let down = new > old && new > 60
            if chrome.minimized != down {
                withAnimation(DS.Motion.standard) { chrome.minimized = down }
            }
        }
    }
}
