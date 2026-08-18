import Foundation

/// `XPerson`'s corpus half (2026-08-18, prd §395) — the only file that reads a
/// `Thing` for it, exactly the way `XRoomSource` stands beside `XRoom`.
///
/// The split is not tidiness: it is what lets the judgement above be compiled
/// WHOLE by `scripts/x-selftest.sh` against no SwiftData at all, which is the
/// only proof these counts are right on a machine where no real archive has
/// ever been opened.
enum XPersonSource {

    static let source = "X"

    /// Every row in the corpus that involves this person, newest first.
    ///
    /// Three memberships and no fourth (see `XPerson`'s type doc): a reply of
    /// yours to them, a post of yours naming them, and a post of theirs you
    /// liked. Anything else in the room is about somebody else.
    ///
    /// `.live` at the boundary (build 177's lesson): this returns model
    /// references to a screen that holds them in `@State` across a delete-sync
    /// heal, so the guarantee is local and provable rather than a promise made
    /// to every caller.
    static func rows(_ things: [Thing], handle: String) -> [Thing] {
        let needle = normalize(handle)
        guard !needle.isEmpty else { return [] }
        return things.live
            .filter { $0.source == source && !Corpus.isImportReceipt($0) }
            .filter { kind($0, needle: needle) != nil }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    /// The card, or nil when there is not enough of a relationship to describe.
    static func compose(_ things: [Thing], handle: String,
                        calendar: Calendar = .current) -> XPerson? {
        XPerson.compose(sightings(things, handle: handle, calendar: calendar))
    }

    /// The plain values the composition runs on. Split out so a probe can dump
    /// them and the harness can feed its own.
    static func sightings(_ things: [Thing], handle: String,
                          calendar: Calendar = .current) -> [XPerson.Sighting] {
        let needle = normalize(handle)
        guard !needle.isEmpty else { return [] }
        var out: [XPerson.Sighting] = []
        for thing in things.live
        where thing.source == source && !Corpus.isImportReceipt(thing) {
            guard let kind = kind(thing, needle: needle) else { continue }
            // ONE calendar for every row, resolved here. A year read per-row
            // off a fresh `Calendar` is the same answer, but reading it in one
            // place is what makes the composition above testable against plain
            // integers rather than against dates and a time zone.
            out.append(XPerson.Sighting(
                year: calendar.component(.year, from: thing.capturedAt), kind: kind))
        }
        return out
    }

    /// How this row involves them, or nil.
    ///
    /// A REPLY is tested first and a mention only after it fails, because a
    /// reply's text opens with the handles it answers — so every reply is also
    /// textually a mention, and counting it as both would double a decade of
    /// conversation and make the headline pick the wrong word.
    static func kind(_ thing: Thing, needle: String) -> XPerson.Sighting.Kind? {
        if thing.kind == .note, let to = thing.parent?.handle,
           normalize(to) == needle { return .reply }
        // Theirs, kept by you. `authorHandle` on a liked row is stamped by
        // `XArchiveImport.fetchFaces` — so this arm is empty until that second
        // act has run, which is correct rather than something to work around
        // (the `savedAuthors` ruling one card over).
        if thing.tags.contains("Liked"), let author = thing.authorHandle,
           normalize(author) == needle { return .liked }
        // Yours, naming them. Scoped to `.note` — a LIKED post is somebody
        // else's writing, and a stranger mentioning this handle inside a post
        // you liked says nothing about you and them.
        if thing.kind == .note,
           XPerson.mentions(thing.postText ?? thing.content, handle: needle) { return .mention }
        return nil
    }

    /// One spelling, so the archive's own casing can't split a person in two.
    static func normalize(_ handle: String) -> String {
        handle.trimmingCharacters(in: CharacterSet(charactersIn: " @")).lowercased()
    }
}
