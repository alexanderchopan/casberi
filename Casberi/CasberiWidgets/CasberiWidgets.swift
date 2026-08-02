import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// The hero widget — one synthesis line on the home screen (P8: awareness
/// lands; the corpus speaks without being asked). Reads the shared store
/// through the app group; tapping opens Home via the deep link.
@main
struct CasberiWidgets: WidgetBundle {
    var body: some Widget {
        HeroWidget()
        ComposeControl()
        #if !targetEnvironment(macCatalyst)
        VoiceRecordingActivity()
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
                    .font(.system(size: 20, weight: .medium))
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
                    .font(.system(size: 24))
                    .foregroundStyle(.red)
            }
            .padding(14)
            .activityBackgroundTint(.black.opacity(0.8))
            .widgetURL(URL(string: "casberi://home"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .medium))
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
    private func compose() -> HeroEntry {
        let group = UserDefaults(suiteName: SharedStore.appGroup)

        // Something landed while the app was closed? The app stamps this
        // boundary on background. Presence only — never how much (§213).
        let lastSeen = group?.double(forKey: "widget.lastSeen") ?? 0

        // ── 1. The brief's own sentence ──────────────────────────────
        if let lede = WidgetLede.current(defaults: group) {
            // No eyebrow above the lede: the sentence is already the whole
            // headline, and "This week" over "ETH has done the lifting seven
            // days running" would date a line that isn't about this week.
            return HeroEntry(date: .now, eyebrow: "", title: lede,
                             subline: "What's going on",
                             hasNew: hasNew(since: lastSeen),
                             isLede: true)
        }

        guard let container = try? SharedStore.extensionContainer() else {
            return HeroEntry(date: .now, eyebrow: "",
                             title: String(localized: "Your things, one place"),
                             subline: "Casberi")
        }
        let context = ModelContext(container)
        // The extension runs in a tight (~30MB) budget — an unbounded fetch
        // hydrated every Thing, inline strings and all (2026-07-21 audit).
        // Now that the tag histogram is gone this needs exactly ONE row, so
        // the fetch is limited to it instead of walking the whole corpus.
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.propertiesToFetch = [\.title, \.source, \.capturedAt]
        descriptor.fetchLimit = 1

        // ── 2. The most recent thing, as itself ──────────────────────
        if let newest = (try? context.fetch(descriptor))?.first {
            return HeroEntry(date: .now, eyebrow: "",
                             title: newest.title,
                             subline: newest.source,
                             hasNew: newest.capturedAt.timeIntervalSince1970 > lastSeen
                                     && lastSeen > 0)
        }

        // ── 3. Nothing yet ───────────────────────────────────────────
        return HeroEntry(date: .now, eyebrow: "",
                         title: String(localized: "Your things go here"),
                         subline: String(localized: "Save one in Casberi"))
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
                .containerBackground(.black, for: .widget)
        }
        // Named for what it now shows (§193 renamed the brief "What's going
        // on"); the old "Synthesis" described the tag-cluster line that's gone.
        .configurationDisplayName("What's going on")
        .description("Your day in one line.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryInline])
    }
}

struct HeroWidgetView: View {
    let entry: HeroEntry
    @Environment(\.widgetFamily) private var family

    /// The app accent, carried across the app group (falls back to Casberi
    /// blue before the app has ever written it).
    private var accent: Color {
        let hex = UserDefaults(suiteName: SharedStore.appGroup)?
            .string(forKey: "theme.tint.hex") ?? "#1673e6"
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        return Color(red: Double((value >> 16) & 0xff) / 255,
                     green: Double((value >> 8) & 0xff) / 255,
                     blue: Double(value & 0xff) / 255)
    }

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
