import SwiftUI
import SwiftData
import CoreSpotlight
import WidgetKit

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
    @State private var draft = ""
    @State private var composerOpen = false
    /// The Actions sheet's height — the composer reports its content height so
    /// the sheet hugs it (grows on its own when an answer streams in).
    @State private var actionsHeight: CGFloat = 360
    @State private var deepLinkThing: Thing?
    @AppStorage("onboarded") private var onboarded = false
    /// After onboarding completes, the "How it works" greeting shows a new
    /// person once (2026-07-11) — swapped in as a SECOND STEP inside the same
    /// full-screen cover (not a sheet presented after the cover dismisses),
    /// so the feed never flashes underneath between the two (2026-07-13 fix:
    /// the old onDismiss handoff had a visible gap where the cover had
    /// already revealed the feed before the sheet slid up).
    @State private var onboardingHowItWorks = false
    @AppStorage("privacy.hidePreviews") private var hidePreviews = true
    @AppStorage("firstThingSaved") private var firstThingSaved = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasBeenActive = false
    /// The last answer's grounding — a follow-up ("which ones were from
    /// Sam?") searches inside it instead of the whole corpus (2026-07-10).
    @State private var lastAnswerHits: [Thing] = []
    @State private var redactNow = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // The themed page — the same field each screen paints for itself
            // (NavigationStack's backing is opaque, so photo rendering lives
            // inside the screens via dsPageBackground; this is the base coat).
            DSPageBackground()

            // Content — records paint, generated surfaces stream (brief §5).
            // Anything dropped on the shell lands as a thing (capture: drop).
            MainSurface()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    saveDropped(url.absoluteString)
                    return true
                }
                .dropDestination(for: String.self) { strings, _ in
                    guard let text = strings.first else { return false }
                    saveDropped(text)
                    return true
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

        }
        // The FAB moved onto MainSurface's root content (2026-07-13 polish):
        // it belongs to Home/Feed, so pushed rooms (Apps, Settings, a setup
        // form) slide over it instead of wearing a compose button that isn't
        // theirs. The sheet stays here.
        .onChange(of: chrome.composerRequest) { _, _ in
            composerOpen = true
        }
        // Privacy as the default (goal 6): leaving the app redacts the
        // corpus — the app-switcher snapshot shows choreography, not content.
        // The person can turn it off in Privacy (Hide previews). Never before
        // first activation: apps LAUNCH inactive, and the nav bar caches a
        // title configured under redaction.
        .redacted(reason: redactNow ? .placeholder : [])
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                hasBeenActive = true
                // Freeze the away window (librarian, prd §67 ⑥) — "while you
                // were away" grounds on it; things landing from here on are
                // arriving while you're present.
                AppVisit.markOpened()
                // Returning crossfades from placeholder to content (§14);
                // leaving redacts instantly — the snapshot must already hide.
                withAnimation(.easeOut(duration: 0.2)) { redactNow = false }
                // Warm the model on foreground so the first Ask is fast; the
                // call is idempotent and returns immediately.
                if !skipPrewarm { OnDeviceModel.prewarm() }
                // Connected bridges are cheap to poll — every foreground
                // refreshes them all (one place, reusable from screens).
                BridgeRefresh.refreshAllConnected(context: modelContext, store: bridges)
                // Build the on-device semantic index for anything new or not
                // yet embedded — a bounded background sweep, so Ask can retrieve
                // by meaning, not just shared words.
                EmbeddingIndex.backfill(context: modelContext)
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
                // A share-extension capture landed while we were away. Its
                // write IS in the store file, but @Query never hears a
                // foreign process's save (SwiftData; Apple's pattern is a
                // foreground reconcile — forums thread 764290), so shared
                // things stayed invisible until relaunch (2026-07-11).
                if group?.bool(forKey: "capture.landed") == true {
                    group?.removeObject(forKey: "capture.landed")
                    nudgeAfterExternalCapture()
                }
            } else {
                if hasBeenActive && hidePreviews { redactNow = true }
                if phase == .background {
                    // The away clock starts — the next foreground reads it.
                    AppVisit.markClosed()
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
        }
        // The composer is a sheet the FAB opens — no tab to remember and
        // return to now; dismissing just closes it over whatever's on screen.
        .sheet(isPresented: $composerOpen) {
            actionsSheet
        }
        // A surface requested an ask (the weekend cover) — open the composer;
        // it consumes the query once it mounts (prd 54).
        .onChange(of: chrome.askRequest) { _, request in
            guard request != nil else { return }
            composerOpen = true
        }
        .dsSensoryFeedback()
        .environment(bridges)
        .environment(chrome)
        // The app-language override, applied to the whole tree: reading the
        // observable store here means picking a language repaints every `Text`
        // from its `.lproj` live, no relaunch (LanguageStore).
        .environment(\.locale, LanguageStore.shared.locale)
        // Mode is the person's; a chosen photo implies the dark treatment.
        .preferredColorScheme(
            ThemeStore.shared.isLight && ThemeStore.shared.backgroundPhoto == nil ? .light : .dark
        )
        // casberi:// deep links — widgets and App Intents route through these.
        // casberi://home|feed|account switch tabs; casberi://thing/latest opens
        // the newest thing's sheet (the widget-tap route).
        .onOpenURL { route($0) }
        .onAppear {
            // Landing (2026-07-13): a curator who's pinned something lands on
            // their board — they know what they want. Someone with nothing
            // pinned yet (new, or never curated) lands on the whole record
            // instead of an empty board. Deep links and debug hooks below can
            // still override this within the same launch.
            let hasPins = !HomePinnedSources.shared.sources.isEmpty
                || WalletStore.shared.addresses.contains(where: \.pinnedToHome)
            FeedFilter.shared.source = hasPins ? "Pinned" : "All"
            #if DEBUG
            // Perf pass: log init→ready (first content appearance) once per
            // process. `ready` = this onAppear, i.e. the first frame's view tree
            // is assembled — read by scripts/perf.sh, not an in-app surface.
            if !LaunchClock.didLog {
                LaunchClock.didLog = true
                let ms = Int(Date().timeIntervalSince(LaunchClock.start) * 1000)
                NSLog("[Casberi] launchTimer init→ready %dms", ms)
            }
            #endif
            // Spotlight mirrors the store; launch reconciles (covers things
            // the share extension made while the app was closed). The fetch
            // reads the main-actor store, so it stays on the main actor — a
            // detached background task sharing this ModelContext races the
            // screens' own reads and crashes SwiftData. The CoreSpotlight
            // calls it makes are non-blocking, so this is cheap on main.
            Task { @MainActor in
                // Every launch: Spotlight reconciles and CloudKit-merge
                // duplicates collapse (covers extension writes + sync merges).
                SpotlightIndex.reindexAll(context: modelContext)
                SyncReconcile.dedupeBySourceRef(context: modelContext)

                // One-time migrations run once per install (bump the version
                // when adding one) — steady-state launches skip the scans.
                let migrationsKey = "migrations.version"
                let migrationsCurrent = 3
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
                        // the feed still headed them "Dexscreener". Rewrite both, and
                        // carry the rename across any Home pin.
                        let staleTokens = (try? modelContext.fetch(FetchDescriptor<Thing>(
                            predicate: #Predicate { $0.source == "Dexscreener" }
                        ))) ?? []
                        for thing in staleTokens {
                            thing.source = "Tokens"
                            if let ref = thing.sourceRef, ref.hasPrefix("dexscreener:") {
                                thing.sourceRef = "tokens:" + String(ref.dropFirst("dexscreener:".count))
                            }
                        }
                        HomePinnedSources.shared.rename("Dexscreener", to: "Tokens")
                    }
                    try? modelContext.save()
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
            // Debug hook: `simctl launch ... -deeplink casberi://feed` lands in
            // UserDefaults; routes without the system open-in dialog.
            #if DEBUG
            NSLog("[Casberi] On-device model: %@", OnDeviceModel.availabilityLine)
            if let raw = UserDefaults.standard.string(forKey: "deeplink"),
               let url = URL(string: raw) {
                UserDefaults.standard.removeObject(forKey: "deeplink")
                route(url)
            }
            // `-openSettings YES` pushes Settings. Lives HERE (not
            // HomeScreen's onAppear, where it was born): since the
            // one-surface shell, HomeScreen only mounts when the landing
            // chip is "Pinned", so on an unpinned install the hook never
            // fired and the launch landed on Home (audit 2026-07-13). This
            // onAppear runs after the whole tree mounts — same proven
            // timing as the `-deeplink` hook above.
            if UserDefaults.standard.bool(forKey: "openSettings") {
                HomeRoute.shared.push = .settings
            }
            // `-openAppsDelay <s>` pushes the store after a delay — records
            // "tapping the grid door" (the zoom plays on the real push path).
            let appsDelay = UserDefaults.standard.double(forKey: "openAppsDelay")
            if appsDelay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(appsDelay))
                    withAnimation(DS.Motion.standard) { HomeRoute.shared.push = .apps }
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
            if let q = UserDefaults.standard.string(forKey: "byokProbe") {
                Task {
                    await EmbeddingIndex.indexPending(context: modelContext)
                    let start = Date()
                    let doc = await keyedAnswerDocument(q)
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    NSLog("[Casberi] byokProbe(\"%@\") %dms →\n%@", q, ms,
                          doc?.joined(separator: "\n") ?? "nil (key/network failed — composer words it)")
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
            // `-openComposerDelay <s>` opens the composer after a delay.
            let composerDelay = UserDefaults.standard.double(forKey: "openComposerDelay")
            if composerDelay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(composerDelay))
                    composerOpen = true
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
                HomeRoute.shared.push = nil   // land on the record, not a stale store push
                FeedFilter.shared.source = "All"
                deepLinkThing = thing
            }
        }
        .sheet(item: $deepLinkThing) { thing in
            ThingSheetView(thing: thing)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboarded }, set: { if !$0 { onboarded = true; onboardingHowItWorks = false } }
        )) {
            // Onboarding (option 4, 2026-07-07): the mini store connects the
            // three real bridges for REAL, and that's the whole tour — no
            // demo mode, no sample things. The dream lives on the store
            // pages as engine-rendered previews. Landing is the record ("All"
            // chip): the connects just filled it, and a brand-new person has
            // nothing pinned yet. The "How it works" greeting is a second
            // step of this SAME cover (below), not a separate presentation —
            // it swaps in in place, so the feed is never revealed until the
            // person taps Done on the greeting.
            Group {
                if onboardingHowItWorks {
                    // Its own Done button calls the environment's dismiss(),
                    // which resolves to this cover's binding and exits both
                    // steps at once.
                    HowItWorksSheet()
                } else {
                    OnboardingView(store: bridges) { _ in
                        FeedFilter.shared.source = "All"
                        onboardingHowItWorks = true
                    }
                }
            }
            // fullScreenCover hosts its content in a separate presentation
            // that doesn't reliably inherit `\.locale` from the presenter
            // (unlike `.sheet`) — reapply so first-run copy honors the
            // language override too.
            .environment(\.locale, LanguageStore.shared.locale)
        }
    }

    /// casberi:// routing — one place, used by onOpenURL and the debug hook.
    private func route(_ url: URL) {
        // A deep link lands you AT a destination, not back in a store the route
        // singleton still holds from an earlier visit. apps/settings re-set it
        // below.
        HomeRoute.shared.push = nil
        switch url.host() {
        // casberi://home is back-compat (the app was a Home tab once) — it
        // now lands on the board.
        case "home":    FeedFilter.shared.source = "Pinned"; FeedFilter.shared.tag = "All"
        case "feed":
            FeedFilter.shared.source = "All"
            FeedFilter.shared.tag = "All"
            // casberi://feed/type/Link — Home's kind bar lands here filtered.
            // casberi://feed/source/Zerion — lands in that source's shape.
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count == 2, parts[0] == "type" {
                FeedFilter.shared.tag = parts[1]
            } else if parts.count == 2, parts[0] == "source" {
                FeedFilter.shared.source = parts[1]
            }
        // Apps is reached through the shared doors now — push it directly,
        // wherever the chip header currently sits (back-compat for
        // casberi://apps and //account).
        case "account", "apps":
            HomeRoute.shared.push = .apps
        case "settings":
            HomeRoute.shared.push = .settings
        case "thing":
            FeedFilter.shared.source = "All"
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

    /// The Actions sheet: the composer, always open — ask a question or say what
    /// to do — with its tools. Presented at 1/2, expandable to 3/4. Same wiring
    /// the floating composer used.
    private var actionsSheet: some View {
        Composer(isOpen: .constant(true), draft: $draft, embedded: true,
                 onHeight: { actionsHeight = min(max($0, 220), 720) },
                 onCommit: saveDraft, onCommitVoice: saveVoice,
                 answer: answerDocument,
                 answerWithKey: keyedAnswerDocument,
                 tagCandidates: projectTags,
                 knownSources: { bridges.bridges.map(\.name) },
                 contextSource: { nil },
                 onNavigate: navigate,
                 onKeepAnswer: keepAnswer,
                 glassNamespace: nil)
            .environment(\.genProjectTap) { name in
                HomeRoute.shared.push = nil
                composerOpen = false
                FeedFilter.shared.source = "Pinned"
                HomeRoute.shared.openTag = name
            }
            // Hug the content — the sheet grows/shrinks with what's inside, so
            // there's no stranded empty space. Drag up to full for a long answer.
            .presentationDetents([.height(actionsHeight), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(DS.Radius.sheet)
            .presentationBackground(DS.surfaceSheet)
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
        HomeRoute.shared.push = nil
        composerOpen = false
        switch intent {
        case .tag(let name):
            FeedFilter.shared.source = "Pinned"
            HomeRoute.shared.openTag = name
        case .source(let source):
            FeedFilter.shared.source = source
            FeedFilter.shared.tag = "All"
        case .kind(let kind):
            FeedFilter.shared.source = "All"
            FeedFilter.shared.tag = kind.typeTag
        }
    }

    private func saveDraft(tags: [String]) {
        guard let thing = Capture.thing(from: draft) else { return }
        thing.tags.append(contentsOf: tags)   // parse-card candidates ride in
        modelContext.insert(thing)
        try? modelContext.save()
        SpotlightIndex.index([thing])
        DSHaptic.success()
        land(thing)
        // A pasted URL saves instantly with its address as its face; the real
        // page title arrives a beat later (best-effort, never blocks the save).
        Task { @MainActor in await LinkTitle.enrich(thing, context: modelContext) }
    }

    /// Dropped text or a link — same path as the composer, same proof. The
    /// composer's parse card was consent; a drop had none, so its toast
    /// carries Undo (§12).
    private func saveDropped(_ text: String) {
        guard let thing = Capture.thing(from: text) else { return }
        modelContext.insert(thing)
        try? modelContext.save()
        SpotlightIndex.index([thing])
        DSHaptic.success()
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
        try? modelContext.save()
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
        try? modelContext.save()
        SpotlightIndex.index([thing])
        DSHaptic.success()
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
        try? modelContext.save()
        SpotlightIndex.index([thing])
        DSHaptic.success()
        chrome.flash("Kept — it's in your things")
    }

    /// Every save ends here (§1): toast, and — unless the person is already
    /// watching the record (any feed shape), where the new row IS the
    /// arrival — the proxy-card flight to the "All" chip. The very first
    /// thing ever gets its own toast and always flies (§8). Haptic stays at
    /// commit, in the callers.
    private func land(_ thing: Thing, undoable: Bool = false) {
        let first = !firstThingSaved
        if first { firstThingSaved = true }

        if undoable && !first {
            let id = thing.id
            chrome.flash("Saved", action: .init(label: "Undo") {
                undoCapture(id: id)
            }, seconds: 4)
        } else {
            chrome.flash(first ? "Your first thing" : "Saved")
        }

        if FeedFilter.shared.source == "Pinned" || first {
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
        try? modelContext.save()
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

    /// Project tags for the parse card's candidate row.
    private func projectTags() -> [String] {
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        return Array(Set(all.flatMap(\.tags)).subtracting(typeTags)).sorted()
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
            let line = "You haven't made any tags yet. Tag things from a thing's sheet, or type 'tag <app> as <name>' here."
            return ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"]
        }
        switch ask {
        case .count:
            let line = "You have \(counts.count) tag\(counts.count == 1 ? "" : "s")."
            return ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"]
        case .list:
            let n = counts.count
            let line = n > 6
                ? "You have \(n) tags. Your biggest are here — tap one to open it."
                : "You have \(n) tag\(n == 1 ? "" : "s") — tap one to open it."
            // TagMap caps at 6 cells; hand it the biggest, "Label Count" each.
            let cells = counts.prefix(6).map { "\(tagMapLabel($0.tag)) \($0.count)" }
            return ["root = Stack([ins, map])",
                    "ins = Insight(\"\(genSafe(line))\")",
                    "map = TagMap(\"\(genSafe(String(localized: "Your tags")))\", null, [\(cells.joined(separator: ", "))])"]
        }
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

    private func answerMode(_ query: String) -> AnswerMode {
        // Smart punctuation types U+2019 — "what's my week" must match the
        // "what's my" cue whichever apostrophe the keyboard chose.
        let q = query.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        // A retrieval verb is a strong lookup signal — it wins outright, even
        // over a temporal cue ("what did I save this week" is still a lookup).
        let lookupVerbs = ["find", "search", "show", "save", "saved",
                           "where", "which", "list", "look up"]
        if lookupVerbs.contains(where: q.contains) { return .lookup }
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

    /// The answer path. The scoring engine always runs first and grounds the
    /// answer (RAG retriever + universal fallback). On Apple-Intelligence
    /// devices the free on-device model answers over the SAME retrieved things,
    /// two ways by intent: a lookup composes a Widget of the real things it
    /// picked (never invents one); a synthesis streams a short plain summary,
    /// growing through `onProseDoc`, grounded on those same things. Everywhere
    /// else — or if the model declines — the scoring doc paints unchanged (zero
    /// regression). `onProseDoc` fires only while prose streams; lookups and the
    /// fallback never call it and return one doc to reveal at once.
    private func answerDocument(_ query: String,
                                onProseDoc: @escaping ([String]) -> Void) async -> [String] {
        // A count/superlative ask is ARITHMETIC, not retrieval — computed
        // over the corpus directly, no model, always correct (2026-07-10).
        let allThings = (try? modelContext.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        ))) ?? []
        let knownSources = Array(Set(allThings.map(\.source)))
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
            return tagsDoc(tagsAsk, in: allThings)
        }
        if let agg = AggregateAsk.parse(query, sources: knownSources) {
            lastAnswerHits = []
            let line = AggregateAsk.answer(agg, things: allThings)
            return ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"]
        }
        // A status ask ("tell me what's going on") names no content to score,
        // so it grounds on recency itself: the newest things from every source
        // in a recent window — the feeds' pulse. The model synthesizes over
        // that sample; everywhere else the counted pulse line answers
        // (2026-07-11).
        if let pulse = StatusAsk.pulse(query, things: allThings) {
            lastAnswerHits = pulse.sample
            guard !pulse.pool.isEmpty else { return proseDoc(StatusAsk.line(pulse)) }
            if let prose = await streamSynthesis(query, over: candidates(pulse.sample),
                                                 onProseDoc: onProseDoc) {
                return proseDoc(prose)
            }
            return pulseDoc(pulse)
        }
        // A follow-up ("which ones were from sam") searches the LAST
        // answer's grounding, not the whole corpus (2026-07-10).
        let pool = isFollowUp(query) && !lastAnswerHits.isEmpty ? lastAnswerHits : nil
        let hits = retrieve(query, in: pool)
        lastAnswerHits = hits
        // If the query names a tag ("about work"), the answer opens with that
        // tag's tile — tap it to open the tag's view, the same push the Home
        // treemap makes (PRD §17: a topic opens its view, not a Feed filter).
        let tag = matchedTag(query)
        guard OnDeviceModel.isAvailable, !hits.isEmpty else {
            return retrievalDoc(hits, tag: tag)
        }
        switch answerMode(query) {
        case .lookup:
            guard let answer = await OnDeviceModel.compose(query: query, candidates: candidates(hits)) else {
                return retrievalDoc(hits, tag: tag)   // model declined or errored — fall back
            }
            return modelDoc(insight: answer.insight, hits: hits, picks: answer.picks, tag: tag)
        case .synthesis:
            guard let prose = await streamSynthesis(query, over: candidates(hits),
                                                    onProseDoc: onProseDoc) else {
                return synthesisEmptyDoc(hits)
            }
            return proseDoc(prose)
        }
    }

    /// The BYO-key retry (prd §67) — the same question over the SAME evidence
    /// the on-device answer saw (`lastAnswerHits`), synthesized by the person's
    /// own agent key (Claude, ChatGPT, Gemini, or Venice), device→API direct.
    /// nil means the key or the network failed and the composer words that; an
    /// empty grounding gets an honest line instead, because a stronger model
    /// can't change what's here.
    private func keyedAnswerDocument(_ query: String) async -> [String]? {
        let hits = lastAnswerHits.isEmpty ? retrieve(query) : lastAnswerHits
        guard !hits.isEmpty else {
            return proseDoc("Nothing in your things matches that — a bigger model can't change what's here.")
        }
        guard let prose = await AgentAnswer.synthesize(query: query,
                                                       candidates: candidates(hits)) else {
            return nil
        }
        return proseDoc(prose)
    }

    /// Retrieved things flattened for the model — the one place the mapping
    /// lives, so every answer path hands the model the same shape.
    private func candidates(_ things: [Thing]) -> [OnDeviceModel.Candidate] {
        things.map {
            OnDeviceModel.Candidate(title: $0.title, kind: $0.kind.typeTag,
                                    source: $0.source, when: shortTime($0.capturedAt),
                                    note: answerSnippet($0))
        }
    }

    /// A short, single-line excerpt of a thing's body for the model — the
    /// substance the title alone can't carry (a note's text, a chat's gist).
    /// Empty when the body adds nothing over the title: missing, a duplicate
    /// of the title, or a bare URL (source + title already stand for a link).
    /// Capped so 16 candidates still fit the on-device context window.
    private func answerSnippet(_ thing: Thing) -> String {
        let body = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body != thing.title else { return "" }
        // A bare link carries no prose the title doesn't already imply.
        if body.lowercased().hasPrefix("http"), !body.contains(" ") { return "" }
        let flat = body.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let squeezed = flat.replacingOccurrences(of: "  ", with: " ")
        return squeezed.count > 180 ? String(squeezed.prefix(180)) + "…" : squeezed
    }

    /// Streams the model's grounded synthesis, painting each snapshot through
    /// `onProseDoc`; returns the final prose, or nil when the model is
    /// unavailable, declined, or wrote nothing — the caller then paints its
    /// grounded fallback. One loop for every synthesis path, so a streaming
    /// fix can't miss one.
    private func streamSynthesis(_ query: String, over candidates: [OnDeviceModel.Candidate],
                                 onProseDoc: @escaping ([String]) -> Void) async -> String? {
        guard let stream = OnDeviceModel.synthesisStream(query: query, candidates: candidates) else {
            return nil
        }
        var last = ""
        for await snapshot in stream {
            last = snapshot
            onProseDoc(proseDoc(snapshot))
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

    /// The grounding list as doc lines — `res = Widget(title, count, rows)`
    /// plus one Row per real thing. Every answer doc that paints things emits
    /// its rows here, so the Row grammar and its escaping live in one place.
    private func groundingLines(_ things: [Thing], title: String) -> [String] {
        let ids = things.indices.map { "r\($0)" }
        var lines = ["res = Widget(\"\(title)\", \"\(things.count)\", [\(ids.joined(separator: ", "))])"]
        for (i, t) in things.enumerated() {
            lines.append("r\(i) = Row(\"\(genSafe(t.title))\", \"\(t.kind.typeTag)\", \"\(t.source)\", \"\(shortTime(t.capturedAt))\")")
        }
        return lines
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

    /// The scoring engine — retrieval only. Matches are scored, not just found:
    /// title hits outweigh tag hits outweigh content hits, fresh things float,
    /// and kind words in the person's own words filter ("screenshots about
    /// work" searches screenshots for work). Returns the ranked grounding set
    /// (top 10 — a wider net for the model than the 4 the fallback paints).
    /// Pronoun-shaped questions lean on what was just answered.
    private func isFollowUp(_ query: String) -> Bool {
        let q = " \(query.lowercased()) "
        return ["them", "those", "these", "ones", "one of", "of that"].contains {
            q.contains(" \($0) ") || q.contains(" \($0)?")
        }
    }

    private func retrieve(_ query: String, in pool: [Thing]? = nil) -> [Thing] {
        var terms = query.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "? "))
            .split(separator: " ").map(String.init)

        // A kind word is a filter, not a search term.
        var kindFilter: ThingKind?
        terms.removeAll { term in
            if let kind = ThingKind.allCases.first(where: {
                $0.typeTag.lowercased() == term || $0.typeTagPlural.lowercased() == term
            }) {
                kindFilter = kind
                return true
            }
            return false
        }
        let stops: Set<String> = ["about", "my", "the", "a", "in", "from", "for", "of",
                                  "what", "whats", "what's", "landed", "on", "happened",
                                  "is", "are", "was", "were", "do", "does", "did", "i",
                                  "me", "you", "your", "who", "how", "when", "where",
                                  "why", "which", "it", "and", "or", "to", "with"]
        terms.removeAll { stops.contains($0) }

        // A date phrase ("today", "last week", "thursday") is a WHEN filter,
        // not a text term — things outside the range drop out entirely.
        let dateMatch = DateQuery.match(in: query)
        if let dateMatch { terms.removeAll { dateMatch.words.contains($0) } }

        let usingPool = pool != nil
        let all: [Thing]
        if let pool {
            all = pool
        } else {
            var descriptor = FetchDescriptor<Thing>(
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 500
            all = (try? modelContext.fetch(descriptor)) ?? []
        }
        // Semantic widening: near-synonyms of the query's words, scored
        // BELOW exact matches — "car stuff" reaches "vehicle" titles.
        let expanded = SemanticExpand.expand(terms)

        // Sentence-level semantic match (2026-07-12): embed the natural-language
        // ask and score each thing by cosine to its stored vector — so a query
        // can reach a thing that shares NO words with it. The whole ASK is
        // embedded (a sentence embedding wants a sentence — the stripped keyword
        // fragments below would degrade it), only its trailing "?" trimmed.
        // Skipped for follow-up pool refinements and bare kind/date lists (no
        // words to carry meaning), and a no-op when the on-device embedding
        // model is unavailable — the keyword engine then stands alone (zero
        // regression). The query norm is computed once, not per thing.
        let ask = query.trimmingCharacters(in: CharacterSet(charactersIn: "? ").union(.whitespaces))
        let queryVec: [Float]? = (!usingPool && !terms.isEmpty)
            ? EmbeddingIndex.vector(for: ask) : nil
        let queryNorm = queryVec.map(EmbeddingIndex.norm) ?? 0
        // Similarity above the boost floor refines ranking; but a thing with NO
        // keyword score must clear the higher QUALIFY floor to answer at all —
        // so a loosely-related recent thing can't ride the freshness bonus into
        // a false answer, and the honest "nothing matches" path survives. The
        // lift is normalized 0…1 above the boost floor and weighted so a strong
        // meaning-match rivals a title hit (+3).
        let semanticBoostFloor = 0.55
        let semanticQualifyFloor = 0.62
        let semanticWeight = 3.0

        // Whole words, not substrings (2026-07-10): "what is my name" used
        // to match the "is" inside "Lisbon" and answer with nonsense — a
        // term now has to BE a word somewhere in the thing.
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty })
        }
        return all.compactMap { thing -> (Thing, Double)? in
            if let kindFilter, thing.kind != kindFilter { return nil }
            if let dateMatch, !dateMatch.range.contains(thing.capturedAt) { return nil }
            let title = words(thing.title)
            let tags = words(thing.tags.joined(separator: " "))
            let content = words(thing.content)
            var score = 0.0
            for term in terms {
                if title.contains(term) { score += 3 }
                if tags.contains(term) { score += 2 }
                if content.contains(term) { score += 1 }
            }
            for term in expanded {
                if title.contains(term) { score += 1.5 }
                if tags.contains(term) { score += 1 }
                if content.contains(term) { score += 0.5 }
            }
            // Semantic lift: meaning-match adds to the score and can qualify a
            // thing that shares no words at all — but only a STRONG match
            // (>= qualify floor) may answer without a keyword hit.
            if let queryVec, let data = thing.embedding, !data.isEmpty {
                let sim = EmbeddingIndex.similarity(query: queryVec, queryNorm: queryNorm, packed: data)
                if sim >= semanticBoostFloor, score > 0 || sim >= semanticQualifyFloor {
                    score += semanticWeight * (sim - semanticBoostFloor) / (1 - semanticBoostFloor)
                }
            }
            // A bare kind query ("screenshots?") lists that kind; a bare date
            // query ("what landed today?") lists the day.
            if terms.isEmpty && (kindFilter != nil || dateMatch != nil) { score = 1 }
            guard score > 0 else { return nil }
            let age = Date.now.timeIntervalSince(thing.capturedAt)
            score += max(0, 1 - age / (7 * 86_400))   // fresh floats, capped +1
            return (thing, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(10)
        .map(\.0)
    }

    /// Today's doc, verbatim — the record paints from the top 4 hits. The
    /// universal fallback and the empty state.
    private func retrievalDoc(_ hits: [Thing], tag: String? = nil) -> [String] {
        let shown = Array(hits.prefix(4))
        guard !shown.isEmpty else {
            // Say what WOULD work, not just that nothing did (2026-07-10) —
            // and don't suggest asking about things when there are none.
            let total = (try? modelContext.fetchCount(FetchDescriptor<Thing>())) ?? 0
            let line = total == 0
                ? "Nothing here yet — connect an app or capture one thing, then ask about it."
                : "Nothing in your things matches that. Casberi answers from what you've captured — try your links, events, or screenshots, or ask what landed today."
            return ["root = Stack([ins])",
                    "ins = Insight(\"\(genSafe(line))\")"]
        }
        let tile = tagTile(tag)
        var doc = ["root = Stack([\(tile == nil ? "res" : "tag, res")])"]
        if let tile { doc.append(tile) }
        return doc + groundingLines(shown, title: "Found")
    }

    /// A tappable tile for the tag an answer is about — opens that tag's view.
    /// nil when the query names no known tag. The tile's name arg is what the
    /// tap routes on (GenProjectTile → genProjectTap → HomeRoute.openTag).
    private func tagTile(_ tag: String?) -> String? {
        guard let tag else { return nil }
        let count = (try? modelContext.fetch(FetchDescriptor<Thing>()))?
            .filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
            .count ?? 0
        guard count > 0 else { return nil }
        return "tag = ProjectTile(\"2\", \"\(genSafe(tag))\", \"\", \"\(count) thing\(count == 1 ? "" : "s")\", \"\(count) things\", null)"
    }

    /// The existing tag a query names, if any — a query term (minus stopwords
    /// and kind words) that matches a tag's name exactly, case-insensitively.
    private func matchedTag(_ query: String) -> String? {
        let stops: Set<String> = ["about", "my", "the", "a", "in", "from", "for",
                                  "of", "what", "did", "i", "save", "saved", "show",
                                  "find", "me", "all", "any"]
        let terms = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stops.contains($0) }
        guard !terms.isEmpty else { return nil }
        let tags = Set((try? modelContext.fetch(FetchDescriptor<Thing>()))?.flatMap(\.tags) ?? [])
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
    private func modelDoc(insight: String, hits: [Thing], picks: [Int], tag: String? = nil) -> [String] {
        let clean = genSafe(insight)
        let picked = picks.compactMap { hits.indices.contains($0) ? hits[$0] : nil }.prefix(6)
        let tile = tagTile(tag)
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

    // MARK: - Toast (commit feedback — state lives in ShellChrome.flash)

    /// Transient chrome floating over content — it wears glass.
    private func toastView(_ text: String) -> some View {
        HStack(spacing: DS.Space.s2) {
            // The first thing ever gets the mark (§8). Once.
            if text == "Your first thing" { CasberiMark(size: 18) }
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
        .padding(.bottom, 140)
        // A replacing flash swaps identity — crossfade, never a stack (§12).
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
    static let bottomInset: CGFloat = 120
    static let topInset: CGFloat = DS.Space.s2
}
