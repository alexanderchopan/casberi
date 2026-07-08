import SwiftUI
import SwiftData
import CoreSpotlight

/// The shell. Three tabs behind a glass capsule; the composer spans full width
/// above the bar; no FAB; content scrolls under the floating stack. The phone
/// frame from the prototype is demo chrome and is dropped — the shell fills the
/// device (brief §7).
struct RootShell: View {
    @Environment(\.modelContext) private var modelContext
    @State private var tab: Tab = .home            // landing: Home
    @State private var bridges = BridgeStore()
    @State private var chrome = ShellChrome()
    @State private var composerOpen = false
    @State private var draft = ""
    @State private var deepLinkThing: Thing?
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("privacy.hidePreviews") private var hidePreviews = true
    @AppStorage("firstThingSaved") private var firstThingSaved = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasBeenActive = false
    @State private var redactNow = false
    @Namespace private var glassNS

    var body: some View {
        ZStack(alignment: .bottom) {
            // The themed page — the same field each screen paints for itself
            // (NavigationStack's backing is opaque, so photo rendering lives
            // inside the screens via dsPageBackground; this is the base coat).
            DSPageBackground()

            // Content — records paint, generated surfaces stream (brief §5).
            // Anything dropped on the shell lands as a thing (capture: drop).
            content
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

            // Scrim behind the engaged composer — light: the glass itself
            // separates the layers; the dim only settles focus.
            if composerOpen {
                DS.scrim.opacity(0.5).ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(DS.Motion.standard) { composerOpen = false }
                        draft = ""
                    }
            }

            if let toast = chrome.toast { toastView(toast) }

            // The capture flight (§1): a proxy card glides from the capture
            // point to the Feed tab, then the tab pulses once.
            if let flight = chrome.flight {
                CaptureFlight(flight: flight, target: chrome.feedTabFrame) {
                    chrome.flight = nil
                    chrome.landedPulse += 1
                }
                .zIndex(2)
            }

            // Floating bottom bar: tab capsule + composer FAB on one axis —
            // one glass substance; the FAB morphs into the bubble (iOS 26).
            DSGlassContainer(spacing: DS.Space.s3) {
                VStack(spacing: DS.Space.s3) {
                    Composer(isOpen: $composerOpen, draft: $draft,
                             onCommit: saveDraft, onCommitVoice: saveVoice,
                             answer: answerDocument,
                             tagCandidates: projectTags, glassNamespace: glassNS)
                    if !composerOpen {
                        HStack(spacing: DS.Space.s3) {
                            GlassTabBar(selection: $tab, glassNamespace: glassNS)
                            ComposerFAB(glassNamespace: glassNS) {
                                DSHaptic.tap()
                                withAnimation(DS.Motion.bubble) { composerOpen = true }
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
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
                // Returning crossfades from placeholder to content (§14);
                // leaving redacts instantly — the snapshot must already hide.
                withAnimation(.easeOut(duration: 0.2)) { redactNow = false }
                // Warm the model on foreground so the first Ask is fast; the
                // call is idempotent and returns immediately.
                if !skipPrewarm { OnDeviceModel.prewarm() }
                // Connected bridges are cheap to poll — every foreground
                // refreshes them all (one place, reusable from screens).
                BridgeRefresh.refreshAllConnected(context: modelContext)
                // Control Center's button left a flag — open the composer.
                let group = UserDefaults(suiteName: SharedStore.appGroup)
                if group?.bool(forKey: "compose.request") == true {
                    group?.removeObject(forKey: "compose.request")
                    withAnimation(DS.Motion.bubble) { composerOpen = true }
                }
            } else {
                if hasBeenActive && hidePreviews { redactNow = true }
                if phase == .background {
                    // Give the model's memory back when we're not in use; the
                    // next foreground reloads it.
                    OnDeviceModel.teardown()
                }
            }
        }
        .animation(DS.Motion.standard, value: composerOpen)
        .dsSensoryFeedback()
        .environment(bridges)
        .environment(chrome)
        // Mode is the person's; a chosen photo implies the dark treatment.
        .preferredColorScheme(
            ThemeStore.shared.isLight && ThemeStore.shared.backgroundPhoto == nil ? .light : .dark
        )
        // casberi:// deep links — widgets and App Intents route through these.
        // casberi://home|feed|account switch tabs; casberi://thing/latest opens
        // the newest thing's sheet (the widget-tap route).
        .onOpenURL { route($0) }
        .onAppear {
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
                let migrationsCurrent = 1
                if UserDefaults.standard.integer(forKey: migrationsKey) < migrationsCurrent {
                    // Demo mode died (option 4, 2026-07-07) — any sample things
                    // a previous build seeded are removed for good.
                    let samples = (try? modelContext.fetch(FetchDescriptor<Thing>(
                        predicate: #Predicate { $0.isSample == true }
                    ))) ?? []
                    for thing in samples { modelContext.delete(thing) }
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
                    for thing in noisy { thing.title = "Screenshot" }
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
            // Debug hook: `simctl launch ... -answerProbe "what did I save about work"`
            // runs the whole answer path (retrieve → on-device compose → doc)
            // and logs the composition + its latency, so it can be verified and
            // timed without the UI. `-probeDelay <s>` waits before the probe
            // (lets prewarm settle, to A/B warm vs `-noPrewarm` cold).
            if let q = UserDefaults.standard.string(forKey: "answerProbe") {
                let delay = UserDefaults.standard.double(forKey: "probeDelay")
                Task {
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    let start = Date()
                    let doc = await answerDocument(q) { partial in
                        NSLog("[Casberi] answerProbe stream →\n%@", partial.joined(separator: "\n"))
                    }
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    NSLog("[Casberi] answerProbe(\"%@\") %dms →\n%@", q, ms, doc.joined(separator: "\n"))
                }
            }
            // Debug hook: open the composer so `-uiAnswerProbe` (handled in the
            // composer) can drive a real send for an on-screen answer render.
            if UserDefaults.standard.string(forKey: "uiAnswerProbe") != nil {
                composerOpen = true
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
                tab = .feed
                deepLinkThing = thing
            }
        }
        .sheet(item: $deepLinkThing) { thing in
            ThingSheetView(thing: thing)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboarded }, set: { if !$0 { onboarded = true } }
        )) {
            // Onboarding (option 4, 2026-07-07): the mini store connects the
            // three real bridges for REAL, and that's the whole tour — no
            // demo mode, no sample things. The dream lives on the store
            // pages as engine-rendered previews. Landing is FEED: the record
            // the connects just filled.
            OnboardingView(store: bridges) { _ in
                onboarded = true
                tab = .feed
            }
        }
    }

    /// casberi:// routing — one place, used by onOpenURL and the debug hook.
    private func route(_ url: URL) {
        switch url.host() {
        case "home":    tab = .home
        case "feed":
            tab = .feed
            // casberi://feed/type/Link — Home's kind bar lands here filtered.
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count == 2, parts[0] == "type" {
                FeedFilter.shared.tag = parts[1]
            }
        // Apps is no longer a tab — land on Home and push the Apps screen from
        // its toolbar route (back-compat for casberi://apps and //account).
        case "account", "apps":
            tab = .home
            HomeRoute.shared.push = .apps
        case "thing":
            tab = .feed
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

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home: HomeScreen()
        case .feed: FeedScreen()
        }
    }

    // MARK: - Capture (rung 1 write: the composer saves to us)

    private func saveDraft(tags: [String]) {
        guard let thing = Capture.thing(from: draft) else { return }
        thing.tags.append(contentsOf: tags)   // parse-card candidates ride in
        modelContext.insert(thing)
        try? modelContext.save()
        SpotlightIndex.index([thing])
        DSHaptic.success()
        land(thing)
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

    /// Every save ends here (§1): toast, and — unless the person is already
    /// watching Feed, where the new row IS the arrival — the proxy-card
    /// flight to the Feed tab. The very first thing ever gets its own toast
    /// and always flies (§8). Haptic stays at commit, in the callers.
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

        if tab != .feed || first {
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

    /// How an Ask gets answered. Lookups ("find X", "what did I save") want a
    /// structured list, so they use guided generation → a Widget of real things
    /// (the strong honesty rail: the model returns indices, never free text).
    /// Open synthesis ("what's my week", "recap") wants a short summary, so it
    /// streams plain prose. The router leans to lookup when unsure — structure
    /// is the safer default.
    private enum AnswerMode { case lookup, synthesis }

    private func answerMode(_ query: String) -> AnswerMode {
        let q = query.lowercased()
        // A retrieval verb is a strong lookup signal — it wins outright, even
        // over a temporal cue ("what did I save this week" is still a lookup).
        let lookupVerbs = ["find", "search", "show", "save", "saved",
                           "where", "which", "list", "look up"]
        if lookupVerbs.contains(where: q.contains) { return .lookup }
        // Otherwise a reflection/summary cue routes to prose.
        let synthesisCues = ["what's my", "whats my", "how was", "how's my", "hows my",
                             "summar", "recap", "overview", "catch me up", "my week",
                             "my day", "my month", "lately", "what did i do",
                             "what have i", "going on", "highlights"]
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
        let hits = retrieve(query)
        guard OnDeviceModel.isAvailable, !hits.isEmpty else {
            return retrievalDoc(hits)
        }
        let candidates = hits.map {
            OnDeviceModel.Candidate(title: $0.title, kind: $0.kind.typeTag,
                                    source: $0.source, when: shortTime($0.capturedAt))
        }
        switch answerMode(query) {
        case .lookup:
            guard let answer = await OnDeviceModel.compose(query: query, candidates: candidates) else {
                return retrievalDoc(hits)   // model declined or errored — fall back
            }
            return modelDoc(insight: answer.insight, hits: hits, picks: answer.picks)
        case .synthesis:
            guard let stream = OnDeviceModel.synthesisStream(query: query, candidates: candidates) else {
                return retrievalDoc(hits)
            }
            var last = ""
            for await snapshot in stream {
                last = snapshot
                onProseDoc(proseDoc(snapshot))
            }
            let final = last.trimmingCharacters(in: .whitespacesAndNewlines)
            return final.isEmpty ? retrievalDoc(hits) : proseDoc(final)
        }
    }

    /// A synthesis snapshot as a composition — a single growing Insight. The
    /// prose is the answer; the grounded things are what it was written from.
    private func proseDoc(_ text: String) -> [String] {
        ["root = Stack([ins])",
         "ins = Insight(\"\(genSafe(text))\")"]
    }

    /// The scoring engine — retrieval only. Matches are scored, not just found:
    /// title hits outweigh tag hits outweigh content hits, fresh things float,
    /// and kind words in the person's own words filter ("screenshots about
    /// work" searches screenshots for work). Returns the ranked grounding set
    /// (top 10 — a wider net for the model than the 4 the fallback paints).
    private func retrieve(_ query: String) -> [Thing] {
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
        let stops: Set<String> = ["about", "my", "the", "a", "in", "from", "for", "of"]
        terms.removeAll { stops.contains($0) }

        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        let all = (try? modelContext.fetch(descriptor)) ?? []

        return all.compactMap { thing -> (Thing, Double)? in
            if let kindFilter, thing.kind != kindFilter { return nil }
            let title = thing.title.lowercased()
            let tags = thing.tags.joined(separator: " ").lowercased()
            let content = thing.content.lowercased()
            var score = 0.0
            for term in terms {
                if title.contains(term) { score += 3 }
                if tags.contains(term) { score += 2 }
                if content.contains(term) { score += 1 }
            }
            // A bare kind query ("screenshots?") lists that kind.
            if terms.isEmpty && kindFilter != nil { score = 1 }
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
    private func retrievalDoc(_ hits: [Thing]) -> [String] {
        let shown = Array(hits.prefix(4))
        guard !shown.isEmpty else {
            return ["root = Stack([ins])",
                    "ins = Insight(\"Nothing matches yet. Things you capture land here.\")"]
        }
        var doc = ["root = Stack([res])"]
        let ids = shown.indices.map { "r\($0)" }
        doc.append("res = Widget(\"Found\", \"\(shown.count)\", [\(ids.joined(separator: ", "))])")
        for (i, t) in shown.enumerated() {
            let title = t.title.replacingOccurrences(of: "\"", with: "")
            doc.append("r\(i) = Row(\"\(title)\", \"\(t.kind.typeTag)\", \"\(t.source)\", \"\(shortTime(t.capturedAt))\")")
        }
        return doc
    }

    /// The model's answer as a composition: its one plain sentence up top, then
    /// the things it picked — painted from the REAL things (the model chose
    /// indices, never content), so every row is honest. No picks = just the
    /// sentence (the model said nothing fits).
    private func modelDoc(insight: String, hits: [Thing], picks: [Int]) -> [String] {
        let clean = genSafe(insight)
        let picked = picks.compactMap { hits.indices.contains($0) ? hits[$0] : nil }.prefix(6)
        guard !picked.isEmpty else {
            return ["root = Stack([ins])",
                    "ins = Insight(\"\(clean)\")"]
        }
        var doc = ["root = Stack([ins, res])",
                   "ins = Insight(\"\(clean)\")"]
        let ids = picked.indices.map { "r\($0)" }
        doc.append("res = Widget(\"Found\", \"\(picked.count)\", [\(ids.joined(separator: ", "))])")
        for (i, t) in picked.enumerated() {
            doc.append("r\(i) = Row(\"\(genSafe(t.title))\", \"\(t.kind.typeTag)\", \"\(t.source)\", \"\(shortTime(t.capturedAt))\")")
        }
        return doc
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
                Button(action: action.run) {
                    Text(action.label)
                        .dsText(.label12)
                        .foregroundStyle(DS.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
        .dsGlass(cornerRadius: DS.Radius.pill)
        .padding(.bottom, 140)
        // A replacing flash swaps identity — crossfade, never a stack (§12).
        .id(text)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// The §1 proxy card: KindGlyph + truncated title, gliding from above the
/// bar to the Feed tab, shrinking and fading. One keyframe pair.
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
