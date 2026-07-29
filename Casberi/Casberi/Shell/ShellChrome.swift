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

    /// The crown pour's hue override (prd §159, 2026-07-21). nil = Casberi's
    /// own tint, the permanent field; the Wallet feed sets a scoped wallet's
    /// face tint here while you stand in that wallet, so the whole crown —
    /// chips included — re-tints to the identity you're inside. Written by
    /// the active feed page, rendered by MainSurface; always reset by the
    /// next page's landing, so a stale hue can't outlive its room.
    var pourHue: Color?

    /// A surface asked the composer to run an ask (the weekend cover's week
    /// synthesis, prd 54) — RootShell opens the bubble on set; the composer
    /// consumes the query and sends it through the real answer path.
    var askRequest: String?
    func ask(_ query: String) { askRequest = query }

    /// The whisper's title, mid-flight (2026-07-22, prd §167a) — set the
    /// instant the capsule is tapped, so a proxy title can mount in
    /// RootShell's OWN composerOpen-driven transaction (the same transaction
    /// that already morphs the bar into the risen surface), rather than
    /// waiting for the real masthead, which doesn't exist until `commit()`
    /// actually runs — a good 400ms+ later, well after the rise transition
    /// has already finished. Cleared by RootShell on a short timer once the
    /// real masthead has had time to mount and take over the geometry pairing.
    var risingBriefTitle: String?

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
    /// The hue the NEXT `refreshPulse` bump should rain in — a specific
    /// source's own brand hue when the pull happened inside its feed (set by
    /// FeedScreen's `.refreshable`, cleared to nil for "All") or a moment's
    /// own source (set by MainSurface's SourceMoments drain). nil rains the
    /// app's default berry blue (delight pass 2026-07-21).
    var refreshHue: Color? = nil

    /// Mac's ⌘R (Mac polish, 2026-07-28): a trackpad's overscroll gesture is
    /// the only trigger `.refreshable` gives Catalyst, and unlike a real
    /// finger pull it isn't reliably discoverable with a mouse — this is the
    /// guaranteed-reachable twin. FeedScreen observes it and runs the exact
    /// same refresh `.refreshable` runs (not just the delight half of it).
    var refreshRequest = 0
    func requestRefresh() { refreshRequest += 1 }

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

    /// A toast's outcome — `.success`/`.failure` fire the matching haptic
    /// (§ Haptics: the buzz rides WITH the words, never alone) so a call site
    /// can't buzz success and forget to say so, or fail silently. `.neutral`
    /// (the default) is for toasts that aren't reporting a write's outcome
    /// (an informational note, a read, a reversible toggle) — those keep
    /// whatever haptic their own gesture already fired, if any.
    enum Tone { case neutral, success, failure }

    func flash(_ text: String, tone: Tone = .neutral, action: ToastAction? = nil, seconds: Double = 2) {
        switch tone {
        case .neutral: break
        case .success: DSHaptic.success()
        case .failure: DSHaptic.failure()
        }
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

/// Mac menu bar commands (2026-07-28) live at the App/Scene level, outside
/// the view hierarchy RootShell's `chrome` (a per-window `@State`, not a
/// `.shared` singleton like `HomeRoute`/`FeedFilter`) is injected into — a
/// `FocusedValue` is the correct bridge back down to it, rather than making
/// transient UI state a global singleton just for this.
private struct ShellChromeFocusedKey: FocusedValueKey {
    typealias Value = ShellChrome
}
extension FocusedValues {
    var shellChrome: ShellChrome? {
        get { self[ShellChromeFocusedKey.self] }
        set { self[ShellChromeFocusedKey.self] = newValue }
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
