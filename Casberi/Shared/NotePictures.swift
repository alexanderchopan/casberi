import Foundation

/// A NOTE'S PICTURES (the note-pictures ruling, 2026-09-29, amending §974's
/// "one picture") — a note of yours holds up to `limit` pictures.
///
/// **The first stays where it was**, in `previewImageData`, so every surface
/// that already draws a note's picture — the room's row, the lede's cover,
/// the page's well, the Recently deleted row — draws the first with nothing
/// new. The REST ride `Thing.notePictures`, one field, as this codec's binary
/// property list of JPEG bytes, each already at the app's one stored size
/// (`ImportMedia.thumbnail`, 480pt / q0.7), so the field stays small.
///
/// Foundation-only, in `Shared/`: `note-checklist-selftest.sh` compiles it.
enum NotePictures {

    /// How many pictures one note holds, the first included. Apple Notes has
    /// no cap; a synced record does (CloudKit's asset per field, and a note
    /// is a note, not an album).
    static let limit = 6

    /// The pictures after the first, as the field stores them; nil for none.
    static func encode(_ rest: [Data]) -> Data? {
        let kept = Array(rest.prefix(limit - 1))
        guard !kept.isEmpty else { return nil }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try? encoder.encode(kept)
    }

    /// The field read back; a field that does not decode is no pictures,
    /// never a crash.
    static func decode(_ stored: Data?) -> [Data] {
        guard let stored,
              let rest = try? PropertyListDecoder().decode([Data].self, from: stored) else { return [] }
        return Array(rest.prefix(limit - 1))
    }

    /// Every picture on a note, first first.
    static func all(first: Data?, rest: Data?) -> [Data] {
        (first.map { [$0] } ?? []) + decode(rest)
    }

    /// How many more a note with `count` can take.
    static func room(after count: Int) -> Int { max(0, limit - count) }
}
