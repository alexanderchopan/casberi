import SwiftUI
import SwiftData

/// THE NOTES ROOM'S SEARCH (prd §1099) — Reading's Search carried over
/// (§1085): a tray with the field at the bottom on glass, where the thumb is
/// (prd §752), finding through `Retriever.find`, the composer's Find engine.
///
/// It searches what the room holds: every note of yours — written, spoken
/// (its transcript), kept from a page — and everything you pinned. A locked
/// note's record holds no words (§982), so only its name can match, and the
/// row says it is locked.
///
/// Optional environment only: on Mac Catalyst a sheet's content is evaluated
/// where the presenter's `.environment` has not reached (prd §872).
struct NotesSearchSheet: View {
    /// Opens a found note on its page, or a pin in its sheet.
    var onOpen: ((Thing) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext

    @State private var query = ""
    @State private var corpus: [Thing] = []
    @State private var recents: [String] = []
    @FocusState private var fieldFocused: Bool

    private static let recentsKey = "notes.find.recents"
    private static let resultCap = 30

    var body: some View {
        DSTray(title: String(localized: "Search"), height: 640, detents: [.large]) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmed.isEmpty { before } else { results }
                }
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                DSTraySearchField(placeholder: String(localized: "Search your notes"),
                                  text: $query, focus: $fieldFocused,
                                  onSubmit: { remember(query) }) { EmptyView() }
            }
        }
        .task { load() }
        .onAppear {
            fieldFocused = true
            #if DEBUG
            // `-notesQuery "<text>"` fills the field (prd §1099): a
            // simctl-booted simulator draws no keyboard to type with.
            if let q = UserDefaults.standard.string(forKey: "notesQuery") {
                NSLog("[Casberi] notesQuery: %@", q)
                query = q
            }
            #endif
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Before you type

    @ViewBuilder private var before: some View {
        if recents.isEmpty {
            footnote(Text("Finds what you wrote, said and pinned."))
        } else {
            DSTrayHead(String(localized: "Recent"))
            ForEach(recents, id: \.self) { recent in
                Button {
                    query = recent
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: "clock.arrow.circlepath")
                            .dsGlyph(.subhead).foregroundStyle(DS.textTertiary)
                            .frame(width: DS.Face.rowCircle)
                        Text(verbatim: recent).dsText(.body17).foregroundStyle(DS.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .padding(.horizontal, DS.Space.s4)
            }
        }
    }

    private func footnote(_ text: Text) -> some View {
        DSFootnote(text)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
    }

    // MARK: - As you type

    @ViewBuilder private var results: some View {
        let hits = Array(Retriever.find(trimmed, in: corpus.live).hits.prefix(Self.resultCap))
        if hits.isEmpty {
            footnote(Text("No note matches."))
        } else {
            ForEach(hits.keyed) { row in
                if let thing = row.live { thingRow(thing) }
            }
        }
    }

    private func thingRow(_ thing: Thing) -> some View {
        let symbol = BridgeIcon.noteSymbol(for: thing)
        let line: String = if Pinboard.isNote(thing) {
            NotePreview.line(title: thing.title, content: thing.content,
                             isVoice: thing.kind == .voice, isLocked: NoteLock.isLocked(thing))
                ?? thing.capturedAt.formatted(date: .abbreviated, time: .omitted)
        } else {
            String(localized: "Pinned · \(thing.source)")
        }
        return Button {
            remember(query)
            onOpen?(thing)
        } label: {
            HStack(spacing: DS.Space.s3) {
                BridgeIcon(name: thing.source, size: DS.Face.rowCircle, circular: true, symbol: symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: thing.title).dsText(.body17)
                        .foregroundStyle(DS.textPrimary).lineLimit(1)
                    Text(verbatim: line).dsText(.subhead12)
                        .foregroundStyle(DS.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .padding(.horizontal, DS.Space.s4)
    }

    // MARK: - Reading

    /// The room's members: your notes and your pins, fetched once when the
    /// tray rises, never in a body (§628).
    private func load() {
        recents = UserDefaults.standard.data(forKey: Self.recentsKey)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let you = NoteSheetSource.keptSource
        var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == you || $0.pinnedAt != nil },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 2_000
        corpus = ((try? modelContext.fetch(d)) ?? []).filter { $0.isLive && Pinboard.inRoom($0) }
    }

    private func remember(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        recents = Array(([q] + recents.filter { $0.caseInsensitiveCompare(q) != .orderedSame }).prefix(5))
        if let data = try? JSONEncoder().encode(recents) {
            DefaultsWrite.set(data, forKey: Self.recentsKey)
        }
    }
}
