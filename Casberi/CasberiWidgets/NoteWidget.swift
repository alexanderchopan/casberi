import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

/// A NOTE ON THE HOME SCREEN (the note-widget ruling, 2026-09-29) — the
/// pinned note, or the one you pick, with its list tickable where it stands.
///
/// **Which note.** Picked in the widget's edit sheet (`NoteWidgetIntent`,
/// any written note of yours, `NoteEntity`); unpicked, the newest PINNED note
/// of yours, else the newest (`NoteAppend.featured`) — "this one on top"
/// (§969) is the note you would put on your Home Screen. A locked note is
/// never offered and never drawn (§982: the record says "Locked note" and
/// nothing else, and the Home Screen is the most stood-next-to surface there
/// is); a note locked after it was picked draws as missing.
///
/// **The tick** is `ToggleNoteItemIntent`, the note page's own one write
/// (§982), run in this extension; the tile reloads on it. Everything else on
/// the tile opens the note (`casberi://thing/<id>`).
///
/// Reads the store directly, like Today's landed rows, so a note changed
/// while the app is closed (a tick here, an Add to note from Siri) is what
/// the tile shows.
struct NoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: NoteAppend.widgetKind, intent: NoteWidgetIntent.self,
                               provider: NoteProvider()) { entry in
            NoteWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("Note")
        .description("A note of yours. Tick its list here.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// The widget's one setting: which note. Empty means the pinned one.
struct NoteWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Note"
    static let description = IntentDescription("Choose a note, or leave it empty for your pinned note.")

    @Parameter(title: "Note")
    var note: NoteEntity?
}

struct NoteEntry: TimelineEntry {
    let date: Date
    /// nil: there is no note to draw (none written, or the picked one is
    /// gone or locked).
    var id: UUID?
    var title = ""
    var lines: [NoteTask.PageLine] = []
    /// A note was picked and cannot be drawn now.
    var missing = false
}

struct NoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        NoteEntry(date: .now, id: UUID(), title: String(localized: "Groceries"),
                  lines: [.item(done: true, text: String(localized: "Milk"), ordinal: 0),
                          .item(done: false, text: String(localized: "Bread"), ordinal: 1)])
    }

    func snapshot(for configuration: NoteWidgetIntent, in context: Context) async -> NoteEntry {
        await load(configuration)
    }

    /// One entry: a note only changes when somebody writes it, and every
    /// writer reloads this kind (the tick, Add to note, the app leaving).
    func timeline(for configuration: NoteWidgetIntent, in context: Context) async -> Timeline<NoteEntry> {
        Timeline(entries: [await load(configuration)], policy: .never)
    }

    /// Values copied out at once — no model outlives this function (the
    /// liveness rule).
    @MainActor
    private func load(_ configuration: NoteWidgetIntent) -> NoteEntry {
        guard let container = try? SharedStore.extensionContainer() else {
            return NoteEntry(date: .now)
        }
        let context = ModelContext(container)
        let picked = configuration.note?.id
        guard let id = picked ?? NoteAppend.featured(in: context),
              let note = NoteAppend.note(id, in: context) else {
            return NoteEntry(date: .now, missing: picked != nil)
        }
        return NoteEntry(date: .now, id: note.id, title: note.title,
                         lines: NoteTask.page(title: note.title, content: note.content))
    }
}

struct NoteWidgetView: View {
    let entry: NoteEntry
    @Environment(\.widgetFamily) private var family

    /// How many lines each family holds under the title.
    private var capacity: Int {
        switch family {
        case .systemSmall: return 4
        case .systemLarge: return 13
        default: return 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetLabel(text: String(localized: "Note"))
            if let id = entry.id {
                Text(entry.title)
                    .dsText(.widgetTitle17)
                    .foregroundStyle(.white)
                    .lineLimit(family == .systemSmall ? 2 : 1)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(entry.lines.prefix(capacity).enumerated()), id: \.offset) { _, line in
                        row(line, note: NoteEntity(id: id, title: entry.title))
                    }
                }
                if entry.lines.count > capacity {
                    Text("\(entry.lines.count - capacity) more")
                        .dsText(.widgetSubline11)
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                Text(entry.missing ? "This note is gone or locked" : "No notes yet")
                    .dsText(.widgetTitle17)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The tile opens the note; with no note, a new one.
        .widgetURL(URL(string: entry.id.map { "casberi://thing/\($0.uuidString)" } ?? "casberi://note"))
    }

    @ViewBuilder
    private func row(_ line: NoteTask.PageLine, note: NoteEntity) -> some View {
        switch line {
        case .item(let done, let text, let ordinal):
            // The circle is the tick — Apple Notes' own mark, the one the
            // note's page draws (§982).
            Button(intent: ToggleNoteItemIntent(note: note, ordinal: ordinal)) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? WidgetChrome.accent : .white.opacity(0.7))
                        .widgetAccentable()
                    Text(text)
                        .dsText(.widgetSubline12)
                        .foregroundStyle(.white.opacity(done ? 0.5 : 0.9))
                        // As the note's page draws a done item.
                        .strikethrough(done, color: .white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(done ? "Untick \(text)" : "Tick \(text)"))
        case .words(let words):
            Text(words)
                .dsText(.widgetSubline12)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(family == .systemLarge ? 2 : 1)
        }
    }
}
