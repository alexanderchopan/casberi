import Foundation
import Observation
import SwiftData

/// Recently Deleted's archive on disk (prd §985). `NoteTrashRules` owns the
/// window; this owns the files.
///
/// **This device only, deliberately.** The delete still reaches every device
/// through iCloud, and the archive stays where the delete was made: a synced
/// tombstone would need every read in the app — search, Spotlight, widgets,
/// answers — to filter it, and a new CloudKit field shipped to Production.
/// The tray says so ("on this iPhone").
///
/// One folder, `Application Support/RecentlyDeleted`, three files a note:
/// `<id>.json` (the entry), `<id>.picture` and `<id>.audio` when it had them,
/// so listing the tray never reads a voice note's megabytes.
@Observable
@MainActor
final class NoteTrash {
    static let shared = NoteTrash()

    /// Newest deletion first.
    private(set) var entries: [NoteTrashEntry] = []

    private let folder: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("RecentlyDeleted", isDirectory: true)

    private init() {
        load()
        purgeExpired()
    }

    // MARK: - Writes

    /// Archive a note of yours before its model is deleted. False when it
    /// could not be written — the caller then keeps the note rather than
    /// promise a recovery the disk cannot make.
    func keep(_ thing: Thing) -> Bool {
        guard let folder, thing.isLive else { return false }
        let picture = thing.previewImageData
        let audio = thing.audio
        let entry = NoteTrashEntry(
            id: thing.id, kind: thing.kind.rawValue, title: thing.title,
            content: thing.content, source: thing.source,
            createdAt: thing.createdAt, capturedAt: thing.capturedAt,
            tags: thing.tags, sourceRef: thing.sourceRef, folder: thing.folder,
            pinnedAt: thing.pinnedAt, wikilinks: thing.wikilinks,
            deletedAt: .now, hasPicture: picture != nil, hasAudio: audio != nil)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let picture { try picture.write(to: file(entry.id, "picture"), options: Self.writing) }
            if let audio { try audio.write(to: file(entry.id, "audio"), options: Self.writing) }
            try JSONEncoder().encode(entry).write(to: file(entry.id, "json"), options: Self.writing)
        } catch {
            removeFiles(entry.id)
            return false
        }
        entries = NoteTrashRules.ordered(entries.filter { $0.id != entry.id } + [entry])
        return true
    }

    /// Put a note back where it was: its words, picture, audio, folder, pin,
    /// tags and day, under its own id. A locked note comes back locked.
    @discardableResult
    func recover(_ entry: NoteTrashEntry, into context: ModelContext) -> Thing? {
        guard entries.contains(where: { $0.id == entry.id }) else { return nil }
        let picture = entry.hasPicture ? try? Data(contentsOf: file(entry.id, "picture")) : nil
        let audio = entry.hasAudio ? try? Data(contentsOf: file(entry.id, "audio")) : nil
        // A voice note is its audio, and a locked note its sealed box (§982):
        // with the bytes gone there is nothing to put back.
        if entry.hasAudio && audio == nil { return nil }
        let thing = Thing(id: entry.id, kind: ThingKind(rawValue: entry.kind) ?? .note,
                          title: entry.title, content: entry.content, source: entry.source,
                          createdAt: entry.createdAt, capturedAt: entry.capturedAt,
                          sourceRef: entry.sourceRef)
        thing.tags = entry.tags
        thing.folder = entry.folder
        thing.pinnedAt = entry.pinnedAt
        thing.wikilinks = entry.wikilinks
        thing.previewImageData = picture
        thing.audio = audio
        context.insert(thing)
        context.saveHonestly()
        SpotlightIndex.index([thing])
        erase(entry)
        return thing
    }

    /// Delete now: the files go and nothing can bring the note back.
    func erase(_ entry: NoteTrashEntry) {
        removeFiles(entry.id)
        entries.removeAll { $0.id == entry.id }
    }

    /// Delete everything (the Data tray's): the archive goes with the store.
    func eraseAll() {
        if let folder { try? FileManager.default.removeItem(at: folder) }
        entries = []
    }

    /// Anything past its thirty days leaves for good. Run at launch and when
    /// the tray opens.
    func purgeExpired(now: Date = .now) {
        for entry in entries where NoteTrashRules.isExpired(entry.deletedAt, now: now) {
            erase(entry)
        }
    }

    // MARK: - Disk

    #if os(iOS)
    private static let writing: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    #else
    private static let writing: Data.WritingOptions = [.atomic]
    #endif

    private func file(_ id: UUID, _ ext: String) -> URL {
        (folder ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("\(id.uuidString).\(ext)")
    }

    private func removeFiles(_ id: UUID) {
        for ext in ["json", "picture", "audio"] {
            try? FileManager.default.removeItem(at: file(id, ext))
        }
    }

    private func load() {
        guard let folder,
              let names = try? FileManager.default.contentsOfDirectory(
                  at: folder, includingPropertiesForKeys: nil)
        else { return }
        let decoder = JSONDecoder()
        entries = NoteTrashRules.ordered(names.filter { $0.pathExtension == "json" }.compactMap {
            (try? Data(contentsOf: $0)).flatMap { try? decoder.decode(NoteTrashEntry.self, from: $0) }
        })
    }
}
