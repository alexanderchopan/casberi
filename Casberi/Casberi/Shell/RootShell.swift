import SwiftUI
import SwiftData
import CoreSpotlight
import WidgetKit
import UIKit

/// The shell (2026-07-13, drastic restructure: no tabs). `MainSurface` is the
/// one destination — a fixed chip header over a body that swaps between the
/// board (Pinned) and the feed. The composer is a FAB floating over it,
/// content scrolls under the floating stack. The phone frame from the
/// prototype is demo chrome and is dropped — the shell fills the device
/// (brief §7).
struct RootShell: View {
    @Environment(\.modelContext) private var modelContext
    @State private var bridges = BridgeStore()
    @State private var chrome = ShellChrome()
    /// Read-only, for the Mac window title (see the `onChange` below) — the
    /// feed's own scope, the same value the chip strip is bound to.
    /// Everything this WINDOW owns (multi-window, 2026-08-02) — navigation,
    /// the source filter and the pane's selection. `@State`, so a second
    /// window gets its own; see `SceneState` for why the `.shared` statics
    /// these replaced were deleted rather than kept as a convenience.
    @State private var sceneState = SceneState()
    private var filter: FeedFilter { sceneState.filter }
    /// THIS window's scene, read off the view's own UIWindow rather than
    /// asked of `UIApplication` (see `WindowSceneReader`).
    @State private var windowScene: UIWindowScene?
    @State private var draft = ""
    @State private var composerOpen = false
    /// Session-scoped only, never persisted — the bar's pulse (ruling 6)
    /// stops once the agent has been raised AT ALL this launch. Distinct
    /// from `KeptAskStore`'s own per-ask, persisted "seen" dot.
    @State private var agentEverOpened = false
    /// The whisper capsule's line (prd §165) — non-nil only between the
    /// first foreground of a day that has something to say and the agent's
    /// next rise. The once-a-day gate is persisted (`whisper.lastShownDay`);
    /// this is just the visible text.
    @State private var whisper: DayBrief.Whisper?
    @State private var deepLinkThing: Thing?
    /// `casberi://person/<Source>/<handle>` — the profile card, by name.
    @State private var deepLinkPerson: SocialProfile?
    @AppStorage("onboarded") private var onboarded = false
    /// Mirrors `DemoMode.isActive` so the standing demo banner appears and
    /// disappears with the mode — see the banner's own gate in `shellBase`.
    @AppStorage("demo.mode.active") private var demoActive = false
    /// Set by the onboarding CTA, consumed by the cover's onDismiss: the
    /// catalog push must wait until the cover is fully DOWN. Pushing while
    /// the cover still stood raced its dismissal, and SwiftUI intermittently
    /// drops a navigationDestination push made under a presented cover — the
    /// same drop class as `-openSettings` at launch (audit 2026-07-13); the
    /// user saw it as "Browse the catalog sometimes doesn't work" (2026-07-17).
    /// Where the onboarding cover said to land once it lifts (§217). Nil means
    /// the feed — right whenever the fork's tap already produced something to
    /// look at, which is the whole point of the fork.
    @State private var landingNode: HomeRoute.Node?
    @AppStorage("privacy.hidePreviews") private var hidePreviews = true
    @AppStorage("firstThingSaved") private var firstThingSaved = false
    /// The bar's teaching grace (2026-07-31). `AgentBar` rests COMPACT now —
    /// but a bar that has never been used should still say what it is once, so
    /// it wears its own name until the verb it names has been used on this
    /// device, then hugs its mark forever. Persisted, unlike the
    /// session-scoped `agentEverOpened` above: the words are a first-run
    /// explanation, and re-explaining on every cold launch is what made them
    /// permanent furniture in the first place.
    ///
    /// It tracks the TRAY since §390, not the agent — the words name the tap,
    /// so the tap is what spends them. Gating on the agent would have left the
    /// grace standing for everyone who never finds the hold, which is a label
    /// that outlives its own explanation.
    @AppStorage("sources.everOpened") private var sourcesEverOpened = false
    /// Every source at once (`SourcesTray`) — raised by holding the agent bar.
    /// Never set directly by a door: they all go through `openSources()`, so
    /// the tray's own feel can't depend on which one you reached it by.
    @State private var sourcesOpen = false
    /// A drag is over the window and a drop would land (one flag per payload
    /// type `dropDestination` accepts) — drives `DropGlow`'s edge answer.
    @State private var dropTargetedURL = false
    @State private var dropTargetedText = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasBeenActive = false
    /// Debounce for `handleActivation`'s two Mac launch-time doors — see its
    /// note. Distant past so the first activation always passes.
    @State private var lastActivation = Date.distantPast
    /// The last answer's grounding — a follow-up ("which ones were from
    /// Sam?") searches inside it instead of the whole corpus (2026-07-10).
    @State private var lastAnswerHits: [Thing] = []
    /// Whether the last answer was a NAMED ask, and if so whether it
    /// synthesized (2026-07-22, §176) — enables the "and bbc?" ellipsis
    /// follow-up to re-run the same shape with a new entity. nil = the last
    /// answer wasn't a named ask, so the ellipsis stays off.
    @State private var lastNamedAskSynth: Bool?
    /// A keyed conversation's prior turns (2026-07-21) — threaded into the
    /// next "Try with your key" so a keyed follow-up is understood in
    /// context, the same way the on-device model's own session is. Clears
    /// when the agent lowers (`onLowerAgent`), same lifecycle as every other
    /// per-conversation composer state.
    @State private var keyedHistory: [AgentTurn] = []
    @State private var redactNow = false
    /// iPad (2026-07-25). The floating agent cluster lives in THIS ZStack,
    /// which is deliberately outside `MainSurface`'s safe-area insets (ruling
    /// 6 — the bar rides every screen this app can push, not just the feed),
    /// so it has to restate the shell's two columns itself to float clear of
    /// them. `PadShellInsets` is where that arithmetic lives.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var shellWidth: CGFloat = 0
    private var padShell: PadShellInsets {
        // A PUSHED room (Apps, Settings, a bridge form) covers the detail
        // pane — the rail is outside the stack and survives, the pane is
        // inside it and doesn't. So the bar reserves the pane's space only
        // while the pane is actually on screen; otherwise it hangs left of
        // centre over a room that runs the full width beside the rail.
        PadShellInsets(regular: horizontalSizeClass == .regular,
                       width: shellWidth,
                       paneVisible: sceneState.route.path.isEmpty)
    }
    /// The bar↔surface morph (2026-07-20) — shared between `AgentBar` and
    /// `Composer`'s `glassNamespace`, both keying `matchedGeometryEffect` to
    /// the same `"agentMorph"` id.
    @Namespace private var agentMorph

    var body: some View {
        // THROWAWAY (2026-07-19): `-summonProto YES` swaps the whole shell for
        // the direction-F prototype. A full swap rather than a cover so the
        // real shell's chrome can't leak into it — delete this branch and
        // `SummonPrototype.swift` together when the experiment is settled.
        if UserDefaults.standard.bool(forKey: "summonProto") {
            // `dsColorScheme()` is not optional here: the branch sits ABOVE the
            // shell's own `.preferredColorScheme`, so without it every adaptive
            // token resolves against light traits and `DS.textPrimary` paints
            // black on the dark page (i.e. invisible).
            SummonPrototype().dsColorScheme()
        } else {
            shell
        }
    }

    /// The whisper's once-a-day gate (prd §165): compose the day brief on
    /// the first foreground of a calendar day, show it only when it has
    /// something to say, never twice in one day. Suppressed until onboarded
    /// (the cover is up; a whisper under it would be dead chrome).
    /// `-whisperProbe YES` bypasses the day stamp so the capsule verifies
    /// headlessly (pair with `-awayGap <hours>` for the landed count and
    /// `-seedWalletHistory` for the wallet fragment).
    @MainActor
    private func refreshWhisper(things: [Thing]) {
        guard onboarded else { return }
        var force = false
        #if DEBUG
        force = UserDefaults.standard.bool(forKey: "whisperProbe")
        #endif
        let today = Date.now.formatted(.iso8601.year().month().day())
        let dayKey = "whisper.lastShownDay"
        let capsuleDue = force || UserDefaults.standard.string(forKey: dayKey) != today
        // The pane's resting state leads with the day too (2026-07-31), on a
        // different clock: the capsule is a once-a-day DELIVERY, the pane is a
        // standing lead redrawn every open. Composing once serves both and is
        // what stops them ever disagreeing about what today was.
        //
        // But composing is not free — `DayBrief.lead` walks the window several
        // times and `walletMove` decodes every watched wallet's sample line —
        // so it happens only when someone will actually read the result. On a
        // phone (no pane, capsule already shown today) that is nobody, and the
        // pre-review cut paid for it on every single foreground.
        let paneReads = sceneState.detail.paneActive
        guard capsuleDue || paneReads else { return }
        let composed = DayBrief.whisper(things: things)
        if paneReads { chrome.paneBrief = composed }
        guard capsuleDue, let composed else {
            #if DEBUG
            if force && composed == nil { NSLog("[Casberi] whisper: (nothing to say)") }
            #endif
            return
        }
        UserDefaults.standard.set(today, forKey: dayKey)
        // …and the capsule stands down when the pane is already showing the
        // same line beside it (§248's own rule, one column over: three
        // controls for one screen, stacked, is duplication). The day stamp is
        // still spent — the delivery happened, the pane made it.
        guard !paneReads else { return }
        withAnimation(DS.Motion.standard) { whisper = composed }
        #if DEBUG
        NSLog("[Casberi] whisper: %@ | %@", composed.title, composed.detail)
        #endif
    }

    private var shell: some View {
        shellPhaseAware
        // The agent is a full-screen ZStack layer now (docs/agent-brief.md
        // ruling 3), rendered above in `shell`'s own ZStack — no more sheet.
        // A fresh composer open is a fresh answer conversation — drop the prior
        // transcript so one conversation's turns never bleed into the next
        // (ConversationModel). Follow-ups WITHIN this open carry context.
        // Anything raised over the shell owns the keyboard — see
        // `ShellChrome.canWalk`. A menu item holding a bare Return or ↓ would
        // take those keys away from a composer field, a tray, or a sheet's own
        // Escape otherwise. ONE expression over every presentation this view
        // owns, rather than a handler per flag each re-ORing the others.
        .onChange(of: composerOpen || sourcesOpen || deepLinkThing != nil
                  || deepLinkPerson != nil || !onboarded, initial: true) { _, modal in
            chrome.walkModalOpen = modal
        }
        .onChange(of: composerOpen) { _, open in
            if open {
                OnDeviceModel.resetConversation()
                agentEverOpened = true
                // The whisper's job is done however the agent rose — it
                // never returns until a new day has something to say.
                whisper = nil
                // Whatever the walk had selected belongs to the feed you just
                // left; coming back should not find a stale ring on a row.
                chrome.walkSelected = nil
            } else {
                // A safety clear, not the primary one (that's the guarded
                // timer at the tap site) — a fast close before the timer
                // fires must not leave a stale proxy title behind for the
                // NEXT rise to inherit.
                chrome.risingBriefTitle = nil
            }
        }
        #if targetEnvironment(macCatalyst)
        // The local MCP listener (2026-08-06) — Mac only, and only if the
        // person turned it on. `startIfEnabled` is a no-op otherwise, so the
        // default build opens no port at all.
        .task { MCPServer.shared.startIfEnabled() }
        #endif
        // A surface requested an ask (the weekend cover) — open the composer;
        // it consumes the query once it mounts (prd 54).
        .onChange(of: chrome.askRequest) { _, request in
            guard request != nil else { return }
            composerOpen = true
        }
        #if targetEnvironment(macCatalyst)
        // The window title says where you are (Mac polish, 2026-07-28) — it
        // said "Casberi" always, which wastes the one piece of Mac chrome
        // that iPhone has no equivalent of. `filter.source` is the exact
        // value the chip strip is already bound to, so this can't drift
        // from what the feed is actually showing.
        .onChange(of: filter.source, initial: true) { _, _ in
            updateMacWindowTitle()
        }
        #endif
        .dsSensoryFeedback()
        .environment(bridges)
        .environment(chrome)
        // Mac menu bar commands (2026-07-28) read `chrome` back through this
        // — see ShellChromeFocusedKey.
        .focusedSceneValue(\.shellChrome, chrome)
        // The three per-window stores, for screens (environment) and for the
        // menu bar (focused value — a command fires from outside every
        // window's hierarchy and must be told which window it meant).
        .environment(sceneState.route)
        .environment(sceneState.filter)
        .environment(sceneState.detail)
        .focusedSceneValue(\.sceneState, sceneState)
        .background(WindowSceneReader { scene in
            windowScene = scene
            applyMacWindowChrome(to: scene)
        })
        // The app-language override, applied to the whole tree: reading the
        // observable store here means picking a language repaints every `Text`
        // from its `.lproj` live, no relaunch (LanguageStore).
        .environment(\.locale, LanguageStore.shared.locale)
        // Mode is the person's; a chosen photo implies the dark treatment.
        // Mac follows the SYSTEM'S appearance instead (2026-07-28, user
        // ruling): forcing a mode is right on iOS, where there's no system
        // convention pulling the other way, but a light-mode Mac opening to
        // a forced-dark window is exactly the jarring "doesn't feel native"
        // gap Mac users notice first. `nil` means "inherit" — every
        // `Color.adaptive` call reads the ACTUAL rendered
        // `userInterfaceStyle` trait already (not this flag directly), so
        // the whole app's color system follows along with no other change.
        .preferredColorScheme(
            ProcessInfo.processInfo.isMacCatalystApp ? nil
                : (ThemeStore.shared.isLight && ThemeStore.shared.backgroundPhoto == nil ? .light : .dark)
        )
        // casberi:// deep links — widgets and App Intents route through these.
        // casberi://home|feed|account switch tabs; casberi://thing/latest opens
        // the newest thing's sheet (the widget-tap route).
        .onOpenURL { route($0) }
        .onAppear {
            // Landing (2026-07-13, simplified 2026-07-20 — the Pinned board
            // retired, docs/agent-brief.md rulings 11-12; reverted to
            // "always All" 2026-07-28 per user feedback — the §131 amendment
            // that persisted "wherever you left it" is undone). Deep links
            // and debug hooks below can still override this within the same
            // launch.
            // Honesty rule: if CasberiApp had to degrade the store open this
            // launch (SharedStore.containerWithFallback), say so once instead
            // of silently showing an empty/unsynced corpus.
            if let reason = SharedStore.degradeReason {
                chrome.flash(reason, tone: .failure, seconds: 4)
            }
            // Sync freshness (2026-07-28): CloudKit mirroring otherwise only
            // catches up on foreground — its silent push has nowhere to land
            // without a device token. This just asks for one; no alert/sound/
            // badge is requested and nothing is ever shown to the person
            // (Casberi never interrupts, by ruling) — it only lets a save on
            // another device reach this one sooner than the next launch.
            if SharedStore.cloudSyncActive {
                UIApplication.shared.registerForRemoteNotifications()
            }
            // Perf pass: log init→ready (first content appearance) once per
            // process. `ready` = this onAppear, i.e. the first frame's view tree
            // is assembled — read by scripts/perf.sh, not an in-app surface.
            // Always in DEBUG; in Release only under `-launchTimer YES`, so the
            // shipping build can be measured without ever logging for a real
            // person (see `LaunchClock.reports`).
            if !LaunchClock.didLog, LaunchClock.reports {
                LaunchClock.didLog = true
                let ms = Int(Date().timeIntervalSince(LaunchClock.start) * 1000)
                NSLog("[Casberi] launchTimer init→ready %dms", ms)
            }
            // Spotlight mirrors the store; launch reconciles (covers things
            // the share extension made while the app was closed). The fetch
            // reads the main-actor store, so it stays on the main actor — a
            // detached background task sharing this ModelContext races the
            // screens' own reads and crashes SwiftData. The CoreSpotlight
            // calls it makes are non-blocking, so this is cheap on main.
            Task { @MainActor in
                // Yield past the first frame (2026-07-24 perf): none of this
                // block is needed for the UI to function — Spotlight donation,
                // duplicate cleanup, and the one-time migrations are all
                // housekeeping. Letting the first paint land before this runs
                // on the main actor keeps cold launch snappy; it also widens
                // the gap before the dedupe delete (already crash-safe via the
                // KeyedThing value-keying) touches the store.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                // Every launch: Spotlight reconciles and CloudKit-merge
                // duplicates collapse (covers extension writes + sync merges).
                #if DEBUG
                LaunchPerf.time("SpotlightIndex.reindexAll") {
                    SpotlightIndex.reindexAll(context: modelContext)
                }
                LaunchPerf.time("SyncReconcile.dedupe") {
                    SyncReconcile.dedupeBySourceRef(context: modelContext)
                }
                #else
                SpotlightIndex.reindexAll(context: modelContext)
                SyncReconcile.dedupeBySourceRef(context: modelContext)
                #endif

                // One-time migrations run once per install (bump the version
                // when adding one) — steady-state launches skip the scans.
                let migrationsKey = "migrations.version"
                let migrationsCurrent = 6
                let migrationsStored = UserDefaults.standard.integer(forKey: migrationsKey)
                if migrationsStored < migrationsCurrent {
                    if migrationsStored < 1 {
                        // Migration v1 also purged sample things left by the retired
                        // demo-seed path; `Thing.isSample` is gone now (nothing set it
                        // true, and every container that reached v1 already purged),
                        // so lightweight migration simply drops the column.
                        // One-time rename (2026-07-06): voice notes' source is
                        // "Voice" now; older ones carried "You".
                        let stale = (try? modelContext.fetch(FetchDescriptor<Thing>(
                            predicate: #Predicate { $0.source == "You" }
                        ))) ?? []
                        for thing in stale where thing.kind == .voice {
                            thing.source = "Voice"
                        }
                        // One-time move (2026-07-07): voice audio used to live as
                        // loose files keyed by sourceRef; it belongs in the store
                        // so sync carries it. Load each file in, then remove it.
                        let voiceThings = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
                        for thing in voiceThings where thing.kind == .voice && thing.audio == nil {
                            guard let ref = thing.sourceRef,
                                  let url = VoiceCapture.audioURL(for: ref),
                                  let data = try? Data(contentsOf: url) else { continue }
                            thing.audio = data
                            try? FileManager.default.removeItem(at: url)
                        }
                        // One-time retitle (2026-07-07): early screenshot ingests
                        // carried the timestamp in the title — pure noise.
                        let noisy = (try? modelContext.fetch(FetchDescriptor<Thing>(
                            predicate: #Predicate { $0.title.starts(with: "Screenshot · ") }
                        ))) ?? []
                        for thing in noisy { thing.title = "Screenshot"; thing.embedding = nil }
                    }
                    if migrationsStored < 2 {
                        // One-time heal (2026-07-12): an earlier Apple Music artwork
                        // search took the top catalog hit blindly, so obscure tracks
                        // wore a stranger's cover ("Daddy Your Rose" → Nirvana). Clear
                        // stored art on every Apple Music thing so it reads as artless;
                        // the corrected title-matching search (AppleMusicIngest.ingest)
                        // re-resolves each on the next foreground — the right cover, or
                        // an honest glyph when no catalog match is trustworthy.
                        let music = (try? modelContext.fetch(FetchDescriptor<Thing>(
                            predicate: #Predicate { $0.source == "Apple Music" }
                        ))) ?? []
                        for thing in music { thing.previewImageURL = nil }
                    }
                    if migrationsStored < 3 {
                        // One-time rename (2026-07-13): the token-watch bridge is
                        // "Tokens" now, not "Dexscreener" — its chart blends three
                        // vendors (commit a2618a2). Things captured before the rename
                        // kept the old source and "dexscreener:" sourceRef prefix, so
                        // the feed still headed them "Dexscreener". Rewrite both.
                        let staleTokens = (try? modelContext.fetch(FetchDescriptor<Thing>(
                            predicate: #Predicate { $0.source == "Dexscreener" }
                        ))) ?? []
                        for thing in staleTokens {
                            thing.source = "Tokens"
                            if let ref = thing.sourceRef, ref.hasPrefix("dexscreener:") {
                                thing.sourceRef = "tokens:" + String(ref.dropFirst("dexscreener:".count))
                            }
                        }
                    }
                    if migrationsStored < 4 {
                        // One-time heal (2026-07-28): Day One backslash-escapes
                        // markdown-special punctuation ("4\.8"); the import never
                        // undid that until now. Re-clean what's already landed.
                        _ = DayOneImport.healEscapedText(context: modelContext)
                    }
                    if migrationsStored < 5 {
                        // One-time re-write (prd §277, 2026-08-02): keychain
                        // accessibility is fixed when an item is ADDED, so keys
                        // stored by an earlier build keep the old
                        // backup-restorable policy until they're written again —
                        // which, for a key you paste once, is never.
                        _ = TokenVault.migrateToDeviceOnly()
                    }
                    if migrationsStored < 6 {
                        // One-time re-source (2026-08-11, `SafeBridge`'s own
                        // top-of-file doc) — the Dexscreener→Tokens rename's
                        // shape, minus the ref rewrite: every already-landed
                        // Safe row carries a `wallet:safe*` ref that never
                        // changed, so only `.source` moves, from "Wallet" to
                        // `SafeBridge.sourceName`. Fetched by the plain,
                        // well-worn `source ==` equality and filtered on the
                        // ref prefix IN SWIFT rather than inside the
                        // predicate — `sourceRef` is optional, and this file
                        // has no precedent combining `?? ""` with
                        // `.starts(with:)` inside a `#Predicate`; a one-time
                        // migration is exactly the wrong place to be the
                        // first to find out that combination traps.
                        let wallet = (try? modelContext.fetch(FetchDescriptor<Thing>(
                            predicate: #Predicate { $0.source == "Wallet" }
                        ))) ?? []
                        for thing in wallet where thing.sourceRef?.hasPrefix("wallet:safe") == true {
                            thing.source = SafeBridge.sourceName
                        }
                    }
                    modelContext.saveHonestly()
                    UserDefaults.standard.set(migrationsCurrent, forKey: migrationsKey)
                }
            }
            // Warm the model at launch (non-blocking) so the first Ask doesn't
            // pay the one-time model load. Guarded so `-noPrewarm` can measure
            // the cold path.
            if !skipPrewarm { OnDeviceModel.prewarm() }
            #if DEBUG
            // The launch-arg connect-and-sync probes (-chatgptImport,
            // -tokenBridge, -fcName, -bskyHandle, -rssFeed) share one shape —
            // one dispatch table in ProbeHooks.
            ProbeHooks.runAll(context: modelContext)
            #endif
            #if DEBUG
            // `-demoEnter YES` — enter the demo headlessly, without walking
            // onboarding, for the screenshot pipeline and the screen-audit
            // skill (2026-08-07). Lives HERE rather than in `ProbeHooks`
            // because `DemoMode.begin` needs a `BridgeStore`, which that
            // file's dispatch table doesn't carry — every hook there gets
            // only `(String, ModelContext)`. Pours immediately rather than
            // waiting for the next activation, so one launch is enough.
            if UserDefaults.standard.bool(forKey: "demoEnter") {
                DemoMode.begin(store: bridges)
                Task { @MainActor in
                    await DemoMode.pourIfNeeded(context: modelContext)
                    NSLog("[Casberi] demoEnter: ready")
                }
            }
            // `-demoProbe YES` — one NSLog per fact, the `-todayProbe`
            // truncation lesson (a joined multi-line message gets cut by the
            // log reader). Waits a beat so a `-demoEnter` on the SAME launch
            // has landed its rows first.
            if UserDefaults.standard.bool(forKey: "demoProbe") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    let count = (try? modelContext.fetchCount(FetchDescriptor<Thing>())) ?? 0
                    NSLog("[Casberi] demoProbe| active=%@ hasSeen=%@ pending=%@ things=%d",
                          DemoMode.isActive ? "YES" : "NO",
                          DemoMode.hasSeen ? "YES" : "NO",
                          UserDefaults.standard.bool(forKey: "demo.mode.pourPending") ? "YES" : "NO",
                          count)
                    NSLog("[Casberi] demoProbe| seats=%d", bridges.bridges.count)
                    NSLog("[Casberi] demoProbe| keptAsks=%@",
                          KeptAskStore.shared.order.joined(separator: ", "))
                }
            }
            #endif
            // Debug hook: `simctl launch ... -deeplink casberi://feed` lands in
            // UserDefaults; routes without the system open-in dialog.
            #if DEBUG
            NSLog("[Casberi] On-device model: %@", OnDeviceModel.availabilityLine)
            if let raw = UserDefaults.standard.string(forKey: "deeplink"),
               let url = URL(string: raw) {
                UserDefaults.standard.removeObject(forKey: "deeplink")
                route(url)
            }
            // `-openThing "<title prefix>"` opens the newest thing whose title
            // starts with the prefix — the sheet-by-content route for headless
            // sheet checks (a UUID changes every install; a title doesn't).
            if let prefix = UserDefaults.standard.string(forKey: "openThing"),
               !prefix.isEmpty {
                let all = (try? modelContext.fetch(FetchDescriptor<Thing>(
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
                ))) ?? []
                let match = all.first { $0.title.hasPrefix(prefix) }
                // On iPad the pane is where a thing opens, so the hook has to
                // go there too — otherwise the probe verifies a route no tap
                // takes. It waits on the shell's first layout rather than a
                // magic delay: `paneActive` is written by `MainSurface` from
                // its own measured width, so before the first geometry pass
                // it reads false in a way that means "not measured", not "no
                // pane" — and the hook would take the sheet on a device that
                // has one.
                // `-openThingDelay <s>` re-fetches after a wait instead of
                // using the mount-time `all` above (2026-08-14). The fetch
                // above runs BEFORE any async seed lands, so pairing
                // `-openThing` with `-demoEnter` in ONE launch always logged
                // "no match" — and on the Mac the usual two-launch answer is
                // unavailable, because `-storeScratch` keys its directory to
                // the process id, so the second launch opens an empty store.
                // Used by scripts/mac-appstore-capture.sh so a source room's
                // detail pane shows that room's own thing rather than the
                // newest thing overall. The zero-delay path below is
                // deliberately left exactly as it was.
                let openDelay = UserDefaults.standard.double(forKey: "openThingDelay")
                if openDelay > 0 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(openDelay))
                        await sceneState.detail.awaitLayout()
                        let late = (try? modelContext.fetch(FetchDescriptor<Thing>(
                            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
                        ))) ?? []
                        guard let hit = late.first(where: { $0.title.hasPrefix(prefix) }),
                              hit.isLive else {
                            NSLog("[Casberi] openThing: no match for %@ (after %.1fs)",
                                  prefix, openDelay)
                            return
                        }
                        let inPane = sceneState.detail.present(hit)
                        if !inPane { deepLinkThing = hit }
                        NSLog("[Casberi] openThing: %@ (%@)", hit.title,
                              inPane ? "pane" : "sheet")
                    }
                } else {
                Task { @MainActor in
                    await sceneState.detail.awaitLayout()
                    guard let match, match.isLive else {
                        NSLog("[Casberi] openThing: no match for %@", prefix)
                        return
                    }
                    let inPane = sceneState.detail.present(match)
                    if !inPane { deepLinkThing = match }
                    NSLog("[Casberi] openThing: %@ (%@)", match.title,
                          inPane ? "pane" : "sheet")
                }
                }
            }
            // `-openSettings YES` pushes Settings. Lives HERE, not a screen's
            // own onAppear — content-first landing is now the ONLY landing
            // (the Pinned board it used to have to out-race retired
            // 2026-07-20), so there's only ever one surface to time against.
            // This onAppear runs after the whole tree mounts — same proven
            // timing as the `-deeplink` hook above.
            if UserDefaults.standard.bool(forKey: "openSettings") {
                sceneState.route.present(.settings)
            }
            // `-openSources YES` raises the sources tray, which is otherwise
            // reachable ONLY by a long press on the agent bar — a gesture no
            // headless run can make and no screenshot pass can stage. Added
            // 2026-08-16 while trying to answer whether `glassEffect` samples
            // a sheet's backdrop at all: that question can only be settled by
            // looking at the rendered panel, and there was no way to render it
            // without a human holding a finger down.
            if UserDefaults.standard.bool(forKey: "openSources") {
                openSources()
            }
            // `-openAppsDelay <s>` pushes the store after a delay — records
            // "tapping the grid door" (the zoom plays on the real push path).
            let appsDelay = UserDefaults.standard.double(forKey: "openAppsDelay")
            if appsDelay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(appsDelay))
                    withAnimation(DS.Motion.standard) { sceneState.route.present(.apps) }
                }
            }
            // `-berryPulse <s>` bumps the refresh pulse after a delay — plays
            // the pull-to-refresh delight (avatar spin + berry rain) without
            // a gesture, for headless verification and screen recordings.
            let berryDelay = UserDefaults.standard.double(forKey: "berryPulse")
            if berryDelay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(berryDelay))
                    chrome.refreshPulse += 1
                    NSLog("[Casberi] berryPulse: dealt")
                }
            }
            // `-groupProbe YES` — is the REAL app-group container reachable and
            // writable (scripts/verify-mac.sh). The check 22 Mac builds needed
            // and no gate had.
            //
            // Every Mac build ever shipped fell all the way down
            // `containerWithFallback`'s ladder to the EPHEMERAL in-memory store,
            // because the container was asked for by the unprefixed group id
            // that macOS does not grant (see `SharedStore.containerGroupID`).
            // Nothing a Mac user saved survived a relaunch. It was invisible
            // from outside — the app launches, paints, and behaves normally for
            // one session — and no gate could see it either, because
            // `verify-mac.sh` launches EVERY run with `-storeScratch YES`,
            // which opens a store at a temp path and never touches the group
            // container at all.
            //
            // So this probe deliberately runs ALONGSIDE `-storeScratch`, rather
            // than the gate dropping that flag: an un-scratched DEBUG launch
            // would open the REAL corpus of whoever is running the harness and
            // forward-migrate it (the whole reason `-storeScratch` exists), and
            // a check that endangers the daily driver's data is not one anybody
            // will keep running. The group id and its URL are independent of
            // which store file is opened, so probing them under scratch is both
            // safe and faithful: hand `containerURL` an id the sandbox never
            // granted and the write below fails, which is exactly the bug.
            //
            // Writes and deletes one empty file, so it proves the grant rather
            // than inferring it from a path that merely looks right — the whole
            // trap here is that the wrong path looks perfectly real until
            // something tries to write to it.
            if UserDefaults.standard.bool(forKey: "groupProbe") {
                let id = SharedStore.containerGroupID
                let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
                var writable = false
                if let url {
                    let probe = url.appendingPathComponent(".casberi-groupProbe")
                    writable = ((try? Data().write(to: probe)) != nil)
                    try? FileManager.default.removeItem(at: probe)
                }
                NSLog("[Casberi] groupProbe| id=%@ writable=%@ url=%@",
                      id, writable ? "YES" : "NO", url?.path ?? "nil")
            }
            // Debug hook (the Mac harness's screenshot, scripts/verify-mac.sh):
            // `-macSnapshot <name>` renders the key window as <name>.png after
            // `-snapshotDelay <s>` (default 4s) and NSLogs the full path for
            // the script to copy out. Exists because the Mac has no
            // `simctl io screenshot`, and `screencapture` needs a Screen
            // Recording grant a headless nightly can't click through — an app
            // rendering its own window needs no permission at all.
            //
            // It writes into the APP GROUP container, and that is load-bearing
            // rather than tidiness. The obvious home is
            // `FileManager.default.temporaryDirectory` — inside
            // `~/Library/Containers/com.casberi.app/Data`, which macOS TCC
            // protects as app data. An interactive terminal usually holds that
            // access, so the first version of this worked perfectly by hand
            // and then failed on the very first launchd run with
            // `cp: Operation not permitted` (2026-08-01). Measured from a real
            // LaunchAgent: app container read DENIED, group container read OK.
            // So the group container is the one directory both a sandboxed app
            // can write and an unattended job can read.
            //
            // The harness cannot DELETE these (group-container writes are
            // denied to it too), so names are reused and overwritten rather
            // than made unique — the set stays as small as the sweep's screen
            // list. Freshness is guaranteed by the caller waiting for THIS
            // run's "wrote" line, not by clearing the file first.
            if let snapName = UserDefaults.standard.string(forKey: "macSnapshot") {
                let snapDelay = UserDefaults.standard.double(forKey: "snapshotDelay")
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(snapDelay > 0 ? snapDelay : 4))
                    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
                            ?? scenes.first?.windows.first
                    else { NSLog("[Casberi] macSnapshot: no window"); return }
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    guard let data = image.pngData() else {
                        NSLog("[Casberi] macSnapshot: FAILED png encode"); return
                    }
                    // macOS resolves an app group ONLY by its team-prefixed id
                    // — the same divergence Casberi-Catalyst.entitlements
                    // documents for keychain groups. Handing `containerURL`
                    // the bare "group.com.casberi.app" here returned a path
                    // OUTSIDE the sandbox grant, so `createDirectory` was
                    // denied and the write failed with the memorably unhelpful
                    // "The file home.png doesn't exist" (2026-08-01). Try
                    // prefixed first, keep the bare id as the iOS-shaped
                    // fallback, and log whichever directory won so the next
                    // failure names itself instead of needing this rediscovered.
                    // Team-prefixed first (macOS), bare second (the iOS shape).
                    let groupIDs = ["35428TQK3S." + SharedStore.appGroup, SharedStore.appGroup]
                    let base = groupIDs.lazy
                        .compactMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
                        .first { FileManager.default.fileExists(atPath: $0.path) }
                    let dir = (base ?? FileManager.default.temporaryDirectory)
                        .appendingPathComponent("HarnessSnapshots")
                    do {
                        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        let url = dir.appendingPathComponent(snapName).appendingPathExtension("png")
                        try data.write(to: url)
                        NSLog("[Casberi] macSnapshot: wrote %@", url.path)
                    } catch {
                        NSLog("[Casberi] macSnapshot: FAILED dir=%@ %@", dir.path, error.localizedDescription)
                    }
                }
            }
            // Debug hook: `simctl launch ... -answerProbe "what did I save about work"`
            // runs the whole answer path (retrieve → on-device compose → doc)
            // and logs the composition + its latency, so it can be verified and
            // timed without the UI. `-probeDelay <s>` waits before the probe
            // (lets prewarm settle, to A/B warm vs `-noPrewarm` cold).
            if let q = UserDefaults.standard.string(forKey: "answerProbe") {
                let delay = UserDefaults.standard.double(forKey: "probeDelay")
                Task {
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    // Ensure the semantic index is built before the headless
                    // ask, so a probe verifies meaning-retrieval deterministically
                    // (the live app builds this on foreground instead).
                    await EmbeddingIndex.indexPending(context: modelContext)
                    let start = Date()
                    let doc = await answerDocument(q) { partial in
                        NSLog("[Casberi] answerProbe stream →\n%@", partial.joined(separator: "\n"))
                    }
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    NSLog("[Casberi] answerProbe(\"%@\") %dms →\n%@", q, ms, doc.joined(separator: "\n"))
                }
            }
            // Debug hook: `-homeInsightProbe YES` runs the on-device "Noticed"
            // line over the current corpus (bypassing the cache), logging the
            // candidates fed, the raw model text, and the post-guard result, so
            // the line's voice/quality/decline-rate can be sampled headlessly.
            if UserDefaults.standard.bool(forKey: "homeInsightProbe") {
                let delay = UserDefaults.standard.double(forKey: "probeDelay")
                Task { @MainActor in
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
                    let surfaced = Corpus.surfaced(all)
                        .sorted { $0.capturedAt > $1.capturedAt }
                    let line = await HomeInsightStore.shared.debugProbe(from: surfaced)
                    NSLog("[Casberi] homeInsightProbe result → %@", line ?? "NONE (declined)")
                }
            }
            // Debug hooks for the BYO-key path: `-byokKey <key>` stores a key
            // headlessly — an optional "provider:" prefix picks the agent
            // ("venice:vk-…"; bare keys stay Anthropic), "clear" removes every
            // provider's key. `-byokProbe "<query>"` runs the keyed answer
            // path and logs the doc — with a bogus key it verifies the honest
            // failure path without spending anything.
            if let raw = UserDefaults.standard.string(forKey: "byokKey") {
                if raw == "clear" {
                    AgentProvider.allCases.forEach { AgentKey.clear($0) }
                } else if let colon = raw.firstIndex(of: ":"),
                          let provider = AgentProvider(rawValue: String(raw[..<colon])) {
                    AgentKey.set(String(raw[raw.index(after: colon)...]), for: provider)
                } else {
                    AgentKey.set(raw, for: .anthropic)
                }
                let active = AgentKey.active
                NSLog("[Casberi] byokKey: configured=%d provider=%@ hint=%@",
                      AgentKey.isConfigured ? 1 : 0, active?.rawValue ?? "none",
                      active.map { AgentKey.hint($0) } ?? "")
            }
            // Debug hook: `-agentModel "<provider>:<model id>"` (or `clear`)
            // pins which model a provider answers with, so a model choice is
            // exercisable headlessly. Declared BEFORE every probe below —
            // hooks run in list order and each must read a store that is
            // already seeded.
            AgentModelStore.seedFromLaunchArgs()
            if let q = UserDefaults.standard.string(forKey: "byokProbe") {
                Task {
                    await EmbeddingIndex.indexPending(context: modelContext)
                    let start = Date()
                    let outcome = await keyedAnswerDocument(q)
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    switch outcome {
                    case .success(let answer):
                        // `rounds` is the field that separates the two shapes
                        // this path can now take — a single-shot summary of
                        // what it was handed, or a real tool loop that went
                        // looking. They produce identical-looking documents,
                        // so a doc dump alone cannot tell them apart.
                        NSLog("[Casberi] byokProbe(\"%@\") %dms model=%@ rounds=%d searchedWeb=%d pagesRead=%d images=%d →\n%@",
                              q, ms, (AgentKey.active?.model ?? "none"), answer.toolRounds,
                              answer.searchedWeb ? 1 : 0, answer.pagesRead, answer.imagesSeen,
                              answer.doc.joined(separator: "\n"))
                    case .failure(let failure):
                        NSLog("[Casberi] byokProbe(\"%@\") %dms failed=%@ → \"%@\"",
                              q, ms, String(describing: failure), failure.line)
                    }
                    // The receipt for whatever just happened, printed right
                    // after it — a keyed probe that answers and a keyed probe
                    // that fails both spend something, and the difference
                    // between them is exactly what this ledger exists to show.
                    for entry in AgentSpend.shared.snapshot() {
                        NSLog("[Casberi] agentSpend| %@ requests=%d toolRounds=%d tokens=%@ model=%@",
                              entry.provider, entry.requests, entry.toolRounds,
                              entry.tokenLine ?? "(not reported)", entry.model ?? "-")
                    }
                }
            }
            // Debug hook: `-spendProbe YES` dumps the key-spend ledger without
            // asking anything — one `agentSpend|` line per provider (the
            // `-todayProbe` truncation lesson). The only way to read what a
            // key has been spent on across launches, since the counts persist
            // and the answer path that writes them does not re-run.
            if UserDefaults.standard.bool(forKey: "spendProbe") {
                let entries = AgentSpend.shared.snapshot()
                NSLog("[Casberi] spendProbe: providers=%d requests=%d",
                      entries.count, AgentSpend.shared.totalRequests)
                for entry in entries {
                    NSLog("[Casberi] agentSpend| %@ requests=%d toolRounds=%d tokens=%@ cacheRead=%@ cacheWrite=%@ model=%@ reported=%@",
                          entry.provider, entry.requests, entry.toolRounds,
                          entry.tokenLine ?? "(not reported)",
                          entry.cachedInputTokens.map(String.init) ?? "(not reported)",
                          entry.cacheWriteTokens.map(String.init) ?? "(not reported)",
                          entry.model ?? "-",
                          entry.reportedUSD.map { String(format: "$%.4f", $0) } ?? "-")
                }
                // The month's ceiling beside the counts it governs (2026-08-20).
                // Printed even when unset, because "no cap" and "a cap we
                // couldn't evaluate" are different states that both leave the
                // librarian running, and only the second is worth chasing.
                NSLog("[Casberi] agentBudget| cap=%@ spentThisMonth=%@ baseline=%@ month=%@ pauses=%d",
                      AgentBudget.monthlyCap.map { AgentBudget.usd($0) } ?? "none",
                      AgentBudget.spentThisMonth.map { AgentBudget.usd($0) } ?? "(unknown)",
                      AgentBudget.baseline.map { AgentBudget.usd($0.usd) } ?? "(none)",
                      AgentBudget.baseline?.month ?? "-",
                      AgentBudget.pausesLibrarian(AgentBudget.measurableProvider) ? 1 : 0)
            }
            // Debug hook: `-agentBudgetCap <usd|clear>` sets the monthly
            // ceiling headlessly, so the pause branch is exercisable without
            // waiting for a real month of spending to accumulate. Declared
            // BEFORE `-librarianProbe` — hooks run in list order, and the
            // probe must read a store that is already seeded.
            if let raw = UserDefaults.standard.string(forKey: "agentBudgetCap") {
                AgentBudget.monthlyCap = raw == "clear" ? nil : Double(raw)
                NSLog("[Casberi] agentBudgetCap: cap=%@ spent=%@ pauses=%d",
                      AgentBudget.monthlyCap.map { AgentBudget.usd($0) } ?? "none",
                      AgentBudget.spentThisMonth.map { AgentBudget.usd($0) } ?? "(unknown)",
                      AgentBudget.pausesLibrarian(AgentBudget.measurableProvider) ? 1 : 0)
            }
            // Debug hook: `-chatTurnsProbe "<title prefix>"` reads a stored chat
            // transcript back as TURNS (`ChatTurns`) and NSLogs one
            // `chatTurn|` line each (the `-todayProbe` truncation lesson), then
            // the exchange pairing a keyed continuation would send as history.
            //
            // It exists because the transcript lives on `enrichedText`, which
            // is retrieval-only by the 2026-07-15 ruling and drawn by NOTHING —
            // so a chat that parses into twelve fabricated turns and one that
            // parses correctly are identical from every screen in the app. The
            // `parsed=0` case is the one to read carefully: it is CORRECT for
            // any row whose enrichedText this app didn't write as a
            // conversation, and a bug only for an imported chat.
            if let prefix = UserDefaults.standard.string(forKey: "chatTurnsProbe") {
                Task { @MainActor in
                    let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
                    guard let thing = all.filter({ $0.isLive && $0.title.hasPrefix(prefix) })
                        .sorted(by: { $0.capturedAt > $1.capturedAt }).first else {
                        NSLog("[Casberi] chatTurnsProbe: nothing titled \"%@\"", prefix)
                        return
                    }
                    let turns = ChatTurns.parse(thing.enrichedText)
                    let partial = ChatTurns.isPartial(parsed: turns,
                                                      messageCount: thing.messageCount)
                    NSLog("[Casberi] chatTurnsProbe: \"%@\" source=%@ stored=%d parsed=%d messageCount=%@ partial=%d",
                          thing.title, thing.source, thing.enrichedText?.count ?? 0,
                          turns.count, thing.messageCount.map(String.init) ?? "-",
                          partial ? 1 : 0)
                    for turn in turns.prefix(20) {
                        NSLog("[Casberi] chatTurn| %@%@ %@",
                              turn.isMine ? "→ " : "← ", turn.speaker,
                              String(turn.text.prefix(90)))
                    }
                    let (history, pending) = ChatTurns.exchanges(turns)
                    NSLog("[Casberi] chatTurnsProbe: exchanges=%d pending=%@",
                          history.count, pending.map { String($0.prefix(60)) } ?? "(none)")
                }
            }
            // Debug hook: `-webFetchProbe "<url>[,<url>]"` runs the page-reading
            // policy (`AgentWebFetch.fetchable`) over URLs WITHOUT asking
            // anything or spending a token — one `webFetch|` line per candidate
            // saying whether it would be shown to the agent and, when it
            // wouldn't, that it was refused. It exists because the whole
            // feature is invisible from outside: a link the policy drops and a
            // link the model simply chose not to read produce byte-identical
            // answers, and only this separates them.
            if let raw = UserDefaults.standard.string(forKey: "webFetchProbe") {
                let candidates = raw == "corpus"
                    ? (try? modelContext.fetch(FetchDescriptor<Thing>()))?
                        .prefix(400).compactMap { ThingLinks.canonicalLink($0.content) } ?? []
                    : raw.components(separatedBy: ",")
                NSLog("[Casberi] webFetchProbe: tool=%@ maxUses=%d maxContentTokens=%d candidates=%d",
                      AgentWebFetch.toolType, AgentWebFetch.maxUses,
                      AgentWebFetch.maxContentTokens, candidates.count)
                var shown = 0
                for candidate in candidates {
                    let verdict = AgentWebFetch.fetchable(candidate)
                    if verdict != nil { shown += 1 }
                    NSLog("[Casberi] webFetch| %@ → %@",
                          String(candidate.prefix(120)), verdict == nil ? "REFUSED" : "shown")
                }
                NSLog("[Casberi] webFetchProbe: shown=%d refused=%d",
                      shown, candidates.count - shown)
            }
            // Debug hook: `-agentCreditsProbe YES` runs OpenRouter's free
            // key-check read (`/v1/auth/key`, no tokens billed) with the
            // STORED key and NSLogs the credit-crossing decision (2026-08-09)
            // — the measure tool for a bridge that has never been checked
            // against a live key on this build host. An empty result has
            // three causes and only one is a bug: no OpenRouter key stored,
            // the key was rejected (same failure `-byokProbe` would show),
            // or the key genuinely carries no `limit` (an unlimited/free-tier
            // key — OpenRouter's own documented meaning for an absent field,
            // not a read failure).
            if UserDefaults.standard.bool(forKey: "agentCreditsProbe") {
                if !AgentKey.isConfigured(.openrouter) {
                    NSLog("[Casberi] agentCreditsProbe: no OpenRouter key stored — connect via -byokKey \"openrouter:<key>\"")
                } else if let key = TokenVault.get(AgentProvider.openrouter.vaultKey) {
                    Task {
                        let outcome = await AgentAnswer.check(key, provider: .openrouter)
                        NSLog("[Casberi] agentCreditsProbe: key check → %@", String(describing: outcome))
                        if let limit = OpenRouterCredits.limit, let remaining = OpenRouterCredits.remaining {
                            NSLog("[Casberi] agentCreditsProbe: limit=$%.2f remaining=$%.2f bucket=%@ (floor=%@)",
                                  limit, remaining, OpenRouterCredits.bucket ?? "none",
                                  limit >= OpenRouterCredits.largeLimitFloor
                                    ? "$\(OpenRouterCredits.lowAbsoluteFloor) absolute"
                                    : "\(Int(OpenRouterCredits.lowFraction * 100))% relative")
                        } else {
                            NSLog("[Casberi] agentCreditsProbe: no `limit` on this key (unlimited/free-tier — OpenRouter's own meaning) or unreadable")
                        }
                        await MainActor.run {
                            let existing = IngestSupport.existingSourceRefs(modelContext)
                            if let thing = OpenRouterCredits.drainPending(context: modelContext, existing: existing) {
                                NSLog("[Casberi] agentCreditsProbe: WOULD LAND → %@", thing.title)
                            } else {
                                NSLog("[Casberi] agentCreditsProbe: nothing to land (not low, or already alerted this crossing)")
                            }
                        }
                    }
                }
            }
            // Debug hook: `-librarianProbe YES` reports whether the keyed
            // librarian (prd §282's passes, run on a key) is reachable and how
            // much work is waiting — WITHOUT spending anything. `-librarianProbe
            // run` actually runs the catch-up pass, which bills real money, so
            // it is a different word rather than a flag: a probe that spends
            // on every headless run is one nobody can safely put in a sweep.
            //
            // The state line is the point. An empty result here has four
            // causes that render as one silence — no key, the toggle off, an
            // on-device model doing the work for free (the healthy case, and
            // NOT a bug), or genuinely nothing left to organize.
            if let mode = UserDefaults.standard.string(forKey: "librarianProbe") {
                Task { @MainActor in
                    let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
                    let weak = all.filter {
                        $0.isLive && $0.kind == .screenshot && $0.ocrAt != nil
                            && !$0.content.isEmpty && ScreenshotNaming.isWeak($0.title)
                    }.count
                    let threads = all.filter { $0.isLive && ThreadDigest.wants($0) }.count
                    NSLog("[Casberi] librarianProbe: onDevice=%d keyed=%d enabled=%d provider=%@ weakTitles=%d undigested=%d",
                          AgentLibrarian.deviceCanDoIt ? 1 : 0, AgentLibrarian.canRun ? 1 : 0,
                          AgentLibrarian.isEnabled ? 1 : 0,
                          AgentKey.active?.rawValue ?? "none", weak, threads)
                    guard mode == "run" else { return }
                    let caught = await AgentLibrarian.catchUp(context: modelContext)
                    NSLog("[Casberi] librarianProbe: named=%d digested=%d → \"%@\"",
                          caught.named, caught.digested, caught.line)
                }
            }
            // Debug hook: `-modelsProbe YES` asks every CONFIGURED provider
            // what models it offers and logs one `agentModel|` line each (plus
            // the count, since a list of 300 can't be logged whole). It exists
            // because a pinned model id fails as a `providerError(404)` that
            // the composer words as ordinary trouble — this is the read that
            // says whether the pin is still real.
            if UserDefaults.standard.bool(forKey: "modelsProbe") {
                Task {
                    for provider in AgentKey.configured {
                        guard let key = TokenVault.get(provider.vaultKey) else { continue }
                        let models = await AgentModels.list(provider: provider, key: key)
                        guard let models else {
                            NSLog("[Casberi] agentModel| %@ UNREADABLE (keeping pin %@)",
                                  provider.rawValue, provider.defaultModel)
                            continue
                        }
                        let pinLives = models.contains { $0.id == provider.defaultModel }
                        NSLog("[Casberi] agentModel| %@ count=%d using=%@ chosen=%@ pinStillReal=%d",
                              provider.rawValue, models.count, provider.model,
                              AgentModelStore.chosen(provider) ?? "-", pinLives ? 1 : 0)
                        for model in models.prefix(40) {
                            NSLog("[Casberi] agentModelRow| %@ %@", provider.rawValue, model.id)
                        }
                    }
                }
            }
            // Debug hook: `-keepAskProbe "<kind>:<title>"` keeps that kind
            // headlessly (or `clear`); `KeptAskStore.seedFromLaunchArgs()` does
            // the keep itself. Then run its composer over the real corpus and
            // log the result, so the persistence + digest machinery verifies
            // without tapping through the UI.
            KeptAskStore.seedFromLaunchArgs()
            if !KeptAskStore.shared.order.isEmpty {
                Task { @MainActor in
                    let all = (try? modelContext.fetch(FetchDescriptor<Thing>(
                        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
                    for kind in KeptAskStore.shared.order {
                        let result = await KeptAskComposers.compose(kind, things: all, context: modelContext)
                        NSLog("[Casberi] keepAskProbe compose(\"%@\") → delta=\"%@\" digest=\"%@\"\n%@",
                              kind, result?.delta ?? "nil", result?.digest ?? "nil",
                              result?.doc.joined(separator: "\n") ?? "(no composer for this kind)")
                    }
                }
            }
            // Debug hook: `-briefLedger "days=6;symbol=ETH;themes=…;sources=…"`
            // (or `clear`) plants prior windows in the §214 ledger, so a
            // streak, a continuity subline or an absence line verifies in ONE
            // launch instead of a week of real opens. Declared before the
            // probe below — hooks run in list order, and the probe must read a
            // ledger that's already seeded.
            BriefLedger.seedFromLaunchArgs()
            // Debug hook: `-briefScope "<Scope>:<hoursAgo>[,…]"` (or `clear`)
            // seeds a scoped brief's own "since I last checked" stamp, so a
            // window that spans real days verifies in one launch instead of
            // a real wait. WAS DECLARED (the function existed in
            // `BriefScope.swift` since the feature shipped) but never called
            // from anywhere — found live, 2026-08-08: seeding "Money:20" had
            // no effect, and `BriefScope.since(category:)` was silently
            // reading whatever a PRIOR launch's real `markViewed` call had
            // left behind instead. Declared here, before every brief-composing
            // probe below, for the same list-order reason `BriefLedger`'s
            // sits here.
            BriefScope.seedFromLaunchArgs()
            // Debug hook: `-todayProbe YES` composes the Today brief (prd
            // §166) over the real corpus and logs the whole doc — every module
            // it chose and every observation that fired — so the composer
            // verifies without a tap. Pair with `-awayGap <hours>` to widen
            // the window a headless run measures.
            //
            // Composes with `presenting: false` ON PURPOSE: recording would
            // make each probe run suppress the leads of the next one, so a
            // rerun wouldn't reproduce. Use `-briefLedger` to stage memory.
            if UserDefaults.standard.bool(forKey: "todayProbe") {
                Task { @MainActor in
                    let all = Corpus.surfaced((try? modelContext.fetch(FetchDescriptor<Thing>(
                        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? [])
                    let landed = DayBrief.landed(all)
                    let result = await KeptAskComposers.compose("today", things: all,
                                                               context: modelContext)
                    NSLog("[Casberi] todayProbe: landed=%d ledger=%d headline=\"%@\" digest=\"%@\"",
                          landed.count, BriefLedger.snapshot().count,
                          DayBrief.headline(things: all) ?? "(nil)",
                          result?.digest ?? "nil")
                    // One NSLog PER LINE — a joined multi-line message gets
                    // truncated by the log reader mid-document, which hid an
                    // unresolved ref for a whole debugging round (2026-07-22).
                    for line in result?.doc ?? ["(no doc)"] {
                        NSLog("[Casberi] todayDoc| %@", line)
                    }
                }
            }
            // Debug hook: `-ellipsisProbe "<q1>|<q2>"` runs two asks in
            // sequence through the REAL answer path (§176) — q1 sets the
            // named-ask shape, then q2 (a bare "and bbc?") exercises the
            // ellipsis. Logs each doc's first line so the second's rewrite is
            // verifiable headlessly (the stateful follow-up can't be tested
            // across two separate launches, which each reset @State).
            if let spec = UserDefaults.standard.string(forKey: "ellipsisProbe"),
               let bar = spec.range(of: "|") {
                let q1 = String(spec[spec.startIndex..<bar.lowerBound])
                let q2 = String(spec[bar.upperBound...])
                Task { @MainActor in
                    let d1 = await answerDocument(q1) { _ in }
                    NSLog("[Casberi] ellipsisProbe q1=\"%@\" synth=%@ → %@", q1,
                          lastNamedAskSynth.map(String.init(describing:)) ?? "nil",
                          d1.first ?? "(none)")
                    let d2 = await answerDocument(q2) { _ in }
                    for line in d2 { NSLog("[Casberi] ellipsisDoc| %@", line) }
                }
            }
            // Debug hook: open the composer so `-uiAnswerProbe` (handled in the
            // composer) can drive a real send for an on-screen answer.
            if UserDefaults.standard.string(forKey: "uiAnswerProbe") != nil
                || UserDefaults.standard.string(forKey: "composerDraft") != nil
                || UserDefaults.standard.string(forKey: "composerType") != nil
                || UserDefaults.standard.bool(forKey: "openComposer") {
                composerOpen = true
            }
            // Debug hook: `-rankSweep "q1|q2|q3"` — run `Retriever.rank` over
            // the real corpus for SEVERAL queries in ONE launch, logging each
            // query's hit count and top three titles (`rankSweep|` per query,
            // one NSLog each — the `-todayProbe` truncation lesson).
            //
            // It exists because the thing worth measuring here is a RANKING,
            // and a ranking can only be judged by comparing queries that should
            // answer against queries that shouldn't. `-findProbe` takes one
            // query per launch, so a twelve-query set across three candidate
            // floors is thirty-six launches and ten minutes — long enough that
            // in practice the comparison never gets run, which is how 0.62
            // stayed unexamined. Pairs with `-semanticFloor <n>`: same corpus,
            // same queries, one variable.
            //
            // Retrieval only — no model, no composer, nothing written.
            if let spec = UserDefaults.standard.string(forKey: "rankSweep"), !spec.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    var descriptor = FetchDescriptor<Thing>(
                        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
                    descriptor.fetchLimit = 2000
                    let corpus = (try? modelContext.fetch(descriptor)) ?? []
                    NSLog("[Casberi] rankSweep: floor=%.2f corpus=%d",
                          Retriever.semanticQualifyFloor, corpus.count)
                    for query in spec.split(separator: "|").map(String.init) {
                        let hits = Retriever.rank(query, in: corpus, isPoolRefinement: false)
                        let top = hits.prefix(3).map(\.title).joined(separator: " ⁄ ")
                        NSLog("[Casberi] rankSweep| %@ → %d | %@", query, hits.count, top)
                    }
                }
            }
            // Debug hook: `-openSources YES` raises the sources tray — the
            // agent bar's HOLD, which no headless run can perform (a long
            // press isn't a launch arg and computer-use is blocked in
            // scheduled runs). Delayed so `chrome.chipOrder` has been mirrored
            // from `MainSurface.chipLabels` first; opening at mount would
            // render the tray against the ["All"] placeholder and read as a
            // one-source corpus.
            if UserDefaults.standard.bool(forKey: "openSources") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    NSLog("[Casberi] openSources: %@", chrome.chipOrder.joined(separator: ", "))
                    // Through the same door as the hold it stands in for, so a
                    // probe exercises what a finger does.
                    openSources()
                }
            }
            // `-openComposerDelay <s>` opens the composer after a delay.
            let composerDelay = UserDefaults.standard.double(forKey: "openComposerDelay")
            if composerDelay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(composerDelay))
                    composerOpen = true
                }
            }
            // `-composerCycles <n>` raises and lowers the agent n times, ~8s
            // apart. The ONE way to measure what an open actually costs in
            // practice: `RootShell` renders the composer as
            // `if composerOpen { … }`, so every raise builds a brand-new
            // `Composer` and every lower destroys it — which means the FIRST
            // open a launch makes is the only one `-openComposer` can show,
            // and it is the atypical one. Everything the open reuses
            // (`AgentOpenCache`) only pays off from the second onward, so
            // without this the cache reads as doing nothing at all.
            let cycles = UserDefaults.standard.integer(forKey: "composerCycles")
            if cycles > 0 {
                Task { @MainActor in
                    for i in 1...cycles {
                        try? await Task.sleep(for: .seconds(8))
                        composerOpen = false
                        try? await Task.sleep(for: .milliseconds(600))
                        NSLog("[Casberi] composerCycle| raise %d", i)
                        composerOpen = true
                    }
                }
            }
            // Debug hook: `-linkTitleProbe <url>` exercises the title fetch
            // headlessly — NSLogs what a pasted link would be renamed to.
            if let raw = UserDefaults.standard.string(forKey: "linkTitleProbe"),
               let url = URL(string: raw) {
                Task { @MainActor in
                    let title = await LinkTitle.fetch(url)
                    NSLog("LinkTitle probe: %@", title ?? "FAILED")
                }
            }
            // Debug hook: `-linkBodyProbe <url>` exercises the readable-body
            // fetch headlessly — NSLogs the lede that would land in a saved
            // link's `enrichedText` for the answer path to reach.
            if let raw = UserDefaults.standard.string(forKey: "linkBodyProbe"),
               let url = URL(string: raw) {
                Task { @MainActor in
                    let body = await LinkTitle.fetchReadable(url)
                    NSLog("[Casberi] linkBodyProbe(%@) → %@", raw,
                          body ?? "FAILED (nothing readable)")
                }
            }
            // Debug hook: `-oembedProbe <url>` asks an allowlisted host what a
            // link is (`OEmbed`) and NSLogs every field it answered with — the
            // measure tool for a path authored against provider docs with no
            // egress to any of them. One line, four facts: a "handled=NO" says
            // the host isn't in the table, a "FAILED" says it is and the
            // endpoint didn't answer, and those are different bugs.
            if let raw = UserDefaults.standard.string(forKey: "oembedProbe"),
               let url = URL(string: raw) {
                Task { @MainActor in
                    guard OEmbed.handles(url) else {
                        NSLog("[Casberi] oembedProbe(%@) → handled=NO (host not allowlisted)", raw)
                        return
                    }
                    guard let embed = await OEmbed.resolve(url) else {
                        NSLog("[Casberi] oembedProbe(%@) → FAILED (no usable answer)", raw)
                        return
                    }
                    NSLog("[Casberi] oembedProbe(%@) → provider=%@ author=%@ thumb=%@",
                          raw, embed.providerName ?? "-", embed.authorName ?? "-",
                          embed.thumbnailURL ?? "-")
                    NSLog("[Casberi] oembedProbe title → %@",
                          OEmbed.title(embed, host: url.host()) ?? "-")
                    NSLog("[Casberi] oembedProbe enrichedText → %@",
                          OEmbed.enrichedText(embed) ?? "-")
                }
            }
            // Debug hook: `-instagramCaptions <n|YES>` runs the caption heal
            // (prd §245 amendment) over imported saves/likes and NSLogs one
            // line per row plus a summary. A numeric spec first FORGETS the
            // attempt ledger, so a pass can be re-walked in one session
            // instead of every row it already gave up on staying skipped.
            //
            // Three counts, not one: "considered" separates "nothing needed
            // doing" from "we tried and got nothing", and `backedOff` says
            // the host pushed back — which is the one outcome that means stop
            // rather than retry, and the reason this probe exists at all.
            // Walk it against a real library before trusting `perPass`/`pace`.
            if let spec = UserDefaults.standard.string(forKey: "instagramCaptions") {
                Task { @MainActor in
                    if Int(spec) != nil { InstagramCaptions.forgetFailures() }
                    let report = await InstagramCaptions.heal(context: modelContext) { line in
                        NSLog("[Casberi] instagramCaption| %@", line)
                    }
                    NSLog("[Casberi] instagramCaptions: considered=%d enriched=%d failed=%d backedOff=%@",
                          report.considered, report.enriched, report.failed,
                          report.backedOff ? "YES" : "NO")
                    // The covers, counted apart (2026-08-18, prd §395): a page
                    // can answer with its words and no picture, and a picture
                    // can fail to download from a page that read perfectly, so
                    // one number could not tell those two apart. `held` against
                    // the cap is what separates "no new covers" from "the cap
                    // is full", which look identical from outside.
                    NSLog("[Casberi] instagramCovers: stored=%d held=%d/%d",
                          report.covered, report.coversHeld, InstagramCaptions.coverCap)
                }
            }
            // Debug hook: `-toolAnswer "<query>"` runs the tool-calling agent
            // path (AnswerTools) in isolation — the model searches the corpus
            // via tools and answers, logging the prose and the ids it grounded
            // on. nil where the model is unavailable (the honest fallback the
            // default lookup path takes to the scoring doc).
            if let q = UserDefaults.standard.string(forKey: "toolAnswer") {
                Task { @MainActor in
                    let snap = toolSnapshot(terms: Retriever.contentTerms(q))
                    if let r = await AnswerTools.answer(query: q, corpus: snap) {
                        NSLog("[Casberi] toolAnswer(\"%@\") → %@\n  grounded on %d things: %@",
                              q, r.prose, r.hitIDs.count, r.hitIDs.joined(separator: ", "))
                    } else {
                        NSLog("[Casberi] toolAnswer(\"%@\") → nil (model unavailable/declined — expected on sim)", q)
                    }
                }
            }
            // Debug hook: `-mcpProbe "<query>"` exercises the MCP tool layer
            // (PRD §34) against the real corpus — search + week synthesis run as
            // reads, and a save is requested (which lands as an approval in Feed,
            // never a silent write). Proves the tools before the transport exists.
            if let q = UserDefaults.standard.string(forKey: "mcpProbe") {
                let hits = MCPTools.searchThings(q, context: modelContext)
                NSLog("[Casberi] mcpProbe search(\"%@\") → %d things:\n%@", q, hits.count,
                      hits.map { "· \($0.title) [\($0.kind.typeTag) · \($0.source)]" }.joined(separator: "\n"))
                NSLog("[Casberi] mcpProbe week_synthesis → %@", MCPTools.weekSynthesis(context: modelContext))
                let approval = MCPTools.saveThing(text: "Ship the MCP spec review",
                                                  from: "Claude", tags: ["Casberi"],
                                                  context: modelContext)
                NSLog("[Casberi] mcpProbe save_thing → approval pending in Feed: %@", approval.title)
            }
            #endif
        }
        // A Spotlight result opens the thing itself, not the app's front door.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let idString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let id = UUID(uuidString: idString) else { return }
            let all = (try? modelContext.fetch(FetchDescriptor<Thing>(
                predicate: #Predicate { $0.id == id }
            ))) ?? []
            if let thing = all.first {
                sceneState.route.path = []   // land on the record, not a stale store push
                sceneState.filter.source = "All"
                deepLinkThing = thing
            }
        }
        // Mac window resize (2026-07-28): the detail pane hands off a thing
        // it can no longer render instead of discarding it — see
        // `PadDetailSelection.displaced`.
        .onChange(of: sceneState.detail.displaced) { _, thing in
            guard let thing else { return }
            deepLinkThing = thing
            sceneState.detail.displaced = nil
        }
        .sheet(item: $deepLinkThing) { thing in
            rootPresented(ThingSheetView(thing: thing))
        }
        .sheet(item: $deepLinkPerson) { person in
            rootPresented(SocialProfileCard(profile: person))
        }
        // Every source at once (2026-07-31) — the agent bar's hold. Hosted
        // HERE, beside the bar that raises it, so it opens over a pushed room
        // (Apps, Settings, a bridge setup form) the same way it opens over the
        // feed; the chip strip it complements only exists on `MainSurface`.
        // `chrome.sourceOrder` is the strip's own frozen order, mirrored live —
        // and deliberately the UNFOLDED one (2026-08-10). The Markets fold
        // collapses seven seats into one chip up in the strip, which is right
        // there and wrong here: this grid is the screen that claims to show
        // EVERY source, so it keeps naming all seven. Handing it the folded
        // list would have dropped them all AND grown a "Markets" cell whose tap
        // writes a non-source into `filter.source` — a room whose predicate
        // matches nothing, forever, under a chip that lights up as if it worked.
        .fullScreenCover(isPresented: Binding(
            get: { !onboarded }, set: { if !$0 { onboarded = true } }
        ), onDismiss: {
            sceneState.filter.source = "All"
            sceneState.filter.tag = "All"
            // The demo pours HERE, with the cover out of the way, so the feed
            // is watched filling rather than revealed already full. Safe to
            // fire unconditionally — it returns immediately unless a pour is
            // actually pending.
            Task { @MainActor in await DemoMode.pourIfNeeded(context: modelContext) }
            guard let node = landingNode else { return }   // nil = the feed itself
            landingNode = nil
            sceneState.route.present(node)
        }) {
            // Onboarding is TWO screens since §217 (2026-07-25), and the
            // second one is the point. The greeting is unchanged — the rain,
            // the three steps, the same words — but its CTA is "Try it" and it
            // leads to the fork, where one tap produces real rows from the
            // person's own life. Before this it landed in a catalog of ~40
            // apps, so first value cost a choice, a connect and a sync; the
            // brief, the themes map and the wallet hero all stayed invisible
            // until a corpus existed. The fork's own escape hatch still opens
            // the catalog, so nothing is taken from someone who came to browse.
            rootPresented(HowItWorksSheet(onStart: { node in
                landingNode = node
                onboarded = true
            }))
        }
    }

    /// Split from `shell` (2026-07-28): the scene-phase / redaction / geometry
    /// handlers are their own stage so the type-checker isn't asked to unify one
    /// 800-line modifier chain in a single expression — a cold, uncached build
    /// (a clean checkout, or a TestFlight archive) timed out here every time,
    /// even though a warm incremental build never re-typechecks an unchanged
    /// file and so never showed it. Same view, same order, just staged.
    private var shellPhaseAware: some View {
        shellBase
        .animation(DS.Motion.standard, value: composerOpen)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shellWidth = $0 }
        // The bar rides RootShell's OWN ZStack now (2026-07-19 — it replaced
        // the FAB, which used to live on MainSurface's root content
        // specifically so pushed rooms could slide over it; the bar
        // deliberately does the opposite, per ruling 6).
        .onChange(of: chrome.composerRequest) { _, _ in
            composerOpen = true
        }
        // The tray, asked for from the menu bar or the bar's own right-click
        // (2026-07-31) — the hold is not the only door anymore.
        .onChange(of: chrome.sourcesRequest) { _, _ in
            openSources()
        }
        // Privacy as the default (goal 6): leaving the app redacts the
        // corpus — the app-switcher snapshot shows choreography, not content.
        // The person can turn it off in Privacy (Hide previews). Never before
        // first activation: apps LAUNCH inactive, and the nav bar caches a
        // title configured under redaction.
        .redacted(reason: redactNow ? .placeholder : [])
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // The phone's activation door. On Mac Catalyst the LAUNCH
                // transition never arrives here — the scene is already
                // .active before SwiftUI attaches this observer (measured
                // 2026-08-01: no Mac run's log ever carried the activation
                // spans — no bridge refresh, no whisper, no pane brief,
                // ever). Later transitions DO deliver on Catalyst, so this
                // branch is gated rather than trusted: the Mac takes the
                // UIKit notification door below for every activation, and
                // each platform having exactly one door is what keeps the
                // work from double-running.
                guard !ProcessInfo.processInfo.isMacCatalystApp else { return }
                handleActivation()
            } else {
                handleDeactivation(phase: phase)
            }
        }
        // The Mac's activation door (2026-08-01): AppKit posts this on every
        // focus-in — launch included, cmd-tab back included — and it is the
        // only activation signal that reliably reaches a Catalyst scene (see
        // the scenePhase note above). Focus-in is also the Mac's natural
        // refresh cadence, standing in for the phone's constant foregrounds.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            guard ProcessInfo.processInfo.isMacCatalystApp else { return }
            handleActivation()
        }
        // Launch coverage for the same door: if activation happened before
        // the subscription above existed (the exact failure mode that hid
        // the scenePhase transition), the state is already .active at attach
        // and the notification will never re-post — read it directly once.
        .task {
            guard ProcessInfo.processInfo.isMacCatalystApp,
                  UIApplication.shared.applicationState == .active else { return }
            handleActivation()
        }
        // The quick action's WARM door (2026-08-14). `SceneDelegate` receives
        // the long-press while this view is alive, so the brief opens on the
        // press rather than waiting on an activation pass that may already
        // have run — see `openBriefIfRequested`, which both doors share.
        .onReceive(NotificationCenter.default.publisher(for: QuickAction.received)) { _ in
            openBriefIfRequested()
        }
    }

    /// Everything one foreground/activation runs — split from the scenePhase
    /// observer (2026-08-01) so the Mac's notification door and the phone's
    /// scenePhase door share one body. Debounced because the Mac has two
    /// launch-time doors (the `.task` fallback and the notification) and a
    /// window that can flip focus rapidly; one activation per couple of
    /// seconds is plenty, and on the phone the debounce is invisible.
    @MainActor
    private func handleActivation() {
        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }
        lastActivation = .now
        let firstActivation = !hasBeenActive
        hasBeenActive = true
        // Freeze the away window (librarian, prd §67 ⑥) — "while you
        // were away" grounds on it; things landing from here on are
        // arriving while you're present.
        AppVisit.markOpened()
        // A STRANDED POUR resumes here (2026-08-07, found while writing the
        // spec for this feature's next pass). `pourIfNeeded` originally had
        // ONE call site — the onboarding cover's `onDismiss` — on the
        // assumption that a kill mid-pour would resume "on the next
        // launch". It never could: `onboarded` is already true by the time
        // the pour starts, so the cover never presents again and
        // `onDismiss` never fires. The person was left in demo mode (banner
        // up, seats connected) over a half-poured corpus, forever. This is
        // unconditional and safe — `pourIfNeeded` returns immediately unless
        // `demo.mode.pourPending` is actually set, which only a genuine
        // interruption leaves behind. Chained with the FRESHNESS re-stamp in
        // the same Task, sequentially — a pour that just landed rows has
        // nothing stale to fix, and running both against the context from
        // one Task avoids two independent writers touching it in the same
        // window.
        Task { @MainActor in
            await DemoMode.pourIfNeeded(context: modelContext)
            await DemoMode.restampIfStale(context: modelContext)
        }
        // Returning crossfades from placeholder to content (§14);
        // leaving redacts instantly — the snapshot must already hide.
        withAnimation(.easeOut(duration: 0.2)) { redactNow = false }
        // Warm the model so the first Ask is fast — but OFF the launch
        // window (PERF 2026-07-29, user: "first open is many seconds
        // and in slow motion, then fine"). `WarmModel.prewarm()` does
        // two synchronous @MainActor calls — `LanguageModelSession()`
        // and `session.prewarm()`, which loads the on-device LLM — and
        // running them the instant the scene activates blocked the main
        // thread as the opening frames painted, so the feed hung and
        // the chip strip wouldn't swipe until the model finished
        // loading ("then fine"). Deferred well past the first
        // interactive frame on cold launch; the only cost is an Ask
        // fired in the opening couple of seconds paying the same
        // one-time load itself, which prewarm merely front-runs.
        if !skipPrewarm {
            let coldLaunch = firstActivation
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(coldLaunch ? 2500 : 300))
                OnDeviceModel.prewarm()
            }
        }
        // The heavier foreground work — polling every connected bridge
        // (`refreshAllConnected` includes a SYNCHRONOUS Photos fetch),
        // the embedding backfill, and the insight/kept-ask/whisper
        // recompute — is deferred past the launch ANIMATION on the
        // FIRST activation (2026-07-24 perf, user report "loading
        // hangs / the coins-flip stutters"): running it as the opening
        // frames paint stalled the main thread mid-animation. A later
        // foreground has no launch animation to protect, so it runs
        // immediately.
        let runForegroundWork: @MainActor () -> Void = {
            // Connected bridges are cheap to poll — every foreground
            // refreshes them all (one place, reusable from screens).
            #if DEBUG
            LaunchPerf.time("refreshAllConnected") {
                BridgeRefresh.refreshAllConnected(context: modelContext, store: bridges)
            }
            #else
            BridgeRefresh.refreshAllConnected(context: modelContext, store: bridges)
            #endif
            // Tracked money records, brought up to date (prd §369 amendment).
            // HERE and not in the background sweep, deliberately: this is the
            // pass that really re-read the sources, and a Live Activity's
            // "checked 2h ago" is a claim about the SOURCE, not about our own
            // store. See `MoneyActivityDriver.sync`.
            Task { await MoneyActivityDriver.sync(context: modelContext) }
            // Build the on-device semantic index for anything new or
            // not yet embedded — a bounded background sweep, so Ask can
            // retrieve by meaning, not just shared words.
            EmbeddingIndex.backfill(context: modelContext)
            // Stamp what each new thing can REACH (a phone number, an
            // address) once, instead of re-detecting it per row per
            // render — prd §260. Same bounded-sweep shape as the
            // embedding backfill above, and deliberately in the same
            // deferred block: it is the work the launch window exists
            // to keep clear. Its scans hop off the main actor themselves
            // (2026-08-06) — on it, 150 rows of `NSDataDetector` was a
            // stall in exactly this window, every foreground.
            Task { @MainActor in
                await SweepClock.measure("verbs.detect") {
                    await VerbDetection.backfill(context: modelContext)
                }
            }
            // The two model-fed sweeps (prd §282, 2026-08-02) — both bounded
            // to a handful of rows per foreground, both no-ops without Apple
            // Intelligence, and both deliberately behind the cheap
            // deterministic sweeps above: a long transcript's digest and a
            // screenshot's name are worth having, never worth delaying the
            // index everything else reads.
            Task { @MainActor in
                await ThreadDigest.sweep(context: modelContext)
                await ScreenshotNaming.sweep(context: modelContext)
            }
            // The "Noticed" line's real trigger (docs/agent-brief.md
            // ruling 10). Also refreshes the kept-ask digest cache
            // (`KeptAskStore.anyChanged`) the bar's pulse reads from.
            Task { @MainActor in
              // On the sweep clock (2026-08-06) because it is main-actor work
              // in the same window as the bridge sweep and costs about what a
              // bridge slot does — a 600-row materialization plus three
              // composes — so a report that showed only the sweep would send
              // whoever reads it to optimize the smaller half.
              await SweepClock.measure("insight.recompute") {
                // Bounded (2026-07-24): insight/kept-ask/whisper read
                // only recent activity, so this needn't materialize the
                // whole corpus on the main actor at launch.
                var d = FetchDescriptor<Thing>(
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
                d.fetchLimit = 600
                #if DEBUG
                let surfaced = LaunchPerf.time("insightFetch600") {
                    Corpus.surfaced((try? modelContext.fetch(d)) ?? [])
                }
                LaunchPerf.time("HomeInsight.refresh") { HomeInsightStore.shared.refresh(from: surfaced) }
                // The deterministic notice (prd §384) — its own bounded
                // fetches, because a newest-600 window structurally cannot
                // hold a three-years-ago anniversary (the §382 widget
                // deadline-scan reasoning).
                LaunchPerf.time("AgentNoticed.refresh") { AgentNoticed.shared.refresh(context: modelContext) }
                // The librarian names the map's clusters (prd §386m) — off
                // the compose path by construction, which is the only reason
                // §386a's "the brief awaits no model" survives the feature.
                await ClusterNames.shared.refresh()
                // GITHUB'S CONTRIBUTION YEAR (2026-08-16, report: "did we
                // just get rid of 'your work' as a category or it's not
                // showing"). Not removed — starved. `TodayBrief.githubCalendar`
                // reads `GitHubGraphStore.year` and deliberately never
                // fetches, so the brief costs nothing for a room it merely
                // mentions; but the ONLY caller that did fetch was the GitHub
                // room's own `.task`. So Work could compose only for someone
                // who had opened that room within six hours, which for most
                // people is never, and the section silently never appeared.
                //
                // This is §320's class exactly ("two features existed and
                // NOTHING CALLED THEM") and §386m's, one section over — a
                // feature whose absence looks identical to its quiet success,
                // since a Work section that declines and one that was never
                // fed render as the same nothing.
                //
                // Safe here for the reason the composer's comment already
                // gives: `refreshIfStale` self-guards on a six-hour cache, an
                // in-flight flag, and a stored token, so a foreground with no
                // GitHub connected returns before it touches the network.
                await GitHubGraphStore.shared.refreshIfStale()
                await KeptAskStore.shared.refreshDigests(things: surfaced, context: modelContext)
                // The widget's rung-1 content (its brief headline) is
                // published as a side effect of composing "today" — but
                // refreshDigests only composes it for someone who has
                // KEPT that ask. Most people never do, so the widget
                // silently sat on rung 2 (the newest thing) forever.
                // Compose it here too, unconditionally, so the widget
                // stops being stale for everyone else (2026-08-03).
                if !KeptAskStore.shared.order.contains("today") {
                    _ = await TodayBrief.compose(things: surfaced, context: modelContext)
                }
                LaunchPerf.time("refreshWhisper") { refreshWhisper(things: surfaced) }
                LaunchPerf.time("widgetPublish") { WidgetPublish.publishAll(things: surfaced, context: modelContext) }
                #else
                let surfaced = Corpus.surfaced((try? modelContext.fetch(d)) ?? [])
                HomeInsightStore.shared.refresh(from: surfaced)
                AgentNoticed.shared.refresh(context: modelContext)
                await ClusterNames.shared.refresh()
                await KeptAskStore.shared.refreshDigests(things: surfaced, context: modelContext)
                if !KeptAskStore.shared.order.contains("today") {
                    _ = await TodayBrief.compose(things: surfaced, context: modelContext)
                }
                // The whisper's compose rides the same corpus walk this
                // Task already paid for — never its own fetch.
                refreshWhisper(things: surfaced)
                WidgetPublish.publishAll(things: surfaced, context: modelContext)
                #endif
              }
            }
            // The agent's chip counters, computed while nothing is waiting on
            // them, so the first raise of a launch costs what every later one
            // does (2026-08-12). Self-delaying and self-skipping — see
            // `AgentOpenCache.warm`; it deliberately does NOT run inline here,
            // since a ~761ms walk in the sweep is the launch stall this whole
            // pass has been removing.
            AgentOpenCache.shared.warm(context: modelContext)
        }
        // Deferred on EVERY activation since 2026-08-06, not just the first.
        // A return has no launch animation to protect, which is why this block
        // used to run inline there — but it has something better worth
        // protecting: the person is looking at a rendered feed and is about to
        // scroll it, and this is a 600-row materialization plus three composes
        // plus ~45 bridge slots landing on the main actor at the exact instant
        // they touch the screen. That was the "lags when I come back" half of
        // the post-271 report. The shorter delay is the crossfade's length —
        // long enough to clear the frame, short enough that nothing feels
        // withheld.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(firstActivation ? 800 : 250))
            runForegroundWork()
        }
        // Resnapshot hand-off state so the thing sheet's "Add to <app>"
        // verbs only show apps the person connected AND has installed.
        HandOffState.refresh(connected: Set(
            bridges.bridges.filter { $0.status == .connected }
                .map { $0.name.lowercased() }))
        // Control Center's button left a flag — open the composer.
        let group = UserDefaults(suiteName: SharedStore.appGroup)
        if group?.bool(forKey: "compose.request") == true {
            group?.removeObject(forKey: "compose.request")
            composerOpen = true
        }
        // The "Daily Brief" quick action (icon long-press / Mac Dock menu)
        // left a flag — this is the COLD-launch door for it, since a launch
        // receives the action long before this view exists. The warm door is
        // the `QuickAction.received` observer on the body.
        openBriefIfRequested()
        // A notification was tapped (prd §306). The tap left the link rather
        // than opening it, because a notification can COLD-LAUNCH the app and
        // `onOpenURL` routing isn't guaranteed live at that instant — the same
        // reason the quick action above uses a flag.
        if let link = Notifications.pendingLink() {
            route(link)
        }
        // Sweep for anything worth telling them about. Runs on foreground as
        // well as in the background task so the two can't drift, and because a
        // person who opens the app rarely may never get a background run at
        // all — this is what makes the whisper re-arm on their schedule.
        Task { @MainActor in await WalletBackgroundRefresh.runNotifySweep() }
        // A share-extension capture landed while we were away. Its
        // write IS in the store file, but @Query never hears a
        // foreign process's save (SwiftData; Apple's pattern is a
        // foreground reconcile — forums thread 764290), so shared
        // things stayed invisible until relaunch (2026-07-11).
        if group?.bool(forKey: "capture.landed") == true {
            group?.removeObject(forKey: "capture.landed")
            nudgeAfterExternalCapture()
        }
    }

    /// Land the "Daily Brief" quick action, if one is waiting.
    ///
    /// Reached from BOTH activation doors on purpose, and the flag is what
    /// makes that safe: whichever runs first clears it, so the other returns
    /// having done nothing. A cold launch is drained by `handleActivation`
    /// (nothing was listening when the action arrived); a warm one is drained
    /// by the `QuickAction.received` observer, because `handleActivation` is
    /// debounced to one pass per two seconds and may already have run — a
    /// flag with no nudge could otherwise sit until some later foreground and
    /// raise the brief on an activation the person meant for something else.
    ///
    /// The landing is the `casberi://brief` route's, verbatim (see `route`'s
    /// `case "brief"`): one composer, one door onto the day.
    @MainActor
    private func openBriefIfRequested() {
        let group = UserDefaults(suiteName: SharedStore.appGroup)
        guard group?.bool(forKey: "brief.request") == true else { return }
        group?.removeObject(forKey: "brief.request")
        NSLog("[Casberi] briefRequest: raising the agent on the brief")
        sceneState.filter.source = "All"
        sceneState.filter.tag = "All"
        chrome.askRequest = TodayBrief.title
        composerOpen = true
    }

    /// The leaving half of the scenePhase observer. Unlike the ACTIVATION
    /// transition, Catalyst DOES deliver these (measured 2026-08-01: a
    /// headless launch that lost focus redacted its pane to placeholder
    /// bars) — only the launch-time activation precedes the observer.
    @MainActor
    private func handleDeactivation(phase: ScenePhase) {
        // Redaction is an app-switcher-snapshot concern. A Mac window stays
        // VISIBLE while unfocused, so blanking it on every focus-out reads
        // as the app breaking — and before the 2026-08-01 activation fix it
        // never happened there (`hasBeenActive` could not become true), so
        // skipping Catalyst also preserves the Mac's long-standing behavior.
        if hasBeenActive && hidePreviews
            && !ProcessInfo.processInfo.isMacCatalystApp { redactNow = true }
        if phase == .background {
            // The away clock starts — the next foreground reads it.
            AppVisit.markClosed()
            // Ask iOS to sample wallet holdings while we're away, so
            // the value line densifies between opens (no-op without a
            // watched wallet; the OS decides if it ever runs).
            WalletBackgroundRefresh.schedule()
            // The widget's new-ring boundary: everything after this
            // stamp is "new since you left" on the home screen too
            // (delight 2026-07-13). Reload so the widget re-reads.
            UserDefaults(suiteName: SharedStore.appGroup)?
                .set(Date.now.timeIntervalSince1970, forKey: "widget.lastSeen")
            WidgetCenter.shared.reloadTimelines(ofKind: "casberi.hero")
            // Give the model's memory back when we're not in use; the
            // next foreground reloads it.
            OnDeviceModel.teardown()
        }
    }

    private var shellBase: some View {
        ZStack(alignment: .bottom) {
            // The themed page — the same field each screen paints for itself
            // (NavigationStack's backing is opaque, so photo rendering lives
            // inside the screens via dsPageBackground; this is the base coat).
            DSPageBackground()

            // Content — records paint, generated surfaces stream (brief §5).
            // Anything dropped on the shell lands as a thing (capture: drop).
            MainSurface()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The demo's marking lives in `MainSurface.topInset`, NOT here
                // — an inset applied at this level is ignored by the source
                // strip, which owns the top of the screen from inside the
                // NavigationStack. See that property for the measurements.
                // The demo's drain — see `ShellChrome.demoLeaving`.
                .opacity(chrome.demoLeaving ? 0 : 1)
                .animation(DS.Motion.standard, value: chrome.demoLeaving)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    if url.isFileURL {
                        saveDroppedFile(url)
                    } else {
                        saveDropped(url.absoluteString)
                    }
                    return true
                } isTargeted: { dropTargetedURL = $0 }
                .dropDestination(for: String.self) { strings, _ in
                    guard let text = strings.first else { return false }
                    saveDropped(text)
                    return true
                } isTargeted: { dropTargetedText = $0 }
                // The window answers the drag (Mac delight, 2026-08-03): a
                // soft tint glow at the edges while a drop would land — the
                // drop target saying so BEFORE release, where the old flow's
                // first feedback was the toast after. See `DropGlow`.
                .overlay {
                    DropGlow(active: dropTargetedURL || dropTargetedText)
                }

            if let toast = chrome.toast { toastView(toast) }

            // The capture flight (§1): a proxy card glides from the capture
            // point to the "All" chip, then it pulses once.
            if let flight = chrome.flight {
                CaptureFlight(flight: flight, target: chrome.feedTabFrame) {
                    chrome.flight = nil
                    // The landing beat — the All chip catches the capture
                    // (the old landedPulse reader died with the tab bar;
                    // the catch bob is the same promise, kept again).
                    chrome.chipCaught("All")
                }
                .zIndex(2)
            }

            // The agent's bar (docs/agent-brief.md ruling 6) — hosted HERE,
            // not on MainSurface, so it rides every screen this app can push
            // (Apps, Settings, a bridge setup form), not just MainSurface's
            // own root the way the FAB it replaces used to. The berry
            // breathes while some kept ask changed and the agent hasn't been
            // raised yet THIS LAUNCH (a plain, session-scoped flag — distinct
            // from `KeptAskStore`'s own PER-ASK persisted "seen" dot, which
            // renders on the pills once risen, not here).
            // Hidden entirely once risen (2026-07-20) — `agentMorph` needs
            // exactly one side of the matched pair present at a time, and a
            // bar sitting inert under the risen sheet was dead weight anyway.
            // The sources panel — a LAYER of this ZStack, not a `.sheet` and not
            // an `.overlay` on the chain (2026-08-16, §394).
            //
            // Not a sheet, because a sheet presents in its own context and the
            // glass cannot sample the feed across it — the whole reason this
            // tray spent four builds looking grey.
            //
            // And placed HERE, before the floating cluster below, so the agent
            // bar keeps drawing on TOP of the panel (user: "make it so when it
            // is selected the fab is still showing and user could tap the fab
            // to dismiss it"). As an `.overlay` the panel covered the bar
            // outright, which left a raised tray with its own opener hidden
            // underneath it. Z-order is the whole fix: the bar is later in this
            // stack, so it stays visible AND hittable, and its own action
            // toggles.
            //
            // `rootPresented` STAYS, and assuming it could go cost a crash: a
            // ZStack layer inside `shell` is still ABOVE the `.environment(...)`
            // injections applied to `shell` itself, so the panel launched with
            // no `BridgeStore` and died on its first read — "No Observable
            // object of type BridgeStore found", on every open, with a clean
            // compile and every static audit green. The helper is about
            // position in the chain, not about sheets.
            if sourcesOpen {
                rootPresented(SourcesOverlay(
                    labels: chrome.sourceOrder,
                    active: filter.source,
                    onDismiss: { closeSources() },
                    // The empty tray's door (2026-08-18). The SAME push the
                    // strip's own catalogue button makes — one catalog, one
                    // way in — and it closes the panel first, because a door
                    // that pushes a screen behind a raised panel reads as
                    // having done nothing.
                    onOpenCatalog: {
                        closeSources()
                        withAnimation(DS.Motion.standard) {
                            sceneState.route.present(.apps)
                        }
                    }) { label in
                    closeSources()
                // Land ON the feed that was named. A pick made from a pushed
                // room would otherwise switch the source BEHIND a Settings
                // screen still standing on the stack — the tray would close
                // onto the same room it was opened from, having visibly done
                // nothing.
                sceneState.route.path = []
                // A pick means the whole source — the kind filter clears for
                // every label, and BEFORE the same-source guard, so a re-tap
                // drops it. The chip strip's own rule (`MainSurface.go(to:)`),
                // restated rather than shared because the two call sites still
                // differ on what the re-tap branch does with the source itself.
                if filter.tag != "All" {
                    withAnimation(DS.Motion.standard) { filter.tag = "All" }
                }
                guard label != filter.source else { return }
                withAnimation(DS.Motion.standard) {
                    filter.source = label
                }
                // A pick here teaches the strip exactly as a chip tap does —
                // this is the same act, reached by a different gesture.
                ChipMemory.visited(label)
                })
            }

            // The cluster stands down for the sources panel too (2026-08-16,
            // user: "if you can drag the panel to close it then the fab
            // doesn't need to be showing").
            //
            // It was briefly shown OVER the panel, on the reasoning that a
            // visible opener is a visible closer. The user's own follow-up
            // killed it and was right on three counts: the bar sits
            // bottom-trailing, so on a fuller corpus a chip lands under it and
            // becomes a source you can see and cannot tap; keeping it clear
            // cost 76pt of panel height, about a whole row at rest; and the
            // panel already has TWO ways out that the sheet never gave us for
            // free — the hand-built drag-to-dismiss and the tap-catcher. A
            // third door, floating on top of the surface it closes, is noise.
            //
            // What was actually lost with the sheet was DETENTS — dragging UP
            // to full height — not drag-to-dismiss, which is rebuilt in
            // `SourcesOverlay`. Those two got conflated for a moment here.
            if !composerOpen && !sourcesOpen {
                // The floating cluster (whisper + bar) renders as one
                // coordinated glass system (2026-07-23) — the container gives
                // both elements a SHARED backdrop sample, so as feed content
                // scrolls behind the pair they lens the same field consistently
                // instead of each sampling on its own. Spacing is 0 ON PURPOSE:
                // a non-zero spacing would let the two shapes MERGE into a
                // liquid bridge, and the whisper is deliberately inset a step
                // narrower to read as SEPARATE from the bar (2026-07-22, the
                // double-bar ruling) — coordinated, not fused.
                DSGlassContainer(spacing: 0) {
                // TRAILING (user ruling 2026-08-07) — the cluster pins to the
                // bottom-right instead of centring on the bottom edge. Centred
                // chrome sat over the middle of the reading column, which is
                // the one column this app exists to serve; in the corner the
                // column runs clear beneath it and the bar is a shorter reach
                // for the thumb of the hand a phone is actually held in.
                // `.trailing` rather than a hard right edge so an RTL layout
                // gets the mirrored corner for free.
                VStack(alignment: .trailing, spacing: DS.Space.s2) {
                    // The whisper rides ABOVE the bar (prd §165) — the day
                    // brief's headline, first open of the day only. Tap
                    // raises the agent, same move as the bar's own.
                    if let whisper {
                        // roomTint nil since 2026-08-15 — see the bar's own
                        // note below; the capsule follows the bar so the
                        // bottom cluster stays one untinted pair.
                        WhisperCapsule(title: whisper.title, lead: whisper.lead,
                                       walletPct: whisper.walletPct,
                                       morphNS: agentMorph,
                                       roomTint: nil) {
                            DSHaptic.tap()
                            // The capsule's promise kept (prd §166): the tap
                            // lands on the Today brief itself, not the rest
                            // state — the headline it teased, opened. Routed
                            // through `chrome.askRequest` (the same door the
                            // weekend cover already uses), so the whisper, a
                            // typed "how's my day", and a kept pill all reach
                            // the one composer.
                            chrome.askRequest = TodayBrief.title
                            // The title travels (prd §167 item 1): set BEFORE
                            // `composerOpen` flips, so the proxy title below
                            // mounts in the SAME `composerOpen`-driven
                            // transaction as the capsule vanishing — the real
                            // masthead doesn't exist for another 400ms+ (it
                            // waits on `consumeAskRequest`'s settle delay,
                            // then commit()), well past this rise animation's
                            // own duration, so without a proxy there'd be
                            // nothing on the OTHER side of the pairing for the
                            // morph to animate into.
                            let title = whisper.title
                            chrome.risingBriefTitle = title
                            composerOpen = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(700))
                                // Only clear OUR OWN word — a fast re-tap that
                                // set a newer title must not be stomped by an
                                // older timer firing late.
                                guard chrome.risingBriefTitle == title else { return }
                                withAnimation(DS.Motion.standard) { chrome.risingBriefTitle = nil }
                            }
                        }
                        // The 2026-07-22 inset is GONE (2026-08-07) — see
                        // `WhisperCapsule`'s own note. It existed to stop two
                        // full-width slabs reading as a double-bar, and the bar
                        // beneath it is no longer a slab. What replaces it is a
                        // CAP: the capsule holds a title over a line of facts,
                        // which needs real width to be worth reading, so it
                        // keeps the phone's whole column and is only bounded on
                        // a shell wide enough to make that column silly.
                        .frame(maxWidth: PadLayout.floatingClusterMaxWidth,
                               alignment: .trailing)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    AgentBar(hasUnseenSignal: KeptAskStore.shared.anyChanged && !agentEverOpened,
                             // The notice glint (prd §384): a small tint dot,
                             // static on purpose — "something unread behind
                             // this", not an animation begging for a tap.
                             noticeGlint: AgentNoticed.shared.glint,
                             // Compact at rest (user ruling 2026-07-31, see
                             // `AgentBar`'s own note). The words survive only
                             // as a first-run grace — and `chrome.minimized`,
                             // which still folds the chip strip, folds them
                             // early if that first-time reader scrolls before
                             // ever opening the tray.
                             expanded: !sourcesEverOpened && !chrome.minimized,
                             morphNS: agentMorph,
                             onSources: { toggleSources() },
                             // NIL since 2026-08-15, the crown-pour ruling's
                             // other half. The user killed the per-wallet
                             // crown pour because it argued with the wallet
                             // hero's fixed blue ("it doesn't match the blue
                             // card"), and this glass tint was the same fact
                             // at a smaller dose: scope to a green-faced
                             // wallet and the bar goes green under a room
                             // whose one bright object is blue. The wallet's
                             // identity lives in the face rail and the hero's
                             // own caption now; the bar is plain glass in
                             // every room. `AgentBar.roomTint` keeps its
                             // parameter — the mechanism is sound, this is a
                             // ruling about what feeds it.
                             roomTint: nil) {
                        // `lift()`, not `tap()`, since §390 — this arrives at
                        // the END of a 0.45s hold, with the finger still down
                        // and nothing on screen yet to say the press
                        // registered. The heavier buzz IS that confirmation;
                        // the tray's ordinary `tap()` now sits on the tap.
                        DSHaptic.lift()
                        // Open onto the Today brief, not the empty chips (prd
                        // §181, user: "make daily brief be the default when a
                        // user opens the agent"). Routed through the SAME
                        // `askRequest` door the whisper tap and a typed "how's
                        // my day" already use — so all three reach the one
                        // composer and none can drift (the §132 principle).
                        // Guarded on nil so a surface that seeded a specific
                        // ask before the bar rose still wins; the masthead
                        // title-travel stays whisper-only (no `risingBriefTitle`
                        // here — a bare tap has no capsule to morph from).
                        // THE RISE LANDS ON THE OVERVIEW (2026-08-14, prd
                        // §386d) — this REVERSES §336's "no auto-brief on a
                        // bare tap", and the reversal is safe for a reason
                        // §336 could not have used: the panel now docks
                        // BENEATH the brief instead of competing with it.
                        //
                        // §336's finding was real — seeding an ask here puts
                        // the composer in `answering`, so `restChrome(keepBrief:
                        // false)` is false and `boardShowing` could never be
                        // true; the panel shipped in 282 and 284 and could not
                        // draw on a single normal open. The fix then was to
                        // stop seeding. The fix NOW is the other half of the
                        // same conjunction: `Composer` renders the panel
                        // inside the brief landing's own scroll, so both are
                        // on screen at once and the rise costs no decision.
                        //
                        // Why re-open it at all: the overview became the app's
                        // one daily screen this session (§386–§386c collapsed
                        // three scoped briefs into it and cut every module
                        // that wasn't a figure, a picture or a person), and it
                        // sat one tap behind a rest surface whose chips had
                        // just been deleted for being chips-to-have-chips.
                        //
                        // Every deliberate route to the brief is untouched: the
                        // whisper capsule, the Daily Brief quick action, the
                        // `casberi://brief` deep link, the day strip, a kept
                        // `today` pill, and a typed "how's my day" all still
                        // seed `askRequest` themselves. The guard below stays
                        // `nil`-checked so any of those still wins if it set an
                        // ask before the bar rose.
                        if chrome.askRequest == nil {
                            chrome.ask(TodayBrief.title)
                        }
                        // Rising is SEEING — the glint's whole claim is "rise
                        // and you'll find it", so the rise itself clears it.
                        AgentNoticed.shared.markSeen()
                        composerOpen = true
                    }
                }
                }
                // Pinned to the trailing edge (2026-08-07). The iPad cap the
                // two frames here used to carry moved ONTO the whisper capsule
                // above, which is the only element that still wants a width —
                // the bar hugs its own controls now, so at 1376pt it is a
                // corner pill rather than the mile-long bar with a placeholder
                // floating in it that the cap was written for.
                //
                // The insets are unchanged and still load-bearing: this ZStack
                // sits OUTSIDE MainSurface's safe-area insets, so the rail and
                // pane widths have to be restated here for the cluster to float
                // over the feed it belongs to rather than over the detail pane's
                // content — and on iPad the TRAILING inset is what now decides
                // which edge "the corner" means, which is exactly why that
                // arithmetic lives in `PadLayout` and not inline.
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, padShell.railInset)
                .padding(.trailing, padShell.paneInset)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s2)
                .transition(.opacity)
            }

            // The agent, full screen (ruling 3 — never a sheet/tray). Grows
            // out of the bar's own frame (2026-07-20, `agentMorph` — the
            // "now-playing bar" morph the design is named after): the outer
            // shape is `matchedGeometryEffect`-paired with `AgentBar`'s via
            // `Composer`'s `glassNamespace`, so the sheet's bounds visibly
            // interpolate from the small capsule to full screen instead of
            // sliding up as an unrelated sheet. Content still needs its own
            // fade-in since the frame match alone doesn't animate opacity.
            if composerOpen {
                ZStack {
                    DS.page.ignoresSafeArea()
                    agentSurface
                }
                .transition(.opacity)
                // The proxy title (prd §167 item 1) — mounts in this SAME
                // transaction as the surface itself appearing, so its
                // `matchedGeometryEffect` has a live pair to interpolate from
                // (the whisper capsule's own title, vanishing in the SAME
                // transaction one layer down). Purely cosmetic scaffolding:
                // Composer's real masthead carries the identical id, so once
                // it mounts the two simply crossfade in place — this view
                // never does anything but sit still and then fade.
                .overlay(alignment: .top) {
                    if let title = chrome.risingBriefTitle {
                        Text(title)
                            .dsText(.heading22)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                            .modifier(WhisperTitleMorph(ns: agentMorph))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.top, 68)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .zIndex(3)
            }
        }
    }

    /// The one door into the sources tray. Every way in fires the SAME buzz —
    /// the bar's tap, the VoiceOver action, the Mac menu bar, the deep link.
    /// It used to live inside `AgentBar`'s long-press, which meant the gesture
    /// with no visible affordance was the only route that said it had been
    /// received, and the routes built for the people who can't perform that
    /// gesture opened the tray in silence. Feel belongs to the tray, not to
    /// one recognizer.
    ///
    /// `tap()`, not the `lift()` it fired until §390: this is an ordinary tap
    /// now, and `lift()` is the weight of a gesture that had to be held.
    private func openSources() {
        DSHaptic.tap()
        // The teaching grace is spent the first time the tray opens by any
        // path — the bar's words have done their one job.
        sourcesEverOpened = true
        withAnimation(DS.Motion.standard) { sourcesOpen = true }
    }

    /// One way out, used by every closer — the panel's drag, its tap-catcher,
    /// a pick, and the bar itself — so the exit animates identically however
    /// it is reached.
    private func closeSources() {
        withAnimation(DS.Motion.standard) { sourcesOpen = false }
    }

    /// The bar's own verb TOGGLES since 2026-08-16 (user: "user could tap the
    /// fab to dismiss it").
    ///
    /// It could only open before, which was invisible while the tray was a
    /// sheet — the sheet covered the bar, so the closed state was the only one
    /// you could ever tap it in. The panel is a ZStack layer under the cluster
    /// now, so the bar stays visible above a raised tray, and a control you
    /// can see while its surface is open must be able to close it. Otherwise
    /// it reads as dead.
    private func toggleSources() {
        if sourcesOpen {
            DSHaptic.tap()
            closeSources()
        } else {
            openSources()
        }
    }

    /// Everything the shell hands its own tree, re-applied to a ROOT-PRESENTED
    /// sheet or cover — whose content hangs OUTSIDE the chain those modifiers
    /// wrap (fullScreenCover doesn't even reliably inherit `\.locale`). One
    /// door for all of it, because per-sheet hand-wiring is exactly how the
    /// token sheet crashed on 2026-07-17: the thing sheet had been handed
    /// chrome-adjacent pieces but not bridges, and a required
    /// `@Environment(BridgeStore.self)` under it was a mount-time fatal. Any
    /// new root sheet/cover goes through here; any new shell-wide environment
    /// object gets added HERE, not to individual sheets.
    ///
    /// NOTE it does NOT re-apply `dsSensoryFeedback()`, deliberately: the trays
    /// raised through here carry their own (`DSTray`), and a second listener in
    /// the same presentation would buzz twice. A root sheet that is not a tray
    /// and fires its own `DSHaptic` calls needs one — see `Haptics.swift`.
    private func rootPresented(_ content: some View) -> some View {
        content
            .environment(bridges)
            .environment(chrome)
            .environment(\.locale, LanguageStore.shared.locale)
    }

    /// casberi:// routing — one place, used by onOpenURL and the debug hook.
    /// Also the landing spot for a FILE handed in via AirDrop / Share Sheet
    /// ("Open in Casberi") — `.onOpenURL` fires for both, and the app only
    /// registers one document type (`.opml`, Info.plist), so a file URL here
    /// is always that.
    private func route(_ url: URL) {
        // A deep link lands you AT a destination, not back in a store the route
        // singleton still holds from an earlier visit. apps/settings re-set it
        // below.
        sceneState.route.path = []
        if url.isFileURL {
            guard url.pathExtension.lowercased() == "opml" else { return }
            PendingOPMLFile.shared.url = url
            sceneState.route.openSetup(forOffer: "RSS")
            return
        }
        switch url.host() {
        // casberi://home is back-compat (the app was a Home tab, then a
        // board) — it now lands on the All feed, ruling 11.
        case "home":    sceneState.filter.source = "All"; sceneState.filter.tag = "All"
        case "feed":
            sceneState.filter.source = "All"
            sceneState.filter.tag = "All"
            // casberi://feed/type/Link — Home's kind bar lands here filtered.
            // casberi://feed/source/Zerion — lands in that source's shape.
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count == 2, parts[0] == "type" {
                sceneState.filter.tag = parts[1]
            } else if parts.count == 2, parts[0] == "source" {
                // A source with no room lands on All rather than on a page
                // nothing can light (ruling 2026-08-02, `Corpus.chiplessSources`).
                // Nothing in the app mints such a link any more — the sheet's
                // eyebrow stopped being a door for these — but an old one, or a
                // hand-typed one, must not strand the strip with no chip lit.
                sceneState.filter.source = Corpus.earnsRoom(parts[1]) ? parts[1] : "All"
            }
        // Apps is reached through the shared doors now — push it directly,
        // wherever the chip header currently sits (back-compat for
        // casberi://apps and //account).
        case "account", "apps":
            sceneState.route.present(.apps)
        case "settings":
            sceneState.route.present(.settings)
        // casberi://brief — the agent, raised onto the brief (2026-07-25).
        // The hero widget carries the brief's own lede now, so its tap has to
        // land on the sentence it was showing; landing on the feed instead
        // would make the tile a headline with nothing behind it. The SAME
        // `askRequest` door the whisper capsule, the agent bar and a typed
        // "how's my day" all already funnel through — one composer, one route.
        case "brief":
            sceneState.filter.source = "All"
            sceneState.filter.tag = "All"
            chrome.askRequest = TodayBrief.title
            composerOpen = true
        // casberi://ask?q=<question> — any ask, by its own words (2026-08-14,
        // prd §382). Minted by the kept-ask and "Needs you" widgets, whose taps
        // must land on the answer they were showing rather than at the feed.
        //
        // It hands the QUESTION to the same `askRequest` door above, which is
        // byte-for-byte what tapping the kept pill in the composer does
        // (`draft = title; commit()`). So a widget can only ever open an answer
        // the app itself would produce for the same words — there is no second
        // dispatch to drift, and a kind this build doesn't recognise degrades to
        // an ordinary free-text ask instead of a dead link.
        case "ask":
            guard let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "q" })?.value,
                  !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            sceneState.filter.source = "All"
            sceneState.filter.tag = "All"
            chrome.askRequest = q
            composerOpen = true
        // casberi://person/<Source>/<handle> — the profile card for one person
        // on one network (2026-07-16). In the app it's reached by tapping a
        // face; this is the same card by name, so the screen sweep can reach it
        // headlessly like every other surface.
        case "person":
            let parts = url.pathComponents.filter { $0 != "/" }
            // `hasPersonRoom`, not `isSocial` (2026-08-18, prd §396): this
            // route opens a room composed entirely out of the corpus, so it
            // works for an X handle even though nothing about X can be
            // fetched.
            if parts.count == 2, SocialThread.hasPersonRoom(parts[0]) {
                deepLinkPerson = SocialProfile(source: parts[0], handle: parts[1],
                                               displayName: nil, bio: nil, avatarURL: nil)
            }
        case "thing":
            sceneState.filter.source = "All"
            let part = url.pathComponents.filter { $0 != "/" }.first
            if part == "latest" {
                deepLinkThing = (try? modelContext.fetch(FetchDescriptor<Thing>(
                    sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
                )))?.first
            } else if let part, let uuid = UUID(uuidString: part) {
                deepLinkThing = (try? modelContext.fetch(FetchDescriptor<Thing>(
                    predicate: #Predicate { $0.id == uuid }
                )))?.first
            }
        default: break
        }
    }

    // MARK: - Screens

    /// The agent, full screen (docs/agent-brief.md ruling 3) — the composer's
    /// entire existing pipeline (byok, lastAnswerHits, GenStream),
    /// unchanged, now hosted as a persistent ZStack layer instead of a sheet.
    private var agentSurface: some View {
        Composer(isOpen: .constant(true), draft: $draft, embedded: true,
                 onCommit: saveDraft, onCommitVoice: saveVoice,
                 answer: answerDocument,
                 answerWithKey: keyedAnswerDocument,
                 knownSources: { bridges.bridges.map(\.name) },
                 // Fixed 2026-07-20 — this was hardcoded nil, silently
                 // dropping the "meets you where you are" lead chip since
                 // the agent shell was built. sceneState.filter.source is
                 // the same active-chip signal MainSurface itself binds
                 // against; "All" is a safe sentinel that never collides
                 // with a real source name.
                 contextSource: { sceneState.filter.source == "All" ? nil : sceneState.filter.source },
                 onNavigate: navigate,
                 onKeepAnswer: keepAnswer,
                 glassNamespace: agentMorph,
                 resolveThing: { idString in
                     guard let uuid = UUID(uuidString: idString) else { return nil }
                     return (try? modelContext.fetch(FetchDescriptor<Thing>(
                         predicate: #Predicate { $0.id == uuid })))?.first
                 },
                 onLowerAgent: { composerOpen = false; keyedHistory = [] })
            .environment(\.genProjectTap) { name in
                // The apps answer's catalog door: "@apps" routes to the Apps
                // page here too (same marker the quiet-day invite uses on
                // Home) — a card that did nothing inside the composer would
                // be a dead control (honesty rule).
                if name == "@apps" {
                    composerOpen = false
                    sceneState.route.present(.apps)
                    return
                }
                // Other sentinels ("@wallet", "@token:…") are surface routes,
                // not tags — from the composer they'd open a bogus tag view
                // literally named "@token:…"; an unknown sentinel does
                // nothing.
                guard !name.hasPrefix("@") else { return }
                composerOpen = false
                sceneState.filter.source = "All"
                // Land on the All feed with the tag's project view pushed —
                // the same screen the feed's Themes treemap opens (this wrote
                // a `HomeRoute.openTag` nothing consumed after the board
                // retired, so the tile was silently inert until 2026-07-22).
                sceneState.route.path = [.project(name)]
            }
    }

    // MARK: - Capture (rung 1 write: the composer saves to us)

    /// A typed ask that names a place — the same destinations the UI's own
    /// taps reach: a tag view, a source's feed, a kind's feed.
    private func navigate(_ intent: NavigateIntent) {
        // The composer closed itself before calling here (its close() owns
        // the morph + state reset) — this only moves the shell.
        // Every destination here is content, not a door — drop any Apps/Settings
        // the singleton still holds, else asking to open a tag while in the
        // store re-presents the store.
        sceneState.route.path = []
        composerOpen = false
        switch intent {
        case .tag(let name):
            sceneState.filter.source = "All"
            sceneState.route.path = [.project(name)]
        case .source(let source):
            sceneState.filter.source = source
            sceneState.filter.tag = "All"
        case .kind(let kind):
            sceneState.filter.source = "All"
            sceneState.filter.tag = kind.typeTag
        // The only destination that sets BOTH (2026-08-05, prd §307) — a room
        // and one of its halves. `FeedFilter` has always ANDed these two; until
        // now nothing could ask for the pair, so an imported room's posts,
        // replies and likes were one undifferentiated column. Still the agent's
        // filter and not a control (§269): the day-section header names it, and
        // any source-chip tap clears it.
        case .sourceFacet(let source, let tag):
            sceneState.filter.source = source
            sceneState.filter.tag = tag
        }
    }

    private func saveDraft() {
        guard let thing = Capture.thing(from: draft) else { return }
        modelContext.insert(thing)
        modelContext.saveHonestly()
        SpotlightIndex.index([thing])
        land(thing)
        // A pasted URL saves instantly with its address as its face; the real
        // page title arrives a beat later (best-effort, never blocks the save).
        Task { @MainActor in await LinkTitle.enrich(thing, context: modelContext) }
    }

    /// A local file dropped in from Finder/Safari/Mail — genuinely a Mac-only
    /// path (2026-07-28): iOS has nowhere to drag a file FROM into this app
    /// except Files itself, which already rides its own connected bridge.
    /// `Capture.thing(from:)` would otherwise run the file:// path through
    /// its URL/text detector and most likely miss (NSDataDetector targets
    /// web links), saving a `.note` whose body is a bare filesystem path —
    /// the same wrong answer FilesBridge exists to avoid for a WATCHED
    /// folder. One-shot, like a paste or a screenshot: this reads what's
    /// here at drop time; there's no folder bookmark to re-sync from later,
    /// because Finder handed us one file, not a folder to watch.
    private func saveDroppedFile(_ url: URL) {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"]
        let textExtensions: Set<String> = [
            "txt", "md", "markdown", "csv", "tsv", "json", "log", "yaml", "yml",
            "xml", "html", "htm", "rtf", "swift", "py", "js", "ts", "css",
        ]
        let ext = url.pathExtension.lowercased()
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        let byteLine = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

        let thing = Thing(kind: .file, title: url.lastPathComponent, content: byteLine,
                          source: "You", sourceRef: "dropped:\(UUID().uuidString)")

        if imageExtensions.contains(ext), let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            // Same target ScreenshotIngest's own thumbnail uses (~480pt,
            // q0.7) — one size, so every previewImageData reader
            // (ThingContent, the Home tray) already knows how to draw it.
            let maxSide: CGFloat = 480
            let scale = min(1, maxSide / max(image.size.width, image.size.height))
            let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1   // downscale render — device scale would triple the byte count for nothing
            let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
            thing.previewImageData = resized.jpegData(compressionQuality: 0.7)
        } else if textExtensions.contains(ext), let body = try? String(contentsOf: url, encoding: .utf8) {
            thing.content = String(body.prefix(300))
        }

        modelContext.insert(thing)
        modelContext.saveHonestly()
        SpotlightIndex.index([thing])
        land(thing, undoable: true)
    }

    /// Dropped text or a link — same path as the composer, same proof. The
    /// composer's parse card was consent; a drop had none, so its toast
    /// carries Undo (§12).
    private func saveDropped(_ text: String) {
        guard let thing = Capture.thing(from: text) else { return }
        modelContext.insert(thing)
        modelContext.saveHonestly()
        SpotlightIndex.index([thing])
        land(thing, undoable: true)
        Task { @MainActor in await LinkTitle.enrich(thing, context: modelContext) }
    }

    /// Makes the share extension's writes visible without a relaunch:
    /// re-assigning a stored property marks an object dirty, the save posts
    /// this context's didSave, and every @Query re-runs — and a fresh fetch
    /// DOES read rows another process committed. Net data change: none.
    /// The newest thing also gets its missed Spotlight pass (the extension
    /// process never indexes).
    private func nudgeAfterExternalCapture() {
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let newest = try? modelContext.fetch(descriptor).first else { return }
        newest.tags = newest.tags
        modelContext.saveHonestly()
        SpotlightIndex.index([newest])
        CorpusSignal.shared.bump()
    }

    /// A finished voice note lands as a voice thing; the transcript is its
    /// content, the audio file rides sourceRef (M6 local half).
    private func saveVoice(transcript: String, sourceRef: String) {
        let title = transcript.isEmpty
            ? "Voice note"
            : {
                let line = transcript.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? transcript
                return line.count > 80 ? String(line.prefix(80)) + "…" : line
            }()
        let thing = Thing(kind: .voice, title: title, content: transcript,
                          source: "Voice", sourceRef: sourceRef)
        // The recording moves INTO the store — externalStorage carries it,
        // and sync can too. The loose file goes; the model owns the bytes.
        if let url = VoiceCapture.audioURL(for: sourceRef),
           let data = try? Data(contentsOf: url) {
            thing.audio = data
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.insert(thing)
        modelContext.saveHonestly()
        SpotlightIndex.index([thing])
        land(thing)
    }

    /// Keep a synthesis answer — the recap lands as a note in your things so
    /// it isn't ephemeral (2026-07-12). A quiet outcome toast, no flight: the
    /// composer is open over the feed, and a proxy card flying behind it reads
    /// as noise. The note is findable and syncs like any other.
    private func keepAnswer(_ text: String) {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        let title = firstLine.count > 80 ? String(firstLine.prefix(80)) + "…" : firstLine
        let thing = Thing(kind: .note, title: title, content: text, source: "You")
        modelContext.insert(thing)
        modelContext.saveHonestly()
        SpotlightIndex.index([thing])
        chrome.flash("Kept — it's in your things", tone: .success)
    }

    /// Every save ends here (§1): toast, and — unless the person is already
    /// watching the record (any feed shape), where the new row IS the
    /// arrival — the proxy-card flight to the "All" chip. The very first
    /// thing ever gets its own toast and always flies (§8). The toast's
    /// `.success` tone carries the haptic, so every caller's commit is felt
    /// exactly once, here.
    private func land(_ thing: Thing, undoable: Bool = false) {
        let first = !firstThingSaved
        if first { firstThingSaved = true }

        if undoable && !first {
            let id = thing.id
            chrome.flash("Saved", tone: .success, action: .init(label: "Undo") {
                undoCapture(id: id)
            }, seconds: 4)
        } else {
            // After a demo, "Your first thing" is the one line that isn't
            // true — the person has just spent minutes among hundreds of
            // things. What is new is that this one is THEIRS, so say that
            // instead. (The demo's own rows never reach `land`; they are
            // poured straight into the context, which is why `first` is still
            // waiting here at all.)
            let firstLine = DemoMode.hasSeen
                ? String(localized: "That one's yours")
                : String(localized: "Your first thing")
            chrome.flash(first ? firstLine : "Saved", tone: .success)
        }

        // "Watching the record" used to mean either feed shape (Pinned or
        // All); the board retired 2026-07-20, so All is the one shape left.
        if sceneState.filter.source == "All" || first {
            chrome.flight = ShellChrome.Flight(kind: thing.kind, title: thing.title)
        }
    }

    /// The drop-toast's Undo: the thing goes, Spotlight forgets it.
    private func undoCapture(id: UUID) {
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.id == id }
        ))) ?? []
        guard let thing = all.first else { return }
        modelContext.delete(thing)
        modelContext.saveHonestly()
        SpotlightIndex.remove(ids: [id])
        withAnimation(DS.Motion.standard) {
            chrome.toast = nil
            chrome.toastAction = nil
        }
    }

    /// DEBUG `-noPrewarm` skips warming the model, so the cold first-answer
    /// latency can be measured against the warm path.
    private var skipPrewarm: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "noPrewarm") != nil
        #else
        return false
        #endif
    }

    /// The person's OWN tags — every tag minus the built-in kind tags (Link,
    /// Note, …, which every thing wears automatically) — with how many things
    /// carry each, biggest first, the name breaking ties.
    private func tagCounts(in all: [Thing]) -> [(tag: String, count: Int)] {
        let typeTags = Set(ThingKind.allCases.map { $0.typeTag.lowercased() })
        var counts: [String: Int] = [:]
        for thing in all {
            for tag in thing.tags where !typeTags.contains(tag.lowercased()) {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (tag: $0.key, count: $0.value) }
    }

    /// "what tags do i have" — the tag set, computed. A list shows the tag
    /// treemap (tap a cell to open that tag, the same push Home makes); a
    /// count answers in one line. No tags yet points at how tags get made
    /// (honesty rule: no dead end).
    private func tagsDoc(_ ask: TagsAsk.Intent, in all: [Thing]) -> [String] {
        let counts = tagCounts(in: all)
        guard !counts.isEmpty else {
            let line = "No tags yet — they arrive from imports, bridges, and #hashtags."
            return ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"]
        }
        switch ask {
        case .count:
            let line = String(localized: "You have \(counts.count) tag.")
            return ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"]
        case .list:
            let n = counts.count
            let line = n > 6
                ? "\(n) tags — tap one to open it."
                : String(localized: "You have \(n) tag — tap one to open it.")
            // TagMap caps at 6 cells; hand it the biggest, "Label Count" each.
            let cells = counts.prefix(6).map { "\(tagMapLabel($0.tag)) \($0.count)" }
            return ["root = Stack([ins, map])",
                    "ins = Insight(\"\(genSafe(line))\")",
                    "map = TagMap(\"\(genSafe(String(localized: "Your tags")))\", null, [\(cells.joined(separator: ", "))])"]
        }
    }

    /// "what apps do you have" — the app set, computed. Connected seats speak
    /// first (names, plus an honest attention count); a catalog ask answers by
    /// size with a taste of names. Every variant carries the catalog door —
    /// the same "@apps" card the quiet day's slot uses — so the answer opens
    /// the real Apps surface instead of dead-ending in prose.
    private func appsDoc(_ ask: AppsAsk.Intent) -> [String] {
        let seats = bridges.bridges
        let shelf = BridgeCatalog.offers.filter(\.connectable)
        let emptyLine = "No apps connected yet — the catalog has \(shelf.count) ready to connect."
        let line: String
        switch ask {
        case .count:
            line = seats.isEmpty
                ? emptyLine
                : "You've connected \(seats.count) of the \(shelf.count) apps in the catalog."
        case .connected:
            if seats.isEmpty {
                line = emptyLine
            } else {
                var l = String(localized: "You've connected \(seats.count) app — \(naturalList(seats.map(\.name))).")
                let needs = bridges.attentionCount
                if needs > 0 { l += " " + String(localized: "\(needs) need attention.") }
                line = l
            }
        case .catalog:
            line = seats.isEmpty
                ? "\(shelf.count) apps to connect."
                : "\(shelf.count) apps to connect — you've connected \(seats.count)."
        }
        return ["root = Stack([ins, door])",
                "ins = Insight(\"\(genSafe(line))\")",
                "door = AppsInvite(\"\(genSafe(String(localized: "Browse the catalog")))\", \"\")"]
    }

    /// Names as a sentence — "A, B, and C", folding overflow into "N more"
    /// (a 20-seat answer should scan, not scroll).
    private func naturalList(_ names: [String], max: Int = 6) -> String {
        var parts = Array(names.prefix(max))
        if names.count > parts.count { parts.append("\(names.count - parts.count) more") }
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ")
            + (parts.count == 2 ? " and " : ", and ") + parts.last!
    }

    /// A tag name safe as a bare TagMap cell label — a comma or bracket would
    /// break the cell list's grammar, and the trailing count is its own token.
    private func tagMapLabel(_ tag: String) -> String {
        genSafe(tag)
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
    }

    /// How an Ask gets answered. Lookups ("find X", "what did I save") want a
    /// structured list, so they use guided generation → a Widget of real things
    /// (the strong honesty rail: the model returns indices, never free text).
    /// Open synthesis ("what's my week", "recap") wants a short summary, so it
    /// streams plain prose. The router leans to lookup when unsure — structure
    /// is the safer default.
    private enum AnswerMode { case lookup, synthesis }

    /// True when the ask carries an explicit retrieval verb — an unambiguous
    /// lookup signal, so routing can take the fast heuristic and skip the
    /// model round-trip (`resolvedMode`). These win outright, even over a
    /// temporal cue ("what did I save this week" is still a lookup).
    private func hasLookupVerb(_ query: String) -> Bool {
        let q = query.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        let lookupVerbs = ["find", "search", "show", "save", "saved",
                           "where", "which", "list", "look up"]
        return lookupVerbs.contains(where: q.contains)
    }

    private func answerMode(_ query: String) -> AnswerMode {
        // Smart punctuation types U+2019 — "what's my week" must match the
        // "what's my" cue whichever apostrophe the keyboard chose.
        let q = query.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        if hasLookupVerb(query) { return .lookup }
        // Otherwise a reflection/summary cue routes to prose. The status
        // cues ride along so a content-qualified status ask ("what's
        // happening with bitcoin") streams prose like its bare form would —
        // one phrase family, one answer shape (review 2026-07-11).
        let synthesisCues = ["what's my", "whats my", "how was", "how's my", "hows my",
                             "summar", "synthes", "digest", "tl;dr", "tldr",
                             "recap", "overview", "catch me up", "my week",
                             "my day", "my month", "lately", "what did i do",
                             "what have i", "going on", "highlights",
                             "happening", "what's new", "whats new", "anything new",
                             "what's up", "whats up", "fill me in", "the latest",
                             "did i miss"]
        if synthesisCues.contains(where: q.contains) { return .synthesis }
        return .lookup
    }

    /// The routing decision, model-refined (2026-07-15). An explicit retrieval
    /// verb is unambiguous — take the fast heuristic, no model call. Otherwise
    /// the on-device model routes (its read beats any hand-enumerated cue list);
    /// when it's unavailable or declines, the keyword heuristic stands in —
    /// zero regression on non-Apple-Intelligence devices.
    private func resolvedMode(_ query: String) async -> AnswerMode {
        if hasLookupVerb(query) { return .lookup }
        if let plan = await QueryPlan.make(query) {
            return plan.synthesis ? .synthesis : .lookup
        }
        return answerMode(query)
    }

    /// The answer path. The scoring engine always runs first and grounds the
    /// answer (RAG retriever + universal fallback). On Apple-Intelligence
    /// devices the free on-device model answers over the SAME retrieved things,
    /// two ways by intent: a lookup composes a Widget of the real things it
    /// picked (never invents one); a synthesis streams a short plain summary,
    /// growing through `onProseDoc`, grounded on those same things. Everywhere
    /// else — or if the model declines — the scoring doc paints unchanged (zero
    /// regression). `onProseDoc` fires only while prose streams; lookups and the
    /// fallback never call it and return one doc to reveal at once.
    /// `onPartialDoc` is the brief's own early-paint channel — see
    /// `Composer.answer` for why it is separate from `onProseDoc`.
    private func answerDocument(_ query: String,
                                onProseDoc: @escaping ([String]) -> Void,
                                onPartialDoc: @escaping ([String]) -> Void = { _ in }) async -> [String] {
        // TAP → FIRST PAINT, measured here because this is the ONE funnel every
        // ask goes through — a typed question, a kept chip, the whisper's tap,
        // the brief. See `AskClock` for why the existing answer metric cannot
        // see this span. DEBUG-only and free in release, the bargain
        // `LaunchPerf`'s span markers already make.
        //
        // The two channels are wrapped rather than instrumented at their call
        // sites: there are five of those and they are exactly the kind of list
        // that goes stale, where a wrapper here covers a branch added later for
        // free.
        #if DEBUG
        let askClock = AskClock(query)
        defer { askClock.settled() }
        let rawProse = onProseDoc, rawPartial = onPartialDoc
        let onProseDoc: ([String]) -> Void = { doc in askClock.paint("prose"); rawProse(doc) }
        let onPartialDoc: ([String]) -> Void = { doc in askClock.paint("partial"); rawPartial(doc) }
        #endif
        // How long the brief's own compose stands off after painting the
        // cached document, so the rise animation gets the main actor
        // (PERF 2026-08-18; see the `TodayBrief.matches` branch below).
        // Roughly the bar→surface morph's own spring response — long enough to
        // cover the frames that make the open feel smooth, short enough to
        // disappear into the seconds the live reads take anyway.
        let briefRiseHoldMS = 250
        // The named-ask ellipsis reads the PREVIOUS answer's shape, then this
        // call resets it — set back to non-nil only when a named ask answers
        // below (`answerNamedAsk`), so any other kind of answer turns the
        // ellipsis off for the next query (§176).
        let priorNamedSynth = lastNamedAskSynth
        lastNamedAskSynth = nil
        // A count/superlative ask is ARITHMETIC, not retrieval — computed
        // over the corpus directly, no model, always correct (2026-07-10).
        // Memoized and LAZY (2026-07-21): this used to fetch the whole corpus
        // unconditionally as the first line of every ask, even ones (wallet,
        // token, apps) that never touch it. `AggregateAsk.parse`/`StatusAsk.pulse`
        // take their corpus argument as an `@autoclosure` for the same reason —
        // together, a plain lookup query now never materializes the corpus here.
        var cachedAllThings: [Thing]?
        func allThings() -> [Thing] {
            if let cachedAllThings { return cachedAllThings }
            let fetched = fullCorpus()
            cachedAllThings = fetched
            return fetched
        }
        func knownSources() -> [String] { Array(Set(allThings().map(\.source))) }
        // A tag-vocabulary ask ("what tags do i have", "how many tags") is
        // answered from the tag SET itself — computed, never the model, always
        // correct. Runs BEFORE AggregateAsk so "how many tags" counts tags, not
        // things, and before retrieval so the literal words never become search
        // terms and surface noise (2026-07-12).
        if let tagsAsk = TagsAsk.parse(query) {
            // Arithmetic answers carry no retrieval grounding — clear the last
            // hits so a keyed retry re-retrieves for THIS question instead of
            // silently grounding on a previous one's evidence (review 2026-07-13).
            lastAnswerHits = []
            return tagsDoc(tagsAsk, in: allThings())
        }
        // An apps ask ("what apps do you have") is a meta-question about the
        // app set — connected seats + the catalog — answered computed, never
        // the model. Before AggregateAsk so "how many apps" counts apps, not
        // things, and before retrieval so "apps"/"have" never become search
        // terms and surface noise (the bug: this ask fell through to the
        // term-scored retriever and answered with unrelated things, 2026-07-17).
        if let appsAsk = AppsAsk.parse(query) {
            lastAnswerHits = []
            return appsDoc(appsAsk)
        }
        if let agg = AggregateAsk.parse(query, sources: knownSources()) {
            lastAnswerHits = []
            // A superlative names a THING, so it answers with that thing beside
            // the line — a count alone would make the person search for the
            // post it just told them about (2026-08-05, prd §307). Falls
            // through to ordinary retrieval when nothing in scope carries the
            // number, rather than asserting a winner that doesn't exist.
            if case .topThing(let metric, let source, let range, let words) = agg {
                if let best = AggregateAsk.topThing(metric: metric, source: source,
                                                    range: range, rangeWords: words,
                                                    things: allThings()) {
                    lastAnswerHits = [best.thing]
                    return ["root = Stack([ins, res])",
                            "ins = Insight(\"\(genSafe(best.line))\")"]
                        + groundingLines([best.thing], title: "The post")
                }
            } else {
                let line = AggregateAsk.answer(agg, things: allThings())
                return ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"]
            }
        }
        // "How's my day?" — the Today brief (prd §166), the screen the whisper
        // capsule opens. Answers THROUGH the composer itself so the typed ask,
        // the kept pill, and the whisper's tap can never drift (the §132
        // principle). Before the wallet/watchlist branches: this ask spans
        // them, and its own words ("today", "my day") never collide with
        // theirs.
        if TodayBrief.matches(query) {
            lastAnswerHits = []
            // THE LAST BRIEF, INSTANTLY (prd §386k). The rise lands on the
            // brief now (§386d), so every bar tap pays `allThings()` — an
            // unbounded main-actor hydration, the exact class the 08-13 ask
            // fix removed from the kept chips — before one pixel of document
            // paints. Painting this session's previous doc through the
            // partial channel makes the rise feel instant; the fresh partial
            // replaces it the moment the corpus half composes, and the
            // quiet-set then says honestly what didn't change. SESSION-ONLY
            // (`AgentOpenCache`'s own trade): a doc from a previous launch
            // could be a day stale, but within a session it is minutes old
            // and about to be corrected either way.
            var paintedCached = false
            if let cached = TodayBrief.lastPresentedDoc {
                onPartialDoc(cached)
                paintedCached = true
                // …AND THE PAINT NEEDS A FRAME TO HAPPEN IN (PERF 2026-08-18).
                //
                // `onPartialDoc` publishes into `GenStream`; the pixels arrive
                // on the next render pass. `allThings()` below is an unbounded
                // main-actor hydration with no yield point inside it, and it
                // sat in the SAME run-loop turn — so the cached doc could not
                // paint before the fetch blocked, and §386k's "instantly" was
                // instant only in the sense that the work started immediately.
                // One yield is what turns a published document into a drawn
                // one; the composer's own `.task(id: isOpen)` makes exactly
                // this move for exactly this reason.
                await Task.yield()
                // Then hold the actor free while the rise animation runs. The
                // morph is a spring, and it needs frames more than the fresh
                // compose needs a 250ms head start — the document on screen is
                // already a real brief, minutes old, and the live reads it is
                // waiting on cost seconds. ONLY when something painted: an
                // empty surface must never be made to wait.
                try? await Task.sleep(for: .milliseconds(briefRiseHoldMS))
            }
            // THE CORPUS-ONLY DRAFT STANDS DOWN WHEN A CACHED DOC PAINTED
            // (PERF 2026-08-18). `TodayBrief.compose` paints a second document
            // before its live reads settle — composed with `skipLiveReads`, so
            // it carries NO money hero, no movers, no cluster map. Over an
            // empty surface that is a real gain. Over the cached doc it is a
            // REGRESSION dressed as progress: the reader watches a complete
            // brief lose three modules and then grow them back, and pays a
            // full corpus compose plus a full document mount for the
            // privilege. Nothing is withheld — the fresh document replaces it
            // either way, bounded by `liveReadBudget`.
            //
            // `askPerf| firstPaint` is unaffected: the cached paint goes
            // through this same wrapped channel, so the span still ends at the
            // first pixel rather than at the first partial.
            let partial: (([String]) -> Void)? = paintedCached ? nil : onPartialDoc
            // `presenting: true` — this is the route every way of REACHING the
            // brief funnels through (the typed ask, the whisper's tap, the
            // kept pill), so it's the one place the §214 ledger should record
            // what was shown.
            if let result = await KeptAskComposers.compose("today", things: allThings(),
                                                          context: modelContext,
                                                          presenting: true,
                                                          onPartial: partial) {
                return result.doc
            }
        }
        // The agent's own deterministic notice (prd §384) — the glint's chip
        // sends exactly this query. The line plus its EVIDENCE rows, so the
        // claim is checked rather than believed; a day with no notice says so
        // honestly instead of falling through to retrieval on the word
        // "notice".
        if AgentNoticed.matches(query) {
            lastAnswerHits = []
            guard let notice = AgentNoticed.shared.notice else {
                return proseDoc(String(localized: "Nothing noticed today — the glint only lights for something real."))
            }
            let ids = Set(notice.ids)
            let evidence = allThings().filter { ids.contains($0.id.uuidString) }
            lastAnswerHits = evidence
            var doc = ["root = Stack([\(evidence.isEmpty ? "ins" : "ins, res")])",
                       "ins = Insight(\"\(genSafe(notice.line))\")"]
            if !evidence.isEmpty {
                doc += groundingLines(evidence, title: String(localized: "The evidence"))
            }
            return doc
        }
        // A watchlist ask ("how's my watchlist") is answered from the same
        // 24h curves the feed pulse draws — computed, current, no model
        // (2026-07-14). Before StatusAsk on purpose: the words name the
        // watchlist, not the feeds.
        if TokensAsk.matches(query) {
            lastAnswerHits = []
            // The last reading, while the candle fetches are out (PERF
            // 2026-08-13) — this branch's whole latency is network, so without
            // it the person watches a breathing berry to be told a number the
            // app computed on the last foreground. Nil until a pass has
            // computed one, so it can never invent a figure.
            if let interim = lastKnownDoc("watchlist") { onPartialDoc(interim) }
            let moves = await TokensAsk.moves(context: modelContext)
            // Watched prediction markets are a watchlist too (2026-07-28) —
            // read from PredictionPulse's existing cache, so this costs no
            // request and can't disagree with the feed rows.
            let markets = MarketsAsk.moves(context: modelContext)
            guard !moves.isEmpty || !markets.isEmpty else {
                // Empty MOVES isn't an empty WATCHLIST — offline, every pulse
                // fetch fails and a "nothing watched" line would be a fake
                // status (honesty rule). Say which nothing this is.
                let watchesNothing = TokensAsk.watched(modelContext).isEmpty
                    && MarketsAsk.watched(modelContext).isEmpty
                return proseDoc(watchesNothing
                    ? "Nothing watched yet — add one from Apps."
                    : "Couldn't read your watchlist's prices right now — check your connection.")
            }
            // TokenChip rows alongside the summary — `KeptAskComposers.watchlistDoc`
            // so a typed ask and the kept "How's my watchlist?" chip can never
            // disagree about what's shown.
            let line = moves.isEmpty ? MarketsAsk.line(markets) : TokensAsk.line(moves)
            return KeptAskComposers.watchlistDoc(line: line, moves: moves, markets: markets)
        }
        // A wallet ask ("how's my wallet") is answered from the live holdings
        // and the forward-only value line — computed, no model (2026-07-15).
        // Before StatusAsk on purpose: the word "wallet" names the holdings, not
        // the feeds' pulse.
        if WalletAsk.matches(query) {
            lastAnswerHits = []
            // The LOCAL half first (PERF 2026-08-13). The approvals and the
            // activity below are rows the bridges already landed, so they can
            // be on screen while the two live reads are still out; only the
            // headline and the treemap actually wait on the network. Scoped to
            // the two rooms `walletDoc` reads rather than the whole store.
            let corpus = keptCorpus(for: "wallet")
            if let interim = lastKnownDoc("wallet", things: corpus) { onPartialDoc(interim) }
            guard let line = await WalletAsk.answer() else {
                return proseDoc(String(localized: "Nothing in your wallet yet — watch an address from Apps → Wallet."))
            }
            // The real holdings treemap alongside the summary, plus the
            // landed approvals + latest activity — shared with the kept-ask
            // composer via `KeptAskComposers.walletDoc` so the two paths agree.
            let groups = await WalletIngest.topHoldingsByWallet()
            // `.live` AFTER the live reads (liveness corollary 6, build 250).
            // `corpus` is fetched above, before two awaits that can take
            // seconds, and the app's own foreground sweep deletes rows in
            // exactly that window — reading a stored property on a tombstoned
            // `Thing` traps inside SwiftData, with the app possibly not even
            // in the foreground. The old code fetched HERE, below the awaits,
            // and got this for free; moving the fetch above them so the local
            // half can paint early is precisely what makes the guard load-
            // bearing. One filter at the last await is sufficient because this
            // is `@MainActor` and nothing below suspends.
            return KeptAskComposers.walletDoc(line: line, groups: groups, things: corpus.live)
        }
        // "What's coming up?" — the forward deadlines, computed, no model
        // (2026-07-21). This branch is what makes the typed ask agree with the
        // kept chip: without it the words fall through to retrieval, and since
        // no THING contains the phrase "coming up", a corpus with two live
        // deadlines answered "nothing in your things matches that" (measured
        // on-sim). "Overdue" only ever appeared to work here because it is a
        // word a reminder itself retrieves on — an accident of vocabulary, not
        // a branch. Answers through the composer itself rather than a parallel
        // builder, so the two paths cannot drift (the §132 principle).
        // "On this day" across every imported room (2026-08-05, prd §310).
        // Before `matchesUpcoming` because the two vocabularies don't collide
        // and this one is more specific; answered through the composer itself
        // so the typed ask and a kept pill can never drift (§132).
        // "Where did my money go?" across Peer, the two cards and 0xBow
        // (2026-08-05, prd §311). Before the wallet branches: those answer
        // about HOLDINGS, this answers about MOVEMENT, and the words don't
        // collide.
        if KeptAskComposers.matchesMoneyFlow(query) {
            lastAnswerHits = []
            if let result = await KeptAskComposers.compose("moneyflow",
                                                          things: keptCorpus(for: "moneyflow"),
                                                          context: modelContext) {
                return result.doc
            }
        }
        // "What did I spend?" — the card seats' own arithmetic (prd §317).
        // AFTER money-flow, whose phrasings this one deliberately doesn't
        // claim: "where did my money go" spans four seats and answers better
        // than a total, so the broader question keeps the broader answer.
        if KeptAskComposers.matchesSpend(query) {
            lastAnswerHits = []
            if let result = await KeptAskComposers.compose("spend",
                                                          things: keptCorpus(for: "spend"),
                                                          context: modelContext) {
                return result.doc
            }
        }
        // The wallet-riding seats' own standing questions (prd §311). After
        // the money-flow branch, which spans them, and before the generic
        // named-ask path, whose prefix table these phrasings don't match.
        if let seat = KeptAskComposers.matchesSeatAsk(query) {
            lastAnswerHits = []
            if let result = await KeptAskComposers.compose("context:" + seat,
                                                          things: keptCorpus(for: "context:" + seat),
                                                          context: modelContext) {
                return result.doc
            }
        }
        if KeptAskComposers.matchesThrowback(query) {
            lastAnswerHits = []
            if let result = await KeptAskComposers.compose("throwback",
                                                          things: keptCorpus(for: "throwback"),
                                                          context: modelContext) {
                return result.doc
            }
        }
        if KeptAskComposers.matchesUpcoming(query) {
            lastAnswerHits = []
            if let result = await KeptAskComposers.compose("upcoming",
                                                          things: keptCorpus(for: "upcoming"),
                                                          context: modelContext) {
                return result.doc
            }
        }
        // A DeFi ask ("how's my loan", "what's my health factor", "how are
        // my Morpho vaults") — live read over Aave + Spark + Morpho, no
        // model (2026-07-20; Morpho 2026-07-21, Spark 2026-07-30). Same slot
        // as WalletAsk, right after it: both need a watched wallet, and
        // "aave"/"morpho"/"health factor" never collides with the generic
        // wallet words (bare "spark" deliberately isn't one of the triggers
        // — see `WalletDeFiAsk`'s own doc comment).
        if WalletDeFiAsk.matches(query) {
            lastAnswerHits = []
            guard let line = await WalletDeFiAsk.answer() else {
                return proseDoc(String(localized: "Nothing to read yet — watch an address from Apps → Wallet."))
            }
            return proseDoc(line)
        }
        // A Uniswap LP ask ("how's my uniswap position", "am I in range") —
        // live read, no model (2026-07-30). Same slot as the DeFi ask, right
        // after it: `UniswapAsk` is a sibling to `WalletDeFiAsk`, not folded
        // into it, since a liquidity position isn't a loan.
        if UniswapAsk.matches(query) {
            lastAnswerHits = []
            guard let line = await UniswapAsk.answer() else {
                return proseDoc(String(localized: "Nothing to read yet — watch an address from Apps → Wallet."))
            }
            return proseDoc(line)
        }
        // A gas ask ("what have I spent on gas") — live read, no model.
        if WalletGasAsk.matches(query) {
            lastAnswerHits = []
            guard let line = await WalletGasAsk.answer() else {
                return proseDoc(String(localized: "Nothing to read yet — watch an address from Apps → Wallet."))
            }
            return proseDoc(line)
        }
        // A Safe ask ("anything pending on my Safe") — live read, no model.
        if SafeAsk.matches(query) {
            lastAnswerHits = []
            guard let line = await SafeAsk.answer() else {
                return proseDoc(String(localized: "Nothing to read yet — watch an address from Apps → Wallet."))
            }
            return proseDoc(line)
        }
        // A named source/publisher ask ("synthesize my Verge feed", "what
        // happened in BBC", the existing "what's new in Calendar"/"how's my
        // GitHub") — 2026-07-22, recognized via the SAME
        // `KeptAskComposers.namedAskTarget` the kept-pill minting uses (see
        // Composer.recognizeKeptAskKind), so a fresh ask and its kept re-run
        // can never disagree about which real entity it named, or what its
        // deterministic recap says. Checked BEFORE StatusAsk on purpose: a
        // query naming a real source/publisher would otherwise reach
        // StatusAsk's cue check, get REJECTED by its filler-word gate (the
        // name survives filler-stripping as a leftover content word), and
        // fall through anyway — checking here first just skips that
        // always-failing detour.
        if let doc = await answerNamedAsk(query, things: allThings(), onProseDoc: onProseDoc, onPartialDoc: onPartialDoc) {
            return doc
        }
        // Follow-up ellipsis (2026-07-22, §176): after a per-source/publisher
        // answer, a bare "and bbc?" / "what about calendar" re-runs the SAME
        // shape (recap vs. synthesize) with the new entity — the natural
        // conversational follow-up. Fires ONLY when the last answer was itself
        // a named ask (`priorNamedSynth` non-nil, captured at the top before
        // this call reset it) AND the residual names a real entity — so it
        // never hijacks an ordinary short query.
        if let synth = priorNamedSynth, let entity = ellipsisEntity(query) {
            let rebuilt = (synth ? "synthesize " : "what happened in ") + entity
            if let doc = await answerNamedAsk(rebuilt, things: allThings(), onProseDoc: onProseDoc, onPartialDoc: onPartialDoc) {
                return doc
            }
        }
        // A status ask ("tell me what's going on") names no content to score,
        // so it grounds on recency itself: the newest things from every source
        // in a recent window — the feeds' pulse. The model synthesizes over
        // that sample; everywhere else the counted pulse line answers
        // (2026-07-11).
        if let pulse = StatusAsk.pulse(query, things: allThings()) {
            lastAnswerHits = pulse.sample
            // The away recap's watchlist line (2026-07-14): watched tokens'
            // moves over the frozen away window, from real candles — the one
            // fact of the absence the corpus' things can't carry themselves.
            // Started here, awaited only when the doc is assembled, so the
            // candle fetches ride under the model's own synthesis time.
            let context = modelContext
            let awayWindow = (pulse.windowWords == "while you were away") ? AppVisit.away : nil
            let tokenLineTask: Task<String?, Never>? = awayWindow.map { away in
                Task { await TokensAsk.awayLine(window: away, context: context) }
            }
            func tokenLine() async -> String? {
                guard let tokenLineTask else { return nil }
                return await tokenLineTask.value
            }
            // The wallet's own away line (2026-07-15) — the value's move over the
            // window, read from local samples (no network), so it needs no task.
            let walletLine = awayWindow.flatMap { WalletAsk.awayLine(window: $0) }
            guard !pulse.pool.isEmpty else {
                return appendingInsight(await tokenLine(), walletLine, to: proseDoc(StatusAsk.line(pulse)))
            }
            if let prose = await streamSynthesis(query,
                                                 over: candidates(pulse.sample,
                                                                  terms: Retriever.contentTerms(query)),
                                                 document: proseDoc,
                                                 onProseDoc: onProseDoc) {
                // Prose, then its away/wallet addenda, then the receipts it
                // was drawn from — the status synthesis success now shows its
                // grounding too, like the counted `pulseDoc` fallback already
                // does (§175).
                let doc = appendingInsight(await tokenLine(), walletLine, to: proseDoc(prose))
                return appendingGrounding(pulse.sample, title: "Drawn from", to: doc)
            }
            return appendingInsight(await tokenLine(), walletLine, to: pulseDoc(pulse))
        }
        // A follow-up ("which ones were from sam") searches the LAST
        // answer's grounding, not the whole corpus (2026-07-10).
        let pool = isFollowUp(query) && !lastAnswerHits.isEmpty ? lastAnswerHits : nil
        var hits = retrieve(query, in: pool)
        // SEMANTIC RECALL (2026-08-07). The keyword retriever finds only things
        // that share WORDS with the query; the sentence embedding meant to
        // bridge vocabulary gaps contributes almost nothing on a real corpus
        // (measured, `-rankSweep` — byte-identical across every floor), so a
        // paraphrase ("that beach place" for a "coastal property" note) comes
        // back empty. When a FRESH ask lands thin and the on-device model is
        // present, it rephrases the query into concrete terms and we UNION
        // anything new those reach — the SAME deterministic retriever, so every
        // hit is still a real ranked thing (honesty rail intact). Purely
        // additive: primary ranking is untouched, and it's a no-op when the ask
        // wasn't thin, the model declines, or there's no model (zero
        // regression). Skipped for a follow-up (its pool is deliberately the
        // last answer's things, and a widened search would lose that anchor).
        if pool == nil, hits.count < 8, OnDeviceModel.isAvailable,
           let phrases = await OnDeviceModel.expandQuery(query) {
            var seen = Set(hits.map(\.id))
            for phrase in phrases {
                for extra in retrieve(phrase, in: nil) where seen.insert(extra.id).inserted {
                    hits.append(extra)
                }
                if hits.count >= 16 { break }
            }
            hits = Array(hits.prefix(16))
        }
        lastAnswerHits = hits
        // If the query names a tag ("about work"), the answer opens with that
        // tag's tile — tap it to open the tag's view, the same push the Home
        // treemap makes (PRD §17: a topic opens its view, not a Feed filter).
        let tag = matchedTag(query, in: allThings())
        guard OnDeviceModel.isAvailable, !hits.isEmpty else {
            return retrievalDoc(hits, tag: tag, in: allThings())
        }
        switch await resolvedMode(query) {
        case .lookup:
            // The fast COMPOSE path is the default: it answers over the
            // keyword+semantic retriever's set, which ranks BETTER than the
            // agent's keyword-only tools and returns in ~half the time. The
            // tool-calling AGENT only earns its extra latency when that retrieval
            // came back THIN — a couple of hits — where its whole-corpus,
            // multi-hop search has room to round the answer out (gate added
            // 2026-07-15; the count is the qualifying-hit count, so a bare
            // kind/date list — many hits — correctly stays on the fast path). A
            // FOLLOW-UP ("which of those…") always stays on compose so
            // "those"/"them" keep meaning the last answer's things — the agent
            // searches everything and has no such anchor. Both ground on real
            // things (honesty rail): tool hits map back to real rows, and the
            // model never invents one. Threshold is a one-line tunable — raise
            // it to lean on the agent, lower it to lean on speed.
            let followUp = isFollowUp(query) && !lastAnswerHits.isEmpty
            let retrievalThin = hits.count < 4
            // A lookup gets a figure too (2026-08-16). `.synthesis` has led with
            // one since §384 and this branch never did, which made the picture
            // an accident of which mode the router happened to pick rather than
            // a property of having retrieved something. Computed HERE for the
            // same two reasons the synthesis arm states: the rows are live at
            // this instant and only the finished `String` crosses the await
            // (corollary 6 out of reach), and the figure is stable from the
            // first painted frame.
            //
            // The tools arm re-derives its own below, because it answers over
            // `grounded` — a DIFFERENT set, found by the agent's own search —
            // and a figure drawn from the pre-retrieval would be a picture of
            // rows that are not the ones underneath it.
            let lookupFigure = AnswerFigure.line(for: hits)
            #if DEBUG
            NSLog("[Casberi] lookup route: %d hits, followUp=%@ → %@", hits.count,
                  followUp ? "yes" : "no",
                  (!followUp && retrievalThin) ? "agent" : "compose")
            #endif
            if !followUp, retrievalThin,
               let result = await AnswerTools.answer(
                   query: query, corpus: toolSnapshot(terms: Retriever.contentTerms(query))) {
                let grounded = things(forIDs: result.hitIDs)
                if !grounded.isEmpty {
                    lastAnswerHits = grounded
                    let toolFigure = AnswerFigure.line(for: grounded)
                    return AnswerFigure.prepending(
                        toolFigure,
                        to: modelDoc(insight: toolFigure == nil ? result.prose
                                                                : AnswerFigure.caption(result.prose),
                                     hits: grounded,
                                     picks: Array(grounded.prefix(6).indices),
                                     tag: tag, in: allThings()))
                }
                // Tools found nothing the pre-retrieval didn't — fall through to
                // compose over `hits` (the stronger semantic retriever's set).
            }
            guard let answer = await OnDeviceModel.compose(
                query: query,
                candidates: candidates(hits, terms: Retriever.contentTerms(query))) else {
                // The fallback keeps its figure: the model declining is exactly
                // when the app's own arithmetic is the whole answer.
                return AnswerFigure.prepending(
                    lookupFigure, to: retrievalDoc(hits, tag: tag, in: allThings()))
            }
            return AnswerFigure.prepending(
                lookupFigure,
                to: modelDoc(insight: lookupFigure == nil ? answer.insight
                                                         : AnswerFigure.caption(answer.insight),
                             hits: hits, picks: answer.picks, tag: tag, in: allThings()))
        case .synthesis:
            // The app's own arithmetic over the same rows the model is about to
            // read — where they came from, or when they landed (`AnswerFigure`,
            // 2026-08-15). Computed HERE, before the await, for two reasons that
            // both matter: the hits are live at this instant and are not read
            // across the suspension (only the finished `String` is captured, so
            // the whole corollary-6 class is out of reach), and the figure is
            // then stable from the FIRST painted frame — the prose grows
            // beneath a picture that is already there, rather than a chart
            // popping in after the typewriter settles.
            let figure = AnswerFigure.line(for: hits)
            // The prose is a CAPTION once a figure leads it (2026-08-16) — the
            // picture is the app's own arithmetic and the sentence is the one
            // part of this screen that can be wrong, so it does not get to be
            // the largest thing on it. With no figure the prose IS the answer
            // and is left whole; `caption` is never called on that path.
            //
            // Applied to the STREAMED snapshots too, not just the settled doc,
            // and that is the point rather than a side effect: the caption
            // writes itself and then stops, instead of growing for a paragraph
            // and being cut at the last frame under the reader's eyes.
            func captioned(_ text: String) -> [String] {
                proseDoc(figure == nil ? text : AnswerFigure.caption(text))
            }
            guard let prose = await streamSynthesis(
                query, over: candidates(hits, terms: Retriever.contentTerms(query)),
                document: captioned,
                onProseDoc: { onProseDoc(AnswerFigure.prepending(figure, to: $0)) }) else {
                return synthesisEmptyDoc(hits)
            }
            // The figure, the prose, and the retrieved things it was drawn from
            // as tappable receipts (§175).
            return appendingGrounding(hits, title: "Drawn from",
                                      to: AnswerFigure.prepending(figure, to: captioned(prose)))
        }
    }

    /// A named source/publisher/person ask ("synthesize my Verge feed", "what
    /// happened in BBC", "what did Sam send", the existing "what's new in
    /// Calendar"/"how's my GitHub") — recognized via the SAME
    /// `KeptAskComposers.namedAskTarget` the kept-pill minting uses
    /// (Composer.recognizeKeptAskKind), so a fresh ask and its kept re-run can
    /// never disagree about which real entity it named. Returns nil when the
    /// query names no real entity, so the caller falls through.
    ///
    /// "synthesize"/"summarize"/"recap" asks for the model's OWN prose over the
    /// same pool the deterministic recap would show — a LIVE-only upgrade
    /// (ruling 13: a kept pill never re-synthesizes, it always re-runs the
    /// plain recap regardless of the minting verb). Honest degradation
    /// throughout: no model, a declined synthesis, or an empty window all fall
    /// to the exact deterministic doc a kept pill would show. Extracted
    /// (2026-07-22, §176) so the ellipsis follow-up can call it with a rebuilt
    /// query. Records `lastNamedAskSynth` so the NEXT query's "and X?" ellipsis
    /// knows this chain's shape.
    ///
    /// `things` is an `@autoclosure` (PERF 2026-08-11). Two things follow, and
    /// the second is the whole point:
    ///
    ///   • A query that names NO entity — the common case, since this is one
    ///     of a dozen branches every ask walks — no longer materialises the
    ///     corpus to find that out. `namedAskTarget` resolves the prefix
    ///     table, the brief scopes and the catalog categories without it.
    ///   • A `.category` ask (the Money/Work/Life chips) is composed over a
    ///     SCOPED fetch instead of the whole corpus. `TodayBrief.compose`
    ///     immediately filters to exactly those sources anyway, so every row
    ///     from every other app was fetched, hydrated and thrown away — on a
    ///     bulk-import corpus that is most of the store, on the main actor,
    ///     before the chip could paint anything.
    private func answerNamedAsk(_ query: String, things fetchAll: @autoclosure () -> [Thing],
                                onProseDoc: @escaping ([String]) -> Void,
                                onPartialDoc: @escaping ([String]) -> Void) async -> [String]? {
        var cachedAll: [Thing]?
        func all() -> [Thing] {
            if let cachedAll { return cachedAll }
            let fetched = fetchAll()
            cachedAll = fetched
            return fetched
        }
        guard let (target, wantsSynthesis) = KeptAskComposers.namedAskTarget(query, things: all())
        else { return nil }
        // The pool this target composes over. A category scopes its own fetch;
        // everything else reads the corpus it was handed. MEMOIZED like
        // `all()` above, and for a reason that only shows on one path: a
        // `.category` ask that ASKS FOR SYNTHESIS ("summarize my Money") reads
        // this once for the synthesis window, and if the model declines it
        // falls through and reads it again for the deterministic recap — two
        // scoped fetches of up to 20,000 hydrated rows for one question.
        var cachedPool: [Thing]?
        func composePool() -> [Thing] {
            if let cachedPool { return cachedPool }
            let pool: [Thing]
            if case .category(let scope) = target { pool = categoryCorpus(scope) } else { pool = all() }
            cachedPool = pool
            return pool
        }
        // Records the shape only when it ACTUALLY answers, so the next query's
        // ellipsis reflects what the person saw — a recognized-but-empty named
        // ask that falls through to another path shouldn't arm "and X?".
        func answered(_ doc: [String]) -> [String] { lastNamedAskSynth = wantsSynthesis; return doc }
        if wantsSynthesis, OnDeviceModel.isAvailable {
            // Scoped for a category (see `composePool`); `target.pool` then
            // narrows it exactly as before — idempotent on an already-scoped
            // array, so the synthesis window is unchanged.
            let pool = target.pool(in: composePool())
            let now = Date.now
            var recent = pool.filter { $0.capturedAt >= now.addingTimeInterval(-3 * 86_400) }
            if recent.isEmpty {
                recent = pool.filter { $0.capturedAt >= now.addingTimeInterval(-7 * 86_400) }
            }
            // An ARCHIVE has no recent window and never will (2026-08-05, prd
            // §307). Both filters above are empty the moment an import
            // finishes, so "summarize my X" could not reach the model at all —
            // it fell to the deterministic recap every time, which is the one
            // shape that can't summarize anything. A bulk-import room hands
            // over its newest instead, which is what the cap below would have
            // taken from a live room anyway.
            if recent.isEmpty {
                recent = pool
                    .filter { !Corpus.isImportReceipt($0)
                              && Corpus.bulkImportSources.contains($0.source) }
                    .sorted { $0.capturedAt > $1.capturedAt }
            }
            if !recent.isEmpty {
                let capped = Array(recent.prefix(16))
                lastAnswerHits = capped
                if let prose = await streamSynthesis(
                    query, over: candidates(capped, terms: Retriever.contentTerms(query)),
                    document: proseDoc,
                    onProseDoc: onProseDoc) {
                    return answered(appendingGrounding(capped, title: "Drawn from", to: proseDoc(prose)))
                }
            }
        }
        lastAnswerHits = []
        // The brief paints its corpus half first (§288 amendment, 2026-08-12)
        // — see `TodayBrief.compose`'s `onPartial`. Routed through the SAME
        // `onProseDoc` channel a streaming synthesis uses, because the
        // composer already repaints on each snapshot and `GenStream.paint`
        // swaps a whole document; nothing new is needed on the display side.
        guard let doc = await KeptAskComposers.compose(target.keptKind, things: composePool(),
                                                       context: modelContext,
                                                       presenting: true,
                                                       onPartial: onPartialDoc)?.doc
        else { return nil }
        return answered(doc)
    }

    /// The whole corpus, newest first — the answer path's unscoped read.
    ///
    /// INSTRUMENTED (2026-08-11) rather than guessed at. "Is the ask slow
    /// because of this fetch or because of the live network reads?" is the
    /// question this pass opened with, and the two need opposite fixes, so the
    /// split is measured instead of argued: this line and `TodayBrief`'s own
    /// `briefPerf|`/`composeTimingDEBUG|` together account for a scoped ask
    /// end to end, in one tap. DEBUG-only and free in release — the bargain
    /// `LaunchPerf`'s span markers already make.
    private func fullCorpus() -> [Thing] {
        #if DEBUG
        let t0 = Date.now
        #endif
        let rows = (try? modelContext.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        ))) ?? []
        #if DEBUG
        NSLog("[Casberi] askPerf| fullCorpus=%dms rows=%d",
              Int(Date.now.timeIntervalSince(t0) * 1000), rows.count)
        #endif
        return rows
    }

    /// Just the rows a BRIEF SCOPE covers (PERF 2026-08-11) — the fetch behind
    /// the Money/Work/Life chips.
    ///
    /// `TodayBrief.compose(category:)` filters to exactly these sources on its
    /// first Stage-1 line, so handing it the whole corpus meant materialising
    /// every row of every unrelated app — fully hydrated, on the main actor —
    /// only to drop them. On a corpus carrying a bulk import that is most of
    /// the store.
    ///
    /// FAILS SAFE, deliberately, and this is why the scoping is worth doing at
    /// all rather than being a risk: an `IN`-shaped predicate is a shape this
    /// codebase has been bitten by before (a `$0.tags.contains(…)` predicate
    /// over a transformable attribute compiles clean and traps at runtime —
    /// see CLAUDE.md). A captured `Set<String>` tested against a plain `String`
    /// column is a different, ordinary construct, but the fallback costs one
    /// line: `try?` swallows a throw and an empty read is treated as no scope
    /// at all, exactly as `scopedCorpus(for:)` already treats its own. So the
    /// worst case here is the performance we had yesterday, never a wrong or
    /// empty answer.
    private func categoryCorpus(_ scope: String) -> [Thing] {
        keptCorpus(for: "category:" + scope)
    }

    /// The rows one kept-ask KIND actually needs, fetched scoped (PERF
    /// 2026-08-13). Generalises `categoryCorpus` above, which was the first
    /// instance of exactly this and covered only the three brief scopes.
    ///
    /// Every kept-ask branch in `answerDocument` used to open with
    /// `allThings()` — `fullCorpus()`, an unbounded fully-hydrated fetch of the
    /// entire store on the main actor — and then hand it to a composer that
    /// filters it down to one or two source rooms on its first line. On a
    /// corpus carrying a bulk import that is the whole felt cost of tapping a
    /// chip, and it is why the agent OPENS fast (its board fetch moved off the
    /// critical path in the 2026-08-11 pass) and a chip tap does not.
    /// `KeptAskComposers.corpusNeed` declares the scope, derived from the same
    /// constants the composers filter on.
    ///
    /// FAILS SAFE, exactly as the category version it replaces did: a `try?`
    /// swallows a throw, and an EMPTY scoped read is treated as no scope at all
    /// and re-fetched whole. So the worst case is the performance we had
    /// yesterday, never a wrong or an empty answer — which matters because a
    /// silently-empty scope here would read as "nothing overdue" / "no card
    /// spending" over a corpus full of both, with every screen still perfect.
    private func keptCorpus(for kind: String) -> [Thing] {
        let need = KeptAskComposers.corpusNeed(for: kind)
        // The ceiling `scopedCorpus` uses: high enough that no real scope is
        // truncated, still a ceiling.
        let ceiling = 20_000
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = ceiling
        switch need {
        case .none:
            // The composer takes no `things` at all — fetching for it was pure
            // waste. Six kinds, every one of them a live read.
            #if DEBUG
            NSLog("[Casberi] keptCorpus| kind=%@ need=none rows=0", kind)
            #endif
            return []
        case .whole:
            return fullCorpus()
        case .sources(let sources):
            guard !sources.isEmpty else { return fullCorpus() }
            descriptor.predicate = #Predicate { sources.contains($0.source) }
        case .dated:
            descriptor.predicate = #Predicate { $0.dueAt != nil }
        case .handle(let handle):
            descriptor.predicate = #Predicate { $0.authorHandle == handle }
        }
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        #if DEBUG
        NSLog("[Casberi] keptCorpus| kind=%@ rows=%d", kind, rows.count)
        #endif
        return rows.isEmpty ? fullCorpus() : rows
    }

    /// What the app ALREADY KNOWS about a kept kind, as a document to paint
    /// while that kind's own reads are still out (PERF 2026-08-13).
    ///
    /// `KeptAskStore.refreshDigests` composes every kept kind on each
    /// foreground and keeps the one-line reading each composer returned
    /// (`currentDeltas`). Tapping the chip then threw that away and recomposed
    /// from scratch — including, for the wallet and the watchlist, live network
    /// reads — so the person watched a breathing berry for the length of a
    /// round trip to be told something the app had computed seconds earlier.
    ///
    /// This is NOT the placeholder doc the 2026-07-20 fix removed. That one
    /// painted the word "Thinking…" inside the answer card's full chrome — an
    /// empty-looking card standing in for content that did not exist. This
    /// paints the last real reading, the same text the panel tile is showing,
    /// and the breathing berry remains the whole loading state. §83 holds
    /// because `currentDeltas` is deliberately never persisted: it is empty at
    /// launch until a foreground pass fills it, so this can only ever show a
    /// figure computed during THIS session, never a stale one restored from
    /// disk. When there is no reading yet, there is no interim — the honest
    /// answer to "what do we know" is nothing, and today's behaviour stands.
    private func lastKnownDoc(_ kind: String, things: [Thing] = []) -> [String]? {
        guard let reading = KeptAskStore.shared.currentDeltas[kind],
              !reading.isEmpty else { return nil }
        // The wallet's document is mostly LOCAL — the approvals and the
        // activity are rows the bridges already landed, and only the headline
        // and the treemap wait on the network. So its interim is the real
        // document minus the parts still in flight, which is the same shape
        // `KeptAskComposers.wallet` already paints when a live read fails.
        if kind == "wallet" {
            return KeptAskComposers.walletDoc(line: reading, groups: [], things: things)
        }
        return ["root = Stack([ins])", "ins = Insight(\"\(genSafe(reading))\")"]
    }

    /// The entity named by a bare follow-up ("and bbc?", "what about calendar",
    /// "how about the verge") — the residual after a leading connective, or the
    /// whole thing when it's just a short name, or nil when the query is a
    /// full sentence that should answer on its own terms (2026-07-22, §176).
    /// Deliberately conservative: at most three words and no question word, so
    /// only a genuine "…and X?" ellipsis qualifies; the caller further gates on
    /// the residual resolving to a real entity.
    private func ellipsisEntity(_ query: String) -> String? {
        // Normalize the curly apostrophe the same way `WalletAsk.matches` and
        // the rest of the ask parsers do, so a contracted "what's" is caught
        // by the query-word guard below rather than slipping through as an
        // entity string (review, 2026-07-22).
        var q = query.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: "? "))
            .trimmingCharacters(in: .whitespaces)
        for lead in ["and how about ", "what about ", "how about ", "and ", "also "] where q.hasPrefix(lead) {
            q = String(q.dropFirst(lead.count)); break
        }
        q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, q.split(separator: " ").count <= 3 else { return nil }
        // A residual that starts with a question/command word is a real query,
        // not an entity — don't rewrite it. Both bare and contracted forms,
        // matching the file's normalization convention.
        let firstWord = q.split(separator: " ").first.map(String.init) ?? q
        let queryWords: Set<String> = ["what", "what's", "whats", "how", "how's", "hows",
                                       "who", "who's", "whos", "when", "where", "why",
                                       "show", "find", "synthesize", "summarize", "recap",
                                       "is", "are", "do", "did", "my"]
        guard !queryWords.contains(firstWord) else { return nil }
        return q
    }

    /// The BYO-key retry (prd §67) — the same question over the SAME evidence
    /// the on-device answer saw (`lastAnswerHits`), synthesized by the person's
    /// own agent key (Claude, ChatGPT, Gemini, Venice, or Bankr), device→API
    /// direct. `onProseDoc` paints each growing chunk as it streams in, the
    /// same live contract `answer`/`streamSynthesis` already give the
    /// composer (2026-07-21) — defaulted so the headless `-byokProbe` hook
    /// needs no change.
    ///
    /// nil means the key or the network failed and the composer words that; an
    /// empty grounding gets an honest line instead, because a stronger model
    /// can't change what's here. A non-empty `keyedHistory` (a keyed
    /// follow-up within the same open conversation) threads prior turns in;
    /// a landed answer whose model named which things it drew on paints the
    /// same grounded "Found" row the on-device lookup path does, via
    /// `modelDoc` — plain prose when it named none.
    private func keyedAnswerDocument(_ query: String,
                                     provider explicitProvider: AgentProvider? = nil,
                                     onProseDoc: @escaping ([String]) -> Void = { _ in })
    async -> Result<KeyedAnswer, AgentAnswerFailure> {
        let hits = lastAnswerHits.isEmpty ? retrieve(query) : lastAnswerHits
        // Bankr answers from the wallet and live markets too, so an empty
        // corpus match still asks; every other agent only re-reads the same
        // evidence, so an empty match gets the honest line instead.
        let provider = explicitProvider ?? AgentKey.active
        // The corpus tools (2026-08-06) — the whole corpus flattened, the same
        // snapshot the on-device tool path already builds. Bankr gets none: it
        // answers from the wallet and live markets rather than from the
        // candidate list at all, so a corpus search is no use to it.
        let corpus = provider == .bankr
            ? [] : toolSnapshot(terms: Retriever.contentTerms(query))
        // The honest line above used to fire whenever the local retrieval came
        // back empty. With tools it fires only for a genuinely empty corpus —
        // an empty retrieval is now exactly the case where a second,
        // differently-worded search is most likely to find something, which is
        // the whole reason the model has tools.
        guard !hits.isEmpty || provider == .bankr || !corpus.isEmpty else {
            return .success(KeyedAnswer(doc: proseDoc(
                "Nothing matches that — a bigger model won't help.")))
        }
        let outcome = await AgentAnswer.synthesize(
            query: query,
            candidates: candidates(hits, terms: Retriever.contentTerms(query)),
            history: keyedHistory,
            provider: provider, corpus: corpus,
            onPartial: { partial in onProseDoc(self.proseDoc(partial)) })
        guard case .success(let result) = outcome else {
            guard case .failure(let failure) = outcome else { return .failure(.empty) }
            return .failure(failure)
        }
        keyedHistory.append(AgentTurn(question: query, answer: result.text))
        let picks = result.picks.filter { hits.indices.contains($0) }
        // Grounding rows now come from two places, and the tool hits LEAD: a
        // thing the model went and found is by construction one the local
        // retrieval missed, so it is the more informative row — and burying it
        // under the candidates it already had would hide the only visible
        // evidence that the tool loop did anything at all.
        let toolHits = things(forIDs: result.toolHitIDs)
        // No `tag:`/`in:` here — `keyedAnswerDocument` never resolves a topic
        // tile the way the on-device lookup route does, and `modelDoc` skips
        // that tile entirely whenever `tag` is nil, so there's no corpus
        // fetch to make for it.
        let doc: [String]
        if toolHits.isEmpty {
            doc = picks.isEmpty ? proseDoc(result.text)
                                : modelDoc(insight: result.text, hits: hits, picks: picks)
        } else {
            // `modelDoc` reads `picks` as indices into the array it is handed,
            // so the two sets merge into one array first — de-duped, since a
            // thing can be both retrieved locally and returned by a tool and
            // must not appear twice under one answer.
            var merged = toolHits
            var seen = Set(toolHits.map(\.id))
            for index in picks where hits.indices.contains(index) {
                let thing = hits[index]
                if seen.insert(thing.id).inserted { merged.append(thing) }
            }
            doc = modelDoc(insight: result.text, hits: merged, picks: Array(merged.indices))
        }
        return .success(KeyedAnswer(doc: doc, searchedWeb: result.searchedWeb,
                                    imagesSeen: result.imagesSeen,
                                    toolRounds: result.toolRounds))
    }

    /// The corpus flattened to a plain `Sendable` snapshot for the tool-calling
    /// agent (AnswerTools) — the newest 2000 things, so a tool's `call` never
    /// reaches SwiftData off its actor. Same evidence shape (title/kind/source/
    /// when + excerpt) the single-shot candidates use.
    private func toolSnapshot(terms: [String] = []) -> [AnswerTools.Snapshot] {
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 2000
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.map { t in
            AnswerTools.Snapshot(id: t.id.uuidString, title: t.title,
                                 kind: t.kind.typeTag, source: t.source,
                                 when: shortTime(t.capturedAt),
                                 text: answerSnippet(t, terms: terms),
                                 // The graph fields (prd §340) — carried on the
                                 // snapshot so `linked_things` can answer from
                                 // the same rows the other tools search, rather
                                 // than reaching back into SwiftData off its
                                 // actor. `mentions` early-outs per field, so a
                                 // row with no URL in it costs a `contains`.
                                 at: t.capturedAt,
                                 link: ThingLinks.canonicalLink(t.content),
                                 mentions: ThingLinksSource.mentions(of: t),
                                 wikilinks: t.wikilinks,
                                 sourceRef: t.sourceRef)
        }
    }

    /// Real things for the ids the tool-calling agent surfaced, in the tool's
    /// SURFACED order (relevance, most relevant first) — the honesty rail: an
    /// agent answer's grounding rows are the real things its tools returned,
    /// never invented. Ids that no longer resolve (a thing deleted mid-answer)
    /// are dropped.
    private func things(forIDs ids: [String]) -> [Thing] {
        let wanted = ids.compactMap { UUID(uuidString: $0) }
        guard !wanted.isEmpty else { return [] }
        let fetched = (try? modelContext.fetch(
            FetchDescriptor<Thing>(predicate: #Predicate { wanted.contains($0.id) }))) ?? []
        let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return wanted.compactMap { byID[$0] }
    }

    /// Retrieved things flattened for the model — the one place the mapping
    /// lives, so every answer path hands the model the same shape.
    private func candidates(_ things: [Thing],
                            terms: [String] = []) -> [OnDeviceModel.Candidate] {
        things.map {
            OnDeviceModel.Candidate(title: $0.title, kind: $0.kind.typeTag,
                                    source: $0.source, when: shortTime($0.capturedAt),
                                    note: answerSnippet($0, terms: terms),
                                    imageData: $0.kind == .screenshot ? $0.previewImageData : nil,
                                    // Read the FULL text, not the excerpt below
                                    // (prd §277) — this is what lets the keyed
                                    // path withhold a screenshot whose secret
                                    // sits past `answerSnippet`'s 300-char cap.
                                    carriesSecret: SecretScan.carriesSecret($0.title + "\n" + $0.content))
        }
    }

    /// A short, single-line excerpt of a thing's body for the model — the
    /// substance the title alone can't carry (a note's text, a chat's gist, a
    /// saved link's fetched article). Empty when nothing adds over the title.
    /// For a bare-URL link the body IS the URL (no prose), so it falls through
    /// to `enrichedText` — the page's own lede — when the fetch landed one.
    /// Capped at 300 so 16 candidates still fit the on-device context window.
    /// When `terms` are given and the body overflows the cap, the excerpt is
    /// CENTERED on the first query-term hit (prd §318, `Retriever.matchWindow`)
    /// — the head-300 of a long note or article rarely contains the fact the
    /// person asked for, which read back as answers that stayed general.
    private func answerSnippet(_ thing: Thing, terms: [String] = []) -> String {
        let rawBody = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare link carries no prose the title doesn't already imply — reach
        // for the fetched article text instead.
        let bodyIsBareURL = rawBody.lowercased().hasPrefix("http") && !rawBody.contains(" ")
        var body = (rawBody.isEmpty || rawBody == thing.title || bodyIsBareURL) ? "" : rawBody
        if body.isEmpty, let extra = thing.enrichedText?.trimmingCharacters(in: .whitespacesAndNewlines) {
            body = extra
        }
        guard !body.isEmpty else { return "" }
        let flat = body.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let squeezed = flat.replacingOccurrences(of: "  ", with: " ")
        guard squeezed.count > 300 else { return squeezed }
        if !terms.isEmpty, let window = Retriever.matchWindow(in: squeezed, terms: terms) {
            return window
        }
        return String(squeezed.prefix(300)) + "…"
    }

    /// Streams the model's grounded synthesis, painting each snapshot through
    /// `onProseDoc`; returns the final prose, or nil when the model is
    /// unavailable, declined, or wrote nothing — the caller then paints its
    /// grounded fallback. One loop for every synthesis path, so a streaming
    /// fix can't miss one.
    ///
    /// `document` is how a caller shapes each snapshot (2026-08-16). It
    /// defaults to `proseDoc`, which is what every caller did inline before —
    /// the synthesis arm overrides it so the streamed snapshots are CAPTIONED
    /// as they arrive rather than at the last frame. Passing the raw snapshot
    /// is what makes that possible at all: the callback used to receive the
    /// finished document, by which point the prose was already sealed inside an
    /// `Insight(…)` argument and could only have been cut back out of the
    /// grammar — the MoneyReceipt refusal, one screen over.
    private func streamSynthesis(_ query: String, over candidates: [OnDeviceModel.Candidate],
                                 document: @escaping (String) -> [String],
                                 onProseDoc: @escaping ([String]) -> Void) async -> String? {
        guard let stream = OnDeviceModel.synthesisStream(query: query, candidates: candidates) else {
            return nil
        }
        var last = ""
        for await snapshot in stream {
            last = snapshot
            onProseDoc(document(snapshot))
        }
        let final = last.trimmingCharacters(in: .whitespacesAndNewlines)
        return final.isEmpty ? nil : final
    }

    /// A synthesis snapshot as a composition — a single growing Insight. The
    /// prose is the answer; the grounded things are what it was written from.
    private func proseDoc(_ text: String) -> [String] {
        ["root = Stack([ins])",
         "ins = Insight(\"\(genSafe(text))\")"]
    }

    /// Tacks computed lines under an answer doc as their own Insights — the
    /// away recap's watchlist and wallet lines ride whatever the answer path
    /// produced (prose, the counted pulse, or the honest empty). nil lines are
    /// skipped; each real one gets its own uniquely-named ref so two can splice
    /// without colliding.
    private func appendingInsight(_ lines: String?..., to doc: [String]) -> [String] {
        let real = lines.compactMap { $0 }
        guard !real.isEmpty,
              let i = doc.firstIndex(where: { $0.hasPrefix("root = Stack([") }),
              doc[i].hasSuffix("])")
        else { return doc }
        var out = doc
        let refs = real.indices.map { "extraIns\($0)" }
        // Splice before the closing "])" — suffix surgery, so a root whose
        // ref list ever nests its own brackets can't be corrupted mid-line.
        out[i] = String(out[i].dropLast(2)) + ", " + refs.joined(separator: ", ") + "])"
        for (j, line) in real.enumerated() {
            out.append("\(refs[j]) = Insight(\"\(genSafe(line))\")")
        }
        return out
    }

    /// The grounding list as doc lines — `res = Widget(title, count, rows)`
    /// plus one Row per real thing. Every answer doc that paints things emits
    /// its rows here, so the Row grammar and its escaping live in one place.
    ///
    /// Each Row now carries its thing's id (arg 4, 2026-07-22) — so a grounding
    /// row OPENS on tap, pushing its thing-view onto the agent's Stack (ruling
    /// 8: tapping content inside an answer drills in, never ejects). Before
    /// this the id was omitted and every "Found"/grounding row was inert; the
    /// id was already the one thing the renderer's tap needed (`GenRow` reads
    /// `el.str(4)`). `widgetRef`/`rowPrefix` let a second grounding list live
    /// in the same doc without colliding with the default `res`/`r0` refs
    /// (used by `appendingGrounding`'s synthesis receipts).
    private func groundingLines(_ things: [Thing], title: String,
                                widgetRef: String = "res", rowPrefix: String = "r") -> [String] {
        let ids = things.indices.map { "\(rowPrefix)\($0)" }
        var lines = ["\(widgetRef) = Widget(\"\(genSafe(title))\", \"\(things.count)\", [\(ids.joined(separator: ", "))])"]
        for (i, t) in things.enumerated() {
            lines.append("\(rowPrefix)\(i) = Row(\"\(genSafe(t.title))\", \"\(t.kind.typeTag)\", \"\(t.source)\", \"\(shortTime(t.capturedAt))\", \"\(t.id.uuidString)\")")
        }
        return lines
    }

    /// Appends a "Drawn from" receipt Widget to a finished answer doc — the
    /// things a SYNTHESIS was written from, shown under the prose so every
    /// model answer is verifiable at a glance and tappable into the Stack
    /// (2026-07-22). Splices a `grd` ref into the root's list by the same
    /// suffix surgery `appendingInsight` uses, and its rows carry a distinct
    /// `g` prefix so they never collide with a doc's own `res`/`r0` rows.
    /// A doc with no root, or no things to show, is returned untouched — the
    /// prose stands alone rather than wearing an empty footer.
    private func appendingGrounding(_ things: [Thing], title: String, to doc: [String]) -> [String] {
        let shown = Array(things.prefix(4))
        guard !shown.isEmpty,
              let i = doc.firstIndex(where: { $0.hasPrefix("root = Stack([") }),
              doc[i].hasSuffix("])")
        else { return doc }
        var out = doc
        out[i] = String(out[i].dropLast(2)) + ", grd])"
        return out + groundingLines(shown, title: title, widgetRef: "grd", rowPrefix: "g")
    }

    /// A synthesis that came back empty — the model refused (a title tripped a
    /// guardrail) or the window's things don't sum into a line. It must NOT
    /// read as a failed lookup: a bare "Found" list under "what's my week"
    /// looks broken (audit 2026-07-11). Instead say so plainly and frame the
    /// grounding things as grounding, not search results. No hits → the honest
    /// nothing-here line the retrieval path already writes.
    private func synthesisEmptyDoc(_ hits: [Thing]) -> [String] {
        let shown = Array(hits.prefix(4))
        guard !shown.isEmpty else { return retrievalDoc(hits) }
        return ["root = Stack([ins, res])",
                "ins = Insight(\"\(genSafe("Couldn't pull these into a summary — here's what's there."))\")"]
            + groundingLines(shown, title: "From your things")
    }

    /// The status answer where the model isn't (or declined): the counted
    /// pulse line, grounded by the things it was counted from — one row per
    /// active source, so "what's going on" reads across the feeds.
    private func pulseDoc(_ pulse: StatusAsk.Pulse) -> [String] {
        var seen = Set<String>()
        let shown = Array(pulse.sample.filter { seen.insert($0.source).inserted }.prefix(4))
        guard !shown.isEmpty else { return proseDoc(StatusAsk.line(pulse)) }
        return ["root = Stack([ins, res])",
                "ins = Insight(\"\(genSafe(StatusAsk.line(pulse)))\")"]
            + groundingLines(shown, title: "From your feeds")
    }

    /// Pronoun-shaped questions lean on what was just answered.
    private func isFollowUp(_ query: String) -> Bool {
        let q = " \(query.lowercased()) "
        return ["them", "those", "these", "ones", "one of", "of that"].contains {
            q.contains(" \($0) ") || q.contains(" \($0)?")
        }
    }

    /// Resolves the corpus to score, then delegates the actual scoring to
    /// `Retriever.rank` (2026-07-20 extraction — that engine is now shared
    /// with a kept-ask "search" composer, so both re-run identically). A
    /// follow-up passes its narrowed `pool` straight through; otherwise this
    /// fetches the newest 2000 things (raised from 500, 2026-07-15: the older
    /// cap made anything past the recent 500 invisible to answers even
    /// though it carried an embedding). Scoring is linear over this set and
    /// runs on the Ask path, so it stays bounded — but 2000 covers a heavy
    /// corpus without a felt cost.
    private func retrieve(_ query: String, in pool: [Thing]? = nil) -> [Thing] {
        let corpus: [Thing]
        if let pool {
            corpus = pool
        } else {
            corpus = scopedCorpus(for: query)
        }
        return Retriever.rank(query, in: corpus, isPoolRefinement: pool != nil)
    }

    /// The things an ask is scored against.
    ///
    /// A query that NAMES a source is fetched scoped to that source instead of
    /// through the global recency window (2026-08-05). The window is the
    /// reason: 2,000 newest things is generous for a corpus that arrives a few
    /// rows at a time, and useless for one that arrives all at once dated
    /// across a decade — an imported X archive of 3,500 posts had well over
    /// half of itself permanently outside any answer, including the answers
    /// that named X explicitly. Scoping by predicate costs the same single
    /// fetch and reaches the whole room.
    ///
    /// FALLS BACK rather than answering empty. A catalog name the person has
    /// nothing from resolves here and fetches nothing, and returning that would
    /// turn a question whose wording happens to contain an app's name into
    /// "nothing matches". An empty scoped read is treated as no scope at all,
    /// and `Retriever.rank` independently declines to honour a filter the
    /// corpus can't confirm.
    private func scopedCorpus(for query: String) -> [Thing] {
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        if let named = Retriever.sourceFilter(in: query) {
            // Bound into a local — a `#Predicate` captures values, not the
            // members of a tuple it was handed.
            let source = named.source
            var scoped = descriptor
            scoped.predicate = #Predicate { $0.source == source }
            // High enough that no real room is truncated, still a ceiling: the
            // scoring pass below is linear over whatever this returns.
            scoped.fetchLimit = 20_000
            let rows = (try? modelContext.fetch(scoped)) ?? []
            if !rows.isEmpty { return rows }
        }
        descriptor.fetchLimit = 2000
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Today's doc, verbatim — the record paints from the top 4 hits. The
    /// universal fallback and the empty state.
    private func retrievalDoc(_ hits: [Thing], tag: String? = nil, in things: [Thing] = []) -> [String] {
        let shown = Array(hits.prefix(4))
        guard !shown.isEmpty else {
            // Say what WOULD work, not just that nothing did (2026-07-10) —
            // and don't suggest asking about things when there are none.
            let total = (try? modelContext.fetchCount(FetchDescriptor<Thing>())) ?? 0
            let line = total == 0
                ? "Nothing here yet — connect an app, or capture something."
                : "Nothing matches that. Try your links, events, or what landed today."
            return ["root = Stack([ins])",
                    "ins = Insight(\"\(genSafe(line))\")"]
        }
        let tile = tagTile(tag, in: things)
        var doc = ["root = Stack([\(tile == nil ? "res" : "tag, res")])"]
        if let tile { doc.append(tile) }
        return doc + groundingLines(shown, title: "Found")
    }

    /// A tappable tile for the tag an answer is about — opens that tag's view.
    /// nil when the query names no known tag. The tile's name arg is what the
    /// tap routes on (GenProjectTile → genProjectTap → HomeRoute.path's
    /// `.project` node, the same screen the feed's treemap opens).
    /// Takes the corpus already fetched by the caller (2026-07-21) — this and
    /// `matchedTag` used to each run their OWN full-corpus fetch on the common
    /// retrieval path, on top of `answerDocument`'s own.
    private func tagTile(_ tag: String?, in things: [Thing]) -> String? {
        guard let tag else { return nil }
        let count = things.filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }.count
        guard count > 0 else { return nil }
        return "tag = ProjectTile(\"2\", \"\(genSafe(tag))\", \"\", \"\(String(localized: "\(count) thing"))\", \"\(count) things\", null)"
    }

    /// The existing tag a query names, if any — a query term (minus stopwords
    /// and kind words) that matches a tag's name exactly, case-insensitively.
    private func matchedTag(_ query: String, in things: [Thing]) -> String? {
        let stops: Set<String> = ["about", "my", "the", "a", "in", "from", "for",
                                  "of", "what", "did", "i", "save", "saved", "show",
                                  "find", "me", "all", "any"]
        let terms = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stops.contains($0) }
        guard !terms.isEmpty else { return nil }
        let tags = Set(things.flatMap(\.tags))
        // Prefer a whole-query match ("book club"), else any single term.
        if let whole = tags.first(where: { $0.caseInsensitiveCompare(terms.joined(separator: " ")) == .orderedSame }) {
            return whole
        }
        return terms.lazy.compactMap { term in
            tags.first { $0.caseInsensitiveCompare(term) == .orderedSame }
        }.first
    }

    /// The model's answer as a composition: its one plain sentence up top, then
    /// the things it picked — painted from the REAL things (the model chose
    /// indices, never content), so every row is honest. No picks = just the
    /// sentence (the model said nothing fits).
    private func modelDoc(insight: String, hits: [Thing], picks: [Int], tag: String? = nil,
                         in things: [Thing] = []) -> [String] {
        let clean = genSafe(insight)
        let picked = picks.compactMap { hits.indices.contains($0) ? hits[$0] : nil }.prefix(6)
        let tile = tagTile(tag, in: things)
        guard !picked.isEmpty else {
            var doc = ["root = Stack([\(tile == nil ? "ins" : "ins, tag")])",
                       "ins = Insight(\"\(clean)\")"]
            if let tile { doc.append(tile) }
            return doc
        }
        let children = tile == nil ? "ins, res" : "ins, tag, res"
        var doc = ["root = Stack([\(children)])",
                   "ins = Insight(\"\(clean)\")"]
        if let tile { doc.append(tile) }
        return doc + groundingLines(Array(picked), title: "Found")
    }

    /// Strips what would break the one-line gen-UI grammar (quotes end a
    /// string; newlines end a line) — model output is untrusted text.
    private func genSafe(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    #if targetEnvironment(macCatalyst)
    /// Mac window chrome for THIS window, applied the moment its scene is
    /// known (2026-08-02).
    ///
    /// SwiftUI's `.frame(minWidth:)` on the WindowGroup's root does NOT
    /// constrain a Catalyst NSWindow — verified live 2026-07-28: the window
    /// drags straight past it, the chip strip overlapping the title bar well
    /// before the intended floor. `UIWindowScene.sizeRestrictions` is the real
    /// Catalyst API (AppKit-native apps use the SwiftUI modifier; a Catalyst
    /// window is still fundamentally a UIWindowScene).
    ///
    /// The floor comes from `PadLayout.macMinWindowSize` now, and that fixed a
    /// live bug: this call read a hardcoded 560 while CasberiApp's frame read
    /// `560 + railWidth`, and since only THIS one binds, the window's real
    /// floor sat 88pt under its stated intent from the day the rail landed —
    /// a 472pt content column, exactly what the frame's own comment believed
    /// it had prevented.
    ///
    /// Driven by `WindowSceneReader` rather than `onAppear`, for two reasons:
    /// the old code asked `UIApplication` for "the first foreground-active
    /// scene", which with two windows open can be the OTHER one (restricting
    /// it twice and this one never); and it fired once with no retry, so a
    /// scene that wasn't foreground-active at that instant was never
    /// restricted at all.
    private func applyMacWindowChrome(to scene: UIWindowScene) {
        scene.sizeRestrictions?.minimumSize = PadLayout.macMinWindowSize
        // **The window is one surface, top to bottom (2026-08-17).** Every
        // other pixel of this app is painted by the design system — the page
        // background, the crown pour, the six bleed hues — and the title bar
        // was the one strip of the window that was not. Hiding the title (and
        // owning no toolbar, which this app deliberately does not — prd §273,
        // the chip rail IS the navigation) collapses that strip and lets the
        // page, and its pour, run to the top edge behind floating window
        // buttons.
        //
        // `windowScene.title` is STILL SET, on every source change, and that
        // is the half worth keeping: the name is what Mission Control, the
        // Window menu and ⌘` cycling read. What goes is the drawn bar, not the
        // window's identity — so nothing that identifies a window is lost, and
        // a person with three windows open can still tell them apart
        // everywhere the system names them.
        scene.titlebar?.titleVisibility = .hidden
        scene.titlebar?.toolbar = nil
        #if DEBUG
        applyMacWindowSizeOverride(to: scene)
        #endif
        updateMacWindowTitle()
    }

    #if DEBUG
    /// `-macWindowSize <W>x<H>` — pin THIS window to a size on launch.
    ///
    /// The Mac's layout branches on measured width (`PadLayout.railWidth`,
    /// `readingMaxWidth`, `minWidthForPane`) and every one of those branches is
    /// invisible from a screenshot of the size the window happens to open at.
    /// Until this existed the only way to see a narrow Mac window was to drag
    /// one by hand, which a headless run cannot do and which produces no record
    /// — so a resize bug could only ever be reported, never measured. Pairs
    /// with `-macSnapshot`: one launch per width gives a real before/after.
    ///
    /// It lowers `minimumSize` first, deliberately. `requestGeometryUpdate`
    /// CLAMPS to the restriction rather than refusing, so asking for a width
    /// below the floor without this returns "success" and silently hands back
    /// the floor — the harness would then measure the wrong window and report
    /// the layout as fine. Going below the shipped floor is the whole point of
    /// a floor test, and this is DEBUG-only, so no shipped window can reach it.
    private func applyMacWindowSizeOverride(to scene: UIWindowScene) {
        guard let spec = UserDefaults.standard.string(forKey: "macWindowSize") else { return }
        let parts = spec.lowercased().split(separator: "x")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]),
              w > 200, h > 200 else {
            NSLog("[Casberi] macWindowSize: unreadable %@ (want WxH, e.g. 620x800)", spec)
            return
        }
        scene.sizeRestrictions?.minimumSize = CGSize(width: min(w, PadLayout.macMinWindowSize.width),
                                                     height: min(h, PadLayout.macMinWindowSize.height))
        let frame = CGRect(x: 40, y: 40, width: w, height: h)
        let ask = { [weak scene] in
            scene?.requestGeometryUpdate(.Mac(systemFrame: frame)) { error in
                NSLog("[Casberi] macWindowSize: REFUSED %.0fx%.0f — %@", w, h, error.localizedDescription)
            }
        }
        ask()
        // …and again after the window has settled. macOS RESTORES a window's
        // last frame, and that restore lands AFTER scene connection: measured
        // 2026-08-12, a launch asking for 1120 logged `padLayout: width=1120`
        // and then `width=780` — the previous run's remembered size — so the
        // snapshot showed a width nobody had asked for while the log said the
        // ask succeeded. The second ask is what makes the requested width the
        // one the harness actually measures.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            ask()
        }
        NSLog("[Casberi] macWindowSize: asked %.0fx%.0f", w, h)
    }
    #endif
    #else
    private func applyMacWindowChrome(to scene: UIWindowScene) {}
    #endif

    #if targetEnvironment(macCatalyst)
    /// `nil` reverts the title bar to the app's own display name (Info.plist
    /// `CFBundleDisplayName`) — the "All" case, so an unscoped feed reads as
    /// plain "Casberi" exactly as it always has.
    private func updateMacWindowTitle() {
        // THIS window's scene (multi-window, 2026-08-02). The old
        // `connectedScenes.first(where: .foregroundActive)` lookup answered
        // "whichever window is frontmost", so with two open, one window
        // changing source retitled the other.
        windowScene?.title = filter.source == "All" ? nil : filter.source
    }
    #endif

    // MARK: - Toast (commit feedback — state lives in ShellChrome.flash)

    /// Transient chrome floating over content — it wears glass.
    ///
    /// The pill and its one action are concentric glass — a tinted prominent
    /// capsule (the drop-capture Undo) riding inside the clear glass pill —
    /// so they live in a `DSGlassContainer`: the container is what lets the
    /// inner button lens against the SAME backdrop sample as the pill instead
    /// of compositing as an unrelated glass layer stacked on top (2026-07-23,
    /// the first real use of the container the design system already shipped).
    private func toastView(_ text: String) -> some View {
        DSGlassContainer(spacing: DS.Space.s2) {
        HStack(spacing: DS.Space.s2) {
            // The first thing ever gets the mark (§8). Once. The first-ever
            // kept ask (composer delight, 2026-07-21) shares the treatment —
            // both are "your first standing X with Casberi" moments.
            if text == "Your first thing" || text.hasPrefix("Your first standing question") {
                CasberiMark(size: 18)
            } else if let mark = chrome.toastMark {
                // A moment's toast wears the brand it's about (prd §384) —
                // whose news this is, said before a word is read.
                BridgeIcon(name: mark, size: DS.Face.badge, circular: true)
            }
            Text(text)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
            if let action = chrome.toastAction {
                // The pane's one action reads as ITS interactive part —
                // a tinted glass capsule riding the glass pill.
                Button(action: action.run) {
                    Text(action.label)
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.s3)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
                .dsGlassProminent(tint: DS.tint, cornerRadius: DS.Radius.pill)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
        .dsGlass(cornerRadius: DS.Radius.pill)
        // It MATERIALIZES (2026-08-06). A toast is the one piece of chrome here
        // that exists ONLY as an arrival — it has no resting state to return to,
        // it appears because something just happened and then it's gone. The
        // move-and-fade below still carries it up from the bottom edge; this is
        // the glass itself forming rather than a finished pane cross-dissolving
        // into place. Applied inside the container so the pill and its Undo
        // capsule form together, as the one substance they already lens as.
        .dsGlassMaterialize()
        }
        .padding(.bottom, 140)
        // A replacing flash swaps identity — crossfade, never a stack (§12).
        // The `.id` rides the container so the whole glass unit swaps as one,
        // preserving the crossfade (a shared `glassEffectID` would morph the
        // shapes instead — deliberately not done, the crossfade ruling stands).
        .id(text)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        // The toast floats ABOVE content in the shell ZStack. A plain outcome
        // pill must let taps fall through to what's under it — only a toast
        // carrying an action (the drop-capture Undo) stays interactive, so its
        // button still works without the pill swallowing taps on content
        // beneath it (perf/hit-test pass 2026-07-13).
        .allowsHitTesting(chrome.toastAction != nil)
    }
}

/// The §1 proxy card: KindGlyph + truncated title, gliding from above the
/// bar to the "All" chip, shrinking and fading. One keyframe pair.
private struct CaptureFlight: View {
    let flight: ShellChrome.Flight
    let target: CGRect
    var onDone: () -> Void
    @State private var flown = false
    /// Reduce Motion skips the flight entirely (2026-08-04, prd §299): the
    /// proxy card exists ONLY to travel, so a still one is a card that appears
    /// over the feed for a third of a second and vanishes. `onDone` still
    /// fires, so the toast and the corpus behave identically.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let start = CGPoint(x: geo.size.width / 2, y: geo.size.height - 160)
            let end = target == .zero
                ? start
                : CGPoint(x: target.midX - geo.frame(in: .global).minX,
                          y: target.midY - geo.frame(in: .global).minY)
            HStack(spacing: DS.Space.s2) {
                KindGlyph(kind: flight.kind, size: 24)
                Text(flight.title)
                    .dsText(.subhead13).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background(DS.surfaceSheet,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .frame(maxWidth: geo.size.width * 0.75)
            .scaleEffect(flown ? 0.3 : 1)
            .opacity(flown ? 0 : 1)
            .position(flown ? end : start)
            .onAppear {
                guard !reduceMotion else { onDone(); return }
                withAnimation(DS.Motion.standard) { flown = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(Int(DS.Motion.duration * 1000) + 50))
                    onDone()
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The safe-area inset the scrolling screens leave for the floating stack.
enum ShellMetrics {
    /// 120 was tuned for iPhone, where the gap is real space taken from a
    /// screen that has none to spare. Mac has no such scarcity, and at a
    /// window near its 480pt minimum height that same 120 read as content
    /// crowding right up against the bar (Mac polish, 2026-07-28) — more
    /// clearance costs Mac nothing, so it gets some. The bar stays floating
    /// glass either way (docs/build-brief.md §8: "the whole point of
    /// dropping the tab bar") — this widens its margin, not its design.
    static var bottomInset: CGFloat {
        ProcessInfo.processInfo.isMacCatalystApp ? 160 : 120
    }
    static let topInset: CGFloat = DS.Space.s2
}

#if DEBUG
/// `askPerf| firstPaint=` — the span a tap actually owns, which until now
/// nothing measured (2026-08-16).
///
/// `scripts/perf.sh` tracks "answer latency" via `-answerProbe`, and that
/// number starts inside the answer path and ends when the document is
/// returned — so BOTH halves of the wait belong to neither end of it: the
/// corpus fetch upstream of the composer, and everything between a document
/// being computed and a pixel of it appearing. That is not a hypothetical
/// gap; it is exactly why the two ask-path regressions found on 2026-08-13
/// (`RootShell.answerDocument` opening every kept branch with an unbounded
/// `fullCorpus()`, and `Composer`'s settle block fetching the whole store
/// again ABOVE the paint line) read clean on every nightly while the chip
/// taps they governed were the slowest thing in the app. **A metric measuring
/// the wrong span reads clean**, and this is the missing span.
///
/// Reports two moments, because they answer different questions: FIRST PAINT
/// is what the person experiences (whichever channel fires first — the brief's
/// early partial, a `lastKnownDoc` interim, or streaming prose), and SETTLED is
/// when the real document lands. A branch with no early channel at all shows
/// `firstPaint=never`, which is itself the finding: it means that ask has
/// nothing to show until it is completely finished.
@MainActor final class AskClock {
    private let t0 = Date.now
    private let query: String
    private var paintedMs: Double?
    init(_ query: String) { self.query = query }

    /// First writer wins — later paints are the document being refined, not the
    /// wait ending.
    func paint(_ channel: String) {
        guard paintedMs == nil else { return }
        let ms = Date.now.timeIntervalSince(t0) * 1000
        paintedMs = ms
        NSLog("[Casberi] askPerf| firstPaint=%dms via=%@ q=\"%@\"", Int(ms), channel, query)
    }

    func settled() {
        NSLog("[Casberi] askPerf| settled=%dms firstPaint=%@ q=\"%@\"",
              Int(Date.now.timeIntervalSince(t0) * 1000),
              paintedMs.map { "\(Int($0))ms" } ?? "never", query)
    }
}
#endif
