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

    /// The FAB lives on MainSurface's root now (it belongs to Home/Feed, not
    /// to pushed rooms or forms) — bumping this asks RootShell, which still
    /// owns the sheet, to open the composer.
    var composerRequest = 0
    func openComposer() { composerRequest += 1 }

    /// Bumped by every pull-to-refresh on the main surface (Home board or
    /// feed alike — the per-tab distinction died with the tabs). MainSurface
    /// hangs the refresh delight off it: the avatar door's spin (TopDoors,
    /// restored 2026-07-14 — the tab-drop rewire had orphaned it) and the
    /// berry rain (BerryRain, user ask same day).
    var refreshPulse = 0

    /// A thing ARRIVED while the person watched (a bridge sync, a pull, a
    /// share landing) — the source's chip does one catch bob: the capture
    /// flight's landing beat, generalized to everything that lands (delight
    /// pass 2026-07-13). First-ever thing from a source also blooms its hue
    /// across the header — the moment a new pipe actually flows.
    var arrivedChip: String?
    var arrivedTick = 0
    /// Per-label bloom counters — monotonic per chip, so one source's bloom
    /// never reverts another's coin-flip trigger (review catch 2026-07-13:
    /// a single shared bloomChip made chip X's trigger string change when
    /// chip Y bloomed later).
    var bloomTicks: [String: Int] = [:]
    func chipCaught(_ label: String, firstEver: Bool = false) {
        arrivedChip = label
        arrivedTick += 1
        if firstEver {
            bloomTicks[label, default: 0] += 1
        }
    }

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
    /// `active: false` mutes the observer without unmounting it — the feed
    /// pager keeps neighbour pages alive (2026-07-16), and three scroll
    /// observers writing one shared `chrome.minimized` means an off-screen
    /// page settling at offset 0 can un-minimize the chrome while you scroll
    /// the visible one.
    func minimizesChrome(_ chrome: ShellChrome, active: Bool = true) -> some View {
        onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y
        } action: { old, new in
            guard active else { return }
            guard abs(new - old) > 4 else { return }   // ignore jitter
            let down = new > old && new > 60
            if chrome.minimized != down {
                withAnimation(DS.Motion.standard) { chrome.minimized = down }
            }
        }
    }
}
