import Foundation

/// RECENTLY DELETED (prd §985) — what a deleted note of yours keeps, and for
/// how long.
///
/// Foundation-only, so `note-folders-selftest.sh` compiles it whole. The
/// store that writes these to disk is `NoteTrash`.
///
/// **An entry is the note, not a reference to it.** The model object is
/// deleted as it always was — so every surface that reads the store (search,
/// Spotlight, widgets, answers, the other devices through iCloud) forgets it
/// with no filter of its own — and the words, picture and audio wait here,
/// on this device, until they are recovered or their thirty days run out.
struct NoteTrashEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: String
    let title: String
    let content: String
    let source: String
    let createdAt: Date
    let capturedAt: Date
    let tags: [String]
    /// A locked note's mark and a voice note's player reference (§982, §971):
    /// a locked note is archived SEALED, and recovers sealed.
    let sourceRef: String?
    let folder: String?
    let pinnedAt: Date?
    let wikilinks: [String]
    let deletedAt: Date
    let hasPicture: Bool
    let hasAudio: Bool
    /// The pictures after the first were archived too (the note-pictures
    /// ruling). Optional, so an entry written before it still reads.
    var hasMorePictures: Bool? = nil
}

enum NoteTrashRules {
    /// Apple Notes' own window.
    static let keepDays = 30

    static func expiry(of deletedAt: Date) -> Date {
        deletedAt.addingTimeInterval(TimeInterval(keepDays) * 86_400)
    }

    static func isExpired(_ deletedAt: Date, now: Date) -> Bool {
        now >= expiry(of: deletedAt)
    }

    /// Whole days left, rounded UP: a note deleted a minute ago has 30, and
    /// one with an hour left still has 1 — never 0 while it can be recovered.
    static func daysLeft(_ deletedAt: Date, now: Date) -> Int {
        let seconds = expiry(of: deletedAt).timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds / 86_400).rounded(.up))
    }

    /// Newest deletion first, as the list reads.
    static func ordered(_ entries: [NoteTrashEntry]) -> [NoteTrashEntry] {
        entries.sorted { $0.deletedAt > $1.deletedAt }
    }
}
