import WidgetKit
import SwiftUI
import AppIntents

/// YOUR standing question, on the Home Screen (2026-08-14, prd §382).
///
/// This is the widget the product was already shaped for and never had. Kept
/// asks are the agent's own surface — the standing questions someone chose to
/// keep, answered DETERMINISTICALLY on every foreground (`KeptAskComposers`,
/// never the model), each carrying a one-line reading its own composer wrote.
/// Until now that reading existed only inside a pill you had to open the app,
/// raise the agent and look at.
///
/// So the tile computes nothing: it draws `KeptAskStore`'s own `currentDeltas`,
/// published by `WidgetPublish`. Which means a reading here can never disagree
/// with the reading on the pill, because there is only one of them.
///
/// CONFIGURABLE, and configured BY KIND. The picker stores `WidgetAskCell.kind`
/// (`away`, `wallet`, `showtag:Recipes`) and never the title, for the same
/// reason `KeptAskStore` keys everything that way: re-wording a question must
/// not orphan a tile somebody placed on their Home Screen.
struct KeptAskWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetAsks.kind,
                               intent: KeptAskConfiguration.self,
                               provider: KeptAskProvider()) { entry in
            KeptAskWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("A kept question")
        .description("One of your standing questions, answered.")
        // No large family: one question with one reading cannot fill it, and a
        // tile that is mostly empty space reads as a tile that failed to load.
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Configuration

/// One kept question, as something the widget's picker can list.
struct KeptAskEntity: AppEntity {
    /// The kind string. See the widget's own note on why this and not the title.
    let id: String
    let title: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Kept question")
    }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
    static var defaultQuery = KeptAskQuery()
}

/// What the picker offers: exactly the questions the app has published.
///
/// `entities(for:)` deliberately answers for an id it can NO LONGER FIND, with
/// the kind standing in as the title. Returning `[]` there would make iOS treat
/// the configuration as invalid and quietly reset the tile to some other
/// question — so a question you removed in the app would be replaced on your
/// Home Screen by a different one you didn't choose. Keeping the entity alive
/// lets the tile say plainly that this question is no longer kept, which is the
/// honest outcome and the one you can act on.
struct KeptAskQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [KeptAskEntity] {
        let published = WidgetAsks.published()
        return identifiers.map { id in
            KeptAskEntity(id: id,
                          title: published.first { $0.kind == id }?.title ?? id)
        }
    }

    func suggestedEntities() async throws -> [KeptAskEntity] {
        WidgetAsks.published().map { KeptAskEntity(id: $0.kind, title: $0.title) }
    }

    /// Placing the tile without configuring it shows the most recently kept
    /// question rather than nothing — the same order the composer's own pill
    /// row uses, so the default is the one you'd have picked.
    func defaultResult() async -> KeptAskEntity? {
        WidgetAsks.published().first.map { KeptAskEntity(id: $0.kind, title: $0.title) }
    }
}

struct KeptAskConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Kept question"
    static var description = IntentDescription("Pick which standing question this widget answers.")

    @Parameter(title: "Question")
    var ask: KeptAskEntity?
}

// MARK: - Timeline

struct KeptAskEntry: TimelineEntry {
    let date: Date
    let title: String
    /// The composer's own one-line answer, or nil — which happens for two very
    /// different reasons the view must not conflate: it hasn't been computed
    /// yet, or it aged out of `WidgetAsks.readingWindow`. Either way the
    /// question stands alone; see `WidgetPayload`'s header.
    let reading: String?
    let changed: Bool
    /// The configured question is no longer kept in the app.
    let removed: Bool
    /// Nothing has ever been kept, so there is nothing to configure.
    let empty: Bool

    /// A changed answer is worth surfacing in a Smart Stack; a steady one is
    /// true all day and worth no promotion. Same three-rung reasoning as the
    /// hero's (§282), one signal shorter because a kept ask has no "lede".
    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: changed ? 80 : 20)
    }
}

struct KeptAskProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> KeptAskEntry {
        KeptAskEntry(date: .now, title: String(localized: "What's new?"),
                     reading: nil, changed: false, removed: false, empty: false)
    }

    func snapshot(for configuration: KeptAskConfiguration, in context: Context) async -> KeptAskEntry {
        compose(configuration)
    }

    func timeline(for configuration: KeptAskConfiguration, in context: Context) async -> Timeline<KeptAskEntry> {
        // Refresh on the hour. The app republishes and reloads this kind itself
        // whenever a reading actually changes (`WidgetPublish.publishAll`), so
        // this is only the floor that keeps a reading from outliving its own
        // freshness window while the app goes unopened.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [compose(configuration)], policy: .after(next))
    }

    private func compose(_ configuration: KeptAskConfiguration) -> KeptAskEntry {
        let published = WidgetAsks.published()
        guard !published.isEmpty else {
            return KeptAskEntry(date: .now, title: String(localized: "Keep a question"),
                                reading: nil, changed: false, removed: false, empty: true)
        }
        // An unconfigured tile follows the newest kept question rather than
        // pinning whichever one happened to be first the day it was placed.
        guard let wanted = configuration.ask?.id else {
            let first = published[0]
            return KeptAskEntry(date: .now, title: first.title, reading: first.reading,
                                changed: first.changed, removed: false, empty: false)
        }
        guard let cell = published.first(where: { $0.kind == wanted }) else {
            return KeptAskEntry(date: .now,
                                title: configuration.ask?.title ?? wanted,
                                reading: nil, changed: false, removed: true, empty: false)
        }
        return KeptAskEntry(date: .now, title: cell.title, reading: cell.reading,
                            changed: cell.changed, removed: false, empty: false)
    }
}

// MARK: - View

struct KeptAskWidgetView: View {
    let entry: KeptAskEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { WidgetChrome.accent }

    /// Where the tile lands. The question's own text, handed to the composer —
    /// which is byte-for-byte what tapping the kept pill in the app does
    /// (`draft = title; commit()`). One door, so a widget can never open an
    /// answer the app itself wouldn't produce.
    private var destination: URL? {
        guard !entry.empty, !entry.removed,
              let url = WidgetAskLink.url(asking: entry.title)
        else { return URL(string: "casberi://home") }
        return url
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .dsText(.widgetTitle14)
                        .lineLimit(entry.reading == nil ? 3 : 2)
                    if let reading = entry.reading {
                        Text(reading)
                            .dsText(.widgetSubline11)
                            .opacity(0.75)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    WidgetLabel(text: String(localized: "You asked"))
                    Text(entry.title)
                        .dsText(.widgetTitle17)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    answerLine
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .topTrailing) {
                    // The same presence dot the pill wears when an answer moved
                    // — never a count of what moved (§213).
                    if entry.changed {
                        Circle().fill(accent).frame(width: 9, height: 9)
                            .accessibilityLabel(Text("Answer changed"))
                    }
                }
            }
        }
        .widgetURL(destination)
    }

    /// The bottom line, and the four things it can honestly say.
    ///
    /// Each state is a DIFFERENT sentence on purpose. Collapsing "no answer
    /// yet" and "this question is gone" into one blank line is how a tile ends
    /// up looking merely quiet when it is actually pointing at something that
    /// no longer exists.
    @ViewBuilder
    private var answerLine: some View {
        if entry.empty {
            Text("Keep a question in Casberi and it appears here.")
                .dsText(.widgetSubline12)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(3)
        } else if entry.removed {
            Text("No longer kept")
                .dsText(.widgetSubline12)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        } else if let reading = entry.reading {
            Text(reading)
                .dsText(.widgetSubline12)
                .foregroundStyle(accent)
                .lineLimit(2)
                .widgetAccentable()
        } else {
            // Deliberately not "—" or an empty line: the question is still a
            // real standing question, and the app simply hasn't answered it
            // recently enough for the number to be worth printing.
            Text("Open to answer")
                .dsText(.widgetSubline12)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
    }
}
