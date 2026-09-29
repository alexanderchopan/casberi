import Foundation
import SwiftData

/// ADD TO NOTE (the add-to-note ruling, 2026-09-29) — words written into a
/// note you already have, from outside the note: Siri and Shortcuts
/// (`AddToNoteIntent`), the share sheet (`ShareExtension`) and the widget's
/// tick (`ToggleNoteItemIntent`).
///
/// **Which notes.** A WRITTEN note of yours (`source == "You"`, `.note`),
/// never a voice note (it is its audio, §972), never a locked one — its
/// record holds nothing but "Locked note" (§982), and writing beside a sealed
/// box would put words where no screen may show them, or lose them on Remove
/// lock. Newest first, the order the Notes room keeps.
///
/// **How.** `NoteTask.appended`: a note ending in a list takes each line as
/// the next item, any other note takes the words on a new line. The note's
/// day, folder, pin and id stay, as §981's edit keeps them.
///
/// In `Shared/` because the share extension and the widget write here too.
/// The app re-derives what it derives from the words (Spotlight, links) the
/// next time the note is saved in it; an extension has no index to write.
enum NoteAppend {

    /// A note offered as a place to add to — values, never a `Thing` held
    /// across a context (the liveness rule).
    struct Choice: Identifiable, Hashable, Sendable {
        let id: UUID
        let title: String
        let capturedAt: Date
    }

    /// The `sourceRef` a locked note carries — `NoteLock.refMark`, spelled
    /// here for the targets that do not compile `NoteLock`.
    /// `note-checklist-selftest.sh` holds the two equal.
    static let lockedRef = "notelock:v1"
    static let keptSource = "You"

    /// Whether words can be added to this thing.
    static func takesWords(_ thing: Thing) -> Bool {
        thing.source == keptSource && thing.kind == .note && thing.sourceRef != lockedRef
    }

    /// The notes words can be added to, newest first, at most `limit`.
    static func notes(in context: ModelContext, limit: Int = 60) -> [Choice] {
        let source = keptSource
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == source },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        // A kind cannot be predicated; your own captures are a handful, so
        // the rest is filtered here, over a bounded read.
        descriptor.fetchLimit = limit * 4
        let found = (try? context.fetch(descriptor)) ?? []
        return found
            .filter { !$0.isDeleted && takesWords($0) }
            .prefix(limit)
            .map { Choice(id: $0.id, title: $0.title, capturedAt: $0.capturedAt) }
    }

    /// The note a Note widget shows before one is picked: the newest PINNED
    /// note of yours — "this one on top" (§969) — else the newest.
    static func featured(in context: ModelContext) -> UUID? {
        let source = keptSource
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == source },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 240
        let notes = ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted && takesWords($0) }
        let pinned = notes.filter { $0.pinnedAt != nil }
            .max { ($0.pinnedAt ?? .distantPast) < ($1.pinnedAt ?? .distantPast) }
        return (pinned ?? notes.first)?.id
    }

    /// The note with this id, if words can still be added to it.
    static func note(_ id: UUID, in context: ModelContext) -> Thing? {
        var descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.id == id })
        descriptor.fetchLimit = 1
        guard let found = (try? context.fetch(descriptor))?.first,
              !found.isDeleted, takesWords(found) else { return nil }
        return found
    }

    /// Add `text` to the note and save. Nil when the note is gone, locked
    /// since, or there was nothing to add.
    @discardableResult
    static func append(_ text: String, to id: UUID, in context: ModelContext) throws -> Thing? {
        guard let note = note(id, in: context) else { return nil }
        let next = NoteTask.appended(note.content, text)
        guard next != note.content else { return nil }
        note.content = next
        try context.save()
        return note
    }

    /// Tick or untick the note's `ordinal`-th item and save (the widget's
    /// tick). Nil when the note is gone or locked.
    @discardableResult
    static func toggle(item ordinal: Int, in id: UUID, context: ModelContext) throws -> Thing? {
        guard let note = note(id, in: context) else { return nil }
        let next = NoteTask.toggled(note.content, ordinal: ordinal)
        guard next != note.content else { return nil }
        note.content = next
        try context.save()
        return note
    }
}
