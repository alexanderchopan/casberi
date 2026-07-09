import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
import ActivityKit

/// The hero widget — one synthesis line on the home screen (P8: awareness
/// lands; the corpus speaks without being asked). Reads the shared store
/// through the app group; tapping opens Home via the deep link.
@main
struct CasberiWidgets: WidgetBundle {
    var body: some Widget {
        HeroWidget()
        ComposeControl()
        VoiceRecordingActivity()
    }
}

/// While a voice note records, the lock screen and Dynamic Island show the
/// recording state — waveform, elapsed time — and tapping returns to the
/// composer. Recording state only; the words stay in the app (goal 6).
struct VoiceRecordingActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceRecordingAttributes.self) { context in
            // Lock screen band.
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.red)
                Text("Recording")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(timerInterval: context.state.startedAt...Date(
                    timeInterval: 60 * 60, since: context.state.startedAt))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
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
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .frame(maxWidth: 60)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Recording")
                        .font(.system(size: 15, weight: .semibold))
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date(
                    timeInterval: 60 * 60, since: context.state.startedAt))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
            }
            .widgetURL(URL(string: "casberi://home"))
        }
    }
}

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
}

struct HeroProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeroEntry {
        HeroEntry(date: .now, eyebrow: "This week",
                  title: "Your things, one place",
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

    /// The hero rule, in miniature: the largest moving cluster leads.
    private func compose() -> HeroEntry {
        guard let container = try? SharedStore.extensionContainer() else {
            return HeroEntry(date: .now, eyebrow: "This week",
                             title: "Your things, one place", subline: "Casberi")
        }
        let context = ModelContext(container)
        let things = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
        guard !things.isEmpty else {
            return HeroEntry(date: .now, eyebrow: "Now",
                             title: "Your things go here",
                             subline: "Save one in Casberi")
        }

        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        var buckets: [String: Int] = [:]
        for thing in things {
            for tag in thing.tags where !typeTags.contains(tag) {
                buckets[tag, default: 0] += 1
            }
        }
        let top = buckets.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }.first

        if let top, top.value >= 2 {
            let sources = Set(things.filter { $0.tags.contains(top.key) }.map(\.source)).count
            return HeroEntry(date: .now, eyebrow: "This week",
                             title: "\(top.key) fills your week",
                             subline: "\(top.value) things across \(sources) app\(sources == 1 ? "" : "s")")
        }
        let count = things.count
        return HeroEntry(date: .now, eyebrow: "Now",
                         title: "Your things are landing",
                         subline: count == 1 ? "1 thing so far" : "\(count) things so far")
    }
}

struct HeroWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "casberi.hero", provider: HeroProvider()) { entry in
            HeroWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Synthesis")
        .description("One line about what your things are up to.")
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.eyebrow.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .widgetAccentable()
                    Text(entry.title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(2)
                    Text(entry.subline)
                        .font(.system(size: 11))
                        .opacity(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.eyebrow)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accent)
                    Text(entry.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text(entry.subline)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .widgetURL(URL(string: "casberi://home"))
    }
}
