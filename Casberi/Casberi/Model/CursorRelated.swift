import Foundation
import SwiftData

/// The other agent runs on the SAME repository (2026-08-08, prd §335).
///
/// A cloud agent run arrives alone: one row, one summary, one PR. But nobody
/// launches one agent — they launch six against the same repo over a week, and
/// the question a finished run raises ("what else has been touched here?") had
/// no answer anywhere in the app. The room groups by day; the sheet showed the
/// run and stopped.
///
/// **The join is EXACT and it has to be.** `authorHandle` carries the repository
/// label the bridge landed (`"org/repo"`), and this matches it by string
/// equality — never a topical guess, never a fuzzy prefix, never an embedding
/// neighbour. That is the `CrossSourceEcho` grade, and the reason is §83: this
/// section makes a CLAIM about two rows being about the same codebase. An exact
/// match is a fact. A near match is a guess wearing a fact's clothes, and on a
/// screen where the next tap is "read what this agent changed", a guess sends
/// somebody to the wrong repository.
///
/// Nothing here is stored, fetched over the network, or cached: the rows are
/// already in the corpus, and this is one scoped fetch on sheet open — the same
/// bar `NoteLinks.backlinks` and `CrossSourceEcho.find` are held to.
enum CursorRelated {

    /// How many siblings a sheet shows. Small on purpose: this is context under
    /// a thing, not a room — a list long enough to scroll is the feed, and the
    /// feed already exists one tap away.
    static let cap = 6

    /// How deep the fetch reaches before ranking. The bridge lands the newest
    /// 30 runs per pass and the corpus accumulates, so this is generous enough
    /// that a busy repo's older runs are still reachable while staying a
    /// bounded read on the main actor.
    private static let window = 300

    /// Other Cursor runs on this run's repository, newest first, capped.
    ///
    /// Empty for anything that isn't a Cursor row, for a row whose repository
    /// the bridge never learned (`repoLabel` answers nil for a source block
    /// with no `repository`), and for the very common case of a repo you have
    /// run exactly one agent against. All three are the same honest nothing —
    /// the caller renders no section rather than an empty one.
    @MainActor
    static func siblings(of run: Thing, context: ModelContext) -> [Thing] {
        guard run.isLive, run.source == "Cursor" else { return [] }
        guard let repo = run.authorHandle?
            .trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty else { return [] }
        let runID = run.id
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == "Cursor" },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = window
        guard let rows = try? context.fetch(descriptor) else { return [] }
        var out: [Thing] = []
        // `where candidate.isLive` before any stored-property read: a fetch is
        // a snapshot, and a bridge heal deleting a row in the same graph update
        // is exactly the liveness class this codebase has paid for six times
        // (see `ThingRowKeying.swift`).
        for candidate in rows where candidate.isLive && candidate.id != runID {
            guard candidate.authorHandle?
                .trimmingCharacters(in: .whitespacesAndNewlines) == repo else { continue }
            out.append(candidate)
            if out.count == cap { break }
        }
        return out
    }
}
