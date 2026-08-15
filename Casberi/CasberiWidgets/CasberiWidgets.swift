import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Casberi's tiles (P8: awareness lands; the corpus speaks without being
/// asked). Every one of them reads the shared store or the app group — none
/// computes anything, none reaches the network, and none can (see
/// `WidgetPayload`).
///
/// Four widgets since 2026-08-14 (prd §382), where there was one. The hero says
/// what the day is; the kept-ask tile answers a standing question you chose;
/// "Needs you" carries the deadlines nothing else on a Home Screen would show;
/// the wallet draws the line the balance card draws. Plus two Control Center
/// buttons and two Live Activities.
@main
struct CasberiWidgets: WidgetBundle {
    var body: some Widget {
        HeroWidget()
        KeptAskWidget()
        NeedsYouWidget()
        WalletWidget()
        ComposeControl()
        BriefControl()
        #if !targetEnvironment(macCatalyst)
        VoiceRecordingActivity()
        ImportActivity()
        #endif
    }
}

/// While a voice note records, the lock screen and Dynamic Island show the
/// recording state — waveform, elapsed time — and tapping returns to the
/// composer. Recording state only; the words stay in the app (goal 6).
/// Unavailable on Mac Catalyst (no Live Activities/Dynamic Island there).
#if !targetEnvironment(macCatalyst)
struct VoiceRecordingActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceRecordingAttributes.self) { context in
            // Lock screen band.
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .dsGlyph(20, weight: .medium)
                    .foregroundStyle(.red)
                Text("Recording")
                    .dsText(.widgetChrome15)
                Spacer()
                Text(timerInterval: context.state.startedAt...Date(
                    timeInterval: 60 * 60, since: context.state.startedAt))
                    .dsText(.widgetChrome15)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
                Image(systemName: "stop.circle.fill")
                    .dsGlyph(24)
                    .foregroundStyle(.red)
            }
            .padding(14)
            .activityBackgroundTint(.black.opacity(0.8))
            .widgetURL(URL(string: "casberi://home"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform")
                        .dsGlyph(22, weight: .medium)
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...Date(
                        timeInterval: 60 * 60, since: context.state.startedAt))
                        .dsText(.heading17)
                        .monospacedDigit()
                        .frame(maxWidth: 60)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Recording")
                        .dsText(.widgetChrome15)
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date(
                    timeInterval: 60 * 60, since: context.state.startedAt))
                    .dsText(.widgetTimer13)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
            }
            .widgetURL(URL(string: "casberi://home"))
        }
    }
}
#endif

/// Control Center's capture button — one press anywhere, the composer opens.
/// The intent leaves a flag in the app group; the shell reads it on activation.
struct OpenComposerIntent: AppIntent {
    static let title: LocalizedStringResource = "Save a thing"
    static let description = IntentDescription("Opens Casberi's composer.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?
            .set(true, forKey: "compose.request")
        return .result()
    }
}

struct ComposeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "casberi.compose") {
            ControlWidgetButton(action: OpenComposerIntent()) {
                Label("Save a thing", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Save to Casberi")
        .description("Opens the composer from Control Center.")
    }
}

/// The READING half of the same pair (2026-08-14). Capture had a button
/// anywhere on the device and the brief — the app's one composed answer to
/// "what's going on" — could only be reached by opening the app and tapping.
///
/// It reuses `"brief.request"`, the flag the Home Screen quick action already
/// writes and `RootShell.openBriefIfRequested` already reads (§377). One door,
/// so a second entrance can't drift into a second behaviour — and notably that
/// door is the one whose delivery half was broken for eleven days, which is
/// another reason not to invent a third.
struct OpenBriefIntent: AppIntent {
    static let title: LocalizedStringResource = "What's going on"
    static let description = IntentDescription("Opens Casberi's daily brief.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedStore.appGroup)?
            .set(true, forKey: "brief.request")
        return .result()
    }
}

struct BriefControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "casberi.brief") {
            ControlWidgetButton(action: OpenBriefIntent()) {
                Label("What's going on", systemImage: "sparkles")
            }
        }
        .displayName("Casberi brief")
        .description("Opens your day from Control Center.")
    }
}

struct HeroEntry: TimelineEntry {
    let date: Date
    let eyebrow: String
    let title: String
    let subline: String
    /// Something landed since the app was last open — a plain accent dot
    /// (delight 2026-07-13, amended 2026-07-25). It used to be a COUNT in a
    /// ring ("47"), which §213 retired everywhere else in the product: volume
    /// is not news. Presence still is — "there's something in there" is a true
    /// and useful thing for a home-screen tile to say — so the dot stayed and
    /// the number went.
    var hasNew: Bool = false

    /// What the Smart Stack sorts on (prd §282, 2026-08-02). A stacked widget
    /// only surfaces itself if it says how much it currently deserves the slot,
    /// and this one never did — so it rotated on nothing but position, showing
    /// the day's lede at 3am and hiding it at 8am when the brief is the whole
    /// point.
    ///
    /// Three rungs, in the order the tile's own content already ranks by:
    /// something landed while you were away (the news case), the brief has
    /// published a lede (the morning case), or the tile is merely showing the
    /// newest thing (which is true all day and worth no promotion).
    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: hasNew ? 90 : (isLede ? 55 : 10))
    }

    /// Whether the title is the brief's own sentence rather than the fallback
    /// rungs — set by the provider, since only it knows which rung answered.
    var isLede: Bool = false

    /// The month-wide theme cells (2026-08-03), largest first, capped at 3.
    ///
    /// DEMOTED to the last fallback (2026-08-14, prd §382 amendment). It held
    /// this slot unconditionally and was the weakest thing the brief draws —
    /// three abstract boxes carrying three WORDS, which you must read before
    /// they tell you anything. `lead` outranks it now; this speaks only on a day
    /// that earned none of the better leads, which a 30-day clustering still can.
    var themes: [WidgetThemeCell] = []

    /// What the day earned as its lead — pictures, money, or the source mix.
    /// See `WidgetDayLead`.
    var lead: WidgetDayLead?
    /// The day's own thumbnails, fetched from the shared store rather than
    /// published (the extension is already reading it). Empty unless
    /// `lead?.kind == .pictures`.
    var shots: [Data] = []
    /// The wallet line, for the money lead — the SAME one the wallet tile
    /// draws, so the two can never disagree about the same wallet.
    var wallet: WidgetWalletLine?

    /// The most recent things, newest first, fetched independently of which
    /// rung answered `title`/`subline` above — the medium widget's treemap
    /// layout pins the first as its own footer row even when the lede answered,
    /// so it can't just reuse `title` the way the non-lede rungs do.
    ///
    /// A LIST since 2026-08-14, where it used to be one title/source pair: the
    /// large family shows three, and each one opens the thing itself rather
    /// than dropping you at the feed to go find what you were just looking at.
    var recents: [WidgetRecentItem] = []

    var recentTitle: String { recents.first?.title ?? "" }
    var recentSource: String { recents.first?.source ?? "" }

    /// Whether a lead can actually be DRAWN — not merely whether one was
    /// published. A pictures lead whose thumbnails all failed to load, or a
    /// money lead whose line aged out of its own freshness window, is a frame
    /// with nothing in it, and the tile falls through to the older layouts
    /// instead. The two checks are separate on purpose: the app decides WHICH
    /// lead the day earned, the widget decides whether it has what that lead
    /// needs.
    var hasLead: Bool {
        switch lead?.kind {
        case .pictures: return !shots.isEmpty
        case .money:    return wallet != nil
        case .posts:    return !(lead?.postsLine ?? "").isEmpty
        case .sources:  return (lead?.sources.count ?? 0) >= WidgetDayLead.sourceFloor
        default:        return false
        }
    }
}

/// One landed thing, as a widget row. `id` is the `Thing`'s own UUID string, so
/// a row can carry a `casberi://thing/<id>` link.
struct WidgetRecentItem: Identifiable {
    let id: String
    let title: String
    let source: String
    let capturedAt: Date
}

struct HeroProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeroEntry {
        HeroEntry(date: .now, eyebrow: "",
                  title: String(localized: "Your things, one place"),
                  subline: "Casberi")
    }

    func getSnapshot(in context: Context, completion: @escaping (HeroEntry) -> Void) {
        completion(compose())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeroEntry>) -> Void) {
        let entry = compose()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// The widget says what the BRIEF says (2026-07-25). It used to compose
    /// its own line — the largest tag cluster and how many things were in it
    /// ("Recipes fills your week · 12 things across 3 apps"). That is a tally,
    /// and §213 ruled tallies out of the product: people receive dozens of
    /// things a day and care WHAT landed, not how many. The brief already
    /// ranks the day into one sentence (risk → money → a person → a deadline),
    /// so this mirrors that sentence rather than inventing a weaker one.
    ///
    /// Three rungs, each a real fact, and it falls to the next only when the
    /// one above has nothing to say:
    ///   1. the brief's published lede,
    ///   2. the most recent THING itself — the module doctrine's own second
    ///      shape, and never a count of them,
    ///   3. the empty-corpus invitation.
    ///
    /// The medium widget's theme cells (2026-08-03) ride alongside whichever
    /// rung answers rather than being a fourth rung of their own — an
    /// unlabeled area, mirroring the brief's own themes card, not a tally.
    private func compose() -> HeroEntry {
        let group = UserDefaults(suiteName: SharedStore.appGroup)

        // Something landed while the app was closed? The app stamps this
        // boundary on background. Presence only — never how much (§213).
        let lastSeen = group?.double(forKey: "widget.lastSeen") ?? 0
        let themes = WidgetLede.themes(defaults: group) ?? []

        // Fetched unconditionally now (2026-08-03), not just on the rung-2
        // fallback path: the medium widget's treemap layout pins the newest
        // thing as its own footer row even when rung 1 (the lede) answers
        // the headline, so both need it in hand at once. Three bounded rows
        // since 2026-08-14 (the large family lists them) — the extension's
        // ~30MB budget hasn't moved, and three is still one page of one index.
        let recents = recentThings(limit: 3)
        let recent = recents.first

        // What the day earned as its lead (2026-08-14) — decided by the APP,
        // in `WidgetDayLead.kind`, because the widget computes nothing. The
        // thumbnails are the one thing fetched rather than published: the
        // extension is already reading this store, and eight JPEGs written into
        // UserDefaults on every foreground to save a read it is already making
        // would be the worse half of both worlds.
        let lead = WidgetLede.lead(defaults: group)
        let shots = lead?.kind == .pictures ? todayShots(limit: 8) : []
        let wallet = lead?.kind == .money ? WidgetWallet.published(defaults: group) : nil

        // ── 1. The brief's own sentence ──────────────────────────────
        if let lede = WidgetLede.current(defaults: group) {
            // No eyebrow above the lede: the sentence is already the whole
            // headline, and "This week" over "One overdue, six more due by
            // Aug 25" would date a line that isn't about this week.
            return HeroEntry(date: .now, eyebrow: "", title: lede,
                             subline: "What's going on",
                             hasNew: hasNew(since: lastSeen),
                             isLede: true, themes: themes,
                             lead: lead, shots: shots, wallet: wallet,
                             recents: recents)
        }

        // ── 2. The most recent thing, as itself ──────────────────────
        if let newest = recent {
            return HeroEntry(date: .now, eyebrow: "",
                             title: newest.title,
                             subline: newest.source,
                             hasNew: newest.capturedAt.timeIntervalSince1970 > lastSeen
                                     && lastSeen > 0,
                             themes: themes,
                             lead: lead, shots: shots, wallet: wallet,
                             recents: recents)
        }

        // ── 3. Nothing yet ───────────────────────────────────────────
        return HeroEntry(date: .now, eyebrow: "",
                         title: String(localized: "Your things go here"),
                         subline: String(localized: "Save one in Casberi"))
    }

    /// A few bounded rows — the extension's ~30MB budget hasn't got room for
    /// more (2026-07-21 audit). Shared by the lede rung (which needs the first
    /// for the medium widget's footer row), the plain rung-2 fallback, and the
    /// large family's list.
    ///
    /// The values are copied out of the models IMMEDIATELY and nothing but
    /// `WidgetRecentItem`s leave this function. That is the liveness rule the
    /// app side spends six corollaries on, and it costs nothing to keep here:
    /// a `Thing` handed up into a `TimelineEntry` would be a model reference
    /// held across the entry's whole life in another process's context.
    private func recentThings(limit: Int) -> [WidgetRecentItem] {
        guard let container = try? SharedStore.extensionContainer() else { return [] }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.propertiesToFetch = [\.id, \.title, \.source, \.capturedAt]
        descriptor.fetchLimit = limit
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows.map { WidgetRecentItem(id: $0.id.uuidString, title: $0.title,
                                           source: $0.source, capturedAt: $0.capturedAt) }
    }

    /// The day's own thumbnails, for the contact-sheet lead.
    ///
    /// Bounded TWICE and both bounds matter in a ~30MB extension:
    /// `previewImageData` is external storage, so each one materializes real
    /// bytes off disk when it is touched — the loop stops the moment it has
    /// enough rather than mapping the whole fetch, and the fetch itself scans a
    /// short window rather than the day. A day with three hundred screenshots
    /// costs exactly what a day with eight does.
    private func todayShots(limit: Int) -> [Data] {
        guard let container = try? SharedStore.extensionContainer() else { return [] }
        let dayStart = Calendar.current.startOfDay(for: .now)
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.capturedAt >= dayStart },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 24
        guard let rows = try? ModelContext(container).fetch(descriptor) else { return [] }
        var out: [Data] = []
        for row in rows {
            guard let data = row.previewImageData else { continue }
            out.append(data)
            if out.count == limit { break }
        }
        return out
    }

    /// Whether anything at all landed since the app went to background — one
    /// bounded fetch, not a count of the corpus.
    private func hasNew(since lastSeen: TimeInterval) -> Bool {
        guard lastSeen > 0, let container = try? SharedStore.extensionContainer() else {
            return false
        }
        let boundary = Date(timeIntervalSince1970: lastSeen)
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate { $0.capturedAt > boundary }
        )
        descriptor.propertiesToFetch = [\.capturedAt]
        descriptor.fetchLimit = 1
        return ((try? ModelContext(container).fetch(descriptor))?.isEmpty == false)
    }
}

struct HeroWidget: Widget {
    var body: some WidgetConfiguration {
        // The kind string is shared with the app's reload call — one name, so
        // a rename can't leave the widget listening on a channel nobody writes.
        StaticConfiguration(kind: WidgetLede.kind, provider: HeroProvider()) { entry in
            HeroWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        // Named for what it now shows (§193 renamed the brief "What's going
        // on"); the old "Synthesis" described the tag-cluster line that's gone.
        .configurationDisplayName("What's going on")
        .description("Your day in one line.")
        // Large joined the set 2026-08-14. It is not the medium tile with more
        // air: it is the only family with room for the sentence AND the themes
        // AND what actually landed, which is the brief's own shape — so it is
        // the first widget in this app that answers "what's going on" without
        // making you choose which half of the answer you wanted.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryInline])
    }
}


struct HeroWidgetView: View {
    let entry: HeroEntry
    @Environment(\.widgetFamily) private var family

    /// The app accent — one definition, shared with the field behind it
    /// (`WidgetChrome.accent`), so the dot and the pour can't name two colours.
    private var accent: Color { WidgetChrome.accent }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                // One line on the lock screen / StandBy — the title is the line.
                Text(entry.title)
            case .accessoryRectangular:
                // Sentence case, never ALL-CAPS: the eyebrow used to be
                // `.uppercased()` here, which the 2026-07-08 ruling banned with
                // no exceptions ("headers are words in sentence case"). It
                // predated the ruling and nobody had looked at the widget
                // since. The type ramp carries the hierarchy on its own.
                //
                // The lede rung emits no eyebrow at all — the sentence IS the
                // headline — so the row is dropped rather than left as an
                // empty line eating one of three scarce lock-screen lines.
                VStack(alignment: .leading, spacing: 1) {
                    if !entry.eyebrow.isEmpty {
                        Text(entry.eyebrow)
                            .dsText(.widgetEyebrow11)
                            .widgetAccentable()
                    }
                    Text(entry.title)
                        .dsText(.widgetTitle14)
                        .lineLimit(entry.eyebrow.isEmpty ? 3 : 2)
                    Text(entry.subline)
                        .dsText(.widgetSubline11)
                        .opacity(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemLarge:
                LargeHeroBody(entry: entry, accent: accent)
            case .systemMedium where entry.hasLead:
                // The day's own lead (2026-08-14) — pictures, money, or the
                // source mix — above the newest thing. The sentence steps
                // aside at this size for §248's original reason: there isn't
                // room for a headline AND a visualization AND a footer row,
                // and the visualization IS an answer to "what's going on"
                // rather than a second unrelated fact competing with one.
                VStack(alignment: .leading, spacing: 8) {
                    HeroLead(entry: entry, accent: accent)
                        .frame(height: 96)
                    RecentItemRow(title: entry.recentTitle, source: entry.recentSource)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .topTrailing) {
                    if entry.hasNew {
                        Circle().fill(accent).frame(width: 9, height: 9)
                            .accessibilityLabel(Text("Something new"))
                    }
                }
            case .systemMedium where !entry.themes.isEmpty:
                // Themes + the newest thing (2026-08-03) — the sentence lede
                // steps aside here; there isn't room for a headline, a
                // 3-cell map, AND a footer row, and the map is itself an
                // answer to "what's going on" (§213's own themes card
                // reasoning), not a second unrelated fact competing with one.
                VStack(alignment: .leading, spacing: 8) {
                    ThemesTreemap(cells: entry.themes, accent: accent)
                    RecentItemRow(title: entry.recentTitle, source: entry.recentSource)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .topTrailing) {
                    if entry.hasNew {
                        Circle()
                            .fill(accent)
                            .frame(width: 9, height: 9)
                            .accessibilityLabel(Text("Something new"))
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    if !entry.eyebrow.isEmpty {
                        Text(entry.eyebrow)
                            .dsText(.label11)
                            .foregroundStyle(accent)
                    }
                    Text(entry.title)
                        .dsText(.widgetTitle17)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text(entry.subline)
                        .dsText(.widgetSubline12)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Something landed since you left — an accent dot, never a red
                // badge and (since §213) never a number. The count that used
                // to sit in this ring was the same "14 things landed" claim the
                // brief itself stopped making: in a corpus taking dozens a day
                // it says nothing except that the app is on. Presence is the
                // part that was ever true, so presence is what's left.
                .overlay(alignment: .topTrailing) {
                    if entry.hasNew {
                        Circle()
                            .fill(accent)
                            .frame(width: 9, height: 9)
                            .accessibilityLabel(Text("Something new"))
                    }
                }
            }
        }
        // Lands on the brief itself — the sentence this tile is showing,
        // opened — rather than the feed. A headline you can't open is the
        // dead control the honesty rule forbids.
        .widgetURL(URL(string: "casberi://brief"))
    }
}

/// The large family (2026-08-14, prd §382) — the brief's own shape on a Home
/// Screen: the sentence, the month's themes, and what actually landed.
///
/// WHY THIS ISN'T THE MEDIUM TILE WITH MORE AIR. The medium family has to
/// choose: §248's own reasoning put the themes map there INSTEAD of the lede,
/// because there is no room for a headline, a map and a footer row at that
/// size. That choice was always a compromise, and the large family is the one
/// place it doesn't have to be made — so this shows both, in the order the
/// brief itself ranks them, and then the rows the map is made of.
///
/// THREE TAP TARGETS, each landing where it says. The tile's own `widgetURL`
/// opens the brief; each landed row opens THAT THING (`casberi://thing/<id>`)
/// rather than dumping you in the feed to find again what you were just
/// reading; the button opens the composer. A row that showed you something and
/// then couldn't open it is the dead control the honesty rule forbids, and at
/// this size there is finally room to make each one real.
private struct LargeHeroBody: View {
    let entry: HeroEntry
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.title)
                .dsText(.widgetHeadline20)
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            // The day's lead, or the 30-day themes when it earned none.
            if entry.hasLead {
                HeroLead(entry: entry, accent: accent, pictureRows: 2)
                    .frame(height: entry.lead?.kind == .pictures ? 150 : 92)
            } else if !entry.themes.isEmpty {
                ThemesTreemap(cells: entry.themes, accent: accent)
                    .frame(height: 92)
            }

            if !entry.recents.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    WidgetLabel(text: String(localized: "Landed"))
                    // Deliberately not `.keyed`-style liveness gymnastics: these
                    // are plain value copies made in the provider, never model
                    // references (see `recentThings`), so there is nothing here
                    // that can be deleted underneath the view.
                    ForEach(entry.recents) { item in
                        Link(destination: URL(string: "casberi://thing/\(item.id)")!) {
                            RecentItemRow(title: item.title, source: item.source)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Button(intent: OpenComposerIntent()) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .dsGlyph(11)
                    Text("Save a thing")
                        .dsText(.widgetSubline12)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.14),
                            in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if entry.hasNew {
                Circle()
                    .fill(accent)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel(Text("Something new"))
            }
        }
    }
}

/// Up to 3 theme cells, largest first — a fixed two-column layout rather than
/// a general treemap algorithm, since the medium widget caps at exactly 3
/// cells (a 4th reads as clutter at this size, mockup 2026-08-03). Area is
/// the only magnitude signal a cell carries; none ever prints its weight as a
/// number (§213 — see `WidgetThemeCell`'s own header).
private struct ThemesTreemap: View {
    let cells: [WidgetThemeCell]
    let accent: Color

    var body: some View {
        HStack(spacing: 3) {
            if let lead = cells.first {
                cell(lead, fill: AnyShapeStyle(LinearGradient(
                    colors: [accent, accent.opacity(0.72)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            let rest = cells.dropFirst().prefix(2)
            if !rest.isEmpty {
                VStack(spacing: 3) {
                    ForEach(Array(rest), id: \.name) { c in
                        cell(c, fill: AnyShapeStyle(Color.white.opacity(0.12)))
                    }
                }
                .frame(width: 100)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func cell(_ c: WidgetThemeCell, fill: AnyShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(c.name)
                .dsText(.widgetTreemapTerm12)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.bottom, 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(fill)
    }
}

/// The newest thing, pinned as the medium widget's footer row under the
/// treemap — same fact the small widget's rung-2 fallback shows, just
/// alongside the map instead of alone.
private struct RecentItemRow: View {
    let title: String
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .dsText(.widgetRecentTitle12)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(source)
                .dsText(.widgetSubline11)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }
}
