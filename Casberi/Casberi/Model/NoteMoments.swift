import Foundation
import SwiftData

/// Delight for the Notes group (2026-07-28) — the sibling of
/// `SocialMoments`/`FeedFollowMoments` for a source with no watched-account
/// roster and no feed to go quiet on. Scoped to Obsidian only: Day One and
/// Apple Journal are one-time imports of possibly years-old entries (their
/// `capturedAt` is the entry's OWN write date, not "just landed"), so the
/// `freshWindow` gate below excludes them naturally rather than by a special
/// case — an entry imported today but written in 2019 can never be "fresh".
/// (Apple Notes is excluded on purpose too — see the note on
/// `NotesShareScreen`: a shared-in note lands with `source == "You"` like any
/// other capture, so nothing here would ever match it.) Every check is a
/// read-only pass over what's already landed, touching nothing the ingest
/// above wrote.
@MainActor
enum NoteMoments {
    /// A thing older than this when a pass runs is a re-scan, not a fresh
    /// arrival — same self-throttle every moment in this app relies on.
    private static let freshWindow: TimeInterval = 600
    /// A linked note untouched this long reads as "rediscovered", not "just
    /// written" — the reach-back a wikilink can uniquely prove.
    private static let staleDays: Double = 180
    /// A corpus floor pushed back by less than this isn't a new fact worth a
    /// moment — a re-import landing a handful of slightly-older stragglers
    /// shouldn't fire every time.
    private static let floorDays: Double = 30

    // MARK: - The crossing: a fresh note naming a link you already saved

    /// Mirrors `SocialMoments.checkSlackCrossings`/
    /// `FeedFollowMoments.checkRedditLinkCrossings` exactly: a note's own
    /// body already carries a URL — `content` IS the note's text for
    /// Obsidian, so this is a pure corpus join, no re-parse of the file.
    /// NEWS ONLY: only a note landed within `freshWindow` is checked, so a
    /// re-sync of an unchanged vault can't refire it.
    static func checkLinkCrossings(context: ModelContext) {
        let source = "Obsidian"
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == source })
        guard let notes = try? context.fetch(descriptor) else { return }
        let fresh = notes.filter { $0.capturedAt.timeIntervalSinceNow > -freshWindow }
        guard !fresh.isEmpty else { return }

        let othersDescriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source != source })
        guard let others = try? context.fetch(othersDescriptor) else { return }
        var savedByURL: [String: Thing] = [:]
        for candidate in others {
            guard let key = normalizedURL(candidate.content) else { continue }
            savedByURL[key] = candidate
        }
        guard !savedByURL.isEmpty else { return }

        for note in fresh {
            guard let url = Capture.detectURL(in: note.content),
                  let key = normalizedURL(url.absoluteString),
                  let saved = savedByURL[key],
                  saved.capturedAt < note.capturedAt else { continue }
            SourceMoments.shared.fire(
                String(localized: "\u{201c}\(note.title)\u{201d} links \u{201c}\(saved.title)\u{201d} — you already saved it"),
                source: source)
        }
    }

    // MARK: - The reach-back: a wikilink into a note gone quiet

    /// The reach only a vault's OWN graph can show: a freshly modified note
    /// links to another note that's sat untouched for `staleDays` — a real
    /// structural fact from `Thing.wikilinks`, never invented. Self-throttled
    /// the same way every moment here is: only the fresh note's own newest
    /// write is checked, so a re-sync can't refire the same pairing.
    static func checkWikilinkReachBack(context: ModelContext) {
        let source = "Obsidian"
        let descriptor = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { $0.source == source })
        guard let notes = try? context.fetch(descriptor) else { return }
        let fresh = notes.filter { $0.capturedAt.timeIntervalSinceNow > -freshWindow && !$0.wikilinks.isEmpty }
        guard !fresh.isEmpty else { return }
        var byTitle: [String: Thing] = [:]
        for note in notes { byTitle[note.title.lowercased()] = note }

        for note in fresh {
            for target in note.wikilinks {
                guard let match = byTitle[target.lowercased()], match.id != note.id else { continue }
                let ageDays = match.capturedAt.timeIntervalSinceNow / -86400
                guard ageDays >= staleDays else { continue }
                SourceMoments.shared.fire(
                    String(localized: "\u{201c}\(note.title)\u{201d} reaches back to \u{201c}\(match.title)\u{201d}, untouched for \(Int(ageDays)) days"),
                    source: source)
                break   // one moment per fresh note, even if it links several stale ones
            }
        }
    }

    // MARK: - The floor: an import pushing the corpus further back than ever

    /// The corpus-wide oldest `capturedAt` — read BEFORE an import inserts
    /// anything, so the caller has an honest "before" to compare its
    /// landed batch's earliest date against.
    static func corpusFloor(_ context: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<Thing>(sortBy: [SortDescriptor(\.capturedAt, order: .forward)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.capturedAt
    }

    /// An import that reaches further into the past than the corpus has ever
    /// gone — the one honest, un-tally-able fact a Day One/Apple Journal
    /// import can produce (a tally like "imported 480 entries" is exactly
    /// what the module doctrine bans). Fires only when the new floor is
    /// meaningfully earlier (`floorDays`) than the one `priorFloor` recorded
    /// — a re-import of an unchanged export lands nothing (`landed` empty,
    /// caller never calls in), and a handful of slightly-older stragglers
    /// isn't a new fact worth a moment.
    static func checkFloorPushedBack(priorFloor: Date?, landed: [Thing], source: String) {
        guard let newFloor = landed.map(\.capturedAt).min() else { return }
        if let priorFloor {
            guard priorFloor.timeIntervalSince(newFloor) > floorDays * 86400 else { return }
        }
        let named = newFloor.formatted(.dateTime.month(.wide).year())
        SourceMoments.shared.fire(
            String(localized: "Casberi now remembers back to \(named)"),
            source: source)
    }

    /// Loose equality for a link across sources — same rule as
    /// `SocialMoments.normalizedURL`/`FeedFollowMoments.normalizedURL`
    /// (strips scheme, a leading "www.", a trailing slash). Duplicated
    /// rather than shared, matching this app's existing moments files, each
    /// deliberately independent of the others.
    private static func normalizedURL(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        for prefix in ["https://www.", "http://www.", "https://", "http://"] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? nil : s.lowercased()
    }
}
