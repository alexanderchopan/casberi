import SwiftUI
import Observation

/// Shell chrome state — scrolling down minimizes the bottom bar (labels fold,
/// the glass tightens); scrolling up blooms it back. Chrome yields to content;
/// the glass visibly reforms (iOS 26 grammar).
@Observable
final class ShellChrome {
    /// Read by `AgentBar` (its words fold, the glass hugs its two controls) and
    /// by `SourceChips` + the strip's top padding (56→48 chips, s6→s2 of air).
    ///
    /// This was written by every feed page and read by NOBODY from the day the
    /// tab bar it was built for was dropped (2026-07-13) until 2026-07-30 — the
    /// doc comment above described a behaviour the app hadn't had in months,
    /// while each page still paid for the scroll observer that computed it.
    var minimized = false
    /// When `minimized` last flipped — see `minimizesChrome`'s settle window.
    /// Observation-ignored on purpose: it is written from a scroll callback,
    /// and an observable write there would invalidate every reader of this
    /// object on every fold.
    @ObservationIgnored var chromeSettledAt: TimeInterval = 0

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

    /// The agent rose to be TYPED IN, not to deliver something (2026-07-30) —
    /// set by the bar's magnifier, consumed by the composer, which focuses the
    /// field on open instead of landing on the day brief. Deliberately not an
    /// `askRequest` of its own: there is no query yet, and the whole point of
    /// the Find door is that nothing runs until the person says what they want.
    var focusDraftOnOpen = false

    /// The whisper's title, mid-flight (2026-07-22, prd §167a) — set the
    /// instant the capsule is tapped, so a proxy title can mount in
    /// RootShell's OWN composerOpen-driven transaction (the same transaction
    /// that already morphs the bar into the risen surface), rather than
    /// waiting for the real masthead, which doesn't exist until `commit()`
    /// actually runs — a good 400ms+ later, well after the rise transition
    /// has already finished. Cleared by RootShell on a short timer once the
    /// real masthead has had time to mount and take over the geometry pairing.
    var risingBriefTitle: String?

    /// The day, for the detail pane's RESTING state (2026-07-31) — the same
    /// `DayBrief` the whisper capsule composes, published UNGATED.
    ///
    /// The capsule is once-a-day by ruling (§165: it's a delivery, and a
    /// delivery that repeats is noise). The pane is not a delivery — it is up
    /// to 560pt of the widest column in the app, standing empty for the whole
    /// session behind one placeholder sentence, and §249 already ruled that
    /// the agent's room leads with the day. So the pane at rest leads with it
    /// too, every open, and simply says nothing on a day with nothing to say
    /// (`DayBrief.whisper` composes nil — the honesty law: no manufactured
    /// news). `RootShell.refreshWhisper` writes it from the corpus walk it
    /// already pays for; the once-a-day stamp still gates the capsule alone.
    var paneBrief: DayBrief.Whisper?

    /// The FAB lives on MainSurface's root now (it belongs to Home/Feed, not
    /// to pushed rooms or forms) — bumping this asks RootShell, which still
    /// owns the sheet, to open the composer.
    var composerRequest = 0
    func openComposer() { composerRequest += 1 }

    /// The sources tray, asked for without the hold (2026-07-31). The tray's
    /// only trigger was a 0.45s press on the agent bar — a gesture with no
    /// visible affordance, which a phone can teach through repetition and a
    /// mouse simply cannot: click-and-wait is not something anyone tries. So
    /// the same tray hangs off the bar's right-click menu and off the View
    /// menu (⌘0, continuing the ⌘1–⌘9 chip run), and the hold is unchanged.
    var sourcesRequest = 0
    func openSources() { sourcesRequest += 1 }

    /// Find — the composer raised straight into a typed search, nothing
    /// running until the person types (§215). One verb because three doors now
    /// reach it: the bar's magnifier, the bar's right-click menu, and Mac's
    /// ⌘F. The two-statement spelling was already drifting into copies.
    func openFind() {
        focusDraftOnOpen = true
        openComposer()
    }

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

    /// The chip strip's CURRENT order, mirrored here so Mac's ⌘1–⌘9 can read
    /// it (2026-07-28) — `MainSurface.chipLabels` depends on the live corpus
    /// (`@Query`) and `ChipMemory`'s tap-learning, neither of which the
    /// Commands layer (outside the view hierarchy) can reach directly.
    /// Position-based like Safari/Chrome's numbered tabs, not identity-based:
    /// ⌘3 is "whatever's third right now", so a re-sort doesn't strand the
    /// shortcut on a chip that moved. "All" is always first, so ⌘1 is always
    /// valid; MainSurface keeps this in sync via `.onChange(of: chipLabels)`.
    var chipOrder: [String] = ["All"]

    // MARK: - The keyboard walk (Mac, 2026-07-31)

    /// The rows the ACTIVE feed page is showing, as ids only — the list half
    /// of list+detail, walkable from the keyboard (↑/↓ move, Return opens,
    /// Escape closes the pane). A two-pane app you cannot arrow through reads
    /// as a port however good its chrome is; this is the gap the 2026-07-28
    /// Mac pass left.
    ///
    /// **Ids, never models.** A `[Thing]` parked on a long-lived object is the
    /// 2026-07-24 crash class by construction — every bridge heal deletes rows
    /// on the main context while this is held. A `String` can't trap, so the
    /// walk carries row ids and the feed page (which has live models anyway)
    /// resolves one only at the moment it opens it. They are ROW ids, matching
    /// `FeedScreen.FeedRow.id` and every `ForEach` key in the feed, so the
    /// scroll target and the list's identity are one value — see
    /// `FeedScreen.walkRowIDs` for why the order is the rendered rows and not
    /// the corpus.
    ///
    /// Written by the active `FeedScreen`, which only compiles this on Mac.
    var walkOrder: [String] = []

    /// The row the keyboard has landed on. nil = nothing selected yet, which
    /// is the resting state — the first ↓ selects the first row rather than
    /// the app pre-selecting something the person didn't ask for.
    var walkSelected: String?

    /// Bumped by the Open command; the active feed page opens `walkSelected`
    /// through its own `openThing` (so the pane/sheet split stays in one
    /// place). A counter rather than a flag, for the same reason
    /// `composerRequest` is one: two Returns in a row are two opens.
    var walkOpenPulse = 0

    /// Something is raised over the shell — the risen agent, the sources tray,
    /// a deep-linked thing or person, the onboarding cover. Written by
    /// `RootShell` only, as one expression over every presentation it owns.
    var walkModalOpen = false

    /// A sheet raised by the feed itself (a thing, a token, a market book).
    /// Written by the active `FeedScreen` only. Separate from `walkModalOpen`
    /// because it has a different owner, not because it means anything
    /// different — and it matters most exactly where the pane doesn't exist: a
    /// Mac window under `PadLayout.minWidthForPane` opens every row as a sheet.
    var walkSheetOpen = false

    /// A pushed room stands on top of the feed. Written by `MainSurface` only.
    /// Settings and every bridge setup form are full of text fields, and a menu
    /// item holding a bare Return or ↓ would take those keys away from them — a
    /// disabled menu item's key equivalent falls through to the responder
    /// chain, an enabled one does not. Three flags with one writer each rather
    /// than one Bool three views race to set.
    var walkInPushedRoom = false

    /// Whether the walk commands are live at all. Mac-only (there is no menu
    /// bar to hold them elsewhere), never over anything raised or pushed, and
    /// never with nothing to walk. This is the single gate — when it is false
    /// the menu items disable, which is what actually hands ↑/↓/Return back to
    /// whatever should have had them.
    var canWalk: Bool {
        DS.isMac && !walkModalOpen && !walkSheetOpen && !walkInPushedRoom
            && !walkOrder.isEmpty
    }

    /// Move the selection by `delta`, clamped at both ends — a walk that
    /// wrapped would silently jump a reader from the newest thing to the
    /// oldest. With nothing selected, the first step lands on the first row
    /// going down and the last going up.
    func walkStep(_ delta: Int) {
        guard canWalk else { return }
        guard let current = walkSelected,
              let index = walkOrder.firstIndex(of: current) else {
            walkSelected = delta > 0 ? walkOrder.first : walkOrder.last
            return
        }
        let next = index + delta
        guard walkOrder.indices.contains(next) else { return }
        walkSelected = walkOrder[next]
    }

    /// Open whatever is selected. The "Open Item" command disables itself when
    /// nothing is (so Return falls through to the responder chain in exactly
    /// that state), which is why this guards rather than selecting a fallback.
    func walkOpen() {
        guard canWalk, walkSelected != nil else { return }
        walkOpenPulse += 1
    }

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
            // A fold CHANGES the top inset, and changing a scroll view's inset
            // reports back here as motion. The 60pt floor already prevents the
            // pathological case (a fold can only happen mid-content, where the
            // offset isn't re-clamped), but this settle window makes it
            // structural rather than incidental: for one animation's length
            // after a toggle, the chrome ignores what its own toggle did.
            let now = Date.timeIntervalSinceReferenceDate
            guard now - chrome.chromeSettledAt > DS.Motion.duration + 0.1 else { return }
            let down = new > old && new > 60
            if chrome.minimized != down {
                chrome.chromeSettledAt = now
                withAnimation(DS.Motion.standard) { chrome.minimized = down }
            }
        }
    }
}
