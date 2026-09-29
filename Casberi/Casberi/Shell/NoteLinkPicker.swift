import SwiftUI
import SwiftData

/// LINK SOMETHING YOU KEPT into a note (prd §982) — Apple Notes' `>>` note
/// link, pointed at everything in the corpus instead of at other notes.
///
/// It writes `[[Exact title]]` into the draft: readable in the field and in a
/// note shared out, the vault's own syntax (so Obsidian reads it too), and
/// resolved at open time against what you keep (`NoteLinks.resolveKept`),
/// never stored as a reference that could outlive its target. The kept note
/// records the titles in `wikilinks`, so the thing it names shows the note
/// under "Points at this".
///
/// Bounded: the newest `window` things, filtered in Swift by title — the same
/// ceiling "points at this" reads with, so a search never walks the corpus on
/// the main actor. An empty field lists the newest, which is usually what a
/// note written now is about.
struct NoteLinkPicker: View {
    let onPick: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var pool: [Row] = []
    @FocusState private var focused: Bool

    static let window = 2000
    static let shown = 30

    /// Values, never `Thing`s (the liveness rule): the picker only needs a
    /// title to write and a source to draw.
    struct Row: Identifiable, Equatable {
        let id: UUID
        let title: String
        let source: String
    }

    private var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let hits = q.isEmpty ? pool : pool.filter { $0.title.localizedStandardContains(q) }
        return Array(hits.prefix(Self.shown))
    }

    var body: some View {
        DSTray(title: String(localized: "Link something"), height: 560,
               detents: [.height(560), .large]) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                DSSlabField(placeholder: String(localized: "Search"),
                            text: $query, actionLabel: "",
                            focus: $focused,
                            glyph: "magnifyingglass", clearable: true,
                            size: .slab, submitLabel: .search, action: {})
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            Button {
                                DSHaptic.tap()
                                onPick(row.title)
                                dismiss()
                            } label: {
                                HStack(spacing: DS.Space.s3) {
                                    BridgeIcon(name: row.source, size: DS.Face.row, circular: true)
                                    Text(row.title)
                                        .dsText(.body17)
                                        .foregroundStyle(DS.textPrimary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPress())
                            .dsHover()
                        }
                        if rows.isEmpty && !pool.isEmpty {
                            DSFootnote(Text("Nothing you keep is called that"))
                                .padding(.top, DS.Space.s3)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear {
            var descriptor = FetchDescriptor<Thing>(
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            descriptor.fetchLimit = Self.window
            descriptor.propertiesToFetch = [\.title, \.source, \.capturedAt]
            let things = (try? modelContext.fetch(descriptor)) ?? []
            var seen = Set<String>()
            pool = things.compactMap { thing in
                guard thing.isLive, !NoteLock.isLocked(thing) else { return nil }
                let title = thing.title.trimmingCharacters(in: .whitespacesAndNewlines)
                // A title with a bracket cannot sit inside `[[…]]`, and the
                // same title twice is one link.
                guard title.count >= 2, !title.contains("]"), !title.contains("["),
                      seen.insert(title.lowercased()).inserted else { return nil }
                return Row(id: thing.id, title: title, source: thing.source)
            }
        }
    }
}
