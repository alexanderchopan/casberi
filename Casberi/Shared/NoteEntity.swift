import AppIntents
import SwiftData
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// A NOTE OF YOURS, as Siri, Shortcuts and the widget name it (the
/// add-to-note and note-widget rulings, 2026-09-29) — the place words go in
/// Add to note, and the note a Note widget shows.
///
/// Only the notes `NoteAppend.takesWords` allows: written notes of yours,
/// never a voice note, never a locked one. A locked note's record holds
/// "Locked note" and nothing else (§982), so it is offered nowhere outside
/// the app — not even by title.
///
/// In `Shared/` because the app (Add to note) and the widget (its note, its
/// tick) both name notes, and an entity type the two disagree on would be a
/// widget configured with a note Siri cannot find.
struct NoteEntity: AppEntity {
    let id: UUID
    let title: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
    static var defaultQuery = NoteEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: "note.text"))
    }

    init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }

    init(_ choice: NoteAppend.Choice) {
        self.init(id: choice.id, title: choice.title)
    }
}

/// Your notes, newest first — what a parameter's picker lists, and what a
/// spoken name is matched against.
struct NoteEntityQuery: EntityStringQuery {
    @MainActor
    private func choices() throws -> [NoteAppend.Choice] {
        let context = ModelContext(try SharedStore.extensionContainer())
        return NoteAppend.notes(in: context)
    }

    @MainActor
    func entities(for identifiers: [NoteEntity.ID]) async throws -> [NoteEntity] {
        let ids = Set(identifiers)
        return try choices().filter { ids.contains($0.id) }.map(NoteEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [NoteEntity] {
        let q = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = try choices()
        guard !q.isEmpty else { return all.map(NoteEntity.init) }
        return all.filter { $0.title.localizedStandardContains(q) }.map(NoteEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [NoteEntity] {
        try choices().map(NoteEntity.init)
    }
}

/// TICK AN ITEM on the Note widget (the note-widget ruling) — the same one
/// write the note's page makes (`NoteTask.toggled`, §982's rule that a tick
/// is the state of the list, not an edit of the words), run where the widget
/// runs, without opening the app.
struct ToggleNoteItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick a note item"
    static let description = IntentDescription("Ticks or unticks an item on a note's checklist.")
    static let isDiscoverable = false

    @Parameter(title: "Note") var note: NoteEntity
    @Parameter(title: "Item") var ordinal: Int

    init() {}

    init(note: NoteEntity, ordinal: Int) {
        self.note = note
        self.ordinal = ordinal
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = ModelContext(try SharedStore.extensionContainer())
        try NoteAppend.toggle(item: ordinal, in: note.id, context: context)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: NoteAppend.widgetKind)
        #endif
        return .result()
    }
}

extension NoteAppend {
    /// The Note widget's kind, spelled once for the widget and every reload.
    static let widgetKind = "casberi.note.page"
}
