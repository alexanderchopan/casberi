import WidgetKit
import SwiftUI
import AppIntents

/// One category's newest things, on the Home Screen (2026-10-04). You pick the
/// category when you add the tile — Notes unless you choose another — and it
/// lists that category's newest rows, as published by `WidgetPublish.shelves`.
///
/// The picker's choices are the shelves the app published, read back from the
/// app group, so the list is never longer than what the app has written: a
/// category with nothing in it is not offered, and Notes always is.
struct CategoryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetShelves.kind, intent: PickCategoryIntent.self,
                               provider: CategoryProvider()) { entry in
            CategoryWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("Category")
        .description("The newest things in one category. Notes unless you pick another.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - The pick

struct CategoryEntity: AppEntity {
    /// The room the shelf opens: a category's name, or Notes' room.
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static let notes = CategoryEntity(id: WidgetShelves.notesRoom, name: String(localized: "Notes"))
}

struct CategoryQuery: EntityQuery {
    /// What the app last published, Notes first. Before the app has ever
    /// published, Notes alone — the default, so the tile always has a pick.
    private func published() -> [CategoryEntity] {
        let shelves = WidgetShelves.published().map { CategoryEntity(id: $0.room, name: $0.name) }
        return shelves.isEmpty ? [.notes] : shelves
    }

    func entities(for identifiers: [CategoryEntity.ID]) async throws -> [CategoryEntity] {
        let all = published()
        // A pick whose category has since emptied keeps its name, so the tile
        // says "nothing yet" under it rather than losing the choice.
        return identifiers.map { id in all.first { $0.id == id } ?? CategoryEntity(id: id, name: id) }
    }

    func suggestedEntities() async throws -> [CategoryEntity] { published() }

    func defaultResult() async -> CategoryEntity? { .notes }
}

struct PickCategoryIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Category"
    static let description = IntentDescription("Choose which category the widget shows.")

    @Parameter(title: "Category")
    var category: CategoryEntity?
}

// MARK: - Timeline

struct CategoryEntry: TimelineEntry {
    let date: Date
    let room: String
    let name: String
    /// nil when the app has published nothing for this pick (yet, or for a week).
    let shelf: WidgetShelf?
}

struct CategoryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CategoryEntry {
        CategoryEntry(date: .now, room: WidgetShelves.notesRoom,
                      name: String(localized: "Notes"), shelf: nil)
    }

    func snapshot(for configuration: PickCategoryIntent, in context: Context) async -> CategoryEntry {
        entry(for: configuration, now: .now)
    }

    func timeline(for configuration: PickCategoryIntent, in context: Context) async -> Timeline<CategoryEntry> {
        // The app reloads this kind whenever a shelf changes; the timeline
        // asks again in a few hours only so a week-old shelf retires on time.
        let now = Date.now
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now
        return Timeline(entries: [entry(for: configuration, now: now)], policy: .after(next))
    }

    private func entry(for configuration: PickCategoryIntent, now: Date) -> CategoryEntry {
        let pick = configuration.category ?? .notes
        let shelf = WidgetShelves.published(now: now).first { $0.room == pick.id }
        return CategoryEntry(date: now, room: pick.id, name: shelf?.name ?? pick.name, shelf: shelf)
    }
}

// MARK: - The tile

struct CategoryWidgetView: View {
    let entry: CategoryEntry
    @Environment(\.widgetFamily) private var family

    private var rows: [WidgetShelf.Row] {
        let all = entry.shelf?.rows ?? []
        switch family {
        case .systemSmall: return Array(all.prefix(2))
        case .systemMedium: return Array(all.prefix(3))
        case .accessoryRectangular: return Array(all.prefix(1))
        default: return all
        }
    }

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name).dsText(.widgetSubline11).opacity(0.75).lineLimit(1)
                    Text(rows.first?.title ?? emptyLine)
                        .dsText(.widgetTitle14)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
                    HStack(spacing: 5) {
                        if let glyph = entry.shelf?.glyph {
                            Image(systemName: glyph)
                                .dsGlyph(.caption, weight: .semibold)
                                .foregroundStyle(WidgetChrome.header)
                                .widgetAccentable()
                        }
                        Text(entry.name)
                            .dsText(.widgetEyebrow11)
                            .foregroundStyle(WidgetChrome.header)
                            .lineLimit(1)
                            .widgetAccentable()
                    }
                    if rows.isEmpty {
                        Text(emptyLine)
                            .dsText(.widgetSubline12)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } else {
                        ForEach(rows, id: \.id) { row in
                            rowView(row)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .widgetURL(roomURL)
    }

    /// A row opens its thing on the families that can take a tap per row; the
    /// small tile is one tap, and it opens the category.
    @ViewBuilder
    private func rowView(_ row: WidgetShelf.Row) -> some View {
        let body = VStack(alignment: .leading, spacing: 1) {
            Text(row.title)
                .dsText(.widgetTitle14)
                .foregroundStyle(.primary)
                .lineLimit(family == .systemSmall ? 2 : 1)
            Text(subline(row))
                .dsText(.widgetSubline11)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if family != .systemSmall, let url = URL(string: "casberi://thing/\(row.id)") {
            Link(destination: url) { body }
        } else {
            body
        }
    }

    /// "GitHub · 2h ago". Notes are all yours, so a note says only when.
    private func subline(_ row: WidgetShelf.Row) -> String {
        // Never "in 9 hr.": a thing dated ahead of the clock says now.
        let when = min(row.at, entry.date).formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        guard entry.room != WidgetShelves.notesRoom else { return when }
        return "\(row.source) · \(when)"
    }

    private var emptyLine: String {
        entry.room == WidgetShelves.notesRoom
            ? String(localized: "Write a note in Casberi")
            : String(localized: "Nothing here yet")
    }

    private var roomURL: URL? {
        var parts = URLComponents()
        parts.scheme = "casberi"
        parts.host = "room"
        parts.path = "/" + entry.room
        return parts.url
    }
}
