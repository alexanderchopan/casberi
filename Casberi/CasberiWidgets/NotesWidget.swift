import WidgetKit
import SwiftUI

/// Your two newest notes, on the Home Screen (prd §1210). A small tile only:
/// one tap, and it opens Notes.
///
/// It draws `WidgetNotes.published()`, which the app writes on every
/// foreground (`WidgetPublish.notes`). Past a week the shelf ages out and the
/// tile asks you to write one rather than listing what was newest a week ago.
struct NotesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetNotes.kind, provider: NotesProvider()) { entry in
            NotesWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("Notes")
        .description("Your newest notes.")
        .supportedFamilies([.systemSmall])
    }
}

struct NotesEntry: TimelineEntry {
    let date: Date
    /// nil when the app has published nothing (yet, or for a week).
    let shelf: WidgetShelf?
}

struct NotesProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotesEntry {
        NotesEntry(date: .now, shelf: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NotesEntry) -> Void) {
        completion(NotesEntry(date: .now, shelf: WidgetNotes.published()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotesEntry>) -> Void) {
        // The app reloads this kind whenever a note changes; the timeline asks
        // again in a few hours only so a week-old shelf retires on time and
        // "2h ago" moves on.
        let now = Date.now
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now
        completion(Timeline(entries: [NotesEntry(date: now, shelf: WidgetNotes.published(now: now))],
                            policy: .after(next)))
    }
}

struct NotesWidgetView: View {
    let entry: NotesEntry

    private var rows: [WidgetShelf.Row] {
        Array((entry.shelf?.rows ?? []).prefix(WidgetNotes.rowCap))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "note.text")
                    .dsGlyph(.caption, weight: .semibold)
                    .foregroundStyle(WidgetChrome.header)
                    .widgetAccentable()
                WidgetLabel(text: String(localized: "Notes"))
            }
            if rows.isEmpty {
                Text("Write a note in Casberi")
                    .dsText(.widgetSubline12)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                ForEach(rows, id: \.id) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .dsText(.widgetTitle14)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        // Never "in 9 hr.": a note dated ahead of the clock says now.
                        Text(min(row.at, entry.date)
                            .formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                            .dsText(.widgetSubline11)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetRoomURL.make(WidgetNotes.notesRoom))
    }
}

/// `casberi://room/<room>`: the door every tile opens. A room name may hold a
/// space ("Your notes"), so the path is built, never interpolated.
enum WidgetRoomURL {
    static func make(_ room: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "casberi"
        parts.host = "room"
        parts.path = "/" + room
        return parts.url
    }
}
