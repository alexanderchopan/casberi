import SwiftUI
import SwiftData

/// PostHog, connected — paste a scoped key, pick a project, watch a metric.
///
/// The screen has three states and shows exactly one at a time, because a
/// setup form that renders its later steps greyed-out reads as broken (the
/// §83 honesty corollary about disabled controls that still paint a live
/// background): no key → the key field; a key but no project → the picker;
/// both → the omnibox and the roster.
struct PostHogScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var hostField = PostHogAccount.host
    @State private var keyField = ""
    /// Bumped whenever the key or project changes, so the derived reads below
    /// re-evaluate. The STORES stay the source of truth — mirroring them into
    /// @State meant four hand-kept assignments that could disagree with the
    /// Keychain.
    @State private var accountVersion = 0

    @State private var projects: [PostHogFetch.Project] = []
    @State private var resolving = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var flipTrigger = 0

    /// The watch omnibox.
    @State private var queryField = ""
    @State private var hits: [PostHogFetch.EventDef] = []
    @State private var hitsQuery = ""
    @FocusState private var fieldFocused: Bool

    /// The watchlist rows — one per watched metric. The watch IS the thing.
    @State private var watched: [Thing] = []
    @State private var syncing = false
    @State private var syncPending = false
    /// Each metric's current reading, keyed by event name — the discs draw
    /// from this, so the roster and the feed can never disagree.
    @State private var readings: [String: PostHogState.Metric] = [:]
    @State private var openThing: Thing?

    private var hasKey: Bool {
        _ = accountVersion
        return TokenBridge.posthog.connected
    }
    private var projectID: String {
        _ = accountVersion
        return PostHogAccount.projectID
    }
    private var configured: Bool { hasKey && !projectID.isEmpty }

    var body: some View {
        List {
            BridgeSetupHeader(
                name: "PostHog",
                mode: .pasteKey,
                intro: "Paste a read-only key, watch the metrics you care about, and only what's actually news arrives: a milestone crossed, a metric falling silent, a deploy you annotated. Aggregates only — nothing here reads an individual person's profile.",
                connected: configured && !watched.isEmpty,
                flipTrigger: flipTrigger)
            if !hasKey {
                keySection.listRowSeparator(.hidden)
            } else if projectID.isEmpty {
                projectSection.listRowSeparator(.hidden)
            } else {
                watchSection.listRowSeparator(.hidden)
                if !watched.isEmpty { rosterSection }
            }
            if hasKey {
                BridgeDisconnectSection(bridgeID: TokenBridge.posthog.bridgeID,
                                        name: "PostHog",
                                        teardown: {
                                            PostHogWatch.unwatchAll(context: modelContext)
                                            TokenVault.delete(TokenBridge.posthog.tokenKey)
                                            PostHogAccount.clear()
                                            projects = []
                                            accountVersion += 1
                                            load()
                                        })
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "PostHog")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .dsScreenTitle("PostHog")
        .sheet(item: $openThing) { thing in
            ThingSheetView(thing: thing)
        }
        .onAppear {
            load()
            if configured && !watched.isEmpty {
                Task { await sync() }
            }
        }
        // Reopening with a key stored but no project picked (a multi-project
        // org, the app relaunched) otherwise rendered step two with no rows,
        // no spinner and no way forward.
        .task(id: hasKey) {
            guard hasKey, projectID.isEmpty, projects.isEmpty, !resolving,
                  let key = TokenVault.get(TokenBridge.posthog.tokenKey) else { return }
            resolving = true
            projects = await PostHogFetch.projects(host: PostHogAccount.host, key: key) ?? []
            resolving = false
        }
        // The debounced event-name search — only once a project is picked,
        // since the endpoint is project-scoped.
        .task(id: queryField) {
            guard configured else { return }
            let q = queryField.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let key = TokenVault.get(TokenBridge.posthog.tokenKey) else { return }
            if let found = await debouncedSearch(q, fetch: {
                await PostHogFetch.eventNames(host: PostHogAccount.host,
                                              project: PostHogAccount.projectID,
                                              key: key, query: q)
            }) {
                hits = found
                hitsQuery = q
            }
        }
    }

    // MARK: - Step one: the key

    private var keySection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if let url = TokenBridge.posthog.setupURL {
                    // Step one, doing itself (prd §218) — verb over address,
                    // the 2026-08-14 anatomy.
                    DSSlabButton(title: TokenBridge.posthog.doorTitle,
                                 detail: TokenBridge.posthog.doorHost,
                                 systemImage: "arrow.up.right") {
                        DSHaptic.tap()
                        openURL(url)
                    }
                }
                // The next line, then the list it points AT, then the last
                // line and the fields. The scopes used to sit below the
                // fields, which is why the first step had to name all three in
                // prose to be useful there — the reorder is what let that
                // sentence lose them (the Stripe fix, one screen over;
                // 2026-07-31). Unnumbered since 2026-08-14 (the door did step
                // one; a "2" under it read as a missing-1 riddle).
                BridgeStepLines(steps: [TokenBridge.posthog.steps[0]], numbered: false)
                // The scopes are the honest ask, and they're the reason this
                // bridge's read-only promise is STRUCTURAL rather than kept by
                // conduct (the Privacy.com divergence): a key minted with these
                // three physically cannot write, whatever the app does. The
                // list IS the read-only promise, so the gray note that restated
                // it is gone.
                DSCheckList(lines: ["query:read", "annotation:read", "event_definition:read"])
                BridgeStepLines(steps: [TokenBridge.posthog.steps[1]], numbered: false)
                // The host has no verb of its own — SAVE below commits both.
                // A `BridgeFieldRow` with an empty label still paints its
                // capsule, and a pre-filled host made it read as a live,
                // tinted, inert button (§83's disabled-control corollary).
                DSSlabField(placeholder: PostHogAccount.defaultHost, text: $hostField,
                            actionLabel: "", keyboard: .URL, action: { })
                // The key field was the last `BridgeFieldRow` here, stacked
                // directly under the host's `DSSlabField` — two field shapes at
                // two heights for one act, the most visible seam left by the
                // §218 slab migration (audit, 2026-07-31). The empty-verb pair
                // above is exactly the shape `DSSlabField` documents for two
                // inputs one act needs; SAVE belongs to the last field.
                DSSlabField(placeholder: TokenBridge.posthog.placeholder,
                            text: $keyField, actionLabel: "Save", secure: true,
                            action: saveKey)
                BridgeSyncStatusRows(syncing: resolving,
                                     syncingLine: String(localized: "Checking the key…"),
                                     result: result, resultIsError: resultIsError)
            }
        }
        .dsSlabSection()
    }

    // MARK: - Step two: the project

    private var projectSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Which project should I read?")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                ForEach(projects) { project in
                    BridgeSearchResultRow(
                        imageURL: nil, fallbackIcon: "PostHog",
                        title: project.name,
                        subtitle: project.org.isEmpty ? PostHogAccount.host : project.org,
                        action: { pick(project) })
                }
                BridgeSyncStatusRows(syncing: resolving,
                                     syncingLine: String(localized: "Reading your projects…"),
                                     result: result, resultIsError: resultIsError)
            }
        }
        .dsSlabSection()
    }

    // MARK: - Step three: watching

    private var watchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                DSSlabField(placeholder: String(localized: "Event or metric name"),
                            text: $queryField, actionLabel: String(localized: "Watch"),
                            focus: $fieldFocused, action: watchTyped)
                ForEach(displayHits) { event in
                    BridgeSearchResultRow(
                        imageURL: nil, fallbackIcon: "PostHog",
                        title: event.name,
                        subtitle: lastSeenLine(event),
                        action: { watch(event.name) })
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading PostHog…"),
                                     result: result, resultIsError: resultIsError)
                DSSlabNote(text: "Deploys and launches you annotate land on their own.")
            }
        }
        .dsSlabSection()
    }

    /// Events already watched drop out of the hits — they're on the shelf below.
    private var displayHits: [PostHogFetch.EventDef] {
        let refs = Set(watched.compactMap(\.sourceRef))
        return hits.filter { !refs.contains(PostHogWatch.metricRef($0.name)) }
    }

    private func lastSeenLine(_ event: PostHogFetch.EventDef) -> String {
        guard let seen = event.lastSeen else { return "" }
        return String(localized: "seen \(seen.formatted(.relative(presentation: .named)))")
    }

    // MARK: - The roster

    private var rosterSection: some View {
        AssetRosterShelf(note: rosterNote) {
            ForEach(watched.keyed) { row in
                // Corollary 3 (build 176) — see `ThingRowKeying`.
                if let thing = row.live { rosterSlot(thing) }
            }
            AssetRosterAddSlot { fieldFocused = true }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var rosterNote: String {
        let n = watched.count
        return n == 1
            ? String(localized: "Watching 1 · hold to unwatch")
            : String(localized: "Watching \(n) · hold to unwatch")
    }

    /// One metric on the shelf. The mark is the metric's OWN shape — its
    /// seven-day curve drawn inside the disc, ringed by how far it's come
    /// toward its next milestone. A generic glyph would have named nothing
    /// (the `TickerDisc` reasoning: a stock has no logo, so the ticker IS the
    /// mark) — and unlike a glyph, this one differs per metric because the
    /// data differs, and it changes as the week does.
    private func rosterSlot(_ thing: Thing) -> some View {
        let event = PostHogWatch.event(from: thing) ?? ""
        let reading = readings[event]
        let change = weekChange(reading)
        return AssetRosterSlot(label: event, change: change) {
            MetricDisc(series: reading?.series ?? [],
                       progress: reading.map { PostHogMilestone.progress($0.total) } ?? 0,
                       change: change)
        }
        .onTapGesture {
            DSHaptic.tap()
            openThing = thing
        }
        .contextMenu {
            Button(role: .destructive) {
                unwatch(thing)
            } label: {
                Label("Unwatch", systemImage: "trash")
            }
        }
    }

    /// This week against the week before it — nil when there isn't enough
    /// series to say, so the slot shows nothing rather than a placeholder.
    private func weekChange(_ reading: PostHogState.Metric?) -> Double? {
        guard let series = reading?.series, series.count >= 14 else { return nil }
        let thisWeek = series.suffix(7).reduce(0, +)
        let lastWeek = series.dropLast(7).suffix(7).reduce(0, +)
        guard lastWeek > 0 else { return nil }
        return Double(thisWeek - lastWeek) / Double(lastWeek)
    }


    // MARK: - Actions

    /// The watch rows only. The prefix is in the PREDICATE, not a Swift
    /// filter after the fact: landed annotations, milestones and silences all
    /// carry `source == "PostHog"` and grow without bound, while the watch
    /// list never does — fetching all of them to keep three was work that got
    /// steadily more expensive (review, 2026-07-27).
    private func load() {
        let prefix = PostHogWatch.metricPrefix
        let descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate {
                $0.source == "PostHog" && ($0.sourceRef?.starts(with: prefix) ?? false)
            },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        watched = (try? modelContext.fetch(descriptor)) ?? []
        readings = PostHogState.all()
    }

    private func saveKey() {
        let key = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = hostField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !resolving else { return }
        DSHaptic.tap()
        resolving = true
        resultIsError = false
        PostHogAccount.host = host.isEmpty ? PostHogAccount.defaultHost : host
        Task {
            let found = await PostHogFetch.projects(host: PostHogAccount.host, key: key)
            resolving = false
            guard let found, !found.isEmpty else {
                // The honest split the probe also draws: a rejected key and an
                // unreachable host are different problems with different fixes.
                result = found == nil
                    ? String(localized: "PostHog refused that key — check it and the host.")
                    : String(localized: "That key can't see any project.")
                resultIsError = true
                return
            }
            TokenVault.set(key, for: TokenBridge.posthog.tokenKey)
            accountVersion += 1
            keyField = ""
            projects = found
            result = nil
            flipTrigger += 1
            DSHaptic.success()
            // One project is not a choice — take it and move on.
            if found.count == 1 { pick(found[0]) }
        }
    }

    private func pick(_ project: PostHogFetch.Project) {
        DSHaptic.tap()
        PostHogAccount.projectID = project.id
        PostHogAccount.projectName = project.name
        accountVersion += 1
        result = nil
        resultIsError = false
    }

    private func watchTyped() {
        let q = queryField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        // The debounced search already ran this exact query — its top hit is
        // what a fresh lookup would return. Only when it really was THIS query
        // (mid-debounce, hits still answer the previous text).
        if hitsQuery == q, let top = hits.first {
            watch(top.name)
        } else {
            watch(q)
        }
    }

    private func watch(_ event: String) {
        DSHaptic.tap()
        resultIsError = false
        guard PostHogWatch.add(event, context: modelContext) != nil else {
            result = String(localized: "\(event) is already watched.")
            return
        }
        result = String(localized: "Watching \(event)")
        queryField = ""
        hits = []
        load()
        PostHogWatch.registerBridge(store: store, context: modelContext)
        Task { await sync() }
    }

    private func unwatch(_ thing: Thing) {
        guard thing.isLive else { return }
        if let event = PostHogWatch.event(from: thing) { PostHogState.forget(event) }
        SpotlightIndex.remove(ids: [thing.id])
        modelContext.delete(thing)
        modelContext.saveHonestly()
        DSHaptic.tap()
        load()
        PostHogWatch.registerBridge(store: store, context: modelContext)
    }

    /// Reads PostHog and lands whatever counts as news. Chains rather than
    /// skips (the Stocktwits contract): a watch added mid-pass re-runs the
    /// sweep with the fresh list instead of dropping the request.
    private func sync() async {
        if syncing { syncPending = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncPending = false
            let added = await PostHogIngest.refresh(context: modelContext)
            load()
            PostHogWatch.registerBridge(store: store, context: modelContext)
            guard !watched.isEmpty else { return }
            if let added {
                result = added > 0 ? String(localized: "\(added) new")
                                   : String(localized: "Up to date")
                resultIsError = false
            } else {
                result = String(localized: "Couldn't reach PostHog — check your connection.")
                resultIsError = true
            }
        } while syncPending
    }
}

// MARK: - The metric's mark

/// A watched metric's disc: its own seven-day curve drawn inside the circle,
/// ringed by its progress toward the next milestone.
///
/// Two facts, no text — the Activity-ring idea applied to the one number a
/// person watching a metric actually wants at a glance ("is it moving, and am
/// I nearly there"). It is data, not decoration: a metric with no reading yet
/// draws an empty disc rather than a fake curve, and the ring is absent (not
/// zeroed) until a total is known, since an empty ring reads as "no progress"
/// when the truth is "not read yet".
struct MetricDisc: View {
    let series: [Int]
    let progress: Double
    /// The week-over-week change the row is ALREADY showing in its delta pill.
    /// Passed in rather than re-derived from the drawn window: the disc read
    /// day-1-vs-day-7 while the pill read this-week-vs-last-week, so a metric
    /// that fell all week but ended well drew a green curve inside a red pill
    /// (review, 2026-07-27). One number, one direction, one colour.
    var change: Double?
    var size: CGFloat = 56

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// **The disc draws itself** (2026-08-04, prd §298): the curve strokes on,
    /// then the milestone ring winds up to where the metric has actually got
    /// to. The ring is the one here that had to be a `trim` rather than a fade
    /// — winding IS the fact it states, and a ring that fades in at 40% just
    /// asserts 40%. Ordered curve-then-ring because the ring is progress toward
    /// a rung the curve explains.
    @State private var entered = false

    /// The last seven days, normalised 0…1 for drawing. Fewer than two points
    /// can't make a line — the disc stays empty rather than inventing one.
    private var normalized: [Double]? {
        let week = Array(series.suffix(7))
        guard week.count >= 2 else { return nil }
        let low = week.min() ?? 0, high = week.max() ?? 0
        guard high > low else {
            // A flat week is real and worth drawing — as a flat line through
            // the middle, not as nothing and not as noise.
            return week.map { _ in 0.5 }
        }
        return week.map { Double($0 - low) / Double(high - low) }
    }

    /// The app's one delta colour, so the disc, the pill beneath it and every
    /// wallet row agree — including on flat, which gets no direction at all.
    private var accent: Color {
        guard let change else { return DS.textTertiary }
        return TokenChartStyle.accent(change: change, scheme: scheme)
    }

    /// Falling — and only genuinely falling. A flat week has no direction, so
    /// it draws solid rather than dashed (the honesty corollary again).
    private var falling: Bool {
        guard let change, !TokenChartStyle.isFlat(change) else { return false }
        return change < 0
    }

    var body: some View {
        ZStack {
            Circle().fill(DS.fillFaint)
            if let week = normalized {
                // Solid up, DASHED down — the same greyscale-survivable
                // treatment `Sparkline` adopted on 2026-07-21, for the same
                // reason: direction carried by hue alone is no direction at
                // all for a colour-blind reader, and this disc is the metric's
                // whole mark.
                curve(week)
                    .trim(from: 0, to: entered ? 1 : 0)
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.8,
                                                       lineCap: .round, lineJoin: .round,
                                                       dash: falling ? [3, 2] : []))
            }
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: entered ? progress : 0)
                    .stroke(accent.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // Still animates on a LATER change too (a sync moving the
                    // metric on), which is what this modifier was here for.
                    .animation(reduceMotion ? nil : DS.Motion.standard, value: progress)
            }
        }
        .frame(width: size, height: size)
        .onAppear(perform: enter)
        .accessibilityLabel(accessibilityLine)
    }

    private func enter() {
        guard !entered else { return }
        guard !reduceMotion else { entered = true; return }
        // The curve strokes over the wipe's own duration; the ring winds up
        // behind it, landing just after — see the `entered` doc.
        withAnimation(.easeOut(duration: ChartEntrance.wipe)
            .delay(ChartEntrance.lead)) { entered = true }
    }

    /// The disc draws TWO facts and spoke one. The curve's direction was named
    /// and the milestone ring — the whole reason this is a disc rather than a
    /// line — was never mentioned at all, so a metric one percent from a rung
    /// it has been climbing for a month announced itself as "trend, up".
    ///
    /// The ring is stated as a share rather than as the rung it is chasing:
    /// `MetricDisc` is handed `progress` alone and does not know what the next
    /// milestone IS, and naming a number it was not given is the one way this
    /// sentence could be confidently wrong.
    private var accessibilityLine: Text {
        var parts: [String] = []
        if let change, !TokenChartStyle.isFlat(change) {
            parts.append(FigureVoice.trend(direction: .of(change: change),
                                           move: TokenChartStyle.changeText(change)))
        } else {
            parts.append(FigureVoice.trend(direction: .flat, move: nil))
        }
        if progress > 0 {
            let pct = Int((min(max(progress, 0), 1) * 100).rounded())
            parts.append(String(localized: "\(pct) percent to the next milestone."))
        }
        return Text(parts.joined(separator: " "))
    }

    /// The curve, inset inside the disc. The inset is applied to the POINTS,
    /// not by `.padding` on the stroked shape: a `Path` ignores the rect it's
    /// proposed, so padding only shifted the whole line down and right and ran
    /// it off the edge of the circle (review, 2026-07-27).
    private func curve(_ week: [Double]) -> Path {
        let inset = size * 0.26
        let box = size - inset * 2
        return Path { path in
            let step = box / Double(week.count - 1)
            for (i, value) in week.enumerated() {
                // y is flipped so a rising series rises.
                let point = CGPoint(x: inset + Double(i) * step,
                                    y: inset + (1 - value) * box)
                i == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }
}
