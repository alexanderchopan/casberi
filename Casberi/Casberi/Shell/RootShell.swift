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
    /// Set by the onboarding CTA, consumed by the cover's onDismiss: the
    /// catalog push must wait until the cover is fully DOWN. Pushing while
    /// the cover still stood raced its dismissal, and SwiftUI intermittently
    /// drops a navigationDestination push made under a presented cover — the
    /// same drop class as `-openSettings` at launch (audit 2026-07-13); the
    /// user saw it as "Browse the catalog sometimes doesn't work" (2026-07-17).
    @State private var landInCatalog = false
    @AppStorage("privacy.hidePreviews") private var hidePreviews = true
    @AppStorage("firstThingSaved") private var firstThingSaved = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasBeenActive = false
    /// The last answer's grounding — a follow-up ("which ones were from
    /// Sam?") searches inside it instead of the whole corpus (2026-07-10).
    @State private var lastAnswerHits: [Thing] = []
    /// A keyed conversation's prior turns (2026-07-21) — threaded into the
    /// next "Try with your key" so a keyed follow-up is understood in
    /// context, the same way the on-device model's own session is. Clears
    /// when the agent lowers (`onLowerAgent`), same lifecycle as every other
    /// per-conversation composer state.
    @State private var keyedHistory: [AgentTurn] = []
    @State private var redactNow = false
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
        guard force || UserDefaults.standard.string(forKey: dayKey) != today
        else { return }
        guard let composed = DayBrief.whisper(things: things) else {
            #if DEBUG
            if force { NSLog("[Casberi] whisper: (nothing to say)") }
            #endif
            return
        }
        UserDefaults.standard.set(today, forKey: dayKey)
        withAnimation(DS.Motion.standard) { whisper = composed }
        #if DEBUG
        NSLog("[Casberi] whisper: %@ | %@", composed.title, composed.detail)
        #endif
    }

    private var shell: some View {
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
            if !composerOpen {
                VStack(spacing: DS.Space.s2) {
                    // The whisper rides ABOVE the bar (prd §165) — the day
                    // brief's headline, first open of the day only. Tap
                    // raises the agent, same move as the bar's own.
                    if let whisper {
                        WhisperCapsule(title: whisper.title, lead: whisper.lead,
                                       walletPct: whisper.walletPct,
                                       morphNS: agentMorph) {
                            DSHaptic.tap()
                            // The capsule's promise kept (prd §166): the tap
                            // lands on the Today brief itself, not the rest
                            // state — the headline it teased, opened. Routed
                            // through `chrome.askRequest` (the same door the
                            // weekend cover already uses), so the whisper, a
                            // typed "how's my day", and a kept pill all reach
                            // the one composer.
                            chrome.askRequest = TodayBrief.title
                            // The title travels (prd §167a): set BEFORE
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
                        // Inset a step narrower than the bar (2026-07-22) —
                        // see WhisperCapsule's own note: stacked full-width
                        // glass read as a double-bar.
                        .padding(.horizontal, DS.Space.s3)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    AgentBar(hasUnseenSignal: KeptAskStore.shared.anyChanged && !agentEverOpened,
                             morphNS: agentMorph) {
                        DSHaptic.tap()
                        composerOpen = true
                    }
                }
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
                // The proxy title (prd §167a) — mounts in this SAME
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
        .animation(DS.Motion.standard, value: composerOpen)
        // The bar rides RootShell's OWN ZStack now (2026-07-19 — it replaced
        // the FAB, which used to live on MainSurface's root content
        // specifically so pushed rooms could slide over it; the bar
        // deliberately does the opposite, per ruling 6).
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
                // The "Noticed" line's real trigger (docs/agent-brief.md
                // ruling 10 — a gap the original ruling didn't name):
                // `HomeInsightStore.refresh` used to fire from ONLY
                // HomeScreen's own compose cycle, so a person who lands on
                // "All" a whole session (increasingly the common case under
                // content-first landing) never got a fresh line — same call,
                // same signature-gate, just a second trigger point, never
                // duplicated logic. Also refreshes the kept-ask digest cache
                // (`KeptAskStore.anyChanged`) the bar's pulse reads from, so
                // that stays current without recomputing on every render.
                Task { @MainActor in
                    let surfaced = Corpus.surfaced((try? modelContext.fetch(FetchDescriptor<Thing>(
                        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? [])
                    HomeInsightStore.shared.refresh(from: surfaced)
                    await KeptAskStore.shared.refreshDigests(things: surfaced, context: modelContext)
                    // The whisper's compose rides the same corpus walk this
                    // Task already paid for — never its own fetch.
                    refreshWhisper(things: surfaced)
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
        }
        // The agent is a full-screen ZStack layer now (docs/agent-brief.md
        // ruling 3), rendered above in `shell`'s own ZStack — no more sheet.
        // A fresh composer open is a fresh answer conversation — drop the prior
        // transcript so one conversation's turns never bleed into the next
        // (ConversationModel). Follow-ups WITHIN this open carry context.
        .onChange(of: composerOpen) { _, open in
            if open {
                OnDeviceModel.resetConversation()
                agentEverOpened = true
                // The whisper's job is done however the agent rose — it
                // never returns until a new day has something to say.
                whisper = nil
            } else {
                // A safety clear, not the primary one (that's the guarded
                // timer at the tap site) — a fast close before the timer
                // fires must not leave a stale proxy title behind for the
                // NEXT rise to inherit.
                chrome.risingBriefTitle = nil
            }
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
            // Landing (2026-07-13, simplified 2026-07-20 — the Pinned board
            // retired, docs/agent-brief.md rulings 11-12; amended 2026-07-21):
            // content-first was "always All" until here — now the app opens
            // wherever you were last standing (`FeedFilter.source` persists
            // on every write, read back in its own `init`), so this no
            // longer resets it. A fresh install has nothing persisted yet
            // and still opens on "All". Deep links and debug hooks below can
            // still override this within the same launch.
            // Honesty rule: if CasberiApp had to degrade the store open this
            // launch (SharedStore.containerWithFallback), say so once instead
            // of silently showing an empty/unsynced corpus.
            if let reason = SharedStore.degradeReason {
                chrome.flash(reason, tone: .failure, seconds: 4)
            }
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
            // Debug hook: `simctl launch ... -deeplink casberi://feed` lands in
            // UserDefaults; routes without the system open-in dialog.
            #if DEBUG
            NSLog("[Casberi] On-device model: %@", OnDeviceModel.availabilityLine)
            // `-landingChip <source>` (or `clear`) seeds the persisted
            // landing directly, without navigating this launch — a
            // two-launch probe (seed here, relaunch plain) verifies the
            // next-launch landing headlessly via MainSurface's `chipLabels:`
            // / the active chip on mount.
            FeedFilter.seedLandingFromLaunchArgs()
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
                deepLinkThing = all.first { $0.title.hasPrefix(prefix) }
                NSLog("[Casberi] openThing: %@",
                      deepLinkThing?.title ?? "no match for \(prefix)")
            }
            // `-openSettings YES` pushes Settings. Lives HERE, not a screen's
            // own onAppear — content-first landing is now the ONLY landing
            // (the Pinned board it used to have to out-race retired
            // 2026-07-20), so there's only ever one surface to time against.
            // This onAppear runs after the whole tree mounts — same proven
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
            if let q = UserDefaults.standard.string(forKey: "byokProbe") {
                Task {
                    await EmbeddingIndex.indexPending(context: modelContext)
                    let start = Date()
                    let outcome = await keyedAnswerDocument(q)
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    switch outcome {
                    case .success(let answer):
                        NSLog("[Casberi] byokProbe(\"%@\") %dms searchedWeb=%d images=%d →\n%@",
                              q, ms, answer.searchedWeb ? 1 : 0, answer.imagesSeen,
                              answer.doc.joined(separator: "\n"))
                    case .failure(let failure):
                        NSLog("[Casberi] byokProbe(\"%@\") %dms failed=%@ → \"%@\"",
                              q, ms, String(describing: failure), failure.line)
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
            // Debug hook: `-todayProbe YES` composes the Today brief (prd
            // §166) over the real corpus and logs the whole doc — every module
            // it chose and every observation that fired — so the composer
            // verifies without a tap. Pair with `-awayGap <hours>` to widen
            // the window a headless run measures.
            if UserDefaults.standard.bool(forKey: "todayProbe") {
                Task { @MainActor in
                    let all = Corpus.surfaced((try? modelContext.fetch(FetchDescriptor<Thing>(
                        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? [])
                    let landed = DayBrief.landed(all)
                    let result = await KeptAskComposers.compose("today", things: all,
                                                               context: modelContext)
                    NSLog("[Casberi] todayProbe: landed=%d headline=\"%@\" digest=\"%@\"",
                          landed.count, DayBrief.headline(things: all) ?? "(nil)",
                          result?.digest ?? "nil")
                    // One NSLog PER LINE — a joined multi-line message gets
                    // truncated by the log reader mid-document, which hid an
                    // unresolved ref for a whole debugging round (2026-07-22).
                    for line in result?.doc ?? ["(no doc)"] {
                        NSLog("[Casberi] todayDoc| %@", line)
                    }
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
            // Debug hook: `-toolAnswer "<query>"` runs the tool-calling agent
            // path (AnswerTools) in isolation — the model searches the corpus
            // via tools and answers, logging the prose and the ids it grounded
            // on. nil where the model is unavailable (the honest fallback the
            // default lookup path takes to the scoring doc).
            if let q = UserDefaults.standard.string(forKey: "toolAnswer") {
                Task { @MainActor in
                    let snap = toolSnapshot()
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
                HomeRoute.shared.push = nil   // land on the record, not a stale store push
                FeedFilter.shared.source = "All"
                deepLinkThing = thing
            }
        }
        .sheet(item: $deepLinkThing) { thing in
            rootPresented(ThingSheetView(thing: thing))
        }
        .sheet(item: $deepLinkPerson) { person in
            rootPresented(SocialProfileCard(profile: person))
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboarded }, set: { if !$0 { onboarded = true } }
        ), onDismiss: {
            guard landInCatalog else { return }
            landInCatalog = false
            FeedFilter.shared.source = "All"
            HomeRoute.shared.present(.apps)
        }) {
            // Onboarding is ONE screen (re-ruled 2026-07-16 — the connect
            // screen died): the "How it works" greeting, wearing the rain
            // itself. Its one door forward lands IN the catalog, which is
            // where connecting actually happens now — the arc is apps rain
            // down → the four steps → the catalog where those apps live, so
            // step 1 is fulfilled the moment the cover lifts. The record
            // ("All" chip) waits one back-swipe beneath it.
            rootPresented(HowItWorksSheet(onOpenCatalog: {
                landInCatalog = true
                onboarded = true
            }))
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
    private func rootPresented(_ content: some View) -> some View {
        content
            .environment(bridges)
            .environment(chrome)
            .environment(\.locale, LanguageStore.shared.locale)
    }

    /// casberi:// routing — one place, used by onOpenURL and the debug hook.
    private func route(_ url: URL) {
        // A deep link lands you AT a destination, not back in a store the route
        // singleton still holds from an earlier visit. apps/settings re-set it
        // below.
        HomeRoute.shared.push = nil
        switch url.host() {
        // casberi://home is back-compat (the app was a Home tab, then a
        // board) — it now lands on the All feed, ruling 11.
        case "home":    FeedFilter.shared.source = "All"; FeedFilter.shared.tag = "All"
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
            HomeRoute.shared.present(.apps)
        case "settings":
            HomeRoute.shared.present(.settings)
        // casberi://person/<Source>/<handle> — the profile card for one person
        // on one network (2026-07-16). In the app it's reached by tapping a
        // face; this is the same card by name, so the screen sweep can reach it
        // headlessly like every other surface.
        case "person":
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count == 2, SocialThread.isSocial(parts[0]) {
                deepLinkPerson = SocialProfile(source: parts[0], handle: parts[1],
                                               displayName: nil, bio: nil, avatarURL: nil)
            }
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

    /// The agent, full screen (docs/agent-brief.md ruling 3) — the composer's
    /// entire existing pipeline (byok, Organize, lastAnswerHits, GenStream),
    /// unchanged, now hosted as a persistent ZStack layer instead of a sheet.
    private var agentSurface: some View {
        Composer(isOpen: .constant(true), draft: $draft, embedded: true,
                 onCommit: saveDraft, onCommitVoice: saveVoice,
                 answer: answerDocument,
                 answerWithKey: keyedAnswerDocument,
                 tagCandidates: projectTags,
                 knownSources: { bridges.bridges.map(\.name) },
                 // Fixed 2026-07-20 — this was hardcoded nil, silently
                 // dropping the "meets you where you are" lead chip since
                 // the agent shell was built. FeedFilter.shared.source is
                 // the same active-chip signal MainSurface itself binds
                 // against; "All" is a safe sentinel that never collides
                 // with a real source name.
                 contextSource: { FeedFilter.shared.source == "All" ? nil : FeedFilter.shared.source },
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
                    HomeRoute.shared.present(.apps)
                    return
                }
                // Other sentinels ("@wallet", "@token:…") are surface routes,
                // not tags — from the composer they'd open a bogus tag view
                // literally named "@token:…"; an unknown sentinel does
                // nothing.
                guard !name.hasPrefix("@") else { return }
                HomeRoute.shared.push = nil
                composerOpen = false
                FeedFilter.shared.source = "All"
                HomeRoute.shared.openTag = name
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
        HomeRoute.shared.push = nil
        composerOpen = false
        switch intent {
        case .tag(let name):
            FeedFilter.shared.source = "All"
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
        modelContext.saveHonestly()
        SpotlightIndex.index([thing])
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
            chrome.flash(first ? "Your first thing" : "Saved", tone: .success)
        }

        // "Watching the record" used to mean either feed shape (Pinned or
        // All); the board retired 2026-07-20, so All is the one shape left.
        if FeedFilter.shared.source == "All" || first {
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
                var l = "You've connected \(seats.count) app\(seats.count == 1 ? "" : "s") — \(naturalList(seats.map(\.name)))."
                let needs = bridges.attentionCount
                if needs > 0 { l += " \(needs) need\(needs == 1 ? "s" : "") attention." }
                line = l
            }
        case .catalog:
            var l = "The catalog has \(shelf.count) apps to connect — \(shelf.prefix(3).map(\.name).joined(separator: ", ")), and more."
            if !seats.isEmpty { l += " You've connected \(seats.count)." }
            line = l
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
    private func answerDocument(_ query: String,
                                onProseDoc: @escaping ([String]) -> Void) async -> [String] {
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
            let fetched = (try? modelContext.fetch(FetchDescriptor<Thing>(
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
            ))) ?? []
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
            let line = AggregateAsk.answer(agg, things: allThings())
            return ["root = Stack([ins])", "ins = Insight(\"\(genSafe(line))\")"]
        }
        // "How's my day?" — the Today brief (prd §166), the screen the whisper
        // capsule opens. Answers THROUGH the composer itself so the typed ask,
        // the kept pill, and the whisper's tap can never drift (the §132
        // principle). Before the wallet/watchlist branches: this ask spans
        // them, and its own words ("today", "my day") never collide with
        // theirs.
        if TodayBrief.matches(query) {
            lastAnswerHits = []
            if let result = await KeptAskComposers.compose("today", things: allThings(),
                                                          context: modelContext) {
                return result.doc
            }
        }
        // A watchlist ask ("how's my watchlist") is answered from the same
        // 24h curves the feed pulse draws — computed, current, no model
        // (2026-07-14). Before StatusAsk on purpose: the words name the
        // watchlist, not the feeds.
        if TokensAsk.matches(query) {
            lastAnswerHits = []
            let moves = await TokensAsk.moves(context: modelContext)
            guard !moves.isEmpty else {
                // Empty MOVES isn't an empty WATCHLIST — offline, every pulse
                // fetch fails and a "nothing watched" line would be a fake
                // status (honesty rule). Say which nothing this is.
                return proseDoc(TokensAsk.watched(modelContext).isEmpty
                    ? "Nothing on your watchlist yet — watch a token from Apps → Tokens."
                    : "Couldn't read your watchlist's prices right now — check your connection.")
            }
            // TokenChip rows alongside the summary — `KeptAskComposers.watchlistDoc`
            // so a typed ask and the kept "How's my watchlist?" chip can never
            // disagree about what's shown.
            return KeptAskComposers.watchlistDoc(line: TokensAsk.line(moves), moves: moves)
        }
        // A wallet ask ("how's my wallet") is answered from the live holdings
        // and the forward-only value line — computed, no model (2026-07-15).
        // Before StatusAsk on purpose: the word "wallet" names the holdings, not
        // the feeds' pulse.
        if WalletAsk.matches(query) {
            lastAnswerHits = []
            guard let line = await WalletAsk.answer() else {
                return proseDoc(String(localized: "Nothing in your wallet yet — watch an address from Apps → Wallet."))
            }
            // The real holdings treemap alongside the summary, plus the
            // landed approvals + latest activity — shared with the kept-ask
            // composer via `KeptAskComposers.walletDoc` so the two paths agree.
            let groups = await WalletIngest.topHoldingsByWallet()
            return KeptAskComposers.walletDoc(line: line, groups: groups, things: allThings())
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
        if KeptAskComposers.matchesUpcoming(query) {
            lastAnswerHits = []
            if let result = await KeptAskComposers.compose("upcoming", things: allThings(),
                                                          context: modelContext) {
                return result.doc
            }
        }
        // A DeFi ask ("how's my loan", "what's my health factor", "how are
        // my Morpho vaults") — live read over Aave + Morpho, no model
        // (2026-07-20; Morpho 2026-07-21). Same slot as WalletAsk, right
        // after it: both need a watched wallet, and "aave"/"morpho"/"health
        // factor" never collides with the generic wallet words.
        if WalletDeFiAsk.matches(query) {
            lastAnswerHits = []
            guard let line = await WalletDeFiAsk.answer() else {
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
        if let (target, wantsSynthesis) = KeptAskComposers.namedAskTarget(query, things: allThings()) {
            // "synthesize"/"summarize"/"recap" asks for the model's OWN
            // prose over the same pool the deterministic recap would show —
            // a LIVE-only upgrade (ruling 13's principle: a kept ask never
            // re-synthesizes, it shows what the answer was drawn from — the
            // kept pill below always re-runs the plain recap regardless of
            // which verb minted it). Honest degradation throughout: no
            // model, a declined synthesis, or an empty window all fall to
            // the exact same deterministic doc a kept pill would show.
            if wantsSynthesis, OnDeviceModel.isAvailable {
                let pool = target.pool(in: allThings())
                let now = Date.now
                var recent = pool.filter { $0.capturedAt >= now.addingTimeInterval(-3 * 86_400) }
                if recent.isEmpty {
                    recent = pool.filter { $0.capturedAt >= now.addingTimeInterval(-7 * 86_400) }
                }
                if !recent.isEmpty {
                    // Capped at 16 candidates, the same convention
                    // `StatusAsk.sample`'s own rotation already keeps so a
                    // rich pool still fits the on-device context window.
                    let capped = Array(recent.prefix(16))
                    lastAnswerHits = capped
                    if let prose = await streamSynthesis(query, over: candidates(capped),
                                                         onProseDoc: onProseDoc) {
                        return proseDoc(prose)
                    }
                }
            }
            lastAnswerHits = []
            if let result = await KeptAskComposers.compose(target.keptKind, things: allThings(),
                                                          context: modelContext) {
                return result.doc
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
            if let prose = await streamSynthesis(query, over: candidates(pulse.sample),
                                                 onProseDoc: onProseDoc) {
                return appendingInsight(await tokenLine(), walletLine, to: proseDoc(prose))
            }
            return appendingInsight(await tokenLine(), walletLine, to: pulseDoc(pulse))
        }
        // A follow-up ("which ones were from sam") searches the LAST
        // answer's grounding, not the whole corpus (2026-07-10).
        let pool = isFollowUp(query) && !lastAnswerHits.isEmpty ? lastAnswerHits : nil
        let hits = retrieve(query, in: pool)
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
            #if DEBUG
            NSLog("[Casberi] lookup route: %d hits, followUp=%@ → %@", hits.count,
                  followUp ? "yes" : "no",
                  (!followUp && retrievalThin) ? "agent" : "compose")
            #endif
            if !followUp, retrievalThin,
               let result = await AnswerTools.answer(query: query, corpus: toolSnapshot()) {
                let grounded = things(forIDs: result.hitIDs)
                if !grounded.isEmpty {
                    lastAnswerHits = grounded
                    return modelDoc(insight: result.prose, hits: grounded,
                                    picks: Array(grounded.prefix(6).indices), tag: tag, in: allThings())
                }
                // Tools found nothing the pre-retrieval didn't — fall through to
                // compose over `hits` (the stronger semantic retriever's set).
            }
            guard let answer = await OnDeviceModel.compose(query: query, candidates: candidates(hits)) else {
                return retrievalDoc(hits, tag: tag, in: allThings())   // model declined or errored — fall back
            }
            return modelDoc(insight: answer.insight, hits: hits, picks: answer.picks, tag: tag, in: allThings())
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
                                     onProseDoc: @escaping ([String]) -> Void = { _ in })
    async -> Result<KeyedAnswer, AgentAnswerFailure> {
        let hits = lastAnswerHits.isEmpty ? retrieve(query) : lastAnswerHits
        // Bankr answers from the wallet and live markets too, so an empty
        // corpus match still asks; every other agent only re-reads the same
        // evidence, so an empty match gets the honest line instead.
        guard !hits.isEmpty || AgentKey.active == .bankr else {
            return .success(KeyedAnswer(doc: proseDoc(
                "Nothing in your things matches that — a bigger model can't change what's here.")))
        }
        let outcome = await AgentAnswer.synthesize(
            query: query, candidates: candidates(hits), history: keyedHistory,
            onPartial: { partial in onProseDoc(self.proseDoc(partial)) })
        guard case .success(let result) = outcome else {
            guard case .failure(let failure) = outcome else { return .failure(.empty) }
            return .failure(failure)
        }
        keyedHistory.append(AgentTurn(question: query, answer: result.text))
        let picks = result.picks.filter { hits.indices.contains($0) }
        // No `tag:`/`in:` here — `keyedAnswerDocument` never resolves a topic
        // tile the way the on-device lookup route does, and `modelDoc` skips
        // that tile entirely whenever `tag` is nil, so there's no corpus
        // fetch to make for it.
        let doc = picks.isEmpty ? proseDoc(result.text)
                                : modelDoc(insight: result.text, hits: hits, picks: picks)
        return .success(KeyedAnswer(doc: doc, searchedWeb: result.searchedWeb,
                                    imagesSeen: result.imagesSeen))
    }

    /// The corpus flattened to a plain `Sendable` snapshot for the tool-calling
    /// agent (AnswerTools) — the newest 2000 things, so a tool's `call` never
    /// reaches SwiftData off its actor. Same evidence shape (title/kind/source/
    /// when + excerpt) the single-shot candidates use.
    private func toolSnapshot() -> [AnswerTools.Snapshot] {
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 2000
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.map { t in
            AnswerTools.Snapshot(id: t.id.uuidString, title: t.title,
                                 kind: t.kind.typeTag, source: t.source,
                                 when: shortTime(t.capturedAt), text: answerSnippet(t))
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
    private func candidates(_ things: [Thing]) -> [OnDeviceModel.Candidate] {
        things.map {
            OnDeviceModel.Candidate(title: $0.title, kind: $0.kind.typeTag,
                                    source: $0.source, when: shortTime($0.capturedAt),
                                    note: answerSnippet($0),
                                    imageData: $0.kind == .screenshot ? $0.previewImageData : nil)
        }
    }

    /// A short, single-line excerpt of a thing's body for the model — the
    /// substance the title alone can't carry (a note's text, a chat's gist, a
    /// saved link's fetched article). Empty when nothing adds over the title.
    /// For a bare-URL link the body IS the URL (no prose), so it falls through
    /// to `enrichedText` — the page's own lede — when the fetch landed one.
    /// Capped at 300 so 16 candidates still fit the on-device context window.
    private func answerSnippet(_ thing: Thing) -> String {
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
        return squeezed.count > 300 ? String(squeezed.prefix(300)) + "…" : squeezed
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
            var descriptor = FetchDescriptor<Thing>(
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 2000
            corpus = (try? modelContext.fetch(descriptor)) ?? []
        }
        return Retriever.rank(query, in: corpus, isPoolRefinement: pool != nil)
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
                ? "Nothing here yet — connect an app or capture one thing, then ask about it."
                : "Nothing in your things matches that. Casberi answers from what you've captured — try your links, events, or screenshots, or ask what landed today."
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
    /// tap routes on (GenProjectTile → genProjectTap → HomeRoute.openTag).
    /// Takes the corpus already fetched by the caller (2026-07-21) — this and
    /// `matchedTag` used to each run their OWN full-corpus fetch on the common
    /// retrieval path, on top of `answerDocument`'s own.
    private func tagTile(_ tag: String?, in things: [Thing]) -> String? {
        guard let tag else { return nil }
        let count = things.filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }.count
        guard count > 0 else { return nil }
        return "tag = ProjectTile(\"2\", \"\(genSafe(tag))\", \"\", \"\(count) thing\(count == 1 ? "" : "s")\", \"\(count) things\", null)"
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

    // MARK: - Toast (commit feedback — state lives in ShellChrome.flash)

    /// Transient chrome floating over content — it wears glass.
    private func toastView(_ text: String) -> some View {
        HStack(spacing: DS.Space.s2) {
            // The first thing ever gets the mark (§8). Once. The first-ever
            // kept ask (composer delight, 2026-07-21) shares the treatment —
            // both are "your first standing X with Casberi" moments.
            if text == "Your first thing" || text.hasPrefix("Your first standing question") {
                CasberiMark(size: 18)
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
